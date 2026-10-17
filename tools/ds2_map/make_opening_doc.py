"""DS2 opening-monster research tools (see docs/ds2-opening-monsters.md).
Steps:
  1. python tools/ds2_dump.py extract OUT/ds2all <names...>   (or extract every .gas of Logic.ds2res into one folder) -> set DS2_LOGIC_DIR
  2. python tools/ds2_map/tank_tree.py "<Steam>/Dungeon Siege 2/Maps/World.ds2map" OUT/map regions/a0_ regions/a1_01_ ds2_world/info/
     (keeps folder paths; the regions then sit in OUT/map/world/maps/ds2_world/regions -> set DS2_REGIONS_DIR)
  3. python tools/ds2_map/analyze.py a0_01_05_tutcav ...        (counts), or import analyze and call encounter_report(region)
  4. python tools/ds2_map/make_opening_doc.py                   (rewrites docs/ds2-opening-monsters.md)
"""
import collections, json, os
import analyze as A

table = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../data/reference/ds2_xp.json')))


def hero_level(xp):
    l = 0
    for i, t in enumerate(table):
        if xp >= t:
            l = i
    return l


def fightable(t):
    return not any(s in t for s in ('npc', 'nis', 'dryad', 'rustguard'))


FORMULA = {  # tier base -> (low base, slope) from the monster templates
    'trivial': (20.0, 5.0), 'weak': (36.0, 9.0), 'normal': (48.0, 12.0), 'strong': (60.0, 15.0), 'miniboss': (160.0, 40.0)}


def formula_xp(tier_base, level):
    tier = tier_base.replace('base_actor_evil_', '').split('_')[-1]
    if tier == 'tank':
        tier = 'normal'
    b = FORMULA.get(tier)
    return (b[0] + b[1] * level) if b else None


L = []
w = L.append
w('# What Dungeon Siege 2 puts in its opening: monsters, levels and groups')
w('')
w('Read from DS2\'s own data (`World.ds2map` region files and the monster templates in `Logic.ds2res`), so every number below is the')
w('game\'s, not a guess. Tools: `tools/ds2_map/` (extract a region with its folder paths, parse the templates, count and group the monsters).')
w('"Hero level" is DS2\'s own 0-based level (a fresh hero is Level 0, see `docs/COMBAT_REFERENCE.md`). Training dummies and scripted')
w('cut-scene extras (invincible or `_nis`/`_npc` actors, the endless "evil dryad" ambience in the trenches) are left out.')
w('')
w('## 1. Where the opening is')
w('')
w('The game starts in the tutorial: **a0_01_01 Western Greilyn Beach** (a start group "Beginning of Tutorial": no monsters, only soldiers and')
w('a scripted landing), then **a0_01_02 the arena** (a forced fight), **a0_01_04 the trenches** (a battlefield) and **a0_01_05 the cave**')
w('(the tutorial\'s last fight, ending in a boss). The main campaign replays the same places as `a1_01_*` (tutmedic, tutcommand, trenches, cave)')
w('with different packs, then opens the jungle at **a1_02_01 jnglight**.')
w('')
w('## 2. The monsters, as the templates define them (normal difficulty)')
w('')
w('| Monster | Role / tier | Level | Life | XP it pays | XP by the usual formula | Notes |')
w('|---|---|---|---|---|---|---|')
roster = [('bracken_defender', 'melee, trivial'), ('bracken_defender_jump', 'melee, trivial'), ('forest_golem', 'ranged, weak'),
          ('mystic_protector', 'magic, weak'), ('ketril', 'melee, normal (tank)'), ('ketril_boss', 'melee, miniboss')]
notes = {'bracken_defender': 'sight 15 m, 2 s swing', 'bracken_defender_jump': 'sight 20 m; leaps up to 6 m onto you', 'forest_golem': 'sight 15 m; ranged attacker',
         'mystic_protector': 'sight 15 m; magic', 'ketril': 'life is a hand-set 166, not the formula', 'ketril_boss': 'life hand-set 373; power level 37.5'}
for n, role in roster:
    s = A.stats(n)
    f = formula_xp(s['tier'], s['level'])
    w('| %s | %s | %d | %.1f | %d | %s (%d%%) | %s |' % (n, role, s['level'], s['life'], s['xp'], '%.0f' % f if f else '?', round(100 * s['xp'] / f) if f else 0, notes[n]))
w('')
w('**The tutorial pays about 55% of the usual XP.** Every opening monster\'s `experience_value` is a hand-set number (14, 30, 35, 40, 152), each')
w('about 0.55 of what the level/tier formula gives. That slows levelling through the tutorial. Monsters from the jungle on use the formula.')
w('')
w('## 3. Enemy level against the hero\'s level')
w('')
w('| Stretch | Monster levels | Hero level on arriving | Gap |')
w('|---|---|---|---|')
w('| Arena | 1 | 0 | +1 |')
w('| Trenches | 1 to 3 | 0 (finishes at 3) | +1 to +3 |')
w('| Cave | 1 to 3 (boss 3) | 3 | 0 to -2 |')
w('| Jungle, first region (jnglight) | 3 to 5 (one boar-beast at 7) | 3 | 0 to +2 (+4 for the boar) |')
w('')
w('Fighting every fightable monster in the tutorial, in order, takes the hero to **level 3** (the same level as your Half-Giant screenshot):')
w('')
w('| Region | Fightable monsters | XP | Hero level after |')
w('|---|---|---|---|')
cum = 0
for r, label in (('a0_01_02_tutarena', 'Arena'), ('a0_01_04_tuttrenches', 'Trenches'), ('a0_01_05_tutcav', 'Cave')):
    it = [i for i in A.hostile_items(r) if fightable(i['tpl'])]
    xp = sum(A.stats(i['tpl'])['xp'] for i in it)
    cum += xp
    w('| %s | %d | %d (total %d) | %d |' % (label, len(it), xp, cum, hero_level(cum)))
w('')
w('The gap never reaches DS2\'s 4-level XP penalty zone in the opening; monsters stand at or just above the hero.')
w('')
w('## 4. Group composition')
w('')
w('Groups are not rolled. Each monster is a placed actor, or a generator that spawns exactly one (a generator with no settings spawns one child).')
w('There are no "packs" as a data object: a pack is whatever stands in the same stretch of the map. Grouping the monsters by the map nodes they')
w('stand in (nodes are DS2\'s ~10 m building blocks) gives these patterns:')
w('')
for r, label in (('a0_01_02_tutarena', 'Arena (forced fight)'), ('a0_01_04_tuttrenches', 'Trenches'), ('a0_01_05_tutcav', 'Cave')):
    it = [i for i in A.hostile_items(r) if fightable(i['tpl'])]
    c = collections.Counter(i['tpl'] for i in it)
    n = len(it)
    nodes, adj = A.node_graph(r)
    per_node = collections.Counter(i['node'] for i in it)
    sizes = collections.Counter(per_node.values())
    w('**%s**: %d monsters over %d map nodes (%.2f per node). Mix: %s.' % (label, n, len(nodes), n / len(nodes),
      ', '.join('%d%% %s' % (round(100 * v / n), k.replace('bracken_defender', 'defender')) for k, v in c.most_common())))
    if len(per_node) > 1:
        w('Monsters sharing one node: ' + ', '.join('%d node(s) hold %d' % (cnt, size) for size, cnt in sorted(sizes.items())) + '.')
    w('')
w('What the arrangement shows:')
w('')
w('* **The arena is one scripted fight**: 10 level-1 Bracken Defenders (5 standing, then 2 and 3 spawned), fought beside two allied mercenaries; 140 XP in all.')
w('* **The trenches are a battlefield, not a corridor of packs.** 88 fightable monsters over about 1,300 nodes, mostly melee defenders (62%, two fifths of them')
w('  "jump" defenders), with golems (16%), protectors (12%) and a few ketrils (9%). The soldiers and dryad skirmishers staged around you are scenery (some invincible, some')
w('  spawned without end) and are not counted. The real enemies come in loose clusters of 3 to 12 that mix kinds: for example 4 defenders + 2 golems')
w('  + 1 protector, or 5 defenders + 4 golems, or 4 ketrils + 4 defenders + 3 protectors + 1 jumper.')
w('* **Jump defenders arrive in ambush bunches**: 5 stand in one node (two such bunches in the trenches), and in tutcommand there are bunches of 5, 8 and 4. They leap up to 6 m when they see you.')
w('* **Reinforcement streams**: two generators in the trenches feed 10 more defenders into one spot, 5 each but only 2 alive per generator at a time, so the fight there is a steady 4 at once until all 10 are dead.')
w('* **Ranged and magic monsters are usually mixed in with melee ones, but not always**: there are spots held by a lone protector, by three protectors, or by three protectors with three golems and no melee at all.')
w('* **The cave is a long path, not a room**: 42 monsters standing in 27 separate nodes along a path about 16 doors long, in small mixed packs of 1 to 4 per node')
w('  (a defender and a ketril, two ketrils, a golem and a defender). The Ketril boss stands in the last node with a Mystic Protector, and the next nodes back hold a')
w('  protector and a defender: the boss has an escort.')
w('* **Ketrils are the tutorial\'s elites**: 166 life against a defender\'s 7.6, placed 1 to 3 at a time, then 14 of them through the cave, one boss at the end.')
w('')
w('### The first real zone (a1_02_01 jnglight): 38 monsters, levels 3 to 7')
w('')
w('| Group (by node) | Make-up | Levels |')
w('|---|---|---|')
w('| Haku camp | 3 slayers + 1 shaman | 3 and 4 |')
w('| Morden outpost | 2 thugs + archer leader + trainee | 5 |')
w('| Slayer ambush | 2 camouflaged slayers (jump) | 3 |')
w('| Hunter line | 4 hunters (ranged), and a separate pair of 2 | 4 |')
w('| Slayer + hunter bunch | 2 slayers + 1 hunter (jump) | 3 and 4 |')
w('| Haku drum circle | 3 slayers + 1 drummer | 3 and 5 |')
w('| Guard post | 2 outpost thugs, then 1 outpost soldier | 3 |')
w('| Boar den | 4 hunters + 1 boar-beast (strong, life 210) | 4 and 7 |')
w('')
w('Slayers (melee, trivial, life 15) are the fodder; hunters (ranged, weak), shamans and drummers (normal, 56 to 112 life) are the supports; a')
w('boar-beast (strong) is the one big thing. Groups are 1 to 5, always mixed melee with ranged or support.')
w('')
w('## 5. Against Curse\'s opening road (`RoadEncounterRoster`)')
w('')
w('| | DS2 opening | Curse opening road |')
w('|---|---|---|')
w('| Monsters in the opening | 140 fightable in the three tutorial fights | 61 over the whole road (cap 64) |')
w('| Monster levels | 1 to 3 in the tutorial, 3 to 7 in the first jungle region | 1 to 6 |')
w('| Group size | 1 to 4 mixed per spot, bunches of 4 to 8 jumpers, 10-strong reinforcement streams | 2 to 3, mostly zombies |')
w('| Mix | melee trivial 61%, ranged 12%, magic 11%, tank or elite 16% | mostly zombies, with ghouls and rock throwers added from level 2, then brutes and a warden |')
w('| XP per level-1 trivial kill | 14 (hand-set, about 0.55 of formula) | 25 (formula) |')
w('| Ambushes | jump defenders in bunches | none |')
w('| Boss | Ketril boss (level 3, life 373, XP 152) with a protector escort | warden (level 6) at the end of the road |')
w('')
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../docs/ds2-opening-monsters.md'), 'w', encoding='utf-8', newline='\n').write('\n'.join(L) + '\n')
print('\n'.join(L))
