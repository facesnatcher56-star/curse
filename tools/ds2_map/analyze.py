"""DS2 opening-monster research tools (see docs/ds2-opening-monsters.md).
Steps:
  1. python tools/ds2_dump.py extract OUT/ds2all <names...>   (or extract every .gas of Logic.ds2res into one folder) -> set DS2_LOGIC_DIR
  2. python tools/ds2_map/tank_tree.py "<Steam>/Dungeon Siege 2/Maps/World.ds2map" OUT/map regions/a0_ regions/a1_01_ ds2_world/info/
     (keeps folder paths; the regions then sit in OUT/map/world/maps/ds2_world/regions -> set DS2_REGIONS_DIR)
  3. python tools/ds2_map/analyze.py a0_01_05_tutcav ...        (counts), or import analyze and call encounter_report(region)
  4. python tools/ds2_map/make_opening_doc.py                   (rewrites docs/ds2-opening-monsters.md)
"""
import os, re, sys, math, collections
import gas, parse_objs as P

LOGIC_DIR = os.environ.get('DS2_LOGIC_DIR', os.environ.get('TEMP', '.') + '/ds2all')   # every .gas from Logic.ds2res in one folder
T = gas.Templates(LOGIC_DIR)
BASE = os.environ.get('DS2_REGIONS_DIR', 'map/world/maps/ds2_world/regions')   # the regions extracted by tank_tree.py


def ev(expr):
    if expr is None:
        return None
    e = expr.replace('#is_normal', '1').replace('#is_veteran', '0').replace('#is_elite', '0')
    e = re.sub(r'#\w+', '0', e)
    e = e.replace('**', '^')
    try:
        return eval(e.replace('^', '**'), {"__builtins__": {}}, {})
    except Exception:
        return None


def stats(tpl):
    """Effective stats of a template at normal difficulty."""
    if tpl not in T.t:
        return None
    ch = T.chain(tpl)
    level = ev(T.get_nested(tpl, ('actor', 'skills', 'monster_level')))
    xp_expr = T.get_nested(tpl, ('aspect', 'experience_value'))
    life_expr = T.get_nested(tpl, ('aspect', 'life'))
    def with_level(expr):
        if expr is None:
            return None
        e = expr.replace('#monster_level', str(level if level is not None else 0))
        return ev(e) if '?' not in e else ev_ternary(e)
    return {
        'chain': ch, 'level': level,
        'xp': with_level(xp_expr), 'life': with_level(life_expr),
        'power': T.get_nested(tpl, ('actor', 'power_level')),
        'sight': T.get_nested(tpl, ('mind', 'sight_range')),
        'screen': T.get_nested(tpl, ('common', 'screen_name')),
        'tier': next((c for c in ch if c.startswith('base_actor_evil_')), ''),
        'evil': 'actor_evil' in ch,
        'good': 'actor_good' in ch,
    }


def ev_ternary(e):
    m = re.match(r'\s*\((.*?)\)\s*\?\s*(.*?)\s*:\s*(.*)$', e)
    if not m:
        return None
    cond = m.group(1)
    try:
        ok = eval(cond.replace('**', '**'), {"__builtins__": {}}, {})
    except Exception:
        return None
    return ev(m.group(2) if ok else m.group(3))


def abs_positions(region):
    p = f'{BASE}/{region}/editor/abs_positions.gas'
    pos = {}
    if not os.path.exists(p):
        return pos
    txt = open(p, encoding='latin1').read()
    for m in re.finditer(r'\[(0x[0-9a-fA-F]+)\]\s*\{\s*f x = ([-\d.]+);\s*f y = ([-\d.]+);\s*f z = ([-\d.]+);', txt):
        pos[int(m.group(1), 16)] = (float(m.group(2)), float(m.group(3)), float(m.group(4)))
    return pos


def placement(body):
    m = re.search(r'p position = ([-\d.e+]+),([-\d.e+]+),([-\d.e+]+),(0x[0-9a-fA-F]+)', body)
    if not m:
        return None
    return (float(m.group(1)), float(m.group(2)), float(m.group(3)), int(m.group(4), 16))


def world_pos(pl, absmap):
    if pl is None:
        return None
    node = absmap.get(pl[3])
    if node is None:
        return (pl[0], pl[2], pl[3])
    return (node[0] + pl[0], node[2] + pl[2], pl[3])


def region_objects(region):
    absmap = abs_positions(region)
    out = []
    for fn in ('actor.gas', 'generator.gas'):
        p = f'{BASE}/{region}/objects/{fn}'
        if not os.path.exists(p):
            continue
        for tpl, scid, body in P.parse(p):
            pl = placement(body)
            wp = world_pos(pl, absmap)
            rec = {'tpl': tpl, 'scid': scid, 'file': fn, 'pos': wp, 'node': pl[3] if pl else None, 'body': body}
            if fn == 'generator.gas':
                child = re.search(r'child_template_name = "([^"]+)"', body)
                rec['child'] = child.group(1) if child else None
                for key in ('num_children_incubating', 'max_alive_children', 'spawn_period', 'initial_command'):
                    mm = re.search(key + r' = ([^;]+);', body)
                    rec[key] = mm.group(1).strip() if mm else None
            out.append(rec)
    return out


def clusters(items, radius):
    """single-linkage clusters of items having a 'pos' (x, z, node)."""
    items = [i for i in items if i['pos'] is not None]
    groups = []
    for it in items:
        merged = None
        for g in groups:
            if any(math.hypot(it['pos'][0] - o['pos'][0], it['pos'][1] - o['pos'][1]) <= radius for o in g):
                if merged is None:
                    g.append(it)
                    merged = g
                else:
                    merged.extend(g)
                    g.clear()
        groups = [g for g in groups if g]
        if merged is None:
            groups.append([it])
    return groups


def monster_kind(tpl):
    s = stats(tpl)
    return s is not None and s['evil']


if __name__ == '__main__':
    for region in sys.argv[1:]:
        objs = region_objects(region)
        actors = [o for o in objs if o['file'] == 'actor.gas']
        gens = [o for o in objs if o['file'] == 'generator.gas']
        print('=' * 90)
        print(region, 'actors', len(actors), 'generators', len(gens))
        # hostile placed actors
        hostile = [o for o in actors if monster_kind(o['tpl'])]
        counts = collections.Counter(o['tpl'] for o in hostile)
        print(' placed hostile actors:', dict(counts))
        gcounts = collections.Counter((g['child'], g['num_children_incubating'], g['max_alive_children'], g['spawn_period']) for g in gens if g['child'] and monster_kind(g['child']))
        print(' monster generators (child, children, max alive, period):')
        for k, n in gcounts.most_common():
            print('     %2d x %s' % (n, k))


def cluster_report(region, radius=9.0):
    objs = region_objects(region)
    items = []
    for o in objs:
        if o['file'] == 'actor.gas' and monster_kind(o['tpl']):
            items.append({'tpl': o['tpl'], 'pos': o['pos'], 'src': 'placed'})
        elif o['file'] == 'generator.gas' and o.get('child') and monster_kind(o['child']):
            n = o.get('num_children_incubating')
            items.append({'tpl': o['child'], 'pos': o['pos'], 'src': 'gen(%s,max%s)' % (n, o.get('max_alive_children'))})
    gs = clusters(items, radius)
    gs.sort(key=lambda g: (sum(i['pos'][0] for i in g) / len(g)))
    print('=' * 100)
    print(region, 'clusters:', len(gs), 'radius', radius)
    tot = collections.Counter()
    for k, g in enumerate(gs, 1):
        cx = sum(i['pos'][0] for i in g) / len(g)
        cz = sum(i['pos'][1] for i in g) / len(g)
        comp = collections.Counter((i['tpl'], i['src'].split('(')[0]) for i in g)
        life = xp = 0.0
        levels = set()
        for i in g:
            s = stats(i['tpl'])
            life += s['life'] or 0
            xp += s['xp'] or 0
            levels.add(s['level'])
        for i in g:
            tot[i['tpl']] += 1
        print(' #%02d (%6.1f,%6.1f) n=%2d lvls=%s life=%6.1f xp=%5.0f  %s' % (k, cx, cz, len(g), sorted(levels), life, xp,
              ', '.join('%dx %s%s' % (n, t, '[gen]' if s == 'gen' else '') for (t, s), n in comp.most_common())))
    print(' totals:', dict(tot))


def node_graph(region):
    p = f'{BASE}/{region}/terrain_nodes/nodes.gas'
    txt = open(p, encoding='latin1').read()
    adj = collections.defaultdict(set)
    nodes = set()
    for m in re.finditer(r'\[t:snode,n:(0x[0-9a-fA-F]+)\]', txt):
        nodes.add(int(m.group(1), 16))
    # each snode block: find its doors
    parts = re.split(r'(?=\[t:snode,n:0x)', txt)
    for part in parts:
        m = re.match(r'\[t:snode,n:(0x[0-9a-fA-F]+)\]', part)
        if not m:
            continue
        g = int(m.group(1), 16)
        for d in re.finditer(r'farguid = (0x[0-9a-fA-F]+);', part):
            f = int(d.group(1), 16)
            adj[g].add(f)
            adj[f].add(g)
    return nodes, adj


def bfs(adj, start, limit=999):
    dist = {start: 0}
    q = collections.deque([start])
    while q:
        u = q.popleft()
        for v in adj[u]:
            if v not in dist:
                dist[v] = dist[u] + 1
                q.append(v)
    return dist


def hostile_items(region):
    items = []
    for o in region_objects(region):
        if o['file'] == 'actor.gas' and monster_kind(o['tpl']):
            items.append({'tpl': o['tpl'], 'node': o['node'], 'src': 'placed'})
        elif o['file'] == 'generator.gas' and o.get('child') and monster_kind(o['child']):
            n = int(o['num_children_incubating'] or 1)
            for _ in range(min(n, 5)):
                items.append({'tpl': o['child'], 'node': o['node'], 'src': 'gen'})
    return items


def encounter_report(region, entry=None, merge_hops=2):
    nodes, adj = node_graph(region)
    items = hostile_items(region)
    outside = sorted(n for n in nodes if any(x not in nodes for x in adj[n]))
    if entry is None:
        entry = outside[0] if outside else next(iter(nodes))
    dist = bfs(adj, entry)
    by_node = collections.defaultdict(list)
    for it in items:
        by_node[it['node']].append(it)
    # merge nearby nodes
    comp = []
    seen = set()
    for n in sorted(by_node, key=lambda x: dist.get(x, 999)):
        if n in seen:
            continue
        cluster = [n]
        seen.add(n)
        stack = [n]
        while stack:
            u = stack.pop()
            du = bfs(adj, u)
            for v in by_node:
                if v not in seen and du.get(v, 999) <= merge_hops:
                    seen.add(v)
                    cluster.append(v)
                    stack.append(v)
        comp.append(cluster)
    print('=' * 100)
    print(region, 'entry node', hex(entry), '| outside-linking nodes', [hex(x) for x in outside][:6], '| nodes', len(nodes), '| hostile', len(items))
    comp.sort(key=lambda c: min(dist.get(n, 999) for n in c))
    tot_xp = 0
    for k, c in enumerate(comp, 1):
        its = [it for n in c for it in by_node[n]]
        hops = min(dist.get(n, 999) for n in c)
        cnt = collections.Counter(it['tpl'] for it in its)
        life = sum((stats(it['tpl'])['life'] or 0) for it in its)
        xp = sum((stats(it['tpl'])['xp'] or 0) for it in its)
        lv = sorted({stats(it['tpl'])['level'] for it in its})
        tot_xp += xp
        print(' group %02d  hops=%3d nodes=%2d n=%2d lvl=%s life=%7.1f xp=%5.0f  %s' % (k, hops, len(c), len(its), lv, life, xp,
              ', '.join('%dx %s' % (n, t) for t, n in cnt.most_common())))
    print(' region XP total (counting every placed + generated monster): %d' % tot_xp)
