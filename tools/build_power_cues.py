"""Cast and impact cues for Whirling Strike, Staggering Blow and War Cry, layered from existing project recordings.

Numpy and soundfile only (no SciPy): the filters are FFT masks and the resampling is linear. Writes assets/audio/powers/<event>.wav.
Rebuild with:  python tools/build_power_cues.py
Sources and licences are listed in assets/audio/CREDITS.md. No DS2 audio and no synthesized noise source is used.
"""
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/audio"
OUT = SOURCE / "powers"
RATE = 44100
USED: set[str] = set()


def recording(name: str, pitch: float = 1.0, low: float = 30.0, high: float = 10000.0) -> np.ndarray:
    """A source file at project rate, shifted by `pitch` (above 1 is higher and shorter) and band-passed by an FFT mask."""
    USED.add(name)
    x, rate = sf.read(SOURCE / name, always_2d=True)
    x = x.mean(axis=1)
    x = x - x.mean()
    x = np.interp(np.linspace(0, len(x) - 1, round(len(x) * RATE / rate)), np.arange(len(x)), x) if rate != RATE else x
    x = np.interp(np.arange(0, len(x) - 1, pitch), np.arange(len(x)), x)
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / RATE)
    spectrum[(freqs < low) | (freqs > high)] = 0.0
    x = np.fft.irfft(spectrum, len(x))
    x *= 0.12 / max(np.sqrt(np.mean(x * x)), 1e-9)
    edge = min(round(0.006 * RATE), len(x) // 2)
    x[:edge] *= np.linspace(0, 1, edge)
    x[-edge:] *= np.linspace(1, 0, edge)
    return x


def smooth(x: np.ndarray, width: int) -> np.ndarray:
    """A moving average (the numpy stand-in for scipy's uniform_filter1d, edges handled by padding)."""
    padded = np.pad(x, (width // 2, width - width // 2 - 1), mode="edge")
    return np.convolve(padded, np.ones(width) / width, mode="valid")


def cue(name: str, duration: float, layers: list, attack: float, decay: float) -> tuple[str, np.ndarray]:
    mix = np.zeros(round(duration * RATE))
    for x, gain, delay in layers:
        start = round(delay * RATE)
        n = min(len(x), len(mix) - start)
        if n > 0:
            mix[start:start + n] += x[:n] * gain
    t = np.arange(len(mix)) / RATE
    local_rms = np.sqrt(np.maximum(smooth(mix * mix, round(0.03 * RATE)), 1e-12))
    mix *= smooth(np.minimum(0.12 / np.maximum(local_rms, 0.008), 12.0), round(0.015 * RATE))
    mix *= np.minimum(t / attack, 1) * np.exp(-t / decay)
    mix *= np.clip((duration - t) / 0.08, 0, 1)
    mix = 0.25 * np.tanh(mix / 0.25)
    # Remove subsonic energy with a brickwall high-pass at 25 Hz.
    spectrum = np.fft.rfft(mix)
    spectrum[np.fft.rfftfreq(len(mix), 1.0 / RATE) < 25.0] = 0.0
    mix = np.fft.irfft(spectrum, len(mix))
    mix[-round(0.03 * RATE):] *= np.linspace(1, 0, round(0.03 * RATE))
    peak = np.max(np.abs(np.interp(np.arange(0, len(mix) - 1, 0.25), np.arange(len(mix)), mix)))
    mix *= 10 ** (-6 / 20) / max(peak, 1e-9)
    return name, mix


def main() -> None:
    swoosh = recording("sword_miss_2.wav", 0.8, 300, 6000)
    swoosh_b = recording("sword_miss_1.wav", 0.95, 300, 6000)
    heavy_swing = recording("sword_miss_3.wav", 0.62, 120, 4000)
    heavy_swing_b = recording("sword_miss_4.wav", 0.7, 120, 4000)
    grit = recording("sword_hit_2.wav", 0.88, 450, 9000)
    grit_low = recording("sword_hit_2.wav", 0.6, 120, 3000)
    bass = recording("leap_land.wav", 0.85, 28, 180)
    body = recording("fireball_impact.wav", 0.78, 75, 1800)
    roar = recording("fireball_cast_2.wav", 0.7, 90, 3500)
    roar_b = recording("fireball_cast_1.wav", 0.6, 90, 3500)
    burst = recording("fireball_impact.wav", 0.9, 400, 7000)
    cues = [
        cue("whirling_strike_cast", 1.1, [(swoosh, 1.0, 0.0), (swoosh_b, 0.7, 0.12)], 0.03, 0.35),
        cue("whirling_strike_hit", 1.2, [(grit, 1.6, 0.0), (bass, 0.5, 0.0), (burst, 0.4, 0.0)], 0.01, 0.45),
        cue("staggering_cast", 1.2, [(heavy_swing, 1.0, 0.0), (heavy_swing_b, 0.6, 0.15), (bass, 0.3, 0.0)], 0.05, 0.4),
        cue("staggering_hit", 1.8, [(bass, 1.0, 0.0), (body, 1.2, 0.0), (grit_low, 1.5, 0.0), (bass, 0.5, 0.45)], 0.008, 0.6),
        cue("war_cry_cast", 1.4, [(roar, 1.0, 0.0), (roar_b, 0.6, 0.1)], 0.08, 0.5),
        cue("war_cry_hit", 1.4, [(burst, 1.0, 0.0), (grit_low, 0.8, 0.0), (body, 0.5, 0.05)], 0.01, 0.5),
    ]
    OUT.mkdir(exist_ok=True)
    for name, x in cues:
        assert np.isfinite(x).all() and np.max(np.abs(x)) < 0.51
        sf.write(OUT / (name + ".wav"), x, RATE, subtype="PCM_16")
        print(name, round(len(x) / RATE, 3), "s")
    print("sources:", sorted(USED))


if __name__ == "__main__":
    main()
