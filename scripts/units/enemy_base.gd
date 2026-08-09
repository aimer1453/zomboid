extends "res://scripts/units/character.gd"

# ============================================================
# EnemyBase — 敌人/丧尸基类 (继承 Character)
# ============================================================
# AI 状态机: 待机/巡逻/追击/攻击/逃跑
# 探索模式: patrol_action 每 1.5s 触发, 发现玩家 → 感叹号 + 追击(格子移动)
# 战斗模式: take_turn 按 AP 行动, 距离不够接近, 距离够了攻击
# 子类覆写: _get_attack_action() / _perform_attack()
# CA/CC 常量继承自 Character 基类

const AR := preload("res://scripts/ui/alert_range.gd")
const Corpse := preload("res://scripts/tiles/corpse.gd")

enum AIState { IDLE, PATROL, CHASE, ATTACK, FLEE, DEAD }

## 名称与属性
@export var enemy_id: String = "zombie_basic"
@export var enemy_name: String = "丧尸"

## AI 参数
var ai_state: AIState = AIState.IDLE
var _target: Node = null
@export var detection_range: int = 5
@export var attack_range: int = 1
@export var flee_hp_threshold: float = 0.25

## 卷入半径 (格): 一只丧尸发现玩家 → 仅此半径内的丧尸被"惊动"加入战斗,
## 范围外的丧尸保持巡逻, 不会整层扑过来 (用户反馈: 惊动一个就全层来打)
const AGGRO_RADIUS_TILES := 10
## 是否已卷入当前这场战斗 (范围外未卷入的丧尸不追击/不计为敌人)
var _engaged: bool = false

## 掉落
@export var xp_reward: int = 10
@export var crystal_drop_chance: float = 0.05

## 巡逻原点
var _patrol_origin: Vector2 = Vector2.ZERO

## 发现感叹号
var _alert_label: Label = null
var _alert_timer: float = 0.0
const ALERT_DURATION: float = 2.0

## 警戒范围红圈
var _alert_range: Node2D = null

signal enemy_died(enemy: Node)


## 子类重写: 返回该丧尸的差异化属性表 (仅写与基类默认值不同的项).
## 基类 _apply_stats() 据此覆盖默认值, 子类不再各自重复 _ready 样板.
func _define_stats() -> Dictionary:
	return {}


## 应用属性表: 子类 _define_stats() 提供的差异化数值覆盖基类默认.
## 必须在 super._ready() (Character._ready) 之前调用 —— Character 会据 max_hp/ap_max 重置 hp/ap_current.
func _apply_stats() -> void:
	var s := _define_stats()
	if s.has("enemy_id"): enemy_id = s["enemy_id"]
	if s.has("enemy_name"): enemy_name = s["enemy_name"]
	if s.has("max_hp"): max_hp = s["max_hp"]
	if s.has("ap_max"): ap_max = s["ap_max"]
	if s.has("attack_power"): attack_power = s["attack_power"]
	if s.has("defense"): defense = s["defense"]
	if s.has("detection_range"): detection_range = s["detection_range"]
	if s.has("attack_range"): attack_range = s["attack_range"]
	if s.has("flee_hp_threshold"): flee_hp_threshold = s["flee_hp_threshold"]
	if s.has("xp_reward"): xp_reward = s["xp_reward"]
	if s.has("crystal_drop_chance"): crystal_drop_chance = s["crystal_drop_chance"]
	# hp/ap_current 始终由 max_hp/ap_max 派生, 不受外部残留值影响
	hp = max_hp
	ap_current = ap_max


func _ready() -> void:
	_apply_stats()
	_patrol_origin = global_position
	super._ready()
	_setup_alert()
	_setup_alert_range()
	# 进入战斗后隐藏警戒范围 (用户反馈: 已触发战斗逻辑的丧尸不再显示红圈)
	TurnManager.combat_started.connect(_hide_alert_range_on_combat)
	# 战斗结束 → 重置卷入状态, 下次探索重新判定 "范围内才来"
	TurnManager.combat_ended.connect(_reset_engagement_on_combat_end)
	print("[Enemy] ", enemy_name, " 就绪 HP=", hp)


## 战斗开始 → 隐藏所有丧尸的警戒红圈
func _hide_alert_range_on_combat() -> void:
	if _alert_range:
		_alert_range.visible = false


func get_display_name() -> String:
	return enemy_name


func _process(delta: float) -> void:
	if _alert_label and _alert_label.visible:
		_alert_timer -= delta
		if _alert_timer <= 0:
			_alert_label.visible = false


# --- 发现感叹号 ---

func _setup_alert() -> void:
	_alert_label = Label.new()
	_alert_label.text = "!"
	_alert_label.add_theme_font_size_override("font_size", 30)
	_alert_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	_alert_label.add_theme_color_override("font_outline_color", Color(0.3, 0.1, 0.0))
	_alert_label.add_theme_constant_override("outline_size", 4)
	_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_label.position = Vector2(-12, -tile_size * 0.95)
	_alert_label.visible = false
	# 纯视觉: 不拦截鼠标 (否则会吞掉点击/让悬停高亮被隐藏)
	_alert_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 探索迷雾穿透: 感叹号在黑幕(z=100)之上, 即使未探索区有丧尸发现角色也能看到
	_alert_label.z_index = 300
	add_child(_alert_label)


func show_alert() -> void:
	if _alert_label:
		_alert_label.visible = true
		_alert_timer = ALERT_DURATION


## 卷入战斗 (公开, 供 TurnManager.propagate_aggro 调用): 仅首次设置并亮感叹号
func engage() -> void:
	if _engaged:
		return
	_engaged = true
	show_alert()


## 解除卷入: 追出半径外时回到巡逻, 不再算作战斗敌人
func disengage() -> void:
	_engaged = false


## 是否已卷入当前战斗 (供 TurnManager 判断哪些丧尸算"敌人"并参与回合/计入胜负)
func is_engaged() -> bool:
	return _engaged


## 战斗结束 → 重置卷入状态, 下次探索重新判定 (由 combat_ended 信号触发)
func _reset_engagement_on_combat_end(_victory: bool) -> void:
	_engaged = false


## 警戒范围红圈 (曼哈顿距离格子, 半径 = detection_range)
func _setup_alert_range() -> void:
	_alert_range = AR.new()
	_alert_range.name = "AlertRange"
	_alert_range.set_range(detection_range, tile_size)
	add_child(_alert_range)


# --- 探索模式巡逻 (TurnManager 每 1.5s 触发一次) ---

## 已脱离战斗但未删除 (逃跑两阶段: 先脱离, 再删)
var _escape_detached: bool = false
## 逃跑脱离阈值: 离玩家超过此格数 → 脱离战斗 (但保留在地图上) (用户反馈)
const FLEE_DETACH_TILES := 10
## 逃跑删除阈值: 脱离后再远离到比格数 → 从地图删除 (用户反馈: 脱离之后才删)
const FLEE_DELETE_TILES := 16


func patrol_action() -> void:
	if hp <= 0 or is_moving:
		return
	var player := TurnManager.get_player()
	# 已脱离战斗: 只持续远离, 足够远后删除 (两阶段逃跑)
	if _escape_detached:
		if player and is_instance_valid(player):
			if global_position.distance_to(player.global_position) >= tile_size * FLEE_DELETE_TILES:
				_escape_remove_from_world()
				return
		else:
			_escape_remove_from_world()
			return
		return
	if player and is_instance_valid(player) and player.get("hp") != null and player.get("hp") > 0:
		var dist := int(global_position.distance_to(player.global_position) / tile_size)
		# 丧尸视野受墙遮挡: 距离内还要直线可视才被发现 (隔墙看不到玩家)
		# has_line_of_sight 定义在 Character 基类 (所有单位通用视觉感知)
		if dist <= detection_range and has_line_of_sight(player.global_position):
			# 玩家进入警戒范围 → 卷入战斗 (仅自己 + 半径内同伴, 不会全层扑来)
			engage()
			TurnManager.enter_combat()
			return
	# 随机巡逻 1 步 (4 方向, 禁对角 — 对角会斜穿墙/峭壁的角)
	var rand_dir := _rand_dir_4()
	if rand_dir == Vector2.ZERO:
		return
	var rand_target := snap_to_grid(global_position + rand_dir * tile_size)
	if not rand_target.is_equal_approx(global_position):
		start_walk(rand_target)


# --- 战斗回合 AI (Take Turn) ---

func take_turn() -> void:
	if hp <= 0:
		ai_state = AIState.DEAD
		return

	# 先评估威胁: 战斗中未卷入的丧尸若已走入 detection_range 且有视线 → 卷入并继续行动
	_evaluate_threat()

	# 战斗中仍未卷入 (范围外/无视线): 冻结待命, 不乱走不抢戏
	if TurnManager.combat_mode and not _engaged:
		_send_turn_report()
		return

	match ai_state:
		AIState.ATTACK:
			_perform_attack()
		AIState.CHASE:
			_step_toward_player(1)
		AIState.FLEE:
			_step_away_from_player()
		AIState.PATROL:
			_step_random()
		_:
			pass

	# 同步返回: 移动动画由 _physics_process 并行播放,
	# TurnManager 统一等待所有敌人移动结束 (保证同时行动, 避免逐个回合)
	_send_turn_report()


func _evaluate_threat() -> void:
	if hp <= max_hp * flee_hp_threshold:
		ai_state = AIState.FLEE
		_target = null
		return

	var player := TurnManager.get_player()
	if not player or not is_instance_valid(player) or player.get("hp") == null or player.get("hp") <= 0:
		ai_state = AIState.IDLE
		_target = null
		return

	var dist := int(global_position.distance_to(player.global_position) / tile_size)

	if dist <= attack_range:
		ai_state = AIState.ATTACK
		_target = player
	elif _engaged:
		# 已卷入: 在传播半径内继续追 (听到打斗/被警报); 追出太远则解除卷入, 回巡逻
		if dist <= AGGRO_RADIUS_TILES:
			ai_state = AIState.CHASE
			_target = player
		else:
			disengage()
			ai_state = AIState.PATROL
			_target = null
	elif dist <= detection_range and has_line_of_sight(player.global_position):
		# 战斗中尚未卷入, 但自己直接看到玩家 → 卷入 (范围外的不自动卷入)
		engage()
		ai_state = AIState.CHASE
		_target = player
	else:
		ai_state = AIState.PATROL
		_target = null


func _send_turn_report() -> void:
	var used: int = mini(ap_current, ap_max)
	ap_current -= used


# --- 移动 (格子化, 平滑动画) ---

## 4 方向随机 (禁对角: 对角移动会斜穿墙/峭壁的角 — 用户反馈"峭壁能越过去"+"单位没按格走")
func _rand_dir_4() -> Vector2:
	var dirs: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	return dirs[randi() % dirs.size()]


func _step_toward_player(_steps: int = 1) -> void:
	var player := TurnManager.get_player()
	if not player or not is_instance_valid(player):
		return
	# 4 方向 (禁对角): 按差值大的轴朝玩家走 1 格
	var delta: Vector2 = player.global_position - global_position
	var dir := Vector2.ZERO
	if absf(delta.x) >= absf(delta.y):
		dir = Vector2(signf(delta.x), 0)
	else:
		dir = Vector2(0, signf(delta.y))
	if dir == Vector2.ZERO:
		return
	var target := snap_to_grid(global_position + dir * tile_size)
	# 目标不能是玩家所在格
	if target.distance_to(player.global_position) < tile_size * 0.5:
		return
	start_walk(target)


func _step_away_from_player() -> void:
	var player := TurnManager.get_player()
	if not player:
		return
	# 阶段1: 离玩家超过脱离阈值 → 脱离战斗 (保留在地图, 不删) (用户反馈: 不是一逃跑就脱离/删除)
	if not _escape_detached and global_position.distance_to(player.global_position) >= tile_size * FLEE_DETACH_TILES:
		_escape_detach_from_combat()
		return
	# 阶段2 (已脱离): 离玩家超过删除阈值 → 从地图删除
	if _escape_detached and global_position.distance_to(player.global_position) >= tile_size * FLEE_DELETE_TILES:
		_escape_remove_from_world()
		return
	# 4 方向 (禁对角)
	var delta: Vector2 = global_position - player.global_position
	var dir := Vector2.ZERO
	if absf(delta.x) >= absf(delta.y):
		dir = Vector2(signf(delta.x), 0)
	else:
		dir = Vector2(0, signf(delta.y))
	if dir == Vector2.ZERO:
		return
	var target := snap_to_grid(global_position + dir * tile_size)
	start_walk(target)


## 阶段1: 脱离战斗 — 从战斗系统移除单位, 但保留在地图上继续逃跑 (用户反馈: 先脱离)
func _escape_detach_from_combat() -> void:
	_escape_detached = true
	print("[", enemy_name, "] 逃出战斗范围, 脱离战斗 (保留在地图)")
	if TurnManager and TurnManager.has_method("unregister_unit"):
		TurnManager.unregister_unit(self)


## 阶段2: 从地图删除 (用户反馈: 脱离之后足够远才删)
func _escape_remove_from_world() -> void:
	print("[", enemy_name, "] 逃跑成功, 从地图移除")
	queue_free()


func _step_random() -> void:
	var rand_dir := _rand_dir_4()
	var target := snap_to_grid(global_position + rand_dir * tile_size)
	start_walk(target)


func _on_arrived() -> void:
	# 探索模式: 丧尸走到玩家身边 → 触发战斗
	if TurnManager and not TurnManager.combat_mode:
		var player := TurnManager.get_player()
		if player and is_instance_valid(player):
			var d := int(global_position.distance_to(player.global_position) / tile_size)
			if d <= 1:
				engage()
				TurnManager.enter_combat()


# --- 攻击 (子类可覆写) ---

func _get_attack_action() -> Resource:
	return CA.create_melee_attack("enemy_attack", "攻击", 4, 1.0)


func _perform_attack() -> void:
	var target := _target
	if not target or not is_instance_valid(target):
		return
	# 攻击前吼叫 (用户反馈: 丧尸攻击时要吼叫一下)
	if SoundManager:
		SoundManager.play("zombie_growl.wav", -4.0)
	execute_attack(target, _get_attack_action())


# --- 死亡 (敌人) ---

## 低级装备掉落池 (所有丧尸都可能穿, 玩家可捡可卖)
const LOOT_LOW_GEAR: Array[String] = ["torn_clothes", "torn_pants", "dirty_shoes", "rusty_knife"]

## 死亡时生成尸体 (供玩家搜刮); 搜空后尸体自动消失
func _spawn_corpse() -> void:
	var world := get_parent()
	if not world:
		return
	var loot := _get_corpse_loot()
	if loot.is_empty():
		return  # 没东西就一了百了, 不生成空尸体
	var corpse := Corpse.new()
	# 用 floor 取整 (与 game_scene_base._cell_of / Tile.world_to_grid 一致): 活体停在格中心时
	# center/tile = cell + 0.5, roundi 会进位到 cell+1 → 尸体偏到右下角一格; 必须用 floor 落在丧尸所在格
	var gp := Vector2i(floori(global_position.x / tile_size), floori(global_position.y / tile_size))
	# 尸体标签: "普通丧尸\n(尸体)" 两行, 居中 (用户反馈: 不居中 + 格式)
	corpse.setup_corpse(gp, tile_size, loot, "%s\n(尸体)" % enemy_name)
	world.add_child(corpse)
	if world.has_method("add_corpse"):
		world.add_corpse(corpse)
	print("[", enemy_name, "] 死亡 → 尸体生成 (", loot, ") at ", gp)


## 按丧尸类型生成掉落:
##   所有丧尸: 基础血肉 1-2 + 低级装备 (破旧衣衫等) 高概率
##   疾速丧尸: +25% 晶石碎片
##   喷射丧尸: +10% 能量晶石
##   坦克丧尸: 必出晶簇 + 5% 大能量晶石
func _get_corpse_loot() -> Array:
	var loot: Array = []
	# 基础血肉 1-2
	var flesh_count: int = 1 + (1 if randf() < 0.5 else 0)
	for i in flesh_count:
		loot.append("zombie_flesh")
	# 低级装备 (丧尸身上扒下来的): 70% 概率出 1 件, 25% 出 2 件
	var gear_roll := randf()
	if gear_roll < 0.70:
		loot.append(LOOT_LOW_GEAR[randi() % LOOT_LOW_GEAR.size()])
	elif gear_roll < 0.95:
		var first := LOOT_LOW_GEAR[randi() % LOOT_LOW_GEAR.size()]
		var second := LOOT_LOW_GEAR[randi() % LOOT_LOW_GEAR.size()]
		loot.append(first)
		if second != first:
			loot.append(second)
	# 变体专属掉落
	if enemy_id == "zombie_runner" and randf() < 0.25:
		loot.append("crystal_shard")
	elif enemy_id == "zombie_spitter" and randf() < 0.10:
		loot.append("crystal_smooth")
	elif enemy_id == "zombie_tank":
		loot.append("crystal_cluster")
		if randf() < 0.05:
			loot.append("crystal_huge")
	return loot


## 死亡差异化钩子: 生成尸体 (基类 die() 已统一处理注销)
func _on_died() -> void:
	ai_state = AIState.DEAD
	enemy_died.emit(self)
	_spawn_corpse()
	queue_free()


# --- 属性导出 (覆盖) ---

func get_combat_stats() -> Dictionary:
	return {
		"name": enemy_name,
		"attack": attack_power,
		"defense": defense,
		"hp": hp,
		"max_hp": max_hp,
		"crit_bonus": 0.0,
		"armor_pierce": 0.0,
	}
