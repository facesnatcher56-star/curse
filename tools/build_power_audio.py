"""Layer existing owner-provided recordings into four original power cues.

No DS2 audio, oscillator or noise source is read or generated. Requires NumPy,
SciPy and SoundFile; --deps can point at the temporary analysis dependencies.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path
if "--deps" in sys.argv:
    sys.path.insert(0, sys.argv[sys.argv.index("--deps") + 1])
import numpy as np
import soundfile as sf
from scipy import signal
from scipy.ndimage import uniform_filter1d

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/audio"
RATE = 44100
USED = set()


def recording(name, pitch=1.0, low=30, high=10000, reverse=False):
    USED.add(name)
    x, rate = sf.read(SOURCE / name, always_2d=True)
    x = x.mean(axis=1)
    x -= x.mean()
    x = signal.resample_poly(x, RATE, rate)
    x = signal.resample(x, round(len(x) / pitch))
    if reverse:
        x = x[::-1]
    sos = signal.butter(3, [low, high], btype="bandpass", fs=RATE, output="sos")
    x = signal.sosfilt(sos, x)
    # Layer gains describe relative RMS rather than uncontrolled source levels.
    x *= .12 / max(np.sqrt(np.mean(x*x)), 1e-9)
    edge = min(round(.006*RATE), len(x)//2)
    x[:edge] *= np.linspace(0, 1, edge)
    x[-edge:] *= np.linspace(1, 0, edge)
    return x


def cue(name, duration, layers, attack, decay, sustain=0):
    mix = np.zeros(round(duration * RATE))
    for x, gain, delay in layers:
        start = round(delay * RATE)
        n = min(len(x), len(mix) - start)
        if n > 0:
            mix[start:start+n] += x[:n] * gain
    t = np.arange(len(mix)) / RATE
    # Shape macro dynamics without erasing the recorded grain. Bounded local
    # gain prevents the short source transient from swallowing the longer body.
    local_rms = np.sqrt(np.maximum(uniform_filter1d(mix*mix, round(.03*RATE)), 1e-12))
    gain = np.minimum(.12 / np.maximum(local_rms, .008), 12.0)
    mix *= uniform_filter1d(gain, round(.015*RATE))
    envelope = np.minimum(t / attack, 1) * np.exp(-np.maximum(t - sustain, 0) / decay)
    envelope *= np.clip((duration - t) / .08, 0, 1)
    mix *= envelope
    # Gentle soft saturation controls rare spikes while retaining recorded texture.
    mix = .25 * np.tanh(mix / .25)
    # Remove inaudible DC/subsonic energy; preserve a fast click-free onset.
    mix = signal.sosfilt(signal.butter(2, 25, btype="highpass", fs=RATE, output="sos"), mix)
    mix[-round(.03*RATE):] *= np.linspace(1, 0, round(.03*RATE))
    truepeak = np.max(abs(signal.resample_poly(mix, 4, 1)))
    mix *= 10 ** (-6 / 20) / max(truepeak, 1e-9)
    return name, mix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deps", type=Path)
    args = parser.parse_args()
    bass = recording("leap_land.wav", .85, 28, 180)
    body = recording("fireball_impact.wav", .78, 75, 1800)
    grit = recording("sword_hit_2.wav", .88, 450, 9000)
    air = recording("fireball_impact.wav", 1.25, 3000, 12500)
    scrape = recording("sword_hit_2.wav", .48, 2200, 11000, True)
    release = recording("sword_miss_2.wav", .78, 180, 5000)
    cues = [
        cue("brutal_hit", 2.42, [(bass, .9, 0), (body, 1.3, 0), (grit, 2.0, 0),
            (air, .35, 0), (body, .18, .17), (bass, .14, .48)], .008, .57),
        cue("take_aim_charge", 1.06, [(air, .8, 0), (scrape, .32, .02),
            (bass, .4, 0), (body, .20, 0)], .11, .30),
        cue("take_aim_fire", 1.29, [(release, .65, 0), (body, .75, 0),
            (bass, .6, 0), (air, .42, .03)], .035, .34),
        cue("take_aim_hit", 2.17, [(bass, 1.0, 0), (body, .8, 0), (grit, 2.0, 0),
            (air, .4, 0), (air, .18, .35), (bass, .65, .35), (body, .35, .45), (bass, .5, .75)], .012, .25, 1.05),
    ]
    out = SOURCE / "powers"
    out.mkdir(exist_ok=True)
    metrics = {}
    for name, x in cues:
        assert np.isfinite(x).all() and np.max(abs(x)) < .51
        sf.write(out / (name + ".wav"), x, RATE, subtype="PCM_16")
        decoded, _ = sf.read(out / (name + ".wav"))
        peak = float(np.max(abs(signal.resample_poly(decoded, 4, 1))))
        assert peak <= .503, "Power cue exceeds -6 dBFS oversampled target"
        energy = np.cumsum(decoded**2); energy /= energy[-1]
        metrics[name] = {"duration_s": len(x)/RATE, "oversampled_peak_dbfs": float(20*np.log10(peak)),
                         "rms_dbfs": float(20*np.log10(np.sqrt(np.mean(decoded**2)))),
                         "energy90_s": float(np.searchsorted(energy, .9)/RATE)}
        print(name, metrics[name])
    # Convenient preview: ordered cues with half-second gaps, not a game asset.
    preview = np.concatenate([np.concatenate([x, np.zeros(RATE//2)]) for _, x in cues])
    docs = ROOT / "docs/audio-analysis"
    docs.mkdir(exist_ok=True)
    sf.write(docs / "curse_power_preview.wav", preview, RATE, subtype="PCM_16")
    manifest = {"sources": {n: hashlib.sha256((SOURCE/n).read_bytes()).hexdigest() for n in sorted(USED)},
                "cues": metrics, "preview_order": [name for name, _ in cues],
                "note": "Derived only from existing project recordings. Source provenance/licences remain in assets/audio/CREDITS.md. No DS2 sample content."}
    (docs / "curse_power_mix.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
