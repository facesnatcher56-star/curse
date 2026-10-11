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
* **Weapon damage until DS2 items**: an item's tier stands in for its item level on DS2's one-handed curve (`3.4 + 0.74L`).
