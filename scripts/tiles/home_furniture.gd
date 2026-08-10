class_name HomeFurniture
extends Node2D

# ============================================================
# HomeFurniture — 家园功能性家具 (床/收集器/净化器/种植区/工作台)
# ============================================================
# 与容器家具 (Furniture) 不同: 不是"打开搜刮", 而是"点击交互"产生功能。
# 由 home_base 场景生成并注册到交互列表, 场景 _on_interact 按 kind 分发。

## 家具类型
enum Kind { BED, RAIN_COLLECTOR, PURIFIER, PLANTING_BED, WORKBENCH, GYM, CHEST }

## 家具类型 → 名称
const KIND_NAMES := {
	Kind.BED: "床",
	Kind.RAIN_COLLECTOR: "雨水收集器",
	Kind.PURIFIER: "雨水净化器",
	Kind.PLANTING_BED: "室内种植区",
	Kind.WORKBENCH: "工作台",
	Kind.GYM: "健身器材",
	Kind.CHEST: "储物箱",
}

var kind: Kind = Kind.WORKBENCH
var furniture_name: String = "家具"
var grid_pos: Vector2i = Vector2i.ZERO

## 功能状态 (各家具自定义)
var capacity: int = 0        # 收集器容量 / 种植区槽位
var stored: int = 0          # 收集器已积攒污染水 / 种植区已种下的植物进度 (0~100)
var plant_item: String = ""  # 种植区: 已种物品 id
var _tile_size: int = 32

## 交互结果提示 (场景读取后展示给玩家)
var last_message: String = ""


## 初始化: 指定类型与格子位置
func setup(p_kind: Kind, gp: Vector2i, tile_size: int) -> void:
	kind = p_kind
	furniture_name = KIND_NAMES.get(p_kind, "家具")
	grid_pos = gp
	_tile_size = tile_size
	position = Vector2(gp.x * tile_size + tile_size * 0.5, gp.y * tile_size + tile_size * 0.5)
	_build_visual()


func _build_visual() -> void:
	# 占位色块 (原始尺寸, 用户要求还原家具)
	var rect := ColorRect.new()
	rect.size = Vector2(_tile_size * 0.8, _tile_size * 0.8)
	rect.position = -rect.size / 2
	rect.color = _kind_color()
	add_child(rect)

	# 家具名标签: 居中在主体中心 (用户反馈: 像尸体一样标注是什么家具)
	var label := Label.new()
	label.text = _wrap_cjk(furniture_name, 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	# 状态标签 (收集器存量/种植进度): 主体下方
	var state := Label.new()
	state.name = "StateLabel"
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 8)
	state.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	state.position = Vector2(-_tile_size * 0.7, _tile_size * 0.5)
	add_child(state)


## 把中文文本按 per 个字插入换行, 让长标签在窄格内 2~3 字一行并居中
func _wrap_cjk(t: String, per: int = 3) -> String:
	if t.length() <= per:
		return t
	var out: String = ""
	for i in range(t.length()):
		if i > 0 and i % per == 0:
			out += "\n"
		out += t[i]
	return out


func _kind_color() -> Color:
	match kind:
		Kind.BED: return Color(0.45, 0.35, 0.6)
		Kind.RAIN_COLLECTOR: return Color(0.3, 0.5, 0.7)
		Kind.PURIFIER: return Color(0.25, 0.6, 0.55)
		Kind.PLANTING_BED: return Color(0.4, 0.6, 0.3)
		Kind.WORKBENCH: return Color(0.6, 0.5, 0.3)
		Kind.GYM: return Color(0.55, 0.45, 0.25)
		Kind.CHEST: return Color(0.62, 0.52, 0.32)
	return Color(0.5, 0.5, 0.5)


func _update_state_label(text: String) -> void:
	for child in get_children():
		if child is Label and child.name == "StateLabel":
			child.text = text


# --- 各家具功能 (由 home_base 调用) ---

## 雨水收集器: 下雨时积攒污染水 (WorldTime 每 tick 调用)
func collect_rain() -> bool:
	if kind != Kind.RAIN_COLLECTOR or stored >= capacity:
		return false
	if WorldTime and WorldTime.is_raining():
		stored = mini(stored + 1, capacity)
		_update_state_label("%d/%d" % [stored, capacity])
		return true
	return false


## 雨水收集器: 取走积攒的污染水 → 背包
func harvest_collector() -> int:
	var take := stored
	if take > 0:
		InventoryBackpack.try_add_item("water_polluted", take)
		stored = 0
		_update_state_label("0/%d" % capacity)
		last_message = "收集到 %d 瓶污染水" % take
	return take


## 种植区: 种植 (消耗 1 种子 + 1 净水)
func plant(seed_id: String) -> bool:
	if kind != Kind.PLANTING_BED or plant_item != "":
		return false
	if not InventoryBackpack.remove_item(seed_id, 1):
		last_message = "没有种子"
		return false
	if not InventoryBackpack.remove_item("water_pure", 1):
		InventoryBackpack.try_add_item(seed_id, 1)  # 退还种子
		last_message = "需要 1 瓶净水浇灌"
		return false
	plant_item = seed_id
	stored = 0
	_update_state_label("生长 0%")
	last_message = "已种下, 等待生长"
	return true


## 种植区: 世界时间推进 → 生长进度
func grow_plant(elapsed_hours: float) -> void:
	if kind != Kind.PLANTING_BED or plant_item == "":
		return
	stored = mini(int(stored + elapsed_hours * 2.0), 100)  # 约 50 小时成熟
	_update_state_label("生长 %d%%" % stored)


## 种植区: 收获成熟的作物
func harvest_plant() -> Dictionary:
	if kind != Kind.PLANTING_BED or plant_item == "":
		return {"success": false, "message": "没有作物"}
	if stored < 100:
		return {"success": false, "message": "作物还没成熟 (%d%%)" % stored}
	var harvest_id := _harvest_of(plant_item)
	InventoryBackpack.try_add_item(harvest_id, randi_range(2, 3))
	plant_item = ""
	stored = 0
	_update_state_label("空闲")
	last_message = "收获成功!"
	return {"success": true, "message": "收获 %s" % harvest_id}


func _harvest_of(seed_id: String) -> String:
	match seed_id:
		"seed_vegetable": return "canned_food"
	return "canned_food"


## 净化器: 污染水 → 净水 (消耗 2 污染水 + 时间)
func purify() -> Dictionary:
	if kind != Kind.PURIFIER:
		return {"success": false, "message": "无法使用"}
	if InventoryBackpack.count_item("water_polluted") < 2:
		return {"success": false, "message": "需要 2 瓶污染水"}
	InventoryBackpack.remove_item("water_polluted", 2)
	InventoryBackpack.try_add_item("water_pure", 2)
	last_message = "净化出 2 瓶净水"
	return {"success": true, "message": "净化成功: 2 瓶净水"}


## 床: 睡觉 (恢复睡眠值+HP, 恢复量按床等级, 消耗世界时间)
## 床等级: 1=草席 / 2=木床 / 3=软床 (升级提升恢复效率)
func sleep_on_bed(player: Node) -> Dictionary:
	if kind != Kind.BED or not player or not player.has_method("take_rest"):
		return {"success": false, "message": "无法休息"}
	var restore := _bed_sleep_restore()
	if player.take_rest(WorldTime.SLEEP_TIME_HOURS, restore):
		last_message = "休息 6 小时, 精力 +%d" % int(restore)
		return {"success": true, "message": "休息完毕 (精力 +%d)" % int(restore)}
	return {"success": false, "message": "休息失败"}


## 床等级 (1~3)
var bed_level: int = 1

## 床等级名
const BED_LEVEL_NAMES := {1: "草席", 2: "木床", 3: "软床"}

## 床等级 → 每次睡觉恢复的睡眠值
const BED_SLEEP_RESTORE := {1: 40.0, 2: 60.0, 3: 80.0}

## 床等级 → 升级所需材料 (item_id → 数量)
const BED_UPGRADE_COST := {
	1: {"zombie_flesh": 3, "wood": 2},
	2: {"zombie_flesh": 5, "wood": 4, "cloth": 2},
}


func _bed_sleep_restore() -> float:
	return BED_SLEEP_RESTORE.get(bed_level, 60.0)


## 升级床: 消耗材料 → 床等级 +1
func upgrade_bed() -> Dictionary:
	if kind != Kind.BED:
		return {"success": false, "message": "无法升级"}
	if bed_level >= 3:
		return {"success": false, "message": "已经是最高级床"}
	var cost: Dictionary = BED_UPGRADE_COST.get(bed_level, {})
	for item_id in cost:
		if InventoryBackpack.count_item(item_id) < int(cost[item_id]):
			return {"success": false, "message": "升级需要 %s x%d (材料不足)" % [item_id, int(cost[item_id])]}
	for item_id in cost:
		InventoryBackpack.remove_item(item_id, int(cost[item_id]))
	bed_level += 1
	_update_state_label("Lv.%d %s" % [bed_level, BED_LEVEL_NAMES.get(bed_level, "")])
	last_message = "床升级为 %s! 睡眠恢复提升" % BED_LEVEL_NAMES.get(bed_level, "Lv.%d" % bed_level)
	return {"success": true, "message": last_message}


## 工作台: 预留 (Phase 后续: 制作配方)
func workbench_interact() -> Dictionary:
	last_message = "工作台: 制作功能开发中"
	return {"success": false, "message": "制作功能开发中"}
