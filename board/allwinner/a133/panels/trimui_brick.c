/* SPDX-License-Identifier: GPL-2.0 */
/*
 * TrimUI Brick (A133P) 1024x768 MIPI DSI panel, registered as "otm1289a" like
 * the stock driver.  The module ships with one of six controllers; the stock
 * U-Boot read the DCS ID registers and told the stock kernel which one through
 * "lcd=<name>" on the command line.  Here the kernel reads the IDs itself, so
 * any U-Boot works and nothing has to be passed.  "trimui_lcd=<name>" forces a
 * table (bring-up aid).  Init tables and IDs: trimui_brick_panels.h.
 * The Brick Pro (DT "trimui,brick-pro") adds gh7003 and its own jd9168 table.
 */
#include <linux/of.h>
#include "trimui_brick.h"
#include "trimui_brick_panels.h"

static void lcd_power_on(u32 sel);
static void lcd_power_off(u32 sel);
static void lcd_bl_open(u32 sel);
static void lcd_bl_close(u32 sel);
static void lcd_panel_init(u32 sel);
static void lcd_panel_exit(u32 sel);

#define panel_reset(sel, val) sunxi_lcd_gpio_set_value(sel, 0, val)

struct trimui_panel_variant {
	const char *name;
	const struct trimui_panel_cmd *table;
};

static const struct trimui_panel_variant trimui_variants[] = {
	{ "gc9702c",  trimui_brick_gc9702c },
	{ "otm1289a", trimui_brick_otm1289a },
	{ "er68576",  trimui_brick_er68576 },
	{ "st7703",   trimui_brick_st7703 },
	{ "nv3052",   trimui_brick_nv3052 },
	{ "jd9168",   trimui_brick_jd9168 },
	{ "gh7003",   trimui_brick_gh7003 },
	{ "jd9168-pro", trimui_brick_jd9168_pro },
};

static const struct trimui_panel_variant *trimui_variant;
static char trimui_lcd_force[16];

static int __init trimui_lcd_setup(char *str)
{
	strlcpy(trimui_lcd_force, str, sizeof(trimui_lcd_force));
	return 1;
}
__setup("trimui_lcd=", trimui_lcd_setup);

static const struct trimui_panel_variant *trimui_variant_by_name(const char *name)
{
	u32 i;

	for (i = 0; i < ARRAY_SIZE(trimui_variants); i++)
		if (!strcmp(trimui_variants[i].name, name))
			return &trimui_variants[i];
	return NULL;
}

static void trimui_read_id(u32 sel, u8 reg, u8 *out)
{
	u8 buf[32] = { 0 };
	u32 num = 1;

	buf[0] = 0xfe;	/* as the vendor reader: seeds the first byte */
	sunxi_lcd_dsi_dcs_read(sel, reg, buf, &num);
	memcpy(out, buf, 4);
}

/* The vendor U-Boot's decision, in its order (check_lcd_module). */
static const struct trimui_panel_variant *trimui_detect(u32 sel)
{
	u8 id04[4], da[4], db[4], dc[4];
	const char *name = NULL;

	trimui_read_id(sel, 0x04, id04);
	trimui_read_id(sel, 0xda, da);
	trimui_read_id(sel, 0xdb, db);
	trimui_read_id(sel, 0xdc, dc);
	pr_info("trimui-brick panel: id 04=%02x %02x %02x da=%02x db=%02x dc=%02x\n",
		id04[0], id04[1], id04[2], da[0], db[0], dc[0]);

	if (id04[0] == 0x00) {
		if (id04[1] == 0x97 && id04[2] == 0x02)
			name = "gc9702c";
	} else if (id04[0] == 0x61) {
		if (id04[1] == 0x00)
			name = "otm1289a";
	} else if (id04[0] == 0xe8) {
		if (da[0] == 0xe8 && db[0] == 0x85 && dc[0] == 0x76)
			name = "er68576";
	} else if (id04[0] == 0x38) {
		if (da[0] == 0x38 && db[0] == 0x21 && dc[0] == 0x1f)
			name = "st7703";
	} else if (id04[0] == 0x30) {
		if (da[0] == 0x30 && db[0] == 0x52 && dc[0] == 0x03)
			name = "nv3052";
	}
	/* 0x91/91 68 03 is jd9168, which is also the fallback */
	if (!name && da[0] == 0x70 && db[0] == 0x03 && dc[0] == 0x0a)
		name = "gh7003";
	if (!name)	/* vendor "default" uses the jd9168 table */
		name = of_machine_is_compatible("trimui,brick-pro") ?
			"jd9168-pro" : "jd9168";
	return trimui_variant_by_name(name);
}

static void lcd_cfg_panel_info(struct panel_extend_para *info)
{
	u32 i = 0, j = 0;
	u32 items;
	u8 lcd_gamma_tbl[][2] = {
		{0, 0}, {15, 15}, {30, 30}, {45, 45}, {60, 60}, {75, 75},
		{90, 90}, {105, 105}, {120, 120}, {135, 135}, {150, 150},
		{165, 165}, {180, 180}, {195, 195}, {210, 210}, {225, 225},
		{240, 240}, {255, 255},
	};
	u32 lcd_cmap_tbl[2][3][4] = {
		{
			{LCD_CMAP_G0, LCD_CMAP_B1, LCD_CMAP_G2, LCD_CMAP_B3},
			{LCD_CMAP_B0, LCD_CMAP_R1, LCD_CMAP_B2, LCD_CMAP_R3},
			{LCD_CMAP_R0, LCD_CMAP_G1, LCD_CMAP_R2, LCD_CMAP_G3},
		},
		{
			{LCD_CMAP_B3, LCD_CMAP_G2, LCD_CMAP_B1, LCD_CMAP_G0},
			{LCD_CMAP_R3, LCD_CMAP_B2, LCD_CMAP_R1, LCD_CMAP_B0},
			{LCD_CMAP_G3, LCD_CMAP_R2, LCD_CMAP_G1, LCD_CMAP_R0},
		},
	};

	items = sizeof(lcd_gamma_tbl) / 2;
	for (i = 0; i < items - 1; i++) {
		u32 num = lcd_gamma_tbl[i + 1][0] - lcd_gamma_tbl[i][0];

		for (j = 0; j < num; j++) {
			u32 value = lcd_gamma_tbl[i][1] +
				((lcd_gamma_tbl[i + 1][1] - lcd_gamma_tbl[i][1]) * j) / num;

			info->lcd_gamma_tbl[lcd_gamma_tbl[i][0] + j] =
				(value << 16) + (value << 8) + value;
		}
	}
	info->lcd_gamma_tbl[255] = (lcd_gamma_tbl[items - 1][1] << 16) +
				   (lcd_gamma_tbl[items - 1][1] << 8) +
				   lcd_gamma_tbl[items - 1][1];
	memcpy(info->lcd_cmap_tbl, lcd_cmap_tbl, sizeof(lcd_cmap_tbl));
}

/* flow and delays as the stock driver */
static s32 lcd_open_flow(u32 sel)
{
	LCD_OPEN_FUNC(sel, lcd_power_on, 10);
	LCD_OPEN_FUNC(sel, lcd_panel_init, 60);
	LCD_OPEN_FUNC(sel, sunxi_lcd_tcon_enable, 50);
	LCD_OPEN_FUNC(sel, lcd_bl_open, 0);
	return 0;
}

static s32 lcd_close_flow(u32 sel)
{
	LCD_CLOSE_FUNC(sel, lcd_bl_close, 0);
	LCD_CLOSE_FUNC(sel, sunxi_lcd_tcon_disable, 0);
	LCD_CLOSE_FUNC(sel, lcd_panel_exit, 200);
	LCD_CLOSE_FUNC(sel, lcd_power_off, 500);
	return 0;
}

static void lcd_power_on(u32 sel)
{
	sunxi_lcd_power_enable(sel, 0);
	sunxi_lcd_delay_ms(10);
	sunxi_lcd_power_enable(sel, 1);
	sunxi_lcd_delay_ms(10);
	sunxi_lcd_pin_cfg(sel, 1);
	sunxi_lcd_delay_ms(50);
	panel_reset(sel, 1);
	sunxi_lcd_delay_ms(20);
	panel_reset(sel, 0);
	sunxi_lcd_delay_ms(120);
	panel_reset(sel, 1);
	sunxi_lcd_delay_ms(20);
}

static void lcd_power_off(u32 sel)
{
	sunxi_lcd_pin_cfg(sel, 0);
	sunxi_lcd_delay_ms(20);
	panel_reset(sel, 0);
	sunxi_lcd_delay_ms(5);
	sunxi_lcd_power_disable(sel, 1);
	sunxi_lcd_delay_ms(5);
	sunxi_lcd_power_disable(sel, 0);
}

static void lcd_bl_open(u32 sel)
{
	sunxi_lcd_pwm_enable(sel);
	sunxi_lcd_backlight_enable(sel);
}

static void lcd_bl_close(u32 sel)
{
	sunxi_lcd_backlight_disable(sel);
	sunxi_lcd_pwm_disable(sel);
}

static void lcd_panel_init(u32 sel)
{
	const struct trimui_panel_cmd *c;

	/*
	 * Read the ID while the link is still in LP: a DCS read after the
	 * HS clock is started leaves the DSI unable to enter video mode.
	 */
	if (!trimui_variant && trimui_lcd_force[0])
		trimui_variant = trimui_variant_by_name(trimui_lcd_force);
	if (!trimui_variant)
		trimui_variant = trimui_detect(sel);
	pr_info("trimui-brick panel: %s\n", trimui_variant->name);

	sunxi_lcd_dsi_clk_enable(sel);

	for (c = trimui_variant->table; c->len != 0xff; c++) {
		if (c->delay_ms)
			sunxi_lcd_delay_ms(c->delay_ms);
		else if (!c->len)
			sunxi_lcd_dsi_dcs_write_0para(sel, c->cmd);
		else
			sunxi_lcd_dsi_dcs_write(sel, c->cmd, (u8 *)c->data, c->len);
	}
}

static void lcd_panel_exit(u32 sel)
{
	sunxi_lcd_dsi_dcs_write_0para(sel, 0x10);
	sunxi_lcd_delay_ms(80);
	sunxi_lcd_dsi_dcs_write_0para(sel, 0x28);
	sunxi_lcd_delay_ms(50);
}

static s32 lcd_user_defined_func(u32 sel, u32 para1, u32 para2, u32 para3)
{
	return 0;
}

struct __lcd_panel trimui_brick_panel = {
	/* the name the vendor device trees use */
	.name = "otm1289a",
	.func = {
		.cfg_panel_info = lcd_cfg_panel_info,
		.cfg_open_flow = lcd_open_flow,
		.cfg_close_flow = lcd_close_flow,
		.lcd_user_defined_func = lcd_user_defined_func,
	},
};
