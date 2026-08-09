extends CharacterBody2D

# ============================================================
# Character — 所有单位基类 (玩家/丧尸/NPC)
# ============================================================
# 统一能力:
#   - 格子移动: WASD 单格 / 点击连续移动(路径队列) / 单目标平滑移动
#   - 战斗: 攻击(CombatAction) / 伤害 / 死亡
#   - 背包: 接口转发到 InventoryBackpack (全局背包)
#   - 回合: TurnManager 注册 + 信号
#
# 子类钩子:
#   - _on_arrived(): 移动到目标后调用 (玩家=扣AP+连续移动, 敌人=接触检测)
#   - _handle_player_input(): 仅玩家有键盘输入
#   - get_combat_stats(): 覆盖以提供独特属性

const CA := preload("res://scripts/combat/combat_actions.gd")
const CC := preload("res://scripts/combat/combat_calculator.gd")
const DP := preload("res://scripts/ui/damage_popup.gd")
const UHB := preload("res://scripts/ui/unit_health_bar.gd")

## 是否为玩家单位 (影响 TurnManager 注册和回合驱动)
@export var is_player_unit: bool = false

## 格子类型: 角色类 (与 Tile.TileType.CHARACTER = 1 一致)
const TILE_TYPE_CHARACTER := 1

func get_tile_type() -> int:
	return TILE_TYPE_CHARACTER

## 数值属性
@export var max_hp: float = 100.0
var hp: float = max_hp
@export var ap_max: int = 10
var ap_current: int = ap_max
@export var attack_power: float = 10.0
@export var defense: float = 3.0
@export var move_speed: float = 200.0
@export var tile_size: int = 32

## 回合/移动状态
var is_my_turn: bool = false
var is_moving: bool = false
var _target_position: Vector2 = Vector2.ZERO
var _path_queue: Array[Vector2] = []
var _keys_held: bool = false

## 走路摆动 (每步左右倾斜交替, 更有动感)
const WALK_TILT_ANGLE := 15.0        # 单步最大倾斜角度 (度)
const TILT_SPEED := 10.0             # 倾斜插值速度
var _walk_step_count: int = 0        # 累计步数 (奇偶决定倾斜方向)
var _target_tilt: float = 0.0        # 当前步目标倾角 (弧度)

## 战斗
var equipped_weapon: Resource = null
var learned_abilities: Array = []

## 已装备物品: 槽位(weapon/armor/backpack) -> item_id (装备系统)
var equipped_slots: Dictionary = {}

## 所属世界节点 (主地图/副本), 提供 is_cell_walkable(cell_center) 用于寻路障碍检测
var world: Node = null

## 头顶血条 (战斗时显示)
var _health_bar: Node2D = null

signal move_completed()
signal movement_stopped()
signal action_completed(action_name: String, ap_cost: int)
signal hp_changed(new_hp: float, max_hp: float)
signal ap_changed(new_ap: int, max_ap: int)
signal combat_action_executed(action: Resource, target: Node, result: Dictionary)


func _ready() -> void:
	hp = max_hp
	ap_current = ap_max
	TurnManager.register_unit(self, is_player_unit)
	TurnManager.player_turn_started.connect(_on_player_turn_started)
	TurnManager.combat_started.connect(_on_combat_started)
	TurnManager.combat_ended.connect(_on_combat_ended)
	if is_player_unit:
		is_my_turn = true  # 探索模式开局即可行动
	_setup_health_bar()


# --- 头顶血条 ---

func _setup_health_bar() -> void:
	_health_bar = UHB.new()
	_health_bar.name = "HealthBar"
	_health_bar.setup(tile_size)
	add_child(_health_bar)


func _on_combat_started() -> void:
	if _health_bar:
		_health_bar.set_bar_visible(true)
		_health_bar.update_health(hp, max_hp)


func _on_combat_ended(_victory: bool = false) -> void:
	if _health_bar:
		_health_bar.set_bar_visible(false)
	# 战斗结束 → 精力(AP)恢复满 (用户反馈: 战斗后精力条应回到 100%)
	ap_current = ap_max
	ap_changed.emit(ap_current, ap_max)


# --- 飘字 ---

## 单位头顶弹出文字 (扣血红字/暴击金字/MISS灰字)
func show_float_text(text: String, color: Color = Color(1.0, 0.3, 0.3), font_size: int = 22, y_offset: float = 0.0) -> void:
	var popup := DP.new()
	popup.setup(text, color, font_size)
	popup.position = Vector2(0, -tile_size * 0.9 + y_offset)
	add_child(popup)


func _physics_process(delta: float) -> void:
	# 走路摆动: 移动中朝当前步目标倾角插值, 停止时回正
	if _walk_step_count > 0:
		var tilt_target := _target_tilt if is_moving else 0.0
		rotation = lerp_angle(rotation, tilt_target, minf(delta * TILT_SPEED, 1.0))

	if is_moving:
		var direction := (_target_position - global_position).normalized()
		var step := move_speed * delta
		if global_position.distance_to(_target_position) <= step:
			global_position = _target_position
			is_moving = false
			_play_footstep()
			_clear_debug_path()
			move_completed.emit()
			_on_arrived()
		else:
			velocity = direction * move_speed
			move_and_slide()
			queue_redraw()  # 寻路引导线跟随角色移动
			return

	if is_my_turn and not is_moving and is_player_unit:
		_handle_player_input()


## 到达/中断后清除寻路引导线
func _clear_debug_path() -> void:
	if not _debug_path.is_empty():
		_debug_path.clear()
		queue_redraw()


## 启动一步移动: 步数 +1, 奇偶交替设定倾斜方向 (第1步 +15°, 第2步 -15° ...)
func _begin_walk_step() -> void:
	_walk_step_count += 1
	_target_tilt = deg_to_rad(WALK_TILT_ANGLE if _walk_step_count % 2 == 1 else -WALK_TILT_ANGLE)


## 移动一格播放脚步声 (自动扫描 footstep_* 随机播放; 玩家 -8dB, 丧尸 -14dB)
func _play_footstep() -> void:
	if SoundManager:
		var vol := -8.0 if is_player_unit else -14.0
		SoundManager.play_footstep(vol)


## 子类钩子: 移动到目标后触发
func _on_arrived() -> void:
	pass


# --- 类型化属性访问 (P1-1: 替代 Node.get 鸭子访问, 类型安全, 属性改名编译期即报错) ---
# TurnManager / 场景基类 / UI 一律通过这里读写, 不要用 unit.get("ap_current") 这类反射。

func get_ap() -> int:
	return ap_current

func set_ap(value: int) -> void:
	var prev := ap_current
	ap_current = maxi(value, 0)
	if ap_current != prev:
		ap_changed.emit(ap_current, ap_max)

func get_ap_max() -> int:
	return ap_max

func get_hp() -> float:
	return hp

func get_max_hp() -> float:
	return max_hp

func get_is_moving() -> bool:
	return is_moving

func set_is_moving(value: bool) -> void:
	is_moving = value


# --- 回合 ---

func _on_player_turn_started() -> void:
	if not is_player_unit:
		return
	is_my_turn = true
	if not TurnManager.combat_mode:
		ap_current = ap_max
	ap_changed.emit(ap_current, ap_max)
	print("[", get_display_name(), "] 轮到行动 (AP: ", ap_current, "/", ap_max, ")")


func get_display_name() -> String:
	return name


func _handle_player_input() -> void:
	# 移动输入 (格状)
	# 探索模式: 按住连续走; 战斗模式: 防连走 (单动作回合制, 需松开再按)
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir != Vector2.ZERO:
		if _keys_held and TurnManager.combat_mode:
			return
		_keys_held = true
		move_in_direction(input_dir)
		return
	_keys_held = false

	if Input.is_action_just_pressed("wait_turn"):
		_end_turn()


func _end_turn() -> void:
	is_my_turn = false
	print("[", get_display_name(), "] 结束行动")

	if TurnManager.combat_mode:
		TurnManager.end_player_phase()
	else:
		TurnManager.process_turn_queue()


func force_end_turn() -> void:
	_end_turn()


# --- 移动 ---

## WASD 单格移动 (公开: 场景基类点击移动/敌人 AI 调用)
func move_in_direction(direction: Vector2) -> void:
	if is_moving:  # 防御: 移动中不接受新方向 (避免连续输入叠加对角/穿墙)
		return
	var cost := TurnManager.get_action_cost("move")
	if ap_current < cost:
		return
	# 规范化到 4 方向 (禁对角): Input.get_vector 对角输入 (0.707,0.707) 会斜穿墙/峭壁的角
	var dir := _dominant_axis(direction)
	if dir == Vector2.ZERO:
		return
	var target := global_position + dir * tile_size
	if not _is_cell_walkable(target):
		return
	_path_queue.clear()
	_begin_walk_step()
	_target_position = target
	is_moving = true


## 取输入方向的主轴 (水平/垂直, 禁对角): (0.707,0.707)→(1,0) 或 (0,1)
func _dominant_axis(dir: Vector2) -> Vector2:
	if absf(dir.x) >= absf(dir.y):
		return Vector2(signf(dir.x), 0)
	return Vector2(0, signf(dir.y))


## 点击移动: 生成到目标的逐格路径并开始连续移动
func move_to_cell(target_world: Vector2) -> void:
	if is_moving or not is_my_turn:
		return
	var cost := TurnManager.get_action_cost("move")
	if ap_current < cost:
		return
	var snapped := Vector2(
		floor(target_world.x / tile_size) * tile_size + tile_size * 0.5,
		floor(target_world.y / tile_size) * tile_size + tile_size * 0.5
	)
	if snapped.is_equal_approx(global_position):
		return

	var path := _build_path(global_position, snapped)
	if path.is_empty():
		return

	# 若目标格有单位, 去掉最后一步 (走到邻格触发接触)
	var last := path[path.size() - 1]
	if _cell_has_character(last):
		path.remove_at(path.size() - 1)
		if path.is_empty():
			return

	_path_queue = path
	_next_path_step()


## 单目标格子移动 (敌人巡逻/追击用, 不走路径队列)
func start_walk(target_world: Vector2) -> void:
	if is_moving:
		return
	var snapped := snap_to_grid(target_world)
	if snapped.is_equal_approx(global_position):
		return
	# 目标不可走 (墙/单位) → 放弃移动, 避免卡死
	if not _is_cell_walkable(snapped):
		return
	_begin_walk_step()
	_target_position = snapped
	is_moving = true


## 世界坐标对齐到格子中心
func snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		floor(pos.x / tile_size) * tile_size + tile_size * 0.5,
		floor(pos.y / tile_size) * tile_size + tile_size * 0.5
	)


## 视觉感知 (所有单位通用: 玩家/丧尸/NPC): 本单位到 target_pos 的直线路径
## 被墙/障碍 (is_cell_walkable=false) 遮挡则看不到。Bresenham 逐格遍历。
func has_line_of_sight(target_pos: Vector2) -> bool:
	if not world or not world.has_method("is_cell_walkable"):
		return true  # 无世界引用时退回"可看到" (距离检测由调用方负责)
	var start := Vector2i(roundi(global_position.x / tile_size), roundi(global_position.y / tile_size))
	var end := Vector2i(roundi(target_pos.x / tile_size), roundi(target_pos.y / tile_size))
	if start == end:
		return true
	var dx := absi(end.x - start.x)
	var dy := absi(end.y - start.y)
	var sx := 1 if start.x < end.x else -1
	var sy := 1 if start.y < end.y else -1
	var err := dx - dy
	var x := start.x
	var y := start.y
	while true:
		# 检查当前格是否被墙/障碍阻挡 (不含起点)
		if x != start.x or y != start.y:
			var cell_center := Vector2(x * tile_size + tile_size * 0.5, y * tile_size + tile_size * 0.5)
			if not world.is_cell_walkable(cell_center):
				return false
		if x == end.x and y == end.y:
			return true
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	return true


## 逐格寻路 (BFS 4 方向绕开墙/单位; 替换原贪心直走撞墙即停 — 原实现遇墙就 break, 不会绕行)
## 只做几何绕墙(世界 is_cell_walkable); 动态单位阻挡由逐格移动(_next_path_step)再判
func _build_path(from_pos: Vector2, to_pos: Vector2) -> Array[Vector2]:
	var path: Array[Vector2] = []
	# 用 floor (与 _cell_of 一致): 格中心坐标 = 格*tile + tile*0.5, 落在中心时
	# roundi(3.5)=4 会整体错一格 → 必须用 floor 取整到所在格
	var start := Vector2i(floori(from_pos.x / tile_size), floori(from_pos.y / tile_size))
	var goal := Vector2i(floori(to_pos.x / tile_size), floori(to_pos.y / tile_size))
	_debug_path = path.duplicate()
	queue_redraw()
	if start == goal:
		return path

	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# 字典键必须用字符串 ("x,y"): 用 Vector2i 当键在 Godot 4.7 下哈希不稳定 → BFS 行为随机
	var key_of := func(c: Vector2i) -> String: return "%d,%d" % [c.x, c.y]
	var queue: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var visited: Dictionary = {key_of.call(start): true}
	var head := 0
	var guard := 0
	var found := false
	while head < queue.size() and guard < 20000:
		guard += 1
		var cur: Vector2i = queue[head]
		head += 1
		if cur == goal:
			found = true
			break
		for d in dirs:
			var nb: Vector2i = cur + d
			var nk: String = key_of.call(nb)
			if visited.has(nk):
				continue
			var nb_center := Vector2(nb.x * tile_size + tile_size * 0.5, nb.y * tile_size + tile_size * 0.5)
			if not _walkable_geom(nb_center):
				continue
			visited[nk] = true
			came_from[nk] = cur
			queue.append(nb)
	if not found:
		return path

	# 回溯 goal -> ... -> start 前一格, 再反转
	var node: Vector2i = goal
	var rev: Array[Vector2] = []
	while node != start:
		rev.append(Vector2(node.x * tile_size + tile_size * 0.5, node.y * tile_size + tile_size * 0.5))
		node = came_from[key_of.call(node)]
	rev.reverse()
	path = rev
	# 调试: 保存路径供 _draw 画引导线 (用户反馈: 想看寻路经过的格子连线)
	_debug_path = path.duplicate()
	queue_redraw()
	return path


## 几何可走性 (只查墙/地形, 不含动态单位) — 寻路用, 避免被临时占位的单位挡死
func _walkable_geom(cell_center: Vector2) -> bool:
	if world and world.has_method("is_cell_walkable"):
		return world.is_cell_walkable(cell_center)
	return _is_cell_walkable(cell_center)


## 寻路调试: 当前路径格子中心 (世界坐标), _draw 画引导线
var _debug_path: Array[Vector2] = []


## 绘制寻路引导线 (用户反馈: 把寻路经过的格子中心连出来)
## 红色折线 + 每个格子中心黄点; 移动中实时显示, 到达/中断后清空
func _draw() -> void:
	if _debug_path.is_empty():
		return
	var pts := PackedVector2Array()
	for p in _debug_path:
		pts.append(to_local(p))
	if pts.size() >= 2:
		draw_polyline(pts, Color(1.0, 0.2, 0.2, 0.85), 2.0)
	for p in pts:
		draw_circle(p, 3.0, Color(1.0, 0.85, 0.2, 0.95))


func _next_path_step() -> void:
	if _path_queue.is_empty():
		return
	var cost := TurnManager.get_action_cost("move")
	if ap_current < cost:
		_path_queue.clear()
		return
	var next_cell := _path_queue[0]
	# 路径下一格不可走 (单位/墙) → 停在当前格
	if not _is_cell_walkable(next_cell):
		_path_queue.clear()
		_on_path_blocked()
		return
	_path_queue.remove_at(0)
	# 同步调试路径: 已走的格从引导线移除 (显示剩余路径)
	if not _debug_path.is_empty():
		_debug_path.remove_at(0)
		queue_redraw()
	_begin_walk_step()
	_target_position = next_cell
	is_moving = true


## 子类钩子: 路径被单位阻挡
func _on_path_blocked() -> void:
	pass


## 格子是否可走: 无单位阻挡 + 世界允许 (墙检测)
func _is_cell_walkable(cell_center: Vector2) -> bool:
	if _cell_has_character(cell_center):
		return false
	# 非玩家单位不可走建筑入口 (丧尸走入口会穿进建筑再穿出 → 视觉"绕过墙", 用户反馈)
	if not is_player_unit and world and world.has_method("is_building_entry") and world.is_building_entry(cell_center):
		return false
	if world and world.has_method("is_cell_walkable"):
		return world.is_cell_walkable(cell_center)
	return true


func _cell_has_character(cell_center: Vector2) -> bool:
	for unit: Node in TurnManager.get_all_units():
		if unit != self and is_instance_valid(unit):
			if unit.global_position.distance_to(cell_center) < tile_size * 0.5:
				return true
	return false


# --- 攻击 ---

func execute_attack(target: Node, action: Resource = null) -> void:
	if not is_instance_valid(target):
		return

	if action == null:
		action = get_default_attack()

	var cost := TurnManager.get_combat_action_cost(action)
	if ap_current < cost:
		push_warning("[", get_display_name(), "] AP 不足, 无法攻击")
		return

	var dist := int(global_position.distance_to(target.global_position) / tile_size)

	# 射程检查: 超出射程给出反馈, 不静默
	var range_max: int = int(action.get("range_max")) if action.get("range_max") != null else 1
	if dist > range_max:
		show_float_text("距离不够", Color(0.95, 0.85, 0.4), 16)
		push_warning("[", get_display_name(), "] 目标超出射程 (", dist, " > ", range_max, ")")
		return

	var att_stats := get_combat_stats()
	var def_stats: Dictionary = {}
	if target.has_method("get_combat_stats"):
		def_stats = target.get_combat_stats()
	else:
		def_stats = {
			"name": target.name,
			"defense": target.get("defense") if target.get("defense") != null else 0.0,
			"hp": target.get("hp") if target.get("hp") != null else 0.0,
		}

	var calc := CC.new()
	var result := calc.calculate_damage(att_stats, def_stats, action, dist)

	# 攻击音效: 攻击声 + 命中/未命中声 (音效缺失时静默)
	if SoundManager:
		var vol := -6.0 if is_player_unit else -11.0
		var sound: String = action.get("sound_id") if action.get("sound_id") != null else ""
		if sound != "":
			SoundManager.play(sound, vol)
		if result.get("damage", 0.0) > 0.0:
			var hit_s: String = action.get("hit_sound_id") if action.get("hit_sound_id") != null else "hit.wav"
			SoundManager.play(hit_s, vol + 2.0)
		else:
			var miss_s: String = action.get("miss_sound_id") if action.get("miss_sound_id") != null else "miss.wav"
			SoundManager.play(miss_s, vol + 3.0)

	# 命中才造成伤害 (MISS 的 damage 为 0, 不应触发 take_damage)
	if result.get("damage", 0.0) > 0.0:
		if target.has_method("take_damage"):
			target.take_damage(result.damage, bool(result.get("did_crit", false)))
	else:
		# 未命中: 目标头顶飘 MISS
		if target.has_method("show_float_text"):
			target.show_float_text("MISS", Color(0.75, 0.75, 0.78), 20)

	# AP 结算: 玩家走单动作回合制(player_acted), 敌人自行扣 AP(take_turn 收尾)
	if is_player_unit:
		TurnManager.player_acted(action.get("action_name"), cost)

	# 攻击后武器磨损 (耐久消耗, 攻击力随之下降)
	if equipped_slots.has(DataManager.EQUIP_SLOT_WEAPON):
		InventoryBackpack.damage_item(equipped_slots[DataManager.EQUIP_SLOT_WEAPON], 1)
	elif not is_player_unit:
		# 非玩家单位 (敌人) 没有走 TurnManager.player_acted, 在这里扣 AP
		ap_current = maxi(ap_current - cost, 0)
	action_completed.emit("attack", cost)
	combat_action_executed.emit(action, target, result)

	# 攻击出击动画: 朝目标冲出一小段再回位 (Tween 不阻塞回合逻辑)
	_play_attack_lunge(target)

	print("[", get_display_name(), "] ", result.log)


## 攻击出击动画: 朝目标方向冲出 tile*0.4 再回到原位 (近战有"扑上去打"的动感)
func _play_attack_lunge(target: Node) -> void:
	if not is_instance_valid(target) or is_moving:
		return
	var dir: Vector2 = (target.global_position - global_position).normalized()
	if dir == Vector2.ZERO:
		return
	var original: Vector2 = global_position
	var lunge_pos: Vector2 = global_position + dir * (tile_size * 0.4)
	var tween := create_tween()
	tween.tween_property(self, "global_position", lunge_pos, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", original, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func attack_nearest_enemy() -> bool:
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		return false

	var action := get_default_attack()
	var calc := CC.new()
	var valid := calc.get_valid_targets(global_position, enemies, action, tile_size)
	if valid.is_empty():
		return false

	var nearest: Node = valid[0]
	var min_dist: float = global_position.distance_squared_to(nearest.global_position)
	for e in valid:
		var d := global_position.distance_squared_to(e.global_position)
		if d < min_dist:
			min_dist = d
			nearest = e

	execute_attack(nearest, action)
	return true


func get_default_attack() -> Resource:
	if equipped_weapon and equipped_weapon.get("primary_action") != null:
		return equipped_weapon.primary_action
	return CA.create_melee_attack("punch", "拳击", 4, 0.6, CA.DamageType.BLUNT)


# --- 背包接口 (转发到全局背包) ---

func add_item(item_id: String, count: int = 1) -> bool:
	return InventoryBackpack.try_add_item(item_id, count).get("success", false)


func remove_item(item_id: String, count: int = 1) -> bool:
	return InventoryBackpack.remove_item(item_id, count) > 0


func count_item(item_id: String) -> int:
	return InventoryBackpack.count_item(item_id)


# --- 装备系统 (穿戴/卸下, 武器/防具/背包三类) ---

## 装备变更信号 (新手引导/UI 监听: item_id, slot)
signal equipment_changed(item_id: String, slot: String)

## 穿戴装备: 从背包移除 → 装入对应槽位; 同槽位旧装备自动放回背包
func equip_item(item_id: String) -> bool:
	var item: DataManager.ItemData = DataManager.get_item(item_id)
	if not item or item.equip_slot == "":
		push_warning("[", get_display_name(), "] 无法装备: ", item_id)
		return false
	var slot: String = item.equip_slot
	if not InventoryBackpack.remove_item(item_id, 1):
		return false
	# 同槽位已有装备 → 卸下放回 (强制放回, 避免超重时旧装备丢失)
	if equipped_slots.has(slot):
		InventoryBackpack.force_add_item(equipped_slots[slot], 1)
	equipped_slots[slot] = item_id
	# 武器 → 更新攻击动作
	if slot == DataManager.EQUIP_SLOT_WEAPON:
		equipped_weapon = _weapon_to_action(item_id)
	# 背包 → 更新负重上限
	elif slot == DataManager.EQUIP_SLOT_BACKPACK:
		_update_weight_bonus()
	equipment_changed.emit(item_id, slot)
	print("[", get_display_name(), "] 装备: ", item.name, " (", slot, ")")
	return true


## 卸下装备 (放回背包), 返回 item_id
func unequip_item(slot: String) -> String:
	if not equipped_slots.has(slot):
		return ""
	var item_id: String = equipped_slots[slot]
	equipped_slots.erase(slot)
	if slot == DataManager.EQUIP_SLOT_WEAPON:
		equipped_weapon = null
	elif slot == DataManager.EQUIP_SLOT_BACKPACK:
		_update_weight_bonus()
	InventoryBackpack.force_add_item(item_id, 1)  # 强制放回, 超重也允许 (装备不能丢)
	var item := DataManager.get_item(item_id)
	print("[", get_display_name(), "] 卸下: ", item.name if item else item_id)
	return item_id


func get_equipped_item(slot: String) -> String:
	return equipped_slots.get(slot, "")


## 武器 item_id → Weapon 资源 (动作)
func _weapon_to_action(item_id: String) -> Resource:
	var wd := load("res://scripts/items/weapon.gd")
	var all: Dictionary = wd.all_weapons()
	if all.has(item_id):
		return all[item_id]
	return null


## 重算背包类装备的负重加成
func _update_weight_bonus() -> void:
	var bonus: float = 0.0
	if equipped_slots.has(DataManager.EQUIP_SLOT_BACKPACK):
		var item := DataManager.get_item(equipped_slots[DataManager.EQUIP_SLOT_BACKPACK])
		if item:
			bonus = float(item.properties.get("weight_bonus", 0))
	if InventoryBackpack:
		InventoryBackpack.set_extra_weight_bonus(bonus)


func use_item_on_self(item_id: String) -> void:
	var cost := TurnManager.get_action_cost("use_item")
	if ap_current < cost:
		return

	var item_data: DataManager.ItemData = DataManager.get_item(item_id)
	if not item_data:
		return

	if not InventoryBackpack.remove_item(item_id, 1):
		return

	var heal_amount: float = item_data.properties.get("heal", 0.0)
	if heal_amount > 0:
		hp = minf(hp + heal_amount, max_hp)
		hp_changed.emit(hp, max_hp)
		print("[", get_display_name(), "] 使用 ", item_id, " 回复 ", heal_amount, " HP")

	if is_player_unit:
		TurnManager.player_acted("use_item", cost)
	else:
		ap_current = maxi(ap_current - cost, 0)
	action_completed.emit("use_item", cost)


# --- 伤害 / 死亡 ---

## 受到伤害: 入参 amount 为【最终伤害】(已含护甲结算)。
## 护甲减伤唯一出口是 CombatCalculator.apply_defense (P0-2 统一, 修复双重减伤)。
## - 常规攻击/异能: 调用方传 result.damage (calculate_damage 已算护甲)
## - 真实伤害(自伤/DOT): 调用方传原值, 不走护甲
func take_damage(amount: float, is_crit: bool = false) -> void:
	if amount <= 0.0:
		return
	var actual := maxf(amount, CC.MIN_DAMAGE)
	hp = maxf(hp - actual, 0.0)
	# 被击中 → 护甲磨损 (护甲防御随之衰减)
	if equipped_slots.has(DataManager.EQUIP_SLOT_ARMOR):
		InventoryBackpack.damage_item(equipped_slots[DataManager.EQUIP_SLOT_ARMOR], 1)
	hp_changed.emit(hp, max_hp)
	_update_health_bar()
	# 头顶飘字: 暴击金色大号, 普通红色
	# (字号是世界单位, 会被相机 zoom 放大; zoom=6 下 22→约132px 太大, 统一缩小)
	if is_crit:
		show_float_text("-%.0f!" % actual, Color(1.0, 0.8, 0.1), 28)
	else:
		show_float_text("-%.0f" % actual, Color(1.0, 0.3, 0.3), 22)
	print("[", get_display_name(), "] 受到 ", actual, " 伤害, HP: ", hp, "/", max_hp)
	if hp <= 0:
		die()


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)
	hp_changed.emit(hp, max_hp)
	_update_health_bar()
	show_float_text("+%.0f" % amount, Color(0.3, 0.9, 0.4), 20)


func _update_health_bar() -> void:
	if _health_bar:
		_health_bar.update_health(hp, max_hp)


## 死亡入口 (统一流程, P1-4): 基类负责公共处理 (注销), 差异化交给 _on_died 钩子。
## 子类不要覆写 die(), 而是覆写 _on_died() 做专属行为 (生成尸体/触发游戏结束)。
func die() -> void:
	print("[", get_display_name(), "] 死亡!")
	TurnManager.unregister_unit(self)
	_on_died()


## 死亡差异化钩子: 子类覆写 (EnemyBase=生成尸体, Player=触发 game_over)
func _on_died() -> void:
	pass


# --- 属性导出 ---

func get_combat_stats() -> Dictionary:
	var weapon_id: String = equipped_slots.get(DataManager.EQUIP_SLOT_WEAPON, "")
	# 攻击力 × 武器耐久比 (磨损的武器攻击下降)
	var atk: float = attack_power * InventoryBackpack.get_durability_ratio(weapon_id)
	return {
		"name": get_display_name(),
		"attack": atk,
		"defense": get_total_defense(),
		"hp": hp,
		"max_hp": max_hp,
		"ap": ap_current,
		"ap_max": ap_max,
		"accuracy_bonus": 0.0,
		"crit_bonus": 0.0,
		"armor_pierce": 0.0,
	}


## 总防御 = 基础防御 + 防具装备加成 × 耐久比 (磨损的护甲防御下降)
func get_total_defense() -> float:
	var total: float = defense
	for slot in equipped_slots:
		if slot == DataManager.EQUIP_SLOT_ARMOR:
			var item := DataManager.get_item(equipped_slots[slot])
			if item:
				var ratio := InventoryBackpack.get_durability_ratio(equipped_slots[slot])
				total += float(item.properties.get("defense", 0)) * ratio
	return total


## 饰品加成: 视野半径 (+格, 探索迷雾用)
func get_vision_bonus() -> int:
	var total := 0
	for slot in equipped_slots:
		if slot == DataManager.EQUIP_SLOT_TRINKET:
			var item := DataManager.get_item(equipped_slots[slot])
			if item:
				total += int(item.properties.get("vision_bonus", 0))
	return total


## 饰品加成: 攻击射程 (+格, 战斗命中范围用)
func get_range_bonus() -> int:
	var total := 0
	for slot in equipped_slots:
		if slot == DataManager.EQUIP_SLOT_TRINKET:
			var item := DataManager.get_item(equipped_slots[slot])
			if item:
				total += int(item.properties.get("range_bonus", 0))
	return total


## 饰品加成: 命中率 (+%, 状态页显示用)
func get_accuracy_bonus() -> float:
	var total := 0.0
	for slot in equipped_slots:
		if slot == DataManager.EQUIP_SLOT_TRINKET:
			var item := DataManager.get_item(equipped_slots[slot])
			if item:
				total += float(item.properties.get("accuracy_bonus", 0))
	return total


## 饰品加成: 暴击率 (+%, 状态页显示用)
func get_crit_bonus() -> float:
	var total := 0.0
	for slot in equipped_slots:
		if slot == DataManager.EQUIP_SLOT_TRINKET:
			var item := DataManager.get_item(equipped_slots[slot])
			if item:
				total += float(item.properties.get("crit_bonus", 0))
	return total


## 饰品加成: 幸运值 (+点, 状态页显示用)
func get_luck_bonus() -> int:
	var total := 0
	for slot in equipped_slots:
		if slot == DataManager.EQUIP_SLOT_TRINKET:
			var item := DataManager.get_item(equipped_slots[slot])
			if item:
				total += int(item.properties.get("luck_bonus", 0))
	return total


func get_ap_cost_modifier(base_cost: int) -> int:
	return base_cost
