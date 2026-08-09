extends "res://scripts/units/enemy_base.gd"
class_name ZombieBasic

# 普通丧尸 — 均衡型近战敌人 (不会逃跑, 死战到底)

func _define_stats() -> Dictionary:
	return {
		"enemy_id": "zombie_basic",
		"enemy_name": "普通丧尸",
		"max_hp": 60.0,
		"ap_max": 8,
		"attack_power": 10.0,
		"defense": 3.0,
		"detection_range": 5,
		"attack_range": 1,
		"flee_hp_threshold": 0.0,  # 不逃跑 (用户反馈: 普通丧尸不会逃跑)
	}
