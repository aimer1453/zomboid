extends "res://scripts/units/enemy_base.gd"
class_name ZombieRunner

# 疾速丧尸 — 高速、低血量、会逃跑

func _define_stats() -> Dictionary:
	return {
		"enemy_id": "zombie_runner",
		"enemy_name": "疾速丧尸",
		"max_hp": 30.0,
		"ap_max": 12,
		"attack_power": 6.0,
		"defense": 1.0,
		"detection_range": 6,
		"attack_range": 1,
		"flee_hp_threshold": 0.20,
	}
