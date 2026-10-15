# Audio credits

## Power cast and impact cues (Lane K, 2026-10-15)

`powers/whirling_strike_cast.wav`, `powers/whirling_strike_hit.wav`, `powers/staggering_cast.wav`, `powers/staggering_hit.wav`,
`powers/war_cry_cast.wav` and `powers/war_cry_hit.wav` are layered, pitched and filtered composites of the existing recordings listed
below. Rebuild with `tools/build_power_cues.py` (numpy and soundfile only). No new sources were downloaded and no DS2 audio is used.
Their licences are the same as the sources' licences, which are still unverified in this file (see the notes above).

## Layered power cues (owner requested, 2026-10-11)

`powers/brutal_hit.wav`, `powers/take_aim_charge.wav`, `powers/take_aim_fire.wav` and
`powers/take_aim_hit.wav` are filtered, pitched and enveloped composites of the existing
`leap_land.wav`, `fireball_impact.wav`, `sword_hit_2.wav` and `sword_miss_2.wav` recordings below.
Rebuild with `tools/build_power_audio.py`; layer recipes are in that script and source hashes
in `docs/audio-analysis/curse_power_mix.json`. No original DS2 audio is included and no oscillator/noise
source was synthesized. All source licence/attribution obligations still apply; owner-supplied
recordings whose source/licence is not documented below still need that information before release.

## Source recordings

- `sword_hit.ogg`: "slash2" by wenpire, Freesound #574820 (https://freesound.org/s/574820/). Check the licence shown on that page and keep its attribution requirements.
- `sword_hit_2.wav`: "slash" by qubodup, Freesound #442903 (https://freesound.org/s/442903/). Check the licence on that page too.
- `sword_miss_1..4.wav`: the four swings cut from "swoosh" by porkmuncher, Freesound #263595 (https://freesound.org/s/263595/). Check the licence on that page.
- `fireball_cast_1/2.wav` (cut from `castfireball.flac`) and `fireball_impact.wav`: supplied by the project owner; add their source and licence here.
- `leap_land.wav` ("warrior landing deep bass impact"): supplied by the project owner; add its source and licence here.
