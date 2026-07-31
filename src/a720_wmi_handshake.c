// SPDX-License-Identifier: GPL-2.0-only
/*
 * Lenovo IdeaCentre A720 bezel-button WMI handshake driver.
 *
 * Reproduces the volume-control protocol used by Lenovo's original Windows
 * OSD utility. Event 0x16 requests a volume synchronization packet. Event
 * 0x17 announces a requested absolute volume that is read from WMI data block
 * instance 0 and exported through read-only module parameters for userspace.
 */

#include <linux/acpi.h>
#include <linux/atomic.h>
#include <linux/dmi.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/sysfs.h>
#include <linux/types.h>
#include <linux/wmi.h>
#include <linux/workqueue.h>

#define A720_EVENT_GUID "ABBC0F20-8EA1-11D1-00A0-C90629100000"
#define A720_IO_GUID    "ABBC0F40-8EA1-11D1-00A0-C90629100000"
#define A720_PACKET_SIZE 0x40
#define A720_MAX_RESPONSE 256

static const u8 a720_init_packet[A720_PACKET_SIZE] = {
	0x01, 0x10, 0x02,
};

static const u8 a720_volume_query_packet[A720_PACKET_SIZE] = {
	0x01, 0x10, 0x04, 0x02, 0x03, 0xa7,
};

enum a720_wmi_kind {
	A720_WMI_EVENT,
	A720_WMI_IO,
};

struct a720_state {
	/* Serializes channel lifecycle and every firmware transaction. */
	struct mutex io_lock;
	struct mutex request_lock;
	struct wmi_device *io_wdev;
	bool event_bound;
	bool initialized;
	struct workqueue_struct *wq;
	struct work_struct volume_query_work;
	struct work_struct volume_sync_work;
	atomic_t pending_volume_queries;
	atomic_t pending_volume_syncs;
	atomic64_t event_sequence;
	atomic64_t query_sequence;
};

static struct a720_state a720 = {
	.io_lock = __MUTEX_INITIALIZER(a720.io_lock),
	.request_lock = __MUTEX_INITIALIZER(a720.request_lock),
	.pending_volume_queries = ATOMIC_INIT(0),
	.pending_volume_syncs = ATOMIC_INIT(0),
	.event_sequence = ATOMIC64_INIT(0),
	.query_sequence = ATOMIC64_INIT(0),
};

static const enum a720_wmi_kind a720_event_kind = A720_WMI_EVENT;
static const enum a720_wmi_kind a720_io_kind = A720_WMI_IO;

static const struct dmi_system_id a720_dmi_table[] = {
	{
		.ident = "Lenovo IdeaCentre A720 type 2564",
		.matches = {
			DMI_EXACT_MATCH(DMI_SYS_VENDOR, "LENOVO"),
			DMI_EXACT_MATCH(DMI_PRODUCT_NAME, "2564"),
			DMI_MATCH(DMI_PRODUCT_VERSION, "IdeaCentre A720"),
		},
	},
	{ }
};
MODULE_DEVICE_TABLE(dmi, a720_dmi_table);

static bool initialize = true;
module_param(initialize, bool, 0444);
MODULE_PARM_DESC(initialize,
	"Send ICMD 0x02 (WINI/APRC++) when the IO GUID binds (default: true)");

static int sync_volume = 50;

static int a720_set_sync_volume(const char *value,
				const struct kernel_param *kp)
{
	int volume;
	int ret;

	ret = kstrtoint(value, 0, &volume);
	if (ret)
		return ret;
	if (volume < 0 || volume > 100)
		return -ERANGE;

	WRITE_ONCE(*(int *)kp->arg, volume);
	return 0;
}

static const struct kernel_param_ops a720_sync_volume_ops = {
	.set = a720_set_sync_volume,
	.get = param_get_int,
};

module_param_cb(sync_volume, &a720_sync_volume_ops, &sync_volume, 0640);
MODULE_PARM_DESC(sync_volume,
	"Volume percentage sent to Lenovo firmware on event 0x16 (0..100, default: 50)");

static bool dump_response;
module_param(dump_response, bool, 0640);
MODULE_PARM_DESC(dump_response,
	"Hex-dump each vendor query response (default: false)");

/* Userspace bridge reads these without requiring journal access. */
static int requested_volume = -1;
static unsigned int request_seq;

static int a720_get_requested_volume(char *buffer,
				     const struct kernel_param *kp)
{
	int volume;

	mutex_lock(&a720.request_lock);
	volume = requested_volume;
	mutex_unlock(&a720.request_lock);

	return sysfs_emit(buffer, "%d\n", volume);
}

static const struct kernel_param_ops a720_requested_volume_ops = {
	.get = a720_get_requested_volume,
};

module_param_cb(requested_volume, &a720_requested_volume_ops, NULL, 0444);
MODULE_PARM_DESC(requested_volume,
	"Most recent Lenovo-requested absolute volume, or -1 before first request");

static int a720_get_request_seq(char *buffer, const struct kernel_param *kp)
{
	unsigned int sequence;

	mutex_lock(&a720.request_lock);
	sequence = request_seq;
	mutex_unlock(&a720.request_lock);

	return sysfs_emit(buffer, "%u\n", sequence);
}

static const struct kernel_param_ops a720_request_seq_ops = {
	.get = a720_get_request_seq,
};

module_param_cb(request_seq, &a720_request_seq_ops, NULL, 0444);
MODULE_PARM_DESC(request_seq,
	"Sequence incremented after each valid requested-volume response");

static int a720_get_request(char *buffer, const struct kernel_param *kp)
{
	unsigned int sequence;
	int volume;

	mutex_lock(&a720.request_lock);
	sequence = request_seq;
	volume = requested_volume;
	mutex_unlock(&a720.request_lock);

	return sysfs_emit(buffer, "%u %d\n", sequence, volume);
}

static const struct kernel_param_ops a720_request_ops = {
	.get = a720_get_request,
};

module_param_cb(request, &a720_request_ops, NULL, 0444);
MODULE_PARM_DESC(request,
	"Atomic request snapshot formatted as: sequence volume");

static int a720_send_initialization(struct wmi_device *wdev)
{
	struct acpi_buffer in = {
		.length = sizeof(a720_init_packet),
		.pointer = (void *)a720_init_packet,
	};
	acpi_status status;

	if (!READ_ONCE(initialize)) {
		dev_dbg(&wdev->dev, "initialization disabled by module parameter\n");
		return 0;
	}

	status = wmidev_block_set(wdev, 0, &in);
	if (ACPI_FAILURE(status)) {
		dev_err(&wdev->dev, "initialization failed: %s\n",
			acpi_format_exception(status));
		return -EIO;
	}

	dev_dbg(&wdev->dev, "initialization command sent\n");
	return 0;
}

/* Caller holds a720.io_lock. */
static int a720_maybe_initialize(void)
{
	int ret;

	if (!a720.event_bound || !a720.io_wdev || a720.initialized)
		return 0;

	ret = a720_send_initialization(a720.io_wdev);
	if (!ret)
		a720.initialized = true;

	return ret;
}

static void a720_dump_buffer(struct device *dev, const u8 *data, u32 length,
			     u64 query_number)
{
	u32 offset;
	u32 shown = min_t(u32, length, A720_MAX_RESPONSE);

	for (offset = 0; offset < shown; offset += 16) {
		u32 chunk = min_t(u32, 16, shown - offset);

		dev_info(dev, "QUERY #%llu %04x: %*phN\n",
			 (unsigned long long)query_number, offset,
			 (int)chunk, data + offset);
	}

	if (length > A720_MAX_RESPONSE)
		dev_info(dev, "QUERY #%llu response truncated from %u to %u bytes\n",
			 (unsigned long long)query_number, length,
			 A720_MAX_RESPONSE);
}

static void a720_run_volume_sync(struct work_struct *work)
{
	struct wmi_device *io_wdev;
	struct acpi_buffer in;
	u8 packet[A720_PACKET_SIZE] = {
		0x01, 0x10, 0x05, 0x03, 0x03, 0xa8, 0x00,
	};
	acpi_status status;
	int requests;
	int volume;

	requests = atomic_xchg(&a720.pending_volume_syncs, 0);
	volume = READ_ONCE(sync_volume);
	packet[6] = (u8)volume;

	mutex_lock(&a720.io_lock);
	io_wdev = a720.io_wdev;
	if (!io_wdev || !a720.initialized) {
		mutex_unlock(&a720.io_lock);
		pr_debug_ratelimited("a720-wmi-handshake: sync skipped without IO channel\n");
		return;
	}

	in.length = sizeof(packet);
	in.pointer = packet;
	status = wmidev_block_set(io_wdev, 0, &in);
	if (ACPI_FAILURE(status))
		dev_err_ratelimited(&io_wdev->dev,
			"volume synchronization failed: %s\n",
			acpi_format_exception(status));
	else
		dev_dbg(&io_wdev->dev,
			"synchronized volume=%d after %d notification(s)\n",
			volume, requests);

	mutex_unlock(&a720.io_lock);
}

static void a720_run_volume_query(struct work_struct *work)
{
	struct wmi_device *io_wdev;
	struct acpi_buffer in = {
		.length = sizeof(a720_volume_query_packet),
		.pointer = (void *)a720_volume_query_packet,
	};
	union acpi_object *response;
	acpi_status status;
	u64 query_number;
	int requests;

	requests = atomic_xchg(&a720.pending_volume_queries, 0);
	query_number = atomic64_inc_return(&a720.query_sequence);

	mutex_lock(&a720.io_lock);
	io_wdev = a720.io_wdev;
	if (!io_wdev || !a720.initialized) {
		mutex_unlock(&a720.io_lock);
		pr_debug_ratelimited("a720-wmi-handshake: query skipped without IO channel\n");
		return;
	}

	status = wmidev_block_set(io_wdev, 0, &in);
	if (ACPI_FAILURE(status)) {
		dev_err_ratelimited(&io_wdev->dev,
			"QUERY #%llu command failed: %s\n",
			(unsigned long long)query_number,
			acpi_format_exception(status));
		goto out_unlock;
	}

	response = wmidev_block_query(io_wdev, 0);
	if (!response) {
		dev_err_ratelimited(&io_wdev->dev,
			"QUERY #%llu returned no ACPI object\n",
			(unsigned long long)query_number);
		goto out_unlock;
	}

	if (response->type != ACPI_TYPE_BUFFER) {
		dev_err_ratelimited(&io_wdev->dev,
			"QUERY #%llu returned ACPI object type=%u\n",
			(unsigned long long)query_number, response->type);
		goto out_free;
	}

	if (response->buffer.length <= 5 || !response->buffer.pointer) {
		dev_warn_ratelimited(&io_wdev->dev,
			"QUERY #%llu response cannot provide byte 5\n",
			(unsigned long long)query_number);
		goto out_dump;
	}

	if (response->buffer.pointer[5] <= 100) {
		u8 volume = response->buffer.pointer[5];

		mutex_lock(&a720.request_lock);
		requested_volume = (int)volume;
		request_seq++;
		mutex_unlock(&a720.request_lock);
		dev_dbg(&io_wdev->dev,
			"QUERY #%llu volume=%u after %d notification(s)\n",
			(unsigned long long)query_number, volume, requests);
	} else {
		dev_warn_ratelimited(&io_wdev->dev,
			"QUERY #%llu returned invalid volume=%u\n",
			(unsigned long long)query_number,
			response->buffer.pointer[5]);
	}

out_dump:
	if (READ_ONCE(dump_response) && response->buffer.pointer &&
	    response->buffer.length)
		a720_dump_buffer(&io_wdev->dev, response->buffer.pointer,
				 response->buffer.length, query_number);
out_free:
	kfree(response);
out_unlock:
	mutex_unlock(&a720.io_lock);
}

static int a720_wmi_probe(struct wmi_device *wdev, const void *context)
{
	const enum a720_wmi_kind *kind = context;
	int ret = 0;

	if (!kind)
		return -EINVAL;

	dev_set_drvdata(&wdev->dev, (void *)kind);
	mutex_lock(&a720.io_lock);

	if (*kind == A720_WMI_EVENT) {
		if (a720.event_bound) {
			ret = -EBUSY;
			goto out_unlock;
		}

		a720.event_bound = true;
		ret = a720_maybe_initialize();
		if (ret)
			a720.event_bound = false;
		goto out_unlock;
	}

	if (!wmidev_instance_count(wdev)) {
		ret = -ENODEV;
		goto out_unlock;
	}

	if (a720.io_wdev) {
		ret = -EBUSY;
		goto out_unlock;
	}

	a720.io_wdev = wdev;
	ret = a720_maybe_initialize();
	if (ret)
		a720.io_wdev = NULL;

out_unlock:
	mutex_unlock(&a720.io_lock);
	if (ret == -EBUSY)
		dev_err(&wdev->dev, "duplicate WMI channel instance\n");
	else if (ret == -ENODEV)
		dev_err(&wdev->dev, "IO data block has no instances\n");
	else if (!ret)
		dev_dbg(&wdev->dev, "%s channel bound\n",
			*kind == A720_WMI_EVENT ? "event" : "IO");

	return ret;
}

static void a720_wmi_remove(struct wmi_device *wdev)
{
	const enum a720_wmi_kind *kind = dev_get_drvdata(&wdev->dev);

	mutex_lock(&a720.io_lock);
	if (kind && *kind == A720_WMI_EVENT)
		a720.event_bound = false;
	else if (a720.io_wdev == wdev)
		a720.io_wdev = NULL;
	a720.initialized = false;
	mutex_unlock(&a720.io_lock);

	cancel_work_sync(&a720.volume_query_work);
	cancel_work_sync(&a720.volume_sync_work);
	atomic_set(&a720.pending_volume_queries, 0);
	atomic_set(&a720.pending_volume_syncs, 0);
}

static void a720_wmi_notify(struct wmi_device *wdev, union acpi_object *data)
{
	const u8 *bytes;
	u32 length;
	u8 event_id;
	u64 sequence;

	if (!data || data->type != ACPI_TYPE_BUFFER ||
	    !data->buffer.length || !data->buffer.pointer) {
		dev_warn_ratelimited(&wdev->dev,
			"event received without a usable buffer payload\n");
		return;
	}

	bytes = data->buffer.pointer;
	length = data->buffer.length;
	event_id = bytes[0];
	sequence = atomic64_inc_return(&a720.event_sequence);

	dev_dbg(&wdev->dev, "EVENT #%llu id=0x%02x length=%u head=%*phN\n",
		(unsigned long long)sequence, event_id, length,
		(int)min_t(u32, length, 8), bytes);

	switch (event_id) {
	case 0x13:
	case 0x14:
		dev_dbg(&wdev->dev,
			"EVENT #%llu brightness event 0x%02x is not implemented\n",
			(unsigned long long)sequence, event_id);
		break;
	case 0x16:
		atomic_inc(&a720.pending_volume_syncs);
		queue_work(a720.wq, &a720.volume_sync_work);
		break;
	case 0x17:
		atomic_inc(&a720.pending_volume_queries);
		queue_work(a720.wq, &a720.volume_query_work);
		break;
	default:
		dev_dbg(&wdev->dev, "EVENT #%llu unhandled id=0x%02x\n",
			(unsigned long long)sequence, event_id);
		break;
	}
}

static const struct wmi_device_id a720_wmi_id_table[] = {
	{ A720_EVENT_GUID, &a720_event_kind },
	{ A720_IO_GUID, &a720_io_kind },
	{ }
};
MODULE_DEVICE_TABLE(wmi, a720_wmi_id_table);

static struct wmi_driver a720_wmi_driver = {
	.driver = {
		.name = "a720-wmi-handshake",
	},
	.id_table = a720_wmi_id_table,
	.probe = a720_wmi_probe,
	.remove = a720_wmi_remove,
	.notify = a720_wmi_notify,
	.no_singleton = false,
};

static int __init a720_init(void)
{
	int ret;

	if (!dmi_check_system(a720_dmi_table))
		return -ENODEV;

	a720.wq = alloc_ordered_workqueue("a720_wmi", WQ_FREEZABLE);
	if (!a720.wq)
		return -ENOMEM;

	INIT_WORK(&a720.volume_query_work, a720_run_volume_query);
	INIT_WORK(&a720.volume_sync_work, a720_run_volume_sync);

	ret = wmi_driver_register(&a720_wmi_driver);
	if (ret) {
		destroy_workqueue(a720.wq);
		a720.wq = NULL;
	}

	return ret;
}

static void __exit a720_exit(void)
{
	wmi_driver_unregister(&a720_wmi_driver);
	destroy_workqueue(a720.wq);
	a720.wq = NULL;
}

module_init(a720_init);
module_exit(a720_exit);

MODULE_AUTHOR("sillymotives");
MODULE_DESCRIPTION("Lenovo IdeaCentre A720 bezel WMI volume protocol driver");
MODULE_VERSION("1.1.0");
MODULE_LICENSE("GPL");
