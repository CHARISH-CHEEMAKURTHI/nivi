class_name UiTheme
extends RefCounted
## The wood-and-gold interface, generated at startup so the project needs no
## image assets. Panels are parchment in a gold frame; buttons are chunky
## rounded slabs with a lit top edge and a solid shadow along the bottom.

const WOOD := Color("6b4423")
const WOOD_DARK := Color("3b2410")
const WOOD_LIGHT := Color("8a5a2e")
const PARCH := Color("f6e7c4")
const PARCH_DARK := Color("e3cb9b")
const FRAME := Color("c9973f")
const INK := Color("493015")
const MUTED := Color("7d6340")

const GREEN := [Color("86d13f"), Color("4f9a12"), Color("367006")]
const RED := [Color("f4614c"), Color("c72c1c"), Color("8f1a0e")]
const BLUE := [Color("55b6ee"), Color("1f7fc4"), Color("135a90")]
const GOLD := [Color("ffd24a"), Color("e3a00d"), Color("a97202")]
const BROWN := [Color("8a5a2e"), Color("5c3a17"), Color("2a1808")]

const TEX := 96          ## generated texture size
const RADIUS := 22.0     ## corner radius in texture pixels
const MARGIN := 30       ## nine-patch margin

static func _rounded_alpha(x: float, y: float, w: float, h: float, r: float) -> float:
	# signed distance to a rounded rectangle, turned into a soft edge
	var qx: float = absf(x - w * 0.5) - (w * 0.5 - r)
	var qy: float = absf(y - h * 0.5) - (h * 0.5 - r)
	var d: float
	if qx > 0.0 and qy > 0.0:
		d = sqrt(qx * qx + qy * qy) - r
	else:
		d = maxf(qx, qy) - r
	return clampf(0.5 - d, 0.0, 1.0)

## A chunky button face: dark rim, vertical gradient, bright top edge, dark base.
static func _button_image(top: Color, bottom: Color, edge: Color, rim: Color) -> ImageTexture:
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	var edge_h := 11.0
	for y in TEX:
		for x in TEX:
			var a := _rounded_alpha(x + 0.5, y + 0.5, TEX, TEX, RADIUS)
			if a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var inner := _rounded_alpha(x + 0.5, y + 0.5, TEX, TEX, RADIUS) - _rounded_alpha(x + 0.5 - 3.0, y + 0.5 - 3.0, TEX - 6.0, TEX - 6.0, RADIUS - 3.0)
			var col: Color
			if inner > 0.35:
				col = rim
			elif y > TEX - edge_h:
				col = edge
			else:
				var t := clampf(float(y) / float(TEX - edge_h), 0.0, 1.0)
				col = top.lerp(bottom, t)
				if y < 6:
					col = col.lerp(Color(1, 1, 1, 1), 0.34 * (1.0 - y / 6.0))
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## Parchment sheet inside a gold frame inside a dark outline.
static func _panel_image() -> ImageTexture:
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	for y in TEX:
		for x in TEX:
			var a := _rounded_alpha(x + 0.5, y + 0.5, TEX, TEX, RADIUS)
			if a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var d_outer := _rounded_alpha(x + 0.5 - 4.0, y + 0.5 - 4.0, TEX - 8.0, TEX - 8.0, RADIUS - 4.0)
			var d_inner := _rounded_alpha(x + 0.5 - 9.0, y + 0.5 - 9.0, TEX - 18.0, TEX - 18.0, RADIUS - 9.0)
			var col: Color
			if d_outer < 0.5:
				col = WOOD_DARK
			elif d_inner < 0.5:
				col = FRAME
			else:
				col = PARCH.lerp(PARCH_DARK, float(y) / float(TEX))
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## A wooden plaque, used for title ribbons, headings and the resource bars.
static func _plaque_image(top: Color, bottom: Color, rim: Color, radius := RADIUS) -> ImageTexture:
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	for y in TEX:
		for x in TEX:
			var a := _rounded_alpha(x + 0.5, y + 0.5, TEX, TEX, radius)
			if a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var inner := _rounded_alpha(x + 0.5 - 3.0, y + 0.5 - 3.0, TEX - 6.0, TEX - 6.0, radius - 3.0)
			var col: Color = rim if inner < 0.5 else top.lerp(bottom, float(y) / float(TEX))
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

static func _stylebox(tex: Texture2D, margin := MARGIN, content := 12) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(content)
	return sb

static func _button_set(theme: Theme, type_name: String, cols: Array, text_col: Color) -> void:
	var normal := _stylebox(_button_image(cols[0], cols[1], cols[2], WOOD_DARK), MARGIN, 14)
	var hover := _stylebox(_button_image(cols[0].lightened(0.10), cols[1].lightened(0.10), cols[2], WOOD_DARK), MARGIN, 14)
	var pressed := _stylebox(_button_image(cols[1], cols[2], cols[2], WOOD_DARK), MARGIN, 14)
	pressed.set_content_margin(SIDE_TOP, 17)
	pressed.set_content_margin(SIDE_BOTTOM, 11)
	var disabled := _stylebox(_button_image(Color("9a9a9a"), Color("6d6d6d"), Color("4b4b4b"), WOOD_DARK), MARGIN, 14)
	theme.set_stylebox("normal", type_name, normal)
	theme.set_stylebox("hover", type_name, hover)
	theme.set_stylebox("pressed", type_name, pressed)
	theme.set_stylebox("disabled", type_name, disabled)
	theme.set_stylebox("focus", type_name, StyleBoxEmpty.new())
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(st, type_name, text_col)
	theme.set_color("font_disabled_color", type_name, Color(1, 1, 1, 0.55))
	theme.set_constant("outline_size", type_name, 5)
	theme.set_color("font_outline_color", type_name, Color(0, 0, 0, 0.45))
	theme.set_font_size("font_size", type_name, 19)

static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18

	# Buttons. The plain Button is blue; the rest are theme type variations.
	_button_set(theme, "Button", BLUE, Color.WHITE)
	for variant in [["GreenButton", GREEN, Color.WHITE], ["RedButton", RED, Color.WHITE],
			["GoldButton", GOLD, Color("5a3c00")], ["WoodButton", BROWN, Color.WHITE]]:
		var name: String = variant[0]
		theme.add_type(name)
		theme.set_type_variation(name, "Button")
		_button_set(theme, name, variant[1], variant[2])

	# Panels.
	theme.set_stylebox("panel", "PanelContainer", _stylebox(_panel_image(), MARGIN, 16))
	theme.add_type("Plaque")
	theme.set_type_variation("Plaque", "PanelContainer")
	theme.set_stylebox("panel", "Plaque", _stylebox(_plaque_image(WOOD_LIGHT, WOOD, WOOD_DARK), MARGIN, 10))
	theme.add_type("Ribbon")
	theme.set_type_variation("Ribbon", "PanelContainer")
	theme.set_stylebox("panel", "Ribbon", _stylebox(_plaque_image(WOOD_LIGHT, WOOD, WOOD_DARK), MARGIN, 12))
	theme.add_type("Card")
	theme.set_type_variation("Card", "PanelContainer")
	theme.set_stylebox("panel", "Card", _stylebox(_plaque_image(Color("fffaf0"), Color("ecd9ae"), FRAME), MARGIN, 8))

	# Labels.
	theme.set_color("font_color", "Label", INK)
	theme.set_font_size("font_size", "Label", 18)
	theme.add_type("TitleLabel")
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_color("font_color", "TitleLabel", Color.WHITE)
	theme.set_font_size("font_size", "TitleLabel", 22)
	theme.set_constant("outline_size", "TitleLabel", 6)
	theme.set_color("font_outline_color", "TitleLabel", Color(0, 0, 0, 0.5))
	theme.add_type("ValueLabel")
	theme.set_type_variation("ValueLabel", "Label")
	theme.set_color("font_color", "ValueLabel", Color.WHITE)
	theme.set_font_size("font_size", "ValueLabel", 19)
	theme.set_constant("outline_size", "ValueLabel", 6)
	theme.set_color("font_outline_color", "ValueLabel", Color(0, 0, 0, 0.75))
	theme.add_type("MutedLabel")
	theme.set_type_variation("MutedLabel", "Label")
	theme.set_color("font_color", "MutedLabel", MUTED)
	theme.set_font_size("font_size", "MutedLabel", 16)

	# Progress bars (build timers, happiness).
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("3b2a12")
	bg.set_corner_radius_all(8)
	bg.border_width_bottom = 2
	bg.border_width_top = 2
	bg.border_width_left = 2
	bg.border_width_right = 2
	bg.border_color = WOOD_DARK
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color("3ddc97")
	fg.set_corner_radius_all(8)
	theme.set_stylebox("background", "ProgressBar", bg)
	theme.set_stylebox("fill", "ProgressBar", fg)
	theme.set_color("font_color", "ProgressBar", Color.WHITE)

	var scroll := StyleBoxFlat.new()
	scroll.bg_color = Color(0, 0, 0, 0)
	theme.set_stylebox("panel", "ScrollContainer", scroll)
	return theme

## A round red close button, the one that sits on the corner of every window.
static func close_button() -> Button:
	var b := Button.new()
	b.text = "X"
	b.custom_minimum_size = Vector2(44, 44)
	b.theme_type_variation = "RedButton"
	return b
