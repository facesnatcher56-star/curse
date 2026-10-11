# Layered power audio — first audition pass, 2026-10-11

Owner requested a best-effort layered implementation after the [DS2 audio study](DS2_POWER_AUDIO_ANALYSIS.md).
Four new composites are now in the game, derived **only** from recordings already present in `assets/audio`.
No DS2 sample, new oscillator or generated noise was included. Original source/licence obligations remain;
the owner-supplied fireball/landing source details still need documenting before release.

## Result and event timing

- **Brutal hit:** recorded contact grit, a lower body, bass and a dark tail; replaces the normal sword-hit cue on a landed Brutal Attack.
- **Take Aim charge:** filtered upper-frequency texture over a small low body; plays once as the powered draw begins, not when the ability waits armed without a target.
- **Take Aim fire:** short release texture plus a weightier body, triggered at arrow creation, independent of the charge file's remaining tail.
- **Take Aim hit:** recorded contact plus a sustained bass/body layer, triggered by the resolved enemy hit. Misses and blocks do not play the power impact.

No damage, interruption, power cost, cooldown, targeting or animation timing was changed. Normal shots and attacks retain their prior behavior. A miss can retain Brutal and produce its existing air-swing sound. Take Aim still spends at release even if its projectile later misses. Terrain does not pretend to be a successful enemy power impact.

Preview order: **Brutal hit → Take Aim charge → Take Aim fire → Take Aim hit**, with half-second gaps.
[`curse_power_preview.wav`](audio-analysis/curse_power_preview.wav) is the unspatialized baked-cue preview;
actual gameplay also applies pitch, distance, gain and the power bus. It is not a recording of the final in-game mix.

## Tuning and limits

| Cue | Duration | 90% energy by | Approximate centroid |
| --- | ---: | ---: | ---: |
| Brutal hit | 2.42 s | 0.667 s | 726 Hz |
| Take Aim charge | 1.06 s | 0.419 s | 3,654 Hz |
| Take Aim fire | 1.29 s | 0.429 s | 1,130 Hz |
| Take Aim hit | 2.17 s | 1.051 s | 467 Hz |

These approach the reference timing/brightness but are **not exact spectral, loudness or perceptual matches**.
The available recordings limit the texture; Take Aim impact remains somewhat shorter in its dense body than the original.
No direct audio-listening/perception tool was available to the agent, so subjective quality awaits the owner's audition.

- WAVs: 44.1 kHz mono PCM16, approximately -6 dBFS four-times-oversampled peak target.
- Offline processing: pitched/filtered recordings, bounded macro-envelope shaping, gentle soft saturation, final peak scaling and click-free edges. Relative gains/recipes live in the rebuild script.
- Runtime: `AudioStreamPlayer3D`; playback rate 0.9–1.1, distance 30, reference distance 7 for Brutal / 6 for Take Aim. Godot's attenuation is a native approximation, not DS2's confirmed curve.
- Runtime gain: charge -4 dB; other cues -1 dB, with no near-source gain boost beyond the authored cap.
- At most two nonretiring voices per cue; a new contact replaces the oldest tail. A 45 ms duplicate-event guard prevents simultaneous duplicate bursts.
- A dedicated `PowerFx` bus routes to Master with a -4 dB limiter ceiling. This guards **power-cue overlap only**; it does not certify headroom for the entire game's existing mixed output or fix the pre-existing sword OGG overshoot.
- Stored arming is silent; no unverified looping aura sound or Brutal activation sound was invented.

## Implementation and rebuild

`game/skills/power_audio.gd` owns spatial playback/concurrency. `Sfx.power` reuses the existing enable switch, event guard and diagnostic log. `Actor.receive` selects successful contact cues after miss/block exits, replacing rather than doubling normal sword impact. Cutter's draw/release code supplies its two phase events. Four pre-baked WAVs avoid per-frame DSP or live multilayer mixing in combat.

Rebuild with `python tools/build_power_audio.py --deps C:/Users/lloyd/AppData/Local/Temp/curse-audio-analysis-deps`.
The script reads only `leap_land.wav`, `fireball_impact.wav`, `sword_hit_2.wav`, `sword_miss_2.wav`.
Source hashes and final measured durations/peaks/energy timing are in [`curse_power_mix.json`](audio-analysis/curse_power_mix.json).
NumPy/SciPy/SoundFile are offline dependencies only; the game does not require Python.

## Verification

- Focused `poweraudio` test passed headlessly and visibly on **monitor two** with sequential playback of all four final cues. The visible run completed with an empty stderr log.
- Tests cover actual draw/release/contact hooks, no audio while waiting armed, no draw-loop restart, no shot on cancellation, no impact on miss/block, no doubled sword sound, the sound-effects switch, per-cue concurrency, spatial/range/pitch settings, the limiter and imported durations.
- Related `brutal`, `archer`, `swordsound`, `fireballsound` regressions passed. Import completed successfully; generator peak/finite-sample checks and `git diff --check` passed. The full suite was not run.
- Canonical project and limiter properties were checked through Godot MCP. No production save touched, no automatic commit or push.

Next adjustment should be based on listening in a normal encounter: contact clarity, bass amount, charge brightness, impact-tail length and mix level. We should tune these four recipes rather than create a second overlapping power-audio system.
