#!/usr/bin/env python3
"""Apply Lenovo A720 absolute-volume requests to PulseAudio or PipeWire."""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import time
from collections.abc import Sequence
from pathlib import Path

BASE = Path("/sys/module/a720_wmi_handshake/parameters")
SYNC = BASE / "sync_volume"
REQUEST = BASE / "request"
LEGACY_REQUESTED = BASE / "requested_volume"
LEGACY_SEQUENCE = BASE / "request_seq"
COMMAND_TIMEOUT = 5.0


def run(
    command: Sequence[str],
    *,
    capture: bool = False,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        text=True,
        capture_output=capture,
        check=check,
        timeout=COMMAND_TIMEOUT,
    )


def backend() -> str:
    if shutil.which("pactl"):
        result = run(["pactl", "info"], capture=True, check=False)
        if result.returncode == 0:
            return "pactl"

    if shutil.which("wpctl"):
        result = run(["wpctl", "status"], capture=True, check=False)
        if result.returncode == 0:
            return "wpctl"

    raise RuntimeError("No working pactl or wpctl audio connection")


def get_volume(selected_backend: str) -> int:
    if selected_backend == "pactl":
        output = run(
            ["pactl", "get-sink-volume", "@DEFAULT_SINK@"],
            capture=True,
        ).stdout
        percentages = [int(value) for value in re.findall(r"/\s*(\d+)%", output)]
        if not percentages:
            raise RuntimeError(f"Could not parse pactl volume: {output.strip()!r}")
        volume = round(sum(percentages) / len(percentages))
    else:
        output = run(
            ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
            capture=True,
        ).stdout
        match = re.search(r"Volume:\s*([0-9]+(?:\.[0-9]+)?)", output)
        if not match:
            raise RuntimeError(f"Could not parse wpctl volume: {output.strip()!r}")
        volume = round(float(match.group(1)) * 100)

    return max(0, min(100, volume))


def set_volume(selected_backend: str, volume: int) -> None:
    volume = max(0, min(100, volume))
    if selected_backend == "pactl":
        run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{volume}%"])
    else:
        run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{volume}%"])


def write_sync(volume: int) -> None:
    volume = max(0, min(100, volume))
    SYNC.write_text(f"{volume}\n", encoding="ascii")


def read_integer(path: Path) -> int:
    return int(path.read_text(encoding="ascii").strip())


def read_request() -> tuple[int, int]:
    if REQUEST.exists():
        fields = REQUEST.read_text(encoding="ascii").split()
        if len(fields) != 2:
            raise RuntimeError(f"Malformed kernel request snapshot: {fields!r}")
        return int(fields[0]), int(fields[1])

    # Version 1.0 exported the fields separately. Read sequence around the
    # value so a rolling upgrade cannot consume a mismatched pair.
    for _ in range(5):
        sequence_before = read_integer(LEGACY_SEQUENCE)
        requested = read_integer(LEGACY_REQUESTED)
        sequence_after = read_integer(LEGACY_SEQUENCE)
        if sequence_before == sequence_after:
            return sequence_after, requested

    raise RuntimeError("Could not obtain a stable legacy request snapshot")


def wait_ready(timeout: float = 45.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        modern_ready = REQUEST.exists()
        legacy_ready = LEGACY_REQUESTED.exists() and LEGACY_SEQUENCE.exists()
        if SYNC.exists() and (modern_ready or legacy_ready):
            return
        time.sleep(0.5)

    raise RuntimeError("Kernel module sysfs controls did not appear")


def main() -> None:
    wait_ready()
    selected_backend = backend()
    current = get_volume(selected_backend)
    write_sync(current)
    print(
        f"A720 bridge ready: backend={selected_backend}, initial volume={current}%",
        flush=True,
    )

    last_sequence, _ = read_request()
    last_refresh = time.monotonic()

    while True:
        sequence, requested = read_request()
        if sequence != last_sequence:
            if 0 <= requested <= 100:
                set_volume(selected_backend, requested)
                write_sync(requested)
                print(f"Lenovo bezel requested {requested}% -> applied", flush=True)
            last_sequence = sequence
            last_refresh = time.monotonic()
        elif time.monotonic() - last_refresh >= 2.0:
            write_sync(get_volume(selected_backend))
            last_refresh = time.monotonic()

        time.sleep(0.08)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except Exception as error:
        print(f"A720 bridge error: {error}", file=sys.stderr, flush=True)
        raise SystemExit(1) from error
