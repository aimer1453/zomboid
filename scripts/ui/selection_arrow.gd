extends Node2D

# ============================================================
# SelectionArrow — 选中地块指示箭头 (渐变出现 → 停留 → 渐变消失)
# ============================================================
# 用户反馈: "选中的地块需要一个箭头渐变出现再渐变消失表明我选择的是这个地块"
# 用法: sel_arrow.show_at(cell_center_world)  显示在目标格中心上方

## 动画阶段
enum Phase { HIDDEN, FADE_IN, HOLD, FADE_OUT }

## 时间参数 (秒)
const FADE_IN_TIME := 0.15
const HOLD_TIME := 0.6
const FADE_OUT_TIME := 0.4

## 箭头视觉 — 白色点状线 (用户反馈: 不要红色/红点点, 引路线改白色虚线框)
const ARROW_COLOR := Color(1.0, 1.0, 1.0, 1.0)   # 纯白
const ARROW_SIZE := 22.0                          # 箭头总高度
const ARROW_W := 16.0                             # 箭头宽
const DASH_LEN := 10.0                            # 虚线段长 (gap = dash/2, Godot draw_dashed_line)

var _phase: int = Phase.HIDDEN
var _timer: float = 0.0
var _target_pos: Vector2 = Vector2.ZERO
var _tile_size: int = 32

## 在目标格中心上方显示箭头 (世界坐标)
func show_at(cell_center: Vector2, tile_size: int = 32) -> void:
	_target_pos = cell_center + Vector2(0, -tile_size * 0.55)
	_tile_size = tile_size
	_phase = Phase.FADE_IN
	_timer = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _phase == Phase.HIDDEN:
		return
	_timer += delta
	match _phase:
		Phase.FADE_IN:
			if _timer >= FADE_IN_TIME:
				_phase = Phase.HOLD
				_timer = 0.0
		Phase.HOLD:
			if _timer >= HOLD_TIME:
				_phase = Phase.FADE_OUT
				_timer = 0.0
		Phase.FADE_OUT:
			if _timer >= FADE_OUT_TIME:
				_phase = Phase.HIDDEN
				_timer = 0.0
	queue_redraw()


func _alpha() -> float:
	match _phase:
		Phase.FADE_IN:
			return _timer / FADE_IN_TIME
		Phase.HOLD:
			return 1.0
		Phase.FADE_OUT:
			return 1.0 - _timer / FADE_OUT_TIME
	return 0.0


func _draw() -> void:
	if _phase == Phase.HIDDEN:
		return
	var a := _alpha()
	if a <= 0.0:
		return
	var color := Color(ARROW_COLOR.r, ARROW_COLOR.g, ARROW_COLOR.b, a)
	var pos := _target_pos
	# 白色点状线: 目标格虚线框 (四边) + 中央白点 (替代原实心黄色箭头)
	var half := _tile_size * 0.42
	var tl := pos + Vector2(-half, -half)
	var br := pos + Vector2(half, half)
	var w := 3.0
	draw_dashed_line(tl, Vector2(br.x, tl.y), color, w, DASH_LEN)
	draw_dashed_line(Vector2(br.x, tl.y), br, color, w, DASH_LEN)
	draw_dashed_line(br, Vector2(tl.x, br.y), color, w, DASH_LEN)
	draw_dashed_line(Vector2(tl.x, br.y), tl, color, w, DASH_LEN)
	draw_circle(pos + Vector2(0, -half * 0.2), 4.5, color)
