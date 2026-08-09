extends "res://scripts/units/enemy_base.gd"
class_name ZombieSpitter

# 喷射丧尸 — 远程酸液攻击, 脆皮但危险
# CA / CC 常量继承自 EnemyBase

@export var acid_damage: float = 12.0


func _define_stats() -> Dictionary:
	return {
		"enemy_id": "zombie_spitter",
		"enemy_name": "喷射丧尸",
		"max_hp": 25.0,
		"ap_max": 9,
		"attack_power": acid_damage,
		"defense": 1.0,
		"detection_range": 6,
		"attack_range": 4,
		"flee_hp_threshold": 0.0,  # 不逃跑 (用户反馈: 普通丧尸不会逃跑)
	}


func _get_attack_action() -> Resource:
	return CA.create_ranged_attack("acid_spit", "酸液喷射", 4, 0.8, attack_range, CA.DamageType.ACID)


func _perform_attack() -> void:
	var target := _target
	if not target or not is_instance_valid(target):
		return

	var action := _get_attack_action()
	var dist := int(global_position.distance_to(target.global_position) / tile_size)

	var my_stats := get_combat_stats()
	var target_stats: Dictionary = {}
	if target.has_method("get_combat_stats"):
		target_stats = target.get_combat_stats()
	else:
		target_stats = {"name": target.name, "defense": 0.0, "hp": target.get("hp")}

	var calc := CC.new()
	var result := calc.calculate_damage(my_stats, target_stats, action, dist)

	if target.has_method("take_damage") and result.get("damage", 0.0) > 0.0:
		target.take_damage(result.damage)
		var dot: float = result.damage * 0.2
		target.take_damage(dot)

	print("[%s] 喷射酸液! %s" % [enemy_name, result.log])
