#!/usr/bin/env python3
"""split-dts.py <dts dir>

Move what every sun50i-h700-anbernic-*.dts has in common into
sun50i-h700-anbernic.dtsi and leave only the differences in each .dts."""
import glob
import os
import re
import sys

DTSI = 'sun50i-h700-anbernic.dtsi'


class Node:
    def __init__(self, head, comment):
        self.head, self.comment, self.tail = head, comment, '};'
        self.items = []          # (key, Node or statement text, comment)


def parse(lines):
    """Statements and nodes per block; comments stick to the next item."""
    root = Node(None, '')
    stack, comment, stmt, seen = [root], [], [], [{}]
    i = 0
    while i < len(lines):
        line = lines[i]
        # trailing /* PA6 */ comments stay on their line
        s = re.sub(r'\s*/\*[^*]*\*/$', '', line.strip()) if not line.strip().startswith('/*') else line.strip()
        i += 1
        if stmt:
            stmt.append(line)
            if s.endswith(';'):
                text = '\n'.join(stmt)
                add(stack[-1], seen[-1], stmt_key(text), text, comment)
                stmt, comment = [], []
            continue
        if not s:
            continue
        if s.startswith('/*'):
            block = [line]
            while '*/' not in lines[i - 1]:
                block.append(lines[i])
                i += 1
            comment.append('\n'.join(block))
        elif s.startswith('//'):
            comment.append(line)
        elif s.endswith('{'):
            n = Node(line, '\n'.join(comment))
            add(stack[-1], seen[-1], s, n, comment)
            stack.append(n)
            seen.append({})
            comment = []
        elif s == '};':
            stack.pop().tail = line
            seen.pop()
        elif s.endswith(';') or s.startswith('#'):
            add(stack[-1], seen[-1], stmt_key(line), line, comment)
            comment = []
        else:
            stmt = [line]
    assert len(stack) == 1 and not stmt
    return root


def add(parent, seen, key, val, comment):
    # repeated keys (two "/ {" blocks) stay apart
    seen[key] = seen.get(key, 0) + 1
    if seen[key] > 1:
        key = '%s#%d' % (key, seen[key])
    parent.items.append((key, val, '\n'.join(comment)))


def stmt_key(text):
    s = text.strip()
    m = re.match(r'(/delete-property/\s+\S+|[^\s=;]+)', s)
    return s if s.startswith(('#', '/delete-node/', '/dts-v1/')) else m.group(1)


def common(nodes):
    """Items every node has identically; nodes recurse."""
    base = nodes[0]
    out = Node(base.head, base.comment)
    out.tail = base.tail
    maps = [dict((k, (v, c)) for k, v, c in n.items) for n in nodes]
    keep = shared_children(nodes, maps)
    for key, val, com in base.items:
        if not all(key in m for m in maps):
            continue
        if isinstance(val, Node) and key not in keep:
            continue
        vals = [m[key] for m in maps]
        if isinstance(val, Node):
            if not all(isinstance(v, Node) and v.head == val.head for v, _ in vals):
                continue
            sub = common([v for v, _ in vals])
            if sub.items:
                same = all(c == com for _, c in vals)
                out.items.append((key, sub, com if same else None))
        elif all(v == val and c == com for v, c in vals):
            out.items.append((key, val, com))
    return out


def shared_children(nodes, maps):
    """Child nodes the dtsi may hold without changing any board's node order:
    a common prefix, since a board's own children land after the dtsi's."""
    seqs = [[k for k, v, _ in n.items if isinstance(v, Node)] for n in nodes]
    cand = [k for k in seqs[0]
            if all(k in m and isinstance(m[k][0], Node) and m[k][0].head == maps[0][k][0].head
                   for m in maps)]
    for seq in seqs:
        n = 0
        while n < len(cand) and n < len(seq) and seq[n] == cand[n]:
            n += 1
        cand = cand[:n]
    return set(cand)


def residue(node, com):
    """What node has beyond com (a common() result, or None)."""
    out = Node(node.head, node.comment)
    out.tail = node.tail
    cmap = dict((k, (v, c)) for k, v, c in com.items) if com else {}
    for key, val, c in node.items:
        if key not in cmap:
            out.items.append((key, val, c))
        elif isinstance(val, Node):
            sub = residue(val, cmap[key][0])
            # the comment stays here unless the dtsi took it
            if sub.items:
                out.items.append((key, sub, c if cmap[key][1] is None else ''))
    return out


def emit(node, depth, out):
    for i, (key, val, c) in enumerate(node.items):
        if i and (depth == 0 or isinstance(val, Node)) and \
                not (key.startswith('#') and node.items[i - 1][0].startswith('#')):
            out.append('')
        if c:
            out.append(c)
        if isinstance(val, Node):
            out.append(val.head)
            emit(val, depth + 1, out)
            out.append(val.tail)
        else:
            out.append(val)


def render(node):
    out = []
    emit(node, 0, out)
    return '\n'.join(out) + '\n'


dts_dir = sys.argv[1]
files = sorted(glob.glob(os.path.join(dts_dir, 'sun50i-h700-anbernic-*.dts')))
# the plus first: its order and comments win in the dtsi
files.sort(key=lambda f: not f.endswith('-rg35xx-plus.dts'))
trees = [parse(open(f).read().split('\n')) for f in files]
for t in trees:
    # each keeps its own header comment and /dts-v1/
    k, v, c = t.items[0]
    assert k == '/dts-v1/;', k
    t.header = c
    t.items = t.items[1:]
com = common(trees)
open(os.path.join(dts_dir, DTSI), 'w').write(
    '// SPDX-License-Identifier: (GPL-2.0+ OR MIT)\n'
    '/*\n * What every H700 board tree shares, split out of the generated trees\n'
    ' * by board/allwinner/h700/scripts/split-dts.py.\n */\n\n' + render(com))
for f, t in zip(files, trees):
    r = residue(t, com)
    open(f, 'w').write('%s\n\n/dts-v1/;\n\n#include "%s"\n\n%s' % (t.header, DTSI, render(r)))
    print('wrote', f)
