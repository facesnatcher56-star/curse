# Dungeon Siege II: Powers (Active Skills) Complete Reference

Extracted directly from installed game data (`active_skills.gas`, `Logic.ds2res`).

Complete numerical baseline for Phase 6 combat powers, weapon stances, recharge formulas, area radii, duration, and exact scaling across all ranks.

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
* **Max Ranks**: 3
* **Stances Required**: `AS_SINGLE_MELEE, AS_SINGLE_MELEE_AND_SHIELD, AS_TWO_HANDED_MELEE, AS_TWO_HANDED_SWORD, AS_DUAL_WIELD, AS_STAFF`
* **Target Type**: `tt_conscious_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `21 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: critical_strike: 1
  * **Rank_2**: critical_strike: 5
  * **Rank_3**: critical_strike: 8
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `melee_brutal_attack_damage_bonus_percentage`:
    * **Rank 1 (level_1)**: `1500 + 25 * #src_melee`
    * **Rank 2 (level_2)**: `1750 + 48 * #src_melee`
    * **Rank 3 (level_3)**: `2000 + 60 * #src_melee`


### Provoke (`provoke`)
* **Summary**: Knights protect their allies by using their shields to provoke nearby enemies, causing them to become angry and attack the knight. The knight's concentration also temporarily increases his armor.\n\nCan only be used when equipped with a shield\nAutomatically Provokes Enemies around Self\nFast Recharge
* **Max Ranks**: 3
* **Stances Required**: `AS_SINGLE_MELEE_AND_SHIELD,AS_SHIELD_ONLY`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `12 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: aegis: 1
  * **Rank_2**: aegis: 6, toughness: 4
  * **Rank_3**: aegis: 10, toughness: 10, rebuke: 5
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `melee_provoke_radius`:
    * **Rank 1 (level_1)**: `6`
    * **Rank 2 (level_2)**: `7`
    * **Rank 3 (level_3)**: `8`
  * `melee_provoke_armor_percentage`:
    * **Rank 1 (level_1)**: `25`
    * **Rank 2 (level_2)**: `30`
    * **Rank 3 (level_3)**: `50`
  * `melee_provoke_armor_duration`:
    * **Rank 1 (level_1)**: `5`
    * **Rank 2 (level_2)**: `8`
    * **Rank 3 (level_3)**: `10`


### Whirling Strike (`whirling_strike`)
* **Summary**: A legendary fighter known only as the Tempest of Tel'kilae originated this technique, in which the fighter whirls his weapons in a circle, damaging and briefly stunning all nearby enemies.\n\nCan only be used with a melee weapon\nAutomatically Strikes Enemies around Self\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `AS_SINGLE_MELEE, AS_SINGLE_MELEE_AND_SHIELD, AS_TWO_HANDED_MELEE, AS_TWO_HANDED_SWORD, AS_DUAL_WIELD, AS_STAFF`
* **Target Type**: `tt_self | tt_conscious_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: critical_strike: 6, fortitude: 8
  * **Rank_2**: critical_strike: 8, fortitude: 10, reinforced_armor: 6
  * **Rank_3**: critical_strike: 12, fortitude: 12, reinforced_armor: 12
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `melee_whirling_strike_radius`:
    * **Rank 1 (level_1)**: `3`
    * **Rank 2 (level_2)**: `3.5`
    * **Rank 3 (level_3)**: `4`
  * `melee_whirling_strike_damage_percentage`:
    * **Rank 1 (level_1)**: `920 + 9 * #src_melee`
    * **Rank 2 (level_2)**: `1070 + 15.4 * #src_melee`
    * **Rank 3 (level_3)**: `1400 + 19 * #src_melee`
  * `melee_whirling_strike_stun_duration`:
    * **Rank 1 (level_1)**: `1.5`
    * **Rank 2 (level_2)**: `1.5`
    * **Rank 3 (level_3)**: `1.5`


### Staggering Blow (`staggering_blow`)
* **Summary**: When a two-handed weapon master activates this ability, his next attack will be a Staggering Blow. He slams his weapon into his target, creating a shockwave that stuns any enemies caught within it.\n\nCan only be used with a two-handed melee weapon\nAutomatically Enhances Next Attack\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `AS_TWO_HANDED_MELEE, AS_TWO_HANDED_SWORD, AS_STAFF`
* **Target Type**: `tt_conscious_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: overbear: 1
  * **Rank_2**: overbear: 5, toughness: 4
  * **Rank_3**: overbear: 12, toughness: 10, smite: 8
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `melee_staggering_blow_damage_percentage`:
    * **Rank 1 (level_1)**: `400 + 7 * #src_melee`
    * **Rank 2 (level_2)**: `425 + 10 * #src_melee`
    * **Rank 3 (level_3)**: `800 + 12 * #src_melee`
  * `melee_staggering_blow_duration`:
    * **Rank 1 (level_1)**: `6.0`
    * **Rank 2 (level_2)**: `8.0`
    * **Rank 3 (level_3)**: `10.0`
  * `melee_staggering_blow_radius`:
    * **Rank 1 (level_1)**: `2.75`
    * **Rank 2 (level_2)**: `3.25`
    * **Rank 3 (level_3)**: `4`


### War Cry (`warcry`)
* **Summary**: Barbarians of the Plain of Tears can unleash a deafening war cry, energizing themselves and terrifying their enemies, causing them to run in fear and leave their defenses open for a short time.\n\nCan only be used with a melee weapon\nCone Effect Targets an Enemy or Terrain\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `AS_SINGLE_MELEE, AS_SINGLE_MELEE_AND_SHIELD, AS_TWO_HANDED_MELEE, AS_TWO_HANDED_SWORD, AS_DUAL_WIELD, AS_STAFF`
* **Target Type**: `tt_conscious_enemy | tt_terrain`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: critical_strike: 8, smite: 1
  * **Rank_2**: critical_strike: 12, smite: 8, desperate_frenzy: 2
  * **Rank_3**: critical_strike: 12, smite: 12, desperate_frenzy: 8
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `melee_warcry_armor_reduction_duration`:
    * **Rank 1 (level_1)**: `20.0`
    * **Rank 2 (level_2)**: `20.0`
    * **Rank 3 (level_3)**: `20.0`
  * `melee_warcry_armor_reduction_percentage`:
    * **Rank 1 (level_1)**: `35.0`
    * **Rank 2 (level_2)**: `50.0`
    * **Rank 3 (level_3)**: `60.0`
  * `melee_warcry_number_critical_hit`:
    * **Rank 1 (level_1)**: `8`
    * **Rank 2 (level_2)**: `12`
    * **Rank 3 (level_3)**: `15`
  * `melee_warcry_dummy_radius`:
    * **Rank 1 (level_1)**: `1`
    * **Rank 2 (level_2)**: `1`
    * **Rank 3 (level_3)**: `1`


### Waves of Force (`waves_of_force`)
* **Summary**: A student of Elven dual-weapon techniques learns to perform a beautiful sequence of rapid swings, each creating a wave of force that rushes out in front of her, tearing apart enemies caught in its wake.\n\nCan only be used when dual-wielding two weapons\nTargets an Enemy or Terrain\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy | tt_breakable | tt_transmutable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: dual_wield: 1
  * **Rank_2**: dual_wield: 5, alacrity: 4
  * **Rank_3**: dual_wield: 10, alacrity: 10, desperate_frenzy: 8
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `melee_waves_damage_percentage`:
    * **Rank 1 (level_1)**: `200 + 3.6 * #src_melee`
    * **Rank 2 (level_2)**: `280 + 7 * #src_melee`
    * **Rank 3 (level_3)**: `490 + 9 * #src_melee`
  * `melee_waves_count`:
    * **Rank 1 (level_1)**: `5`
    * **Rank 2 (level_2)**: `5`
    * **Rank 3 (level_3)**: `5`
  * `melee_waves_frequency`:
    * **Rank 1 (level_1)**: `0.24`
    * **Rank 2 (level_2)**: `0.24`
    * **Rank 3 (level_3)**: `0.24`
  * `melee_waves_distance`:
    * **Rank 1 (level_1)**: `12`
    * **Rank 2 (level_2)**: `12`
    * **Rank 3 (level_3)**: `12`
  * `melee_waves_speed`:
    * **Rank 1 (level_1)**: `10`
    * **Rank 2 (level_2)**: `10`
    * **Rank 3 (level_3)**: `10`
  * `melee_waves_dummy_radius`:
    * **Rank 1 (level_1)**: `1`
    * **Rank 2 (level_2)**: `1`
    * **Rank 3 (level_3)**: `1`


### Elemental Rage (`elemental_rage`)
* **Summary**: The highest art of the Elven Blademaster is a meditative frenzy that causes elemental energy to manifest in his weapons and speeds his attacks. Ignoring his own defense, he leaps into battle.\n\nCan only be used when dual-wielding two weapons\nAutomatically Enhances Self\nSlow Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: critical_strike: 8, fierce_renewal: 2
  * **Rank_2**: critical_strike: 10, fierce_renewal: 6, desperate_frenzy: 1
  * **Rank_3**: critical_strike: 14, fierce_renewal: 12, desperate_frenzy: 12
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `melee_erage_duration`:
    * **Rank 1 (level_1)**: `15`
    * **Rank 2 (level_2)**: `15`
    * **Rank 3 (level_3)**: `15`
  * `melee_erage_edamage_min`:
    * **Rank 1 (level_1)**: `(3.7 + 0.90 * #src_melee) * (2.0 + 0.015 * #src_melee)`
    * **Rank 2 (level_2)**: `(3.6 + 0.87 * #src_melee) * (2.0 + 0.029 * #src_melee)`
    * **Rank 3 (level_3)**: `(3.4 + 0.83 * #src_melee) * (2.5 + 0.036 * #src_melee)`
  * `melee_erage_edamage_max`:
    * **Rank 1 (level_1)**: `(6.2 + 1.54 * #src_melee) * (2.0 + 0.015 * #src_melee)`
    * **Rank 2 (level_2)**: `(5.9 + 1.48 * #src_melee) * (2.0 + 0.029 * #src_melee)`
    * **Rank 3 (level_3)**: `(5.7 + 1.42 * #src_melee) * (2.5 + 0.036 * #src_melee)`
  * `melee_erage_number_elements`:
    * **Rank 1 (level_1)**: `3`
    * **Rank 2 (level_2)**: `3`
    * **Rank 3 (level_3)**: `3`
  * `melee_erage_attack_rate_bonus_percentage`:
    * **Rank 1 (level_1)**: `10.0`
    * **Rank 2 (level_2)**: `15.0`
    * **Rank 3 (level_3)**: `20.0`
  * `melee_erage_vulnerability_percentage`:
    * **Rank 1 (level_1)**: `12`
    * **Rank 2 (level_2)**: `15`
    * **Rank 3 (level_3)**: `20`


---

## Ranged (Archer) Powers

### Take Aim (`take_aim`)
* **Summary**: Dryad archers conceal themselves to surprise their enemies, but their first shot reveals their position. They learn to focus their concentration and take careful aim, making their next shot as devastating as possible.\n\nCan only be used with a bow, crossbow, or thrown weapon\nAutomatically Enhances Next Attack\nFast Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_conscious_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `21 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: critical_shot: 1
  * **Rank_2**: critical_shot: 5
  * **Rank_3**: critical_shot: 8, penetrate: 1
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `ranged_take_aim_damage_bonus_percentage`:
    * **Rank 1 (level_1)**: `1500 + 25 * #src_melee`
    * **Rank 2 (level_2)**: `1700 + 48 * #src_melee`
    * **Rank 3 (level_3)**: `2500 + 60 * #src_ranged`


### Thunderous Shot (`thunderous_shot`)
* **Summary**: A thunderous arrow or crossbow bolt travels faster than the eye can see, punching through all enemies in its path and leaving them stunned. Azunai's archers turned many battles with this attack.\n\nCan only be used with a bow or crossbow\nTargets an Enemy or Terrain\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `AS_BOW_AND_ARROW, AS_MINIGUN`
* **Target Type**: `tt_conscious_enemy | tt_breakable | tt_terrain`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: biting_arrow: 1
  * **Rank_2**: biting_arrow: 8, far_shot: 1
  * **Rank_3**: biting_arrow: 12, far_shot: 8, mortal_wound: 5
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `ranged_thunderous_shot_damage_bonus_percentage`:
    * **Rank 1 (level_1)**: `530 + 9 * #src_ranged`
    * **Rank 2 (level_2)**: `1025 + 16 * #src_ranged`
    * **Rank 3 (level_3)**: `1225 + 21 * #src_ranged`
  * `ranged_thunderous_shot_stun_duration`:
    * **Rank 1 (level_1)**: `6.0`
    * **Rank 2 (level_2)**: `8.0`
    * **Rank 3 (level_3)**: `10.0`
  * `ranged_thunderous_shot_dummy_radius`:
    * **Rank 1 (level_1)**: `1`
    * **Rank 2 (level_2)**: `1`
    * **Rank 3 (level_3)**: `1`


### Silence (`silence`)
* **Summary**: Azunai's armies relied on Dalziel, one of the Champions of the Northern Reaches, to destroy Zaramoth's mages. Dalziel's hatred of their magic manifested as an ability to silence them temporarily, preventing them from casting spells.\n\nArea of Effect Targets an Enemy or Terrain\nFast Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `21 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: dodge: 5, survival: 3
  * **Rank_2**: dodge: 10, survival: 6, mortal_wound: 1
  * **Rank_3**: dodge: 14, survival: 10, mortal_wound: 12
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `ranged_silence_radius`:
    * **Rank 1 (level_1)**: `4`
    * **Rank 2 (level_2)**: `5`
    * **Rank 3 (level_3)**: `6`
  * `ranged_silence_duration`:
    * **Rank 1 (level_1)**: `15`
    * **Rank 2 (level_2)**: `20`
    * **Rank 3 (level_3)**: `25`


### Shrapnel Blast (`bursting_missile`)
* **Summary**: When this thrown weapon strikes a target, a blast shatters it into many pieces that fly in all directions. Stories of a single ranger defeating a crowd of foes are often tales of this power in action.\n\nCan only be used with a thrown weapon\nTargets an Enemy or Terrain\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `AS_THROWABLE`
* **Target Type**: `tt_conscious_enemy | tt_dead_enemy | tt_breakable | tt_terrain | tt_transmutable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: quick_draw: 1
  * **Rank_2**: quick_draw: 5, bleed: 5
  * **Rank_3**: quick_draw: 10, bleed: 8, penetrate: 6
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `ranged_bursting_missile_radius`:
    * **Rank 1 (level_1)**: `1.0`
    * **Rank 2 (level_2)**: `1.0`
    * **Rank 3 (level_3)**: `1.0`
  * `ranged_bursting_missile_radial_damage`:
    * **Rank 1 (level_1)**: `80 + 1.5 * #src_ranged`
    * **Rank 2 (level_2)**: `130 + 3.0 * #src_ranged`
    * **Rank 3 (level_3)**: `200 + 3.6 * #src_ranged`
  * `ranged_bursting_missile_damage`:
    * **Rank 1 (level_1)**: `950 + 17 * #src_ranged`
    * **Rank 2 (level_2)**: `1450 + 24 * #src_ranged`
    * **Rank 3 (level_3)**: `1700 + 30 * #src_ranged`
  * `ranged_bursting_missile_number`:
    * **Rank 1 (level_1)**: `5`
    * **Rank 2 (level_2)**: `7`
    * **Rank 3 (level_3)**: `9`
  * `ranged_bursting_missile_dummy_radius`:
    * **Rank 1 (level_1)**: `1`
    * **Rank 2 (level_2)**: `1`
    * **Rank 3 (level_3)**: `1`


### Repulse (`repulse`)
* **Summary**: The Crimson Hunter Laethel liked to get close to his enemies, but developed this ability to survive when they got too close. Repulse knocks enemies away from the ranger and stuns them.\n\nAutomatically Repulses Enemies around Self\nLong Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: dodge: 4, survival: 3
  * **Rank_2**: dodge: 10, survival: 6, ricochet: 1
  * **Rank_3**: dodge: 14, survival: 10, ricochet: 12
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `ranged_repulse_radius`:
    * **Rank 1 (level_1)**: `3.0`
    * **Rank 2 (level_2)**: `3.5`
    * **Rank 3 (level_3)**: `4.0`
  * `ranged_repulse_knockback_distance`:
    * **Rank 1 (level_1)**: `3`
    * **Rank 2 (level_2)**: `5`
    * **Rank 3 (level_3)**: `7`
  * `ranged_repulse_stun_duration`:
    * **Rank 1 (level_1)**: `1.5`
    * **Rank 2 (level_2)**: `1.5`
    * **Rank 3 (level_3)**: `1.5`
  * `ranged_repulse_duration`:
    * **Rank 1 (level_1)**: `12.0`
    * **Rank 2 (level_2)**: `16.0`
    * **Rank 3 (level_3)**: `20.0`


### Flurry (`flurry`)
* **Summary**: Elven adventurers learn to focus their strength into a burst of energy, temporarily allowing them to throw multiple weapons at a rapid rate; but the increase in speed comes at the cost of accuracy.\n\nCan only be used with a thrown weapon\nAutomatically Enhances Self\nLong Recharge
* **Max Ranks**: 3
* **Stances Required**: `AS_THROWABLE`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: critical_shot: 8, cunning_renewal: 4
  * **Rank_2**: critical_shot: 10, cunning_renewal: 8, ricochet: 8
  * **Rank_3**: critical_shot: 14, cunning_renewal: 12, ricochet: 12
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `ranged_flurry_attack_rate_multiplier`:
    * **Rank 1 (level_1)**: `1.2`
    * **Rank 2 (level_2)**: `1.4`
    * **Rank 3 (level_3)**: `1.5`
  * `ranged_flurry_damage_percentage`:
    * **Rank 1 (level_1)**: `180 + 1.4 * #src_ranged`
    * **Rank 2 (level_2)**: `205 + 2.2 * #src_ranged`
    * **Rank 3 (level_3)**: `210 + 2.6 * #src_ranged`
  * `ranged_flurry_num_projectiles`:
    * **Rank 1 (level_1)**: `2`
    * **Rank 2 (level_2)**: `2`
    * **Rank 3 (level_3)**: `2`
  * `ranged_flurry_duration`:
    * **Rank 1 (level_1)**: `15`
    * **Rank 2 (level_2)**: `15`
    * **Rank 3 (level_3)**: `15`


---

## Combat Magic Powers

### Energy Orb (`energy_orb`)
* **Summary**: The Elven mage Arinth could summon a ball of energy that hovered above him and shot fire at his enemies. He later perfected it, learning to weave additional types of energy into the orb.\n\nAutomatically Summons Orb Above Self\nFast Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `21 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: brilliance: 1
  * **Rank_2**: brilliance: 4, devastation: 2
  * **Rank_3**: brilliance: 8, devastation: 4
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `cmagic_energy_orb_damage_min`:
    * **Rank 1 (level_1)**: `(20 + 5 * #src_combat_magic_level) * (0.82 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
    * **Rank 2 (level_2)**: `(20 + 5 * #src_combat_magic_level) * (1.00 + 0.029 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
    * **Rank 3 (level_3)**: `(20 + 5 * #src_combat_magic_level) * (1.20 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
  * `cmagic_energy_orb_damage_max`:
    * **Rank 1 (level_1)**: `(30 + 7.5 * #src_combat_magic_level) * (0.82 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
    * **Rank 2 (level_2)**: `(30 + 7.5 * #src_combat_magic_level) * (1.00 + 0.029 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
    * **Rank 3 (level_3)**: `(30 + 7.5 * #src_combat_magic_level) * (1.20 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
  * `cmagic_energy_orb_duration`:
    * **Rank 1 (level_1)**: `20`
    * **Rank 2 (level_2)**: `20`
    * **Rank 3 (level_3)**: `20`


### Flame Nexus (`flame_nexus`)
* **Summary**: Convectus the Red communed with Lava Spirits, learning to summon and launch them as weapons in battle. The Spirit gleefully reaches out with tendrils of fire to burn any nearby enemies.\n\nTargets an Enemy or Terrain\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_conscious_enemy | tt_dead_enemy | tt_breakable | tt_terrain | tt_transmutable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: devastation: 2, searing_flames: 1
  * **Rank_2**: devastation: 5, searing_flames: 4
  * **Rank_3**: devastation: 12, searing_flames: 8, ignite: 5
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `cmagic_flame_nexus_damage`:
    * **Rank 1 (level_1)**: `(40 + 10 * #src_combat_magic_level) * (0.82 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_fire_damage * .01))`
    * **Rank 2 (level_2)**: `(40 + 10 * #src_combat_magic_level) * (1.15 + 0.029 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_fire_damage * .01))`
    * **Rank 3 (level_3)**: `(40 + 10 * #src_combat_magic_level) * (2.00 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_fire_damage * .01))`
  * `cmagic_flame_nexus_dummy_radius`:
    * **Rank 1 (level_1)**: `1`
    * **Rank 2 (level_2)**: `1`
    * **Rank 3 (level_3)**: `1`


### Detonation (`conflagration`)
* **Summary**: The greatest power of the fire mage is a dangerous weapon. The mage recklessly gathers more energy than he can control, releasing it in a massive conflagration that burns his enemies.\n\nArea of Effect Targets an Enemy or Terrain\nSlow Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_conscious_enemy | tt_dead_enemy | tt_breakable | tt_terrain`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: searing_flames: 8, ignite: 1
  * **Rank_2**: searing_flames: 12, ignite: 6
  * **Rank_3**: searing_flames: 16, ignite: 10, arcane_fury: 8
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `cmagic_conflagration_damage`:
    * **Rank 1 (level_1)**: `(67.5 + 16.9 * #src_combat_magic_level) * (2.0 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_fire_damage * .01))`
    * **Rank 2 (level_2)**: `(67.5 + 16.9 * #src_combat_magic_level) * (2.0 + 0.029 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_fire_damage * .01))`
    * **Rank 3 (level_3)**: `(67.5 + 16.9 * #src_combat_magic_level) * (2.7 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_fire_damage * .01))`
  * `cmagic_conflagration_radius`:
    * **Rank 1 (level_1)**: `3`
    * **Rank 2 (level_2)**: `3.5`
    * **Rank 3 (level_3)**: `4`
  * `cmagic_conflagration_party_damage`:
    * **Rank 1 (level_1)**: `0`
    * **Rank 2 (level_2)**: `0`
    * **Rank 3 (level_3)**: `0`


### Corrosive Eruption (`corrosive_eruption`)
* **Summary**: Enemies caught within this noxious cloud are infected by gasses that rot them from the inside out. Corrosive fumes violently erupt from victims when they die, burning and poisoning nearby foes.\n\nArea of Effect Targets an Enemy or Terrain\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: debilitation: 1
  * **Rank_2**: debilitation: 5, grim_necromancy: 4
  * **Rank_3**: debilitation: 12, grim_necromancy: 10, arcane_fury: 4
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `cmagic_corrosive_eruption_curse_duration`:
    * **Rank 1 (level_1)**: `30`
    * **Rank 2 (level_2)**: `60`
    * **Rank 3 (level_3)**: `300`
  * `cmagic_corrosive_eruption_curse_radius`:
    * **Rank 1 (level_1)**: `4`
    * **Rank 2 (level_2)**: `5`
    * **Rank 3 (level_3)**: `6`
  * `cmagic_corrosive_eruption_damage_percentage`:
    * **Rank 1 (level_1)**: `45 * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_death_damage * .01))`
    * **Rank 2 (level_2)**: `60 * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_death_damage * .01))`
    * **Rank 3 (level_3)**: `70 * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_death_damage * .01))`
  * `cmagic_corrosive_eruption_eruption_radius`:
    * **Rank 1 (level_1)**: `2.5`
    * **Rank 2 (level_2)**: `2.5`
    * **Rank 3 (level_3)**: `2.5`


### Harvest Soul (`harvest_soul`)
* **Summary**: A deadly attack invented by the vilest mages in history, this dark ritual creates a gigantic scythe that cuts away the life force of the mage's enemies, allowing his allies to absorb it and heal themselves.\n\nArea of Effect Targets an Enemy or Terrain\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: devastation: 6, grim_necromancy: 5
  * **Rank_2**: devastation: 8, grim_necromancy: 8, vampirism: 4
  * **Rank_3**: devastation: 10, grim_necromancy: 12, vampirism: 10
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `cmagic_harvest_souls_damage`:
    * **Rank 1 (level_1)**: `(40 + 10 * #src_combat_magic_level) * (1.5 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_death_damage * .01))`
    * **Rank 2 (level_2)**: `(40 + 10 * #src_combat_magic_level) * (2.0 + 0.029 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_death_damage * .01))`
    * **Rank 3 (level_3)**: `(40 + 10 * #src_combat_magic_level) * (2.5 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_death_damage * .01))`
  * `cmagic_harvest_souls_radius`:
    * **Rank 1 (level_1)**: `3`
    * **Rank 2 (level_2)**: `3`
    * **Rank 3 (level_3)**: `3`
  * `cmagic_harvest_souls_percentage_healed`:
    * **Rank 1 (level_1)**: `6`
    * **Rank 2 (level_2)**: `6`
    * **Rank 3 (level_3)**: `6`


### Chain Lightning (`chain_lightning`)
* **Summary**: A favored attack of young Combat Mages, Chain Lightning hurls a bolt of lightning that shocks the nearest enemy then jumps to other nearby foes. The bolt deals reduced damage with each jump.\n\nAutomatically Targets Nearest Enemy\nFast Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `21 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: devastation: 2, amplified_lightning: 1
  * **Rank_2**: devastation: 5, amplified_lightning: 4
  * **Rank_3**: devastation: 12, amplified_lightning: 8, arcing: 5
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `cmagic_chain_lightning_damage`:
    * **Rank 1 (level_1)**: `(66.4 + 16.6 * #src_combat_magic_level) * (0.82 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_lightning_damage * .01))`
    * **Rank 2 (level_2)**: `(40.9 + 10.2 * #src_combat_magic_level) * (1.20 + 0.029 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_lightning_damage * .01))`
    * **Rank 3 (level_3)**: `(29.5 + 7.40 * #src_combat_magic_level) * (2.00 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_lightning_damage * .01))`
  * `cmagic_chain_lightning_number_jumps`:
    * **Rank 1 (level_1)**: `2`
    * **Rank 2 (level_2)**: `4`
    * **Rank 3 (level_3)**: `6`
  * `cmagic_chain_lightning_damageratio`:
    * **Rank 1 (level_1)**: `0.38`
    * **Rank 2 (level_2)**: `0.22`
    * **Rank 3 (level_3)**: `0.15`


### Gathered Bolt (`gathered_bolt`)
* **Summary**: The mage gradually builds up a massive electrical charge on the ground, causing a tremendous bolt of lightning to crash down, devastating all enemies it hits.\n\nArea of Effect Targets an Enemy or Terrain\nLong Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: amplified_lightning: 8, quickened_casting: 1
  * **Rank_2**: amplified_lightning: 10, quickened_casting: 6, arcane_fury: 1
  * **Rank_3**: amplified_lightning: 14, quickened_casting: 12, arcane_fury: 6
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `cmagic_gathered_bolt_damage`:
    * **Rank 1 (level_1)**: `(70 + 17.5 * #src_combat_magic_level) * (1.85 + 0.015 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_lightning_damage * .01))`
    * **Rank 2 (level_2)**: `(70 + 17.5 * #src_combat_magic_level) * (2.00 + 0.029 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_lightning_damage * .01))`
    * **Rank 3 (level_3)**: `(70 + 17.5 * #src_combat_magic_level) * (2.5 + 0.036 * #src_combat_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_lightning_damage * .01))`
  * `cmagic_gathered_bolt_party_damage`:
    * **Rank 1 (level_1)**: `0`
    * **Rank 2 (level_2)**: `0`
    * **Rank 3 (level_3)**: `0`
  * `cmagic_gathered_bolt_radius`:
    * **Rank 1 (level_1)**: `3.5`
    * **Rank 2 (level_2)**: `4`
    * **Rank 3 (level_3)**: `5`


---

## Nature Magic Powers

### Gravity Stone (`gravity_stone`)
* **Summary**: The mage summons a monolithic stone of such density that its gravitational force pulls enemy creatures toward it and holds them in place until it collapses under itself.\n\nArea of Effect Targets an Enemy or Terrain\nFast Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: natural_bond: 1
  * **Rank_2**: natural_bond: 5
  * **Rank_3**: natural_bond: 8, arcane_renewal: 6
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `nmagic_gravity_stone_radius`:
    * **Rank 1 (level_1)**: `4`
    * **Rank 2 (level_2)**: `5`
    * **Rank 3 (level_3)**: `6`
  * `nmagic_gravity_stone_pull_distance`:
    * **Rank 1 (level_1)**: `2`
    * **Rank 2 (level_2)**: `2`
    * **Rank 3 (level_3)**: `2`
  * `nmagic_gravity_stone_duration`:
    * **Rank 1 (level_1)**: `4`
    * **Rank 2 (level_2)**: `5`
    * **Rank 3 (level_3)**: `6`


### Icicle Blast (`icicle_blast`)
* **Summary**: A deadly attack inspired by the North Dragon's breath, Icicle Blast launches shards of ice from the caster's fingers in a fan of destruction, knocking enemies back and blasting them with cold.\n\nCone Effect Targets an Enemy or Terrain\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_conscious_enemy | tt_terrain | tt_breakable | tt_dead_enemy | tt_transmutable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: aquatic_affinity: 2
  * **Rank_2**: aquatic_affinity: 5, arctic_mastery: 5
  * **Rank_3**: aquatic_affinity: 10, arctic_mastery: 10, freezing: 8
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `nmagic_icicle_blast_damage`:
    * **Rank 1 (level_1)**: `(56 + 14 * #src_nature_magic_level) * (0.82 + 0.015 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
    * **Rank 2 (level_2)**: `(56 + 14 * #src_nature_magic_level) * (1.3 + 0.029 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
    * **Rank 3 (level_3)**: `(56 + 14 * #src_nature_magic_level) * (2.0 + 0.036 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
  * `nmagic_icicle_blast_dummy_radius`:
    * **Rank 1 (level_1)**: `1`
    * **Rank 2 (level_2)**: `1`
    * **Rank 3 (level_3)**: `1`


### Circle of Frost (`circle_of_frost`)
* **Summary**: Circle of Frost banishes all heat from an area. The ground cracks as moisture turns to ice, the very air freezes, and any creature unlucky enough to be caught in the circle is frozen until it thaws.\n\nArea of Effect Targets an Enemy or Terrain\nLong Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy | tt_breakable`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: natural_bond: 5, arctic_mastery: 8, freezing: 1
  * **Rank_2**: natural_bond: 6, arctic_mastery: 10, freezing: 6
  * **Rank_3**: natural_bond: 8, arctic_mastery: 12, freezing: 12
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `nmagic_circle_of_frost_freeze_duration`:
    * **Rank 1 (level_1)**: `12.0`
    * **Rank 2 (level_2)**: `15.0`
    * **Rank 3 (level_3)**: `18.0`
  * `nmagic_circle_of_frost_radius`:
    * **Rank 1 (level_1)**: `3.5`
    * **Rank 2 (level_2)**: `4.0`
    * **Rank 3 (level_3)**: `4.5`
  * `nmagic_circle_of_frost_damage`:
    * **Rank 1 (level_1)**: `(13.3 + 3.3 * #src_nature_magic_level) * (2.0 + 0.015 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
    * **Rank 2 (level_2)**: `(13.3 + 3.3 * #src_nature_magic_level) * (2.0 + 0.029 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
    * **Rank 3 (level_3)**: `(13.3 + 3.3 * #src_nature_magic_level) * (2.5 + 0.036 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`


### Summon Provoke (`summon_provoke`)
* **Summary**: With an Agallan rhyme, the mage provokes enemies around himself to focus their wrath upon his summoned creature. Once provoked, monsters won't always respond to additional provocation.\n\nCan only be used when mage has summoned a creature\nAutomatically Provokes Enemies around Caster\nFast Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self | tt_summoned`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `12 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: summon_fortitude: 3, summon_might: 1
  * **Rank_2**: summon_fortitude: 7, summon_might: 4
  * **Rank_3**: summon_fortitude: 12, summon_might: 6, summon_bond: 6
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `nmagic_summon_provoke_radius`:
    * **Rank 1 (level_1)**: `6`
    * **Rank 2 (level_2)**: `7`
    * **Rank 3 (level_3)**: `8`


### Aether Blast (`aether_blast`)
* **Summary**: Aether Blast channels a spike of magical energy through the mage's link with his summoned creature, creating a devastating explosion. The more powerful the creature, the more deadly the blast.\n\nCan only be used when mage has summoned a creature\nAutomatically Blasts Enemies around Summoned Creature\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `TT_SELF | TT_SUMMONED`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: summon_might: 8, arcane_renewal: 1
  * **Rank_2**: summon_might: 10, arcane_renewal: 6, summon_bond: 2
  * **Rank_3**: summon_might: 14, arcane_renewal: 8, summon_bond: 12
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `nmagic_aether_blast_radius`:
    * **Rank 1 (level_1)**: `3.5`
    * **Rank 2 (level_2)**: `4`
    * **Rank 3 (level_3)**: `5`
  * `nmagic_aether_blast_stun_time`:
    * **Rank 1 (level_1)**: `5`
    * **Rank 2 (level_2)**: `5`
    * **Rank 3 (level_3)**: `5`
  * `nmagic_aether_blast_damage_percentage`:
    * **Rank 1 (level_1)**: `(240 + 1.8 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
    * **Rank 2 (level_2)**: `(240 + 3.5 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`
    * **Rank 3 (level_3)**: `(350 + 4.3 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01))`


### Invulnerability (`invulnerability`)
* **Summary**: The most powerful defensive magic a Nature Mage can possess, Invulnerability protects the party so completely that no physical or magical attack can harm them.\n\nAutomatically Protects All Nearby Allies\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: enveloping_embrace: 1
  * **Rank_2**: enveloping_embrace: 6, nurturing_gift: 4
  * **Rank_3**: enveloping_embrace: 12, nurturing_gift: 8, arcane_renewal: 6
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `nmagic_invulnerability_duration`:
    * **Rank 1 (level_1)**: `6`
    * **Rank 2 (level_2)**: `8`
    * **Rank 3 (level_3)**: `12`


### Glacial Aura (`glacial_aura`)
* **Summary**: Nature Mages of frozen mountains can focus glacial power around themselves, creating an aura that emits waves of frost that damage and briefly freeze any enemies who draw near.\n\nAutomatically Enhances Self\nSlow Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
  * **Rank_1**: feral_wrath: 8, freezing: 4
  * **Rank_2**: feral_wrath: 12, freezing: 12, absorption: 6
  * **Rank_3**: feral_wrath: 14, freezing: 15, absorption: 12
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `nmagic_glacial_aura_duration`:
    * **Rank 1 (level_1)**: `10`
    * **Rank 2 (level_2)**: `12`
    * **Rank 3 (level_3)**: `15`
  * `nmagic_glacial_aura_freeze_duration`:
    * **Rank 1 (level_1)**: `4`
    * **Rank 2 (level_2)**: `5`
    * **Rank 3 (level_3)**: `6`
  * `nmagic_glacial_aura_wave_damage`:
    * **Rank 1 (level_1)**: `(2.6 + 0.65 * #src_nature_magic_level) * (2.0 + 0.015 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
    * **Rank 2 (level_2)**: `(2.2 + 0.54 * #src_nature_magic_level) * (2.6 + 0.029 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
    * **Rank 3 (level_3)**: `(1.7 + 0.44 * #src_nature_magic_level) * (2.9 + 0.036 * #src_nature_magic_level) * (1 + (#increased_magic_power_damage_percentage * .01)) * (1 + (#increased_ice_damage * .01))`
  * `nmagic_glacial_aura_wave_frequency`:
    * **Rank 1 (level_1)**: `0.8`
    * **Rank 2 (level_2)**: `0.8`
    * **Rank 3 (level_3)**: `0.8`


### Frost Aura (`ice_elemental_power`)
* **Summary**: Ice Elementals are feared for their ability to direct some of their freezing essence into waves of cold that damage and briefly freeze any enemies who draw near.\n\nAutomatically Targets Self\nNormal Recharge
* **Max Ranks**: 3
* **Stances Required**: `Any / None required`
* **Target Type**: `tt_self`
* **Cast / Charge Time**: 0.5s
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Unlock Requirements**:
* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:
  * `nmagic_glacial_aura_duration`:
    * **Rank 1 (level_1)**: `20`
    * **Rank 2 (level_2)**: `N/A`
    * **Rank 3 (level_3)**: `N/A`
  * `nmagic_glacial_aura_freeze_duration`:
    * **Rank 1 (level_1)**: `6`
    * **Rank 2 (level_2)**: `N/A`
    * **Rank 3 (level_3)**: `N/A`
  * `nmagic_glacial_aura_wave_damage`:
    * **Rank 1 (level_1)**: `2 + 0.5 * #src_nature_magic_level * ((0.06 * #src_nature_magic_level) + 0.5)`
    * **Rank 2 (level_2)**: `N/A`
    * **Rank 3 (level_3)**: `N/A`
  * `nmagic_glacial_aura_wave_frequency`:
    * **Rank 1 (level_1)**: `0.8`
    * **Rank 2 (level_2)**: `N/A`
    * **Rank 3 (level_3)**: `N/A`


---

## Pet & Summon Powers (1 Rank Each)

### skill_values (`skill_values`)
* **Class Type**: unknown
* **Target Type**: `None`
* **Recharge Formula**: `None`
* **Values**:


### requirements (`requirements`)
* **Class Type**: unknown
* **Target Type**: `None`
* **Recharge Formula**: `None`
* **Values**:


### Staggering Kick (`packmule_power`)
* **Class Type**: melee
* **Target Type**: `tt_conscious_enemy | tt_breakable`
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Values**:
  * `packmule_damage_percentage`: `30 * #src_melee + 250`
  * `packmule_blow_duration`: `8.0`
  * `packmule_blow_radius`: `3.5`


### Explosive Sting (`queen_scorpion_power`)
* **Class Type**: nature
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy | tt_breakable`
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Values**:
  * `scorpion_queen_damage`: `(60 + 15 * #src_ranged) * (0.06 * #src_ranged + 0.5)`
  * `scorpion_queen_radius`: `3.5`


### Inferno (`fire_elemental_power`)
* **Class Type**: combat
* **Target Type**: `tt_terrain | tt_conscious_enemy | tt_dead_enemy | tt_breakable`
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Values**:
  * `fire_elemental_damage`: `(22 + 5.5 * #src_combat_magic_level) * ((0.06 * #src_combat_magic_level) + 0.5)`
  * `fire_elemental_power_duration`: `5`
  * `fire_elemental_power_range`: `6`
  * `fire_elemental_power_dummy_radius`: `1`


### Furious Howl (`dire_wolf_power`)
* **Class Type**: nature
* **Target Type**: `tt_conscious_enemy | tt_unconscious_enemy | tt_breakable | tt_terrain`
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Values**:
  * `dire_wolf_damage`: `(60 + 16 * #src_melee) * ((0.06 * #src_melee) + 0.5)`
  * `dire_wolf_radius`: `5.0`
  * `dire_wolf_cone_angle`: `0.785`
  * `dire_wolf_dummy_radius`: `1`


### Arboreal Rejuvenation (`dark_naiad_power`)
* **Class Type**: nature
* **Target Type**: `tt_self`
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Values**:
  * `dark_naiad_heal_amount`: `30 + 6 * #src_nature_magic_level`


### Enrage (`mythrilhorn_power`)
* **Class Type**: nature
* **Target Type**: `tt_self`
* **Recharge Formula**: `12 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Values**:
  * `mythrilhorn_radius`: `10.0`


### Decompose (`necrolithid_power`)
* **Class Type**: combat
* **Target Type**: `tt_self`
* **Recharge Formula**: `35 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Values**:
  * `necrolithid_radius`: `3.0`
  * `necrolithid_duration`: `20.0`
  * `necrolithid_percentage_health_restored`: `2.5`


### Draconic Inspiration (`pocket_dragon_power`)
* **Class Type**: combat
* **Target Type**: `tt_self`
* **Recharge Formula**: `60 * (6 + 1.5 * #character_level) * (1 + 0.022 * #character_level) * #active_group_members`
* **Values**:
  * `pocket_dragon_radius`: `5.0`
  * `pocket_dragon_duration`: `20`
  * `pocket_dragon_power_damage_bonus_percentage`: `0.35`

