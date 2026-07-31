#!/usr/bin/env python3
"""Generate the Darkstar boot and shutdown jingles."""

from __future__ import annotations

import argparse
import math
from pathlib import Path
import struct
import wave

SAMPLE_RATE = 48_000
CHANNELS = 2
SAMPLE_WIDTH = 2
PEAK = 0.075
DRIVE = 4.0

C4 = 261.63
EB4 = 311.13
G4 = 392.00


def shaped_square(phase: float) -> float:
    return math.tanh(DRIVE * math.sin(phase)) / math.tanh(DRIVE)


def envelope(
    index: int,
    length: int,
    attack_seconds: float,
    release_seconds: float,
) -> float:
    attack = max(1, int(SAMPLE_RATE * attack_seconds))
    release = max(1, int(SAMPLE_RATE * release_seconds))
    gain = 1.0

    if index < attack:
        gain = min(gain, index / attack)

    remaining = length - index - 1

    if remaining < release:
        gain = min(gain, max(0.0, remaining / release))

    return gain


def fixed_tone(
    frequency: float,
    duration: float,
    phase: float,
    *,
    attack: float = 0.004,
    release: float = 0.004,
) -> tuple[list[float], float]:
    length = int(SAMPLE_RATE * duration)
    output: list[float] = []

    for index in range(length):
        phase += 2.0 * math.pi * frequency / SAMPLE_RATE
        output.append(
            shaped_square(phase)
            * PEAK
            * envelope(index, length, attack, release)
        )

    return output, phase


def falling_tone(
    start_frequency: float,
    end_frequency: float,
    duration: float,
    phase: float,
) -> tuple[list[float], float]:
    length = int(SAMPLE_RATE * duration)
    output: list[float] = []

    for index in range(length):
        progress = index / max(1, length - 1)
        curved = progress**1.25
        frequency = start_frequency + (
            end_frequency - start_frequency
        ) * curved
        phase += 2.0 * math.pi * frequency / SAMPLE_RATE
        output.append(
            shaped_square(phase)
            * PEAK
            * envelope(index, length, 0.004, 0.34)
        )

    return output, phase


def save_wav(path: Path, samples: list[float]) -> None:
    frames = bytearray()

    for sample in samples:
        clamped = max(-1.0, min(1.0, sample))
        value = int(round(clamped * 32767))
        frames.extend(struct.pack("<hh", value, value))

    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(CHANNELS)
        wav_file.setsampwidth(SAMPLE_WIDTH)
        wav_file.setframerate(SAMPLE_RATE)
        wav_file.writeframes(frames)


def build_boot() -> list[float]:
    phase = 0.0
    output: list[float] = []

    for frequency, duration, release in (
        (C4, 0.100, 0.004),
        (EB4, 0.100, 0.004),
        (G4, 0.600, 0.260),
    ):
        segment, phase = fixed_tone(
            frequency,
            duration,
            phase,
            release=release,
        )
        output.extend(segment)

    return output


def build_shutdown() -> list[float]:
    phase = 0.0
    output: list[float] = []

    for frequency in (G4, EB4):
        segment, phase = fixed_tone(frequency, 0.100, phase)
        output.extend(segment)

    segment, phase = falling_tone(C4, 90.0, 0.850, phase)
    output.extend(segment)
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path.cwd(),
    )
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    boot_path = args.output_dir / "darkstar_boot.wav"
    shutdown_path = args.output_dir / "darkstar_shutdown.wav"

    save_wav(boot_path, build_boot())
    save_wav(shutdown_path, build_shutdown())

    print(boot_path)
    print(shutdown_path)


if __name__ == "__main__":
    main()
