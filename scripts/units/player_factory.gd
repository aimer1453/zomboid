class_name PlayerFactory
extends RefCounted

# ============================================================
# PlayerFactory — 玩家实例工厂 (主地图/副本共用)
# ============================================================

static func spawn(parent: Node, pos: Vector2, tile_size: int = 32) -> CharacterBody2D:
	var player := CharacterBody2D.new()
	player.name = "Player"
	player.position = pos

	# Area2D 点击检测
	var area := Area2D.new()
	area.name = "ClickArea"
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = tile_size * 0.55
	collision.shape = shape
	area.add_child(collision)
	player.add_child(area)

	# 挂载玩家脚本
	var player_script := load("res://scripts/units/player.gd")
	player.set_script(player_script)
	player.tile_size = tile_size
	player.move_speed = 220.0

	# 占位色块 (视觉 ~满格, 与墙/地板格子等大; 用户反馈: 格子大小应一致)
	# z_index=1 画在 DrawTileMap (z=-1) 之上, 避免格子线盖在角色上
	var sprite := ColorRect.new()
	sprite.name = "BodyVisual"
	sprite.size = Vector2(tile_size * 0.95, tile_size * 0.95)
	sprite.color = Color(0.2, 0.4, 1.0)
	sprite.position = -sprite.size / 2
	sprite.z_index = 1
	# 纯视觉: 不拦截鼠标 (否则会吞掉点击/让悬停高亮被隐藏)
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.add_child(sprite)

	# 摄像机 (用户反馈: 视角太小想更近; 内部分辨率已提到 1440 故 zoom 6.0 既更近又清晰)
	# canvas_transform 已包含相机变换, 点击坐标转换(_event_to_world) 仍精确命中
	var cam := Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.zoom = Vector2(1.8, 1.8)
	player.add_child(cam)

	parent.add_child(player)
	return player
