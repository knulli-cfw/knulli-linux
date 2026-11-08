#!/usr/bin/env python3
"""gen-select-dts.py <dts dir> <panels.conf>

Append one "knulli,panel-<name>" node per line of panels.conf to the
first-boot device tree (sun50i-h700-anbernic-select.dts): the lcd0 block of
the board that ships that panel, with that single init table and no id pin.
The disp2 driver reads lcd0 from that node when lcd_panel selects it."""
import os
import re
import sys

dts_dir, conf = sys.argv[1:3]
SOURCE = {  # panel table -> the per-device DTS whose lcd0 timings it needs
    'rg35xx-plus': 'rg35xx-plus', 'rg35xx-h': 'rg35xx-h', 'rg35xx-sp': 'rg35xx-sp',
    'rg40xx': 'rg40xx-h', 'rg34xx': 'rg34xx', 'rg34xx-sp': 'rg34xx-sp',
    'rgcubexx': 'rg-cubexx', 'rg28xx': 'rg28xx',
}
DROP = ('lcd_panel_init', 'lcd_id_gpio', 'pinctrl-')

nodes = []
for line in open(conf):
    line = line.strip()
    if not line or line[0] == '#':
        continue
    panel = line.split('|')[0]
    src = SOURCE[re.sub(r'-(old|boe)$', '', panel)]
    text = open(os.path.join(dts_dir, 'sun50i-h700-anbernic-%s.dts' % src)).read()
    m = re.search(r'^&lcd0 \{\n(.*?)^\};', text, re.S | re.M)
    props = [l for l in m.group(1).splitlines()
             if l.strip() and not l.strip().startswith(('/*', '*')) and not l.strip().startswith(DROP)]
    props.append('\tlcd_panel_init = "%s";' % panel)
    nodes.append('\tpanel-%s {\n\t\tcompatible = "knulli,panel-%s";\n%s\n\t};' %
                 (panel, panel, '\n'.join('\t' + p for p in props)))

out = os.path.join(dts_dir, 'sun50i-h700-anbernic-select.dts')
s = open(out).read()
s += ('\n/* first boot: every panel, switched at runtime through\n'
      ' * /sys/class/disp/disp/attr/lcd_panel (see h700-panels.conf) */\n/ {\n%s\n};\n'
      % '\n\n'.join(nodes))
open(out, 'w').write(s)
print('wrote', out, len(nodes), 'panels')
