# ============================================================
# CombatAction — 战斗动作资源定义
# ============================================================
# 每个动作定义了 AP 消耗、射程、伤害公式等元数据。
# 用于 CombatCalculator 计算和 CombatUI 展示。

class_name CombatAction
extends Resource

enum ActionType { MOVE, MELEE, RANGED, USE_ITEM, ABILITY, WAIT }
enum DamageType { SLASH, PIERCE, BLUNT, ACID, FIRE, ELECTRIC, PSYCHIC, TRUE }

@export var action_id: String = ""
@export var action_name: String = "动作"
@export var action_type: ActionType = ActionType.MELEE
@export var damage_type: DamageType = DamageType.SLASH

## 技能描述 (菜单/图鉴显示)
@export var description: String = ""

## AP 消耗 (会被单位属性修正)
@export var ap_cost: int = 4

## 射程 (格数, 0=自身, 1=近战, 2+=远程)
@export var range_min: int = 0
@export var range_max: int = 1

## 伤害倍率 (乘以攻击力)
@export var damage_multiplier: float = 1.0

## 基础固定伤害 (不受攻击力影响)
@export var base_damage: float = 0.0

## 附加效果
@export var crit_chance: float = 0.05
@export var crit_multiplier: float = 1.5
@export var armor_pierce: float = 0.0

## 命中率修正 (-0.3 ~ +0.3, 叠加到基础命中)
@export var accuracy_mod: float = 0.0

## 额外效果字典 (异能专用): heal / heal_percent / buff_type / buff_value / buff_rounds / self_damage / stun / poison ...
@export var effects: Dictionary = {}

## 状态效果 (id 列表, 按概率触发)
@export var status_effects: Array[Dictionary] = []

## 是否消耗武器耐久
@export var consumes_durability: bool = true

## 图标路径
@export var icon_path: String = ""

## 动画名称
@export var animation_name: String = ""

## 攻击音效 (assets/sounds/ 下文件名, 如 "punch.mp3" / "gunshot.mp3")
@export var sound_id: String = ""
## 命中音效
@export var hit_sound_id: String = "hit.wav"
## 未命中音效
@export var miss_sound_id: String = "miss.wav"

## 异能分类标签: 用于特殊机制判定.
## 例如 "space" = 空间系异能, 可使玩家【隔空搜刮尸体】(不受"需靠近尸体 1 格"限制).
## 普通攻击/武器动作留空.
@export var ability_category: String = ""


# --- 预定义动作工厂 ---

static func create_melee_attack(id: String, name: String, ap: int, dmg_mult: float, dmg_type: DamageType = DamageType.SLASH) -> CombatAction:
	var a := new()
	a.action_id = id
	a.action_name = name
	a.action_type = ActionType.MELEE
	a.damage_type = dmg_type
	a.ap_cost = ap
	a.range_min = 0
	a.range_max = 1
	a.damage_multiplier = dmg_mult
	a.crit_chance = 0.05
	a.sound_id = "punch.mp3"  # 近战拳击声
	return a


static func create_ranged_attack(id: String, name: String, ap: int, dmg_mult: float, rng: int, dmg_type: DamageType = DamageType.PIERCE) -> CombatAction:
	var a := new()
	a.action_id = id
	a.action_name = name
	a.action_type = ActionType.RANGED
	a.damage_type = dmg_type
	a.ap_cost = ap
	a.range_min = 2
	a.range_max = rng
	a.damage_multiplier = dmg_mult
	a.crit_chance = 0.08
	a.accuracy_mod = -0.05 * (rng - 2)  # 越远越难命中
	a.sound_id = "gunshot.mp3"  # 远程枪击声
	return a


static func create_ability(id: String, name: String, ap: int, dmg_mult: float, rng: int, dmg_type: DamageType) -> CombatAction:
	var a := new()
	a.action_id = id
	a.action_name = name
	a.action_type = ActionType.ABILITY
	a.damage_type = dmg_type
	a.ap_cost = ap
	a.range_min = 0
	a.range_max = rng
	a.damage_multiplier = dmg_mult
	a.crit_chance = 0.10
	return a


static func create_item_action(id: String, name: String) -> CombatAction:
	var a := new()
	a.action_id = id
	a.action_name = name
	a.action_type = ActionType.USE_ITEM
	a.ap_cost = 1
	a.range_min = 0
	a.range_max = 0
	a.damage_multiplier = 0.0
	a.consumes_durability = false
	return a


# --- 默认动作库 ---

static func default_actions() -> Array[CombatAction]:
	return [
		create_melee_attack("punch", "拳击", 4, 0.6, DamageType.BLUNT),
		create_melee_attack("slash", "斩击", 4, 1.0, DamageType.SLASH),
		create_melee_attack("bash", "重击", 5, 1.4, DamageType.BLUNT),
		create_ranged_attack("shoot", "射击", 4, 1.0, 5, DamageType.PIERCE),
		create_ranged_attack("aimed_shot", "瞄准射击", 5, 1.3, 6, DamageType.PIERCE),
		create_item_action("use_bandage", "使用绷带"),
		create_item_action("use_stim", "使用兴奋剂"),
	]


# --- 技能数据表 (所有技能集中定义, 按 id 取用) ---
# 加新技能: 在 _build_db 里注册一条即可, 场景代码用 CA.get_action("id") 取。
# 字段: id / name / type / ap / 伤害倍率 / 射程 / 伤害类型 / 音效 / 额外修正

static var _db_built := false
static var _db: Dictionary = {}

static func _build_db() -> void:
	if _db_built:
		return
	_db_built = true

	# --- 玩家技能 ---
	var punch := create_melee_attack("punch", "拳击", 4, 0.6, DamageType.BLUNT)
	punch.description = "空手拳击，聊胜于无。"
	_db["punch"] = punch

	var slash := create_melee_attack("slash", "斩击", 4, 1.0, DamageType.SLASH)
	slash.description = "刀刃挥砍，稳定可靠。"
	_db["slash"] = slash

	var bash := create_melee_attack("bash", "重击", 5, 1.4, DamageType.BLUNT)
	bash.description = "全力一击，破甲 10%。"
	bash.armor_pierce = 0.1
	_db["bash"] = bash

	var shoot := create_ranged_attack("shoot", "射击", 4, 1.0, 5, DamageType.PIERCE)
	shoot.description = "手枪射击，中距离可靠。"
	_db["shoot"] = shoot

	var aimed_shot := create_ranged_attack("aimed_shot", "瞄准射击", 5, 1.3, 6, DamageType.PIERCE)
	aimed_shot.description = "屏息瞄准，高命中高伤。"
	aimed_shot.accuracy_mod = 0.05
	aimed_shot.crit_chance = 0.12
	_db["aimed_shot"] = aimed_shot

	var burst := create_ranged_attack("burst", "扫射", 4, 0.9, 6, DamageType.PIERCE)
	burst.description = "步枪连射，弹幕压制。"
	_db["burst"] = burst

	var blast := create_ranged_attack("blast", "轰击", 5, 1.6, 3, DamageType.PIERCE)
	blast.description = "霰弹轰击，近距离毁灭。"
	blast.accuracy_mod = -0.10
	blast.crit_chance = 0.12
	_db["blast"] = blast

	# --- 敌人技能 ---
	var enemy_attack := create_melee_attack("enemy_attack", "撕咬", 4, 1.0, DamageType.SLASH)
	enemy_attack.description = "丧尸撕咬。"
	_db["enemy_attack"] = enemy_attack

	var spit := create_ranged_attack("spit", "酸液喷射", 5, 0.7, 4, DamageType.ACID)
	spit.description = "远程酸液，附带腐蚀。"
	spit.sound_id = "spit.wav"
	_db["spit"] = spit

	var tank_slam := create_melee_attack("tank_slam", "地面猛击", 6, 1.5, DamageType.BLUNT)
	tank_slam.description = "范围猛击，重创面前目标。"
	_db["tank_slam"] = tank_slam


## 按 id 获取技能动作 (数据表查询; 未知 id 返回 null)
static func get_action(action_id: String) -> CombatAction:
	_build_db()
	return _db.get(action_id)


## 获取全部技能 (遍历用)
static func get_all_actions() -> Array[CombatAction]:
	_build_db()
	var out: Array[CombatAction] = []
	for a in _db.values():
		if a is CombatAction:
			out.append(a)
	return out
