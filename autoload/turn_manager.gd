extends Node

# ============================================================
# TurnManager — 异步回合制 AP 调度系统
# ============================================================
#
# 核心模型：
#   主角每消耗 N 点 AP 执行一个动作，随后所有其他单位获得等量 AP。
#   按 ap_current 降序排列，ap_current >= ap_max 的单位可行动。
#   所有单位无法或不愿行动时，进入下一轮。
#
# 关键修正 (Phase 2):
#   - player_acted 是【战斗模式】AP 扣除 + 敌人行动的唯一起点: 玩家动作 → 敌人同时行动 → 新回合
#   - spend_player_ap_only 是【探索模式】专用: 只扣玩家 AP + 触发丧尸巡逻, 不推进敌人回合
#   - 增加了 combat_mode 标记, 区分探索移动和战斗模式
#   - 增加了回合阶段信号 (player_phase_start/end)
# 契约 (2026-08-05 审计):
#   - 战斗模式扣 AP: 只能走 player_acted / end_player_phase, 禁止直接 set_ap
#   - 探索模式扣 AP: 只能走 spend_player_ap_only
#   - 不要手动 set_ap, 除非是在 _start_new_round 的回满逻辑里

# Preload 类型引用 (用于函数签名)
const CombatActionClass := preload("res://scripts/combat/combat_actions.gd")

## 默认动作 AP 消耗
const AP_COST_MOVE: int = 2
const AP_COST_ATTACK: int = 4
const AP_COST_USE_ITEM: int = 1
const AP_COST_WAIT: int = 5
const AP_COST_INTERACT: int = 2
const AP_COST_ABILITY: int = 6

## 基础最大 AP
const DEFAULT_AP_MAX: int = 10

var _units: Array[Node] = []
var _player_unit: Node = null
var _current_turn_unit: Node = null
var _round_number: int = 1
var _is_processing: bool = false

## 战斗模式 (true = 战斗回合制, false = 探索自由移动)
var combat_mode: bool = false

## 战斗模式下，玩家回合阶段标记
var player_phase_active: bool = false

## 回合历史记录 (用于回放/日志)
var _turn_log: Array[Dictionary] = []

## 战斗中获得的临时 buff (按 unit 索引)
var _combat_buffs: Dictionary = {}

## 探索模式异步节奏: 玩家每走 N 步, 丧尸各巡逻 1 步
var _explore_steps_since_patrol: int = 0
const PATROL_EVERY_PLAYER_STEPS: int = 2

## 卷入半径 (格): 一只丧尸发现玩家 → 仅此半径内的丧尸被惊动加入战斗
## (与 enemy_base.AGGRO_RADIUS_TILES 保持一致, 范围外丧尸不参战)
const AGGRO_RADIUS_TILES := 10

# 核心原则: 主角的行动是世界时钟。主角不动 → 世界静止。
# 丧尸巡逻完全由玩家移动驱动 (每 PATROL_EVERY_PLAYER_STEPS 步触发一次), 无 timer。

signal round_started(round_number: int)
signal player_turn_started()
signal player_phase_started()
signal player_phase_ended()
signal unit_turn_started(unit: Node)
signal unit_action_executed(unit: Node, action: String, ap_cost: int)
signal all_units_exhausted()
signal round_ended(round_number: int)
signal combat_started()
signal combat_ended(victory: bool)


## 场景切换时调用: 清空所有单位注册与战斗状态
func reset_scene() -> void:
	_units.clear()
	_player_unit = null
	_current_turn_unit = null
	combat_mode = false
	player_phase_active = false
	_round_number = 1
	_explore_steps_since_patrol = 0
	_turn_log.clear()
	print("[TurnManager] 场景重置")


# --- 注册 / 注销 ---

func register_unit(unit: Node, is_player: bool = false) -> void:
	if not _units.has(unit):
		_units.append(unit)
	if is_player:
		_player_unit = unit
	print("[TurnManager] 注册单位: ", unit.name, " (玩家=", is_player, ")")


func unregister_unit(unit: Node) -> void:
	_units.erase(unit)
	_combat_buffs.erase(unit)
	if unit == _player_unit:
		_player_unit = null


# --- 查询 ---

func get_player() -> Node:
	return _player_unit

func get_current_unit() -> Node:
	return _current_turn_unit

func get_round() -> int:
	return _round_number

func get_unit_ap(unit: Node) -> int:
	return _unit_ap(unit)

func get_unit_max_ap(unit: Node) -> int:
	return _unit_ap_max(unit)

func get_all_units() -> Array[Node]:
	return _units

func get_enemy_units() -> Array:
	var enemies: Array = []
	for u in _units:
		if u != _player_unit and is_instance_valid(u):
			enemies.append(u)
	return enemies

func get_alive_enemy_count() -> int:
	var count := 0
	for u in _units:
		if u != _player_unit and is_instance_valid(u) and _unit_hp(u) > 0:
			count += 1
	return count

func get_turn_log() -> Array[Dictionary]:
	return _turn_log


# --- 辅助属性读取 (P1-1 类型化: 优先走 Character 类型化方法, 非 Character 单位回退反射) ---

func _unit_ap(unit: Node) -> int:
	if unit and unit.has_method("get_ap"):
		return unit.get_ap()
	return int(unit.get("ap_current")) if unit else 0

func _unit_ap_max(unit: Node) -> int:
	if unit and unit.has_method("get_ap_max"):
		return unit.get_ap_max()
	return int(unit.get("ap_max")) if unit else DEFAULT_AP_MAX

func _unit_hp(unit: Node) -> float:
	if unit and unit.has_method("get_hp"):
		return unit.get_hp()
	return float(unit.get("hp")) if unit else 0.0

func _unit_is_moving(unit: Node) -> bool:
	if unit and unit.has_method("get_is_moving"):
		return unit.get_is_moving()
	return bool(unit.get("is_moving")) if unit else false

func _set_unit_ap(unit: Node, value: int) -> void:
	if unit and unit.has_method("set_ap"):
		unit.set_ap(value)
	elif unit:
		unit.set("ap_current", value)

func _set_unit_is_moving(unit: Node, value: bool) -> void:
	if unit and unit.has_method("set_is_moving"):
		unit.set_is_moving(value)
	elif unit:
		unit.set("is_moving", value)


# --- 战斗模式 ---

func enter_combat() -> void:
	var was_combat := combat_mode
	combat_mode = true
	_round_number = 1 if not was_combat else _round_number
	_explore_steps_since_patrol = 0
	# 卷入警戒范围内的丧尸 (范围外不参战); 已在战斗中不重复回满 AP
	if _player_unit and is_instance_valid(_player_unit):
		propagate_aggro(_player_unit.global_position, AGGRO_RADIUS_TILES)
	if not was_combat:
		if _player_unit and is_instance_valid(_player_unit):
			_set_unit_ap(_player_unit, _unit_ap_max(_player_unit))
		# 仅给"已卷入"的丧尸回满 AP; 范围外丧尸保持低 AP, 不会行动
		for unit: Node in _units:
			if unit != _player_unit and is_instance_valid(unit) and unit.has_method("is_engaged") and unit.is_engaged():
				_set_unit_ap(unit, _unit_ap_max(unit))
		combat_started.emit()
	_check_player_turn()


## 把 center 周围 radius_tiles 格内的丧尸卷入战斗 (它们"听到打斗/被警报")
func propagate_aggro(center: Vector2, radius_tiles: int) -> void:
	for unit: Node in _units:
		if unit == _player_unit or not is_instance_valid(unit):
			continue
		if unit.has_method("is_engaged") and not unit.is_engaged():
			var ts: int = int(unit.get("tile_size")) if unit.get("tile_size") != null else 32
			var d := int(unit.global_position.distance_to(center) / ts)
			if d <= radius_tiles and unit.has_method("engage"):
				unit.engage()


func exit_combat(victory: bool = false) -> void:
	combat_mode = false
	player_phase_active = false
	_current_turn_unit = null
	combat_ended.emit(victory)


func are_all_enemies_defeated() -> bool:
	# 仅统计"已卷入战斗"的丧尸; 范围外未卷入者不算, 否则战斗永远不结束
	for u in _units:
		if u != _player_unit and is_instance_valid(u) and u.has_method("is_engaged") and u.is_engaged() and _unit_hp(u) > 0:
			return false
	return true


# --- 核心逻辑 ---

func player_acted(action_name: String, ap_cost: int) -> void:
	if not _player_unit:
		push_error("[TurnManager] 玩家单位未注册!")
		return

	var current_ap: int = get_unit_ap(_player_unit)
	if current_ap < ap_cost:
		push_warning("[TurnManager] AP 不足: ", current_ap, " < ", ap_cost)
		return

	_set_unit_ap(_player_unit, current_ap - ap_cost)
	unit_action_executed.emit(_player_unit, action_name, ap_cost)

	for unit: Node in _units:
		if unit != _player_unit and is_instance_valid(unit) and (not unit.has_method("is_engaged") or unit.is_engaged()):
			var unit_ap: int = _unit_ap(unit)
			var max_ap: int = _unit_ap_max(unit)
			_set_unit_ap(unit, mini(unit_ap + ap_cost, max_ap))

	_turn_log.append({
		"round": _round_number,
		"unit": _player_unit.name,
		"action": action_name,
		"ap_cost": ap_cost,
	})

	# 单动作回合制: 战斗模式下执行完一个动作即清空玩家 AP, 自动进入敌人阶段
	if combat_mode:
		player_phase_active = false
		player_phase_ended.emit()
		_set_unit_ap(_player_unit, 0)

	process_turn_queue()


func process_turn_queue() -> void:
	if _is_processing:
		return
	_is_processing = true

	var ready_units := _get_ready_units()
	ready_units.erase(_player_unit)

	if ready_units.is_empty():
		var player_ready := _get_player_ap() >= _get_player_max_ap()
		if not player_ready:
			_start_new_round()
		else:
			_check_player_turn()
		_is_processing = false
		return

	# 敌人阶段: 所有 ready 敌人【同时】开始行动。
	# take_turn 是同步函数: 各自启动移动/攻击动画后立即返回,
	# 全部启动后由下方统一等待所有移动动画结束 → 敌人真正并行行动, 不是逐个回合。
	_current_turn_unit = null
	for unit: Node in ready_units:
		if not is_instance_valid(unit):
			continue
		unit_turn_started.emit(unit)
		if unit.has_method("take_turn"):
			unit.take_turn()
		else:
			var used_ap: int = mini(_unit_ap(unit), DEFAULT_AP_MAX)
			_set_unit_ap(unit, _unit_ap(unit) - used_ap)

	# 统一等待所有敌人移动动画完成 (带超时保护防止死锁)
	var wait_frames := 0
	while _any_unit_moving(ready_units) and wait_frames < 180:
		await get_tree().process_frame
		wait_frames += 1
	# 超时强制复位, 防止动画卡死
	for unit: Node in ready_units:
		if is_instance_valid(unit) and _unit_is_moving(unit):
			_set_unit_is_moving(unit, false)
			if unit is CharacterBody2D:
				unit.velocity = Vector2.ZERO

	_current_turn_unit = null
	_is_processing = false

	# 敌人行动完毕后: 单动作回合制下玩家 AP 已被清空, 直接开新回合
	if _get_player_ap() < _get_player_max_ap():
		_start_new_round()
	else:
		_check_player_turn()


func spend_player_ap_only(ap_cost: int) -> bool:
	if not _player_unit:
		return false
	var current_ap: int = get_unit_ap(_player_unit)
	if current_ap < ap_cost:
		return false
	_set_unit_ap(_player_unit, current_ap - ap_cost)
	unit_action_executed.emit(_player_unit, "move_explore", ap_cost)

	# 探索模式异步节奏: 玩家每走2步, 所有丧尸各巡逻1步
	_explore_steps_since_patrol += 1
	if _explore_steps_since_patrol >= PATROL_EVERY_PLAYER_STEPS:
		_explore_steps_since_patrol = 0
		_trigger_enemy_patrol()
	return true


func _trigger_enemy_patrol() -> void:
	for unit: Node in _units:
		if unit != _player_unit and is_instance_valid(unit) and unit.has_method("patrol_action"):
			unit.patrol_action()


func end_player_phase() -> void:
	if not combat_mode:
		return
	player_phase_active = false
	player_phase_ended.emit()
	if _player_unit:
		_set_unit_ap(_player_unit, 0)
	process_turn_queue()


# --- 内部方法 ---

func _get_ready_units() -> Array:
	var ready: Array = []
	for unit: Node in _units:
		if is_instance_valid(unit):
			var ap: int = _unit_ap(unit)
			var max_ap: int = _unit_ap_max(unit)
			if ap >= max_ap:
				ready.append(unit)
	return ready


## 检查给定单位列表中是否还有正在移动的 (用于敌人并行行动统一等待)
func _any_unit_moving(units: Array) -> bool:
	for unit: Node in units:
		if is_instance_valid(unit) and _unit_is_moving(unit):
			return true
	return false


func _get_player_ap() -> int:
	return _unit_ap(_player_unit)


func _get_player_max_ap() -> int:
	return _unit_ap_max(_player_unit)


func _start_new_round() -> void:
	round_ended.emit(_round_number)
	_round_number += 1

	for unit: Node in _units:
		if unit == _player_unit:
			_set_unit_ap(unit, _unit_ap_max(unit))
		elif unit.has_method("is_engaged") and unit.is_engaged():
			# 仅给卷入战斗的丧尸回满 AP; 范围外未卷入者不回 (保持不行动)
			_set_unit_ap(unit, _unit_ap_max(unit))

	if WorldTime:
		WorldTime.tick_round()

	round_started.emit(_round_number)

	if combat_mode:
		if are_all_enemies_defeated():
			exit_combat(true)
			return
		if _player_unit and _unit_hp(_player_unit) <= 0:
			exit_combat(false)
			return

	_check_player_turn()


func _check_player_turn() -> void:
	if _player_unit and is_instance_valid(_player_unit):
		if combat_mode:
			player_phase_active = true
			player_phase_started.emit()
		player_turn_started.emit()


# --- 便捷方法 ---

func get_action_cost(action: String) -> int:
	match action:
		"move": return AP_COST_MOVE
		"attack": return AP_COST_ATTACK
		"use_item": return AP_COST_USE_ITEM
		"wait": return AP_COST_WAIT
		"interact": return AP_COST_INTERACT
		"ability": return AP_COST_ABILITY
	return 0


func get_combat_action_cost(action: Resource) -> int:
	var base: int = action.get("ap_cost")
	if _player_unit and _player_unit.has_method("get_ap_cost_modifier"):
		base = _player_unit.get_ap_cost_modifier(base)
	return maxi(base, 1)
