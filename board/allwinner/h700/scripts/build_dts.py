#!/usr/bin/env python3
"""build_dts.py <vendor.dts> <linux-5.4 tree> <model> <out.dts> [device]

<device> defaults to the vendor file name; the RG-SP has no vendor tree of
its own and is built from the rg34xx-sp one.

Generate a 5.4 board DTS for an Anbernic H700 from the vendor 4.9 DTS.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vendor2dts as v2d

vendor, ktree, model, out = sys.argv[1:5]
root = v2d.parse(open(vendor).read())

# panel init tables (board/allwinner/h700/panels) per vendor board: the first
# is the vendor's "old" panel, the second the "boe" one it selects when PE6
# reads low; single-table boards have no id gpio.  PULL: whether that board's
# vendor U-Boot enables the pull-up on PE6 before reading it (decoded from the
# binaries; rg35xx-sp and rg40xx read the bare pin, so it must be a strap
# there and a pull-up could override it).
PANELS = {
    'rg35xx-plus': ('rg35xx-plus-old', 'rg35xx-plus-boe'),
    'rg35xx-h': ('rg35xx-h-old', 'rg35xx-h-boe'),
    'rg35xx-pro': ('rg35xx-h-old', 'rg35xx-h-boe'),
    'rg35xx-sp': ('rg35xx-sp-old', 'rg35xx-sp-boe'),
    'rg34xx': ('rg34xx-old', 'rg34xx-boe'),
    'rg34xx-sp': ('rg34xx-sp-old', 'rg34xx-sp-boe'),
    'rg-sp': ('rg34xx-sp-old', 'rg34xx-sp-boe'),     # same vendor tree; its panel is the "old" one
    'rg40xx-h': ('rg40xx-old', 'rg40xx-boe'),
    'rg40xx-v': ('rg40xx-old', 'rg40xx-boe'),
    'rg28xx': ('rg28xx',),
    'rg-cubexx': ('rgcubexx',),
    'select': ('rg35xx-plus-old', 'rg35xx-plus-boe'),  # first boot: plus tree + every panel as a node
}
PULL = {'select': 1, 'rg35xx-plus': 1, 'rg35xx-h': 1, 'rg35xx-pro': 1, 'rg34xx': 1, 'rg34xx-sp': 1, 'rg-sp': 1,
        'rg35xx-sp': 0, 'rg40xx-h': 0, 'rg40xx-v': 0}
device = sys.argv[5] if len(sys.argv) > 5 else os.path.basename(vendor).rsplit('.', 1)[0]
panels = PANELS[device]
lcd_panel_init = '\tlcd_panel_init = %s;' % ', '.join('"%s"' % x for x in panels)
lcd_id_gpio = '\tlcd_id_gpio = <&pio 4 6 0 %d 0xffffffff 0>;' % PULL.get(device, 0) if len(panels) > 1 else ''
lcd_id_pull = PULL.get(device, 0)

PIO, RPIO = 0x4b, 0x10c
v2d.VENDOR_TO_DTSI.update({PIO: 'pio', RPIO: 'r_pio', 0x49: 'nmi_intc'})
v2d.KNOWN_FUNCS = {
    'pio': v2d.known_funcs(os.path.join(ktree, 'drivers/pinctrl/sunxi/pinctrl-sun50iw9.c')),
    'r_pio': v2d.known_funcs(os.path.join(ktree, 'drivers/pinctrl/sunxi/pinctrl-sun50iw9-r.c')),
}
em = v2d.Emitter(root, PIO, RPIO)
S = '/soc@03000000/'


def node(p):
    return v2d.find(root, p)


def props_of(p, drop=(), ind=1, rename=None):
    """Only the properties of a vendor node, converted, as override lines."""
    n = node(p)
    t = '\t' * ind
    lines = []
    for k, v in n.props:
        if k in drop:
            continue
        v = em.conv_value(k, v)
        if rename and k in rename:
            k = rename[k]
        lines.append('%s%s;' % (t, k) if v is None else '%s%s = %s;' % (t, k, v))
    return '\n'.join(lines)


def ph(p):
    return node(p).phandle


def ref(p):
    return em.ref(ph(p))


# ------------------------------------------------------------ vendor blocks
SYSCONFIG = ['product', 'platform', 'target', 'power_sply', 'charger0', 'card_boot',
             'ir_boot_recovery', 'key_boot_recovery', 'boot_init_gpio', 'pm_para',
             'card0_boot_para', 'card2_boot_para', 'twi_para', 'uart_para', 'jtag_para',
             'clock', 'dram_select_para'] + ['dram_para%d' % i for i in range(1, 16)] + ['secure']
sysconfig = '\n\n'.join(em.emit(node(S + n), 2) for n in SYSCONFIG
                        if any(c.name == n for c in node('/soc@03000000').children))

clocks = em.emit(node('/clocks'), 1)
standby = em.emit(node('/standby_param'), 1)
axpparam = em.emit(node('/axp2202-parameter'), 1)
memory = em.emit(node('/memory@40000000'), 1)

PMU = S + 'twi@0x07081400/pmu'
pmu = em.emit(node(PMU), 2)

DISP_DROP = ('compatible', 'reg', 'interrupts', 'clocks', 'iommus', 'status', 'boot_disp', 'fb_base')
disp_cfg = props_of(S + 'disp@01000000', drop=DISP_DROP)
lcd0_cfg = props_of(S + 'lcd0@01c0c000', drop=('compatible', 'status'))

# U-Boot's display and backlight code finds disp/lcd0/lcd1/tv0/hdmi/pwm*
# through aliases only and expects the vendor layout (legacy clocks, an lcd1
# node, the old pwm binding).  Give it verbatim copies with the compatible
# renamed so the kernel never binds them, under a container node outside the
# soc bus so it does not even create devices for them; the kernel keeps the
# dtsi nodes.
PWMS = ['pwm@0300a000'] + ['pwm%d@0300a000' % i for i in range(6)]
UBOOT_DISPLAY = ['disp@01000000', 'lcd0@01c0c000', 'lcd1@01c0c001', 'tv0@01c94000',
                 'hdmi@06000000'] + PWMS


def uboot_copy(name):
    n = node(S + name)
    compat = dict(n.props)['compatible'].split('"')[1]
    return em.emit(n, 2, drop=('compatible', 'iommus'), extra=('compatible = "%s-uboot"' % compat,))


uboot_display = '\n\n'.join(uboot_copy(n) for n in UBOOT_DISPLAY)
pwm_aliases = '\n'.join('\t\t%s = &%s;' % (n.split('@')[0], em.label_for(ph(S + n))) for n in PWMS)

usbc0_cfg = props_of(S + 'usbc0@0', drop=('device_type',))
sdc2 = S + 'sdmmc@04022000'

dram_cfg = props_of('/dram', drop=('compatible', 'clocks', 'clock-names', 'device_type'))
gpu_cfg = props_of('/gpu@0x01800000', drop=('compatible', 'reg', 'interrupts', 'interrupt-names',
                                            'clocks', 'clock-names', '#cooling-cells', 'device_type',
                                            'operating-points'))

# pins referenced directly by the board part below
uart0_default = em.ref(0x2b)
twi5_default = em.ref(0x47)
sdc0_default = em.ref(0x93)
sdc2_default = '%s %s' % (em.ref(0x99), em.ref(0x9a))
sdc2_sleep = em.ref(0x9b)
pwm0_default, pwm0_sleep = em.ref(0xab), em.ref(0xac)
uart1_default, uart1_sleep = em.ref(0x2d), em.ref(0x2e)
sdc1_default, sdc1_sleep = em.ref(0x9f), em.ref(0xa0)   # vendor drives the SDIO pins at 40 mA, the dtsi at 30
losc_out_pin = em.ref(0xdc)
# The vendor mcu_pwr_ctrl (PE5) / mcu_led_pwr (PI7) are 6-cell vendor gpio
# specs the 5.4 3-cell pio cannot parse; the battery driver (kernel patch
# 0022) switches them through mcu-pwr-gpios for the mcu_pwr sysfs file.
mcu_pwr = ''
if 'mcu_pwr_ctrl = <0x4b 0x04 0x05' in open(vendor).read():
    mcu_pwr = '''
/* RGB LED MCU power: PE5 MCU, PI7 LEDs (axp2202-battery/mcu_pwr) */
&%s {
	mcu-pwr-gpios = <&pio 4 5 GPIO_ACTIVE_HIGH>, <&pio 8 7 GPIO_ACTIVE_HIGH>;
};
''' % em.label_for(ph(PMU + '/bat-power-supply'))
# RGB boards (rg40xx-h/v, cubexx): the LED MCU on uart5 (PH2/PH3, ttyS5
# through the serial5 alias), which silkyrgb drives; off on the others.
_u5 = dict(node(S + 'uart@05001400').props)
uart5 = ''
if '"okay"' in _u5.get('status', ''):
    uart5 = '''
/* RGB LED MCU (silkyrgb, /dev/ttyS5) */
&uart5 {
	pinctrl-names = "default", "sleep";
	pinctrl-0 = <%s>;
	pinctrl-1 = <%s>;
	status = "okay";
};
''' % (em.ref(int(_u5['pinctrl-0'].strip('<>'), 0)), em.ref(int(_u5['pinctrl-1'].strip('<>'), 0)))

# SMHC1 is the RTL8821CS SDIO port; keep the vendor caps, the dtsi has the rest
SDC1_DROP = ('compatible', 'device_type', 'reg', 'interrupts', 'clocks', 'clock-names',
             'pinctrl-names', 'pinctrl-0', 'pinctrl-1', 'bus-width', 'keep-power-in-suspend',
             'sunxi-dly-52M-ddr4', 'ctl-spec-caps', 'status',
             'sd-uhs-sdr50', 'sd-uhs-ddr50', 'sd-uhs-sdr104')  # DDR50 init fails on this host
sdc1_cfg = props_of(S + 'sdmmc@04021000', drop=SDC1_DROP)

# Buttons and sticks: one rocknix-singleadc-joypad device (the module our
# Rockchip boards use too) with the vendor's key list as its buttons, and
# the sticks through the analog mux the vendor tree describes: amux-en PI0,
# select PI1/PI2, four axes on GPADC channel 0.  The dpad keeps the vendor's
# hat encoding (package/controllers/rocknix-joypad carries the patch that
# honours linux,input-value), so the input layout matches the gpio-keys one.
STICKS = {'rg35xx-h', 'rg35xx-pro', 'rg40xx-h', 'rg40xx-v', 'rg34xx', 'rg34xx-sp', 'rg-cubexx'}
# The vendor tree's key codes are a private numbering (physical A reported
# BTN_SOUTH, Y BTN_C, L1 BTN_WEST, R2 BTN_START ...) that its userspace
# mapped back; use the Linux gamepad codes by the vendor's key names instead.
# Anbernic layout: A right, B bottom, X top, Y left.  Dpad stays a hat.
KEY_CODES = {
    # keyX/keyY in the vendor tree are the physical Y/X buttons (verified with evtest)
    'keya': 'BTN_EAST', 'keyb': 'BTN_SOUTH', 'keyx': 'BTN_WEST', 'keyy': 'BTN_NORTH',
    'keystart': 'BTN_START', 'keysel': 'BTN_SELECT', 'keymenu': 'BTN_MODE',
    'keyl1': 'BTN_TL', 'keyr1': 'BTN_TR', 'keyl2': 'BTN_TL2', 'keyr2': 'BTN_TR2',
    'keyl3': 'BTN_THUMBL', 'keyr3': 'BTN_THUMBR',
    'keyvol+': 'KEY_VOLUMEUP', 'keyvol-': 'KEY_VOLUMEDOWN',
}
keys = []
for k in node(S + 'gpio_keys').children:
    p = dict(k.props)
    port, pin = [int(x, 16) for x in p['gpios'].strip('<>').split()[1:3]]
    kname = k.name.lower()
    if 'linux,input-type' in p:
        code = p['linux,code'].strip('<>')     # dpad: hat axis + value from the vendor
    elif kname in KEY_CODES:
        code = KEY_CODES[kname]
    else:
        raise SystemExit('%s: no gamepad code for key %s' % (vendor, k.name))
    kname = kname[:-1] + {'+': '-up', '-': '-down'}[kname[-1]] if kname[-1] in '+-' else kname
    lines = ['\t\t%s {' % kname,
             '\t\t\tlabel = %s;' % p['label'],
             '\t\t\tgpios = <&pio %d %d (GPIO_ACTIVE_LOW | GPIO_PULL_UP)>; /* P%s%d */' % (port, pin, chr(ord('A') + port), pin),
             '\t\t\tlinux,code = <%s>;' % code]
    if 'linux,input-type' in p:
        lines.append('\t\t\tlinux,input-type = %s;' % p['linux,input-type'])
        lines.append('\t\t\tlinux,input-value = %s;' % p['linux,input-value'])
    lines.append('\t\t};')
    keys.append('\n'.join(lines))
keys_label = dict(node(S + 'gpio_keys').props)['label']
amux_count = 4 if device in STICKS else 0
# panel buffers needed to hold 1280x720x4 x2 (HDMI): 720x720 -> 4, the rest -> 6
fb0_buffer_num = 4 if device == 'rg-cubexx' else 6
# boards without sticks: the D-pad can act as the left stick (dpad-toggle)
dpad_joystick = '' if device in STICKS else '\t\trocknix,dpad-joystick;\n'
# clamshells: the vendor hall_key (PE7) as a lid switch.  The sensor drives
# the line (high = open), it only needs the pin muxed as an input, which the
# gpio request does; a pinctrl claim would make the request fail (strict).
lid = ''
if 'hall_key = <0x4b 0x04 0x07' in open(vendor).read():
    lid = '''
	gpio-keys-lid {
		compatible = "gpio-keys";

		lid-switch {
			label = "Lid Switch";
			gpios = <&pio 4 7 GPIO_ACTIVE_LOW>; /* PE7 */
			linux,input-type = <EV_SW>;
			linux,code = <SW_LID>;
			linux,can-disable;
			debounce-interval = <20>;
			wakeup-source;
			wakeup-event-action = <EV_ACT_DEASSERTED>;
		};
	};
'''

pins = em.emit_pins(2)

dts = f'''// SPDX-License-Identifier: (GPL-2.0+ OR MIT)
/*
 * {model}, on the orangepi 5.4 sun50iw9 BSP.
 *
 * Generated from the vendor 4.9 device tree by
 * board/allwinner/h700/scripts/build_dts.py.  The vendor U-Boot 2018
 * shares this DTB with the kernel: it wants the legacy /clocks tree, the
 * sys_config nodes under /soc and allwinner,* pin properties, which the 5.4
 * kernel either ignores or understands as a fallback.
 */

/dts-v1/;

#include "sun50iw9.dtsi"
#include <dt-bindings/input/input.h>
#include <dt-bindings/input/gpio-keys.h>

/ {{
	model = "{model}";
	/* the extlinux entry this tree belongs to (S01knulli-device) */
	knulli,device = "{device}";
	compatible = "allwinner,h616", "arm,sun50iw9p1";

	aliases {{
		disp = &{em.label_for(ph(S + 'disp@01000000'))};
		hdmi = &{em.label_for(ph(S + 'hdmi@06000000'))};
		lcd0 = &{em.label_for(ph(S + 'lcd0@01c0c000'))};
		lcd1 = &{em.label_for(ph(S + 'lcd1@01c0c001'))};
		tv0 = &{em.label_for(ph(S + 'tv0@01c94000'))};
{pwm_aliases}
		pmu0 = &{em.label_for(ph(PMU))};
		standby_param = &{em.label_for(ph('/standby_param'))};
		twi5 = &twi5;
		mmc0 = &sdc0;
		mmc2 = &sdc2;
		sdc0 = &sdc0;
		sdc2 = &sdc2;
	}};

	chosen {{
		stdout-path = "serial0:115200n8";
	}};

{memory}

{clocks}

{standby}

{axpparam}

	joypad: rocknix-singleadc-joypad {{
		compatible = "rocknix-singleadc-joypad";
		joypad-name = {keys_label};
		/* same ids as the gpio-keys device had: the es_input.cfg entries
		 * match GUID 19000000010000000100000000010000 */
		joypad-vendor = <0x0001>;
		joypad-product = <0x0001>;
		joypad-revision = <0x0100>;
		poll-interval = <20>;

		/* sticks: 4 axes through the analog mux into gpadc channel 0 */
		io-channel-names = "amux_adc";
		io-channels = <&gpadc 0>;
		amux-count = <{amux_count}>;
{dpad_joystick}		/* ABS_RY ABS_RX ABS_Y ABS_X */
		amux-channel-mapping = <0 2 1 3>;
		amux-en-gpios = <&pio 8 0 GPIO_ACTIVE_HIGH>; /* PI0 */
		amux-a-gpios = <&pio 8 1 GPIO_ACTIVE_LOW>;   /* PI1 */
		amux-b-gpios = <&pio 8 2 GPIO_ACTIVE_LOW>;   /* PI2 */
		button-adc-scale = <2>;
		button-adc-deadzone = <128>;
		button-adc-fuzz = <32>;
		button-adc-flat = <32>;
		abs_x-p-tuning = <70>;
		abs_x-n-tuning = <70>;
		invert-absx;
		abs_y-p-tuning = <70>;
		abs_y-n-tuning = <70>;
		invert-absy;
		abs_rx-p-tuning = <70>;
		abs_rx-n-tuning = <70>;
		invert-absrx;
		abs_ry-p-tuning = <70>;
		abs_ry-n-tuning = <70>;
		invert-absry;

{chr(10).join(keys)}
	}};
{lid}}};

/* the sunxi GPADC through the mainline IIO driver (kernel patch 0018) */
&gpadc {{
	compatible = "allwinner,sun50i-h616-gpadc";
	#address-cells = <1>;
	#size-cells = <0>;
	#io-channel-cells = <1>;
	status = "okay";

	channel@0 {{
		reg = <0>;
	}};
}};

/* No OP-TEE in this boot package. */
&{{/firmware/optee}} {{
	status = "disabled";
}};

&cpu0 {{
	cpu-supply = <&{em.label_for(ph(PMU + '/regulators@0/dcdc1'))}>;
}};

/* The H700 fuses speed bin 0x6c00, which the 5.4 cpufreq-nvmem driver maps
 * to "a5" (kernel patch 0012); the dtsi table only knows a0-a4.  Voltages
 * are mainline's speed5 set (rocknix), which runs this device at 1.5 GHz. */
&cpu_opp_table {{
	opp@480000000 {{
		opp-microvolt-a5 = <900000>;
		opp-supported-hw = <0x3f>;
	}};
	opp@720000000 {{
		opp-microvolt-a5 = <900000>;
		opp-supported-hw = <0x2d>;
	}};
	opp@1008000000 {{
		opp-microvolt-a5 = <900000>;
		opp-supported-hw = <0x3f>;
	}};
	opp@1104000000 {{
		opp-microvolt-a5 = <950000>;
		opp-supported-hw = <0x2d>;
	}};
	opp@1200000000 {{
		opp-microvolt-a5 = <1020000>;
		opp-supported-hw = <0x3f>;
	}};
	opp@1416000000 {{
		opp-microvolt-a5 = <1100000>;
		opp-supported-hw = <0x2d>;
	}};
	opp@1512000000 {{
		opp-microvolt-a5 = <1160000>;
		opp-supported-hw = <0x2a>;
	}};
}};

/* Mali OPPs and dvfs knobs from the vendor tree (legacy operating-points),
 * minus the 696 MHz @ 0.96 V point: the GPU rail (dcdc2) is a fixed 0.94 V. */
&gpu {{
{gpu_cfg}
	operating-points = <240000 900000  336000 900000  420000 900000
			    504000 900000  600000 900000>;
}};

&dram {{
{dram_cfg}
}};

/* U-Boot reaches these through its aliases only; keeping them out of the
 * simple-bus means the kernel creates no platform devices for them (they
 * would collide with the dtsi nodes of the same unit address). */
/ {{
	uboot-display {{
		#address-cells = <2>;
		#size-cells = <2>;
{uboot_display}
	}};
}};

&soc {{
{sysconfig}

		boot_disp: boot_disp {{
			compatible = "allwinner,boot_disp";
		}};
}};

/* Bank G (wifi SDIO, bt uart, 32k out) runs at 1.8 V from aldo4; the 5.4
 * pinctrl sets a bank's pad voltage mode from its supply, nothing else. */
&pio {{
	vcc-pg-supply = <&{em.label_for(ph(PMU + '/regulators@0/aldo4'))}>;
	/* panel generation id, read by the disp2 panel driver (lcd_id_gpio) */
	pinctrl-names = "default";
	pinctrl-0 = <&lcd_id_pin>;

	lcd_id_pin: lcd-id-pin {{
		allwinner,pins = "PE6";
		allwinner,function = "gpio_in";
		allwinner,muxsel = <0>;
		allwinner,drive = <0>;
		allwinner,pull = <{lcd_id_pull}>;
	}};

{chr(10).join(pins['pio'])}
}};

&r_pio {{
{chr(10).join(pins['r_pio'])}
}};

&uart0 {{
	pinctrl-names = "default", "sleep";
	pinctrl-0 = <{uart0_default}>;
	pinctrl-1 = <&uart0_ph_sleep>;
	status = "okay";
}};

&twi5 {{
	clock-frequency = <200000>;
	pinctrl-names = "default";
	pinctrl-0 = <{twi5_default}>;
	no_suspend = <1>;
	status = "okay";

{pmu}
}};

/* Rails the vendor tree leaves at "whatever U-Boot set" (0.5-3.5 V range):
 * pin them like mainline does, so enabling them lands on the right voltage.
 * aldo4: codec AVCC and the 1.8 V PG bank; cldo1: speaker amp; cldo4: wifi. */
&{em.label_for(ph(PMU + '/regulators@0/aldo4'))} {{
	regulator-min-microvolt = <1800000>;
	regulator-max-microvolt = <1800000>;
}};

&{em.label_for(ph(PMU + '/regulators@0/cldo1'))} {{
	regulator-min-microvolt = <3300000>;
	regulator-max-microvolt = <3300000>;
}};

&{em.label_for(ph(PMU + '/regulators@0/cldo4'))} {{
	regulator-min-microvolt = <3300000>;
	regulator-max-microvolt = <3300000>;
}};

&sdc0 {{
	pinctrl-0 = <{sdc0_default}>;
	cd-gpios = <&pio 5 6 (GPIO_ACTIVE_LOW | GPIO_PULL_UP)>; /* PF6 */
	cd-used-24M;
	sunxi-dis-signal-vol-sw;
	ctl-spec-caps = <0x608>;
	max-busy-timeout = <0x1388>;
	status = "okay";
}};

/* TF2 slot: SMHC2 wired to the PC pins as a 4-bit SD port. */
&sdc2 {{
	pinctrl-0 = <{sdc2_default}>;
	pinctrl-1 = <{sdc2_sleep}>;
	bus-width = <4>;
	/delete-property/ non-removable;
	/delete-property/ no-sd;
	no-mmc;
	cap-sd-highspeed;
	broken-cd;
	cd-gpios = <&pio 4 22 (GPIO_ACTIVE_LOW | GPIO_PULL_UP)>; /* PE22 */
	card-pwr-gpios = <&pio 4 4 GPIO_ACTIVE_HIGH>; /* PE4 */
	cd-used-24M;
	sunxi-dis-signal-vol-sw;
	sunxi-power-save-mode;
	ctl-spec-caps = <0x608>;
	max-busy-timeout = <0x1388>;
	vqmmc-supply = <&{em.label_for(ph(PMU + '/regulators@0/aldo1'))}>;
	status = "okay";
}};

/* U-Boot uses the vendor copies under /soc instead. */
/delete-node/ &uboot_disp;
/delete-node/ &uboot_hdmi;

/* pll-video0-4x is the PLL's VCO and cannot go below 288 MHz; disp2 sets the
 * TCON parent to lcd_dclk_freq * 6 (144 MHz here), so feed tcon-lcd0 from the
 * /4 output instead or the panel is clocked at twice its dot clock. */
&disp {{
	assigned-clocks = <&ccu CLK_TCON_TV0>, <&ccu CLK_TCON_LCD0>;
	assigned-clock-parents = <&ccu CLK_PLL_VIDEO2>, <&ccu CLK_PLL_VIDEO0>;
	assigned-clock-rates = <0>, <0>;
{disp_cfg}
	/* fb0 is sized at boot: room for a double-buffered 1280x720 HDMI fb */
	fb0_buffer_num = <{fb0_buffer_num}>;
}};

&lcd0 {{
{lcd0_cfg}
	/* init tables in the disp2 panel driver: PE6 high (pull-up) / low */
{lcd_panel_init}
{lcd_id_gpio}
}};

&pwm0 {{
	pinctrl-names = "active", "sleep";
	pinctrl-0 = <{pwm0_default}>;
	pinctrl-1 = <{pwm0_sleep}>;
	status = "okay";
}};

&usbc0 {{
{usbc0_cfg}
}};

&sdc1 {{
	pinctrl-0 = <{sdc1_default}>;
	pinctrl-1 = <{sdc1_sleep}>;
{sdc1_cfg}
	status = "okay";
}};

{uart5}{mcu_pwr}
/* bluetooth side of the RTL8821CS */
&uart1 {{
	pinctrl-names = "default", "sleep";
	pinctrl-0 = <{uart1_default}>;
	pinctrl-1 = <{uart1_sleep}>;
	status = "okay";
}};

/* RTL8821CS: PG18 wifi enable, PG19 bt reset, PG15/PG16 host wake, PG17
 * bt wake, cldo4 the module rail, and the 32 kHz fanout on PG10.  bt_rst_n
 * is active low for sunxi-bt: probe drives the assert level, on releases it. */
&rfkill {{
	pinctrl-names = "default";
	pinctrl-0 = <{losc_out_pin}>;
	status = "okay";

	wlan {{
		compatible = "allwinner,sunxi-wlan";
		clocks = <&rtc_ccu CLK_OSC32K_OUT>;
		clock-names = "32k-fanout";
		assigned-clocks = <&rtc_ccu CLK_OSC32K_OUT>;
		assigned-clock-parents = <&rtc_ccu CLK_DCXO_32K_OUT>;
		wlan_busnum = <1>;
		wlan_power = "axp2202-cldo4";
		wlan_regon = <&pio 6 18 GPIO_ACTIVE_HIGH>; /* PG18 */
		wlan_hostwake = <&pio 6 15 GPIO_ACTIVE_HIGH>; /* PG15 */
	}};

	bt {{
		compatible = "allwinner,sunxi-bt";
		clocks = <&rtc_ccu CLK_OSC32K_OUT>;
		clock-names = "32k-fanout";
		bt_rst_n = <&pio 6 19 GPIO_ACTIVE_LOW>; /* PG19 */
	}};
}};

&btlpm {{
	uart_index = <1>;
	bt_wake = <&pio 6 17 GPIO_ACTIVE_HIGH>; /* PG17 */
	bt_hostwake = <&pio 6 16 GPIO_ACTIVE_HIGH>; /* PG16 */
	status = "okay";
}};

/* Internal codec, card "audiocodec".  PI5 enables the speaker amplifier on
 * cldo1; PI3 is the headphone jack, high when a plug is in (kernel patch
 * 0008 mutes the amplifier while it is). */
&codec {{
	lineout_vol = <0x1f>;
	tx_hub_en;
	pa_pin_max = <1>;
	pa_pin_0 = <&pio 8 5 GPIO_ACTIVE_HIGH>; /* PI5 */
	pa_pin_level_0 = <1>;
	pa_pin_msleep_0 = <100>;
	pa-supply = <&{em.label_for(ph(PMU + '/regulators@0/cldo1'))}>;
	hp-det-gpios = <&pio 8 3 GPIO_ACTIVE_HIGH>; /* PI3 */
	status = "okay";
}};

&codec_plat {{
	status = "okay";
}};

&codec_mach {{
	status = "okay";
}};

/* third reg: the EHCI0 PMU block, whose PHY0 SIDDQ the udc clears (0011) */
&udc {{
	reg = <0x0 0x05100000 0x0 0x1000>,
	      <0x0 0x00000000 0x0 0x100>,
	      <0x0 0x05101800 0x0 0x100>;
	clocks = <&ccu CLK_BUS_OTG>, <&ccu CLK_USB_PHY0>, <&ccu CLK_BUS_EHCI0>;
	clock-names = "bus_otg", "phy", "bus_ehci0";
	resets = <&ccu RST_BUS_OTG>, <&ccu RST_USB_PHY0>, <&ccu RST_BUS_EHCI0>;
	reset-names = "otg", "phy", "ehci0";
	det_vbus_supply = <&{em.label_for(ph(PMU + '/usb_power_supply'))}>;
	status = "okay";
}};

&ehci0 {{
	drvvbus-supply = <&{em.label_for(ph(PMU + '/regulators@0/drivevbus'))}>;
	status = "okay";
}};

&ohci0 {{
	drvvbus-supply = <&{em.label_for(ph(PMU + '/regulators@0/drivevbus'))}>;
	status = "okay";
}};
'''

# pins referenced while emitting the late blocks above (pwm0 etc.) are already
# in need_pins because em.ref() registered them before emit_pins() ran.
# 24-bit panels the vendor still dithers to 18 bit (lcd_frm = 1): the FRM
# pattern shows as vertical lines on flat colours (RG34XX-SP, checked side by
# side on hardware).  Both lcd0 copies: the kernel's and U-Boot's.
FRM_OFF = {'rg34xx-sp'}
if device in FRM_OFF:
    assert dts.count('lcd_frm = <0x01>;') == 2, device
    dts = dts.replace('lcd_frm = <0x01>;', 'lcd_frm = <0x00>;')
open(out, 'w').write(dts)
print('wrote', out)
