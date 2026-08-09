class_name EnemyFactory
extends RefCounted

# ============================================================
# EnemyFactory — 敌人实例工厂 (所有场景共用)
# ============================================================
# 统一构建: 点击 Area2D + 占位色块 (按类型分色, 替换美术前区分变体)
# 用法: const EF := preload("res://scripts/units/enemy_factory.gd")
#       var e := EF.spawn(self, script, pos, tile_size, move_speed)
# 可选 display_name 非空时创建头顶名字 Label

## 敌人类型 → 占位色块颜色 (键 = 脚本文件名, 不含 .gd)
const ENEMY_COLORS := {
	"zombie_basic": Color(0.35, 0.55, 0.3),
	"zombie_runner": Color(0.85, 0.7, 0.2),
	"zombie_spitter": Color(0.6, 0.4, 0.8),
	"zombie_tank": Color(0.8, 0.3, 0.3),
}


static func spawn(parent: Node, script: Script, pos: Vector2, tile_size: int = 32, move_speed: float = 140.0, display_name: String = "") -> CharacterBody2D:
	var enemy := CharacterBody2D.new()
	enemy.set_script(script)
	enemy.position = pos
	enemy.tile_size = tile_size
	enemy.move_speed = move_speed

	# 点击碰撞 (网格命中为主, Area2D 仅为备用物理层)
	var area := Area2D.new()
	area.name = "ClickArea"
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = tile_size * 0.55
	collision.shape = shape
	area.add_child(collision)
	enemy.add_child(area)

	# 占位色块 (视觉 ~满格, 与墙/地板格子等大; 用户反馈: 格子大小应一致)
	# z_index=1 画在 DrawTileMap 之上
	var rect := ColorRect.new()
	rect.name = "BodyVisual"
	rect.size = Vector2(tile_size * 0.95, tile_size * 0.95)
	rect.position = -rect.size / 2
	rect.z_index = 1
	var color_key: String = script.resource_path.get_file().get_basename()
	rect.color = ENEMY_COLORS.get(color_key, Color(0.7, 0.7, 0.7))
	# 纯视觉: 不拦截鼠标 (否则会吞掉点击/让悬停高亮被隐藏 — 用户反馈点丧尸被绿块截胡)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy.add_child(rect)

	# 可选头顶名字
	if display_name != "":
		var label := Label.new()
		label.text = display_name
		label.position = Vector2(-20, -tile_size * 0.65)
		label.add_theme_font_size_override("font_size", 10)
		# 纯视觉: 不拦截鼠标
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		enemy.add_child(label)

	parent.add_child(enemy)
	return enemy
