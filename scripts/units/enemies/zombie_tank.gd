extends "res://scripts/units/enemy_base.gd"
class_name ZombieTank

# 坦克丧尸 — 超高血量、高防御、近战范围攻击
# CA 常量继承自 EnemyBase

var _slam_cooldown: int = 0
var _slam_cooldown_max: int = 3


func _define_stats() -> Dictionary:
	return {
		"enemy_id": "zombie_tank",
		"enemy_name": "坦克丧尸",
		"max_hp": 200.0,
		"ap_max": 7,
		"attack_power": 18.0,
		"defense": 10.0,
		"detection_range": 4,
		"attack_range": 1,
		"flee_hp_threshold": 0.0,  # 不逃跑 (用户反馈: 普通丧尸不会逃跑)
	}


func _get_attack_action() -> Resource:
	var action := CA.create_melee_attack("tank_smash", "重砸", 5, 1.5, CA.DamageType.BLUNT)
	action.crit_chance = 0.03
	return action


func _perform_attack() -> void:
	# 优先使用地面猛击
	if _should_use_slam():
		_do_slam()
		return
	super._perform_attack()


func _should_use_slam() -> bool:
	var player := TurnManager.get_player()
	if not player:
		return false
	var dist := int(global_position.distance_to(player.global_position) / tile_size)
	return dist <= attack_range + 1 and _slam_cooldown <= 0 and ap_current >= 6


func _do_slam() -> void:
	_slam_cooldown = _slam_cooldown_max

	var player := TurnManager.get_player()
	if is_instance_valid(player) and player.has_method("take_damage"):
		var base := attack_power * 0.8
		# 物理伤害: 统一走 CombatCalculator 护甲公式 (P0-2, take_damage 不再自行减伤)
		var player_def: float = player.get_total_defense() if player.has_method("get_total_defense") else 0.0
		var dmg := CC.apply_defense(base, player_def)
		player.take_damage(dmg)
		print("[坦克丧尸] 地面猛击! 对玩家造成 %.1f 范围伤害 (基础 %.1f)" % [dmg, base])


func _send_turn_report() -> void:
	_slam_cooldown = maxi(_slam_cooldown - 1, 0)
	super._send_turn_report()
