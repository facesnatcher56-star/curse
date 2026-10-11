"""Known-signal checks; temporary numeric test WAVs never enter game assets."""
import sys
import tempfile
from pathlib import Path
if "--deps" in sys.argv:
    sys.path.insert(0, sys.argv[sys.argv.index("--deps") + 1])
import numpy as np
import soundfile as sf
from analyze_power_audio import analyze

with tempfile.TemporaryDirectory(prefix="curse-dsp-check-") as folder:
    sr = 22050
    path = Path(folder) / "known.wav"
    t = np.arange(sr) / sr
    sf.write(path, .5 * np.sin(2 * np.pi * 200 * t), sr, subtype="PCM_16")
    m, _ = analyze(path)
    assert m["duration_s"] == 1 and m["channels"] == 1
    assert abs(m["peak_dbfs"] + 6.0206) < .01
    assert abs(m["rms_dbfs"] + 9.0309) < .01
    assert abs(m["centroid_energy_weighted_hz"] - 200) < 1
    assert m["band_energy_pct"]["80-250 Hz"] > 99.9
    assert abs(m["energy_times_s"]["0.5"] - .5) < .002
    # Odd length, stereo input and Nyquist coverage exercise the other FFT branch.
    stereo = np.column_stack([.25 * np.sin(2 * np.pi * 6000 * t), .25 * np.sin(2 * np.pi * 6000 * t)])[:-1]
    sf.write(path, stereo, sr, subtype="PCM_16")
    m, _ = analyze(path)
    assert m["channels"] == 2
    assert m["band_energy_pct"]["4000-8000 Hz"] > 99.9
    assert abs(sum(m["band_energy_pct"].values()) - 100) < .001
    assert m["samples_at_or_above_0_999"] == 0
print("PASS: known sine levels, frequency, energy timing, mono/stereo, odd/even FFT and band coverage")
