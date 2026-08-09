extends Node2D

# ============================================================
# DamagePopup — 扣血/治疗飘字
# ============================================================
# 挂在单位上 (局部坐标, 跟随单位), 显示后上浮 + 渐隐 + 放大, 约 1 秒销毁。
# 用法:
#   var popup := DP.new()
#   popup.setup("-12", Color(1, 0.25, 0.25), 22)   # 文本/颜色/字号
#   popup.position = Vector2(0, -tile_size * 0.9)  # 头顶
#   add_child(popup)

var _label: Label = null
var _life: float = 1.0
const MAX_LIFE: float = 1.0
const RISE_SPEED: float = 38.0


func setup(text: String, color: Color = Color(1.0, 0.3, 0.3), font_size: int = 22) -> void:
	_label = Label.new()
	_label.text = text
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 宽高粗分配, 靠 scale/alignment 居中
	_label.size = Vector2(120, 40)
	_label.position = Vector2(-60, -36)
	add_child(_label)
	z_index = 50
	set_process(true)


## 抵消父节点走路倾斜, 保持飘字垂直
func _process(delta: float) -> void:
	var p := get_parent()
	if p and p.rotation != 0.0:
		rotation = -p.rotation
	elif rotation != 0.0:
		rotation = 0.0
	_life -= delta
	var t := _life / MAX_LIFE
	position.y -= RISE_SPEED * delta
	if _label:
		# 渐隐 (前半段保持清晰, 后半段淡出)
		_label.modulate.a = clampf(t * 2.0, 0.0, 1.0)
		# 轻微放大回弹
		var s := 1.0 + (1.0 - t) * 0.25
		_label.scale = Vector2(s, s)
	if _life <= 0.0:
		queue_free()
