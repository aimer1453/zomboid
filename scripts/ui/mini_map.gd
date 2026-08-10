class_name MiniMap
extends Control

# ============================================================
# MiniMap — 屏幕右上角小地图 (CanvasLayer 内, 不随相机缩放)
# ============================================================
# 复用 FogOfWar 的探索/可见状态:
#   - 已探索格 -> 画地形色 (当前视野内亮, 仅记忆则暗)
#   - 未探索格 -> 近黑
#   - 主角 -> 亮蓝点; 已探索区内的敌人 -> 红点
# 数据来源: DrawTileMap.get_used_cells() / get_cell_atlas_coords(),
#           FogOfWar.is_explored_cell/is_visible_cell,
#           TurnManager.get_enemy_units().

var _tilemap: Node = null
var _fog: Node = null
var _player: Node = null

var box_size: float = 170.0
var margin: float = 10.0

var _last_sig: String = ""


func setup(tilemap: Node, fog: Node, player: Node) -> void:
	_tilemap = tilemap
	_fog = fog
	_player = player


func _cell_of_world(p: Vector2) -> Vector2i:
	var ts: int = _tilemap.get_tile_px() if _tilemap and _tilemap.has_method("get_tile_px") else 32
	return Vector2i(floori(p.x / float(ts)), floori(p.y / float(ts)))


func _process(_delta: float) -> void:
	if _tilemap == null or _player == null:
		return
	var sig := str(_cell_of_world(_player.global_position))
	for e in TurnManager.get_enemy_units():
		if is_instance_valid(e):
			sig += ";" + str(_cell_of_world(e.global_position))
	if sig != _last_sig:
		_last_sig = sig
		queue_redraw()


func _draw() -> void:
	if _tilemap == null or _fog == null or _player == null:
		return
	if not _tilemap.has_method("get_used_cells"):
		return
	var cells: Array = _tilemap.get_used_cells()
	if cells.is_empty():
		return

	# 地图包围盒
	var minx: int = 1000000
	var maxx: int = -1000000
	var miny: int = 1000000
	var maxy: int = -1000000
	for c in cells:
		var cc: Vector2i = c
		minx = mini(minx, cc.x)
		maxx = maxi(maxx, cc.x)
		miny = mini(miny, cc.y)
		maxy = maxi(maxy, cc.y)
	var cols: int = maxx - minx + 1
	var rows: int = maxy - miny + 1
	var ts: int = _tilemap.get_tile_px()
	var map_w: float = float(cols * ts)
	var map_h: float = float(rows * ts)
	var scale: float = mini(box_size / map_w, box_size / map_h)
	var draw_w: float = map_w * scale
	var draw_h: float = map_h * scale
	var ox: float = size.x - margin - draw_w
	# 下移避开 HUD 状态栏 (y=12..96) 与战斗日志 (y=104..312): 小地图 y=112..~282
	var oy: float = margin + 102.0
	var cw: float = float(ts) * scale + 0.5

	# 外框
	draw_rect(Rect2(ox - 3.0, oy - 3.0, draw_w + 6.0, draw_h + 6.0), Color(0.0, 0.0, 0.0, 0.7))
	draw_rect(Rect2(ox - 3.0, oy - 3.0, draw_w + 6.0, draw_h + 6.0), Color(0.6, 0.6, 0.7, 0.5), false, 1.0)

	# 格子
	for c in cells:
		var cc: Vector2i = c
		var idx: int = _tilemap.get_cell_atlas_coords(cc).x
		var col: Color = DrawTileMap.TILE_COLORS.get(idx, Color(0.5, 0.5, 0.5))
		var sx: float = ox + float(cc.x - minx) * float(ts) * scale
		var sy: float = oy + float(cc.y - miny) * float(ts) * scale
		if not _fog.is_explored_cell(cc.x, cc.y):
			col = Color(0.03, 0.03, 0.05)
		elif not _fog.is_visible_cell(cc.x, cc.y):
			col = col * 0.45  # 记忆区变暗
		draw_rect(Rect2(sx, sy, cw, cw), col)

	# 敌人 (仅在已探索格, 记忆/可见都显示)
	for e in TurnManager.get_enemy_units():
		if not is_instance_valid(e):
			continue
		var ec: Vector2i = _cell_of_world(e.global_position)
		if _fog.is_explored_cell(ec.x, ec.y):
			var ex: float = ox + (float(ec.x - minx) + 0.5) * float(ts) * scale
			var ey: float = oy + (float(ec.y - miny) + 0.5) * float(ts) * scale
			draw_circle(Vector2(ex, ey), maxf(cw * 0.5, 2.0), Color(0.92, 0.22, 0.22))

	# 主角
	var pc: Vector2i = _cell_of_world(_player.global_position)
	var px: float = ox + (float(pc.x - minx) + 0.5) * float(ts) * scale
	var py: float = oy + (float(pc.y - miny) + 0.5) * float(ts) * scale
	draw_circle(Vector2(px, py), maxf(cw * 0.6, 3.0), Color(0.35, 0.9, 1.0))

	# 标题
	if ThemeDB and ThemeDB.has_method("fallback_font"):
		draw_string(ThemeDB.fallback_font, Vector2(ox, oy - 5.0), "小地图", HORIZONTAL_ALIGNMENT_LEFT, int(draw_w), 12, Color(1.0, 1.0, 1.0, 0.85))
