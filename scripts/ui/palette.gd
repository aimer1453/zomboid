class_name Palette
extends RefCounted

## 项目配色 (用户指定) + 衍生面板配色, 集中管理便于全局统一
const BLUE   := Color("#4E7D96")  # 钢蓝 — 强调/激活/边框
const ORANGE := Color("#FF844B")  # 橙 — 选中态/警示/高亮
const LIGHT  := Color("#E3EDF2")  # 浅蓝灰 — 文本/亮边
const DARK   := Color("#0A0D25")  # 深蓝近黑 — 背景/文字

## 面板配色
const BG_TOP    := Color("#1A2B3C")  # 背景渐变顶 (蓝调)
const BG_BOTTOM := Color("#0A0D25")  # 背景渐变底 (深)
const PANEL_BG      := Color(0.08, 0.10, 0.16, 0.92)  # 详情面板背景
const PANEL_BORDER  := Color("#4E7D96")  # 详情面板边框
const CARD_BG_UNSEL := Color(0.10, 0.13, 0.20, 0.85)  # 未选中卡片
const CARD_BG_SEL   := Color(0.18, 0.24, 0.34, 0.95)  # 选中卡片 (亮蓝调)
const CARD_BORDER_UNSEL := Color(0.32, 0.42, 0.55, 0.8)
const CARD_BORDER_SEL   := Color("#FF844B")  # 选中态: 橙色边框
const ACCENT_GRADIENT := [Color("#FF844B"), Color("#E3EDF2")]  # 强调渐变 (橙→浅)

## 文本
const TEXT_PRIMARY   := Color("#E3EDF2")
const TEXT_SECONDARY := Color("#FF844B")  # 系列文字 — 橙
const TEXT_MUTED     := Color(0.55, 0.65, 0.78)


## 创建竖向渐变纹理 (顶 → 底). 用作背景/Panel 渐变填充
static func vertical_gradient(top: Color, bottom: Color, w: int = 4, h: int = 512) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, top)
	grad.set_color(1, bottom)
	# 默认 INTERPOLATION_LINEAR (0), 不显式设, 避免不同 Godot 版本枚举名差异
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = w
	tex.height = h
	tex.repeat = 0
	return tex


## 主背景: 顶深蓝 → 底更深 (呼应 DARK + BLUE)
static func bg_gradient() -> GradientTexture2D:
	return vertical_gradient(BG_TOP, BG_BOTTOM, 4, 2048)


## 强调渐变 (橙→浅蓝): 用于标题/选中态装饰
static func accent_gradient() -> GradientTexture2D:
	return vertical_gradient(ACCENT_GRADIENT[0], ACCENT_GRADIENT[1], 256, 64)


## 给 StyleBoxFlat 添加阴影感的边框颜色 (按状态)
static func border_for(selected: bool) -> Color:
	return CARD_BORDER_SEL if selected else CARD_BORDER_UNSEL


## 标题字号 (大字)/ 副标题 (中)/ 正文 (中)/ 提示 (小)
const TITLE_FONT := 42
const SUBTITLE_FONT := 17
const CARD_NAME_FONT := 19
const CARD_SERIES_FONT := 11
const CARD_TAG_FONT := 12
const DETAIL_TITLE_FONT := 22
const DETAIL_TEXT_FONT := 13
const BUTTON_FONT := 18
const BUTTON_BIG_FONT := 20