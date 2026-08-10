class_name UiStyle
extends RefCounted

## 统一 UI 风格工具 — 集中圆角/阴影/配色, 让所有面板/按钮/标签走 Palette
## 用法: _panel.add_theme_stylebox_override("panel", UiStyle.standard_panel(...))

const CORNER_RADIUS := 12

## 标准面板: 半透明深色 + 蓝色边框 + 阴影 (详情/容器/存档/任务等)
static func standard_panel(radius: int = CORNER_RADIUS, padding: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.border_color = Palette.PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Palette.SHADOW
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_left = padding
	sb.content_margin_right = padding
	sb.content_margin_top = padding
	sb.content_margin_bottom = padding
	return sb


## 浅色面板: 列表/容器行
static func light_panel(radius: int = CORNER_RADIUS, padding: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.CARD_LIGHT_ROW
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Palette.SHADOW
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 1)
	sb.content_margin_left = padding
	sb.content_margin_right = padding
	sb.content_margin_top = padding - 2
	sb.content_margin_bottom = padding - 2
	return sb


## 主 CTA 按钮 (橙填充 + 深色字)
static func cta_button_states(radius: int = 12) -> Dictionary:
	return {
		"normal": _make_filled_sb(Palette.ORANGE, radius),
		"hover":  _make_filled_sb(Color("#FFA070"), radius),
		"pressed": _make_filled_sb(Color("#E3682C"), radius),
		"disabled": _make_filled_sb(Color(0.30, 0.35, 0.42), radius),
		"font_normal": Palette.DARK,
		"font_hover": Palette.DARK,
		"font_pressed": Palette.LIGHT,
		"font_disabled": Color(0.55, 0.60, 0.65),
	}


## 胶囊按钮 (次要按钮, 透明底+描边+hover 浅填充) — accent 用 Palette.BLUE/ORANGE
static func pill_button_states(accent: Color, radius: int = 18) -> Dictionary:
	return {
		"normal": _make_pill_sb(Color(0, 0, 0, 0), accent, 1, radius),
		"hover":  _make_pill_sb(Color(accent.r, accent.g, accent.b, 0.18), accent, 1, radius),
		"pressed": _make_pill_sb(Color(accent.r, accent.g, accent.b, 0.32), accent, 1, radius),
		"font_normal": accent,
		"font_hover": Palette.ORANGE,
		"font_pressed": Palette.ORANGE,
	}


## 应用按钮 (普通 → 主 CTA / 胶囊); states: {"normal": StyleBoxFlat, ..., "font_normal": Color, ...}
static func apply_button(b: Button, states: Dictionary) -> void:
	for k in states:
		var v = states[k]
		if v is StyleBoxFlat:
			b.add_theme_stylebox_override(k, v)
		elif k.begins_with("font_"):
			# key 已是完整颜色覆盖名 (如 font_normal), 直接使用
			b.add_theme_color_override(k, v)


## 应用文本色 (按语义)
static func style_label(l: Label, color: Color, font_size: int) -> void:
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)


static func _make_filled_sb(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func _make_pill_sb(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb