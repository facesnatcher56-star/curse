"""A small parser for DS2 .gas files and a template resolver.
parse_gas(text) -> list of (kind, name, body) where body is nested dict: section -> dict | key -> value string.
"""
import os
import re

HEADER = re.compile(r'\[(t:[^\],]+(?:,n:[^\]]+)?|[^\]\[]+)\]')


def _strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    out = []
    for line in text.split('\n'):
        in_str = False
        res = []
        i = 0
        while i < len(line):
            c = line[i]
            if c == '"':
                in_str = not in_str
            if not in_str and line.startswith('//', i):
                break
            res.append(c)
            i += 1
        out.append(''.join(res))
    return '\n'.join(out)


def parse_block(tokens, i):
    """tokens: list of lines; returns (dict, next index) after the closing brace."""
    d = {}
    while i < len(tokens):
        line = tokens[i].strip()
        i += 1
        if not line:
            continue
        if line == '}':
            return d, i
        if line.startswith('['):
            name = line.strip()
            # the opening brace is on this line or the next
            if i < len(tokens) and tokens[i].strip() == '{':
                i += 1
            elif line.endswith('{'):
                name = name[:-1].strip()
            if name.endswith('{'):
                name = name[:-1].strip()
            sub, i = parse_block(tokens, i)
            key = name.strip('[]')
            if key in d and isinstance(d[key], dict):
                # repeated section (e.g. [*]): keep a list under key+'#'
                d.setdefault(key + '#', []).append(sub)
            else:
                d[key] = sub
            continue
        if line == '{':
            continue
        m = re.match(r'(?:[a-z]\s+)?([A-Za-z0-9_\*\.:]+)\s*=\s*(.*?);?\s*$', line)
        if m:
            key = m.group(1)
            val = m.group(2).rstrip(';').strip()
            # multi-line expressions: continue until a line ends with ';'
            while not line.rstrip().endswith(';') and i < len(tokens) and not tokens[i].strip().startswith('[') and tokens[i].strip() not in ('}', '{'):
                line = tokens[i].strip()
                i += 1
                val += ' ' + line.rstrip(';').strip()
            if key in d:
                d.setdefault(key + '#', []).append(val)
            else:
                d[key] = val
    return d, i


def _split_tokens(text):
    out = []
    in_str = False
    for c in text:
        if c == '"':
            in_str = not in_str
        if not in_str and c in '{}':
            out.append('\n' + c + '\n')
        elif not in_str and c == ';':
            out.append(';\n')
        else:
            out.append(c)
    return ''.join(out)


def parse_gas(text):
    text = _split_tokens(_strip_comments(text))
    lines = text.split('\n')
    out = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        i += 1
        m = re.match(r'\[t:([^,\]]+)(?:,n:([^\]]+))?\]', line)
        if m:
            if i < len(lines) and lines[i].strip() == '{':
                i += 1
            body, i = parse_block(lines, i)
            out.append((m.group(1), m.group(2), body))
    return out


class Templates:
    def __init__(self, folder):
        self.t = {}
        for fn in os.listdir(folder):
            if not fn.endswith('.gas'):
                continue
            try:
                text = open(os.path.join(folder, fn), encoding='latin1').read()
            except OSError:
                continue
            for kind, name, body in parse_gas(text):
                if kind == 'template' and name:
                    self.t[name] = body
                    self.t[name]['_file'] = fn

    def chain(self, name):
        out = []
        seen = set()
        while name and name in self.t and name not in seen:
            seen.add(name)
            out.append(name)
            spec = self.t[name].get('specializes')
            name = spec.strip().strip('"') if spec else None
        return out  # most specific first

    def get(self, name, section, key, default=None):
        for n in self.chain(name):
            sec = self.t[n].get(section)
            if isinstance(sec, dict) and key in sec:
                return sec[key]
        return default

    def get_nested(self, name, path, default=None):
        """path like ('actor','skills','monster_level')"""
        for n in self.chain(name):
            cur = self.t[n]
            ok = True
            for p in path:
                if isinstance(cur, dict) and p in cur:
                    cur = cur[p]
                else:
                    ok = False
                    break
            if ok and not isinstance(cur, dict):
                return cur
        return default
