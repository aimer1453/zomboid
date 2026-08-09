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

## 箭头视觉
const ARROW_COLOR := Color(1.0, 0.9, 0.3, 1.0)   # 亮黄
const ARROW_SIZE := 22.0                          # 箭头总高度
const ARROW_W := 16.0                             # 箭头宽

var _phase: int = Phase.HIDDEN
var _timer: float = 0.0
var _target_pos: Vector2 = Vector2.ZERO

## 在目标格中心上方显示箭头 (世界坐标)
func show_at(cell_center: Vector2, tile_size: int = 32) -> void:
	_target_pos = cell_center + Vector2(0, -tile_size * 0.55)
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
	# 箭头: 三角头 + 矩形杆 (指向下方地块)
	var color := Color(ARROW_COLOR.r, ARROW_COLOR.g, ARROW_COLOR.b, a)
	var pos := _target_pos
	# 三角头 (尖端朝下)
	var head := PackedVector2Array([
		pos + Vector2(-ARROW_W * 0.5, -ARROW_SIZE),
		pos + Vector2(ARROW_W * 0.5, -ARROW_SIZE),
		pos,
	])
	draw_colored_polygon(head, color)
	# 杆 (矩形)
	var shaft := Rect2(
		pos + Vector2(-ARROW_W * 0.18, -ARROW_SIZE),
		Vector2(ARROW_W * 0.36, ARROW_SIZE * 0.55)
	)
	draw_rect(shaft, color)
