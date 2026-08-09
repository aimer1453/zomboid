extends Node

# ============================================================
# Main — 入口场景控制器 (Phase 2 更新)
# ============================================================

const CombatSM := preload("res://scripts/combat/combat_state_machine.gd")
var combat_state_machine: Node = null

func _ready() -> void:
	print("[Main] 游戏启动...")
	print("  引擎: Godot ", Engine.get_version_info().string)
	print("  分辨率: ", get_viewport().get_visible_rect().size)

	_verify_autoloads()
	_setup_combat_system()

	# 延迟到 _ready 之后 (场景树稳定) 再切换场景, 避免 headless/编辑器下
	# change_scene_to_file 在 _ready 期间被内部延迟丢弃导致卡在原场景
	call_deferred("_boot_game")


func _boot_game() -> void:
	# 启动进入"开始游戏"界面 (选角色 / 继续游戏), 由界面决定新游戏或读档
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _verify_autoloads() -> void:
	var required := ["GameManager", "TurnManager", "WorldTime", "DataManager", "PartyManager", "InventoryBackpack"]
	for name in required:
		var node := get_node_or_null("/root/" + name)
		assert(node, "Autoload 缺失: " + name)
	print("[Main] 所有 Autoload 就绪")


func _setup_combat_system() -> void:
	combat_state_machine = CombatSM.new()
	combat_state_machine.name = "CombatStateMachine"
	add_child(combat_state_machine)
	print("[Main] CombatStateMachine 已初始化")


func _has_saves() -> bool:
	return FileAccess.file_exists("user://saves/save_0.json")


func _load_or_new_game() -> void:
	GameManager.load_game()  # 硬核单槽 (HARDCORE_SAVE_SLOT=0), 无参版本


func _start_new_game() -> void:
	GameManager.start_new_game(GameManager.CharacterID.SPECIAL_FORCE)
