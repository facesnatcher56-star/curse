# Dungeon Siege 2: combat and loot, from the game's own data

Everything below was read out of the installed game, not recalled from memory or wikis. `Logic.ds2res` (2,817 files), `Objects.ds2res` and `World.ds2map` are "Tank" archives (zlib-compressed 16 KB chunks, data base offset 828). Inside are the plain-text GAS/Skrit files that *are* the rules: `rules.skrit` (the damage code), `formulas.gas`, `rules.gas`, `active_skills.gas`, `passive_skills.gas`, the item templates, `pcontent.gas` (affixes) and `pcontent_macros.gas` (drop tables).

Things that live in the C++ engine and are **not** in the data are listed in [section 13](#13-what-the-data-does-not-tell-us). Where I'm inferring rather than reading, I say so.

---

## 0. How it plays, in twelve lines

1. You lead a **party** (a hero plus recruited characters; the XP-share rules go up to four leveling members, plus pets and summons that don't level). You click to move and attack; the others fight on AI "limited" orders and auto-defend and auto-heal.
2. There are four **class skills** that level independently from use: **Melee, Ranged, Nature Magic, Combat Magic**. Using a bow levels Ranged, a firebolt levels Combat Magic. Any character can mix them.
3. Combat is **real-time auto-attack**. There is no accuracy roll: a hit lands unless the target **dodges** or **blocks** it.
4. Per-hit damage is *weapon roll + Strength/Dexterity bonus*, optionally doubled by a critical, then **cut by the target's armor** using a single ratio formula (§4).
5. **Spells** are not weapon-based. Damage and mana cost both scale linearly with **Intelligence**, capped by the spell tier (§8).
6. Active skills are called **powers**. They recharge by *damage dealt*, not seconds (§7.3).
7. Monster stats are a pure function of **monster level** (§9). Difficulty is not a damage multiplier; it is a **jump in monster level**: Mercenary about 0–40, Veteran about 40–64, Elite about 64–85.
8. Monsters give XP **as you damage them**, in proportion to the fraction of their life you removed, with penalties for level gaps (§10).
9. Loot is **rolled on death from a per-tier table** (weak/normal/strong/miniboss) keyed to monster level. Most kills drop nothing. Magic find only scales the rarity weights (§11).
10. Gear is **level-gated**: to wield an item you need your class skill at roughly `item_level - 2`.
11. Item power is **very formulaic**. Weapon damage, armor and monster stats all hang off the same "character damage per second = 8 + 2 × level" yardstick.
12. Two item types are fixed-stat: **uniques** (198 found) and **set pieces** (22 sets, 105 pieces). Everything else is a base item plus 0–2 random prefix/suffix.

---

## 1. Characters and stats

### Class skills and level
* Skills in `formulas.gas`: `Uber` (character level, max 100), `Melee` ("Fighter"), `Ranged` ("Archer"), `Nature Magic`, `Combat Magic`, each max 100. Strength/Intelligence/Dexterity max 300 (1000 with bonuses).
* Per class, the weights used when class experience feeds stat growth (`skill_influences`):

| Class | STR | DEX | INT |
| --- | --- | --- | --- |
| Melee | **3** | 1 | 1 |
| Ranged | 1 | **3** | 1 |
| Nature / Combat Magic | 1 | 1 | **3** |

The weapon-design notes in `wpn_bases.gas` assume `STR = 3 × class level + 10`, so a pure fighter at level 30 has about 100 STR.

### Life and mana (`rules.gas`, `rules.skrit` `CalculateMaxLife$`/`CalculateMaxMana$`)
```
max life = (0.50·STR + 0.39·DEX + 0.23·INT) × 5 × (1 + Fortitude%)
max mana = (0.01·STR + 0.12·DEX + 0.87·INT) × 5 × (1 + Brilliance%)
```
(The comment block in the file quotes older constants; the numbers above are the live ones.)
Example: pure level-30 fighter (STR 100, DEX 40, INT 40) ≈ **374 life** before gear and Fortitude. That matches the design note "fighter health = 50 + 10.6 × level".

### Regeneration
`RegenerateLife$`/`RegenerateMana$`: each tick adds `dt × unit × maxValue / 100`. Heroes have `life_recovery_unit = mana_recovery_unit = 1.0`, i.e. about **1% of max per second** at baseline. Gear affixes (`of Mending` etc.) raise it.

### Races (`heroes_ds2.gas`)
Starting stats are the third number in `strength = 0, 0, 12` (my reading; the meaning of the first two numbers is engine-side).

| Race | STR / DEX / INT | Extras |
| --- | --- | --- |
| Human | 12 / 11 / 11 | +10% magic find, +2 bonus skill points |
| Elf | 10 / 11 / 13 | starts with Critical Strike, Brilliance, Brutal Attack, Energy Orb |
| Dryad | 8 / 14 / 12 | 10% death resistance; starts with Natural Bond, Dodge, Gravity Stone |
| Half-giant | 16 / 8 / 10 | starts with Fortitude 2 |

### Downed and dead (`combat_constants`)
* At 0 life a character goes **unconscious**; they die if life falls `death_threshold = 0.66` (as a fraction of max life, my reading) below zero.
* They stay down at least **5 s**, and stand up only after regenerating to **40% life**, and only when **no enemy is within 8 m**.
* Resurrection exists as spells (Minor, Lesser, Resurrect, Greater, Master; mana `11 × magic level + 40`) and as scrolls.

---

## 2. What one swing does: the whole pipeline

Source: `rules.skrit` `CalcCanHit$` → `GetDamageRangeHelperMain$` → `CalculateDamage$` → `DamageGoMeleeMultiplier$` → `DamageGo$`. Melee, ranged and "powers" share this path; spells have their own copy (§8).

### Step 1: does it connect? (`CalcCanHit$`)
No base accuracy. Only:
* **Dodge**: Ranger skill *Dodge* (4% at L1 → 40% at L20, melee **and** ranged) plus any `chance_to_dodge_hit` gear.
* **Miss**: only from debuffs (negative chance-to-hit alterations).
* Ranged shots also roll an **aiming error** (`CalcAimingError$`).

### Step 2: weapon damage range (`GetDamageRangeHelperMain$`)
**Melee hero:**
```
min = weaponMin + bonusMinMelee ;  max = weaponMax + bonusMaxMelee
strBonus = 0.2 × max(STR, 10)
min += 0.75 × strBonus ;  max += 1.25 × strBonus
if two-handed:  ×(1 + Overbear%)          (8% … 50%)
if dual-wield:  min,max = average of both weapons, then ×(1 + DualWield%)   (8% … 70%)
× (1 + melee-damage-% affixes)            (Cruel +10…56%, etc.)
```
**Ranged hero:** same shape with `0.2 × DEX`, then ×(1 + Biting Arrow%) for bows and crossbows only (not thrown), then ranged-damage-% affixes.
**Monsters:** weapon damage **plus** the monster's own `[attack]` damage; they get no STR/DEX bonus.
Floors: `min ≥ 1`, `max ≥ min`.

### Step 3: roll, add elemental, apply armor (`CalculateDamage$`)
```
1. Toughness (victim): min and max reduced by 3% … 26%   (physical attacks only)
2. damage = uniform(min, max)
3. + "damage to type" bonus if the weapon names the victim's template
4. + added elemental damage (fire, ice, lightning, death):
      flat amount × (1 − victim's resistance to that element)   ← added BEFORE armor
5. armor:  damage × min(8 + 2·attackerLevel, armor) / armor     (if armor ≠ 0)
6. level gap (attackerLevel − victimLevel):
      < −4 → ×0.75     < −6 → ×0.50     < −8 → ×0.25
7. floor at 1
```
Step 6 applies in **both directions**: a hero more than 8 levels below a monster deals ×0.25, and a monster more than 8 levels below a hero also deals ×0.25. Over-leveled enemies are harmless, under-leveled heroes are nearly toothless.
Because step 5 is a ratio, **armor at or below `8 + 2L` of the attacker does nothing**, and every point above it cuts damage proportionally. A level-30 attacker faces on-level gear of `16 + 4L = 136` armor, so about **50% of damage gets through** (`68 / 136`).
Monster armor: `1.333 × (8 + 2L) × (1 + 0.004L)`. A hero hitting a same-level monster therefore deals about **75% at low level, drifting to ~67% at L30** (`68 / 102`) because of the `0.004L` term. The power-tuning comments call this "Expected Damage Dealt = 0.75".

### Step 4: criticals, blocks, power multipliers (`DamageGoMeleeMultiplier$`)
* **Block** (melee or ranged, shield required): `shield block % + Barricade bonus` (2% … 20% each for melee and ranged). A blocked hit deals **nothing** and awards no XP. With *Rebuke* the blocker counter-hits for `0.4 … 2.5 × melee level`.
* **Critical:** chance = `Critical Strike/Shot` (8% … 50%) + gear. A crit is a **second, separately rolled hit added on top** × `(1 + crit-damage bonus)`. Base is therefore **200%**. *Deadly Strike* (melee) and *Mortal Wound* (bows/crossbows) raise it to **224% … 350%** (`+(X − 200)/100` on the multiplier).
* **Powers never crit** (the check is skipped while `UsingPowerDamage`). *War Cry* forces the next 8/12/15 hits to crit.
* Powers pass a `damageMultiplier` that scales the final number.

### Step 5: applying it (`DamageGo$`)
In order:
1. **Party sacrifice**: a designated member absorbs a fixed % of damage meant for another.
2. Spell hit → **Absorption** skill heals/mana-refunds the caster.
3. Damage-class objects (puzzle-like targets) check the weapon type is allowed.
4. **Difficulty factor**: in this build all six difficulty multipliers are **1.00**. The old 0.8/1.25 values are commented out.
5. **Resistance**: victim's resistance to the *weapon's damage type* is applied to the total. Heroes are **capped at 80%** (`max_resistance`). Monsters can exceed 100%: above 100% the hit **heals** them (a heal effect plays). *Survival* adds fire/ice/lightning resistance for heroes.
6. **Transfer Injury** (nature skill): a share of damage is redirected to your summon.
7. Min-damage threshold: if the target has a `damage_threshold`, hits below it do nothing.
8. Apply life change. **Gibs** when the killing damage exceeds the target's `gib_min_damage` and `gib_threshold × maxLife` (powers always gib).
9. **Life steal / mana steal**: `newLife = life + flatBonus + steal% × damageDealt`.
10. **Reflect** (gear and auras): reflected damage hits the attacker and even awards the victim XP.
11. Aggro is added to the victim and its friends by damage type; kills notify nearby monsters.

### Weapon speed
Attack loop duration = `reload_delay × (1 + reload bonus) + base attack-animation length`, then `÷ (1 + Alacrity%)` (Alacrity 3% … 25%). The animation lengths themselves are in animation data I did not extract. `reload_delay` per weapon: 1H melee **0.67**, 2H melee **0.9**, bow **0.625**, crossbow **0.9**, thrown **0.73**, cestus **1.0**, 2H staff **0.9**.

---

## 3. Defense, resistances, blocking

| Source | Effect |
| --- | --- |
| Armor (items) | Sum of worn `defense` plus affixes. Then ×(1 + *Reinforced Armor* 4…35%), plus *Barricade* (shield armor +20…120%), then ×(1 + armor-% bonuses). Heroes have **0** base armor. |
| Armor tuning (`amr_bases.gas`) | `defense = class mult × slot coefficient × (16 + 4 × item_level)`. Class mult: fighter 1.0, ranger 0.8, mage 0.6. Slot: body 0.50, helm 0.20, shield 0.20, gloves 0.15, boots 0.15. A fighter in a full non-shield set has exactly `16 + 4L`. |
| Resistances | Types: fire, ice, lightning, death, melee, ranged, physical, magical. Hero cap **80%**. Affix tiers reach 25% per element, 14% melee, 20% ranged. |
| Dodge | Ranger *Dodge* skill (4…40%) plus gear. |
| Block | Shield only. Base from the shield's affixes (up to 20%) plus Barricade (up to 20%). Monsters can also block combat/nature magic through `[defend]` fields. |
| Toughness | Melee skill; −3…26% on physical damage taken. |
| Regeneration | ~1% max life per second baseline (§1). |
| Potions | Used instantly, but the healing is spread **over 12 s** (`restore_duration = 12`). |

---

## 4. Status effects and crowd control

| Effect | Source and numbers |
| --- | --- |
| **Stun** | *Smite* (2H hits): 5…50% chance, 1…2 s. *Staggering Blow*: radius 2.75…4 m, **6/8/10 s**. *Thunderous Shot*: 6/8/10 s. *Whirling Strike* and *Repulse*: 1.5 s. *Aether Blast*: 5 s. |
| **Freeze** | *Freezing* skill: chance `skill × damage / (0.75 + 0.4·INT)`, 1…2 s. Weapon freeze affix: 1.0 s (`weapon_freeze_duration`). *Circle of Frost*: 12/15/18 s. |
| **Ignite** | *Ignite* skill: chance `skill × damage / (1.2 + 0.6·INT)`, 3 s DoT of `0.08…0.5 × INT` per second. Fire *powers* always ignite for 4 s at `0.1 × INT`/s. Note the chance scales with **how big the hit was relative to your INT**. |
| **Arc** | Lightning spells: chance `skill × damage / (1.2 + 0.6·INT)` to arc to nearby foes (radius 4 m). |
| **Bleed** | Thrown weapons only: 10…25% chance, `0.06…0.5 × DEX` per second for 4 s. |
| **Silence** | *Silence* power (ranged): radius 4/5/6, 15/20/25 s; blocks monster damage/heal/summon/buff/curse/resurrect spells. |
| **Provoke** | *Provoke* (shield, melee) radius 6/7/8, +25/30/50% armor for 5/8/10 s. *Summon Provoke* makes enemies target your summon. |
| **Knockback** | *Icicle Blast*, *Repulse*, commander/boss slams. |
| **Armor shred** | *War Cry*: enemy armor −35/50/60% for 20 s. *Decay Armor* curse: −15% physical resistance. |
| **Anger** | Monsters crossing their aggro threshold become "angry" (temporary buffs), `angry_duration = 12 + 8×Veteran + 18×Elite` s. |

---

## 5. Experience and leveling (`rules.skrit` `CalculateExperience$`, `AwardExperience$`)

* A monster has a fixed XP pool. Each hit pays `experienceValue × damage / maxLife` (damage clipped to remaining life), and the pool drains. You earn XP **as you damage**, not on the kill. Minimum award 1.
* The XP goes to the class skill of the **weapon or spell used**, and to **Uber** (character level).
* **Level-gap multiplier** (your Uber level − monster level): more than 4 above: `1 − 0.2 × (gap − 4)`; more than 4 below: `1 + 0.2 × (gap + 4)` (−5 = 80%, −8 = 20%). Floor **5%**.
* **Party bonus** by number of leveling members: ×1.80 (2), ×2.43 (3), ×2.92 (4+), then split evenly, so each member gets `1.80/2 = 90%`, `2.43/3 = 81%`, `2.92/4 = 73%` of what a solo hero would. Multiplayer groups add ×1.60/2.00/2.30 for 2/3/4 parties, split by average party level.
* Summons and pets pay their XP to their **benefactor**. Pets themselves never level.
* **Level-up**: full life and mana, powers recharged, skill point available.
* XP needed to *reach* level L (`experience_table`): L2 300, L5 4,000, L10 34,200, L20 196k, L30 663k, L40 1.99M, L50 5.74M, L60 16.4M, L70 46.7M, L80 133M, L90 377M, L100 1.07B.
* **Monster XP value** (normal tier): `L<12: 48 + 12L`; else `6480 × 1.11^L / (5.4 × (L + 10))`. Tier multipliers: trivial 0.42, weak 0.80, normal 1, strong 1.25, miniboss 3.33.

---

## 6. Passive skills (`passive_skills.gas`)

48 passives, 12 per class, **max level 20 each**, each gated by class level and prerequisite skills (e.g. Reinforced Armor needs Melee 24 and Barricade 1). Value shown is Level 1 → Level 20.

| Class | Skill | Effect |
| --- | --- | --- |
| Melee | Fortitude | Max life +6 → +45% |
| | Critical Strike | Crit chance 8 → 50% (crit = 200%) |
| | Barricade (aegis) | Unlocks shields; shield armor +20 → +120%; block 2 → 20% melee and ranged |
| | Overbear | Unlocks 2H; 2H damage +8 → +50% |
| | Dual Wield | Unlocks dual-wield; +8 → +70% |
| | Toughness | −3 → −26% physical damage |
| | Alacrity | Melee attack speed +3 → +25% |
| | Reinforced Armor | Armor +4 → +35% |
| | Smite | 2H stun chance 5 → 50%, 1 → 2 s |
| | Fierce Renewal | Melee power recharge +3 → +30% |
| | Rebuke | On blocking: damage `0.4 → 2.5 × melee level`, stun 1 → 2 s |
| | Deadly Strike | Melee crit damage 224 → 350% |
| Ranged | Critical Shot | Crit chance 8 → 50% |
| | Dodge | 4 → 40% to dodge melee or ranged |
| | Biting Arrow | Unlocks crossbows; bow/xbow damage +8 → +50% |
| | Quick Draw | Unlocks thrown; thrown rate +3 → +25% |
| | Far Shot | Bow range +6 → +60% |
| | Bleed | 10 → 25% chance, `0.06 → 0.5 × DEX`/s, 4 s |
| | Survival | Fire/ice/lightning resist +10 → +60%; harvest health potions |
| | Shockwave | Arrow shockwave (2 m) for 8 → 50% damage when it flies farther than 9 → 7 m |
| | Penetrate | 12 → 75% chance a projectile passes through its victim |
| | Cunning Renewal | Ranged power recharge +3 → +30% |
| | Mortal Wound | Bow/xbow crit damage 224 → 350% |
| | Ricochet | Thrown crits bounce (7.5 m) for 66 → 150% damage |
| Nature | Natural Bond | Mana cost −6 → −60%; harvest mana potions |
| | Aquatic Affinity | Healing +5 → +50%; ice damage +5 → +40% |
| | Summon Fortitude / Might | Summon life +16 → 100%; summon damage +24 → 150% |
| | Enveloping Embrace / Feral Wrath | Embrace and wrath spell power +20 → +150%, duration +32 → +200% |
| | Arctic Mastery | Ice damage (spells and powers) +8 → +60% |
| | Nurturing Gift | Healing +8 → +100% |
| | Arcane Renewal | Magic power recharge +3 → +30% |
| | Freezing | Freeze chance 5 → 30%, 1 → 2 s |
| | Summon Bond | 12 → 66% of damage transferred to the summon |
| | Absorption | 14 → 85% of magic damage absorbed, 8 → 50% of that returned as mana |
| Combat | Brilliance | Max mana +7 → +150% |
| | Devastation | Combat magic damage +10 → +60% |
| | Debilitation | Curse power +24 → +150%, duration +32 → +200% |
| | Searing Flames / Amplified Lightning / Grim Necromancy | Fire / lightning / death damage +8 → +60% (spells and powers) |
| | Summon Alacrity | Summon attack speed +7 → +40% |
| | Quickened Casting | Cast speed +4 → +25% |
| | Vampirism | 3 → 25% of death damage returned as life |
| | Ignite / Arcing | see §4; arc damage `0.18 → 1.0 × INT` |
| | Arcane Fury | Combat and nature **power** damage +3 → +30% |

Skill suites bundle three skills so that gear can say "+2 to Barricade, Toughness, and Reinforced Armor" (14 suites in `skill_suites.gas`).

---

## 7. Powers (active skills)

### 7.1 The model
There are 28 hero powers (7 per class) plus 9 pet powers. Each has **3 levels**, unlocked by class level and passive prerequisites. Each is bound to specific stances (for example Staggering Blow needs a two-handed weapon; Waves of Force and Elemental Rage need dual-wield; Flurry and Shrapnel Blast need thrown weapons).

### 7.2 Power list
Recharge class = `reload_damage_formula` seconds of "combat" (§7.3).

| Power | Class | Recharge | What it does (L1 → L3) |
| --- | --- | --- | --- |
| Brutal Attack | Melee | 21 | Next hit deals `1500 + 25×melee` % → `2000 + 60×melee` % |
| Provoke | Melee (shield) | 12 | Taunt radius 6 → 8 m, +25 → +50% armor, 5 → 10 s |
| Whirling Strike | Melee | 35 | `920 + 9×melee` % to all within 3 → 4 m, 1.5 s stun |
| Staggering Blow | Melee (2H) | 35 | `400 + 7×melee` % → `800 + 12×melee` %, radius stun 6 → 10 s |
| War Cry | Melee | 35 | Armor −35 → −60% for 20 s, next 8 → 15 hits crit, enemies flee |
| Waves of Force | Melee (dual) | 35 | 5 waves each `200 + 3.6×melee` % → `490 + 9×melee` % of main-hand |
| Elemental Rage | Melee (dual) | 60 | +10 → +20% attack speed, adds fire/ice/lightning per hit, but +12 → +20% melee/ranged vulnerability, 15 s |
| Take Aim | Ranged | 21 | Next shot `1500+` % → `2500 + 60×ranged` % |
| Thunderous Shot | Ranged | 35 | Piercing shot `530 + 9×ranged` % → `1225 + 21×ranged` %, 6 → 10 s stun |
| Silence | Ranged | 21 | Radius 4 → 6 m, 15 → 25 s |
| Charged Shots | Ranged | 60 | Every arrow adds lightning, 12 → 15 s |
| Shrapnel Blast | Ranged (thrown) | 35 | 5 → 9 missiles plus explosion damage |
| Repulse | Ranged | 60 | Knocks back and stuns (1.5 s), radius 3 → 4 m, up to 20 s |
| Flurry | Ranged (thrown) | 60 | Attack rate ×1.2 → ×1.5, three projectiles, reduced accuracy, 15 s |
| Gravity Stone | Nature | 35 | Pulls enemies in, radius 4 → 6 m, 4 → 6 s |
| Icicle Blast | Nature | 35 | Ice cone `(56 + 14×natureLvl) × (0.82 → 2.0 + …)` |
| Circle of Frost | Nature | 60 | Freezes 12 → 18 s, radius 3.5 → 4.5 m |
| Summon Provoke | Nature | 12 | Radius 6 → 8 m, enemies target your summon |
| Aether Blast | Nature | 35 | Explosion = 240 → 350% of your **summon's max life**, 5 s stun |
| Invulnerability | Nature | 60 | Whole party takes no damage, 6 → 12 s |
| Glacial Aura | Nature | 60 | Ice waves every 0.8 s, freeze 4 → 6 s, 10 → 15 s |
| Energy Orb | Combat | 21 | Floating orb shoots for 20 s |
| Flame Nexus | Combat | 35 | Fire elemental tendrils `(40 + 10×cmLvl)…` |
| Detonation | Combat | 60 | `(67.5 + 16.9×cmLvl) × (2.0 + …)` fire in 3 → 4 m |
| Corrosive Eruption | Combat | 35 | Curse cloud; victims burst for 45 → 70% of their max life when they die |
| Harvest Soul | Combat | 35 | Death scythe; heals the party for 6% of damage dealt |
| Chain Lightning | Combat | 21 | Jumps 2/4/6 times, damage ratio 0.38/0.22/0.15 per jump |
| Gathered Bolt | Combat | 60 | `(70 + 17.5×cmLvl) × (1.85 → 2.0 + …)` lightning in 3.5 → 5 m |

Pet powers: Staggering Kick (pack mule), Explosive Sting (scorpion queen), Inferno (fire elemental), Furious Howl (dire wolf), Frost Aura (ice elemental), Arboreal Rejuvenation (dark naiad: heals **and resurrects**), Enrage (mythrilhorn), Decompose (necrolithid), Draconic Inspiration (pocket dragon: +35% power damage for 20 s).

### 7.3 Recharge by damage dealt
From `active_skills.gas`:
```
reload_damage_formula = secondsOfCombat × (6 + 1.5 × level) × (1 + 0.022 × level) × activeGroupMembers
```
Presets: very fast = 12, fast = 21, medium = 35, long = 60 "seconds of combat". A power is ready again after the **party** has dealt that much damage (`Actor.GetActiveSkillReloadDamage()` must reach zero before `job_attack_object_melee.skrit` will fire it). *Power recovery rate* affixes and *Fierce/Cunning/Arcane Renewal* speed it up; leveling up resets all powers. The exact per-hit decrement is engine code (see §13).

---

## 8. Spells

### 8.1 Formulas (`spl_ds2_spellscmagic.gas`, `spl_ds2_spellsnmagic.gas`)
Each spell has four tiers (Lesser / normal / Greater / Master). Tiers differ by **required level** and by `max_intel`, the cap on the INT the formula can use:
```
clamped_intel = min(INT, max_intel)
damage        = uniform(lo, hi) × (a + b × clamped_intel) × (1 + Combat% or Ice%) × (1 + Element%)
mana cost     = (k × clamped_intel − c) × (1 − Natural Bond%)
```
Firebolt tiers: required level 0 / 13 / 30 / 56, INT cap 59 / 136 / 256 / 424. Cast delay is per spell (1.04 … 2.5 s) and shortened by Quickened Casting.
**Important**: both damage and mana cost grow with INT, so mana efficiency (damage per mana) is *constant* with level and only changes by spell choice and by **Natural Bond** (−6 … −60% mana cost).

Per-spell average damage and mana (before skill multipliers, per projectile where the spell fires several):

| Spell | Element | Avg dmg @INT 100 | Mana @100 | Avg dmg @INT 200 | Mana @200 | Cast delay (s) | Dmg per mana |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Firebolt | fire | 106 | 40 | 210 | 81 | 1.39 | 2.6 |
| Firespray (5 embers) | fire | 22 | 30 | 44 | 62 | 1.04 | 0.7 |
| Embers (multi) | fire | 34 | 51 | 67 | 102 | 1.04 | 0.65 |
| Plasma Globes | fire | 80 | 56 | 158 | 113 | 1.66 | 1.4 |
| Fireball (AoE) | fire | 53 | 82 | 105 | 164 | 1.66 | 0.64 |
| Grave Beam | death | 71 | 24 | 141 | 48 | 1.04 | 3.0 |
| Leech Life | death | 86 | 48 | 170 | 98 | 1.25 | 1.7 |
| Soul Lance (pierces) | death | 85 | 48 | 168 | 97 | 1.66 | 1.7 |
| Skull Spray (3) | death | 80 | 56 | 158 | 113 | 2.08 | 1.4 |
| Impale | death | 80 | 122 | 158 | 244 | 2.5 | 0.64 |
| Jolt | lightning | 71 | 24 | 141 | 48 | 1.04 | 3.0 |
| Multispark (3) | lightning | 36 | 40 | 71 | 81 | 1.39 | 0.87 |
| Static Bolt (slows) | lightning | 71 | 30 | 141 | 62 | 1.04 | 2.3 |
| Lightning Blast (pierces) | lightning | 106 | 82 | 210 | 164 | 1.66 | 1.3 |
| Call Lightning (2 strikes) | lightning | 66 | 64 | 131 | 128 | 1.39 | 1.0 |
| Icebolt | ice | 81 | 38 | 160 | 76 | 1.39 | 2.1 |
| Encase (slows) | ice | 131 | 78 | 259 | 158 | 2.5 | 1.6 |
| Cold Snap (AoE) | ice | 24 | 34 | 48 | 68 | 1.25 | 0.7 |
| Frost Beam | ice | 75 | 48 | 149 | 96 | 1.04 | 1.6 |
| Iceball (AoE) | ice | 40 | 76 | 79 | 152 | 1.66 | 0.5 |
| Ripple (AoE) | none | 33 | 45 | 65 | 91 | 1.66 | 0.7 |
| Grasping Vine (roots 15 s) | none | 174 | 101 | 345 | 204 | 2.5 | 1.7 |

So single-target "bolt/beam" spells are the efficient ones; AoE spells trade efficiency for coverage.

### 8.2 Other spell families
* **Summons** (all cost `4.1 × INT − 8` mana, 3 s cast, 600 s duration, one at a time). Combat: Trasak, Thrusk, Stygian Twisted Shail, Mucrim Shocker. Nature: Bracken Defender, Raptor, Rhinock, Scorpion, Lertisk, Ketril, Forest Golem. Summons are real monster templates (e.g. "Summoned Raptor" sits in the monster roster at `monster_level = 0`; I infer the level is set from the caster at summon time, which is engine-side). Summon Fortitude/Might/Alacrity and Summon Bond apply.
* **Heals** (nature): Heal (instant), Healing Rain (8 s HoT, area), Nourish (6 s HoT, cheap), Healing Cascade (bouncing). Scaled by Aquatic Affinity and Nurturing Gift.
* **Embraces** (defensive buffs: Earthen, Wind, Spirit, Aquatic, Life) and **Wraths** (offensive: Bear, Magic, Ice, the Fallen, Ancestors), scaled by Enveloping Embrace / Feral Wrath.
* **Curses** (combat): Dehydrate, Steal Magic, Blind, Infect, Decay Armor, Drown, Punishing Fire, Cripple, Corpse Transmutation. Scaled by Debilitation.
* **Resurrect** ×5 tiers.
* **Monster spells**: 130 templates (generic heals, buffs, debuffs, summons, damage). Monsters autocast at fixed chances (damage 50%, heal 25%, debuff 25%, buff 15%) and are interrupted by *Silence*.

### 8.3 Spell hit resolution (`DamageGoMagic$`)
Same armor and level-gap formula as weapons (`CalculateDamage$`), then monster **magic block** (chance and flat amount per magic class, or full block), then % and flat magic reduction, then `DamageGo$` (resistance etc.), then on-hit procs: Arc (lightning), Ignite (fire), Freeze (ice).

---

## 9. Enemies

### 9.1 Stat templates (`actor_evil_*.gas`)
Every monster is `base_actor_evil_<role>_<tier>` with `monster_level` (L) plugged in:

| Stat | Normal melee |
| --- | --- |
| Life | `(9L + 18) × (1 + 0.12L)` |
| Damage | `(2.12L + 8) × (1 + 0.04L)`, rolled ×0.75 … ×1.25 |
| Armor | `1.333 × (8 + 2L) × (1 + 0.004L)` |
| XP | see §5 |
| Move speed | 2.5 m/s (hero 4.5) |

Tier multipliers for life (relative to normal) and the damage coefficient `(a·L + b)`:

| Tier | Life | Damage `a`,`b` (melee) | Speed (melee) | Loot macro |
| --- | --- | --- | --- | --- |
| trivial | ×0.25 | 1.0, 4 | 2.7 | weak |
| weak | ×0.67 | 1.4, 5.33 | 2.7 | weak |
| normal | ×1 | 2.12, 8 | 2.5 | normal |
| strong | ×1.67 | 3.0, 11.5 | 2.3 | strong |
| miniboss | ×3.67 | 4.7, 17.8 | 2.7 | miniboss |

Variants (per-hit numbers from the formulas): **rogue** = ×0.8 life, ×0.85 damage per hit; **tank** = ×1.25 life, ×1.2 damage per hit. The file comments say rogue is meant to be 1.25× and tank 0.7× the *damage output*, so the rest of the difference must come from attack rate in the animations (not extracted). Roles: **ranged** (×0.8 life, move speed 3.0), **magic** (×0.6 life, speed 3.5), **magic_aoe** (damage ≈ 0.4× per hit).

Worked numbers for a **normal melee** monster:

| Monster L | Life | Avg hit (before armor) | Armor |
| --- | --- | --- | --- |
| 5 | 101 | 22 | 24 |
| 15 | 428 | 64 | 54 |
| 30 | 1,325 | 158 | 102 |
| 45 | 2,707 | 290 | 154 |
| 64 | 5,156 | 512 | 228 |
| 85 | 8,770 | 828 | 318 |

Tuning intent (from the comments): monsters are sized for a **four-character party** dealing `4 × (8 + 2L) × 0.75` damage per second. A normal monster should die in ~6–7 s and a level-appropriate character has `50 + 10.6L` life. The `(1 + 0.12L)` factor in life is what keeps them tanky at high levels.

### 9.2 Difficulty is monster level
Each monster template sets `monster_level = X×isNormal + Y×isVeteran + Z×isElite`:

| Monster | Mercenary | Veteran | Elite |
| --- | --- | --- | --- |
| Hak'u Skinner | 3 | 40 | 64 |
| Morden-Viir Grunt | 3–4 | 40 | 64 |
| Skath Zealot | 16 | 46 | 69 |
| Kurgan | 20 | 48 | 71 |
| Snow Va'arth Brute | 28 | 54 | 76 |
| Birath | 39 | 63 | 84 |
| Qatall Attendant | 40 | 64 | 85 |

Resistances scale the same way: for example **Devoted Skath Zealot has `fire resistance = 0.5 / 1.0 / 1.5`**, so at Elite he *heals* from fire. Others get ice vulnerability that shrinks with difficulty (−25% / −10% / −5%). The three worlds also swap the loot-thief template (`loot_thief` vs `loot_thief_advanced`) and extend the "angry" duration.

### 9.3 Multiplayer scaling (`formulas.gas`)
Monster life ×`[0.8, 1, 1, 1, 1.35, 1.70, 2.05, 2.40, 2.75, 3.10, 3.45, 3.80]` and XP ×`[1, 1, 1, 1, 1.1 … 1.8]` indexed by party size (the first entry presumably being one character).

### 9.4 Roster
464 distinct named monsters in 1,527 stat-template variants, organised by act and faction. The main families: **Hak'u** (jungle tribal: skinners, hunters, shamans, drummers who buff), **Morden-Viir / Morden-Urg / Morden-Gral / Morden-Durvla** (human soldiers, thugs, mages, butchers), **Skath** (zealots, avengers, disciples), **Bracken / Mystic Protector / Forest Golem** (nature constructs), **Kurgan, Va'arth, Snow Beast, Taugrim** (snow), **Vai'Kesh** (fanatics, seers, warlocks, demons), **Korven, Qatall, Kluun Legionnaires** (late game), **Shails, Shard Souls, Plagued variants** (corrupted versions of earlier monsters), plus **Mimic** (chest monster), **Loot Thief**, **Bone Minion** (necromantic summon), **Ketril, Lertisk, Sangor, Gantis, Feaster, Iraca** (beasts). Each melee/ranged/magic role usually comes in "regular" and "mini-boss" (named/elite) versions, plus summoned and "Plagued" versions.

### 9.5 AI
* Base `actor_evil`: **sight 15 m**, engage range 10 m, rescan every 2 s, job travel limit 20 m, loses interest if the hero flees. Heroes engage melee at 8 m and ranged at 6 m.
* **Coaches and plays** (`ai/plays`): monsters join a group (coach) within 10 m. A play is chosen for the group: *cautious attack* (some flee when a friend dies), *charge*, *hide/flank* (ambush from 10 m then all charge together), *mob attack*, *ranged flee* (ranged attackers keep distance; by default only 10% of the melee members attack and the rest hang back), *leader guard*, *battle yell* (call for help), *thief* (loot thief steals dropped items and flees).
* Aggro is tracked per damage type (melee, ranged, combat magic, nature magic); damaging a monster aggros its visible friends too.
* **Angry**: when aggro passes a threshold the monster gets temporary buffs.
* Monsters cast spells (§8.2) and many mini-bosses have signature moves (Ganth slam, commander knockback).

---

## 10. Items

### 10.1 Weapon damage tuning (`wpn_bases.gas`)
Every weapon's `damage = (8 + 2·L) × weaponDuration × typeModifier − statBonus`, with the stat bonus pre-subtracted so that weapon plus STR/DEX bonus lands on the yardstick. Resulting formulas (min is ×0.75, max is ×1.25):

| Type | Damage per hit at item level L | Swing delay |
| --- | --- | --- |
| 1H melee (sword, axe, hammer, mace, club, dagger) | `3.4 + 0.74L` | 0.67 s |
| 2H melee, fighter staff | `5.2 + 1.2L` | 0.9 s |
| Bow | `3.0 + 0.65L` | 0.625 s (range 9 m, velocity 30) |
| Crossbow | `5.2 + 1.2L` | 0.9 s (range 9 m, velocity 20) |
| Thrown | `3.84 + 0.86L` | 0.73 s (range 7.5 m) |
| 1H mage weapon (cestus) | `1.65 + 0.31L` | 1.0 s |
| 2H mage staff | `3.75 + 0.85L` | 0.9 s |

Example: level-30 fighter with a level-30 short sword and 100 STR: weapon 19.2–32.0, STR bonus +15/+25 → **34–57 per swing (avg 46)**; against a same-level normal monster the armor factor is `68 / 102 = 0.67`, so ≈ **31 per hit** and ~43 hits to kill its 1,325 life. That is why the game is balanced around a four-character party plus powers.

### 10.2 Requirements
`equip_requirements = melee:#item_level - 2.0` (class skill ≥ item level − 2). Shields add `aegis:1` (Barricade 1), 2H weapons need Overbear, dual-wield weapons need Dual Wield, crossbows need Biting Arrow, thrown need Quick Draw.

### 10.3 Item tiers and levels
Every base item has a **`base` item level plus `var1`–`var4`**, which is how the same sword reappears stronger in later difficulties/acts.

| Base item | Item levels (base, var1…var4) |
| --- | --- |
| Short Sword | 2, 13, 32, 42, 51 |
| Katana | 39, 76, 85, 93, 95 |
| Leather Jerkin | 3, 9, 18, 27, 36 |
| Mythril Armor | 39, 66, 78, 84, 90 |
| Buckler | 6, 11, 17, 28, 39 |
| Archmage Robe | 39, 63, 75, 84, 90 |
| Resplendent Amulet | 45, 77, 88, 93, 98 |

Counts (non-unique base items I could parse): **192** across weapons, armor, shields, rings, amulets, spellbooks. Armor comes as **fighter / ranger / nature-mage / combat-mage** sets of body, helm, gloves, boots (6–7 tiers each). Weapon families: sword (1H/2H), axe (1H/2H), hammer (1H/2H), mace, club, dagger, fighter staff, mage staff, cestus, bow, crossbow, thrown (knife, axe, crescent, star, glaive, chakram, shiv). Item level tops out around **98**.

### 10.4 Rarity tiers
| Tier | How it's made |
| --- | --- |
| Normal | Base template, no modifiers. |
| Magic | Base plus **1 or 2** random modifiers (drop tables ask for `mod(1)` / `mod(2)`). |
| Rare | Engine-generated: base plus a bundle of modifiers (my reading of `pcontent_min/max_modifier = monster_level − 25 … +5`: a **wider, higher modifier-level window** than magic items; the modifier count is engine-side). Named crafted rares (239 templates in `crafted_items.gas`, fixed stats, `is_pcontent_allowed = false`) are sold/crafted, not dropped. |
| Unique | Hand-authored: fixed stats, `allow_modifiers = false`. **198** found. |
| Set | 22 sets, **105 pieces**, bonuses by number worn (§10.6). |

### 10.5 Affixes (`pcontent.gas`)
304 modifier rows in about 62 families. Each family is a chain of tiers keyed to a **modifier level**; each affix has a level (matched against the item/drop level window by the engine) and carries `object_types` (weapon, armor, body, helm…) and `skill_types` (fighter, ranger, mage, nmage, cmage) so a fighter helmet never rolls spell damage. Families have **exclusion groups** so incompatible ones don't co-roll.

| Affix | Tiers (modifier level) → range |
| --- | --- |
| **of Hardiness → Colossus** (+STR) | 9 tiers, L2 → L82: +1 → +72 |
| **of the Swift → Effortlessness** (+DEX) | 9 tiers, L1 → L81: +1 → +100 |
| **of Awareness → Omniscience** (+INT) | 9 tiers, L3 → L83: +1 → +60 |
| **of the Rat → Lion** (+life) | 12 tiers, L1 → L75: +4 → +237 |
| **of the Toad → Dragon** (+mana) | 12 tiers, L1 → L67: +4 → +274 |
| **of Wounding → Torture** (+max melee damage) | 6 tiers, L1 → L74: +1 → +72 |
| **of Accuracy → Mastery** (+max ranged damage) | 6 tiers: +1 → +72 |
| **of Affliction → Desolation** (+min melee) / **of Piercing → Penetrating** (+min ranged) | 6 tiers, L3 → L48: +3 → +18 |
| **Cruel → Excrutiating** (melee %) | 8 tiers, L2 → L53: +10% → +56% |
| **Sharp → Razor** (ranged %) | 8 tiers: +10% → +56% |
| **Feral → Arboreal / Destructive → Tragic** (nature / combat spell %) | 8 tiers: +4% → +25% / +32% |
| **Chilling / Scorching / Jolting / Grim** (melee) and **Frosted / Heated / Glimmering / Somber** (ranged) | added elemental damage: ice 3 → 27 (L18 → L74), fire 2 → 36 (L15 → L80), lightning 2 → 24 (L18 → L85), death 4 → 35 (L22 → L85) |
| **of the Parasite → Blood** (life steal) | L6 → L60: 3 → 8% |
| **of the Phantom → Wraith** (mana steal) | 3 → 8% |
| **of Consumption → Devouring** (life per hit) | L12 → L78: +2 → +23 |
| **of Candlelight → Starlight** (mana per hit) | +2 → +23 |
| **Stout → Adamantine** (+armor) | 12 tiers, L1 → L86: +2 → +85 |
| **Steadfast → eternal** (+% armor) | 8 tiers, L4 → L60: +26% → +115% |
| **Azure / Crimson / Pale / Indigo** (ice/fire/lightning/death resist) | 5 tiers: 10% → 25% |
| **Twilight** (magic resist), **Noble** (physical, shields), **Formidable** (melee resist, up to 14%), **Disorienting** (ranged resist, up to 20%) | |
| **of Reversal → Retribution** (reflect) | 10 → 40% |
| **of Mending → Regeneration** / **of Brightening → Visions** (life / mana recovery) | +4% → +12% |
| **of Repulsion / of Deflection** (shield block) | up to 15% melee / 20% ranged |
| **Rousing → Invigorating** (power recharge) | L20 → L50: +5% → +10% |
| **Warrior's … Champion's** etc. (+1/+2 to all passives of a class) | L40 / L65 |
| **Knight's / Brawler's / Duelist's / Archer's / Assassin's / Caller's / Rime / Blazing …** (+2/3/4 to a **skill suite**) | L30 / L55 / L80 |
| **Fortunate → Serendipitous** (magic find) | 4 → 35% (L20 → L60) |
| **Glittering → Affluent** (gold dropped) | +5% → +70% |

### 10.6 Uniques and sets (examples)
* **Claw of Kajj** (short sword, item level 12): +7 min damage, +20% damage, 5% life steal, +10% magic find.
* **Xeria's Fury** (Katana, L85): +11 STR, +25–74 lightning, +30% lightning resist, +4 to Critical Strike/Dual Wield/Alacrity.
* **The Radiant Sun** (Mythril Armor, L85): +78 STR, +300 health, +140% armor, +10% melee and ranged resistance, +2 melee skills.
* **Nature's Avatar / Entropy** (robes, L85): +60 INT, +525 mana, +200% armor, +2 to the class's skills.
* **Endless Memory** (cestus, L85): +65 INT, +40% nature and combat magic damage, +3 to both magic skills.
* **Starfall** (bow, L84): +30 min damage, +36–60 ice, +20% magic resist, +4 to Critical Shot/Dodge/Survival.

Set bonus examples: **Night's Shadow** (5-piece dual-wield: life steal 3→7%, dodge 4→12%, magic find 20→40%, +2 to Critical Strike/Dual Wield/Alacrity), **Lorethal's Legacy** (8-piece 1H/shield: STR +3→+18, armor +5→+65, +3 melee skills at 8), **Legend of the Fire King** (4-piece 2H: STR to +56, fire damage, +4 to Fortitude/Overbear/Smite), **The Circle of Four** and the other armor sets (22 total: `set_definitions.gas`). Bonuses are cumulative **per pieces worn**.

### 10.7 Potions and gold
* **Health**: Small 125, Health 250, Large 450, Super 700, Colossal 1,100. **Mana**: 150 / 300 / 500 / 900 / 1,400. **Rejuvenation** restores both (125/150 … 1,100/1,100). All restore over **12 s**.
* Item levels per potion: for example Colossal 60/70/80/90. Monsters drop potions from `monster_level − 10` up to `monster_level`.
* Gold pile for a normal monster: `uniform(0.093, 0.156) × (0.2L² + 5.2L + 2)`; "jackpot" `0.375 … 0.625 ×` the same polynomial.

---

## 11. Loot: what drops and how often (`pcontent_macros.gas`)

Each source is a **weighted pick** (`oneof`, weights sum to ~1). A kill rolls once per `oneof` block. Most weak/normal kills drop nothing.

### 11.1 By monster tier
| | Nothing | Gold | Jackpot gold | Health potion | Mana potion | Item (any, "#") | Rare | Unique | Set |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Weak** | 73.85% | 12% | 2% | 4% | 2.4% | 5% | 0.45% | 0.15% | 0.15% |
| **Normal** | 66.25% | 12% | 3% | 6% | 3.5% | 8% | 0.75% | 0.25% | 0.25% |
| **Strong** | 51.5% | 14% | 4% | 8% | 4.8% | 15% | 1.35% | 0.45% | 0.45% |

(Rare/unique/set weights are multiplied by `(1 + magicFind/100)`; the "nothing" weight is not, so magic find has a slightly *diluted* effect.)
**Item level window** for the drop: `monster_level − 5 … +1` (normal), `−4 … +2` (strong), `−6 … 0` (weak). Rares `−4…+2` with a modifier window of `−25…+5`; uniques `−40…+3`; sets `−50…+3`. So uniques and sets can be far below the monster's level.

**Miniboss** (guaranteed): 2–3 piles of gold (`0.187…0.312 × (2L² + 42L + 20)`, 10% jackpot), 74% a potion, and one gear roll: **30% 1-mod magic, 50% 2-mod magic, 12% rare, 4% unique, 4% set** (each MF-scaled).

### 11.2 Containers
| Container | Drops |
| --- | --- |
| **Breakable** (barrels, crates) | 16% nothing, 75% small gold, 3% big gold, 2% health potion, 1% mana potion, 3% item |
| **Open** | 5.5% nothing, 75% gold, 4% big gold, 6% / 4% potions, 5% item, 0.5% rare |
| **Chest** | Always gold (95/5 split), 75% a potion (40% health, 25% mana, 10% any), plus an item roll: 50% 1-mod, 46% 2-mod, 2.5% rare, 0.75% unique, 0.75% set |
| **Weapon barrel** | 54% melee (30% 1-mod / 24% 2-mod), 42% ranged (24% / 18%), plus 2.5% rare, 0.75% unique, 0.75% set; always an item |
| **Armor stand** | 60% 1-mod / 36% 2-mod armor, +2.5% rare, 0.75% each unique/set |
| **Magic bookcase** | A spell (50% nature / 50% combat) **plus** a caster item (60% 1-mod, 36% 2-mod, +rare/unique/set) |
| **Class chests** (behind class doors) | A guaranteed rare from that class |
| **Mock chest (Mimic)** | 3–4 gold piles, a guaranteed potion, **2 two-modifier items, a spell, a reagent, and a guaranteed rare/unique/set (70/15/15)** |
| **Quest rewards** | `quest_level_N_macro` tables, plus `rare_unique_set_macro` (70% rare, 15% unique, 15% set), often with `player_drop_type = all` meaning **every player gets their own drop** |

### 11.3 Magic find
* Additive stat from items (affixes up to +35%, uniques like Claw of Kajj +10%, set bonuses +20 … +40%) and race (human +10%).
* Used only in the formula `chance × (1 + MF/100)` on rare/unique/set/magic-item weights, as above.

### 11.4 Loot Thief
`loot_thief_chance = 5%` per item drop event, with a **300 s** cooldown between spawns. A thief monster (`loot_thief`, `loot_thief_advanced` in Veteran/Elite) grabs dropped loot and runs; killing it gives it back.

### 11.5 Inventory and vendors
Heroes have a grid inventory (5 × 13), a `loot_range` of 7 m and a collect-loot job (exact pickup rules are engine-side). Vendors can sell crafted items (`store_add_crafted.skrit`, the 239 fixed-stat crafted rares); the UI also has a party stash, reserve store, hire shop, pet store and an enchanter store.

---

## 12. A full worked example: Level-30 fighter vs a Skath Zealot (Mercenary, L16)

* **Hero**: STR 100, DEX 40, INT 40. Life ≈ 374 (+ Fortitude). Short sword (item L30).
* **Hero swing**: 34–57 (avg 46). Monster armor = `1.333 × 40 × 1.064 = 56.7`; expected = `min(8 + 60, 56.7) = 56.7` → **no armor reduction** (the hero's `8 + 2L` exceeds the monster's armor). Level gap = +14 → no damage penalty. So ~46 per hit, plus an 8% chance (Critical Strike 1) of a second 46 on top.
* **Monster**: life `(9×16+18)×(1+1.92) = 473`. Dies in ~10 hits. XP: the hero is 14 levels above it → multiplier `1 − 0.2×(14−4) = −1` → floored to **5%**. Fighting trash far below your level is nearly worthless, which pushes players forward.
* **Monster hits back**: raw avg `(2.12×16+8)×(1+0.64) = 69`, rolled 52–86. Hero armor 136 (on-level), attacker level 16 → `expected = 40`; `40/136 = 29%` lands → ~20. Then the **level-gap rule**: the monster is 14 levels *below* the hero (< −8), so ×0.25 → **~5 per hit**. A Mercenary-level monster can barely scratch an Elite-level hero.

---

## 13. What the data does not tell us

These are implemented in the C++ engine, so I can't state exact behaviour:
* How a power's **reload damage** counter decreases per hit (the formula that sets the target amount is visible).
* How **class XP** converts into STR/DEX/INT growth (the `skill_influences` weights are visible, the conversion is not), and skill-point-per-level counts.
* The **random selection inside `pcontent`**: exact affix counts for rare items, how exclusion families break ties, how `il_main = #` is expanded, and the order of weighting.
* **Animation-driven attack timings** (the base chore durations).
* Pathing/formation details, pet stat building (`SBuildPetStats`), and loot pick-up mechanics.
* The exact meaning of the three-number `strength = a, b, c` triplet on heroes.

Everything else above comes straight from the files.

---

## 14. Source map

| Topic | File (inside `Logic.ds2res`) |
| --- | --- |
| Damage, hit, armor, XP, crits, blocks | `world/global/rules/rules.skrit` |
| Life/mana/XP-share/constants | `world/global/rules/rules.gas`, `world/global/formula/formulas.gas` |
| Passive / active skills, suites | `world/global/skills/*.gas` |
| Weapons / armor / rings / spells / potions | `world/contentdb/templates/interactive/{wpn,amr,trs,spl,ptn}_*.gas` |
| Affixes | `world/contentdb/pcontent.gas`, schema in `pcontent/pcontent_table_schema.gas` |
| Drop tables | `world/contentdb/pcontent/macros/pcontent_macros.gas`, `quest_pcontent_macros.gas`, `act*_macros.gas` |
| Sets | `world/global/sets/set_definitions.gas` |
| Monster stats | `world/contentdb/templates/actors/evil/actor_evil_*.gas` and per-monster files |
| Hero races | `world/contentdb/templates/actors/good/heroes_ds2.gas` |
| AI | `world/ai/jobs/common/brain_*.skrit`, `world/ai/plays/*.skrit` |

---

## 15. Takeaways if you are borrowing the design

* **One yardstick**: `8 + 2 × level` damage per second. Weapons, armor, monster life/damage and power cooldowns are all derived from it, which is why balance holds across 100 levels.
* **Armor as a ratio against attacker level** (`min(8+2L, armor)/armor`) is simple, self-scaling and punishes under-geared play without a hard cap.
* **Crit as a second roll** and **powers that cannot crit** keep power numbers predictable.
* **Powers recharge on damage dealt**, so fighting well, not waiting, refreshes them.
* **Spell damage and mana cost both scale with INT**, so efficiency is a spell-choice and skill question, not a level question.
* **Difficulty as a monster-level jump** plus resist tweaks avoids stat-bloat multipliers and keeps drop levels and XP consistent.
* **Drop tables are weights, not stages**: every kill rolls once per block, and a boss's guaranteed gear roll is just a `oneof` with no "nothing" entry.
* **Level-windowed everything** (`level − 5 … +1`) makes loot feel appropriate, and the wide windows for uniques and sets make old drops still exciting.
