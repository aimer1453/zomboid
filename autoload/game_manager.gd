extends Node

# ============================================================
# GameManager — 游戏全局状态管理、场景切换、角色选择
# ============================================================

enum GameState {
	LOADING,
	MAIN_MENU,
	EXPLORING,
	COMBAT,
	INVENTORY,
	DIALOG,
	BUILDING,
	GAME_OVER,
}

enum CharacterID {
	NONE = 0,
	SPECIAL_FORCE = 1,
	HUNTER = 2,
	DOCTOR = 3,
	ELECTRICIAN = 4,
	PSYCHIC = 5,
}

## 角色中文名映射
const CHARACTER_NAMES := {
	CharacterID.SPECIAL_FORCE: "前特种兵",
	CharacterID.HUNTER: "老猎人",
	CharacterID.DOCTOR: "前医生",
	CharacterID.ELECTRICIAN: "电工",
	CharacterID.PSYCHIC: "通灵者",
}

var current_state: GameState = GameState.LOADING
var current_character: CharacterID = CharacterID.NONE

## 已解锁可选的初始角色
var unlocked_characters: Array = [CharacterID.SPECIAL_FORCE]
## 已招募为队友的角色
var recruited_characters: Array = []

## 主线任务进度 (用于控制世界状态)
var story_progress: int = 0
## 存档槽号
var active_save_slot: int = -1
## 新手引导模式 (新游戏开局=家园醒来+引导; 通关引导后关闭)
var _tutorial_active: bool = false

signal game_state_changed(new_state: GameState)
signal character_switched(new_character: CharacterID)


func _ready() -> void:
	print("[GameManager] 初始化完成")


## 新游戏开场: 家园醒来 + 新手引导
func is_tutorial_mode() -> bool:
	return _tutorial_active


## 新手引导完成 (家园场景调用, 之后新玩家出生带默认装备)
func set_tutorial_done() -> void:
	_tutorial_active = false
	print("[GameManager] 新手引导完成")


## 测试辅助: 手动开启/关闭引导模式
func set_tutorial_for_test(on: bool) -> void:
	_tutorial_active = on


func change_state(new_state: GameState) -> void:
	var old := current_state
	current_state = new_state
	game_state_changed.emit(new_state)
	print("[GameManager] ", GameState.keys()[old], " -> ", GameState.keys()[new_state])


func start_new_game(character: CharacterID) -> void:
	current_character = character
	unlocked_characters = [character]
	recruited_characters.clear()
	story_progress = 0
	_pending_player_data = {}
	# 新游戏: 重置建造/研究状态 (工作台预解锁)
	if BuildingManager:
		BuildingManager.reset()
	# 新游戏: 家园醒来 + 新手引导 (P1 开场流程)
	_tutorial_active = true
	change_state(GameState.EXPLORING)
	if get_tree():
		get_tree().call_deferred("change_scene_to_file", "res://scenes/home_base.tscn")


## 主角死亡: 硬核模式 → 删档 → 游戏结束
func game_over() -> void:
	print("[GameManager] 游戏结束! 硬核模式: 删除存档")
	delete_save()
	change_state(GameState.GAME_OVER)


func unlock_character(id: CharacterID) -> void:
	if id not in unlocked_characters:
		unlocked_characters.append(id)


func recruit_character(id: CharacterID) -> void:
	if id not in recruited_characters:
		recruited_characters.append(id)
		PartyManager.add_member(id)


func is_character_unlocked(id: CharacterID) -> bool:
	return id in unlocked_characters


func is_character_recruited(id: CharacterID) -> bool:
	return id in recruited_characters


func get_character_name(id: CharacterID) -> String:
	return CHARACTER_NAMES.get(id, "未知")


## 硬核模式: 固定单存档槽 (GDD 要求, 死亡自动删档)
const HARDCORE_SAVE_SLOT := 0


func save_game() -> bool:
	return save_game_slot(HARDCORE_SAVE_SLOT)


func save_game_slot(slot: int) -> bool:
	active_save_slot = slot
	var data := {
		"version": ProjectSettings.get_setting("application/config/version"),
		"character": current_character,
		"unlocked": unlocked_characters,
		"recruited": recruited_characters,
		"story_progress": story_progress,
	}
	# 委托各管理器补充数据
	data["inventory"] = InventoryBackpack.serialize()
	data["party"] = PartyManager.serialize()
	data["world_time"] = WorldTime.serialize()
	# 建造/研究进度持久化
	if BuildingManager:
		data["building"] = BuildingManager.serialize()
	# P0: 主角状态全量入档
	var player := TurnManager.get_player()
	if player and player.has_method("serialize"):
		data["player"] = player.serialize()
	return DataManager.save_to_slot(slot, data)


func load_game() -> bool:
	return load_game_slot(HARDCORE_SAVE_SLOT)


func load_game_slot(slot: int) -> bool:
	var data := DataManager.load_from_slot(slot)
	if data.is_empty():
		return false
	active_save_slot = slot
	current_character = data.get("character", CharacterID.NONE)
	unlocked_characters = data.get("unlocked", [])
	recruited_characters = data.get("recruited", [])
	story_progress = data.get("story_progress", 0)
	InventoryBackpack.deserialize(data.get("inventory", {}))
	PartyManager.deserialize(data.get("party", {}))
	WorldTime.deserialize(data.get("world_time", {}))
	# 建造/研究进度恢复
	if BuildingManager and data.has("building"):
		BuildingManager.deserialize(data["building"])
	# P0: 主角状态暂存, 场景加载后应用到 Player 节点
	_pending_player_data = data.get("player", {})
	change_state(GameState.EXPLORING)
	if get_tree():
		get_tree().call_deferred("change_scene_to_file", "res://scenes/world_map.tscn")
	return true


## 读档后的主角数据 (等 Player 节点就绪后应用)
var _pending_player_data: Dictionary = {}


## 由场景基类在 Player 创建后调用 (P0 存档应用链)
func apply_pending_player_data(player: Node) -> void:
	if _pending_player_data.is_empty():
		return
	if player and player.has_method("deserialize"):
		player.deserialize(_pending_player_data)
	_pending_player_data = {}


func has_save() -> bool:
	return DataManager.save_exists(HARDCORE_SAVE_SLOT)


func delete_save() -> void:
	DataManager.delete_slot(HARDCORE_SAVE_SLOT)
