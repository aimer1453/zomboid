class_name CombatStateMachine
extends Node

# Preload 类引用
const CombatActionClass := preload("res://scripts/combat/combat_actions.gd")
const CombatCalculatorClass := preload("res://scripts/combat/combat_calculator.gd")
const WeaponClass := preload("res://scripts/items/weapon.gd")

enum Phase { EXPLORING, COMBAT_INIT, PLAYER_PHASE, ANIMATING, ENEMY_PHASE, ROUND_END, COMBAT_END }

var current_phase: Phase = Phase.EXPLORING
var input_locked: bool = false

## 当前玩家可选的动作
var available_actions: Array = []

## 当前选中的目标
var selected_target: Node = null

## 玩家是否正在行动中
var is_player_turn_active: bool = false

signal phase_changed(old_phase: Phase, new_phase: Phase)
signal player_actions_ready(actions: Array)
signal combat_log_updated(message: String)
signal target_selected(target: Node)
signal target_deselected()


func _ready() -> void:
	_connect_turn_manager()
	print("[CombatSM] 状态机就绪, 当前阶段: EXPLORING")


func _connect_turn_manager() -> void:
	TurnManager.combat_started.connect(_on_combat_started)
	TurnManager.combat_ended.connect(_on_combat_ended)
	TurnManager.round_started.connect(_on_round_started)
	TurnManager.round_ended.connect(_on_round_ended)
	TurnManager.player_turn_started.connect(_on_player_turn_started)
	TurnManager.unit_turn_started.connect(_on_unit_turn_started)
	TurnManager.player_phase_started.connect(_on_player_phase_started)
	TurnManager.player_phase_ended.connect(_on_player_phase_ended)


# --- 阶段切换 ---

func _set_phase(new_phase: Phase) -> void:
	var old := current_phase
	current_phase = new_phase
	phase_changed.emit(old, new_phase)
	print("[CombatSM] %s -> %s" % [_phase_name(old), _phase_name(new_phase)])

	match new_phase:
		Phase.PLAYER_PHASE:
			input_locked = false
			is_player_turn_active = true
			_refresh_actions()
		Phase.ENEMY_PHASE:
			input_locked = true
			is_player_turn_active = false
			selected_target = null
		Phase.ANIMATING:
			input_locked = true
		Phase.EXPLORING:
			input_locked = false
			is_player_turn_active = false


func _phase_name(p: Phase) -> String:
	match p:
		Phase.EXPLORING: return "探索"
		Phase.COMBAT_INIT: return "战斗初始化"
		Phase.PLAYER_PHASE: return "玩家阶段"
		Phase.ANIMATING: return "动画中"
		Phase.ENEMY_PHASE: return "敌人阶段"
		Phase.ROUND_END: return "回合结束"
		Phase.COMBAT_END: return "战斗结束"
	return "?"


# --- TurnManager 回调 ---

func _on_combat_started() -> void:
	combat_log_updated.emit("[战斗开始!]")
	_set_phase(Phase.COMBAT_INIT)
	await get_tree().create_timer(0.3).timeout
	_set_phase(Phase.PLAYER_PHASE)


func _on_combat_ended(victory: bool) -> void:
	var msg := "[胜利! 所有敌人已被击败]" if victory else "[战斗失败...]"
	combat_log_updated.emit(msg)
	_set_phase(Phase.COMBAT_END)


func _on_round_started(round_num: int) -> void:
	combat_log_updated.emit("--- 第 %d 回合 ---" % round_num)
	_set_phase(Phase.PLAYER_PHASE)


func _on_round_ended(_round_num: int) -> void:
	_set_phase(Phase.ROUND_END)


func _on_player_turn_started() -> void:
	if not TurnManager.combat_mode:
		return
	_set_phase(Phase.PLAYER_PHASE)


func _on_player_phase_started() -> void:
	_set_phase(Phase.PLAYER_PHASE)


func _on_player_phase_ended() -> void:
	_set_phase(Phase.ENEMY_PHASE)


func _on_unit_turn_started(unit: Node) -> void:
	_set_phase(Phase.ENEMY_PHASE)
	combat_log_updated.emit("[%s 开始行动]" % unit.name)


# --- 动作管理 ---

func _refresh_actions() -> void:
	available_actions.clear()

	var player := TurnManager.get_player()
	if not player:
		return

	# 主武器攻击
	var weapon: Resource = null
	if player.has_method("get") and player.get("equipped_weapon") != null:
		weapon = player.equipped_weapon

	if weapon and weapon.get("primary_action") != null:
		available_actions.append(weapon.primary_action)
	else:
		available_actions.append(CombatActionClass.create_melee_attack("punch", "拳击", 4, 0.6, CombatActionClass.DamageType.BLUNT))

	# 异能
	for ability in player.learned_abilities:
		if is_instance_of(ability, CombatActionClass):
			available_actions.append(ability)

	# 使用道具
	available_actions.append(CombatActionClass.create_item_action("use_item", "使用道具"))

	player_actions_ready.emit(available_actions)


func request_action(action: Resource, target: Node) -> bool:
	if input_locked:
		push_warning("[CombatSM] 输入被锁定, 无法执行动作")
		return false

	var player := TurnManager.get_player()
	if not player:
		return false

	if not is_instance_valid(target):
		# 对自身使用的动作
		if action.get("action_type") == CombatActionClass.ActionType.USE_ITEM:
			player.use_item_on_self("bandage")
			return true
		push_warning("[CombatSM] 需要选择目标")
		return false

	# 距离检查 (inline, 避免 CombatCalculator 静态方法兼容问题)
	var tile_size: int = player.tile_size if player.get("tile_size") != null else 32
	var dist_tiles: int = int(player.global_position.distance_to(target.global_position) / tile_size)
	if dist_tiles < action.get("range_min") or dist_tiles > action.get("range_max"):
		combat_log_updated.emit("[目标不在射程内!]")
		return false

	_set_phase(Phase.ANIMATING)

	match action.get("action_type"):
		CombatActionClass.ActionType.MELEE, CombatActionClass.ActionType.RANGED:
			player.execute_attack(target, action)
		CombatActionClass.ActionType.ABILITY:
			player.execute_ability(action, target)
		CombatActionClass.ActionType.USE_ITEM:
			player.use_item_on_self("bandage")

	await get_tree().create_timer(0.3).timeout
	_set_phase(Phase.PLAYER_PHASE)
	return true


func skip_turn() -> void:
	if input_locked:
		return
	var player := TurnManager.get_player()
	if player:
		player.force_end_turn()
	_set_phase(Phase.ENEMY_PHASE)


# --- 目标管理 ---

func select_target(target: Node) -> void:
	selected_target = target
	target_selected.emit(target)


func clear_target() -> void:
	selected_target = null
	target_deselected.emit()


func get_selected_target() -> Node:
	return selected_target


func is_player_turn() -> bool:
	return is_player_turn_active and not input_locked
