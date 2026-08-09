extends Node

# ============================================================
# InventoryBackpack — 重量制背包 (替代原方格背包)
# ============================================================
# 简单列表式背包: item_id -> count。
# 每个物品有重量 (ItemData.weight), 角色有负重上限 max_weight。
# 放不下时返回 overflow, 由 UI 弹超重提示。

const DEFAULT_MAX_WEIGHT := 10.0  # 初始负重 10kg (用户反馈: 50kg 太多, 靠锻炼/背包提升)
## 背包默认 4x4 = 16 格 (每种物品占 1 格, 可堆叠)
const MAX_SLOTS := 16

## 物品: item_id -> count
var items: Dictionary = {}
## 负重上限
var max_weight: float = DEFAULT_MAX_WEIGHT
## 装备背包类物品带来的额外负重加成 (由 Character 穿戴时更新)
var extra_weight_bonus: float = 0.0
## 当前总负重
var total_weight: float = 0.0
## 装备磨损度: item_id -> current (0 = 未磨损; max 由 DataManager.item.properties["durability"] 提供, 0=无限)
var item_durability: Dictionary = {}

signal inventory_changed()
signal weight_overflow(over_weight: float)


## 物品最大耐久 (0 = 无限/不可磨损)
func get_max_durability(item_id: String) -> int:
	var item := DataManager.get_item(item_id)
	if not item:
		return 0
	return int(item.properties.get("durability", 0))


## 当前磨损度 (0 = 未磨损)
func get_durability(item_id: String) -> int:
	return int(item_durability.get(item_id, 0))


## 耐久比例 0.0~1.0 (0 = 无限耐久 → 恒 1.0)
func get_durability_ratio(item_id: String) -> float:
	var max_du := get_max_durability(item_id)
	if max_du <= 0:
		return 1.0
	return clampf(1.0 - float(get_durability(item_id)) / float(max_du), 0.0, 1.0)


## 磨损物品 (amount 点); 超过最大耐久 clamp。无耐久定义(0)则忽略
func damage_item(item_id: String, amount: int = 1) -> void:
	var max_du := get_max_durability(item_id)
	if max_du <= 0 or amount <= 0:
		return
	var cur := get_durability(item_id) + amount
	item_durability[item_id] = mini(cur, max_du)
	inventory_changed.emit()


## 交易价值 (含磨损折扣: 磨损越多价值越低, 商人交易用)
func get_item_value(item_id: String) -> int:
	var item := DataManager.get_item(item_id)
	if not item:
		return 0
	var base: int = item.value
	var ratio := get_durability_ratio(item_id)
	return maxi(int(round(base * (0.3 + 0.7 * ratio))), 1)


func _ready() -> void:
	print("[InventoryBackpack] 重量制背包初始化, 负重上限 ", max_weight, ", 格子 ", MAX_SLOTS)


# --- 查询 ---

func get_total_weight() -> float:
	return total_weight

func get_max_weight() -> float:
	return max_weight + extra_weight_bonus


## 装备背包类物品时更新负重加成 (Character 穿戴/卸下时调用)
func set_extra_weight_bonus(bonus: float) -> void:
	extra_weight_bonus = maxf(bonus, 0.0)
	inventory_changed.emit()

func count_item(item_id: String) -> int:
	return items.get(item_id, 0)

func has_item(item_id: String) -> bool:
	return items.has(item_id)


## 物品重量 (单件)
func get_item_weight(item_id: String) -> float:
	var item := DataManager.get_item(item_id)
	return item.weight if item else 0.0


## 全部物品列表: [{item_id, count, weight(总), name, value, rarity}]
func list_items() -> Array:
	var result: Array = []
	for id in items:
		var count: int = items[id]
		var item := DataManager.get_item(id)
		result.append({
			"item_id": id,
			"count": count,
			"name": item.name if item else id,
			"weight": (item.weight if item else 0.0) * count,
			"unit_weight": item.weight if item else 0.0,
			"value": item.value if item else 0,
			"type": item.type if item else 0,
			"description": item.description if item else "",
			"rarity": item.rarity if item else 0,
		})
	return result


# --- 增删 ---

## 尝试放入物品, 负重不足返回 overflow, 格子满返回 slots_full
func try_add_item(item_id: String, count: int = 1) -> Dictionary:
	var item := DataManager.get_item(item_id)
	if not item:
		return {"success": false, "error": "未知物品: " + item_id}

	# 格子限制: 新物品类型且背包已满 → 放不下
	if not items.has(item_id) and items.size() >= MAX_SLOTS:
		return {"success": false, "error": "slots_full", "slots_full": true}

	var added_weight := item.weight * count
	if total_weight + added_weight > max_weight + 0.001:
		weight_overflow.emit(total_weight + added_weight - max_weight)
		return {"success": false, "error": "weight", "overflow": true}

	items[item_id] = items.get(item_id, 0) + count
	total_weight += added_weight
	inventory_changed.emit()
	return {"success": true}


## 强制放入 (无视负重/格子上限): 用于卸下装备/读档恢复, 避免物品丢失 (超重状态允许存在, 不能再拾取)
func force_add_item(item_id: String, count: int = 1) -> void:
	var item := DataManager.get_item(item_id)
	items[item_id] = items.get(item_id, 0) + count
	total_weight += (item.weight if item else 0.0) * count
	inventory_changed.emit()


## 移除物品, 返回实际移除数量
func remove_item(item_id: String, count: int = 1) -> int:
	var have: int = items.get(item_id, 0)
	if have <= 0:
		return 0
	var removed: int = mini(count, have)
	items[item_id] = have - removed
	var item := DataManager.get_item(item_id)
	total_weight = maxf(total_weight - (item.weight if item else 0.0) * removed, 0.0)
	if items[item_id] <= 0:
		items.erase(item_id)
	inventory_changed.emit()
	return removed


# --- 序列化 ---

func serialize() -> Dictionary:
	return {
		"items": items,
		"max_weight": max_weight,
		"total_weight": total_weight,
		"item_durability": item_durability,
	}


func deserialize(data: Dictionary) -> void:
	items = data.get("items", {})
	max_weight = data.get("max_weight", DEFAULT_MAX_WEIGHT)
	total_weight = data.get("total_weight", 0.0)
	item_durability = data.get("item_durability", {})
	inventory_changed.emit()
