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
