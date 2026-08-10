extends Control

# ============================================================
# WorldMap (主地图 / 战略层) — 无限地图, 以主角为中心窗口化探索
# ============================================================
# 玩法: 主角站在中心格, 点击"相邻且已揭示"的格子前进。
#   - 公路/公园(纯路程) → 仅移动, 不进副本
#   - 公寓/医院/超市/诊所/别墅/研究所 → 到达即进入对应副本
#   - 家 → 回安全屋
# 走到新格会自动生成其四周(迷雾向外扩展), 已生成与已探索的部分随存档保留。
# WorldMapData 是 autoload 单例, 直接用全局名 WorldMapData 访问。

const DungeonScript := preload("res://scripts/dungeons/dungeon_base.gd")

const RADIUS := 4                      # 以主角为中心的视野半径 (9x9 窗口)
const CELL := 60

var _cell_layer: Control = null
var _info_label: Label = null
var _home_btn: Button = null

func _ready() -> void:
	_setup_cell_layer()
	_build_ui()
	_rebuild_cells()
	if "--auto-test" in OS.get_cmdline_user_args():
		_run_auto_test()


func _setup_cell_layer() -> void:
	_cell_layer = Control.new()
	_cell_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cell_layer)


## 以主角为中心: 把 9x9 窗口居中到实际视口 (玩家"你"标记天然落在屏幕正中)
func _window_origin() -> Vector2:
	var win := (2 * RADIUS + 1) * CELL
	var vp := get_viewport_rect().size
	var x := (vp.x - win) / 2.0
	# 顶部给标题/按钮留 140px, 否则地图会压到它们
	var y := maxf(140.0, (vp.y - win) / 2.0)
	return Vector2(x, y)


func _build_ui() -> void:
	var title := Label.new()
	title.text = "世界地图 — 点击相邻地点前进，走到新地点自动生成四周"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 30)
	title.size = Vector2(720, 36)
	title.add_theme_color_override("font_color", Color(0.92, 0.93, 0.88))
	add_child(title)

	_home_btn = Button.new()
	_home_btn.text = "返回家园"
	_home_btn.position = Vector2(560, 80)
	_home_btn.size = Vector2(140, 42)
	_home_btn.pressed.connect(_on_home_pressed)
	add_child(_home_btn)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 14)
	_info_label.position = Vector2(20, 80)
	_info_label.size = Vector2(520, 42)
	_info_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.86))
	add_child(_info_label)


func _rebuild_cells() -> void:
	for c in _cell_layer.get_children():
		c.free()
	var origin := _window_origin()
	var pc: Vector2i = WorldMapData.player_cell
	for gy in range(-RADIUS, RADIUS + 1):
		for gx in range(-RADIUS, RADIUS + 1):
			var wx: int = pc.x + gx
			var wy: int = pc.y + gy
			if not WorldMapData.is_revealed(wx, wy):
				continue
			var screen := origin + Vector2((gx + RADIUS) * CELL, (gy + RADIUS) * CELL)
			_build_cell(wx, wy, screen)
	_update_info()


func _build_cell(wx: int, wy: int, screen: Vector2) -> void:
	var t: int = WorldMapData.terrain_at(wx, wy)
	var explored_cell: bool = WorldMapData.is_explored(wx, wy)
	var rect := ColorRect.new()
	rect.position = screen
	rect.size = Vector2(CELL, CELL)
	var col: Color = WorldMapData.terrain_color(t)
	if not explored_cell:
		col = col.darkened(0.55)
	rect.color = col
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cell_layer.add_child(rect)

	# 细边框, 让格与格有分隔 (不刺眼)
	var border := ColorRect.new()
	border.position = screen
	border.size = Vector2(CELL, 2)
	border.color = Color(0.0, 0.0, 0.0, 0.35)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cell_layer.add_child(border)

	var label := Label.new()
	label.text = WorldMapData.terrain_name(t) if explored_cell else "?"
	label.add_theme_font_size_override("font_size", 13)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = screen
	label.size = Vector2(CELL, CELL)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cell_layer.add_child(label)

	if Vector2i(wx, wy) == WorldMapData.player_cell:
		var you := Label.new()
		you.text = "你"
		you.add_theme_font_size_override("font_size", 16)
		you.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
		you.position = screen + Vector2(CELL - 24, 2)
		you.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cell_layer.add_child(you)
		var ring := ColorRect.new()
		ring.position = screen
		ring.size = Vector2(CELL, CELL)
		ring.color = Color(0, 0, 0, 0)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cell_layer.add_child(ring)

	if t == WorldMapData.TerrainType.HOME and explored_cell:
		var star := Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", 18)
		star.position = screen + Vector2(4, 1)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cell_layer.add_child(star)

	# 进出口对称: 返回主地图时, 在"上次进入副本的格"上标"出口"
	if WorldMapData.has_last_entry and Vector2i(wx, wy) == WorldMapData.last_entry_cell \
			and Vector2i(wx, wy) != WorldMapData.player_cell:
		var here := Label.new()
		here.text = "出口"
		here.add_theme_font_size_override("font_size", 12)
		here.position = screen + Vector2(2, CELL - 16)
		here.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
		here.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cell_layer.add_child(here)


func _update_info() -> void:
	if _info_label == null:
		return
	var pc: Vector2i = WorldMapData.player_cell
	var t: int = WorldMapData.terrain_at(pc.x, pc.y)
	var name: String = WorldMapData.terrain_name(t)
	_info_label.text = "当前位置: %s (%d, %d)　|　点击相邻已揭示的地点前进" % [name, pc.x, pc.y]


func _on_home_pressed() -> void:
	WorldMapData.enter_home()


func _input(event) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var lp := get_local_mouse_position()
		var origin := _window_origin()
		var gx := int(floor((lp.x - origin.x) / CELL)) - RADIUS
		var gy := int(floor((lp.y - origin.y) / CELL)) - RADIUS
		if gx < -RADIUS or gx > RADIUS or gy < -RADIUS or gy > RADIUS:
			return
		_on_cell_clicked(gx, gy)


func _on_cell_clicked(gx: int, gy: int) -> void:
	var pc: Vector2i = WorldMapData.player_cell
	var target := pc + Vector2i(gx, gy)
	if target == pc:
		return
	# 仅允许走到相邻(上下左右 4 向)已揭示格; 斜向(曼哈顿距离≠1)不允许
	if abs(target.x - pc.x) + abs(target.y - pc.y) != 1:
		return
	if not WorldMapData.is_revealed(target.x, target.y):
		return
	var t: int = WorldMapData.terrain_at(target.x, target.y)
	if t == WorldMapData.TerrainType.HOME:
		print("[WorldMap] 返回家园")
		WorldMapData.enter_home()
		return
	if WorldMapData.is_building(t):
		print("[WorldMap] 进入: ", WorldMapData.terrain_name(t), " (", target.x, ",", target.y, ")")
		WorldMapData.enter_location(target.x, target.y)
		return
	# 公路/公园: 仅旅行
	WorldMapData.move_player_to(target.x, target.y)
	print("[WorldMap] 前进到: ", WorldMapData.terrain_name(t), " (", target.x, ",", target.y, ")")
	_rebuild_cells()


# --- 自动测试 (纯逻辑, 不切场景) ---

func _run_auto_test() -> void:
	var ok := true

	# === 重置: 家已探索, 四周已揭示, 远处不可见 ===
	WorldMapData.reset_map()
	var hx: int = WorldMapData.home_cell.x
	var hy: int = WorldMapData.home_cell.y
	if not WorldMapData.is_revealed(hx, hy):
		ok = false
		push_error("[WorldMap] 初始 HOME 应可见")
	if not WorldMapData.is_revealed(hx + 1, hy):
		ok = false
		push_error("[WorldMap] HOME 邻居应可见")
	if WorldMapData.is_revealed(hx + 5, hy):
		ok = false
		push_error("[WorldMap] 远处 (hx+5) 不应可见")
	# 初始应只揭示 5 格(家 + 上下左右, 菱形十字), 而非九宫格 9 格
	var init_n := 0
	for yy in range(-2, 3):
		for xx in range(-2, 3):
			if WorldMapData.is_revealed(hx + xx, hy + yy):
				init_n += 1
	if init_n != 5:
		ok = false
		push_error("[WorldMap] 初始应只揭示家+上下左右共 5 格(菱形), 实际=", init_n)
	if WorldMapData.terrain_at(hx, hy) != WorldMapData.TerrainType.HOME:
		ok = false
		push_error("[WorldMap] home 格不是 HOME")

	# === 移动: 走到邻居 → 下一圈被揭示 (迷雾扩展, 无限生成) ===
	WorldMapData.reset_map()
	WorldMapData.move_player_to(hx + 1, hy)
	if not WorldMapData.is_explored(hx + 1, hy):
		ok = false
		push_error("[WorldMap] 移动后目标格应已探索")
	if not WorldMapData.is_revealed(hx + 2, hy):
		ok = false
		push_error("[WorldMap] 移动后外圈 (hx+2) 应解锁可见")
	if not WorldMapData.is_revealed(hx + 1, hy + 1):
		ok = false
		push_error("[WorldMap] 移动后对角外圈应解锁可见")
	if WorldMapData.is_revealed(hx - 5, hy):
		ok = false
		push_error("[WorldMap] 远处 (hx-5) 仍不应可见")

	# === 确定性: 同格永远同地形 ===
	var a1: int = WorldMapData.terrain_at(7, -3)
	var a2: int = WorldMapData.terrain_at(7, -3)
	if a1 != a2:
		ok = false
		push_error("[WorldMap] 地形非确定性")
	# 家永远是家
	if WorldMapData.terrain_at(hx, hy) != WorldMapData.TerrainType.HOME:
		ok = false
		push_error("[WorldMap] 家格地形被覆盖")

	# === 建筑判定: ROAD/PARK 不是建筑, 其余是 ===
	if WorldMapData.is_building(WorldMapData.TerrainType.ROAD):
		ok = false
		push_error("[WorldMap] ROAD 不应是建筑")
	if WorldMapData.is_building(WorldMapData.TerrainType.PARK):
		ok = false
		push_error("[WorldMap] PARK 不应是建筑")
	if not WorldMapData.is_building(WorldMapData.TerrainType.SUPERMARKET):
		ok = false
		push_error("[WorldMap] SUPERMARKET 应是建筑")
	if WorldMapData.terrain_to_dungeon_type(WorldMapData.TerrainType.HOSPITAL) != DungeonScript.BuildingType.HOSPITAL:
		ok = false
		push_error("[WorldMap] HOSPITAL 映射错误")
	if WorldMapData.terrain_to_dungeon_type(WorldMapData.TerrainType.SUPERMARKET) != DungeonScript.BuildingType.SUPERMARKET:
		ok = false
		push_error("[WorldMap] SUPERMARKET 映射错误")

	# === 持久化: 序列化往返保留已生成/已探索 ===
	WorldMapData.reset_map()
	WorldMapData.move_player_to(hx + 1, hy)
	WorldMapData.move_player_to(hx + 1, hy + 1)
	var snap_tiles: int = WorldMapData.tiles.size()
	var snap_explored: int = WorldMapData.explored.size()
	var pc_before: Vector2i = WorldMapData.player_cell
	var ser: Dictionary = WorldMapData.serialize()
	WorldMapData.reset_map()  # 清空
	WorldMapData.deserialize(ser)
	if WorldMapData.tiles.size() != snap_tiles:
		ok = false
		push_error("[WorldMap] 序列化后 tiles 数量不一致: %d vs %d" % [WorldMapData.tiles.size(), snap_tiles])
	if WorldMapData.explored.size() != snap_explored:
		ok = false
		push_error("[WorldMap] 序列化后 explored 数量不一致: %d vs %d" % [WorldMapData.explored.size(), snap_explored])
	if WorldMapData.player_cell != pc_before:
		ok = false
		push_error("[WorldMap] 序列化后 player_cell 不一致")

	print("=== 自动测试: 无限世界地图=", ok, " (应为 true) tiles=", WorldMapData.tiles.size(), " explored=", WorldMapData.explored.size())
