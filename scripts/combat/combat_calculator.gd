# ============================================================
# CombatCalculator — 战斗计算引擎
# ============================================================
# 处理伤害计算、命中判定、暴击、护甲穿透、状态效果。
# 纯数学类，不依赖场景树。

class_name CombatCalculator
extends RefCounted

const CA := preload("res://scripts/combat/combat_actions.gd")

## 基础命中率
const BASE_HIT_CHANCE: float = 0.85
## 每格距离的命中惩罚
const DISTANCE_PENALTY_PER_TILE: float = 0.04
## 基础暴击率 (叠加武器/技能)
const BASE_CRIT_CHANCE: float = 0.05
## 护甲减伤系数 (每点防御减伤比例)
const DEFENSE_REDUCTION: float = 0.06
## 护甲减伤上限 (防止无敌)
const MAX_DEFENSE_REDUCTION: float = 0.75
## 最低伤害 (破防保证)
const MIN_DAMAGE: float = 1.0

enum HitResult { MISS, HIT, CRIT, BLOCKED, DODGED }


# --- 公开接口 ---

## 计算伤害结果
static func calculate_damage(
	attacker_stats: Dictionary,
	defender_stats: Dictionary,
	action: Resource,
	distance: int = 1
) -> Dictionary:
	var log_parts: Array[String] = []
	var attacker_name: String = attacker_stats.get("name", "攻击者")
	var defender_name: String = defender_stats.get("name", "防御者")

	# 1. 命中判定
	var hit_chance := _calc_hit_chance(attacker_stats, defender_stats, action, distance)
	var hit_roll := randf()
	var result: HitResult
	var did_crit := false

	if hit_roll > hit_chance:
		result = HitResult.MISS
		log_parts.append("%s 的攻击未命中 %s! (命中率 %.0f%%)" % [attacker_name, defender_name, hit_chance * 100])
		return {
			"result": result, "damage": 0.0, "raw_damage": 0.0,
			"hit_chance": hit_chance, "did_crit": false, "armor_reduced": 0.0,
			"statuses_applied": [], "log": "\n".join(log_parts),
		}

	# 2. 计算原始伤害
	var raw_damage := _calc_raw_damage(attacker_stats, action)
	log_parts.append("%s 的 %s (基础伤害: %.1f)" % [attacker_name, action.get("action_name"), raw_damage])

	# 3. 暴击判定
	var crit_chance: float = BASE_CRIT_CHANCE + float(action.get("crit_chance")) + float(attacker_stats.get("crit_bonus", 0.0))
	var crit_roll := randf()
	if crit_roll <= crit_chance:
		did_crit = true
		raw_damage *= float(action.get("crit_multiplier"))
		result = HitResult.CRIT
		log_parts.append("暴击! (倍率: %.1fx)" % float(action.get("crit_multiplier")))
	else:
		result = HitResult.HIT

	# 4. 护甲计算 (统一走 apply_defense, 护甲公式单一出口)
	var def_value: float = float(defender_stats.get("defense", 0.0))
	var pierce: float = float(action.get("armor_pierce")) + float(attacker_stats.get("armor_pierce", 0.0))
	var final_damage := apply_defense(raw_damage, def_value, pierce)

	var armor_reduction: float = 0.0
	if raw_damage > 0.0:
		armor_reduction = 1.0 - final_damage / raw_damage
	var armor_reduced: float = raw_damage - final_damage

	var dmg_type: int = int(action.get("damage_type"))
	var dmg_type_match := _calc_type_effectiveness(dmg_type, defender_stats.get("resistances", {}))
	final_damage *= dmg_type_match

	final_damage = maxf(final_damage, MIN_DAMAGE)

	log_parts.append("防御力 %.0f 减少 %.1f 伤害 (%.0f%%)" % [def_value, armor_reduced, armor_reduction * 100])

	if pierce > 0:
		log_parts.append("护甲穿透: %.0f%%" % (pierce * 100))

	log_parts.append("最终伤害: %.1f" % final_damage)

	var statuses := _roll_status_effects(action, attacker_stats, defender_stats)
	if not statuses.is_empty():
		log_parts.append("触发状态: %s" % ", ".join(statuses))

	return {
		"result": result, "damage": final_damage, "raw_damage": raw_damage,
		"hit_chance": hit_chance, "did_crit": did_crit, "armor_reduced": armor_reduced,
		"statuses_applied": statuses, "log": "\n".join(log_parts),
	}


## 护甲减伤公式 —【唯一出口】(P0-2 统一, 防两套公式分裂)
## 所有"物理减伤"必须走这里: 攻击结算(calculate_damage) / 敌人特殊技能(坦克猛击) / 未来 DOT。
## 语义: 返回经过护甲减免后的最终伤害, 下限 MIN_DAMAGE。
## 注意: 真实伤害(自伤/毒伤) 不走护甲, 直接传原值。
static func apply_defense(base_damage: float, defense: float, pierce: float = 0.0) -> float:
	var reduction: float = minf(defense * DEFENSE_REDUCTION, MAX_DEFENSE_REDUCTION)
	reduction = maxf(reduction - pierce, 0.0)
	return maxf(base_damage * (1.0 - reduction), MIN_DAMAGE)


## 快速计算期望伤害 (用于 AI 决策)
static func estimate_damage(attacker_stats: Dictionary, defender_stats: Dictionary, action: Resource, distance: int = 1) -> float:
	var hit_chance := _calc_hit_chance(attacker_stats, defender_stats, action, distance)
	var raw := _calc_raw_damage(attacker_stats, action)
	var def: float = defender_stats.get("defense", 0.0)
	var pierce: float = float(action.get("armor_pierce")) + float(attacker_stats.get("armor_pierce", 0.0))
	var after_armor := apply_defense(raw, def, pierce)
	var avg_crit_bonus: float = (BASE_CRIT_CHANCE + float(action.get("crit_chance"))) * (float(action.get("crit_multiplier")) - 1.0)
	return after_armor * hit_chance * (1.0 + avg_crit_bonus)


## 检查单位是否在动作射程内
static func in_range(attacker_pos: Vector2, target_pos: Vector2, action: Resource, tile_size: int = 32) -> bool:
	var dist_tiles := int(attacker_pos.distance_to(target_pos) / tile_size)
	return dist_tiles >= int(action.get("range_min")) and dist_tiles <= int(action.get("range_max"))


## 获取射程内的有效目标
static func get_valid_targets(attacker_pos: Vector2, candidates: Array, action: Resource, tile_size: int = 32) -> Array:
	var valid: Array = []
	for c in candidates:
		if is_instance_valid(c) and in_range(attacker_pos, c.global_position, action, tile_size):
			valid.append(c)
	return valid


# --- 内部公式 ---

static func _calc_hit_chance(attacker: Dictionary, _defender: Dictionary, action: Resource, distance: int) -> float:
	var base: float = BASE_HIT_CHANCE
	base += float(action.get("accuracy_mod"))
	base += float(attacker.get("accuracy_bonus", 0.0))
	base -= distance * DISTANCE_PENALTY_PER_TILE
	return clampf(base, 0.05, 0.98)


static func _calc_raw_damage(attacker: Dictionary, action: Resource) -> float:
	var atk: float = float(attacker.get("attack", 10.0))
	var dmg: float = atk * float(action.get("damage_multiplier")) + float(action.get("base_damage"))
	dmg *= randf_range(0.9, 1.1)
	return maxf(dmg, 0.0)


static func _calc_type_effectiveness(dmg_type: int, resistances: Dictionary) -> float:
	match dmg_type:
		CA.DamageType.SLASH:
			return 1.0 - resistances.get("slash", 0.0)
		CA.DamageType.PIERCE:
			return 1.0 - resistances.get("pierce", 0.0)
		CA.DamageType.BLUNT:
			return 1.0 - resistances.get("blunt", 0.0)
		CA.DamageType.ACID:
			return 1.0 - resistances.get("acid", 0.0)
		CA.DamageType.FIRE:
			return 1.0 - resistances.get("fire", 0.0)
		CA.DamageType.ELECTRIC:
			return 1.0 - resistances.get("electric", 0.0)
		CA.DamageType.PSYCHIC:
			return 1.0 - resistances.get("psychic", 0.0)
		CA.DamageType.TRUE:
			return 1.0
	return 1.0


static func _roll_status_effects(action: Resource, attacker: Dictionary, defender: Dictionary) -> Array[String]:
	var applied: Array[String] = []
	var effects: Array = action.get("status_effects")
	if effects == null:
		effects = []
	for effect in effects:
		var chance: float = effect.get("chance", 0.0)
		if randf() <= chance:
			applied.append(effect.get("status_id", "unknown"))
	return applied
