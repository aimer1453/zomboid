extends Node

# ============================================================
# DataManager — 物品、技能、配方数据库 + 存档文件操作
# ============================================================

const SAVE_DIR := "user://saves/"

## 物品类型 (装备类: 武器/防具/背包/饰品; 其他: 消耗品/材料/弹药/蓝图/任务道具)
enum ItemType { CONSUMABLE, WEAPON, ARMOR, MATERIAL, KEY_ITEM, AMMO, BLUEPRINT, BACKPACK, TRINKET }

## 稀有度 (决定掉落边框颜色: 普通灰 / 优秀绿 / 稀有蓝 / 史诗紫 / 传说金)
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## 稀有度 → 边框颜色 (UI 统一从这里取, 禁止散落定义)
const RARITY_COLORS := {
	Rarity.COMMON: Color(0.62, 0.62, 0.62),
	Rarity.UNCOMMON: Color(0.35, 0.85, 0.45),
	Rarity.RARE: Color(0.35, 0.6, 0.95),
	Rarity.EPIC: Color(0.75, 0.45, 0.95),
	Rarity.LEGENDARY: Color(0.95, 0.75, 0.25),
}

## 稀有度中文名
const RARITY_NAMES := {
	Rarity.COMMON: "普通",
	Rarity.UNCOMMON: "优秀",
	Rarity.RARE: "稀有",
	Rarity.EPIC: "史诗",
	Rarity.LEGENDARY: "传说",
}

## 装备槽位 (equip_slot 用): 武器 / 防具 / 背包 / 饰品
const EQUIP_SLOT_WEAPON := "weapon"
const EQUIP_SLOT_ARMOR := "armor"
const EQUIP_SLOT_BACKPACK := "backpack"
const EQUIP_SLOT_TRINKET := "trinket"

## 物品数据类
class ItemData:
	var id: String
	var name: String
	var type: ItemType
	var description: String
	var size: Vector2i
	var stack_max: int
	var icon_path: String
	var properties: Dictionary
	var weight: float   # 单件重量 (负重制背包)
	var value: int      # 价值 (交易/售价用)
	var equip_slot: String  # 装备槽位 (weapon/armor/backpack; 非装备为空)
	var rarity: Rarity = Rarity.COMMON  # 稀有度 (掉落边框颜色)

	func _init(p_id: String, p_name: String, p_type: ItemType,
			   p_desc: String = "", p_size: Vector2i = Vector2i(1, 1),
			   p_stack: int = 99, p_icon: String = "", p_props: Dictionary = {},
			   p_rarity: Rarity = Rarity.COMMON, p_weight: float = -1.0):
		id = p_id; name = p_name; type = p_type; description = p_desc
		size = p_size; stack_max = p_stack; icon_path = p_icon; properties = p_props
		weight = p_weight if p_weight >= 0.0 else _default_weight(p_type)
		value = _default_value(p_type)
		equip_slot = _default_equip_slot(p_type)
		rarity = p_rarity

	## 按类型推断装备槽位 (非装备返回 "")
	static func _default_equip_slot(t: ItemType) -> String:
		match t:
			ItemType.WEAPON: return EQUIP_SLOT_WEAPON
			ItemType.ARMOR: return EQUIP_SLOT_ARMOR
			ItemType.BACKPACK: return EQUIP_SLOT_BACKPACK
			ItemType.TRINKET: return EQUIP_SLOT_TRINKET
		return ""

	## 按类型给默认重量 (kg)
	static func _default_weight(t: ItemType) -> float:
		match t:
			ItemType.CONSUMABLE: return 0.5
			ItemType.WEAPON: return 3.0
			ItemType.ARMOR: return 4.0
			ItemType.MATERIAL: return 1.5
			ItemType.KEY_ITEM: return 0.1
			ItemType.AMMO: return 0.2
			ItemType.BLUEPRINT: return 0.5
			ItemType.BACKPACK: return 2.0
			ItemType.TRINKET: return 0.3
		return 0.5

	## 按类型给默认价值
	static func _default_value(t: ItemType) -> int:
		match t:
			ItemType.CONSUMABLE: return 15
			ItemType.WEAPON: return 80
			ItemType.ARMOR: return 120
			ItemType.MATERIAL: return 10
			ItemType.KEY_ITEM: return 200
			ItemType.AMMO: return 5
			ItemType.BLUEPRINT: return 300
			ItemType.BACKPACK: return 150
		return 10


var _items: Dictionary = {}
var _abilities: Dictionary = {}
var _building_recipes: Dictionary = {}


func _ready() -> void:
	print("[DataManager] 初始化数据库...")
	_register_default_items()
	_register_default_abilities()
	_validate_data_consistency()


# --- 物品数据库 ---

func _register_default_items() -> void:
	# 基础消耗品 (普通)
	_add_item(ItemData.new("bandage", "绷带", ItemType.CONSUMABLE, "止血包扎",
		Vector2i(1,1), 20, "", {"heal": 15}))
	_add_item(ItemData.new("medkit", "急救包", ItemType.CONSUMABLE, "大量恢复生命",
		Vector2i(1,2), 5, "", {"heal": 50}, Rarity.UNCOMMON))
	_add_item(ItemData.new("antidote", "抗污染药剂", ItemType.CONSUMABLE, "降低污染值",
		Vector2i(1,1), 10, "", {"reduce_pollution": 20}, Rarity.UNCOMMON))
	_add_item(ItemData.new("canned_food", "罐头食品", ItemType.CONSUMABLE, "充饥",
		Vector2i(1,1), 10, "", {"food": 25}))
	_add_item(ItemData.new("bread", "面包", ItemType.CONSUMABLE, "新鲜面包, 充饥+心情",
		Vector2i(1,1), 20, "", {"food": 35, "morale": 5}, Rarity.COMMON))
	_add_item(ItemData.new("water_pure", "净水", ItemType.CONSUMABLE, "干净的饮用水",
		Vector2i(1,1), 20, "", {"water": 20}, Rarity.COMMON, 1.0))  # 1L 瓶装水 ≈ 1kg
	_add_item(ItemData.new("soda", "汽水", ItemType.CONSUMABLE, "冰镇汽水, 解渴+心情",
		Vector2i(1,1), 15, "", {"water": 12, "morale": 8}, Rarity.UNCOMMON, 0.5))
	_add_item(ItemData.new("chocolate", "巧克力", ItemType.CONSUMABLE, "甜食, 大幅提升心情",
		Vector2i(1,1), 10, "", {"food": 10, "morale": 20}, Rarity.UNCOMMON, 0.2))
	_add_item(ItemData.new("water_polluted", "污染水", ItemType.MATERIAL, "雨水收集的异变之水",
		Vector2i(1,1), 30, "", {}, Rarity.COMMON, 1.0))  # 1L ≈ 1kg
	# 肾上腺素: 快速回复精力 (AP+睡眠合并), 战斗应急用
	_add_item(ItemData.new("adrenaline", "肾上腺素", ItemType.CONSUMABLE, "快速回复精力, 战斗应急",
		Vector2i(1,1), 5, "", {"energy_restore": 40}, Rarity.UNCOMMON))
	_add_item(ItemData.new("energy_drink", "能量饮料", ItemType.CONSUMABLE, "回复少量精力",
		Vector2i(1,1), 10, "", {"energy_restore": 20}, Rarity.COMMON))

	# 饰品 (TRINKET): 提供视野/射程/命中/暴击/幸运加成 (durability=耐久, 磨损影响价值)
	_add_item(ItemData.new("tactical_scope", "战术瞄准镜", ItemType.TRINKET, "提升视野范围和射击精度",
		Vector2i(1,1), 1, "", {"vision_bonus": 3, "range_bonus": 1, "accuracy_bonus": 0.1, "durability": 40}, Rarity.RARE))
	_add_item(ItemData.new("sharpening_glove", "磨刀手套", ItemType.TRINKET, "增加近战武器的攻击范围",
		Vector2i(1,1), 1, "", {"range_bonus": 1, "durability": 30}, Rarity.UNCOMMON))
	_add_item(ItemData.new("lucky_charm", "幸运吊坠", ItemType.TRINKET, "增加幸运值",
		Vector2i(1,1), 1, "", {"luck_bonus": 5}, Rarity.RARE))
	_add_item(ItemData.new("combat_visor", "战斗护目镜", ItemType.TRINKET, "提升命中率和暴击率",
		Vector2i(1,1), 1, "", {"accuracy_bonus": 0.15, "crit_bonus": 0.1, "durability": 35}, Rarity.UNCOMMON))

	# 武器 (战斗数值唯一真源在 weapon.gd 工厂, 此处只存元数据: ammo_type 供弹药系统; 见 _validate_data_consistency)
	# 稀有度: 近战普通/优秀, 枪械稀有+, 与武器伤害/获取难度匹配
	# durability: 磨损度 (攻击消耗, 磨损后攻击力下降, 交易价值折扣)
	_add_item(ItemData.new("rusty_knife", "生锈小刀", ItemType.WEAPON, "锈迹斑斑的小刀, 丧尸捡来的",
		Vector2i(1,1), 1, "", {"durability": 20}, Rarity.COMMON))
	_add_item(ItemData.new("knife", "战术匕首", ItemType.WEAPON, "近战利器",
		Vector2i(1,2), 1, "", {"durability": 40}, Rarity.UNCOMMON))
	_add_item(ItemData.new("crowbar", "撬棍", ItemType.WEAPON, "多功能工具, 也能当不错的武器",
		Vector2i(1,2), 1, "", {"durability": 50}, Rarity.UNCOMMON))
	_add_item(ItemData.new("baseball_bat", "棒球棍", ItemType.WEAPON, "结实的棒球棍, 挥舞起来很有威力",
		Vector2i(1,3), 1, "", {"durability": 30}, Rarity.COMMON))
	_add_item(ItemData.new("pistol", "手枪", ItemType.WEAPON, "9mm 半自动手枪",
		Vector2i(1,2), 1, "", {"ammo_type": "9mm", "durability": 35}, Rarity.RARE))
	_add_item(ItemData.new("rifle", "突击步枪", ItemType.WEAPON, "5.56mm 突击步枪",
		Vector2i(1,3), 1, "", {"ammo_type": "556", "durability": 45}, Rarity.EPIC))
	_add_item(ItemData.new("shotgun", "霰弹枪", ItemType.WEAPON, "近距离高伤害",
		Vector2i(1,3), 1, "", {"ammo_type": "shotgun", "durability": 30}, Rarity.RARE))
	_add_item(ItemData.new("bow", "复合弓", ItemType.WEAPON, "无声远程武器",
		Vector2i(1,3), 1, "", {"ammo_type": "arrow", "durability": 25}, Rarity.RARE))

	# 护甲 (durability=耐久, 被击中磨损; 磨损后防御按比例衰减)
	_add_item(ItemData.new("torn_clothes", "破旧衣衫", ItemType.ARMOR, "丧尸身上扒下来的破布衣服, 几乎没防护",
		Vector2i(1,1), 1, "", {"defense": 1, "durability": 15}, Rarity.COMMON))
	_add_item(ItemData.new("torn_pants", "破旧长裤", ItemType.ARMOR, "磨损严重的长裤, 聊胜于无",
		Vector2i(1,1), 1, "", {"defense": 1, "durability": 15}, Rarity.COMMON))
	_add_item(ItemData.new("dirty_shoes", "脏旧鞋子", ItemType.ARMOR, "沾满污渍的旧鞋, 勉强能穿",
		Vector2i(1,1), 1, "", {"defense": 1, "durability": 15}, Rarity.COMMON))
	_add_item(ItemData.new("leather_vest", "皮背心", ItemType.ARMOR, "基础防护",
		Vector2i(2,2), 1, "", {"defense": 5, "durability": 30}, Rarity.UNCOMMON))
	_add_item(ItemData.new("kevlar", "防弹衣", ItemType.ARMOR, "军用级防护",
		Vector2i(2,2), 1, "", {"defense": 15, "durability": 60}, Rarity.EPIC))
	_add_item(ItemData.new("combat_helmet", "战术头盔", ItemType.ARMOR, "头部防护",
		Vector2i(1,1), 1, "", {"defense": 6, "head": true, "durability": 25}, Rarity.RARE))

	# 背包类装备 (提升负重上限)
	_add_item(ItemData.new("backpack_small", "小背包", ItemType.BACKPACK, "+10kg 负重",
		Vector2i(1,1), 1, "", {"weight_bonus": 10}, Rarity.UNCOMMON))
	_add_item(ItemData.new("backpack_large", "大背包", ItemType.BACKPACK, "+25kg 负重",
		Vector2i(2,1), 1, "", {"weight_bonus": 25}, Rarity.RARE))
	_add_item(ItemData.new("backpack_tactical", "战术背包", ItemType.BACKPACK, "+20kg 负重, 取物更快",
		Vector2i(2,1), 1, "", {"weight_bonus": 20}, Rarity.EPIC))

	# 弹药 (普通)
	_add_item(ItemData.new("ammo_9mm", "9mm 子弹", ItemType.AMMO, "手枪弹药",
		Vector2i(1,1), 50, "", {"ammo_type": "9mm"}))
	_add_item(ItemData.new("ammo_556", "5.56mm 子弹", ItemType.AMMO, "步枪弹药",
		Vector2i(1,1), 30, "", {"ammo_type": "556"}))
	_add_item(ItemData.new("ammo_shotgun", "霰弹", ItemType.AMMO, "霰弹枪弹药",
		Vector2i(1,1), 20, "", {"ammo_type": "shotgun"}))
	_add_item(ItemData.new("arrow", "箭矢", ItemType.AMMO, "弓箭弹药",
		Vector2i(1,1), 30, "", {"ammo_type": "arrow"}))

	# 关键物品 (晶石按稀有度递进, 蓝图传说)
	_add_item(ItemData.new("crystal_shard", "晶石碎片", ItemType.KEY_ITEM, "击杀普通感染者掉落",
		Vector2i(1,1), 99, "", {"crystal_value": 5}, Rarity.UNCOMMON))
	_add_item(ItemData.new("crystal_smooth", "能量晶石", ItemType.KEY_ITEM, "击杀特殊感染者掉落",
		Vector2i(1,1), 99, "", {"crystal_value": 15}, Rarity.RARE))
	_add_item(ItemData.new("crystal_cluster", "晶簇", ItemType.KEY_ITEM, "精英感染者掉落",
		Vector2i(1,1), 30, "", {"crystal_value": 35}, Rarity.EPIC))
	_add_item(ItemData.new("crystal_huge", "大能量晶石", ItemType.KEY_ITEM, "Boss掉落",
		Vector2i(1,1), 10, "", {"crystal_value": 60}, Rarity.LEGENDARY))
	_add_item(ItemData.new("zombie_flesh", "丧尸血肉", ItemType.MATERIAL, "搜刮尸体获得, 制作/出售材料",
		Vector2i(1,1), 30))
	_add_item(ItemData.new("wood", "木材", ItemType.MATERIAL, "基础建材, 升级家具/制作使用",
		Vector2i(1,1), 50, "", {}, Rarity.COMMON))
	_add_item(ItemData.new("cloth", "布料", ItemType.MATERIAL, "缝纫材料, 升级软家具使用",
		Vector2i(1,1), 40, "", {}, Rarity.COMMON))
	_add_item(ItemData.new("nail", "钉子", ItemType.MATERIAL, "固定建材, 建造家具/加固使用",
		Vector2i(1,1), 60, "", {}, Rarity.COMMON))
	_add_item(ItemData.new("metal_scrap", "废金属", ItemType.MATERIAL, "从废墟/机械拆解, 建造金属家具使用",
		Vector2i(1,1), 40, "", {}, Rarity.COMMON))
	_add_item(ItemData.new("seed_vegetable", "蔬菜种子", ItemType.MATERIAL, "可在室内种植",
		Vector2i(1,1), 20))
	_add_item(ItemData.new("blueprint_purifier", "雨水净化器蓝图", ItemType.BLUEPRINT, "解锁雨水净化器",
		Vector2i(1,1), 1, "", {}, Rarity.LEGENDARY))


func _add_item(item: ItemData) -> void:
	_items[item.id] = item


# --- 数据一致性校验 (P0-1: 防双数据源漂移) ---
# 物品表与 weapon.gd 武器工厂是两套定义, 靠 item_id 硬关联。
# 本函数在启动时校验: 物品表里每把 WEAPON 都必须在武器工厂里有对应,
# 且武器工厂里每把武器都能在物品表里找到物品 (双向完整, 数值由武器工厂为准)。
# 发现漂移立即 push_error, 让"改了不生效"的 bug 在启动时就暴露。

func _validate_data_consistency() -> void:
	var weapon_factory := load("res://scripts/items/weapon.gd")
	if not weapon_factory:
		push_error("[DataManager] 校验失败: 无法加载 weapon.gd")
		return
	var all_weapons: Dictionary = weapon_factory.all_weapons()
	var item_ids: Array = _items.keys()
	var missing_in_factory: Array = []
	var missing_in_items: Array = []

	for item_id in item_ids:
		var item: ItemData = _items[item_id]
		if item.type == ItemType.WEAPON and not all_weapons.has(item_id):
			missing_in_factory.append(item_id)

	for weapon_id in all_weapons:
		if not _items.has(weapon_id):
			missing_in_items.append(weapon_id)

	if not missing_in_factory.is_empty() or not missing_in_items.is_empty():
		if not missing_in_factory.is_empty():
			push_error("[DataManager] 数据漂移: 物品表有武器但武器工厂缺失: ", missing_in_factory)
		if not missing_in_items.is_empty():
			push_error("[DataManager] 数据漂移: 武器工厂有武器但物品表缺失: ", missing_in_items)
		push_error("[DataManager] 请同步 物品表(data_manager.gd) 与 武器工厂(weapon.gd) 的 weapon_id!")
	else:
		print("[DataManager] 数据一致性校验通过: ", all_weapons.size(), " 把武器双向映射完整")


func get_item(id: String) -> ItemData:
	return _items.get(id)


## 获取物品图标路径: 优先用 ItemData.icon_path 显式配置, 否则按约定 res://assets/sprites/items/[id].jpg
func get_icon_path(id: String) -> String:
	if not _items.has(id):
		return ""
	var item: ItemData = _items[id]
	if item.icon_path != "":
		return item.icon_path
	return "res://assets/sprites/items/" + id + ".jpg"


func get_all_items() -> Dictionary:
	return _items


func get_items_by_type(type: ItemType) -> Array:
	var result: Array = []
	for item in _items.values():
		if item.type == type:
			result.append(item)
	return result


# --- 异能数据库 (Phase 5: 五主角异能树 + 技能点) ---

const CA := preload("res://scripts/combat/combat_actions.gd")

## 异能树数据: id -> {name, character, tier, cost, desc, action(CombatAction), passive}
## action 类型: 伤害型(正常) / 治疗型(properties.heal) / 增益型(properties.buff_*)

func _register_default_abilities() -> void:
	# ===== 前特种兵 (近战系, character=1) =====
	# Tier 1
	_register_ability("sf_iron_skin", "钢铁皮肤", 1, 1, 1, "被动: 防御力 +20%",
		null, true)
	_register_ability("sf_battle_cry", "战吼", 1, 1, 1, "主动: 攻击力 +30% (3轮)",
		CA.create_ability("sf_battle_cry", "战吼", 4, 0.0, 0, CA.DamageType.BLUNT),
		false, {"buff_type": "attack", "buff_value": 0.3, "buff_rounds": 3})
	# Tier 2
	_register_ability("sf_regen", "自愈", 1, 2, 2, "主动: 恢复 30% 生命",
		CA.create_ability("sf_regen", "自愈", 4, 0.0, 0, CA.DamageType.TRUE),
		false, {"heal": 0.3, "heal_percent": true})
	_register_ability("sf_lunge", "突进打击", 1, 2, 2, "主动: 冲撞目标, 高额伤害",
		CA.create_ability("sf_lunge", "突进打击", 5, 1.6, 2, CA.DamageType.BLUNT),
		false)
	# Tier 3
	_register_ability("sf_rage", "狂化", 1, 3, 3, "主动: 攻击力 +60%, 每轮损失少量生命 (3轮)",
		CA.create_ability("sf_rage", "狂化", 6, 0.0, 0, CA.DamageType.TRUE),
		false, {"buff_type": "attack", "buff_value": 0.6, "buff_rounds": 3, "self_damage": 0.03})

	# ===== 老猎人 (远程/陷阱系, character=2) =====
	_register_ability("hu_dynamic_vision", "动态视觉", 2, 1, 1, "被动: 侦测范围 +2",
		null, true)
	_register_ability("hu_trap_master", "陷阱强化", 2, 2, 2, "被动: 陷阱伤害翻倍",
		null, true)
	_register_ability("hu_mark_shot", "标记射击", 2, 3, 3, "主动: 标记目标, 下次攻击必暴击",
		CA.create_ability("hu_mark_shot", "标记射击", 4, 0.8, 6, CA.DamageType.PIERCE),
		false, {"guarantee_crit": true})

	# ===== 前医生 (辅助/化学系, character=3) =====
	_register_ability("doc_toxic_fog", "毒雾", 3, 1, 1, "主动: 释放毒雾, 目标中毒",
		CA.create_ability("doc_toxic_fog", "毒雾", 5, 0.8, 3, CA.DamageType.ACID),
		false, {"poison": true})
	_register_ability("doc_hormone", "激素治疗", 3, 2, 2, "主动: 治疗 50% 生命",
		CA.create_ability("doc_hormone", "激素治疗", 5, 0.0, 0, CA.DamageType.TRUE),
		false, {"heal": 0.5, "heal_percent": true})
	_register_ability("doc_pheromone", "信息素诱饵", 3, 3, 3, "主动: 驱散/吸引丧尸",
		CA.create_ability("doc_pheromone", "信息素诱饵", 4, 0.0, 4, CA.DamageType.TRUE),
		false, {"taunt": true})

	# ===== 电工 (技术/机械系, character=4) =====
	_register_ability("el_overload", "过载机械", 4, 1, 1, "主动: 瘫痪机械目标",
		CA.create_ability("el_overload", "过载机械", 4, 0.7, 3, CA.DamageType.ELECTRIC),
		false, {"stun": true})
	_register_ability("el_static_field", "静电场", 4, 2, 2, "主动: 周围敌人减速",
		CA.create_ability("el_static_field", "静电场", 5, 0.6, 2, CA.DamageType.ELECTRIC),
		false, {"slow": true})
	_register_ability("el_jammer", "电子干扰", 4, 3, 3, "主动: 干扰敌方 AI",
		CA.create_ability("el_jammer", "电子干扰", 6, 0.0, 4, CA.DamageType.ELECTRIC),
		false, {"confuse": true})

	# ===== 通灵者 (法系, character=5) =====
	_register_ability("ps_mind_blast", "心灵震爆", 5, 1, 1, "主动: 精神伤害",
		CA.create_ability("ps_mind_blast", "心灵震爆", 5, 1.1, 4, CA.DamageType.PSYCHIC),
		false)
	_register_ability("ps_control", "精神控制", 5, 2, 2, "主动: 短暂控制丧尸",
		CA.create_ability("ps_control", "精神控制", 6, 0.5, 3, CA.DamageType.PSYCHIC),
		false, {"stun": true})
	_register_ability("ps_scout", "灵体侦查", 5, 3, 3, "主动: 揭示视野内敌人",
		CA.create_ability("ps_scout", "灵体侦查", 3, 0.0, 0, CA.DamageType.TRUE),
		false, {"reveal": true})


func _register_ability(id: String, name: String, character: int, tier: int, cost: int,
		desc: String, action: Resource, passive: bool, extra_props: Dictionary = {}) -> void:
	if action and not extra_props.is_empty():
		action.effects = extra_props
	_abilities[id] = {
		"name": name,
		"character": character,
		"tier": tier,
		"cost": cost,
		"desc": desc,
		"action": action,
		"passive": passive,
	}


func get_abilities_for_character(character_id: int) -> Array:
	var result: Array = []
	for key in _abilities:
		if _abilities[key].get("character", 0) == character_id:
			result.append({"id": key, "data": _abilities[key]})
	# 按 tier 排序
	result.sort_custom(func(a, b): return int(a["data"]["tier"]) < int(b["data"]["tier"]))
	return result


func get_ability(id: String) -> Dictionary:
	return _abilities.get(id, {})


## 获取异能的施放动作 (被动返回 null)
func get_ability_action(id: String) -> Resource:
	var data: Dictionary = _abilities.get(id, {})
	return data.get("action") if not data.is_empty() else null


## 同角色是否有已学异能满足前置 (学 tier N 需低 tier 至少一个已学)
func ability_unlockable(id: String, learned_ids: Array) -> bool:
	var data: Dictionary = _abilities.get(id, {})
	if data.is_empty():
		return false
	var tier: int = data.get("tier", 1)
	if tier <= 1:
		return true
	var character: int = data.get("character", 0)
	for prev in learned_ids:
		var prev_data: Dictionary = _abilities.get(prev, {})
		if prev_data.get("character", 0) == character and int(prev_data.get("tier", 0)) < tier:
			return true
	return false


# --- 存档操作 ---

func save_to_slot(slot: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file_path := _get_save_path(slot)
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	print("[DataManager] 存档已保存: slot ", slot)
	return true


func load_from_slot(slot: int) -> Dictionary:
	var file := FileAccess.open(_get_save_path(slot), FileAccess.READ)
	if not file:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("[DataManager] JSON 解析失败: slot ", slot)
		return {}
	return json.data


func delete_slot(slot: int) -> void:
	var file_path := _get_save_path(slot)
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)


func save_exists(slot: int) -> bool:
	return FileAccess.file_exists(_get_save_path(slot))


func _get_save_path(slot: int) -> String:
	return SAVE_DIR + "save_" + str(slot) + ".json"
