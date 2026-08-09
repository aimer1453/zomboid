class_name Weapon
extends Resource

const CA := preload("res://scripts/combat/combat_actions.gd")

enum WeaponType { UNARMED, MELEE_ONE_HAND, MELEE_TWO_HAND, PISTOL, RIFLE, SHOTGUN, THROWABLE, SPECIAL }
enum WeaponSlot { PRIMARY, SECONDARY, MELEE }

@export var weapon_id: String = ""
@export var weapon_name: String = "空手"
@export var weapon_type: WeaponType = WeaponType.UNARMED
@export var slot: WeaponSlot = WeaponSlot.MELEE

## 主要攻击动作
@export var primary_action: Resource = null

## 次要动作 (如近战枪托)
@export var secondary_action: Resource = null

## 耐久度 (-1 = 无限)
@export var max_durability: int = 100
@export var current_durability: int = 100

## 属性加成
@export var attack_bonus: float = 0.0
@export var accuracy_bonus: float = 0.0
@export var crit_bonus: float = 0.0
@export var armor_pierce_bonus: float = 0.0

## AP 消耗修正 (负数 = 减少 AP 消耗)
@export var ap_cost_modifier: int = 0

## 武器格子尺寸 (用于背包方格)
@export var grid_size: Vector2i = Vector2i(1, 2)

## 图标路径
@export var icon_path: String = ""

## 描述
@export_multiline var description: String = ""


# --- 工厂方法 ---

static func create_knife() -> Weapon:
	var w := new()
	w.weapon_id = "knife"
	w.weapon_name = "求生刀"
	w.weapon_type = WeaponType.MELEE_ONE_HAND
	w.slot = WeaponSlot.MELEE
	w.primary_action = CA.create_melee_attack("slash", "斩击", 3, 0.8, CA.DamageType.SLASH)
	w.primary_action.crit_chance = 0.10
	w.max_durability = 60
	w.current_durability = 60
	w.grid_size = Vector2i(1, 1)
	w.description = "一把普通的求生刀，轻便但有效。"
	return w


static func create_crowbar() -> Weapon:
	var w := new()
	w.weapon_id = "crowbar"
	w.weapon_name = "撬棍"
	w.weapon_type = WeaponType.MELEE_ONE_HAND
	w.slot = WeaponSlot.MELEE
	w.primary_action = CA.create_melee_attack("bash", "重击", 4, 1.1, CA.DamageType.BLUNT)
	w.primary_action.armor_pierce = 0.1
	w.max_durability = 80
	w.current_durability = 80
	w.grid_size = Vector2i(1, 2)
	w.description = "多功能工具，也能当不错的武器。"
	return w


static func create_bat() -> Weapon:
	var w := new()
	w.weapon_id = "baseball_bat"
	w.weapon_name = "棒球棍"
	w.weapon_type = WeaponType.MELEE_TWO_HAND
	w.slot = WeaponSlot.MELEE
	w.primary_action = CA.create_melee_attack("bash", "挥击", 4, 1.3, CA.DamageType.BLUNT)
	w.primary_action.crit_chance = 0.08
	w.max_durability = 50
	w.current_durability = 50
	w.grid_size = Vector2i(1, 3)
	w.description = "结实的棒球棍，挥舞起来很有威力。"
	return w


static func create_pistol() -> Weapon:
	var w := new()
	w.weapon_id = "pistol"
	w.weapon_name = "手枪"
	w.weapon_type = WeaponType.PISTOL
	w.slot = WeaponSlot.PRIMARY
	w.primary_action = CA.create_ranged_attack("shoot", "射击", 4, 1.0, 5, CA.DamageType.PIERCE)
	w.primary_action.crit_chance = 0.08
	w.max_durability = 200
	w.current_durability = 200
	w.accuracy_bonus = 0.05
	w.grid_size = Vector2i(1, 1)
	w.description = "标准手枪，弹容量15发。"
	return w


static func create_rifle() -> Weapon:
	var w := new()
	w.weapon_id = "rifle"
	w.weapon_name = "突击步枪"
	w.weapon_type = WeaponType.RIFLE
	w.slot = WeaponSlot.PRIMARY
	w.primary_action = CA.create_ranged_attack("shoot", "扫射", 4, 0.9, 6, CA.DamageType.PIERCE)
	w.primary_action.crit_chance = 0.05
	w.max_durability = 300
	w.current_durability = 300
	w.grid_size = Vector2i(2, 1)
	w.description = "军用突击步枪，射速快，火力强。"
	return w


static func create_shotgun() -> Weapon:
	var w := new()
	w.weapon_id = "shotgun"
	w.weapon_name = "霰弹枪"
	w.weapon_type = WeaponType.SHOTGUN
	w.slot = WeaponSlot.PRIMARY
	var action := CA.create_ranged_attack("shoot", "轰击", 5, 1.6, 3, CA.DamageType.PIERCE)
	action.crit_chance = 0.12
	action.accuracy_mod = -0.10
	w.primary_action = action
	w.max_durability = 150
	w.current_durability = 150
	w.grid_size = Vector2i(2, 1)
	w.description = "近战王者，远距离无力。"
	return w


static func create_bow() -> Weapon:
	var w := new()
	w.weapon_id = "bow"
	w.weapon_name = "复合弓"
	w.weapon_type = WeaponType.THROWABLE
	w.slot = WeaponSlot.PRIMARY
	w.primary_action = CA.create_ranged_attack("shoot", "射箭", 3, 1.2, 8, CA.DamageType.PIERCE)
	w.primary_action.crit_chance = 0.10
	w.max_durability = 120
	w.current_durability = 120
	w.grid_size = Vector2i(2, 1)
	w.description = "无声远程武器，射程远，暴击高。"
	return w


static func create_rusty_knife() -> Weapon:
	var w := new()
	w.weapon_id = "rusty_knife"
	w.weapon_name = "生锈小刀"
	w.weapon_type = WeaponType.MELEE_ONE_HAND
	w.slot = WeaponSlot.MELEE
	w.primary_action = CA.create_melee_attack("slash", "戳刺", 3, 0.55, CA.DamageType.PIERCE)
	w.max_durability = 40
	w.current_durability = 40
	w.grid_size = Vector2i(1, 1)
	w.description = "锈迹斑斑的小刀，丧尸捡来的。"
	return w


# --- 武器库 ---

static func all_weapons() -> Dictionary:
	return {
		"rusty_knife": create_rusty_knife(),
		"knife": create_knife(),
		"crowbar": create_crowbar(),
		"baseball_bat": create_bat(),
		"pistol": create_pistol(),
		"rifle": create_rifle(),
		"shotgun": create_shotgun(),
		"bow": create_bow(),
	}
