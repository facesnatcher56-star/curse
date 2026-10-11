"""Offline DSP research; reads reference WAVs, never copies audio into the game.

Requires numpy, scipy, matplotlib, soundfile. Optional --deps adds an isolated
dependency directory. Outputs measurements and plots, not replacement sounds.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

# Resolve the optional dependency path before scientific imports; leave importing
# this module safe for focused tests (no extraction or report generation).
if "--deps" in sys.argv:
    sys.path.insert(0, sys.argv[sys.argv.index("--deps") + 1])
import numpy as np
import soundfile as sf
from scipy import signal
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

BANDS = [(0, 20), (20, 80), (80, 250), (250, 1000), (1000, 4000), (4000, 8000), (8000, 100000)]
LABELS = [f"{a}-{b} Hz" if b < 100000 else "8000-Nyquist Hz" for a, b in BANDS]
EPS = 1e-20


def db(value):
    return 20 * np.log10(np.maximum(value, 1e-10))


def analyze(path):
    info = sf.info(path)
    channels, sr = sf.read(path, always_2d=True, dtype="float64")
    x = channels.mean(axis=1)
    # Remove DC only for spectral measurements; level measurements use original PCM.
    centered = x - x.mean()
    win = max(32, round(sr * .02))
    hop = max(1, round(sr * .005))
    starts = np.arange(0, max(1, len(x) - win + 1), hop)
    rms = np.array([np.sqrt(np.mean(x[t:t + win] ** 2)) for t in starts])
    times = (starts + win / 2) / sr
    peak = float(np.max(np.abs(channels)))
    total_rms = float(np.sqrt(np.mean(channels ** 2)))
    energy = np.cumsum(x ** 2)
    energy /= max(energy[-1], EPS)
    quantiles = {str(q): float(np.searchsorted(energy, q) / sr) for q in [.01, .05, .1, .5, .9, .95, .99]}
    active = np.flatnonzero(rms >= rms.max() * .01)  # -40 dB relative to maximum 20ms RMS
    nfft = 2048
    freq, st, z = signal.stft(centered, sr, nperseg=nfft, noverlap=nfft - hop, boundary="zeros", padded=True)
    power = abs(z) ** 2
    power_sum = power.sum(axis=0) + EPS
    spectrum = power.sum(axis=1)
    audible = freq >= 20
    centroid = (freq[:, None] * power).sum(axis=0) / power_sum
    cumulative = np.cumsum(power, axis=0)
    rolloff = freq[np.argmax(cumulative >= .95 * power_sum, axis=0)]
    flatness = np.exp(np.mean(np.log(power[audible] + EPS), axis=0)) / (np.mean(power[audible], axis=0) + EPS)
    weights = power_sum / power_sum.sum()
    bandpower = np.array([power[(freq >= lo) & (freq < hi)].sum(axis=0) for lo, hi in BANDS])
    # Whole-file FFT gives fine low-frequency resolution and includes the complete onset.
    exactfreq = np.fft.rfftfreq(len(centered), 1/sr)
    exactpower = abs(np.fft.rfft(centered)) ** 2
    exactpower[1:-1 if len(centered) % 2 == 0 else None] *= 2
    bandpct = np.array([100 * exactpower[(exactfreq >= lo) & (exactfreq < hi)].sum() / exactpower.sum() for lo, hi in BANDS])
    # Positive changes in normalized magnitude identify candidate new layers/transients.
    mag = abs(z)
    norm = mag / (np.linalg.norm(mag, axis=0) + EPS)
    flux = np.sqrt(np.sum(np.maximum(np.diff(norm, axis=1), 0) ** 2, axis=0))
    valid = power_sum[1:] > power_sum.max() * .001
    flux = np.where(valid, flux, 0)
    peaks, _ = signal.find_peaks(flux, distance=max(1, round(.07 * sr / hop)), prominence=.06)
    events = sorted([{"time_s": float(st[i + 1]), "novelty": float(flux[i])} for i in peaks], key=lambda p: -p["novelty"])[:10]
    events.sort(key=lambda p: p["time_s"])
    wf, welch = signal.welch(centered, sr, nperseg=min(8192, len(centered)))
    spectral_peaks, _ = signal.find_peaks(welch, distance=3)
    spectral_peaks = sorted(spectral_peaks, key=lambda i: welch[i], reverse=True)[:8]
    # Tail-energy regression is descriptive only: a designed FX decay is NOT room RT60.
    reverse = np.cumsum((x ** 2)[::-1])[::-1]
    edc = 10 * np.log10(np.maximum(reverse / max(reverse[0], EPS), EPS))
    fitmask = (edc <= -5) & (edc >= -25)
    decay = None
    if fitmask.sum() > sr * .02:
        tx = np.flatnonzero(fitmask) / sr
        slope, intercept = np.polyfit(tx, edc[fitmask], 1)
        prediction = slope * tx + intercept
        r2 = 1 - np.sum((edc[fitmask] - prediction) ** 2) / max(np.sum((edc[fitmask] - edc[fitmask].mean()) ** 2), EPS)
        decay = {"minus5_to_minus25_duration_s": float(tx[-1] - tx[0]), "slope_db_s": float(slope), "r_squared": float(r2)}
    segments = []
    # Equal-duration thirds show evolution; not alleged original source layers.
    for a, b in [(0, 1/3), (1/3, 2/3), (2/3, 1)]:
        mask = (st >= a * len(x) / sr) & (st < b * len(x) / sr)
        w = power_sum[mask]
        segments.append({"time_s": [a * len(x) / sr, b * len(x) / sr],
                         "centroid_hz": float(np.average(centroid[mask], weights=w)),
                         "band_energy_pct": dict(zip(LABELS, (100 * bandpower[:, mask].sum(axis=1) / w.sum()).tolist()))})
    attack = []
    for fraction in [.1, .9]:
        attack.append(float(times[np.flatnonzero(rms[:rms.argmax()+1] >= rms.max()*fraction)[0]]))
    metrics = {"file": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
               "sample_rate_hz": sr, "channels": info.channels, "format": info.format, "subtype": info.subtype,
               "frames": len(x), "duration_s": len(x) / sr, "peak_dbfs": float(db(peak)),
               "rms_dbfs": float(db(total_rms)), "crest_db": float(db(peak / max(total_rms, EPS))),
               "dc_offset": float(x.mean()), "samples_at_or_above_0_999": int(np.sum(abs(channels) >= .999)),
               "peak_sample_time_s": float(np.argmax(np.max(abs(channels), axis=1)) / sr),
               "max_rms_time_s": float(times[rms.argmax()]), "energy_times_s": quantiles,
               "first_50ms_energy_pct": float(100 * energy[min(len(x)-1, round(sr*.05))]),
               "first_100ms_energy_pct": float(100 * energy[min(len(x)-1, round(sr*.1))]),
               "rms_attack_10_to_90_s": attack,
               "four_times_oversampled_peak_dbfs": float(db(np.max(abs(signal.resample_poly(channels, 4, 1, axis=0))))),
               "active_minus40db_s": [float(starts[active[0]] / sr), float(min(len(x), starts[active[-1]] + win) / sr)],
               "centroid_energy_weighted_hz": float(np.sum(exactfreq * exactpower) / exactpower.sum()),
               "rolloff95_energy_weighted_hz": float(np.sum(rolloff * weights)),
               "flatness_energy_weighted": float(np.sum(flatness * weights)),
               "zero_crossing_rate": float(np.mean(np.diff(np.signbit(centered)) != 0)),
               "band_energy_pct": dict(zip(LABELS, bandpct.tolist())),
               "welch_spectral_peak_bins_hz": [float(wf[i]) for i in spectral_peaks],
               "novelty_candidates": events, "tail_energy_fit": decay, "thirds": segments,
               "pitch_rate_0_9_to_1_1_duration_s": [len(x) / sr / 1.1, len(x) / sr / .9]}
    return metrics, (x, sr, times, rms, freq, st, power, centroid, bandpower, edc)


def plot(path, out, data):
    x, sr, times, rms, freq, st, power, centroid, bandpower, edc = data
    fig, axes = plt.subplots(4, 1, figsize=(12, 12), constrained_layout=True)
    fig.suptitle(path.stem, fontsize=15)
    step = max(1, len(x) // 20000)
    axes[0].plot(np.arange(0, len(x), step) / sr, x[::step], lw=.45, alpha=.75, label="PCM amplitude")
    axes[0].plot(times, rms, color="darkorange", label="20ms RMS")
    axes[0].plot(times, -rms, color="darkorange")
    axes[0].set(ylabel="Amplitude", xlim=(0, len(x)/sr))
    axes[0].legend(loc="upper right")
    specdb = 10 * np.log10(power / max(power.max(), EPS) + EPS)
    mesh = axes[1].pcolormesh(st, freq, specdb, vmin=-75, vmax=0, shading="auto", cmap="magma")
    axes[1].set(yscale="log", ylim=(40, sr/2), ylabel="Frequency (Hz)")
    fig.colorbar(mesh, ax=axes[1], label="dB relative to maximum STFT bin")
    for row, label in zip(bandpower, LABELS):
        axes[2].plot(st, 10 * np.log10(row / max(bandpower.max(), EPS) + EPS), label=label)
    axes[2].set(ylim=(-65, 3), ylabel="Band energy (relative dB)")
    axes[2].legend(ncol=3, fontsize=8)
    axes[3].plot(times, db(rms / rms.max()), label="RMS envelope / own maximum")
    axes[3].plot(np.arange(len(x))/sr, edc, label="Remaining-energy decay")
    axes[3].set(ylim=(-65, 3), ylabel="Relative dB", xlabel="Time (seconds)")
    axes[3].legend()
    fig.savefig(out, dpi=140)
    plt.close(fig)


def main(args):
    args.output.mkdir(parents=True, exist_ok=True)
    results, comparison = [], []
    originals = sorted(args.source.glob("*.wav"))
    assert len(originals) == 4, "Expected the four extracted DS2 power WAVs, not arbitrary source content"
    for path in originals:
        metrics, data = analyze(path)
        results.append(metrics)
        plot(path, args.output / (path.stem + ".png"), data)
        assert np.isfinite(data[0]).all() and metrics["duration_s"] > 0
        assert .99 < sum(metrics["band_energy_pct"].values()) / 100 < 1.01
        print(json.dumps(metrics, indent=2))
    if args.compare:
        for path in sorted(args.compare.iterdir()):
            if path.suffix.lower() in (".wav", ".ogg", ".flac"):
                metrics, _ = analyze(path)
                comparison.append(metrics)
    output = {"method": "20ms RMS/5ms hop; zero-padded Hann STFT 2048/5ms hop; exact whole-file FFT bands/centroid with DC removed; Welch8192 peaks; 4x oversampled peak estimate; no loudness normalization",
              "limitations": ["No listening performed by this script", "No original isolated stems or plugin chain recoverable",
                              "Tail-energy fit is not room RT60", "RMS is not perceptual LUFS", "Novelty candidates are not proven separate hits"],
              "ds2": results, "project_comparison": comparison}
    (args.output / "measurements.json").write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    # At equal sample rate, normalized correlation can reveal reused recordings.
    correlations = []
    for i, first in enumerate(originals):
        for second in originals[i + 1:]:
            a, sa = sf.read(first); b, sb = sf.read(second)
            if sa != sb or a.ndim != 1 or b.ndim != 1:
                continue
            a, b = a - a.mean(), b - b.mean()
            c = signal.correlate(a, b, mode="full", method="fft") / (np.linalg.norm(a) * np.linalg.norm(b))
            at = int(np.argmax(abs(c)))
            correlations.append({"a": first.name, "b": second.name, "max_abs_normalized_correlation": float(abs(c[at])),
                                 "lag_s": float((at - len(b) + 1) / sa)})
    (args.output / "cross_correlations.json").write_text(json.dumps(correlations, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--deps", type=Path)
    parser.add_argument("--compare", type=Path)
    main(parser.parse_args())
