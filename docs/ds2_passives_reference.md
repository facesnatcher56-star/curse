# Dungeon Siege II - Passive Skills 20-Rank Tables Reference

### Fortitude (`fortitude`)
**Description**: Maximum Health: +~increased_hitpoints~%

#### `[increased_hitpoints]`
```gas
[increased_hitpoints]
{
	level_1 = 6; level_2 = 10; level_3 = 14; level_4 = 18; level_5 = 21;
	level_6 = 24; level_7 = 26; level_8 = 28; level_9 = 30; level_10 = 32;
	level_11 = 34; level_12 = 36; level_13 = 38; level_14 = 39; level_15 = 40;
	level_16 = 41; level_17 = 42; level_18 = 43; level_19 = 44; level_20 = 45;
}
```

### Critical Strike (`critical_strike`)
**Description**: Chance to Inflict Critical Hit: ~melee_critical_chance~%\nCritical Hits Deal 200.0% Damage

#### `[melee_critical_chance]`
```gas
[melee_critical_chance]
{
	level_1 = 8; level_2 = 14; level_3 = 18; level_4 = 22; level_5 = 25.5;
	level_6 = 28.5; level_7 = 31; level_8 = 33.5; level_9 = 36; level_10 = 38;
	level_11 = 40; level_12 = 41.5; level_13 = 43; level_14 = 44.5; level_15 = 46;
	level_16 = 47; level_17 = 48; level_18 = 49; level_19 = 49.5; level_20 = 50;
}
```

### Barricade (`aegis`)
**Description**: Character can equip shields\nShield Armor: +~increased_shield_defense_percentage~%\nChance To Block Melee: ~increased_melee_block_chance~%\nChance To Block Ranged: ~increased_ranged_block_chance~%

#### `[increased_shield_defense_percentage]`
```gas
[increased_shield_defense_percentage]
{
	level_1 = 20; level_2 = 35; level_3 = 45; level_4 = 55; level_5 = 63;
	level_6 = 70; level_7 = 76; level_8 = 82; level_9 = 88; level_10 = 93;
	level_11 = 98; level_12 = 102; level_13 = 106; level_14 = 109; level_15 = 112;
	level_16 = 114; level_17 = 116; level_18 = 118; level_19 = 119; level_20 = 120;
}
```

#### `[increased_melee_block_chance]`
```gas
[increased_melee_block_chance]
{
	level_1 = 2; level_2 = 4; level_3 = 6; level_4 = 8; level_5 = 9;
	level_6 = 10; level_7 = 11; level_8 = 12; level_9 = 13; level_10 = 14;
	level_11 = 15; level_12 = 16; level_13 = 16.5; level_14 = 17; level_15 = 17.5;
	level_16 = 18; level_17 = 18.5; level_18 = 19; level_19 = 19.5; level_20 = 20;
}
```

#### `[increased_ranged_block_chance]`
```gas
[increased_ranged_block_chance]
{
	level_1 = 2; level_2 = 4; level_3 = 6; level_4 = 8; level_5 = 9;
	level_6 = 10; level_7 = 11; level_8 = 12; level_9 = 13; level_10 = 14;
	level_11 = 15; level_12 = 16; level_13 = 16.5; level_14 = 17; level_15 = 17.5;
	level_16 = 18; level_17 = 18.5; level_18 = 19; level_19 = 19.5; level_20 = 20;
}
```

### Overbear (`overbear`)
**Description**: Character can equip two-handed melee weapons\nTwo-Handed Weapon Damage: +~increased_2h_weapon_damage~%

#### `[increased_2h_weapon_damage]`
```gas
[increased_2h_weapon_damage]
{
	level_1 = 8; level_2 = 14; level_3 = 18; level_4 = 22; level_5 = 25.5;
	level_6 = 28.5; level_7 = 31; level_8 = 33.5; level_9 = 36; level_10 = 38;
	level_11 = 40; level_12 = 41.5; level_13 = 43; level_14 = 44.5; level_15 = 46;
	level_16 = 47; level_17 = 48; level_18 = 49; level_19 = 49.5; level_20 = 50;
}
```

### Toughness (`toughness`)
**Description**: Physical Damage Resistance: ~physical_damage_resistance_percentage~%

#### `[physical_damage_resistance_percentage]`
```gas
[physical_damage_resistance_percentage]
{
	level_1 = 3; level_2 = 5; level_3 = 7; level_4 = 9; level_5 = 11;
	level_6 = 12.5; level_7 = 14; level_8 = 15.5; level_9 = 17; level_10 = 18;
	level_11 = 19; level_12 = 20; level_13 = 21; level_14 = 22; level_15 = 23;
	level_16 = 24; level_17 = 24.5; level_18 = 25; level_19 = 25.5; level_20 = 26;
}
```

### Alacrity (`alacrity`)
**Description**: Melee Attack Speed: +~increased_melee_attack_speed~%

#### `[increased_melee_attack_speed]`
```gas
[increased_melee_attack_speed]
{
	level_1 = 3; level_2 = 5; level_3 = 7; level_4 = 9; level_5 = 10;
	level_6 = 11; level_7 = 12; level_8 = 13; level_9 = 14; level_10 = 15;
	level_11 = 16; level_12 = 17; level_13 = 18; level_14 = 19; level_15 = 20;
	level_16 = 21; level_17 = 22; level_18 = 23; level_19 = 24; level_20 = 25;
}
```

### Smite (`smite`)
**Description**: Two-Handed Weapon Stun Chance: ~melee_2H_stun_chance~%\nStun Duration: ~melee_2H_stun_duration~ seconds

#### `[melee_2H_stun_chance]`
```gas
[melee_2H_stun_chance]
{
	level_1 = 5; level_2 = 10; level_3 = 14; level_4 = 18; level_5 = 22;
	level_6 = 25; level_7 = 28; level_8 = 31; level_9 = 34; level_10 = 36;
	level_11 = 38; level_12 = 40; level_13 = 42; level_14 = 44; level_15 = 45;
	level_16 = 46; level_17 = 47; level_18 = 48; level_19 = 49; level_20 = 50;
}
```

#### `[melee_2H_stun_duration]`
```gas
[melee_2H_stun_duration]
{
	level_1 = 1; level_2 = 1; level_3 = 1; level_4 = 1; level_5 = 1;
	level_6 = 1.25; level_7 = 1.25; level_8 = 1.25; level_9 = 1.25; level_10 = 1.25;
	level_11 = 1.5; level_12 = 1.5; level_13 = 1.5; level_14 = 1.5; level_15 = 1.5;
	level_16 = 2; level_17 = 2; level_18 = 2; level_19 = 2; level_20 = 2;
}
```

### Reinforced Armor (`reinforced_armor`)
**Description**: Armor: +~increased_armor~%

#### `[increased_armor]`
```gas
[increased_armor]
{
	level_1 = 4; level_2 = 7; level_3 = 10; level_4 = 13; level_5 = 15;
	level_6 = 17; level_7 = 19; level_8 = 21; level_9 = 23; level_10 = 24.5;
	level_11 = 26; level_12 = 27.5; level_13 = 29; level_14 = 30; level_15 = 31;
	level_16 = 32; level_17 = 33; level_18 = 34; level_19 = 34.5; level_20 = 35;
}
```

### Fierce Renewal (`fierce_renewal`)
**Description**: Melee Power Recovery Rate: +~increased_melee_power_recovery~%

#### `[increased_melee_power_recovery]`
```gas
[increased_melee_power_recovery]
{
	level_1 = 3; level_2 = 6; level_3 = 8; level_4 = 10; level_5 = 12;
	level_6 = 14; level_7 = 16; level_8 = 17.5; level_9 = 19; level_10 = 20.5;
	level_11 = 22; level_12 = 23; level_13 = 24; level_14 = 25; level_15 = 26;
	level_16 = 26; level_17 = 27; level_18 = 28; level_19 = 29; level_20 = 30;
}
```

### Rebuke (`rebuke`)
**Description**: Rebukes Opponent when Character Blocks a Melee Attack\nRebuke Damage: ~rebuke_damage~ * Melee Level\nRebuke Stun Time: ~rebuke_stun_time~ seconds

#### `[rebuke_damage]`
```gas
[rebuke_damage]
{
	level_1 = 0.4; level_2 = 0.7; level_3 = 0.9; level_4 = 1.1; level_5 = 1.3;
	level_6 = 1.45; level_7 = 1.6; level_8 = 1.7; level_9 = 1.8; level_10 = 1.9;
	level_11 = 1.98; level_12 = 2.06; level_13 = 2.14; level_14 = 2.22; level_15 = 2.3;
	level_16 = 2.34; level_17 = 2.38; level_18 = 2.42; level_19 = 2.46; level_20 = 2.5;
}
```

#### `[rebuke_stun_time]`
```gas
[rebuke_stun_time]
{
	level_1 = 1; level_2 = 1; level_3 = 1; level_4 = 1; level_5 = 1;
	level_6 = 1.25; level_7 = 1.25; level_8 = 1.25; level_9 = 1.25; level_10 = 1.25;
	level_11 = 1.5; level_12 = 1.5; level_13 = 1.5; level_14 = 1.5; level_15 = 1.5;
	level_16 = 2; level_17 = 2; level_18 = 2; level_19 = 2; level_20 = 2;
}
```

### Critical Shot (`critical_shot`)
**Description**: Chance to Inflict Critical Hit: ~ranged_critical_chance~%\nCritical Hits Deal 200.0% Damage

#### `[ranged_critical_chance]`
```gas
[ranged_critical_chance]
{
	level_1 = 8; level_2 = 14; level_3 = 18; level_4 = 22; level_5 = 25.5;
	level_6 = 28.5; level_7 = 31; level_8 = 33.5; level_9 = 36; level_10 = 38;
	level_11 = 40; level_12 = 41.5; level_13 = 43; level_14 = 44.5; level_15 = 46;
	level_16 = 47; level_17 = 48; level_18 = 49; level_19 = 49.5; level_20 = 50;
}
```

### Dodge (`dodge`)
**Description**: Chance to Dodge Melee or Ranged Attacks: ~ranged_dodge_chance~%

#### `[ranged_dodge_chance]`
```gas
[ranged_dodge_chance]
{
	level_1 = 4; level_2 = 7; level_3 = 10; level_4 = 13; level_5 = 16;
	level_6 = 18; level_7 = 20; level_8 = 22; level_9 = 24; level_10 = 26;
	level_11 = 28; level_12 = 30; level_13 = 32; level_14 = 34; level_15 = 35;
	level_16 = 36; level_17 = 37; level_18 = 38; level_19 = 39; level_20 = 40;
}
```

### Quick Draw (`quick_draw`)
**Description**: Character can equip thrown weapons\nThrown Weapon Firing Rate: +~increased_ranged_thrown_attack_speed~%

#### `[increased_ranged_thrown_attack_speed]`
```gas
[increased_ranged_thrown_attack_speed]
{
	level_1 = 3; level_2 = 5; level_3 = 7; level_4 = 9; level_5 = 10;
	level_6 = 11; level_7 = 12; level_8 = 13; level_9 = 14; level_10 = 15;
	level_11 = 16; level_12 = 17; level_13 = 18; level_14 = 19; level_15 = 20;
	level_16 = 21; level_17 = 22; level_18 = 23; level_19 = 24; level_20 = 25;
}
```

### Survival (`survival`)
**Description**: Fire Damage Resistance: +~survival_fire_resistance_percentage~%\nIce Damage Resistance: +~survival_ice_resistance_percentage~%\nLightning Damage Resistance: +~survival_lightning_resistance_percentage~%\nCan Harvest Health Potions

#### `[survival_fire_resistance_percentage]`
```gas
[survival_fire_resistance_percentage]
{
	level_1 = 10; level_2 = 17; level_3 = 22; level_4 = 27; level_5 = 31;
	level_6 = 35; level_7 = 38; level_8 = 41; level_9 = 44; level_10 = 46.5;
	level_11 = 49; level_12 = 51; level_13 = 53; level_14 = 55; level_15 = 56;
	level_16 = 57; level_17 = 58; level_18 = 59; level_19 = 59.5; level_20 = 60;
}
```

#### `[survival_ice_resistance_percentage]`
```gas
[survival_ice_resistance_percentage]
{
	level_1 = 10; level_2 = 17; level_3 = 22; level_4 = 27; level_5 = 31;
	level_6 = 35; level_7 = 38; level_8 = 41; level_9 = 44; level_10 = 46.5;
	level_11 = 49; level_12 = 51; level_13 = 53; level_14 = 55; level_15 = 56;
	level_16 = 57; level_17 = 58; level_18 = 59; level_19 = 59.5; level_20 = 60;
}
```

#### `[survival_lightning_resistance_percentage]`
```gas
[survival_lightning_resistance_percentage]
{
	level_1 = 10; level_2 = 17; level_3 = 22; level_4 = 27; level_5 = 31;
	level_6 = 35; level_7 = 38; level_8 = 41; level_9 = 44; level_10 = 46.5;
	level_11 = 49; level_12 = 51; level_13 = 53; level_14 = 55; level_15 = 56;
	level_16 = 57; level_17 = 58; level_18 = 59; level_19 = 59.5; level_20 = 60;
}
```

#### `[health_harvested]`
```gas
[health_harvested]
{
	level_1 = 1; level_2 = 2; level_3 = 3; level_4 = 4; level_5 = 5;
	level_6 = 6; level_7 = 7; level_8 = 8; level_9 = 9; level_10 = 10;
	level_11 = 11; level_12 = 12; level_13 = 13; level_14 = 14; level_15 = 15;
	level_16 = 16; level_17 = 17; level_18 = 18; level_19 = 19; level_20 = 20;
}
```

### Bleed (`bleed`)
**Description**: Chance to Cause Bleed: ~increased_bleed_percentage~% \nDamage per Second: ~bleed_damage~ * Dexterity\nBleed Duration: ~bleed_duration~ seconds

#### `[increased_bleed_percentage]`
```gas
[increased_bleed_percentage]
{
	level_1 = 10; level_2 = 15; level_3 = 18; level_4 = 22; level_5 = 25;
	level_6 = 25; level_7 = 25; level_8 = 25; level_9 = 25; level_10 = 25;
	level_11 = 25; level_12 = 25; level_13 = 25; level_14 = 25; level_15 = 25;
	level_16 = 25; level_17 = 25; level_18 = 25; level_19 = 25; level_20 = 25;
}
```

#### `[bleed_damage]`
```gas
[bleed_damage]
{
	level_1 = 0.06; level_2 = 0.11; level_3 = 0.15; level_4 = 0.19; level_5 = 0.23;
	level_6 = 0.26; level_7 = 0.29; level_8 = 0.315; level_9 = 0.34; level_10 = 0.36;
	level_11 = 0.38; level_12 = 0.4; level_13 = 0.42; level_14 = 0.435; level_15 = 0.45;
	level_16 = 0.46; level_17 = 0.47; level_18 = 0.48; level_19 = 0.49; level_20 = 0.5;
}
```

#### `[bleed_duration]`
```gas
[bleed_duration]
{
	level_1 = 4.0; level_2 = 4.0; level_3 = 4.0; level_4 = 4.0; level_5 = 4.0;
	level_6 = 4.0; level_7 = 4.0; level_8 = 4.0; level_9 = 4.0; level_10 = 4.0;
	level_11 = 4.0; level_12 = 4.0; level_13 = 4.0; level_14 = 4.0; level_15 = 4.0;
	level_16 = 4.0; level_17 = 4.0; level_18 = 4.0; level_19 = 4.0; level_20 = 4.0;
}
```

### Brilliance (`brilliance`)
**Description**: Maximum Mana: +~increased_mana~%

#### `[increased_mana]`
```gas
[increased_mana]
{
	level_1 = 7; level_2 = 14; level_3 = 21; level_4 = 28; level_5 = 36;
	level_6 = 44; level_7 = 52; level_8 = 60; level_9 = 68; level_10 = 76;
	level_11 = 83; level_12 = 90; level_13 = 97; level_14 = 105; level_15 = 113;
	level_16 = 121; level_17 = 129; level_18 = 136; level_19 = 143; level_20 = 150;
}
```

### Devastation (`devastation`)
**Description**: Combat Magic Damage: +~increased_combat_damage~%

#### `[increased_combat_damage]`
```gas
[increased_combat_damage]
{
	level_1 = 10; level_2 = 17; level_3 = 22; level_4 = 27; level_5 = 31;
	level_6 = 35; level_7 = 38; level_8 = 41; level_9 = 44; level_10 = 46.5;
	level_11 = 49; level_12 = 51; level_13 = 53; level_14 = 55; level_15 = 56;
	level_16 = 57; level_17 = 58; level_18 = 59; level_19 = 59.5; level_20 = 60;
}
```

### Searing Flames (`searing_flames`)
**Description**: Fire Magic Damage: +~increased_fire_damage~%\nFire Power Damage: +~increased_fire_damage~%

#### `[increased_fire_damage]`
```gas
[increased_fire_damage]
{
	level_1 = 8; level_2 = 14; level_3 = 20; level_4 = 24; level_5 = 28;
	level_6 = 32; level_7 = 36; level_8 = 39; level_9 = 42; level_10 = 44;
	level_11 = 46; level_12 = 48; level_13 = 50; level_14 = 52; level_15 = 54;
	level_16 = 56; level_17 = 57; level_18 = 58; level_19 = 59; level_20 = 60;
}
```

### Quickened Casting (`quickened_casting`)
**Description**: Cast Speed: +~increased_magic_attack_speed~%

#### `[increased_magic_attack_speed]`
```gas
[increased_magic_attack_speed]
{
	level_1 = 4; level_2 = 7; level_3 = 10; level_4 = 12; level_5 = 14;
	level_6 = 15.5; level_7 = 17; level_8 = 18; level_9 = 19; level_10 = 20;
	level_11 = 21; level_12 = 21.75; level_13 = 22.5; level_14 = 23; level_15 = 23.5;
	level_16 = 24; level_17 = 24.25; level_18 = 24.5; level_19 = 24.75; level_20 = 25;
}
```

### Ignite (`ignite`)
**Description**: Chance to Ignite: ~increased_ignite_chance~%\nIgnite Damage per Second: ~ignite_damage_per_second~ * Intelligence\nIgnite Duration: ~ignite_duration~ seconds

#### `[increased_ignite_chance]`
```gas
[increased_ignite_chance]
{
	level_1 = 5; level_2 = 8; level_3 = 11; level_4 = 13; level_5 = 15;
	level_6 = 17; level_7 = 18.5; level_8 = 20; level_9 = 21.5; level_10 = 22.5;
	level_11 = 23.5; level_12 = 24.5; level_13 = 25.5; level_14 = 26.5; level_15 = 27.25;
	level_16 = 28; level_17 = 28.5; level_18 = 29; level_19 = 29.5; level_20 = 30;
}
```

#### `[ignite_damage_per_second]`
```gas
[ignite_damage_per_second]
{
	level_1 = 0.08; level_2 = 0.14; level_3 = 0.18; level_4 = 0.22; level_5 = 0.25;
	level_6 = 0.28; level_7 = 0.31; level_8 = 0.33; level_9 = 0.35; level_10 = 0.37;
	level_11 = 0.39; level_12 = 0.41; level_13 = 0.43; level_14 = 0.44; level_15 = 0.45;
	level_16 = 0.46; level_17 = 0.47; level_18 = 0.48; level_19 = 0.49; level_20 = 0.5;
}
```

#### `[ignite_duration]`
```gas
[ignite_duration]
{
	level_1 = 3.0; level_2 = 3.0; level_3 = 3.0; level_4 = 3.0; level_5 = 3.0;
	level_6 = 3.0; level_7 = 3.0; level_8 = 3.0; level_9 = 3.0; level_10 = 3.0;
	level_11 = 3.0; level_12 = 3.0; level_13 = 3.0; level_14 = 3.0; level_15 = 3.0;
	level_16 = 3.0; level_17 = 3.0; level_18 = 3.0; level_19 = 3.0; level_20 = 3.0;
}
```
