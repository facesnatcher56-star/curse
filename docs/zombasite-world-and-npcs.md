# Zombasite: towns, NPCs, clans, factions, modifiers and monster behaviour

Research notes for Curse, taken from Zombasite's own data files (Soldak Entertainment, 2015-2016; the studio also made Depths of Peril, Din's Curse and Drox Operative). Combat is deliberately left out; the focus is the world around it: **how towns and clans work, how NPCs think and relate to each other, how factions behave, what the dungeon/level modifiers are, and what monsters do when they are not fighting you.**

## How this was researched

- The game ships its data as plain zip packs (`Assets/assets001..004.zip`) that the manual itself says are moddable. Inside are text definitions (`Database/*.gdb`) and display strings (`Loc/English/*.trn`). Later packs override earlier ones, so everything below is the final (latest-pack) state.
- `tools/zombasite_dump.py` extracts and reads them (`extract OUTDIR`, `show OUTDIR FILE NAME`). Nothing from the game is stored in this repository; run it against your own install.
- **What is read vs inferred.** Numbers and lists are read straight from the data. Where I describe *how a system plays out* (the behaviour the engine builds from the data), that is inference, marked **(inferred)**. The engine's C++ logic is not visible, only its tuning data.
- File map (what lives where): `clans.gdb`, `clanTraits.gdb`, `factions.gdb`, `crimes.gdb`, `activities.gdb`, `quests.gdb` (events), `world.gdb`, `worldModifiers.gdb`, `levelModifiers.gdb`, `specialRooms.gdb`, `systems.gdb` (global tuning), `Monsters/` (`npcTypes`, `npcArchetypes`, `npcPersonality`, `npcChat`, `npcEnhancements`, `MonsterTypes`, `MonsterArchetypes`, `monsterEnhancements`, `BehaviorStacks`, `BehaviorData`), `Loc/English/*.trn` (all text).

---

## 1. The big picture

- **Premise.** A zombie parasite (the "Zombasite") is spreading. You lead a *clan* of survivors (the data calls clans "covenants" internally). The unit of play is an **area** (a region with a world map): one **town** (your base) plus a wilderness of levels (forests, deserts, plains, tropics, caves, dungeons, secret areas) linked by gates.
- **The area is a living simulation.** There are 3 to 8 AI clans (human and monster) in the same region, all pursuing their own goals, plus monsters, zombies and a stream of random events. The manual: *"Each and every town will be very different"*, and when an NPC says hurry, "they really do mean it."
- **Four ways to win, two to lose** (all enabled in the data):
  - Military: destroy every other clan. Diplomatic: all remaining clans allied (including yours). Logistics: stockpile a huge food surplus (the data sets a 10x multiplier on a clan's needs). Adventurer: solve every world quest.
  - Human loss: all your followers dead. Military loss: your *healthstone* (the clan's life crystal in town) destroyed. You get 10 minutes (`LoseTime 600`) to fix a losing position.
  - After a win you start a new area and your characters, items and recruits carry over.
- **Pacing knobs** (selectable at game start): starting monster level, area size, number of clans, pace (very slow ... very fast; slower pace = quests advance and monsters respawn slower, with a 15-20% XP penalty, faster = the reverse), "low stress" (no town attacks, -15% XP), difficulty tiers Champion/Elite/Legendary/Ultimate (attack multipliers 1.5x, 2.2x, 2.8x, 3.8x and up).
- **Clocks (global tuning, `systems.gdb`).** New quest every 180-300 s; new random event every 120-195 s; monster respawn 440 s (750 s after the player dies); there is a day/night cycle (`RealToWorldTimeFactor 24`, `RealToWorldDayFactor 10`; the exact real-time length is not visible); ground items vanish after 5 minutes (rarer items last longer).
- **World generation.** A disc-shaped "adventure" built from sections: a locked town section (10 town-level variants, up to 8 towns added) and a wilderness section whose monster level rises with depth and distance. Each area is stocked per map block (monster chance, chests, traps, objects), has a day/night light cycle with more and rarer monsters at night, gets random level modifiers (section 6), and almost every level has a gate for fast travel.

## 2. Your clan and your town

**What a town is.** A single level with a fixed layout: a front gate, a grid of dozens of NPC standing positions facing the town centre, houses, and your clan buildings. Monsters can still wander near it (a low density, more at night). The town is the hub you return to after every outing: gates make travel instant once activated, there is a one-use teleport stone, and dying and resurrecting at your personal lifestone necklace is the "other" way back.

**Clan buildings and services** (from the manual, help topics and data):
- **Healthstone**: free, quick healing in town (cannot cure zombie infection). It is also the clan's life: if it falls, you lose.
- **Clan gate**: teleport to any gate you have found.
- **Bulletin board**: the clan's own quests. Every other clan can also give you quests, usually through the Relations screen without walking there.
- **Crafting station**: salvage items, repair weapons and armour, enchant. Repair needs scraps and grindstones.
- **Clan layout**: where you place **relics** (magic items that affect the *whole clan* at once; four displayed), **guards** (captured monsters that defend against raids and town attacks; four on duty; bought from beastmasters, found bound to crystals, or captured on expeditions) and **doors**.
- **Stash and shared stash**, vendors, and a "clan info" screen with food, expeditions, gifts and zombie knowledge.

**Food is the clan's economy.** Shared by everyone; hunger runs per second and NPCs eat more when adventuring. Low food means rationing (everyone performs worse and is unhappier); no food means eventual starvation of clan NPCs. You get food by hunting, foraging, trapping, fishing, looting, or from destroyed clans. Cooks, hunters, foragers, fishers and trappers (NPC skills, see 3.7) make this go further.

**Expeditions** (from the Clan Info screen): send NPCs to **hunt** (food), **forage** (potion herbs), **adventure**, **capture guards**, or **scavenge**. Each costs 50 *expedition points*, which only regenerate while no one is out; going negative makes NPCs unhappy. Success depends on party size, NPC skills, the terrain (forests good for hunting, jungle for foraging, grassland for fishing), the area's food modifiers and a bit of luck. NPCs can be hurt, killed or infected while away. Timers: hunts 5 min, adventures 10 min, capture/scavenge 5 min.

**Vendors.** Wandering vendors come to town (more often with the "Vendors Galore" modifier and as your level rises) and have a **finite amount of gold**. There are specialist types (jewelers, food/drink, potions, bags, crafting, doors, beastmasters, and weapon/armour sub-types such as swords, axes, maces, staffs, daggers, bows, shields, cloth/leather/mail/plate, plus "Elite" versions). Every vendor pays the same for anything you sell. They hold the last two items you sold (buy-back) and can hold an item for you. 12-24 random items each (the data marks them as not restocking, and `MagicChance` is set very high, so most stock is magic).

**Threats to the town.** Town attacks, raids by other clans, invasions in waves (3, 6, 9, 12 or 15), horde attacks, ambushes, zombie town attacks, and traitors inside (see 3.5). Town attacks and sieges can be switched off with "low stress".

## 3. NPCs

### 3.1 Kinds of NPC (`npcTypes.gdb`, 244 definitions)
- **Free recruits**: by class (warrior x12, rogue, priest, wizard, ranger, conjurer, demon hunter x20, death knight x16, commoner), male and female variants. Recruits have personalities, skills and a level near yours. Recruiting is a trade-off: useful skills versus personality conflicts and another mouth to feed.
- **Commoners**, the **bulletin-board keeper**, and **wandering vendors** (above).
- **Hostile "hero" NPCs** (named renegade types) that appear as quest targets: sorceress, sorcerer, warlock, archmage, wizard, witch, mad wizard, mercenary, alchemist, black knight, fanatic, conqueror, necromancer, illusionist, syndicate rogue, druid, death knight, pyromancer, mastermind, infiltrator, inquisitor, executioner, gladiator, reaver, blackguard, dark templar, reaper, blood mage, summoner, nightblade.
- **Story NPCs**: prisoners and escaped prisoners, the insane, imposters, smugglers, pirates, spies, thieves, fledgling heroes, ghosts (NPCs that died and came back), and rescue / delivery / escort NPCs.
- **Every clan has its own NPC types.** Monster clans field their own races (orc, naga, saurian, torva, imp, dark elf ...) as clan members; human clans use human recruit archetypes (the Sisterhood only recruits women; the Mystic Brotherhood only priests, wizards and conjurers).

### 3.2 An NPC's mind: happiness, insanity, morale, hunger
- **Happiness** (the data works in a roughly -100 to +100 band, with no hard floor; activities switch on at -25, -75 and so on). Below 0 an NPC "causes more and more trouble": starts fights, makes others unhappy, sabotages the clan. Raising it: keep NPCs safe, living in a house, fed, rested and healthy, with good relationships.
- **Insanity** (0-100). At 100 the NPC goes insane and tries to kill anything nearby. Therapists reduce it; other NPCs leaving or being banished raise it (more for family, a little for friends).
- **Morale** drives fleeing in combat (NPC base 100; each hit costs 50, doubled at low health).
- **Hunger** ticks constantly; infection makes it worse.
- **Mood labels** shown to the player come from relation thresholds (Dislikes below 45, neutral 45-55, Likes above 55).

### 3.3 Personality (`npcPersonality.gdb`, ~450 definitions)
Each NPC gets 3-5 personality traits (with a chance of extra related ones). A trait never changes stats directly. It **re-weights what the NPC does in town** and **how they react to what others do to them**:
- **Behavioural traits (about 150).** Gossip, Drunk, Greedy, Generous, Adventurous, Religious, Jealous, Argumentative, Joker, Boastful, Seductive, Loyal, Scheming, Zealot, Fanatical, Paranoid, Gambler, Hateful, Vengeful, Pacifistic, Brave, Coward, Reckless, Lazy, Protective, Secretive, Romantic ... Each raises or lowers the weight of particular activities (e.g. Gossip multiplies gossip and secret-sharing x12-24; Drunk multiplies drinking x24; Greedy lowers gift-giving and raises the chance of turning traitor when unhappy; Adventurous raises quest-solving and banter, lowers base morale, and gives happiness from experience and kills). Some traits exclude each other (Sober vs Drunk, Greedy vs Generous).
- **Reaction traits.** "Likes / Loves / Dislikes / Hates" + an *interaction type*: arguments, conversation, gossip, praise, flirting, bragging, complaining, insults, jokes, small talk, banter, sharing, gifts, secrets, lectures, lies, snobs, cowards, the brave, beauty, outgoing people, boring talk ... The same event pleases one NPC and offends another, which is where relationships come from.
- **Fears and hates**: NPCs can fear or hate specific monster types and fear specific damage types. Hating a monster makes fighting it raise happiness; fearing one lowers it.

### 3.4 What NPCs do all day (`activities.gdb`, 107 definitions)
A town NPC runs a loop (about 15 s per activity; `ActivityTime 15`) choosing from weighted activities. The weight depends on mood: unhappy NPCs pick darker activities, happy ones pick sociable ones. Activities (each changes happiness, reputation and the other party's feelings, and plays a status effect/animation):
- **Social:** conversation, small talk, banter, jokes, sharing, gifts (to NPCs or to the player), praise (also of third parties), flirting, marriage and divorce, gossip and keeping/telling secrets, lies (also about third parties), boasting, lectures, boring talk.
- **Conflict:** arguments (normal, upset, very upset), insults, complaining (also about third parties), jealousy.
- **Habits:** drinking (at vendors; can make them drunk), gambling (small wins 40% at 2x, jackpots 0.2% at 50x; wins and losses move relationships), praying.
- **Duty:** *job* (do their skill's work: diplomacy, enchanting, therapy, cooking...), solving quests for the clan (more likely for adventurous types; success chance weighting 5:1:1 for success / failure / nothing), personal quests, paying off a debt.
- **Worry:** "dwell on" the zombie infection, low food, no food, a clan war, a raid, a town attack (each drains happiness and spreads the mood).
- **Greeting the player:** "hello", "I want to talk" (an NPC walks over when it has something to say; the chat system below).
- **When very unhappy (happiness below -100):** leave town, or turn **renegade** (a hostile quest target); both have a high weight (5.0) compared with a normal activity (about 0.05-4).
- **Traitor activities (happiness below -10).** An unhappy NPC may secretly commit one of ten acts, each of which also spawns a *clue quest* for the player to find the culprit (the "evidence" quests): set traps in town, poison the food supply, spread plague, curse the town, scout for the monsters, side with an enemy clan's war on the town, plan an uprising (raid or town-attack plan), open the gate to the enemy, use deadly poison.
- **Crimes and punishment** (`crimes.gdb`). When a traitor/thief is caught, the town's reputation and the NPC's happiness fall and they are fined, scaled by severity: theft is mild (victim reputation -10, town -5, fine 2x); traps, curses and monster scouting are -10 / 4x; plague, poisoned supply, war against the town, uprising raid plans, opening the gate and deadly poison are -15 / 6x; planning a town-attack uprising is the worst at -20 / 8x.

### 3.5 Relationships between NPCs
- Relationships are pairwise and persistent. They can be friends, good friends, married, or dislike/hate each other, and each pair's opinion is visible per NPC.
- **Bad relations make NPCs fight, even to the death** (`CanNpcFightOtherNpcToDeath` is on). **Enough dislike gets an NPC banished** from the clan; the banished may join another clan (10%), start one (2%) or steal food (10%). Banishing and leaving raise other NPCs' insanity and lower their happiness/morale (family most).
- You repair relationships by **giving gifts to one NPC in the name of another**, or break up a fight by **donating food or money to both**.
- Relationship events are broadcast to others through the dynamic chat system (3.6).

### 3.6 NPC dialogue is event-driven (`npcChat.gdb`, 168 chat definitions)
Rather than scripted conversations, NPCs and monsters **react to events with short lines**, so the world feels reactive. NPCs have a generic talk pool plus ~90 triggers, including: a clan-mate turning zombie / getting infected / infection worsening / cured; a raid defended or repelled; the player defending a raid or saving the town; the player dying; an NPC killed by a normal or unique monster; a clan destroyed (by monsters, by you, by another clan); rain, snow, a special level; finding or crafting a unique item; being rescued or rescuing; a boss, unique monster, assassin, scout, hunter, renegade or thief killed; rescue / delivery / escort NPCs dying; being cured of poison, petrification or a curse; random insult, praise or complaint; hunger starting and ending; a new recruit; being recruited; being insulted, gifted, praised, shared with or argued with by another NPC (with different lines if they *like* that behaviour); fear or hatred of a monster; boasting after a kill; the clan's power ranking (most powerful / weakest clan, ours or another); relationship milestones (married, good friends, friends, hate, dislike); fights started by me or by others; wars, peace and treaties started by us or by others (with different reactions depending on which side the speaker likes); going insane; being banished; a good item for sale; an NPC turning renegade.
- **Monsters talk too** (`monsterChat.trn`): taunts, gloating when they kill the player or an NPC, mocking when the player runs, remarks when they level up ("upgrade"), when they pick up a new item, when they cause trouble (events), when they retreat, calling for help, and when they banish the player. Orcs, imps, nagas, torva, death knights, liches, horrors and undead heralds each have their own voice.

### 3.7 NPC skills and jobs
Passive "clan skills" that work whether the NPC is home or on an expedition: **Cook** (clan makes better use of food), **Hunter / Forager / Fisher / Trapper** (more food, each best in a terrain), **Herbalist** (occasionally brews health potions), **Alchemist** (elixirs), **Enchanter** (cheaper enchanting for the clan), **Diplomat** (improves relations with other clans), **Beastmaster** (stronger guards), **Therapist** (lowers another NPC's insanity), **Spy** (cheaper rumours, sabotage and quest-target searches). Doing a job produces a visible log line ("X's therapy decreased Y's insanity by 3"). NPCs can also carry minor "enhancements" (extra strength, quickness, stone skin, resistances including zombie resistance, extra attributes), and special flags exist for recruits ("hero" recruit, basic recruit), vendors, renegades, rescue, delivery, escort and fledgling heroes.

## 4. Clans and factions

### 4.1 The clan roster (`clans.gdb`)
Danger Low / Medium / High is shown to the player. Every clan has two *traits* (4.2); the Mystic Brotherhood's are random each game. "Brings" = the level modifier the clan's presence is tied to.

| Clan (race) | Align. | Danger | Traits | Notes |
| --- | --- | --- | --- | --- |
| Eternal Darkness (dark elves) | evil | High | Ruthless, Aggressive | Cohesive only while they share an enemy. Always has a hero. Wars via assassins and plague. Brings Darkness. Guards are zealots. |
| Demon Spears (scree, mini demons) | evil | High | Chaotic, Deceitful, Recruiter | Swarm, lie for fun, seldom keep promises. War by uprising. |
| Inferno (goblin fire throwers) | evil | High | Defensive, Deceitful | Arsonists who also sabotage relationships between other clans. War by siege. |
| Frenzy (targ) | evil | High | Defensive, Chaotic | Rarely kill each other; slow to start outside fights. |
| Fang (naga) | evil | High | Deceitful, Spies | Master liars and spies. War by poisoner assassins. |
| The Scourge (orcs) | evil | High | Raider, Chaotic | Disciplined for orcs, "don't leave survivors". War by town attacks. |
| Dragon Claw (saurians) | evil | High | Aggressive, Adventurous | Aggression is partly show. Weak to cold. Brings Storms. War by building weather/earthquake/anti-magic/temporal-flux machines. |
| Eviscerators (torva) | evil | High | Demanding, Aggressive | Fair to allies, hard to please. Immune to fire. Brings Rain. War against the town. |
| The Horde (orcs + goblins) | evil | High | Raider, Deceitful, Recruiter | Believe their own lies, raid at any slight. |
| Reptilian Terror (saurians + nagas) | evil | High | Adventurous, Spies | Spies and saboteurs, decent allies. Brings Storms. |
| Little Titans (imps) | neutral | Medium | Trader, Spies, Recruiter | Foragers and traders; trade secrets only with trusted clans. |
| Order of the Moon (stalkers) | neutral | Medium | Adventurous, Honorable | Hunt zombies, keep deals, never take more than they need. |
| The Enlightened (outcast monsters of any evil race) | good | Low | Honorable, Defensive | Monsters who chose a code of honour; seek peace talks. |
| Nemesis (humans) | evil | High | Aggressive, Deceitful | Unscrupulous; trust no one beyond short-term goals. |
| Nightwatch (humans) | neutral | Medium | Recruiter, Defensive, Generous | One of the largest; loose, sociable, cohesive against enemies. |
| The Guardians (humans) | good | Low | Defensive, Honorable | Strict code, loyal allies, favour underdogs. |
| The Collectors (humans) | neutral | Medium | Collector, Lucky | Want your good items; trade often. |
| Sisterhood of Light (humans, women) | good | Low | Honorable, Trader | Better deals with clans that have female members; good diplomats. Brings Brightness. |
| Mystic Brotherhood (humans) | neutral | Unknown | random | Wild card. Priests, wizards, conjurers only. |
| Heart of Gold (humans) | good | Low | Financial, Generous | Rich and giving. |

- **Zombie versions.** Sixteen of the clans have an infected "Zombie ..." version (Zombie Spears, Zombie Fang, Zombiewatch, Heart of Zombie ...) that replaces them when they fall. Orcs, torva, The Horde and The Enlightened have none ("some monsters are immune").
- **Clan power** (used for AI decisions): people count the most (x10), then house, items and lifestone (x1 each).
- Raid parties are limited to 6 members (`MaxRaidGroupSize`) and adventure parties to 2; an area gets a random 3-8 AI clans.

### 4.2 Clan traits (`clanTraits.gdb`)
A trait is a set of multipliers on diplomacy and war behaviour (plus sometimes a status effect on members):
- **Ruthless** stays angry once angered; wars start 12.5% more readily. **Aggressive**: worse relations, wars start quicker. **Chaotic**: unpredictable (changes direction often).
- **Deceitful**: much more likely to cancel agreements (honour x0.75). **Honorable**: much less likely (x1.25), and positive diplomacy 20% stronger, negative 20% weaker. (Mutually exclusive.)
- **Defensive**: starts wars 10% and raids 17% less; recruit defences boosted. **Raider**: raids 40% more likely. (Mutually exclusive.)
- **Spies**: spying attempts x4, success x1.8, resistance halved, recruits harder to notice. **Adventurous**: recruits adventure much more. **Recruiter**: x2.5 recruiting.
- **Demanding**: x2.25 demands. **Generous**: x1.5 gifts. (Mutually exclusive.) **Trader**: x1.75 trade attempts.
- **Collector / Lucky / Financial**: better or more items, more money.

### 4.3 The relations engine (`BaseClan` tuning)
Relations are a number from 0 to 100 between every pair of clans, **starting at 50** (47.5 for zombie clans). Things happen when thresholds are crossed and as a stream of small events:
- **Thresholds.** Dislike below 45, like above 55. Peace treaty needs ~44 (38 easy, 50 hard); non-aggression 57.5; mutual protection 70; alliance 80; joint adventures need 50-60. **Raids start** at a relation of 20 (easy), 30 (normal), 40 (hard) or 42.5 (very hard) **(inferred: below that value)**. Wars and agreements trigger from relation 40-50.
- **Treaties.** Signing gives +0.5 to +0.75. Cancelling costs -4 (non-aggression), -8 (mutual protection), -12 (alliance); other clans that were friends of the victim punish the breaker too. 
- **Things that move relations:** random drift every 30 s (about -0.075 to +0.05); being at war or sharing territory (-0.4); a *desired war* (-1.2); weak or differently-levelled people (-0.1/-0.2); enemy-of-my-friend / friend-of-my-enemy (-0.15 to +0.1) and enemy-of-my-enemy (+0.15); compliments (+0.75..+1.25) and insults (-0.75..-1.25); demands (-1..-2, rejected -0.5..-1); ignored trade (-1..-2); gifts and trades; **killing an enemy monster near them** (+3..+9); killing their member (-1..-3); trading with their enemy (-0.5..-0.25); shared adventures (XP-based gain, jealousy when you leave, -5 on a partner's death); long wars gradually cool.
- **Fear** is its own number (base 5, max 50) that changes with raids won/lost, war results, being raided, alliances (+/- multipliers) and the state of the lifestone, and it feeds trade and demand values.
- **What a clan does to you and to others, per second of idle time (chance curves versus relation):** demands (likely at low relation), trades, gifts (at high relation), compliments, insults (at low relation), pleas for help, **positive and negative rumours, propaganda, espionage and sabotage** (each with quick / planned / well-crafted versions that take 1.5 to 4 minutes), and "peace" / "war" / "break treaty" requests.
- **Raids.** A clan can raid you or another clan (`CanRaid`). The chance multiplies for bad relations (x4), for being the enemy of an ally, and for an enemy that is hunting, raiding or being raided, and is lowered if the clan raided lately or its own lifestone is threatened. Each raid carries an end-chance that shifts with how the lifestone fight is going and with how long it has dragged on (5, 10 and 15 minute marks). Raids and wars also generate quests for the player (bounty hunters, assassins, kill-member quests, siege, town attack, uprising, scouts), some given to *you* and some to *their enemy*.
- **Quest jealousy.** Doing a quest for one clan changes how the others feel: enemies of that clan -2, neutral -0.6, friends 0.
- **Quest rewards flow through relations**: solving a clan's problem raises its opinion of you; friends of that clan also warm to you, its enemies cool. Solving for an enemy hurts.
- **Dialogue flavour** differs by alignment (good clans say "Accept our friendship", evil ones threaten), with separate line sets for offers, trades, gifts, demands, acceptance, rejection and confirmations.

### 4.4 Monster factions (`factions.gdb`, 91 definitions)
Beneath the clans, every monster belongs to a **faction** (a race or kind) with a reputation matrix: 20 means enemy, 80 or 100 means ally, the default is 50 (neutral). This is what makes monsters fight *each other* in the wild:
- Orcs vs torva and hell hounds; naga and saurians (allied) vs dark elves and stalkers; wisps vs furies; giant spiders vs scorpions; hell hounds vs ragnar; the five imp kinds (pixie, sprite, imp, gremlin, urchin) all fight each other but belong to one clan.
- Necromantic: liches ally with zombies, skeletons, undead heralds and ghosts; ghosts ally with zombies; death knights ally with elementals.
- Everything shares allies among objects, totems, traps, gargoyles, cave-ins, dimensional gates and "monster leader" units.
- Players are a separate faction (monsters default to 30 toward them: hostile). Clan factions (one per clan) inherit their race's friends and enemies.
- **Avatars** (rare boss-like manifestations: Blixt for saurians, Erillin for nagas, Hamlec for orcs, Kracht for stalkers, Mortus for undead, Valta for dark elves) are allied to their race's faction.
- The "Chaos" and "Wars" world modifiers make this infighting more frequent.

## 5. The event web (`quests.gdb`, 584 definitions)

Almost everything that happens is a **quest/event** definition with chances to spawn randomly, and **chains** (`OnEventQuestName`, `OnCompleteQuestName`, `OnFailQuestName`, each with a probability). So events cause events:

- *A unique monster is spotted* -> it may plan a raid, a town-attack, an invasion, build something, or become a bounty target. Failing to stop it *completes* its goal, which becomes a new problem (an uncompleted "build an earthquake machine" quest turns into a running earthquake machine, which adds a level modifier to the area).
- **Unique monster roles** (named monsters with a job): Raider, Pillager, Invader, Siege Master, Scout Master, Assassin Master, Hunt Master, Trickster, Slave Master, Trap Master, Bomb Master, Fire Master, Plague Master, Poison Master, Puppet Master, Enforcer, Collector, Soul Hunter, Rumor Monger, Coward, Ambush Master, Lich, Machinist, War Monger, Peacemaker, Fallen Hero, and altar builders for the six avatars.
- **Things monsters build** (each is a quest to find the plans and stop it): gates, altars, curse altars, recon totems, machines (earthquake, noise, weather, darkness, anti-magic, temporal flux, fog, ice), fleets/armies. A finished machine changes the area's rules until destroyed.
- **Uprisings**: monster hordes/armies rise (zombie, demon, saurian, naga, orc, skeleton, lich, death knight, dark elf, plus "madness" and "area overrun"); they can block gates and escalate into a war against the town.
- **Assassins** (kidnap, trapper, bomber, fire, poisoner) and **scouts/spies** are sent by clans or monsters against the town; assassins can also seed town problems (plague, curse, petrify, shrunk, madness, deadly poison, poisoned supply, noise machine, town traps, bombs) each with a 10-20% chance.
- **War, truces and meetings** between clans (war battles, world wars, "upset factions", peace talks, truce meetings).
- **Town attacks and raids**: single, large, and multi-wave invasions (3-15 waves), surprise starts, pillage, blitz, horde attacks, zombie variants of each.
- **Ambushes** (small, medium, large, remote, zombie, ghost, hidden, ranged).
- **Hunting parties against monsters** (monster hunter, bounty hunter), kill-a-group quests (named groups: coven, council, syndicate, thieves, marauders, cult, triumvirate, outlaws, pirates, smugglers, bandits, assassin guild, vigilantes, circle).
- **Personal and economic quests**: recover a body, lost heirloom, treasure maps (hoard, tomb, pirate, food, enchanter), craftsmen's quest items (weaponsmith, armorsmith, blacksmith, enchanter, tailor, leatherworker, jeweler, carver, bowyer, fletcher, weaver, cobbler, each with a bonus version), find plans, deliveries (artifact, peace talks, gift, captured renegade, stolen goods, personal, smuggled goods), get-information missions, escorts, rescues (monsters, starving, ambushed, pirates, smugglers, spies, mercenaries, alchemists, fanatics, illusionists, disappeared, vendors, prisoners), and renegade hunts (every hostile hero type, in an "at this level" and an "any level" version).
- **Pace controls** scale how fast these fire (event timer -10% per extra player, "nemesis time escalation x5", etc.).

## 6. Dungeon / level modifiers (the main design takeaway)

Each level (and the whole region, via a matching "world modifier") can carry modifiers that change the *rules and population* of the level. Roughly **half of levels get one** (`LevelModifierChance 0.5`, **inferred** to be a per-level roll); there are secret "More/Less modifiers" modifiers that add 3 or remove 10. Modifiers have a minimum player level, may be above-ground-only or below-ground-only, can stack up to a copy limit, and some are mutually exclusive (Darkness/Bright, Rain/Dry, Good/Bad foraging). They show as a prefix and suffix on the level name ("Foggy ... of Fog"). Clans also bring their own: Darkness (dark elves), Storms (saurians), Rain (torva), Brightness (Sisterhood).

**How a modifier acts (data patterns, all from `levelModifiers.gdb`):**
- *Spawn weights*: multiply the chance of specific monster archetypes (x6 to x20).
- *Object weights*: multiply specific objects (traps, barrels, chests, web, mushrooms, obelisks, support beams, active monster traps).
- *Counts*: more weather fronts, lightning, tornadoes, traps, chests, money, objects, ghosts, gargoyles, ambient critters.
- *Lighting*: darker world and darker entity lighting.
- *Enhancement weights*: more of a monster affix (x24).
- *Economy*: food/drink prices, hunting/foraging/fishing/trapping yield.

| Modifier | What it does | Notes |
| --- | --- | --- |
| Rainy / Dry | Weather fronts x8 and less fire / drier, more fire | above ground; exclusive |
| Storms | Weather x16, lightning x20 | above ground; saurian clans |
| Tornado Alley | Weather x16, tornadoes x12 | above ground |
| Electrical Hazard | Lightning traps and cone traps, lightning elementals, wisps, saurian mages, storms | |
| Traps / Monster Traps | Ground traps x16 / active monster-built traps (spinners, poison towers, fire/ice spin towers, poison clouds, cone traps) | L5+ / any |
| Trickster Realm | Objects locked and trapped far more often (x12) | L10+ |
| Gargoyles | Many monsters are statues that wake up (x16) | L5+ |
| Undead / Haunted / Demons / Spiders / Dark Elves | One family's spawn weight x12-20 (spiders add webs, haunted adds ghosts) | |
| Horror | Undead x8, dead bodies, darkness, monsters call out more | |
| Fear | Dead bodies, "ground spawn" traps x24, ghosts/shadows/invisible x12, darker, noisy | |
| Cursed | More cursed items, liches x16, curse traps | |
| Acid | Acid traps x24, nagas and naga priests x8 | L10+ |
| Fire Hazard / Explosion Hazard / Magma | Oil barrels and fire traps / exploding barrels and magical explosions (fewer chests) / magma traps and volcanoes | |
| Unstable | Ground cracks, ceiling drips, steam and gas leaks, support beams (cave-ins) x12 | below ground, L10+ |
| Mushrooms | Poison mushrooms x32 | |
| Foggy | Fog patches x32 (melee is hampered in fog) | |
| Anti-Magic | Anti-magic fields x12 (spells misbehave) | L10+ |
| Temporal Flux | Flux fields (projectiles slow to a crawl) | L10+ |
| Darkness / Bright | World light x-2 / x+0.5 | exclusive |
| Clutter / Warehouse | Many more breakables; barrels and crates | |
| Gigantism / Fleet of Foot / Berserk | Monster affix (Giant / Fleet of Foot / Berserker) weights x24 | L10+ |
| Aggressive World | Monster aggression range doubled | L20+ |
| Noisy (secret) | Monster idle sounds x12 (they call out and alert) | |
| Mining / Treasure / Obelisk Heaven / Money / Chests (secret) | Gold veins, many chests, buff obelisks (giant, haste, stone skin, regeneration, life/power steal, holy shield, infinite power/stamina, fire shield) alongside evil obelisks that monsters can use | rewards |
| Good/Bad Hunting, Foraging, Fishing, Trapping; Famine; Good/Bad health and mana potion foraging | Multiplies each expedition yield; Famine (L25+) cuts every food source | above ground; exclusive pairs |
| Infestation | Ambient critters, raising food prices | quest-driven |

**World (region-wide) modifiers.** All of the above can apply to the whole region, plus: **High Intensity** (dangers move quicker), **Vulnerable Town** (attacked more), **Chaos** (monsters always at war, L20+), **Wars**, **Dangerous Monsters** (stronger, fewer), **Raging Hordes** (more, weaker), **Vendors Galore**, the four **pace** settings, **Low Stress**, **Plague**, **Paying Traitors**, slow/fast **NPC pace**, the **machines** (earthquake, darkness, weather, anti-magic, temporal flux, fog, ice) that monster plots can switch on, and the **town personality** modifiers: **Gambling, Seedy (more crime), Misery (dwell on problems), Drunk, Religious, Social, Heroic, Thieves Den, Cupid (relationships go well), Rowdy (fights).**

**Zombie infection mutations** (world modifiers that make the Zombasite itself evolve in an area): more contagious, more carriers, deadlier, faster incubation, more parasites, more uprisings / town attacks / wars, weaker resistance, harder to cure, and "all new zombies (or parasites) have a minor affix" (extra strength, quickness, elemental resistance, fleet of foot, defender, berserker, zealot, giant, deadly aim, cold/fire/lightning/poison imbued, regeneration, warrior, guardian, tempest, slayer, stalker).

**Special rooms** (`specialRooms.gdb`, each in Lesser / normal / Greater): vault, sanctuary, armory, treasure room, lair, torture room, massacre, food room, graveyard, shrine, storage (barrels, jars, crates), experience room, boneyard, game room, and others: themed side-rooms with their own loot, monsters and rules.

## 7. Monster modifiers (enhancements, `monsterEnhancements.gdb`)

Monsters roll **affixes** that scale in three tiers (Minor / normal / Major; Minor-Major are the `1`/`2`/`3` variants) and add a name prefix/suffix ("the Leader"). Rarity tiers (common ... unique, plus twelve unique levels) exist as enhancement definitions and presumably decide how many a monster rolls **(inferred)**. Families:
- **Stat**: Extra Strength, Quickness, Stone Skin, Elemental/Magic Resistance, Fleet of Foot, Defender, Berserker, Zealot, Giant, Deadly Aim, Warrior, Guardian, Tempest, Slayer, Stalker, Wealth (more loot).
- **Special hits**: Critical, Crushing, Stunning, Deep Wounds, Thorns, Mana Burn, Stamina Burn, Life Steal, Regeneration.
- **Elemental**: Cold / Fire / Lightning / Poison / Acid / Elemental Imbued, Fire Shield, resistances up to "Incredible", fire/ice/acid weapons.
- **Auras**: fire, cold, lightning, poison, elemental, healing, circle of protection, circle of power, anti-magic, fog, temporal flux, ice/lightning/fire/poison wards (each with an offence and a defence aura), and race auras (dark elf, orc, undead).
- **Behavioural "major" affixes** (these change how a monster *acts*, not just its numbers): **Leader** (friends with all monsters and *calls for help each time it is hurt*), **Terror** (lowers the morale of everyone nearby each time it is hit or hits), **Teleporter** (blinks when hit), **Hunter** (slow but accurate, high crit), **Swarm** (extra projectiles), **Healer**, **Vampire**, **Beast**, **Dragon**, **Ancient**, **Executioner**, **Shadow**, **Noxious**, **Flux**, **Cursed**, **Savage**, **Bloodthirsty**.
- **Special states**: Gargoyle (statue that wakes), Controlled Undead (a necromancer's follower), Zombie Infection (can spread it), Nemesis / Arch-Nemesis (a promoted monster with 3x health and reduced attack, tracked over the run; `NemesisChance 1.0`, escalation timers x5), Avatar (good/evil).
- The level modifiers Gigantism, Fleet of Foot and Berserk simply raise the weights of the corresponding affixes in a level.

## 8. What monsters do when they are not fighting

Monster behaviour is a **priority list ("behavior stack")** evaluated every tick: the first behaviour that applies wins. The stacks are data, picked per monster archetype:

- **Standard melee monster:** teleport to leader (if too far) -> melee -> follow leader -> avoid leader (don't crowd) -> use objects (their clan's healthstones when hurt) -> pick up items -> **adventure** -> return home -> **idle** -> **sleep**.
- **Skill users** add Retreat (flee on low morale/health), Use Object, Use Skill; **ranged** add Avoid Danger, Approach and a kiting retreat. **Spiders** add Jump; **necromancers** Raise Dead; **scavengers** Eat Corpse; **dimensional gates** only eat corpses and use skills; **lurkers** and **stationary** monsters have shortened stacks.
- **Behaviour parameters (`BehaviorData`)**:
  - **Idle**: think every 0.4-0.6 s; stand still 0.5-1.5 s (active kinds 0.25-1 s, stationary 1-2 s); idle range ~800 units with a **patrol range of 250**; occasionally make an idle sound (every 4-6 s, 20% chance; "loud" types 2-3 s at 45%) and **other monsters within 300-1000 units answer (40%)**: this is how packs notice and gather. They will not run while targeted (`DontRunWhenTargeted`).
  - **Adventure**: wander in 250-unit steps with random offsets, retarget the final goal after 5 failures, goals up to 1000 units away: monsters roam beyond their spawn.
  - **Return home**: starts beyond 200 units, ends within 100.
  - **Follow / avoid leader**: stay within 150-300 of the leader and no closer than 125; **teleport to the leader** beyond 600.
  - **Use objects**: sense range 400; they use **obelisks** (for the buff, only when it is a new effect), **turn torches off** (making an area dark) and, for clan monsters, **turn the clan's lights back on**, and use **healthstones when hurt** (held while it heals); some use machines, and death knights have their own object list.
  - **Pick up items**: monsters pick up loot they see (and later comment on the new item).
  - **Retreat**: runs 250 units, uses morale; `KeepRetreating`.
  - **Activity (clan members)**: every 15 s decide whether to do a social activity, with 30-45% chance depending on happiness.
- **Senses and stealth:** per-archetype aggression range (300; NPCs 350), a smaller range against hiding targets, a 20% chance to still notice a stealthed enemy at half range, separate sense/hearing/knowledge timers (1 s / 4 s / 2 s). Noise (bashing doors/chests, loud modifiers) alerts monsters.
- **Hiding:** some monsters hide in a surface (chance, "group extra hide chance", hide when out of sight) and **ambush**; others are partly hidden (skeletons, scavengers).
- **Morale** (base 10 for monsters): drops when hurt with no enemy near, from nearby terror, from hazards of a given type (wisps from lightning), recovers 1/s; at low morale they **flee**, then come back.
- **Packs and leaders:** monsters spawn with **followers** (archetype lists), a leader's pack **calls its group** when idle-calling or hurt, necromancers keep up to 10 followers within 500 units, pets keep owner stats.
- **Eating and raising:** scavengers and spiders **eat corpses** (some grant a temporary bonus: giant spiders gain poison imbued); necromancers **raise dead** into controlled undead; nearly any corpse of a susceptible archetype can be **turned into a zombie**.
- **Kidnapping:** most archetypes are flagged as able to kidnap; assassin events can kidnap NPCs from the town (25% chance per assassin), who must then be rescued.
- **Messengers of the world:** monsters are sent as **scouts and spies** to watch the town, as **assassins**, as **raiders**, **hunters** and **bounty hunters**, and some clans pay monsters to attack (10-15% town-attack chance per clan).
- **Guards:** most archetypes can be guards; bound-to-crystal guards can be found, bought from beastmasters or captured; a guard's worth scales with level.
- **Respawn rules (`GameSystem`):** 440 s normal, shorter where the level was not loaded (10 s), longer after the player dies (750 s); each kill adds 4 s; much faster in the middle of a battle (x0.2); respawns avoid spawning within 450 units of the player, 600 of a clan, 450 of gates, 300 of inhabited places; a third chance to respawn near an inhabited place.
- **Upgrades:** monsters gain levels and strengthen over time and from kills (they comment when they "upgrade"); nemeses persist and escalate.
- **Day and night:** nights have a higher chance of uncommon/rare monsters and a different light colour (`NightSunColor`).

## 9. Zombie infection (the clan-wide threat system)
- Any damage taken from a zombie can infect, more likely the bigger the hit compared to max health.
- **Stage 1** (hidden): the victim is hungrier, less happy, loses morale and relations faster. **Stage 2**: little health regeneration, takes damage until death, much worse penalties; **carriers** spawn zombie parasites and do not tell anyone they are infected. A victim killed by the infection or by a zombie **turns into a zombie** soon after; NPC zombies are much stronger and keep class and personality bonuses.
- **Cures** (the Zombie Knowledge screen unlocks facts as you kill/repel/quell enough zombies, uprisings and town attacks): health potions (higher level works better), zombie-resistance potions (best; made with Oil of Purification), fire or poison damage (small chance), skills that heal everything at once. Drinking a mana potion poisons a stage-2 victim, and a resistance potion poisons any infected one. Resistance lowers the chance of catching it. Stage 2 infected and carriers can't attack zombies, and zombies ignore them in return.

## 10. What Curse could take from this

These are suggestions (not decisions), mapped to Curse's current wave-survival arena:

1. **Level modifiers as wave modifiers.** The cheapest high-value import. A modifier is just data: *spawn-weight multipliers, object/hazard weights, affix weights, lighting, counts*. Curse already has data-driven enemies (`EnemyDef`) and spawn composition in `RunDirector`; a `WaveModifierDef` resource (name, prefix/suffix, enemy-weight table, hazard list, affix weights, light level, min wave, incompatible list) would give "Spidery / Foggy / Unstable / Cursed" waves with no new systems beyond hazards. Roughly half of waves modified, with a "more/less modifiers" knob, is the original ratio.
2. **Tiered monster affixes with behavioural ones.** Zombasite's affixes come in Minor / normal / Major tiers and include **behavioural** ones (Leader calls for help when hurt, Terror lowers morale around it, Teleporter blinks when hit, Swarm adds projectiles). Curse's `EnemyBehavior` classes make behavioural affixes straightforward (wrap or override a behaviour), and level modifiers like Gigantism/Berserk are just weights on those affixes.
3. **Behaviour stacks.** The priority-list model (retreat -> use skill -> melee -> follow leader -> adventure -> return home -> idle -> sleep) maps onto `EnemyBehavior` as composable layers. The outside-combat layers (idle patrol, calling to the pack, following a leader, picking up items, using the environment, hiding) are what make monsters feel alive between fights.
4. **Monster faction infighting.** A small reputation matrix (orc vs torva, wisp vs fury ...) makes unaligned monsters fight each other, which creates openings and chaos for free. Curse's new enemy types (ghoul, spitter, bloater, priest) could get a matrix and a "Chaos" modifier.
5. **Monsters that talk.** A short line set triggered by events (killed the player, player ran, levelled, picked up an item, retreated, asked for help) is cheap and adds a lot of character.
6. **A town/hub between waves** (if Curse grows one): the clan loop (healthstone, crafting, bulletin board, vendors with finite gold and buy-back, relics and guards in a layout, food as pressure, expeditions with a cost pool) is a complete design to draw from. The minimum viable slice would be a hub with vendors (finite gold), a crafting station and a bulletin board of generated quests.
7. **NPC companions with happiness, personality and relationships.** The personality system is data: a trait is a weight table over activities plus likes/dislikes over interaction types. A tiny version (3 traits from a list of ~20, happiness, a few activities) already produces the "NPCs gossip, argue, get banished, turn traitor" stories; traitor "evidence quests" are a great way to give the player an investigation.
8. **Clans and diplomacy** only matter if there is a world map; a smaller faction layer (3-4 factions with a single relation number, thresholds for peace/raids, quest jealousy, rumours/sabotage) can sit on top of waves or a run map.
9. **Events as chains.** Define events with spawn chance and `on_event / on_complete / on_fail` links (with probabilities). That single pattern gives raids, uprisings, built machines that become modifiers if you fail to stop them, and assassins/scouts, with very little code.
10. **Tuning discipline.** All of this is numbers in files (relation thresholds, chances, multipliers). Curse's `tools/write_*_defs.py` pipeline already supports that approach.

**Open questions worth deciding before building any of it:** whether Curse stays a single arena or grows a map and hub; whether NPC relationships are a feature or flavour; and how much of the modifier set (many need hazards/objects that do not exist yet) to build first. The modifiers that need no new content are the spawn-weight and affix-weight ones (Undead, Demons, Spiders, Dark Elves, Gigantism, Fleet of Foot, Berserk, Aggressive World, Darkness/Bright, Clutter).
