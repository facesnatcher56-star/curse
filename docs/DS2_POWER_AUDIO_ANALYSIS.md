# DS2 power audio: measured reference and replacement brief

Analyzed 2026-10-11. Scope: the four original WAVs associated with Brutal Attack and Take Aim in the installed `Sound2.ds2res`, their SED playback settings, `Logic.ds2res` sound aliases and effect wrappers, and ten existing Curse recordings. Original audio remains in a temporary reference directory, not game assets or Git.

## What this establishes—and what it does not

This is **signal analysis plus visual inspection of waveform/spectrogram plots**, not a claimed listening evaluation. No direct audio-listening/perception tool was available in this session. Terms such as thump, air, crunch and rumble below are **suggested layer roles inferred from measurements**, not identification of the actual recording sources.

We can measure the finished files precisely. We cannot recover their original stems, microphone, synthesizer, effects chain, exact EQ/compressor settings or room impulse response. A recording's full duration is not an animation lockout. Frequency centroid is spectral brightness, **not musical pitch**; noisy impacts have no reliable single fundamental note. Broad spectral peaks are not proof of a tuned oscillator. File levels are not the game's final perceived loudness.

## Measured overview

All four originals are **22,050 Hz, mono, 16-bit PCM WAV**. The frequency ceiling is 11,025 Hz. None reaches full scale in its decoded samples or the four-times-oversampled peak estimate. No normalization was applied before measurement.

| Original event | File duration | Sample peak | Whole-file RMS | Crest factor | 50% / 90% energy reached | Spectral centroid |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Brutal impact | 2.423 s | -2.00 dBFS | -14.87 dBFS | 12.87 dB | 0.205 / 0.661 s | 750 Hz |
| Take Aim charge | 1.056 s | -2.10 dBFS | -16.92 dBFS | 14.82 dB | 0.218 / 0.446 s | 4,025 Hz |
| Take Aim fire | 1.287 s | -4.52 dBFS | -17.45 dBFS | 12.93 dB | 0.240 / 0.448 s | 1,083 Hz |
| Take Aim impact | 2.167 s | -3.30 dBFS | -12.28 dBFS | 8.98 dB | 0.598 / 1.171 s | 554 Hz |

RMS includes the complete file, including its tail; differences are not LUFS or a loudness-matched listening comparison. Crest factor is peak-to-RMS ratio: the smaller Take Aim impact value agrees with its sustained dense envelope, not proof of a particular compressor.

### Where the energy is

Percentages are integrated whole-file FFT energy after removing DC. Bands partition the spectrum, including an explicitly separate sub-20 Hz band. These are **energy shares, not mixer fader settings or perceived loudness shares**.

| Event | Below 20 Hz | 20–80 Hz | 80–250 Hz | 250–1,000 Hz | 1–4 kHz | 4–8 kHz | 8–11.025 kHz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Brutal impact | 3.7% | 54.5% | 18.8% | 5.9% | 9.4% | 6.6% | 1.1% |
| Take Aim charge | 1.7% | 17.6% | 14.2% | 2.4% | 14.4% | 31.2% | 18.5% |
| Take Aim fire | 0.7% | 43.4% | 18.4% | 13.2% | 14.3% | 7.9% | 2.1% |
| Take Aim impact | 1.9% | 59.0% | 18.8% | 9.0% | 7.0% | 2.7% | 1.6% |

The charge is the outlier: **49.7% above 4 kHz**. Both impacts are strongly low-frequency weighted: **73.3% and 77.8% in 20–250 Hz**. The Take Aim firing sound is also weighty, not merely a thin high-pitched string snap.

## 1. Brutal Attack impact

[Waveform, spectrum, band envelopes and decay](audio-analysis/s_pw_ft_brutalattack_hit.png)

Measured structure:

- Starts immediately; 10% of total energy arrives by 50 ms, 24.9% by 100 ms. The maximum 20 ms RMS window is centered at 75 ms. A brief onset and early body carry the attack, not a late blast.
- The first rise to 90% of maximum windowed RMS is around 45 ms. A later individual PCM peak at 205 ms does **not** imply delayed contact.
- Half the energy is delivered by 205 ms; 95% by 800 ms; 99% by 1.157 s. The remaining long tail extends beyond the main punch.
- Bass is broad and irregular. Strong Welch bins cluster around 38, 51, 59 and 78 Hz; these are not a single proven pitched note.
- High-frequency content dies away earlier than the bass. Time-resolved plots show the last third becoming almost exclusively low-frequency energy. That darkening tail is a major part of the weight.
- Remaining-energy decay between -5 and -25 dB spans 1.157 s, with an approximately -18.25 dB/s slope and R² 0.998. This is a descriptive designed-sound decay, **not measured room RT60**.

Replacement design inference: combine a short, readable recorded contact texture with a much heavier low-frequency body and a progressively darkened rumble tail. A bright metallic hit alone will not match; nor will simply making the same short hit louder. The high-frequency contact should clear quickly so the continuing bass does not mask the next attack.

Suggested brief using licensed/owner recordings: contact texture in roughly the first 20–80 ms; strong body during the first 0.2–0.4 s; most energy gone within 0.8–1.2 s; a quiet dark tail allowed to extend toward 2.4 s. These are production targets inferred from the reference, not recovered original layer timestamps. Trigger the beginning on weapon contact, not on the button press, and do not delay damage for the audio peak.

## 2. Take Aim charge

[Detailed analysis plot](audio-analysis/s_pw_rg_takeaim_charge.png)

Measured structure:

- A roughly 0.1 s swell into the main body: maximum 20 ms RMS is at 150 ms, with the first 90%-of-maximum crossing around 115 ms.
- It is **not a continuous crescendo all the way to release**. The envelope is strongest early and then fades, with a smaller energy rise around the mid-0.3 s region visible in the graph.
- 90% of energy is delivered by 446 ms, 95% by 517 ms and 99% by 654 ms, despite the 1.056 s total duration. This fits a short charge presentation followed by a tail rather than a one-second mandatory cast.
- Nearly half its spectral energy lies above 4 kHz, but about 31.8% is still in 20–250 Hz. A pure hiss would lose its foundation.
- Spectral flatness is substantially higher than the other three files, consistent with a more broadband/noise-like texture. It does not establish whether the source was air, filtered noise, reversed material or a processed recording.
- The remaining-energy -5 to -25 dB interval is 427 ms; fitted slope about -46.65 dB/s.

Replacement inference: a brief recorded air/friction texture with a low body, swelling early and then thinning away. A delicate tonal accent may help, but no exact note or original oscillator is established. Do not substitute a long rising whistle or sustain it for the entire armed wait.

Timing: DS2's wrapper plays `power_takeaim_charge` on the caster at the charge effect. The visible bow-hand particle gather is about 0.4 s; the audio tail can legitimately outlast those particles. In Curse, charge is a separate event from indefinite stored-power arming; its future audio hook should fire once when the actual powered draw begins, not every frame while the aura exists.

## 3. Take Aim firing

[Detailed analysis plot](audio-analysis/s_pw_rg_takeaim_fire.png)

Measured structure:

- Maximum windowed RMS at 220 ms; 90%-of-maximum RMS first crossed around 100 ms. Only 2.4% of its total energy is in the first 50 ms. The file has a small immediate onset followed by a wider body, not an isolated zero-time click.
- Half the energy by 240 ms; 90% by 448 ms; 99% by 627 ms. Much of the 1.287 s duration is a quiet tail.
- 61.8% of spectral energy is in 20–250 Hz. The low body is accompanied by midrange and upper-frequency texture; about 10% is above 4 kHz.
- Strong low-frequency bins cluster around 40–70 Hz. No stable musical pitch is established.
- -5 to -25 dB remaining-energy interval: 402 ms; slope about -50.98 dB/s.

Replacement inference: short physical release/string/contact texture plus a compact low whoosh/body, not a duplicate of the bright charge sound. A recordable bow/string layer would provide identity while the low body provides power. Keep the useful body around the first half-second and let the tail clear quickly.

Trigger at **arrow release**. Do not postpone projectile creation by 220 ms to align with the file's largest RMS window; DS2 starts the sample at the event and the sample's own envelope develops afterward. Charge and release tails may overlap; that is not a reason to make the cast wait for a sample to finish.

## 4. Take Aim impact

[Detailed analysis plot](audio-analysis/s_pw_rg_takeaim_hit.png)

Measured structure:

- Immediate audible-scale onset is suggested by the RMS envelope, followed by a **dense, uneven body lasting roughly 1.2 s**. This is not just a sharp arrow hit followed by a smooth quiet reverb tail.
- Half of total energy is not reached until 598 ms; 90% at 1.171 s, 95% at 1.228 s, 99% at 1.464 s. It retains much more later energy than Brutal's impact.
- The maximum 20 ms RMS window occurs at 1.192 s, but substantial energy exists from the beginning. The reported first 90%-of-maximum RMS crossing at 718 ms must not be misread as 718 ms of silence or delayed hit registration.
- About 77.8% of energy is in 20–250 Hz, with a modest upper contact/noise component. Spectral centroid is only 554 Hz.
- Bass remains active while upper detail thins out, then the body falls away rapidly after roughly 1.2 s. The late section is overwhelmingly low frequency.
- Several spectral-novelty candidates occur near 0.59–1.32 s. These identify changes in texture, not proven additional arrow contacts or isolated layers.
- Crest factor 8.98 dB is lower than the other originals; its waveform is dense over an extended interval. This could result from layered sources, shaping or compression, but the processing cannot be identified exactly.
- -5 to -25 dB remaining-energy interval: 775 ms; fitted slope about -28.70 dB/s, less linear than Brutal's decay (R² 0.983).

Replacement inference: a physical contact cue over a broad, sustained low impact/energy body, with irregular motion and a dark tail. Treating this as the same short arrow contact played at lower pitch would miss its central characteristic. A future deliberate modernization could shorten its dense body to reduce masking in crowds, but that would be a departure from the reference and needs owner approval.

## DS2 playback and event routing

Measured source files are not the whole final mix. Position, camera/listener, distance attenuation, other combat samples, effects/master gain, concurrent voices and the engine all influence what is heard.

Verified from the four corresponding `*_sed.gas` files:

- `min_playback_rate = 0.9`, `max_playback_rate = 1.1` for all four: about **-1.82 to +1.65 semitones**, changing duration as well as pitch.
- Maximum simultaneous samples: **2 per sound definition**, not a global two-voice limit.
- Brutal impact distance override: 7–30; Take Aim sounds: 6–30. These are DS2 game-space values; an identical numeric Godot distance does not prove an identical attenuation curve.
- `stereo_playback = false`; consistent with mono sources, but not proof of the complete output spatialization algorithm.

| Event | Nominal duration | Duration at playback-rate extremes |
| --- | ---: | ---: |
| Brutal impact | 2.423 s | 2.203–2.692 s |
| Take Aim charge | 1.056 s | 0.960–1.173 s |
| Take Aim fire | 1.287 s | 1.170–1.430 s |
| Take Aim impact | 2.167 s | 1.970–2.407 s |

`sound.gas` sets default falloff 6–30 and a `sound_latency` configuration of 100 ms. That is a configured mix-ahead value, **not measured end-to-end latency on this PC** and not an animation delay to copy.

Alias evidence in `sounddb.gas`:

- `power_brutal_attack_hit` → `s_pw_ft_brutalattack_hit` (line 3111).
- `power_takeaim_charge` → `s_pw_rg_takeaim_charge` (3189).
- `power_takeaim_cast` → `s_pw_rg_takeaim_fire` (3190).
- `power_takeaim_hit` → `s_pw_rg_takeaim_hit` (3191).

Important uncertainty: `ffx_take_aim.flick` requests **`power_take_aim_hit`**, whereas this sound database entry is **`power_takeaim_hit`**. The extracted database does not contain the former spelling. The WAV exists, but that mismatch means we should not assert that this wrapper definitely plays it in the original game without tracing engine alias handling, other overrides or a controlled original-game capture. It does not prove the impact is silent either.

Brutal's impact wrapper plays the impact sound on the caster; Take Aim charge/fire also play on the caster, with its impact wrapper requesting playback at the target. Brutal's pre-launch and charge wrappers themselves do not issue a PlaySound. The database also contains generic melee/ranged power-charge aliases, so these four files alone should **not** be called an exhaustive recording of everything that can sound during activation.

## Comparison with Curse's available recordings and implementation

- Current `sword_hit.ogg` / `sword_hit_2.wav` are 0.571 / 0.260 s, centroids approximately 2,388 / 2,321 Hz, and deliver 90% of their energy by 124 / 119 ms. Compared with the original power impacts, they are shorter, brighter and far less bass-weighted. Pitching them down a little cannot create the missing long body/tail.
- `leap_land.wav` has 97.8% of its energy in 20–80 Hz and a 34 Hz centroid. It is a possible **low foundation only**, not a complete impact replacement: it lacks the upper contact textures and much of the 80–250 Hz body. It is also already quite loud at -8.16 dBFS whole-file RMS; layering it without attenuation risks muddying the mix.
- `fireball_impact.wav` has a roughly 758 Hz centroid, a fast initial body and more energy in 80–250 Hz than the original impacts. Its broad structure is closer than the sword-hit clips in some respects, but source identity, envelope and spectral balance differ. It is only a candidate layer, not a declared sound match.
- The two fireball-cast recordings are predominantly low-frequency (about 95% below 250 Hz) and cannot alone supply Take Aim charge's bright broadband texture. The sword-miss clips mainly occupy 250–1,000 Hz and are also not substitutes for that high-frequency component.
- **Headroom finding:** the existing `sword_hit.ogg` decodes to a sample peak of **+2.47 dBFS**. Floating-point lossy decoding can produce values above nominal full scale; this does not by itself prove existing audible clipping. It does require gain/headroom checks, particularly when the current Sfx helper adds heavy-hit gain and several sounds overlap. No asset or mixer gain was changed during this analysis.
- Curse's `Sfx.sample` uses a non-positional `AudioStreamPlayer` and normally multiplies pitch by a random 0.95–1.05. It does not currently reproduce the DS2 per-definition two-voice limits or 6/7–30 distance behavior. The body-impact-specific global voice guard is a different mechanism.
- Static inspection found no dedicated Take Aim charge/fire/impact audio family/hook. Actor hits use existing sword recordings. Therefore the new bow/body **visual** effects do not mean that the power audio has already been brought into parity.

Recommendation: build four distinct replacement events with owner/licensed recordings, using these measured envelopes and frequency roles as targets. Keep event triggers separate from audio duration, preserve headroom, and test overlap at combat density. There is no need for a new general-purpose audio framework to accomplish this; the existing Sfx system can gain small, targeted event families/spatial playback where needed. **No replacement was generated or integrated in this task.**

## Reproducibility, checks and artifacts

- Tool: [`tools/analyze_power_audio.py`](../tools/analyze_power_audio.py). Dependencies installed into an isolated temporary directory, not the game's runtime or system site-packages: NumPy, SciPy, Matplotlib; existing SoundFile handles decoding.
- Full measurements, SHA-256 source identities, phase statistics, oversampled peak estimates, candidate spectral changes and comparison recordings: [`measurements.json`](audio-analysis/measurements.json).
- Six pairwise full-waveform correlations: [`cross_correlations.json`](audio-analysis/cross_correlations.json). Maximum absolute normalized correlations range 0.092–0.196 at their best lags. None looks like a straightforward identical full recording shifted in time; this test cannot exclude shared layers, resampled/pitched reuse or related processing.
- Level/envelope analysis: 20 ms RMS windows every approximately 5 ms. Spectrogram: Hann-windowed 2,048-sample STFT (92.9 ms at 22.05 kHz), zero-padded at boundaries; frequency-bin spacing 10.77 Hz. Thus spectrogram onset localization is smeared across a window; exact sample/energy times come directly from PCM instead.
- Integrated bands and centroid: whole-file one-sided FFT after DC removal, including complete onset; spectral peak candidates use Welch spectra with up to 8,192-sample windows. Phase-third/band-envelope statistics use the coarser STFT and should not be confused with exact global band percentages.
- Spectral/envelope/energy analysis uses the channel average for stereo comparison files; overall RMS/peak use all channels. The four DS2 originals are mono, so no downmix ambiguity affects their measurements. Stereo phase cancellation can affect comparison spectra and would require channel-separated review before production mixing decisions.
- A 4× polyphase oversampling peak estimate checks intersample headroom; it is not a certified broadcast true-peak measurement. No claimed LUFS, original compressor ratio, room RT60 or perceptual material classifier was invented.
- Focused known-signal tests passed: sine-wave level/RMS, spectral centroid, energy timing, band coverage, mono/stereo and odd/even FFT input lengths. All four real reference files decoded and generated finite measurements/graphs. All four graphs were visually inspected. Godot bridge confirmed the canonical project path and absence of an imported Brutal WAV.
- No gameplay changed, no interactive game window launched, no production save touched, no original sounds imported, no commit/push. Gameplay regression suites were not run because this task changes only offline research tooling/documentation.

Example command (substitute the actual temporary dependency path):

```powershell
python tools/analyze_power_audio.py C:/Users/lloyd/AppData/Local/Temp/curse-ds2-audio-reference docs/audio-analysis --deps C:/Users/lloyd/AppData/Local/Temp/curse-audio-analysis-deps --compare assets/audio
python tools/test_power_audio_analysis.py --deps C:/Users/lloyd/AppData/Local/Temp/curse-audio-analysis-deps
```
