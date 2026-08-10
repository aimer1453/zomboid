extends Node

# ============================================================
# BuildingManager — 建造/研究系统 (autoload 单例)
# ============================================================
# 家园建造需要"从外面收集的素材": 木材/钉子/废金属/布料等.
# 流程: 探索副本搜刮素材 → 在工作台研究蓝图(消耗素材解锁) → 建造家具(消耗素材放置).
# 状态跨场景保留 (autoload), 并通过 GameManager 存档持久化.
# 注意: 本脚本即 autoload 单例, 全局名为 BuildingManager; 不要再加 class_name 以免遮蔽单例.
#       其他 autoload (InventoryBackpack/DataManager) 直接以全局名引用, 不要 preload 脚本后调非静态方法.

const HF := preload("res://scripts/tiles/home_furniture.gd")

## 蓝图: kind(int) -> {name, desc, build:Dictionary, research:Dictionary, preknown:bool}
## build/research: item_id -> 数量
const BLUEPRINTS := {
	HF.Kind.WORKBENCH: {
		"name": "工作台",
		"desc": "建造与研究的中心, 点击它打开建造/研究面板",
		"build": {"wood": 4, "nail": 2},
		"research": {},
		"preknown": true,
	},
	HF.Kind.CHEST: {
		"name": "储物箱",
		"desc": "存放物品的容器 (可建造, 点击打开存取)",
		"build": {"wood": 3, "nail": 2},
		"research": {"wood": 1, "nail": 1},
	},
	HF.Kind.BED: {
		"name": "床",
		"desc": "休息恢复精力与生命 (可升级)",
		"build": {"wood": 3, "cloth": 2},
		"research": {"wood": 2},
	},
	HF.Kind.GYM: {
		"name": "健身器材",
		"desc": "锻炼提升体力上限",
		"build": {"wood": 4, "metal_scrap": 2},
		"research": {"wood": 2, "nail": 1},
	},
	HF.Kind.PLANTING_BED: {
		"name": "种植区",
		"desc": "消耗种子与净水种植蔬菜",
		"build": {"wood": 3, "cloth": 2},
		"research": {"wood": 1, "cloth": 1},
	},
	HF.Kind.RAIN_COLLECTOR: {
		"name": "雨水收集器",
		"desc": "下雨时积攒污染水 (需露天放置)",
		"build": {"wood": 4, "metal_scrap": 2},
		"research": {"wood": 2, "metal_scrap": 1},
	},
	HF.Kind.PURIFIER: {
		"name": "雨水净化器",
		"desc": "将污染水净化为净水",
		"build": {"wood": 3, "metal_scrap": 3, "nail": 2},
		"research": {"wood": 3, "metal_scrap": 2, "nail": 1},
	},
}

## 已研究蓝图: kind(int) -> true
var researched: Dictionary = {}
## 已建造家具: [{kind, x, y}]
var built: Array = []
## 家园房间扩建次数 (home_base 读写, 随存档持久化; 读档后按此重建房间大小)
var room_expansions: int = 0


func _ready() -> void:
	reset()


## 新游戏: 清空全部状态, 仅保留 preknown 蓝图 (工作台)
func reset() -> void:
	researched.clear()
	built.clear()
	room_expansions = 0
	for kind in BLUEPRINTS:
		if BLUEPRINTS[kind].get("preknown", false):
			researched[kind] = true


func is_researched(kind: int) -> bool:
	return researched.has(kind)


func bp_name(kind: int) -> String:
	return BLUEPRINTS.get(kind, {}).get("name", "未知家具")


func build_cost(kind: int) -> Dictionary:
	return BLUEPRINTS.get(kind, {}).get("build", {})


func research_cost(kind: int) -> Dictionary:
	return BLUEPRINTS.get(kind, {}).get("research", {})


## 是否买得起某成本 (素材来自外部搜刮)
func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if InventoryBackpack.count_item(id) < int(cost[id]):
			return false
	return true


## 成本文案: "木材×3、钉子×2"
func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for id in cost:
		var item = DataManager.get_item(id)
		var nm: String = item.name if item else id
		parts.append("%s×%d" % [nm, int(cost[id])])
	return ("、").join(parts) if not parts.is_empty() else "免费"


## 研究蓝图: 消耗 research 材料, 标记解锁
func research(kind: int) -> Dictionary:
	if not BLUEPRINTS.has(kind):
		return {"success": false, "message": "未知蓝图"}
	if researched.has(kind):
		return {"success": false, "message": "已研究过"}
	var cost: Dictionary = research_cost(kind)
	if not can_afford(cost):
		return {"success": false, "message": "材料不足: 需要 " + cost_text(cost)}
	for id in cost:
		InventoryBackpack.remove_item(id, int(cost[id]))
	researched[kind] = true
	return {"success": true, "message": "研究完成: " + bp_name(kind)}


## 该格是否已有建造
func is_built_at(cell: Vector2i) -> bool:
	for b in built:
		if b.x == cell.x and b.y == cell.y:
			return true
	return false


## 提交建造: 校验已研究 + 同格未建 + 买得起, 消耗材料并记录
func commit_build(kind: int, cell: Vector2i) -> Dictionary:
	if not BLUEPRINTS.has(kind):
		return {"success": false, "message": "未知蓝图"}
	if not researched.has(kind):
		return {"success": false, "message": "尚未研究该蓝图"}
	if is_built_at(cell):
		return {"success": false, "message": "该位置已建造"}
	var cost: Dictionary = build_cost(kind)
	if not can_afford(cost):
		return {"success": false, "message": "材料不足: 需要 " + cost_text(cost)}
	for id in cost:
		InventoryBackpack.remove_item(id, int(cost[id]))
	built.append({"kind": kind, "x": cell.x, "y": cell.y})
	return {"success": true, "message": "建造完成: " + bp_name(kind)}


# --- 序列化 (GameManager 存盘调用) ---

func serialize() -> Dictionary:
	return {
		"researched": researched.keys(),
		"built": built,
		"room_expansions": room_expansions,
	}


func deserialize(data: Dictionary) -> void:
	researched.clear()
	built.clear()
	room_expansions = int(data.get("room_expansions", 0))
	for k in data.get("researched", []):
		researched[int(k)] = true
	# 保证工作台始终可用
	if BLUEPRINTS.get(HF.Kind.WORKBENCH, {}).get("preknown", false):
		researched[HF.Kind.WORKBENCH] = true
	for b in data.get("built", []):
		if b is Dictionary:
			built.append({"kind": int(b.get("kind", 0)), "x": int(b.get("x", 0)), "y": int(b.get("y", 0))})
