# Combat reference and decision rule

Dungeon Siege II is Curse's combat foundation. Its installed game data has already been traced in
[`ds2-combat-and-loot.md`](ds2-combat-and-loot.md); that evidence, rather than memory or a wiki, is the baseline for attacks, powers,
recharge, damage, defenses, party behavior, enemy roles, progression and loot.

For every combat task:

1. Read the relevant DS2 section and state what DS2 does.
2. Implement that behavior as the starting point wherever Curse has the corresponding systems.
3. Preserve any engine-visible uncertainty instead of inventing an exact DS2 rule.
4. Suggestions to improve feel, clarity, balance or physicality are welcome, but label them as deliberate departures and bring material
   choices to the owner. Never let a convenience change silently replace the DS2 foundation.
5. Tests should lock both the copied baseline and any approved Curse-specific improvement.

Current example—Brutal Attack recharge:

```text
reload damage = 21 × (6 + 1.5 × hero level) × (1 + 0.022 × hero level) × active group members
```

After the power lands, subsequent damage dealt by the active party subtracts from that budget. Waiting does nothing. The power's own
damage does not refill itself. Its stored activation survives a miss, dodge, block, dead target or out-of-range swing and is spent only
by a successful melee hit. The visible armed state is a restrained orange heat haze that traces just outside the character's
silhouette like rising steam, based on the owner's direct DS2 screenshot. It is not a weapon coating, ground pool, or fire cloud.

Current example—Take Aim: Cutter automatically arms DS2's first Ranged power when ready. His next successful arrow deals 1500%
weapon damage, cannot crit, and spends the power only when it connects. It uses the same 21-second active-party damage recharge
formula as Brutal Attack. A miss, blocked shot, lost target or arrow striking terrain preserves it.

## The DS2 character and combat model (2026-10, owner decision)

Implemented from `ds2-combat-and-loot.md` and locked by `--only=classskills`, `--only=ds2combat` and `--only=xp`:

* **Levels and XP** (`HeroProgression`): character level 1-100 on DS2's experience table. DS2 monster XP (`48 + 12L` under 12, the
  steeper curve above) times the tier, the level-gap multiplier (both ways, floor 5%), and DS2's party bonus with Cutter (90% each).
* **Class skills and attributes** (`HeroAttributes`): Melee, Ranged, Combat Magic, Nature Magic rise from XP; STR/DEX/INT follow DS2's
  3:1:1 weights from the human start 12/11/11; life and mana are DS2's formulas; regeneration 1% a second. A level-up restores life and
  mana and recharges every power.
* **Combat** (`Combat`): no accuracy roll (dodge and shield block only), crit 200%, powers never crit, armour
  `min(8 + 2L, armour) / armour`, level gap x0.75 / x0.5 / x0.25, hero resistance cap 80%, floor 1. Hero melee is the weapon plus
  `0.2 x STR` (0.75 / 1.25 on the low / high roll); thrown uses DEX; Fireball is a DS2 spell (damage and mana grow with INT).
* **Monsters** (`MonsterScaling`): DS2 life, damage per hit and armour by level, tier (`EnemyDef.tier`) and role (`EnemyDef.role`).

Curse choices where DS2's engine is not visible, or the owner chose differently (each is a deliberate, labelled departure):

* **XP on the kill** (owner): DS2 pays hit by hit; Curse pays when the monster dies, and splits the hero's share over his class skills
  by the damage each did. XP no hit earned (quests, nests) goes to his most-used class skill.
* **Class-skill table**: a class skill uses the character table one step behind (0 untrained, 1 at 300 XP), so a pure level 30 fighter
  is Melee 29 = 99 / 40 / 40, matching DS2's design note (about 100 / 40 / 40). Each class level adds its 3/1/1 weights.
* **Experience table**: DS2's documented points are exact; the levels between them are filled in geometrically.
* **Monster level** (`WorldThreat.monster_level`): the world's threat dial maps to a DS2 level (threat 1.25 = level 1, 12 levels per
  point), so the road opens at level 1 as DS2 does.
* **Crit**: the second hit is taken equal to the first (200%), since a blow arrives already rolled.
* **Fireball**: DS2's table values (53 at INT 100, 105 at INT 200) fitted as `1 + 0.52 x INT`; mana `0.82 x INT`.
* **Heavy blows**: DS2 has no stagger roll. Curse keeps its physical knockdown: a blow of weight 2.0 or more (a Brute's heavy swing,
  the Warden's special) puts the hero down. The Zombasite "crushing" and "deep wounds" outcomes are gone.

## DS2 items (2026-10, owner decision; locked by `--only=ds2items`)

* **Slots**: weapon, shield, helm, body, gloves, boots, amulet, two rings (`Items.Slot`). A two-handed weapon and a shield push each other off.
* **Bases** (`ItemDef`): five item levels each (DS2's base and var1-var4). Weapon damage per hit is DS2's curve by type (1H `3.4 + 0.74L`, 2H
  `5.2 + 1.2L`, x0.75 / x1.25); armour `class x slot x (16 + 4L)` (fighter 1.0, ranger 0.8; body 0.5, helm and shield 0.2, gloves and boots 0.15).
* **Rarities**: Normal, Magic (1-2 modifiers), Rare, Unique, Set. Modifiers are DS2's families and tiers (`AffixDef`), one per family.
* **Requirement** (DS2's `equip_requirements`, item level - 2): weapons Melee, armour its own class's skill (fighter Melee, ranger Ranged,
  mage Combat Magic), rings and amulets the character level (`Items.requirement`).
* **Drops**: DS2's item columns per monster tier (weak 5% / 0.45 / 0.15 / 0.15, normal 8 / 0.75 / 0.25 / 0.25, strong 15 / 1.35 / 0.45 / 0.45),
  the item-level windows (-6..0, -5..+1, -4..+2; rares -4..+2, uniques -40..+3, sets -50..+3), a miniboss's guaranteed piece (30 / 50 / 12 / 4 / 4),
  rewards 70 / 15 / 15, magic find `x (1 + MF/100)` on rare, unique and set.
* **Gear on the hero**: STR/DEX/INT, life, mana, min/max melee, melee %, combat magic %, added fire (before armour), life steal and life per hit,
  armour and armour %, fire resistance, reflect, life and mana recovery, block (with a shield), power recharge, magic find, gold found.

Curse choices (labelled in code):

* **Few bases**: two or three a slot with their levels spread, so a slot has a base near any level; when none fits a drop's window the nearest
  variant drops. Ice, lightning and death damage, ranged-only and class-skill modifiers wait for those systems.
* **A magic item's modifier window** (DS2 leaves it to the engine) is `item level - 20 ... item level`; a rare's is DS2's `-25 ... +5`, with 3 or 4
  modifiers (DS2: engine-side).
* **DS2's "#" item** drops plain half the time, with one modifier 30% and two 20%. Jewellery is never plain.
* **Stance passives** DS2 also asks for (Barricade for a shield, Overbear for two hands) arrive with the passive trees.
* **Gold and potions** stay Curse's own (gold per kill, health orbs); only the item columns of DS2's tables are used.
* **The hero's thrown blade** is his melee weapon, so it keeps the melee damage modifiers.

## DS2 skill points and passives (2026-10, owner decision; locked by `--only=skilltree`)

* **Skill points**: one a character level after the first, plus a human's two (`TownState.skill_points_total`). Spent one rank at a time on
  passives (20 ranks each), chosen with + and -, then confirmed for good: DS2 has no respec (`SkillTreeView`, from the character screen).
* **Gates**: each passive opens at its tree's class skill level (DS2's tiers 1, 5, 12, 24, 36) and may need ranks in another first.
* **Stances**: a two-handed weapon needs Overbear 1, a shield Barricade 1 (`Items.requirement`).
* **Effects** (rank 1 -> 20, DS2's): Fortitude life +6-45%, Critical Strike 8-50%, Overbear two-handed damage +8-50%, Toughness physical
  damage taken -3-26%, Barricade block +2-20% and shield armour +20-120%, Alacrity melee speed +3-25%, Smite two-handed stun 5-50% for 1-2 s,
  Reinforced Armor +4-35%, Fierce Renewal Brutal Attack recharge +3-30%, Rebuke a block hits back for 0.4-2.5 x Melee level and stuns,
  Deadly Strike crits 224-350%; Critical Shot 8-50% (no effect until the hero has a ranged attack), Dodge 4-40%, Quick Draw (thrown attack
  rate, no effect until throwing weapons) +3-25%, Survival fire resistance
  +10-60%, Bleed (thrown) 10-25% for 0.06-0.5 x DEX a second, 4 s; Brilliance mana +7-150%, Devastation combat magic +10-60%, Searing Flames
  fire +8-60%, Quickened Casting +4-25%, Ignite chance `rank x damage / (1.2 + 0.6 INT)`, 0.08-0.5 x INT a second for 3 s.

Every passive follows DS2's own 20-rank table (`docs/ds2_passives_reference.md`; the curve flattens toward rank 20), and so do the
second values: Barricade's shield armour, Smite's and Rebuke's stun (1 / 1.25 / 1.5 / 2 s), Bleed's damage, Ignite's chance (5-30: DS2's `rules.skrit` rolls
`increased_ignite_chance x damage / (1.2 + 0.6 INT)` against a random 0-100, so the table value is a percentage).

Curse choices (labelled in `tools/write_passive_defs.py`):

* **Tiers and prerequisites** are DS2's own (`ds2-combat-and-loot.md` 6.1), except that Alacrity asks for Critical Strike instead of DS2's
  Dual Wield, which Curse does not have.
* **Left out** until Curse has the mechanic: Dual Wield, the bow and crossbow passives, summons, ice, lightning, death, curses and the Nature
  Magic tree. Cunning Renewal waits for a hero ranged power.
* **Deadly Strike** also raises the hero's thrown crits (DS2 gives bows Mortal Wound; Curse's thrown blade is his sword).

## DS2 powers (2026-10, owner decision; locked by `--only=powers`)

* All 27 of DS2's hero powers are data (`PowerDef`, `tools/write_power_defs.py`, from `ds2_powers_reference.md`): three ranks, each
  opened by passive ranks (nothing is spent on a power), no mana, no cooldown, recharged by damage dealt (12 / 21 / 35 / 60 seconds of
  DS2's combat formula), a stance, and the numbers per rank as expressions in the class levels.
* A power whose `needs` is set is shown on the skill screen but cannot be used until Curse has the system (dual wielding, bows,
  throwing weapons, ice, lightning, death damage, summons, the Nature tree). Brutal Attack and Take Aim are live: Brutal Attack opens with
  Critical Strike 1 and its damage follows its rank (rank 3 at Critical Strike 8).
* Owner decision: Power Strike, Skewer, Leap, Earthshatter and Weapon Throw are retired, replaced by the DS2 powers that play (Whirling
  Strike, Staggering Blow, War Cry, Provoke, Repulse, Silence, Flame Nexus, Detonation). Fireball stays: in DS2 it is a spell, not a power.
  With Weapon Throw gone, Critical Shot, Quick Draw and Bleed have no effect until throwing weapons or bows exist; they stay buyable as
  DS2's path through the Ranged tree.

**Playable now** (`PowerController`, `--only=livepowers`): Whirling Strike (spin, every enemy within 3-4 m, 1.5 s stun), Staggering Blow
(two-handed; armed, released by the next blow that lands: a shockwave of 2.75-4 m that stuns 6-10 s), War Cry (a cone in front: armour
-35 to -60% for 20 s and the enemies flee; the next 8-15 blows crit), Provoke (shield; the enemies within 6-8 m turn on the hero, armour
+25-50% for 5-10 s), Repulse (12-20 s: an enemy that comes within 3-4 m is thrown 3-7 m and stunned 1.5 s), Silence (an area of 4-6 m:
no spells, so no priest wards or raisings, for 15-25 s), Flame Nexus and Detonation (fire around the hero / at the target, never dodged,
grown by Searing Flames, setting victims alight 4 s at 0.1 x INT as DS2's fire powers do). They go on the hotbar like any skill.

Curse choices: every rank's values are DS2's own, except that Take Aim's ranks 1 and 2 grow with Ranged where DS2's file says Melee (a
slip: rank 3 and every other ranged power use Ranged); DS2's `desperate_frenzy`
is Deadly Strike (confirmed in passive_skills.gas); War Cry's cone (8 m, 70 degrees), its fear (4 s), Flame Nexus's radius (4 m) and the reach of
targeted powers (14 m) are Curse's (DS2's file gives only dummy radii); Cutter buys no passives, so his Take Aim stays at rank 1 and grows with his Ranged level.
