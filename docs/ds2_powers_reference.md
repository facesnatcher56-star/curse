# Dungeon Siege II: Powers (Active Skills) Reference

Extracted directly from installed game data (`active_skills.gas`, `Logic.ds2res`).

Baseline data for Phase 6 combat powers, weapon stances, recharge formulas, area radii, and numerical scaling per rank.

---

## 1. Power Recharge Mechanics

Active skills in DS2 do not cost mana and do not have timed cooldowns. Instead, they recharge via **Damage Dealt in Combat** by the active party.

```text
reload_damage = SECONDS * (6 + 1.5 * character_level) * (1 + 0.022 * character_level) * active_party_members
```

Recharge durations by tier:

* **Very Fast Recharge**: 12 seconds of party combat damage

* **Fast Recharge**: 21 seconds of party combat damage

* **Medium Recharge**: 35 seconds of party combat damage

* **Long Recharge**: 60 seconds of party combat damage

---

## Melee (Fighter) Powers

### Brutal Attack (`brutal_attack`)
* **Summary**: Though originated by Half-Giant warriors, many warriors learn this technique. Focusing all their strength into their next attack, fighters deal massive damage with a single, brutal strike.\n\nCan only be used with a melee weapon\nAutomatically Enhances Next Attack\nFast Recharge
* **Stances Required**: `AS_SINGLE_MELEE, AS_SINGLE_MELEE_AND_SHIELD, AS_TWO_HANDED_MELEE, AS_TWO_HANDED_SWORD, AS_DUAL_WIELD, AS_STAFF`
* **Target Type**: `tt_conscious_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `21 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: critical_strike: 1
  * **Rank_2**: critical_strike: 5
  * **Rank_3**: critical_strike: 8
* **Rank Scaling (Skill Values)**:
  * `melee_brutal_attack_damage_bonus_percentage`:
    * **// Damage**: `((Character Damage / Second ) / (Fighter Attack Damage)) * Power Effectiveness * Reload Time * .83 for Skills) / # of hits // = ((1/0.75) * PE * 20 * .83 + 100) / 1 = PE * 22.13 + 100 // Damage * 3/4 because focused damage is VERY GOOD = PE * 16.6 + 75 level_1 = 1500 + 25 * #src_melee`
    * **// Power Effectiveness**: `180% = 115% + 3.6% per level (level 18)`


### Provoke (`provoke`)
* **Summary**: Knights protect their allies by using their shields to provoke nearby enemies, causing them to become angry and attack the knight. The knight's concentration also temporarily increases his armor.\n\nCan only be used when equipped with a shield\nAutomatically Provokes Enemies around Self\nFast Recharge
* **Stances Required**: `AS_SINGLE_MELEE_AND_SHIELD,AS_SHIELD_ONLY`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `12 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: aegis: 1
  * **Rank_2**: aegis: 6, toughness: 4
  * **Rank_3**: aegis: 10, toughness: 10, rebuke: 5
* **Rank Scaling (Skill Values)**:
  * `melee_provoke_radius`:
    * **level_1**: `6`
    * **level_2**: `7`
    * **level_3**: `8`
  * `melee_provoke_armor_percentage`:
    * **// Final Armor**: `Armor * (1 + 0.01 * (% Armor Bonus)) level_1 = 25`
    * **level_2**: `30`
    * **level_3**: `50`
  * `melee_provoke_armor_duration`:
    * **level_1**: `5`
    * **level_2**: `8`
    * **level_3**: `10`


### Whirling Strike (`whirling_strike`)
* **Summary**: A legendary fighter known only as the Tempest of Tel'kilae originated this technique, in which the fighter whirls his weapons in a circle, damaging and briefly stunning all nearby enemies.\n\nCan only be used with a melee weapon\nAutomatically Strikes Enemies around Self\nNormal Recharge
* **Stances Required**: `AS_SINGLE_MELEE, AS_SINGLE_MELEE_AND_SHIELD, AS_TWO_HANDED_MELEE, AS_TWO_HANDED_SWORD, AS_DUAL_WIELD, AS_STAFF`
* **Target Type**: `tt_self | tt_conscious_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: critical_strike: 6, fortitude: 8
  * **Rank_2**: critical_strike: 8, fortitude: 10, reinforced_armor: 6
  * **Rank_3**: critical_strike: 12, fortitude: 12, reinforced_armor: 12
* **Rank Scaling (Skill Values)**:
  * `melee_whirling_strike_radius`:
    * **level_1**: `3`
    * **// 5 enemies
				level_2**: `3.5`
    * **// 5 enemies
				level_3**: `4`
  * `melee_whirling_strike_damage_percentage`:
    * **// Damage**: `((Fighter Damage / Second) / (Fighter Weapon Damage)) * Power Effectiveness * Reload Time * .83 for Skills) / # of hits // = ((1/.75) * PE * 30 * .8 because it stuns * .83 + 100) / # of hits = 5.3 * PE + 20 level_1 = 920 + 9 * #src_melee`
    * **// Power Effectiveness**: `470% = 260% + 3.6% per level (level 58)`
  * `melee_whirling_strike_stun_duration`:
    * **level_1**: `1.5`
    * **level_2**: `1.5`
    * **level_3**: `1.5`


### Staggering Blow (`staggering_blow`)
* **Summary**: When a two-handed weapon master activates this ability, his next attack will be a Staggering Blow. He slams his weapon into his target, creating a shockwave that stuns any enemies caught within it.\n\nCan only be used with a two-handed melee weapon\nAutomatically Enhances Next Attack\nNormal Recharge
* **Stances Required**: `AS_TWO_HANDED_MELEE, AS_TWO_HANDED_SWORD, AS_STAFF`
* **Target Type**: `tt_conscious_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: overbear: 1
  * **Rank_2**: overbear: 5, toughness: 4
  * **Rank_3**: overbear: 12, toughness: 10, smite: 8
* **Rank Scaling (Skill Values)**:
  * `melee_staggering_blow_damage_percentage`:
    * **// Damage**: `((Fighter Damage / Second) / (Fighter Weapon Damage)) * Power Effectiveness * Reload Time * .83 for Skills) / # of hits // = ((1/.9) * PE * 30 * .5 because it stuns * .83 + 100)/ # of hits = (13.8 * PE + 100) / # of hits level_1 = 400 + 7 * #src_melee`
    * **// Power Effectiveness**: `410% = 230% + 3.6% per level (level 50)`
  * `melee_staggering_blow_duration`:
    * **level_1**: `6.0`
    * **level_2**: `8.0`
    * **level_3**: `10.0`
  * `melee_staggering_blow_radius`:
    * **level_1**: `2.75`
    * **// 3 enemies
				level_2**: `3.25`
    * **// 4 enemies
				level_3**: `4`


### War Cry (`warcry`)
* **Summary**: Barbarians of the Plain of Tears can unleash a deafening war cry, energizing themselves and terrifying their enemies, causing them to run in fear and leave their defenses open for a short time.\n\nCan only be used with a melee weapon\nCone Effect Targets an Enemy or Terrain\nNormal Recharge
* **Stances Required**: `AS_SINGLE_MELEE, AS_SINGLE_MELEE_AND_SHIELD, AS_TWO_HANDED_MELEE, AS_TWO_HANDED_SWORD, AS_DUAL_WIELD, AS_STAFF`
* **Target Type**: `tt_conscious_enemy | tt_terrain`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: critical_strike: 8, smite: 1
  * **Rank_2**: critical_strike: 12, smite: 8, desperate_frenzy: 2
  * **Rank_3**: critical_strike: 12, smite: 12, desperate_frenzy: 8
* **Rank Scaling (Skill Values)**:
  * `melee_warcry_armor_reduction_duration`:
    * **level_1**: `20.0`
    * **level_2**: `20.0`
    * **level_3**: `20.0`
  * `melee_warcry_armor_reduction_percentage`:
    * **level_1**: `35.0`
    * **// Power Effectiveness**: `150% (level 50) ~2x damage`
  * `melee_warcry_number_critical_hit`:
    * **level_1**: `8`
    * **// Damage Bonus over duration**: `Extra Damage * 12 hits * .9 hits per second / 30 seconds = 36%`
  * `melee_warcry_dummy_radius`:
    * **level_1**: `1`
    * **level_2**: `1`
    * **level_3**: `1`


### Waves of Force (`waves_of_force`)
* **Summary**: A student of Elven dual-weapon techniques learns to perform a beautiful sequence of rapid swings, each creating a wave of force that rushes out in front of her, tearing apart enemies caught in its wake.\n\nCan only be used when dual-wielding two weapons\nTargets an Enemy or Terrain\nNormal Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy | tt_breakable | tt_transmutable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: dual_wield: 1
  * **Rank_2**: dual_wield: 5, alacrity: 4
  * **Rank_3**: dual_wield: 10, alacrity: 10, desperate_frenzy: 8
* **Rank Scaling (Skill Values)**:
  * `melee_waves_damage_percentage`:
    * **// NOTE: Dual Wield powers deal damage based on the damage of the main hand weapon
				// Damage**: `((Fighter Damage / Second) / (Fighter Weapon Damage)) * Power Effectiveness * Reload Time * .78 for Skills) / (# of hits * # of waves) // = ((1/.66) * PE * 30 * .78 + 100) / (3 * 5) = 2.4 * PE + 6.6667 level_1 = 200 + 3.6 * #src_melee`
    * **// Power Effectiveness**: `350% = 200% + 3.6% per level (level 42)`
  * `melee_waves_count`:
    * **level_1**: `5`
    * **level_2**: `5`
    * **level_3**: `5`
  * `melee_waves_frequency`:
    * **// This value is the amount of time between waves, making it a period instead of a frequency
				level_1**: `0.24`
    * **level_2**: `0.24`
    * **level_3**: `0.24`
  * `melee_waves_distance`:
    * **level_1**: `12`
    * **level_2**: `12`
    * **level_3**: `12`
  * `melee_waves_speed`:
    * **level_1**: `10`
    * **level_2**: `10`
    * **level_3**: `10`
  * `melee_waves_dummy_radius`:
    * **level_1**: `1`
    * **level_2**: `1`
    * **level_3**: `1`


### Elemental Rage (`elemental_rage`)
* **Summary**: The highest art of the Elven Blademaster is a meditative frenzy that causes elemental energy to manifest in his weapons and speeds his attacks. Ignoring his own defense, he leaps into battle.\n\nCan only be used when dual-wielding two weapons\nAutomatically Enhances Self\nSlow Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: critical_strike: 8, fierce_renewal: 2
  * **Rank_2**: critical_strike: 10, fierce_renewal: 6, desperate_frenzy: 1
  * **Rank_3**: critical_strike: 14, fierce_renewal: 12, desperate_frenzy: 12
* **Rank Scaling (Skill Values)**:
  * `melee_erage_duration`:
    * **// Duration must be the same for all three levels.
				// Add 2 to intended values to compensate for activation animation
				level_1**: `15`
    * **// 13 seconds + 2
				level_2**: `15`
    * **level_3**: `15`
  * `melee_erage_edamage_min`:
    * **// Damage**: `0.75 * ((Fighter Damage / Second ) * Power Effectiveness * Reload Time * Seconds per Attack) / (# of Elements * Duration * Attack Speed Bonus) // = 0.75 * (8 + 2 * #src_melee) * PE * 40 * 0.66 / (3 * 13 * Attack Speed Bonus) // = (4.1 + 1 * #src_melee) * PE / Attack Speed Bonus level_1 = (3.7 + 0.90 * #src_melee) * (2.0 + 0.015 * #src_melee)`
    * **// Power Effectiveness**: `450% = 250% + 3.6% * #src_melee (level 62), Attack Speed Bonus = 1.15`
  * `melee_erage_edamage_max`:
    * **// Damage**: `1.25 * ((Fighter Damage / Second ) * Power Effectiveness * Reload Time * Time per Attack) / (# of Elements * Duration * Attack Speed Bonus) // = 1.25 * (8 + 2 * #src_melee) * PE * 40 * 0.66 / (3 * 13 * Attack Speed Bonus) // = (6.84 + 1.7 * #src_melee) * PE / Attack Speed Bonus level_1 = (6.2 + 1.54 * #src_melee) * (2.0 + 0.015 * #src_melee)`
    * **// Power Effectiveness**: `450% = 250% + 3.6% * #src_melee (level 56)`
  * `melee_erage_number_elements`:
    * **level_1**: `3`
    * **level_2**: `3`
    * **level_3**: `3`
  * `melee_erage_attack_rate_bonus_percentage`:
    * **level_1**: `10.0`
    * **// 110% normal attack rate
				level_2**: `15.0`
    * **// 115% normal attack rate 
				level_3**: `20.0`
  * `melee_erage_vulnerability_percentage`:
    * **// (1 - Penalty)**: `.25 + .75 * (1 + Percentage) // Percentage = -1.33 * Penalty level_1 = 12`
    * **// Penalty**: `-15%`


---

## Ranged (Archer) Powers

### Take Aim (`take_aim`)
* **Summary**: Dryad archers conceal themselves to surprise their enemies, but their first shot reveals their position. They learn to focus their concentration and take careful aim, making their next shot as devastating as possible.\n\nCan only be used with a bow, crossbow, or thrown weapon\nAutomatically Enhances Next Attack\nFast Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_conscious_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `21 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: critical_shot: 1
  * **Rank_2**: critical_shot: 5
  * **Rank_3**: critical_shot: 8, penetrate: 1
* **Rank Scaling (Skill Values)**:
  * `ranged_take_aim_damage_bonus_percentage`:
    * **// Damage**: `((Character Damage / Second ) / (Ranger Attack Damage)) * Power Effectiveness * Reload Time * .83 for Skills) / # of hits // = ((1/0.75) * PE * 20 * .83 + 100) / 1 = PE * 22.13 + 100 // Damage * 3/4 because focused damage is VERY GOOD = PE * 16.6 + 75 level_1 = 1500 + 25 * #src_melee`
    * **// Power Effectiveness**: `240% = 146% + 3.6% per level (level 26)`


### Thunderous Shot (`thunderous_shot`)
* **Summary**: A thunderous arrow or crossbow bolt travels faster than the eye can see, punching through all enemies in its path and leaving them stunned. Azunai's archers turned many battles with this attack.\n\nCan only be used with a bow or crossbow\nTargets an Enemy or Terrain\nNormal Recharge
* **Stances Required**: `AS_BOW_AND_ARROW, AS_MINIGUN`
* **Target Type**: `tt_conscious_enemy | tt_breakable | tt_terrain`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: biting_arrow: 1
  * **Rank_2**: biting_arrow: 8, far_shot: 1
  * **Rank_3**: biting_arrow: 12, far_shot: 8, mortal_wound: 5
* **Rank Scaling (Skill Values)**:
  * `ranged_thunderous_shot_damage_bonus_percentage`:
    * **// Damage Bonus**: `((Ranger Damage / Second) / (Ranger Weapon Damage)) * Power Effectiveness * Reload Time * .83 for Skills / # of hits // = ((1/.75) * PE * 30 * .5 because it stuns * .83 + 100) / 2.75 = 6 * PE + 35 level_1 = 530 + 9 * #src_ranged`
    * **// Power Effectiveness**: `350% = 200% + 3.6% per level (level 42)`
  * `ranged_thunderous_shot_stun_duration`:
    * **level_1**: `6.0`
    * **level_2**: `8.0`
    * **level_3**: `10.0`
  * `ranged_thunderous_shot_dummy_radius`:
    * **level_1**: `1`
    * **level_2**: `1`
    * **level_3**: `1`


### Silence (`silence`)
* **Summary**: Azunai's armies relied on Dalziel, one of the Champions of the Northern Reaches, to destroy Zaramoth's mages. Dalziel's hatred of their magic manifested as an ability to silence them temporarily, preventing them from casting spells.\n\nArea of Effect Targets an Enemy or Terrain\nFast Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `21 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: dodge: 5, survival: 3
  * **Rank_2**: dodge: 10, survival: 6, mortal_wound: 1
  * **Rank_3**: dodge: 14, survival: 10, mortal_wound: 12
* **Rank Scaling (Skill Values)**:
  * `ranged_silence_radius`:
    * **level_1**: `4`
    * **level_2**: `5`
    * **level_3**: `6`
  * `ranged_silence_duration`:
    * **level_1**: `15`
    * **level_2**: `20`
    * **level_3**: `25`


### Shrapnel Blast (`bursting_missile`)
* **Summary**: When this thrown weapon strikes a target, a blast shatters it into many pieces that fly in all directions. Stories of a single ranger defeating a crowd of foes are often tales of this power in action.\n\nCan only be used with a thrown weapon\nTargets an Enemy or Terrain\nNormal Recharge
* **Stances Required**: `AS_THROWABLE`
* **Target Type**: `tt_conscious_enemy | tt_dead_enemy | tt_breakable | tt_terrain | tt_transmutable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: quick_draw: 1
  * **Rank_2**: quick_draw: 5, bleed: 5
  * **Rank_3**: quick_draw: 10, bleed: 8, penetrate: 6
* **Rank Scaling (Skill Values)**:
  * `ranged_bursting_missile_radius`:
    * **//Radius damage for shrapnel blast
				level_1**: `1.0`
    * **level_2**: `1.0`
    * **level_3**: `1.0`
  * `ranged_bursting_missile_radial_damage`:
    * **// Radial Damage**: `(((Ranger Damage / Second) / (Ranger Weapon Damage)) * Power Effectiveness * Reload Time * .1 because it's not the major damage) / # of enemies hit // = ((1/.75) * PE * 30 * .1) / 4 = 1 * PE level_1 = 80 + 1.5 * #src_ranged`
    * **// Power Effectiveness**: `350% = 200% + 3.6% * #src_ranged (level 42)`
  * `ranged_bursting_missile_damage`:
    * **// Damage**: `((Ranger Damage / Second) / (Ranger Weapon Damage)) * Power Effectiveness * Reload Time) / # of hits // = ((1/.75) * PE * 30 + 100) / # of hits = (33.2 * PE + 100) / # of hits level_1 = 950 + 17 * #src_ranged`
    * **// Power Effectiveness**: `350% = 200% + 3.6% * #src_ranged (level 42)`
  * `ranged_bursting_missile_number`:
    * **level_1**: `5`
    * **// Assume 3 hit
				level_2**: `7`
    * **// Assume 3 hit
				level_3**: `9`
  * `ranged_bursting_missile_dummy_radius`:
    * **level_1**: `1`
    * **level_2**: `1`
    * **level_3**: `1`


### Repulse (`repulse`)
* **Summary**: The Crimson Hunter Laethel liked to get close to his enemies, but developed this ability to survive when they got too close. Repulse knocks enemies away from the ranger and stuns them.\n\nAutomatically Repulses Enemies around Self\nLong Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: dodge: 4, survival: 3
  * **Rank_2**: dodge: 10, survival: 6, ricochet: 1
  * **Rank_3**: dodge: 14, survival: 10, ricochet: 12
* **Rank Scaling (Skill Values)**:
  * `ranged_repulse_radius`:
    * **level_1**: `3.0`
    * **level_2**: `3.5`
    * **level_3**: `4.0`
  * `ranged_repulse_knockback_distance`:
    * **// NOTE: This variable is not used any more
				level_1**: `3`
    * **level_2**: `5`
    * **level_3**: `7`
  * `ranged_repulse_stun_duration`:
    * **level_1**: `1.5`
    * **level_2**: `1.5`
    * **level_3**: `1.5`
  * `ranged_repulse_duration`:
    * **level_1**: `12.0`
    * **level_2**: `16.0`
    * **level_3**: `20.0`


### Flurry (`flurry`)
* **Summary**: Elven adventurers learn to focus their strength into a burst of energy, temporarily allowing them to throw multiple weapons at a rapid rate; but the increase in speed comes at the cost of accuracy.\n\nCan only be used with a thrown weapon\nAutomatically Enhances Self\nLong Recharge
* **Stances Required**: `AS_THROWABLE`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: critical_shot: 8, cunning_renewal: 4
  * **Rank_2**: critical_shot: 10, cunning_renewal: 8, ricochet: 8
  * **Rank_3**: critical_shot: 14, cunning_renewal: 12, ricochet: 12
* **Rank Scaling (Skill Values)**:
  * `ranged_flurry_attack_rate_multiplier`:
    * **level_1**: `1.2`
    * **level_2**: `1.4`
    * **level_3**: `1.5`
  * `ranged_flurry_damage_percentage`:
    * **// NOTE: Flurry is modified by 2 skills, so its damage is multiplied by .7 (8.3^2), not .83
				// Damage**: `((Character Damage / Second ) * Power Effectiveness * Reload Time * .7 for Skills) + 100) / (Duration * Attack Rate Multiplier * # of Projectile Hits per attack) // = ((1) * PE * 40 * .7 + 100) / (Duration * Attack Rate Modifier * 2) // = (28 * PE + 100) / (13 * Attack Rate Modifier * 2) // = (1.076 * PE + 3.85) / (Attack Rate Modifier) // level_1 = 180 + 1.4 * #src_ranged`
    * **// Power Effectiveness**: `525% = 290% + 3.6% per level (level 66) // The base values are close enough to 100% that I am simply plugging in 100 for all of them. level_1 = 180 + 1.4 * #src_ranged`
    * **level_2**: `205 + 2.2 * #src_ranged`
    * **level_3**: `210 + 2.6 * #src_ranged`
  * `ranged_flurry_num_projectiles`:
    * **level_1**: `2`
    * **// Projectiles**: `3, average of 2 hit per throw`
  * `ranged_flurry_duration`:
    * **// Add 2 to intended values to compensate for activation animation
				// All values must be identical - hardcoded in the power
				level_1**: `15`
    * **// 13 seconds + 2
				level_2**: `15`
    * **// 13 seconds + 2 
				level_3**: `15`


---

## Combat Magic Powers

### Energy Orb (`energy_orb`)
* **Summary**: The Elven mage Arinth could summon a ball of energy that hovered above him and shot fire at his enemies. He later perfected it, learning to weave additional types of energy into the orb.\n\nAutomatically Summons Orb Above Self\nFast Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `21 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: brilliance: 1
  * **Rank_2**: brilliance: 4, devastation: 2
  * **Rank_3**: brilliance: 8, devastation: 4
* **Rank Scaling (Skill Values)**:
  * `cmagic_energy_orb_damage_min`:
    * **level_1**: `(20 + 5 * #src_combat_magic_level) * (0.82 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
    * **level_2**: `(20 + 5 * #src_combat_magic_level) * (1.00 + 0.029 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
    * **level_3**: `(20 + 5 * #src_combat_magic_level) * (1.20 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
  * `cmagic_energy_orb_damage_max`:
    * **level_1**: `(30 + 7.5 * #src_combat_magic_level) * (0.82 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
    * **level_2**: `(30 + 7.5 * #src_combat_magic_level) * (1.00 + 0.029 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
    * **level_3**: `(30 + 7.5 * #src_combat_magic_level) * (1.20 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
  * `cmagic_energy_orb_duration`:
    * **// All values must be the same (20)
				level_1**: `20`
    * **level_2**: `20`
    * **level_3**: `20`


### Flame Nexus (`flame_nexus`)
* **Summary**: Convectus the Red communed with Lava Spirits, learning to summon and launch them as weapons in battle. The Spirit gleefully reaches out with tendrils of fire to burn any nearby enemies.\n\nTargets an Enemy or Terrain\nNormal Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_conscious_enemy | tt_dead_enemy | tt_breakable | tt_terrain | tt_transmutable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: devastation: 2, searing_flames: 1
  * **Rank_2**: devastation: 5, searing_flames: 4
  * **Rank_3**: devastation: 12, searing_flames: 8, ignite: 5
* **Rank Scaling (Skill Values)**:
  * `cmagic_flame_nexus_damage`:
    * **// Damage**: `((Character Damage / Second) * Power Effectiveness * Reload Time * .83 for Skills) / # of hits // = (8 + 2 * #src_combat_magic_level) * PE * 30 * .83 / 5 // = (40 + 10 * #src_combat_magic_level) * PE // Power Effectiveness = 90% = 82% + 1.5% per level (level 5) level_1 = (40 + 10 * #src_combat_magic_level) * (0.82 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_fire_damage * .01))`
    * **// Power Effectiveness**: `350% = 200% + 3.6% per level (level 42) level_3 = (40 + 10 * #src_combat_magic_level) * (2.00 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_fire_damage * .01))`
  * `cmagic_flame_nexus_dummy_radius`:
    * **level_1**: `1`
    * **level_2**: `1`
    * **level_3**: `1`


### Detonation (`conflagration`)
* **Summary**: The greatest power of the fire mage is a dangerous weapon. The mage recklessly gathers more energy than he can control, releasing it in a massive conflagration that burns his enemies.\n\nArea of Effect Targets an Enemy or Terrain\nSlow Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_conscious_enemy | tt_dead_enemy | tt_breakable | tt_terrain`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: searing_flames: 8, ignite: 1
  * **Rank_2**: searing_flames: 12, ignite: 6
  * **Rank_3**: searing_flames: 16, ignite: 10, arcane_fury: 8
* **Rank Scaling (Skill Values)**:
  * `cmagic_conflagration_damage`:
    * **// Damage**: `((Character Damage / Second ) * Power Effectiveness * Reload Time * .83 for Skills) / # of hits // = (8 + 2 * #src_combat_magic_level) * PE * 40 * .83 / 4 // = (67.5 + 16.9 * #src_combat_magic_level) * PE // Power Effectiveness = 240% = 200% + 1.5% per level (level 26) level_1 = (67.5 + 16.9 * #src_combat_magic_level) * (2.0 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_fire_damage * .01))`
    * **// Power Effectiveness**: `480% = 270% + 3.6% per level (level 62) level_3 = (67.5 + 16.9 * #src_combat_magic_level) * (2.7 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_fire_damage * .01))`
  * `cmagic_conflagration_radius`:
    * **level_1**: `3`
    * **// 4 targets
				level_2**: `3.5`
    * **// 4 targets
				level_3**: `4`
  * `cmagic_conflagration_party_damage`:
    * **level_1**: `0`
    * **level_2**: `0`
    * **level_3**: `0`


### Corrosive Eruption (`corrosive_eruption`)
* **Summary**: Enemies caught within this noxious cloud are infected by gasses that rot them from the inside out. Corrosive fumes violently erupt from victims when they die, burning and poisoning nearby foes.\n\nArea of Effect Targets an Enemy or Terrain\nNormal Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: debilitation: 1
  * **Rank_2**: debilitation: 5, grim_necromancy: 4
  * **Rank_3**: debilitation: 12, grim_necromancy: 10, arcane_fury: 4
* **Rank Scaling (Skill Values)**:
  * `cmagic_corrosive_eruption_curse_duration`:
    * **level_1**: `30`
    * **level_2**: `60`
    * **level_3**: `300`
  * `cmagic_corrosive_eruption_curse_radius`:
    * **level_1**: `4`
    * **level_2**: `5`
    * **level_3**: `6`
  * `cmagic_corrosive_eruption_damage_percentage`:
    * **// Damage**: `# of monsters damaged * Monster Health * Percentage // Damage = ((Character Damage / Second) * PE * Reload Time // Percentage = ((Character Damage / Second ) * PE * Reload Time * .8 for Skills / (Monster Health * # of monsters damaged) // = (8 + 2 * #src_combat_magic_level) * PE * 30 * .8 / (18 + 9 * #src_combat_magic_level) * (1.0 + 0.12 * #src_combat_magic_level) * (3 + 2 + 1) // = PE * 30 * .8 / (4 * (1.0 + 0.12 * #src_combat_magic_level) * 6) // = PE / (1.0 + 0.12 * #src_combat_magic_level) // Power Effectiveness = 90% = 82% + 1.5% per level (level 5) level_1 = 45 * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_death_damage * .01))`
    * **// Power Effectiveness**: `350% = 200% + 3.6% per level (level 42) level_3 = 70 * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_death_damage * .01))`
  * `cmagic_corrosive_eruption_eruption_radius`:
    * **level_1**: `2.5`
    * **level_2**: `2.5`
    * **level_3**: `2.5`


### Harvest Soul (`harvest_soul`)
* **Summary**: A deadly attack invented by the vilest mages in history, this dark ritual creates a gigantic scythe that cuts away the life force of the mage's enemies, allowing his allies to absorb it and heal themselves.\n\nArea of Effect Targets an Enemy or Terrain\nNormal Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: devastation: 6, grim_necromancy: 5
  * **Rank_2**: devastation: 8, grim_necromancy: 8, vampirism: 4
  * **Rank_3**: devastation: 10, grim_necromancy: 12, vampirism: 10
* **Rank Scaling (Skill Values)**:
  * `cmagic_harvest_souls_damage`:
    * **// Damage**: `((Character Damage / Second ) * Power Effectiveness * 0.8 because it heals * Reload Time * .83 for skills) / # of hits // = (8 + 2 * #src_combat_magic_level) * PE * 0.8 * 30 * .83 / 4 // = (40 + 10 * #src_combat_magic_level) * PE // Power Effectiveness = 180% = 150% + 1.5% per level (level 18) level_1 = (40 + 10 * #src_combat_magic_level) * (1.5 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_death_damage * .01))`
    * **// Power Effectiveness**: `450% = 250% + 3.6% per level (level 56) level_3 = (40 + 10 * #src_combat_magic_level) * (2.5 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_death_damage * .01))`
  * `cmagic_harvest_souls_radius`:
    * **//keep the radius the same through the levels due to sfx custom effects
				level_1**: `3`
    * **level_2**: `3`
    * **level_3**: `3`
  * `cmagic_harvest_souls_percentage_healed`:
    * **// Amount Healed ~**: `15% of a fighter's health // Amount Healed = Damage * Multiplier * (# monsters) / (# Characters) // = Damage * Multiplier * 4 / 4 // Multiplier = (15% Fighter Health) / Damage // = 15 * (10.6 * level + 50) / (10 * level + 40) * PE level_1 = 6`
    * **level_2**: `6`
    * **level_3**: `6`


### Chain Lightning (`chain_lightning`)
* **Summary**: A favored attack of young Combat Mages, Chain Lightning hurls a bolt of lightning that shocks the nearest enemy then jumps to other nearby foes. The bolt deals reduced damage with each jump.\n\nAutomatically Targets Nearest Enemy\nFast Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `21 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: devastation: 2, amplified_lightning: 1
  * **Rank_2**: devastation: 5, amplified_lightning: 4
  * **Rank_3**: devastation: 12, amplified_lightning: 8, arcing: 5
* **Rank Scaling (Skill Values)**:
  * `cmagic_chain_lightning_damage`:
    * **// Damage**: `((Mage Damage / Second ) * Power Effectiveness * Reload Time * .83 for Skills) / Damage Ratio // = (8 + 2 * #src_combat_magic_level) * PE * 20 * .83 / Damage Ratio // = (132.8 + 33.2 * #src_combat_magic_level) * PE / Damage Ratio // Damage Ratio equals total multiplier of base damage after all chain jumps // Power Effectiveness = 90% = 82% + 1.5% per level (level 5), Damage Ratio = 2.0 level_1 = (66.4 + 16.6 * #src_combat_magic_level) * (0.82 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_lightning_damage * .01))`
    * **// Power Effectiveness**: `350% = 200% + 3.6% per level (level 42), Damage Ratio = 4.5 level_3 = (29.5 + 7.40 * #src_combat_magic_level) * (2.00 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_lightning_damage * .01))`
  * `cmagic_chain_lightning_number_jumps`:
    * **level_1**: `2`
    * **// Hits 3 enemies
				level_2**: `4`
    * **// Hits 5 enemies
				level_3**: `6`
  * `cmagic_chain_lightning_damageratio`:
    * **// Damage on next hit**: `Damage on previous hit * (1.0 - damage_ratio) level_1 = 0.38`
    * **// 38% damage after 3 hits
				level_2**: `0.22`
    * **// 37% damage after 5 hits
				level_3**: `0.15`


### Gathered Bolt (`gathered_bolt`)
* **Summary**: The mage gradually builds up a massive electrical charge on the ground, causing a tremendous bolt of lightning to crash down, devastating all enemies it hits.\n\nArea of Effect Targets an Enemy or Terrain\nLong Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: amplified_lightning: 8, quickened_casting: 1
  * **Rank_2**: amplified_lightning: 10, quickened_casting: 6, arcane_fury: 1
  * **Rank_3**: amplified_lightning: 14, quickened_casting: 12, arcane_fury: 6
* **Rank Scaling (Skill Values)**:
  * `cmagic_gathered_bolt_damage`:
    * **// Damage**: `1.3 * ((Mage Damage / Second ) * Power Effectiveness * Reload Time * .83 for Skills) / # of hits // = 1.3 * (8 + 2 * #src_combat_magic_level) * PE * 40 * .83 / 5 // = (70 + 17.5 * #src_combat_magic_level) * PE // Power Effectiveness = 220% = 185% + 1.5% per level (level 26) level_1 = (70 + 17.5 * #src_combat_magic_level) * (1.85 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_lightning_damage * .01))`
    * **// Power Effectiveness**: `450% = 250% + 3.6% per level (level 56) level_3 = (70 + 17.5 * #src_combat_magic_level) * (2.5 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_lightning_damage * .01))`
  * `cmagic_gathered_bolt_party_damage`:
    * **level_1**: `0`
    * **level_2**: `0`
    * **level_3**: `0`
  * `cmagic_gathered_bolt_radius`:
    * **level_1**: `3.5`
    * **level_2**: `4`
    * **level_3**: `5`


---

## Nature Magic Powers

### Gravity Stone (`gravity_stone`)
* **Summary**: The mage summons a monolithic stone of such density that its gravitational force pulls enemy creatures toward it and holds them in place until it collapses under itself.\n\nArea of Effect Targets an Enemy or Terrain\nFast Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: natural_bond: 1
  * **Rank_2**: natural_bond: 5
  * **Rank_3**: natural_bond: 8, arcane_renewal: 6
* **Rank Scaling (Skill Values)**:
  * `nmagic_gravity_stone_radius`:
    * **level_1**: `4`
    * **level_2**: `5`
    * **level_3**: `6`
  * `nmagic_gravity_stone_pull_distance`:
    * **level_1**: `2`
    * **level_2**: `2`
    * **level_3**: `2`
  * `nmagic_gravity_stone_duration`:
    * **level_1**: `4`
    * **level_2**: `5`
    * **level_3**: `6`


### Icicle Blast (`icicle_blast`)
* **Summary**: A deadly attack inspired by the North Dragon's breath, Icicle Blast launches shards of ice from the caster's fingers in a fan of destruction, knocking enemies back and blasting them with cold.\n\nCone Effect Targets an Enemy or Terrain\nNormal Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_conscious_enemy | tt_terrain | tt_breakable | tt_dead_enemy | tt_transmutable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: aquatic_affinity: 2
  * **Rank_2**: aquatic_affinity: 5, arctic_mastery: 5
  * **Rank_3**: aquatic_affinity: 10, arctic_mastery: 10, freezing: 8
* **Rank Scaling (Skill Values)**:
  * `nmagic_icicle_blast_damage`:
    * **// Damage**: `((Character Damage / Second) * Power Effectiveness * Reload Time * .83 for Skills) / # of enemies hit // = (8 + 2 * #src_nature_magic_level) * PE * 30 * .83 / 3.5 // = (56 + 14 * #src_nature_magic_level) * PE // Power Effectiveness = 90% = 82% + 1.5% * #src_nature_magic_level (level 5) level_1 = (56 + 14 * #src_nature_magic_level) * (0.82 + 0.015 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
    * **// Power Effectiveness**: `350% = 200% + 3.6% * #src_nature_magic_level (level 42) level_3 = (56 + 14 * #src_nature_magic_level) * (2.0 + 0.036 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
  * `nmagic_icicle_blast_dummy_radius`:
    * **level_1**: `1`
    * **level_2**: `1`
    * **level_3**: `1`


### Circle of Frost (`circle_of_frost`)
* **Summary**: Circle of Frost banishes all heat from an area. The ground cracks as moisture turns to ice, the very air freezes, and any creature unlucky enough to be caught in the circle is frozen until it thaws.\n\nArea of Effect Targets an Enemy or Terrain\nLong Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: natural_bond: 5, arctic_mastery: 8, freezing: 1
  * **Rank_2**: natural_bond: 6, arctic_mastery: 10, freezing: 6
  * **Rank_3**: natural_bond: 8, arctic_mastery: 12, freezing: 12
* **Rank Scaling (Skill Values)**:
  * `nmagic_circle_of_frost_freeze_duration`:
    * **level_1**: `12.0`
    * **level_2**: `15.0`
    * **level_3**: `18.0`
  * `nmagic_circle_of_frost_radius`:
    * **level_1**: `3.5`
    * **level_2**: `4.0`
    * **level_3**: `4.5`
  * `nmagic_circle_of_frost_damage`:
    * **// Damage**: `((Character Damage / Second ) * Power Effectiveness * Reload Time * .83 for Skills) / (# of hits * 4 because it stuns) // = (8 + 2 * #src_nature_magic_level) * PE * 40 * .83 / 20 // = (13.3 + 3.3 * #src_nature_magic_level) * PE // Power Effectiveness = 240% = 200% + 1.5% * #src_nature_magic_level (level 26) level_1 = (13.3 + 3.3 * #src_nature_magic_level) * (2.0 + 0.015 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
    * **// Power Effectiveness**: `450% = 250% + 3.6% * #src_nature_magic_level (level 56) level_3 = (13.3 + 3.3 * #src_nature_magic_level) * (2.5 + 0.036 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`


### Summon Provoke (`summon_provoke`)
* **Summary**: With an Agallan rhyme, the mage provokes enemies around himself to focus their wrath upon his summoned creature. Once provoked, monsters won't always respond to additional provocation.\n\nCan only be used when mage has summoned a creature\nAutomatically Provokes Enemies around Caster\nFast Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self | tt_summoned`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `12 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: summon_fortitude: 3, summon_might: 1
  * **Rank_2**: summon_fortitude: 7, summon_might: 4
  * **Rank_3**: summon_fortitude: 12, summon_might: 6, summon_bond: 6
* **Rank Scaling (Skill Values)**:
  * `nmagic_summon_provoke_radius`:
    * **level_1**: `6`
    * **level_2**: `7`
    * **level_3**: `8`


### Aether Blast (`aether_blast`)
* **Summary**: Aether Blast channels a spike of magical energy through the mage's link with his summoned creature, creating a devastating explosion. The more powerful the creature, the more deadly the blast.\n\nCan only be used when mage has summoned a creature\nAutomatically Blasts Enemies around Summoned Creature\nNormal Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `TT_SELF | TT_SUMMONED`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: summon_might: 8, arcane_renewal: 1
  * **Rank_2**: summon_might: 10, arcane_renewal: 6, summon_bond: 2
  * **Rank_3**: summon_might: 14, arcane_renewal: 8, summon_bond: 12
* **Rank Scaling (Skill Values)**:
  * `nmagic_aether_blast_radius`:
    * **level_1**: `3.5`
    * **level_2**: `4`
    * **level_3**: `5`
  * `nmagic_aether_blast_stun_time`:
    * **// All values must be the same
				level_1**: `5`
    * **level_2**: `5`
    * **level_3**: `5`
  * `nmagic_aether_blast_damage_percentage`:
    * **// Summoned Monster Health**: `12.7 * Level + 60 // = 1.2 * (3.53 * Intelligence + 14.67) // ~= 1.2 * 5.3 * (Character Damage / Second) = 6.35 * (Character Damage / Second) // Damage = ((Character Damage / Second) * Power Effectiveness * Reload Time) / # of hits // = (8 + 2 * #src_nature_magic_level) * PE * 30 / 4 // = (Character Damage / Second) * PE * 7.5 // Percentage = 7.5 * PE / 6.35 = 1.2 * PE // Power Effectiveness = 240% = 200% + 1.5% * #src_nature_magic_level (level 26) level_1 = (240 + 1.8 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
    * **// Power Effectiveness**: `525% = 290% + 3.6% * #src_nature_magic_level (level 66) level_3 = (350 + 4.3 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`


### Invulnerability (`invulnerability`)
* **Summary**: The most powerful defensive magic a Nature Mage can possess, Invulnerability protects the party so completely that no physical or magical attack can harm them.\n\nAutomatically Protects All Nearby Allies\nNormal Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: enveloping_embrace: 1
  * **Rank_2**: enveloping_embrace: 6, nurturing_gift: 4
  * **Rank_3**: enveloping_embrace: 12, nurturing_gift: 8, arcane_renewal: 6
* **Rank Scaling (Skill Values)**:
  * `nmagic_invulnerability_duration`:
    * **level_1**: `6`
    * **level_2**: `8`
    * **level_3**: `12`


### Glacial Aura (`glacial_aura`)
* **Summary**: Nature Mages of frozen mountains can focus glacial power around themselves, creating an aura that emits waves of frost that damage and briefly freeze any enemies who draw near.\n\nAutomatically Enhances Self\nSlow Recharge
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: feral_wrath: 8, freezing: 4
  * **Rank_2**: feral_wrath: 12, freezing: 12, absorption: 6
  * **Rank_3**: feral_wrath: 14, freezing: 15, absorption: 12
* **Rank Scaling (Skill Values)**:
  * `nmagic_glacial_aura_duration`:
    * **level_1**: `10`
    * **level_2**: `12`
    * **level_3**: `15`
  * `nmagic_glacial_aura_freeze_duration`:
    * **level_1**: `4`
    * **level_2**: `5`
    * **level_3**: `6`
  * `nmagic_glacial_aura_wave_damage`:
    * **// Damage equals total damage of Power divided in to waves
				// Damage**: `((Character Damage / Second) * Power Effectiveness * Reload Time * Frequency * .83 for Skills) / (# of hits per wave * Duration) // = (8 + 2 * #src_nature_magic_level) * PE * 40 * 0.5 because it stuns * 0.8 seconds per wave * .83 / (4 * Duration in seconds) // = (26 + 6.5 * #src_nature_magic_level) * PE / Duration // Power Effectiveness = 240% = 200% + 1.5% * #src_nature_magic_level (level 26) level_1 = (2.6 + 0.65 * #src_nature_magic_level) * (2.0 + 0.015 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
    * **// Power Effectiveness**: `525% = 290% + 3.6% * #src_nature_magic_level (level 66) level_3 = (1.7 + 0.44 * #src_nature_magic_level) * (2.9 + 0.036 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
  * `nmagic_glacial_aura_wave_frequency`:
    * **// Must be 0.8
				level_1**: `0.8`
    * **level_2**: `0.8`
    * **level_3**: `0.8`


---
