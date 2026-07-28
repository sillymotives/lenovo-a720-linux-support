// SPDX-License-Identifier: GPL-2.0-only
/*
 * Lenovo IdeaCentre A720 bezel-button WMI handshake diagnostic.
 *
 * Reproduces the read-only half of Lenovo's original Windows OSD protocol:
 *   WMI event 0x17
 *     -> write 64-byte command 01 10 04 02 03 a7 ... to ABBC0F40
 *     -> query ABBC0F40 instance 0
 *     -> log the returned buffer and response byte 5 (requested volume)
 *
 * The module does not emit input events and does not change Linux volume or
 * brightness. On event 0x16 it sends Lenovo's exact volume synchronization
 * packet using a configurable 0..100 volume value.
 */

#include <linux/acpi.h>
#include <linux/atomic.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/slab.h>
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
	struct mutex lock;
	struct wmi_device *io_wdev;
	struct work_struct volume_query_work;
	struct work_struct volume_sync_work;
	atomic_t pending_volume_queries;
	atomic_t pending_volume_syncs;
	atomic64_t event_sequence;
	atomic64_t query_sequence;
};

static struct a720_state a720 = {
	.lock = __MUTEX_INITIALIZER(a720.lock),
	.pending_volume_queries = ATOMIC_INIT(0),
	.pending_volume_syncs = ATOMIC_INIT(0),
	.event_sequence = ATOMIC64_INIT(0),
	.query_sequence = ATOMIC64_INIT(0),
};

static const enum a720_wmi_kind a720_event_kind = A720_WMI_EVENT;
static const enum a720_wmi_kind a720_io_kind = A720_WMI_IO;

static bool initialize = true;
module_param(initialize, bool, 0444);
MODULE_PARM_DESC(initialize,
	"Send ICMD 0x02 (WINI/APRC++) when the IO GUID binds (default: true)");


static int sync_volume = 50;
module_param(sync_volume, int, 0644);
MODULE_PARM_DESC(sync_volume,
	"Volume percentage sent to Lenovo firmware on event 0x16 (0..100, default: 50)");

static bool dump_response = false;
module_param(dump_response, bool, 0644);
MODULE_PARM_DESC(dump_response,
	"Hex-dump each vendor query response (default: false)");

/* User-space bridge reads these without needing journal access. */
static int requested_volume = -1;
module_param(requested_volume, int, 0444);
MODULE_PARM_DESC(requested_volume,
	"Most recent Lenovo-requested absolute volume, or -1 before first request");

static unsigned int request_seq;
module_param(request_seq, uint, 0444);
MODULE_PARM_DESC(request_seq,
	"Sequence incremented after each valid requested-volume response");

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

	(void)work;
	requests = atomic_xchg(&a720.pending_volume_syncs, 0);
	volume = clamp(sync_volume, 0, 100);
	packet[6] = (u8)volume;

	mutex_lock(&a720.lock);
	io_wdev = a720.io_wdev;
	if (io_wdev)
		get_device(&io_wdev->dev);
	mutex_unlock(&a720.lock);

	if (!io_wdev) {
		pr_warn("a720-wmi-handshake: volume sync skipped: IO channel is not bound\n");
		return;
	}

	in.length = sizeof(packet);
	in.pointer = packet;
	status = wmidev_block_set(io_wdev, 0, &in);
	if (ACPI_FAILURE(status)) {
		dev_err(&io_wdev->dev,
			"SYNC failed for volume=%d: %s (0x%x)\n",
			volume, acpi_format_exception(status), status);
	} else {
		dev_info(&io_wdev->dev,
			"SYNC completed after %d event-0x16 notification(s): sent 01 10 05 03 03 a8 %02x (volume=%d)\n",
			requests, volume, volume);
	}

	put_device(&io_wdev->dev);
}

static void a720_run_volume_query(struct work_struct *work)
{
	struct wmi_device *io_wdev;
	struct acpi_buffer in;
	union acpi_object *response;
	acpi_status status;
	u64 query_number;
	int requests;

	(void)work;

	/* Coalesce a firmware repeat storm into one transaction per work run. */
	requests = atomic_xchg(&a720.pending_volume_queries, 0);
	query_number = atomic64_inc_return(&a720.query_sequence);

	mutex_lock(&a720.lock);
	io_wdev = a720.io_wdev;
	if (io_wdev)
		get_device(&io_wdev->dev);
	mutex_unlock(&a720.lock);

	if (!io_wdev) {
		pr_warn("a720-wmi-handshake: QUERY #%llu skipped: IO channel is not bound\n",
			(unsigned long long)query_number);
		return;
	}

	in.length = sizeof(a720_volume_query_packet);
	in.pointer = (void *)a720_volume_query_packet;
	status = wmidev_block_set(io_wdev, 0, &in);
	if (ACPI_FAILURE(status)) {
		dev_err(&io_wdev->dev,
			"QUERY #%llu vendor command 01 10 04 02 03 a7 failed: %s (0x%x)\n",
			(unsigned long long)query_number,
			acpi_format_exception(status), status);
		goto out_put;
	}

	response = wmidev_block_query(io_wdev, 0);
	if (!response) {
		dev_err(&io_wdev->dev,
			"QUERY #%llu WMI IO block returned no ACPI object\n",
			(unsigned long long)query_number);
		goto out_put;
	}

	if (response->type != ACPI_TYPE_BUFFER) {
		dev_err(&io_wdev->dev,
			"QUERY #%llu unexpected ACPI object type=%u\n",
			(unsigned long long)query_number, response->type);
		goto out_free;
	}

	dev_info(&io_wdev->dev,
		 "QUERY #%llu completed after %d event-0x17 notification(s): response length=%u\n",
		 (unsigned long long)query_number, requests,
		 response->buffer.length);

	if (response->buffer.length > 5) {
		u8 volume = response->buffer.pointer[5];

		if (volume <= 100) {
			WRITE_ONCE(requested_volume, (int)volume);
			WRITE_ONCE(request_seq, READ_ONCE(request_seq) + 1);
		}

		dev_info(&io_wdev->dev,
			 "QUERY #%llu requested_volume=response[5]=%u (0x%02x)%s\n",
			 (unsigned long long)query_number,
			 volume, volume,
			 volume <= 100 ? "" : " [outside expected 0..100 range]");
	} else {
		dev_warn(&io_wdev->dev,
			 "QUERY #%llu response is too short for byte 5\n",
			 (unsigned long long)query_number);
	}

	if (dump_response)
		a720_dump_buffer(&io_wdev->dev, response->buffer.pointer,
				 response->buffer.length, query_number);

out_free:
	kfree(response);
out_put:
	put_device(&io_wdev->dev);
}

static int a720_wmi_probe(struct wmi_device *wdev, const void *context)
{
	const enum a720_wmi_kind *kind = context;
	struct acpi_buffer in;
	acpi_status status;

	if (!kind)
		return -EINVAL;

	if (*kind == A720_WMI_EVENT) {
		dev_info(&wdev->dev,
			 "event channel bound; waiting for Lenovo events 0x13, 0x14, 0x16 and 0x17\n");
		return 0;
	}

	mutex_lock(&a720.lock);
	if (a720.io_wdev) {
		mutex_unlock(&a720.lock);
		dev_err(&wdev->dev, "a second IO channel attempted to bind\n");
		return -EBUSY;
	}
	a720.io_wdev = wdev;
	mutex_unlock(&a720.lock);

	dev_info(&wdev->dev, "IO channel bound\n");
	if (!initialize) {
		dev_info(&wdev->dev, "initialization skipped by module parameter\n");
		return 0;
	}

	in.length = sizeof(a720_init_packet);
	in.pointer = (void *)a720_init_packet;
	status = wmidev_block_set(wdev, 0, &in);
	if (ACPI_FAILURE(status)) {
		dev_err(&wdev->dev, "initialization failed: %s (0x%x)\n",
			acpi_format_exception(status), status);
		mutex_lock(&a720.lock);
		a720.io_wdev = NULL;
		mutex_unlock(&a720.lock);
		return -EIO;
	}

	dev_info(&wdev->dev,
		 "initialization sent (ICMD 0x02 / WINI / APRC++)\n");
	return 0;
}

static void a720_wmi_remove(struct wmi_device *wdev)
{
	mutex_lock(&a720.lock);
	if (a720.io_wdev == wdev)
		a720.io_wdev = NULL;
	mutex_unlock(&a720.lock);

	cancel_work_sync(&a720.volume_query_work);
	cancel_work_sync(&a720.volume_sync_work);
}

static void a720_wmi_notify(struct wmi_device *wdev, union acpi_object *data)
{
	const u8 *bytes;
	u32 length;
	u8 event_id;
	u64 sequence;

	if (!data || data->type != ACPI_TYPE_BUFFER || !data->buffer.length) {
		dev_info(&wdev->dev, "event received without a usable buffer payload\n");
		return;
	}

	bytes = data->buffer.pointer;
	length = data->buffer.length;
	event_id = bytes[0];
	sequence = atomic64_inc_return(&a720.event_sequence);

	dev_info(&wdev->dev,
		 "EVENT #%llu id=0x%02x length=%u head=%*phN\n",
		 (unsigned long long)sequence, event_id, length,
		 (int)min_t(u32, length, 8), bytes);

	switch (event_id) {
	case 0x13:
		dev_info(&wdev->dev,
			 "EVENT #%llu Lenovo handler classifies this as one brightness direction\n",
			 (unsigned long long)sequence);
		break;
	case 0x14:
		dev_info(&wdev->dev,
			 "EVENT #%llu Lenovo handler classifies this as the opposite brightness direction\n",
			 (unsigned long long)sequence);
		break;
	case 0x16:
		atomic_inc(&a720.pending_volume_syncs);
		schedule_work(&a720.volume_sync_work);
		break;
	case 0x17:
		atomic_inc(&a720.pending_volume_queries);
		schedule_work(&a720.volume_query_work);
		break;
	default:
		dev_info(&wdev->dev,
			 "EVENT #%llu unhandled Lenovo event id=0x%02x\n",
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
	.no_singleton = true,
};

static int __init a720_init(void)
{
	INIT_WORK(&a720.volume_query_work, a720_run_volume_query);
	INIT_WORK(&a720.volume_sync_work, a720_run_volume_sync);
	return wmi_driver_register(&a720_wmi_driver);
}

static void __exit a720_exit(void)
{
	wmi_driver_unregister(&a720_wmi_driver);
	cancel_work_sync(&a720.volume_query_work);
	cancel_work_sync(&a720.volume_sync_work);
}

module_init(a720_init);
module_exit(a720_exit);

MODULE_AUTHOR("OpenAI; protocol reconstructed from Lenovo's original OSD utility");
MODULE_DESCRIPTION("Lenovo IdeaCentre A720 bezel WMI volume bridge");
MODULE_LICENSE("GPL");
