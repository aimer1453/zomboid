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

## 角色档案: 背景故事 + 异能系列 + 主线任务 (每个角色 4 步, 索引 0..3)
## 主线推进由共享玩法里程碑驱动 (出院/进副本/击杀/天数), 文本按角色区分
const CHARACTER_PROFILES := {
	CharacterID.SPECIAL_FORCE: {
		"series": "钢铁意志 · 近战系",
		"background": "病毒爆发前你是特种部队突击手，经历过最惨烈的巷战。城市在七天里沦陷，你凭训练活了下来，小队却失散了。回到临时安全屋，你决心找回幸存的兄弟。",
		"main_quest": [
			"在废土中醒来，恢复体能",
			"走出安全屋，踏入废土",
			"探索一处沦陷的军事据点",
			"击退尸潮，找回失散的小队",
		],
	},
	CharacterID.HUNTER: {
		"series": "荒野之眼 · 远程/陷阱系",
		"background": "你在北境森林当了三十年猎人，比谁都懂怎么在野外活着。末日来时你正带着女儿避世山林，如今她失踪了，你循着足迹走向文明的废墟。",
		"main_quest": [
			"在林间小屋中整理行装",
			"走出猎屋，进入荒废城镇",
			"设伏清剿一支尸群",
			"追踪女儿踪迹，揭开营地秘密",
		],
	},
	CharacterID.DOCTOR: {
		"series": "生命回响 · 辅助/化学系",
		"background": "你是市第一医院主治医师，疫情初期就怀疑这不只是流感。医院被感染者淹没时，你带着仅存的血清样本突围，想找到解药的答案。",
		"main_quest": [
			"在废弃诊室中稳住伤情",
			"走出诊所，进入污染区",
			"采集变异样本，解析病毒",
			"合成抑制药剂，点亮希望",
		],
	},
	CharacterID.ELECTRICIAN: {
		"series": "电流脉动 · 技术/机械系",
		"background": "你是城市电网抢修工，懂电路也懂机械。停电后你靠一台旧发电机撑了半个月，现在要去变电站重启供电，重建文明的灯火。",
		"main_quest": [
			"在车库中检修装备",
			"走出车库，穿越断电街区",
			"修复一座废弃变电站",
			"重启电网，为据点供能",
		],
	},
	CharacterID.PSYCHIC: {
		"series": "虚空低语 · 法系/精神系",
		"background": "你从小能听见死者的低语，被当作疯子关了多年。末日爆发后，那些声音变成预警——你能感知尸群的意念。你走出收容所，想去听听\"源头\"在说什么。",
		"main_quest": [
			"在收容所废墟中清醒",
			"走出收容所，进入低语区",
			"连接一处尸群意识节点",
			"聆听虚空源头，揭开真相",
		],
	},
}

## 成就解锁规则: 满足条件 → 解锁对应角色 (stat 累计于整局游戏, 跨角色共享)
## kills = 累计击杀, days = 累计存活天数
const CHARACTER_UNLOCK_RULES := {
	CharacterID.HUNTER:     {"stat": "kills", "threshold": 15, "hint": "累计击杀 15 只丧尸解锁"},
	CharacterID.DOCTOR:     {"stat": "days",  "threshold": 7,  "hint": "存活满 7 天解锁"},
	CharacterID.ELECTRICIAN:{"stat": "kills", "threshold": 40, "hint": "累计击杀 40 只丧尸解锁"},
	CharacterID.PSYCHIC:    {"stat": "days",  "threshold": 15, "hint": "存活满 15 天解锁"},
}

var current_state: GameState = GameState.LOADING
var current_character: CharacterID = CharacterID.NONE

## 已解锁可选的初始角色
var unlocked_characters: Array = [CharacterID.SPECIAL_FORCE]
## 已招募为队友的角色
var recruited_characters: Array = []

## 累计统计 (成就解锁用, 跨角色共享; 启动从 meta 读取)
var stats := {"kills": 0, "days": 0}

## 主线任务进度 (0..3, 控制任务面板高亮; 受共享里程碑推进)
var story_progress: int = 0
## 存档槽号
var active_save_slot: int = -1
## 新手引导模式 (新游戏开局=家园醒来+引导; 通关引导后关闭)
var _tutorial_active: bool = false

signal game_state_changed(new_state: GameState)
signal character_switched(new_character: CharacterID)

## 死亡结算界面 (主角死亡时弹出: 你死了 + 重新开始/读档)
const DeathScreen := preload("res://scenes/death_screen.tscn")
var _death_screen: CanvasLayer = null


func _ready() -> void:
	# 启动即读取元存档 (已解锁角色 + 统计), 让成就跨会话生效, 即使尚未读档
	var meta := DataManager.load_meta()
	if not meta.is_empty():
		var u: Array = meta.get("unlocked", [])
		if u.size() > 0:
			unlocked_characters = u
		var s: Dictionary = meta.get("stats", {})
		if not s.is_empty():
			stats = s
	print("[GameManager] 初始化完成, 已解锁角色: ", unlocked_characters)


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
	# 注意: 不重置 unlocked_characters — 成就解锁是永久的, 跨周目保留
	recruited_characters.clear()
	story_progress = 0
	_pending_player_data = {}
	# 新游戏: 重置建造/研究状态 (工作台预解锁)
	if BuildingManager:
		BuildingManager.reset()
	# 新游戏: 重置无限世界地图 (家在原点, 全新探索)
	if WorldMapData:
		WorldMapData.reset_map()
	# 新游戏: 家园醒来 + 新手引导 (P1 开场流程)
	_tutorial_active = true
	change_state(GameState.EXPLORING)
	if get_tree():
		get_tree().call_deferred("change_scene_to_file", "res://scenes/home_base.tscn")


## 主角死亡: 弹出死亡结算界面 (保留存档, 由界面提供"读档"重试)
func game_over(reason: String = "") -> void:
	print("[GameManager] 主角死亡 → 弹出死亡结算界面")
	change_state(GameState.GAME_OVER)
	_show_death_screen(reason)


## 显示死亡结算界面并暂停游戏树 (界面自身 process_mode=ALWAYS, 暂停期按钮可点)
func _show_death_screen(reason: String = "") -> void:
	if _death_screen == null:
		_death_screen = DeathScreen.instantiate()
		add_child(_death_screen)
	_death_screen.show_screen(reason, has_save())
	get_tree().paused = true


## 隐藏死亡界面并恢复游戏树 (重新开始/读档时调用)
func hide_death_screen() -> void:
	if _death_screen:
		_death_screen.hide_screen()
	get_tree().paused = false


## 死亡界面"重新开始": 开新游戏 (沿用当前角色)
func restart_from_death() -> void:
	hide_death_screen()
	var char_id: CharacterID = current_character if current_character != CharacterID.NONE else CharacterID.SPECIAL_FORCE
	start_new_game(char_id)


## 死亡界面"读档": 读最后一次存档 (无档则不动作)
func load_from_death() -> void:
	if not has_save():
		return
	hide_death_screen()
	load_game()


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


## 角色档案查询 (开始界面 / 任务面板用)
func get_character_profile(id: CharacterID) -> Dictionary:
	return CHARACTER_PROFILES.get(id, {})


func get_character_series(id: CharacterID) -> String:
	return CHARACTER_PROFILES.get(id, {}).get("series", "")


func get_character_background(id: CharacterID) -> String:
	return CHARACTER_PROFILES.get(id, {}).get("background", "")


func get_character_quest(id: CharacterID) -> Array:
	return CHARACTER_PROFILES.get(id, {}).get("main_quest", [])


## 当前角色的主线任务 (供任务面板展示)
func get_current_quest() -> Dictionary:
	var id: CharacterID = current_character if current_character != CharacterID.NONE else CharacterID.SPECIAL_FORCE
	return {
		"character_id": id,
		"name": get_character_name(id),
		"series": get_character_series(id),
		"background": get_character_background(id),
		"steps": get_character_quest(id),
		"current": story_progress,
	}


## 成就解锁提示 (开始界面锁定卡片显示)
func get_unlock_hint(id: CharacterID) -> String:
	if is_character_unlocked(id):
		return ""
	return CHARACTER_UNLOCK_RULES.get(id, {}).get("hint", "达成隐藏成就解锁")


## 统计累计 (由 gameplay 钩子调用)
func record_kill() -> void:
	stats["kills"] = int(stats.get("kills", 0)) + 1
	check_character_unlocks()
	# 击杀里程碑推进主线 (步骤 4 = 索引 3)
	if int(stats.get("kills", 0)) >= 20:
		advance_story(3)


func record_day() -> void:
	stats["days"] = int(stats.get("days", 0)) + 1
	check_character_unlocks()
	# 存活里程碑推进主线 (步骤 4 = 索引 3)
	if int(stats.get("days", 0)) >= 10:
		advance_story(3)


## 检查并解锁达成条件的角色; 返回本次新解锁的角色名列表
func check_character_unlocks() -> Array:
	var newly_unlocked: Array = []
	for id in CHARACTER_UNLOCK_RULES.keys():
		if is_character_unlocked(id):
			continue
		var rule: Dictionary = CHARACTER_UNLOCK_RULES[id]
		var val: int = int(stats.get(rule.get("stat", "kills"), 0))
		if val >= int(rule.get("threshold", 999999)):
			unlock_character(id)
			newly_unlocked.append(get_character_name(id))
	if newly_unlocked.size() > 0:
		# 解锁即刻持久化到元存档, 跨会话保留
		DataManager.save_meta({"unlocked": unlocked_characters, "stats": stats})
		print("[GameManager] 成就解锁: ", newly_unlocked)
	return newly_unlocked


## 推进主线进度 (target 为步骤索引, 只增不减, 不超出任务长度-1)
func advance_story(target: int) -> void:
	var steps: int = get_character_quest(current_character).size()
	var max_idx: int = maxi(steps - 1, 0)
	story_progress = clampi(maxi(story_progress, target), 0, max_idx)



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
		"stats": stats,
	}
	# 委托各管理器补充数据
	data["inventory"] = InventoryBackpack.serialize()
	data["party"] = PartyManager.serialize()
	data["world_time"] = WorldTime.serialize()
	# 建造/研究进度持久化
	if BuildingManager:
		data["building"] = BuildingManager.serialize()
	# 无限世界地图持久化 (已生成地形 + 已探索视野 + 主角位置)
	if WorldMapData:
		data["world_map"] = WorldMapData.serialize()
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
	stats = data.get("stats", {"kills": 0, "days": 0})
	InventoryBackpack.deserialize(data.get("inventory", {}))
	PartyManager.deserialize(data.get("party", {}))
	WorldTime.deserialize(data.get("world_time", {}))
	# 建造/研究进度恢复
	if BuildingManager and data.has("building"):
		BuildingManager.deserialize(data["building"])
	# 无限世界地图恢复 (已生成地形 + 已探索视野 + 主角位置)
	if WorldMapData and data.has("world_map"):
		WorldMapData.deserialize(data["world_map"])
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
