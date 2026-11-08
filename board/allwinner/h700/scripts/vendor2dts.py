#!/usr/bin/env python3
"""Lift nodes out of a decompiled vendor (4.9 sunxi) DTS into label-based
DTS source that can sit on top of the 5.4 sun50iw9.dtsi.

Numeric phandles become labels.  Pin nodes referenced by anything we copy are
collected and emitted under &pio / &r_pio, keeping their legacy allwinner,*
properties (the vendor U-Boot only understands those; the 5.4 kernel falls back
to them).  Functions the 5.4 pinctrl tables do not have (io_disabled,
*_suspend) get a generic `function = "gpio_in"` that the kernel prefers.
"""
import re, sys

VENDOR_TO_DTSI = {}          # vendor phandle -> dtsi label
KNOWN_FUNCS = set()


class Node:
    def __init__(self, name, parent, start):
        self.name, self.parent, self.start = name, parent, start
        self.props = []      # (name, raw value or None)
        self.children = []
        self.phandle = None

    @property
    def path(self):
        p = []
        n = self
        while n is not None and n.parent is not None:
            p.append(n.name)
            n = n.parent
        return '/' + '/'.join(reversed(p))


def parse(text):
    root = Node('', None, 0)
    cur = root
    stack = []
    buf = ''
    for line in text.split('\n'):
        s = line.strip()
        if not s or s.startswith('/dts-v1/') or s.startswith('//'):
            continue
        if buf:
            buf += ' ' + s
            if not buf.endswith(';'):
                continue
            s, buf = buf, ''
        m = re.match(r'^(?:[\w-]+:\s*)?([^\s=]+) \{$', s)
        if m:
            if m.group(1) == '/' and cur is root:
                stack.append(cur)
                continue
            n = Node(m.group(1), cur, 0)
            cur.children.append(n)
            stack.append(cur)
            cur = n
            continue
        if s == '};':
            cur = stack.pop()
            continue
        if not s.endswith(';'):
            buf = s
            continue
        s = s[:-1]
        if '=' in s:
            k, v = s.split('=', 1)
            k, v = k.strip(), v.strip()
        else:
            k, v = s, None
        if k == 'linux,phandle':
            continue
        if k == 'phandle':
            cur.phandle = int(v.strip('<>'), 16)
            continue
        cur.props.append((k, v))
    return root


def walk(n):
    yield n
    for c in n.children:
        yield from walk(c)


def find(root, path):
    for n in walk(root):
        if n.path == path:
            return n
    raise KeyError(path)


# ---------------------------------------------------------------- phandles
ALL_CELLS = re.compile(r'^(clocks|assigned-clocks|assigned-clock-parents|pinctrl-\d+|'
                       r'.*-supply|.*_supply|param|interrupt-parent|cpu-idle-states|'
                       r'operating-points-v2|nvmem-cells|iommus|pwms)$')


def cells(v):
    return v.strip('<>').split()


class Emitter:
    def __init__(self, root, pio_ph, rpio_ph):
        self.root = root
        self.by_ph = {n.phandle: n for n in walk(root) if n.phandle is not None}
        self.pio_ph, self.rpio_ph = pio_ph, rpio_ph
        self.labels = {}         # phandle -> label
        self.used_labels = set()
        self.need_pins = {}      # phandle -> node
        self.emitted = set()     # phandles emitted as nodes

    def label_for(self, ph):
        if ph in VENDOR_TO_DTSI:
            return VENDOR_TO_DTSI[ph]
        if ph in self.labels:
            return self.labels[ph]
        n = self.by_ph[ph]
        base = re.sub(r'[^A-Za-z0-9_]', '_', n.name)
        if n.parent is not None and n.parent.name == 'clocks':
            base = 'clk_' + base
        elif n.parent is not None and n.parent.name.startswith('pinctrl@'):
            base = 'v_' + base
        elif not base.startswith('v_'):
            base = 'v_' + base
        lab, i = base, 1
        while lab in self.used_labels:
            i += 1
            lab = '%s_%d' % (base, i)
        self.used_labels.add(lab)
        self.labels[ph] = lab
        if n.parent is not None and n.parent.name.startswith('pinctrl@'):
            self.need_pins[ph] = n
        return lab

    def ref(self, ph):
        return '&' + self.label_for(ph)

    def conv_value(self, k, v):
        if v is None or not v.startswith('<'):
            return v
        # a value may be several <..> groups
        groups = re.findall(r'<([^>]*)>', v)
        if not groups:
            return v
        out = []
        for g in groups:
            c = g.split()
            if ALL_CELLS.match(k):
                c = [self.ref(int(x, 16)) if int(x, 16) in self.by_ph or int(x, 16) in VENDOR_TO_DTSI else x
                     for x in c]
            elif len(c) in (4, 7) and int(c[0], 16) in (self.pio_ph, self.rpio_ph):
                # sys_config style gpio: <phandle port pin mul pull drv data>
                c = [self.ref(int(c[0], 16))] + c[1:]
            out.append('<' + ' '.join(c) + '>')
        return ', '.join(out)

    def emit(self, n, ind, rename=None, drop=(), extra=(), label=True, skip_children=()):
        t = '\t' * ind
        name = rename or n.name
        lab = ''
        if label and n.phandle is not None:
            lab = self.label_for(n.phandle) + ': '
            self.emitted.add(n.phandle)
        lines = ['%s%s%s {' % (t, lab, name)]
        for k, v in n.props:
            if k in drop:
                continue
            v = self.conv_value(k, v)
            lines.append('%s\t%s;' % (t, k) if v is None else '%s\t%s = %s;' % (t, k, v))
        for e in extra:
            lines.append('%s\t%s;' % (t, e))
        for c in n.children:
            if c.name in skip_children:
                continue
            lines.append('')
            lines.append(self.emit(c, ind + 1))
        lines.append('%s};' % t)
        return '\n'.join(lines)

    def emit_pins(self, ind):
        """Emit every referenced pin node, repeating until the closure is done."""
        out = {'pio': [], 'r_pio': []}
        done = set()
        while True:
            todo = [ph for ph in self.need_pins if ph not in done]
            if not todo:
                break
            for ph in todo:
                done.add(ph)
                n = self.need_pins[ph]
                which = 'r_pio' if n.parent.phandle == self.rpio_ph else 'pio'
                props = dict(n.props)
                fn = props.get('allwinner,function', '""').strip('"')
                extra = []
                # 0xffffffff means "leave the pad as it is" in sys_config, but
                # the kernel parses it as a value and computes a drive strength
                # of 0, which makes the whole pin state fail to apply.  The
                # generic property wins over allwinner,drive in the kernel and
                # is ignored by U-Boot.
                if props.get('allwinner,drive') == '<0xffffffff>':
                    extra.append('drive-strength = <10>')
                if fn not in KNOWN_FUNCS[which]:
                    extra.append('function = "gpio_in"')
                    sys.stderr.write('pin %s: function %s not in 5.4 tables -> gpio_in for the kernel\n'
                                     % (n.path, fn))
                txt = self.emit(n, ind, rename=self.label_for(ph).replace('_', '-'), extra=extra)
                out[which].append(txt)
        return out


def known_funcs(path):
    src = open(path).read()
    return set(re.findall(r'SUNXI_FUNCTION\([^,]+,\s*"([^"]+)"', src)) | {'gpio_in', 'gpio_out'}


if __name__ == '__main__':
    pass
