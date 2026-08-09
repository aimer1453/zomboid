extends Control

# ============================================================
# WorldMap (主地图 / 战略层) — 点格进入不同地形地点
# ============================================================
# 家 (HOME) 是其中一格; 院门出来即到此; 点"家"格回家园。
# 已探索格 → 直接点进入副本; 未探索的 "?" → 弹"侦察/进入"菜单。
# 侦察 = 仅开图 (reveal_neighbors), 不切场景; 进入 = 进副本。
# WorldMapData 是 autoload 单例, 直接用全局名 WorldMapData 访问 (含 const/enum/实例方法)。

const DungeonScript := preload("res://scripts/dungeons/dungeon_base.gd")

var grid_origin := Vector2(40, 320)
var cell_size := 80

## 格子节点容器 (侦察后只需重建此层, 不动标题/按钮)
var _cell_layer: Control = null
## 侦察/进入 弹出菜单
var _scout_menu: PopupMenu = null
## 待操作的目标格 (弹菜单时记录)
var _pending_cell: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_setup_cell_layer()
	_build_ui()
	if "--auto-test" in OS.get_cmdline_user_args():
		_run_auto_test()


func _setup_cell_layer() -> void:
	_cell_layer = Control.new()
	_cell_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cell_layer)

	_scout_menu = PopupMenu.new()
	_scout_menu.id_pressed.connect(_on_scout_menu_selected)
	add_child(_scout_menu)


func _build_ui() -> void:
	var title := Label.new()
	title.text = "世界地图 — 点击地点进入探索"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 40)
	title.size = Vector2(720, 40)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	add_child(title)

	var home_btn := Button.new()
	home_btn.text = "返回家园"
	home_btn.position = Vector2(540, 90)
	home_btn.size = Vector2(150, 40)
	home_btn.pressed.connect(_on_home_pressed)
	add_child(home_btn)

	var legend := Label.new()
	var parts: Array = []
	for t in WorldMapData.TERRAIN_NAMES:
		parts.append(WorldMapData.terrain_name(t))
	legend.text = "地形: " + " / ".join(parts)
	legend.add_theme_font_size_override("font_size", 12)
	legend.position = Vector2(20, 95)
	legend.size = Vector2(500, 30)
	legend.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	add_child(legend)

	_rebuild_cells()


func _rebuild_cells() -> void:
	for c in _cell_layer.get_children():
		c.free()
	for y in WorldMapData.GRID:
		for x in WorldMapData.GRID:
			if WorldMapData.is_revealed(x, y):
				_build_cell(x, y)


func _build_cell(x: int, y: int) -> void:
	var t: int = WorldMapData.terrain_at(x, y)
	var explored_cell: bool = WorldMapData.is_explored(x, y)
	var rect := ColorRect.new()
	rect.position = grid_origin + Vector2(x * cell_size, y * cell_size)
	rect.size = Vector2(cell_size, cell_size)
	var col: Color = WorldMapData.terrain_color(t)
	if not explored_cell:
		col = col.darkened(0.6)
	rect.color = col
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cell_layer.add_child(rect)

	var label := Label.new()
	if explored_cell:
		label.text = WorldMapData.terrain_name(t)
	else:
		label.text = "?"
	label.add_theme_font_size_override("font_size", 15)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = rect.position
	label.size = rect.size
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cell_layer.add_child(label)

	if t == WorldMapData.TerrainType.HOME and explored_cell:
		var star := Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", 22)
		star.position = rect.position + Vector2(4, 1)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cell_layer.add_child(star)


func _on_home_pressed() -> void:
	WorldMapData.enter_home()


func _input(event) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var lp := get_local_mouse_position()
		var gx := int((lp.x - grid_origin.x) / cell_size)
		var gy := int((lp.y - grid_origin.y) / cell_size)
		if gx >= 0 and gx < WorldMapData.GRID and gy >= 0 and gy < WorldMapData.GRID:
			if WorldMapData.is_revealed(gx, gy):
				_on_cell_clicked(gx, gy)


func _on_cell_clicked(x: int, y: int) -> void:
	# 已探索 → 直接进副本; 未探索 (?) → 弹侦察/进入菜单
	if WorldMapData.is_explored(x, y):
		print("[WorldMap] 进入: ", WorldMapData.terrain_name(WorldMapData.terrain_at(x, y)), " (", x, ",", y, ")")
		WorldMapData.enter_location(x, y)
		return
	_pending_cell = Vector2i(x, y)
	_scout_menu.clear()
	_scout_menu.add_item("侦察此地（仅开图）", 0)
	_scout_menu.add_item("进入探索（进副本）", 1)
	_scout_menu.popup_at_position(get_local_mouse_position())


## 菜单选择: 0=侦察, 1=进入
func _on_scout_menu_selected(id: int) -> void:
	if _pending_cell == Vector2i.ZERO:
		return
	var cx := _pending_cell.x
	var cy := _pending_cell.y
	if id == 0:
		_scout_cell(cx, cy)
	else:
		WorldMapData.enter_location(cx, cy)


## 侦察: 仅开图不切场景 (复用 reveal_neighbors)
func _scout_cell(x: int, y: int) -> void:
	WorldMapData.reveal_neighbors(x, y)
	_rebuild_cells()
	print("[WorldMap] 侦察: ", WorldMapData.terrain_name(WorldMapData.terrain_at(x, y)), " 已开图 (", x, ",", y, ")")


# --- 自动测试 (纯逻辑, 不切场景) ---

func _run_auto_test() -> void:
	var ok := true
	if WorldMapData.cells.size() != WorldMapData.GRID * WorldMapData.GRID:
		ok = false
		push_error("[WorldMap] 格子总数错误: ", WorldMapData.cells.size())

	# === 迷雾探索: 只显示已探索格 + 其上下左右邻居 ===
	WorldMapData.generate()  # 重置: HOME 已探索, 其余未探索
	var hx: int = WorldMapData.home_cell.x
	var hy: int = WorldMapData.home_cell.y
	if not WorldMapData.is_revealed(hx, hy):
		ok = false
		push_error("[WorldMap] 初始 HOME 应可见")
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for d: Vector2i in dirs:
		if not WorldMapData.is_revealed(hx + d.x, hy + d.y):
			ok = false
			push_error("[WorldMap] HOME 邻居应可见: " + str(hx + d.x) + "," + str(hy + d.y))
	if WorldMapData.is_revealed(0, 0):
		ok = false
		push_error("[WorldMap] 远处 (0,0) 不应可见")
	WorldMapData.mark_explored(hx, hy + 1)
	if not WorldMapData.is_revealed(hx, hy + 2):
		ok = false
		push_error("[WorldMap] 探索后外层 (hx,hy+2) 应解锁可见")
	if WorldMapData.is_revealed(0, 0):
		ok = false
		push_error("[WorldMap] (0,0) 仍不应可见")

	# === reveal_neighbors: 走到院门即点亮 HOME 四周邻居 (开图不必进副本) ===
	WorldMapData.generate()  # 重置
	WorldMapData.reveal_neighbors(hx, hy)
	if not WorldMapData.is_explored(hx, hy - 1) or not WorldMapData.is_explored(hx, hy + 1) \
			or not WorldMapData.is_explored(hx - 1, hy) or not WorldMapData.is_explored(hx + 1, hy):
		ok = false
		push_error("[WorldMap] reveal_neighbors 未点亮 HOME 四周邻居")
	if not WorldMapData.is_revealed(hx, hy - 2):
		ok = false
		push_error("[WorldMap] reveal_neighbors 后外圈 (hx,hy-2) 应解锁可见")
	if WorldMapData.is_revealed(0, 0):
		ok = false
		push_error("[WorldMap] 远处 (0,0) 仍不应可见")

	# === 侦察: 点 "?" 仅开图, 不进副本 ===
	WorldMapData.generate()
	WorldMapData.reveal_neighbors(hx, hy)  # HOME 四周已亮
	_scout_cell(hx, hy + 1)  # 侦察下邻居
	if not WorldMapData.is_explored(hx, hy + 1):
		ok = false
		push_error("[WorldMap] 侦察后 (hx,hy+1) 应已探索")
	if not WorldMapData.is_revealed(hx, hy + 2):
		ok = false
		push_error("[WorldMap] 侦察后外圈 (hx,hy+2) 应解锁可见")
	if WorldMapData.is_revealed(0, 0):
		ok = false
		push_error("[WorldMap] 远处 (0,0) 仍不应可见 (侦察不影响远处)")

	if WorldMapData.terrain_at(WorldMapData.home_cell.x, WorldMapData.home_cell.y) != WorldMapData.TerrainType.HOME:
		ok = false
		push_error("[WorldMap] home 格不是 HOME")
	if WorldMapData.terrain_to_dungeon_type(WorldMapData.TerrainType.HOSPITAL) != DungeonScript.BuildingType.HOSPITAL:
		ok = false
		push_error("[WorldMap] HOSPITAL 映射错误")
	if WorldMapData.terrain_to_dungeon_type(WorldMapData.TerrainType.SUPERMARKET) != DungeonScript.BuildingType.SUPERMARKET:
		ok = false
		push_error("[WorldMap] SUPERMARKET 映射错误")

	# === 精细掉落: 按家具类型 (用户反馈: 90%+ 太高, 同地点也分不同家具) ===
	var db: Node = DungeonScript.new()
	var FT = DungeonScript.FurnType
	# 药柜药品占比: 应明显高但非碾压 (0.45~0.78)
	var med_total := 0
	var med_med := 0
	for i in 5000:
		var id: String = db.pick_loot_by_furniture(FT.MED_CABINET)
		med_total += 1
		if id in ["bandage", "medkit", "antidote", "adrenaline", "painkiller"]:
			med_med += 1
	var med_ratio: float = float(med_med) / float(med_total)
	if med_ratio < 0.45 or med_ratio > 0.78:
		ok = false
		push_error("[WorldMap] 药柜药品占比异常: " + str(med_ratio))
	# 文件柜: 文件(doc/book)应占主导
	var file_total := 0
	var file_doc := 0
	for i in 3000:
		var fid: String = db.pick_loot_by_furniture(FT.FILE_CABINET)
		file_total += 1
		if fid in ["document", "book"]:
			file_doc += 1
	var file_ratio: float = float(file_doc) / float(file_total)
	if file_ratio < 0.35:
		ok = false
		push_error("[WorldMap] 文件柜文件占比过低: " + str(file_ratio))
	# 医院整体(按家具构成抽样): 分家具后药品占比应明显下降 (< 0.45)
	var hosp_list: Array = db.FURN_WEIGHTS_BY_BUILDING[db.BuildingType.HOSPITAL]
	var hosp_total := 0
	var hosp_med := 0
	for i in 6000:
		var hft: int = hosp_list[randi() % hosp_list.size()]
		var hid: String = db.pick_loot_by_furniture(hft)
		hosp_total += 1
		if hid in ["bandage", "medkit", "antidote", "adrenaline", "painkiller"]:
			hosp_med += 1
	var hosp_ratio: float = float(hosp_med) / float(hosp_total)
	if hosp_ratio > 0.45:
		ok = false
		push_error("[WorldMap] 医院整体药品占比过高(分家具后应下降): " + str(hosp_ratio))
	# 超市货架: 食物/水应占主导
	var sup_list: Array = db.FURN_WEIGHTS_BY_BUILDING[db.BuildingType.SUPERMARKET]
	var sup_total := 0
	var sup_food := 0
	for i in 4000:
		var sft: int = sup_list[randi() % sup_list.size()]
		var sid: String = db.pick_loot_by_furniture(sft)
		sup_total += 1
		if sid in ["canned_food", "water_pure", "bread", "soda", "chocolate"]:
			sup_food += 1
	var sup_ratio: float = float(sup_food) / float(sup_total)
	if sup_ratio < 0.6:
		ok = false
		push_error("[WorldMap] 超市食物占比过低: " + str(sup_ratio))

	print("=== 自动测试: 世界地图+家具掉落=", ok, " (应为 true) 药柜药=%.2f 文件柜文件=%.2f 医院整体药=%.2f 超市食物=%.2f" % [med_ratio, file_ratio, hosp_ratio, sup_ratio])
