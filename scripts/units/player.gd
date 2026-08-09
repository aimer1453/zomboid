extends "res://scripts/units/character.gd"

# ============================================================
# PlayerUnit — 主角 (继承 Character)
# ============================================================
# 玩家特有:
#   - 探索模式连续移动 (路径队列) + 遇敌触发战斗
#   - 异能 (execute_ability)
#   - 装备武器 (equip_weapon)
#   - 污染值 (WorldTime)
# CA/CC 常量继承自 Character 基类

const WD := preload("res://scripts/items/weapon.gd")

## 修正属性 (装备/异能提供)
var accuracy_bonus: float = 0.0
var crit_bonus: float = 0.0
var armor_pierce: float = 0.0

## 生存属性 (0~100, 100 = 最健康; 随世界时间衰减, 消耗品恢复)
var hunger: float = 100.0   # 饱腹度
var thirst: float = 100.0   # 水分
## 体力 (通过锻炼增加, 每点 +0.5kg 负重上限)
var stamina: float = 20.0
## 幸运值 (饰品可加成, 影响暴击/掉落/事件)
var luck: float = 5.0

## 精力 (Energy): AP + 睡眠合并 — 战斗挥拳/技能消耗; 睡觉/休息/肾上腺素恢复
## 注意: 旧 sleep 字段移除, 精力不再随时间自然衰减 (避免"自然下降"矛盾)
## 饱腹/口渴<阈值时精力恢复速度减慢 (联动)

## 每小时生存衰减 (随 WorldTime.advance_time 推进)
const SURVIVAL_HUNGER_PER_HOUR := 1.5
const SURVIVAL_THIRST_PER_HOUR := 2.5

## 饱腹/口渴阈值: 低于此值精力恢复变慢 (联动; 旧 SLEEP_EXHAUSTED_THRESHOLD 替换)
const ENERGY_HUNGER_THRESHOLD := 30.0

signal survival_updated(hunger: float, thirst: float)


func _ready() -> void:
	is_player_unit = true
	# 默认主角: 前特种兵 (直接跑测试场景时 current_character 可能未设置)
	if GameManager and int(GameManager.current_character) == 0:
		GameManager.current_character = 1
	# 玩家初始数值强化 (平衡调整: HP/攻击/防御, 打丧尸不那么吃力)
	max_hp = 200.0
	hp = max_hp
	attack_power = 22.0
	defense = 5.0
	super._ready()
	# 新手引导模式: 空手开局 (从衣柜拿棒球棍再装备); 非引导模式: 默认手枪
	if GameManager and not GameManager.is_tutorial_mode():
		equip_weapon(WD.create_pistol())
		add_item("crystal_shard", 3)
		add_item("bread", 2)
		add_item("water_pure", 2)
		add_item("adrenaline", 1)        # 肾上腺素应急
		add_item("energy_drink", 2)      # 能量饮料
	TurnManager.round_started.connect(_on_round_started)
	if WorldTime:
		# 生存属性跟随世界时间衰减 (不是按回合)
		WorldTime.time_advanced.connect(_on_world_time_advanced)
		WorldTime.register_character_pollution(GameManager.current_character, 0.0)
	print("[Player] 就绪: HP=", hp, " AP=", ap_current, "/", ap_max, " 技能点=", skill_points, " 体力=", stamina)
	# 初始负重上限 = 基础 + 体力加成 (每点体力 +0.5kg)
	if InventoryBackpack:
		InventoryBackpack.max_weight = get_carry_capacity()


# --- 负重上限公式: 基础 10kg + 体力加成 (每点体力 +0.5kg) + 装备背包加成 (InventoryBackpack.extra_weight_bonus) ---
const BASE_CARRY := 10.0
const STAMINA_PER_KG := 0.5


## 当前负重上限 (含体力, 不含背包装备加成 — 由 InventoryBackpack.extra_weight_bonus 叠加)
func get_carry_capacity() -> float:
	return BASE_CARRY + stamina * STAMINA_PER_KG


## 锻炼: 增加体力 (+stamina_amount), 消耗游戏内时间 (默认 2 小时), 同步刷新负重
func train(stamina_amount: float = 1.0, hours: float = 2.0) -> bool:
	if not WorldTime or stamina_amount <= 0.0:
		return false
	stamina += stamina_amount
	if InventoryBackpack:
		InventoryBackpack.max_weight = get_carry_capacity()
	WorldTime.advance_time(hours)
	# 飘字反馈: 像掉血一样告诉玩家体力增加
	if is_player_unit and is_inside_tree():
		show_float_text("+%.0f 体力" % stamina_amount, Color(0.4, 0.9, 0.45), 22)
	print("[Player] 锻炼 +", stamina_amount, " 体力, 耗时 ", hours, " 小时 (当前负重上限 ", get_carry_capacity(), "kg)")
	return true


# --- 生存属性 (饥饿/口渴/睡眠) ---

## 世界时间推进 → 饱腹/口渴衰减 (精力不再随时间自然衰减, 由消耗品/睡眠/肾上腺素管理)
func _on_world_time_advanced(_day: int, _hour: float, elapsed_hours: float) -> void:
	if not is_player_unit:
		return
	_set_survival(
		maxf(hunger - SURVIVAL_HUNGER_PER_HOUR * elapsed_hours, 0.0),
		maxf(thirst - SURVIVAL_THIRST_PER_HOUR * elapsed_hours, 0.0))


func _set_survival(h: float, t: float) -> void:
	hunger = clampf(h, 0.0, 100.0)
	thirst = clampf(t, 0.0, 100.0)
	survival_updated.emit(hunger, thirst)


## HUD 初始同步用 (sleep 字段已移除)
func get_survival() -> Dictionary:
	return {"hunger": hunger, "thirst": thirst}


## 休息(睡觉): 消耗游戏内时间, 恢复精力 + HP (精力是核心资源, 由休息/肾上腺素管理)
## 精力恢复量由床等级决定 (home_furniture 传入), 默认基础值
func take_rest(hours: float = WorldTime.SLEEP_TIME_HOURS, energy_restore: float = 60.0) -> bool:
	if not WorldTime or hours <= 0.0:
		return false
	# 睡醒恢复: 回 30% 生命 + 精力 (高等级床恢复更多; 饱腹/口渴<阈值时恢复减半)
	var heal_amount: float = max_hp * 0.3
	hp = minf(hp + heal_amount, max_hp)
	hp_changed.emit(hp, max_hp)
	var restore: float = energy_restore
	if hunger < ENERGY_HUNGER_THRESHOLD or thirst < ENERGY_HUNGER_THRESHOLD:
		restore *= 0.5  # 饥饿/口渴时精力恢复减半
	ap_current = minf(ap_current + restore, float(ap_max))
	ap_changed.emit(ap_current, ap_max)
	# 飘字反馈: 像掉血一样告诉玩家精力/生命回复
	if is_player_unit and is_inside_tree():
		show_float_text("+%.0f 精力" % restore, Color(0.35, 0.8, 1.0), 22)
		if heal_amount > 0.0:
			show_float_text("+%.0f 生命" % heal_amount, Color(0.4, 0.9, 0.45), 20, -tile_size * 0.5)
	print("[Player] 休息 ", hours, " 小时, 精力 +", restore, ", HP +", heal_amount)
	# 推进世界时间 (饱腹/口渴随之衰减)
	WorldTime.advance_time(hours)
	return true


## 坐下: 短暂休息, 恢复少量精力, 消耗少量游戏内时间 (主角地板菜单"坐下")
## 与睡觉(take_rest)区别: 坐下是轻量小憩, 不回血, 只回一点精力, 时间很短
func sit(minutes: float = 30.0) -> bool:
	if not WorldTime or minutes <= 0.0:
		return false
	var restore: float = 8.0
	if hunger < ENERGY_HUNGER_THRESHOLD or thirst < ENERGY_HUNGER_THRESHOLD:
		restore *= 0.5  # 饥饿/口渴时精力恢复减半
	ap_current = minf(ap_current + restore, float(ap_max))
	ap_changed.emit(ap_current, ap_max)
	WorldTime.advance_time(minutes / 60.0)
	# 飘字反馈: 像掉血一样告诉玩家精力回复
	if is_player_unit and is_inside_tree():
		show_float_text("+%.0f 精力" % restore, Color(0.35, 0.8, 1.0), 22)
	print("[Player] 坐下休息 ", minutes, " 分钟, 精力 +", restore)
	return true


## 制作物品 (Phase 6 家园系统用): 消耗游戏内时间
## 具体配方由 DataManager._building_recipes 提供, 这里预留时间消耗契约
func craft_item(_recipe_id: String) -> bool:
	if not WorldTime:
		return false
	print("[Player] 制作物品, 消耗 ", WorldTime.CRAFT_TIME_HOURS, " 小时")
	WorldTime.advance_time(WorldTime.CRAFT_TIME_HOURS)
	return true


## 食用/饮用消耗品: 返回消耗结果
## 支持的属性: food(饱腹) / water(水分) / heal(生命) / energy_restore(精力, 肾上腺素类) / reduce_pollution(污染)
func consume_item(item_id: String) -> Dictionary:
	var item := DataManager.get_item(item_id)
	if not item:
		return {"success": false, "reason": "unknown"}
	if not InventoryBackpack.remove_item(item_id, 1):
		return {"success": false, "reason": "not_have"}

	var props: Dictionary = item.properties
	var messages: Array[String] = []

	var food_val := float(props.get("food", 0.0))
	if food_val > 0.0:
		hunger = clampf(hunger + food_val, 0.0, 100.0)
		messages.append("饱腹 +%.0f" % food_val)
		show_float_text("+%.0f" % food_val, Color(0.95, 0.8, 0.4), 18)

	var water_val := float(props.get("water", 0.0))
	if water_val > 0.0:
		thirst = clampf(thirst + water_val, 0.0, 100.0)
		messages.append("水分 +%.0f" % water_val)
		show_float_text("+%.0f" % water_val, Color(0.4, 0.7, 0.95), 18)

	var heal_val := float(props.get("heal", 0.0))
	if heal_val > 0.0:
		heal(heal_val)
		messages.append("生命 +%.0f" % heal_val)

	# 精力恢复 (肾上腺素/能量饮料类)
	var energy_val := float(props.get("energy_restore", 0.0))
	if energy_val > 0.0:
		ap_current = minf(ap_current + energy_val, float(ap_max))
		ap_changed.emit(ap_current, ap_max)
		messages.append("精力 +%.0f" % energy_val)
		show_float_text("+%.0f 精力" % energy_val, Color(0.85, 0.5, 1.0), 18)

	var pollute_val := float(props.get("reduce_pollution", 0.0))
	if pollute_val > 0.0 and WorldTime:
		WorldTime.reduce_pollution(GameManager.current_character, pollute_val)
		messages.append("污染 -%.0f" % pollute_val)

	survival_updated.emit(hunger, thirst)
	if messages.is_empty():
		return {"success": true, "messages": ["没有效果"]}
	print("[Player] 食用 ", item.name, ": ", ", ".join(messages))
	return {"success": true, "messages": messages}


func get_display_name() -> String:
	return "主角"


# --- 移动完成钩子 (玩家) ---

func _on_arrived() -> void:
	var cost := TurnManager.get_action_cost("move")
	if cost <= 0:
		return

	if TurnManager.combat_mode:
		# 战斗模式: 单动作回合制, 走一格即结束回合 (回合推进已消耗 ROUND_TIME)
		TurnManager.player_acted("move", cost)
	else:
		# 探索模式: 扣 AP + 触发丧尸异步巡逻 (每2步1次)
		TurnManager.spend_player_ap_only(cost)
		# 走路消耗世界时间 → 生存属性随世界时间衰减 (行走驱动时间, 主角不动世界静止)
		if WorldTime:
			WorldTime.advance_time(WorldTime.WALK_TIME_HOURS)

	action_completed.emit("move", cost)

	# 遇敌检测 (探索模式)
	if not TurnManager.combat_mode:
		if _check_enemy_alert():
			_path_queue.clear()
			_trigger_combat_on_contact()
			return
		# 探索模式 AP 用尽自动回满, 继续连续移动
		if ap_current <= 0:
			ap_current = ap_max
			ap_changed.emit(ap_current, ap_max)
		# 继续走路径下一格
		if not _path_queue.is_empty():
			_next_path_step()
			return
		movement_stopped.emit()
		return

	# 战斗模式: 回合已由 player_acted 推进
	if ap_current <= 0:
		_end_turn()


func _on_path_blocked() -> void:
	if not TurnManager.combat_mode:
		movement_stopped.emit()


# --- 遇敌触发战斗 ---

## 是否进入任一丧尸的警戒范围 (dist <= detection_range) → 触发战斗
func _check_enemy_alert() -> bool:
	for enemy in TurnManager.get_enemy_units():
		if is_instance_valid(enemy):
			var d := int(global_position.distance_to(enemy.global_position) / tile_size)
			var alert_range: int = int(enemy.get("detection_range") if enemy.get("detection_range") != null else 5)
			if d <= alert_range:
				return true
	return false


func _trigger_combat_on_contact() -> void:
	print("[Player] 遭遇丧尸! 进入战斗")
	is_my_turn = true
	TurnManager.enter_combat()


# --- 异能 (Phase 5: 技能点 / 晶石吸收 / 异能树) ---

## 技能点 (晶石吸收获得, 学习异能消耗)
var skill_points: int = 3
## 吸收功率 (基础 1.0, 装备/称号可提升)
var absorption_power: float = 1.0
## 已学被动异能 id
var learned_passives: Array[String] = []

## 增益状态 (buff_type: attack)
var _attack_buff: float = 0.0
var _buff_rounds_left: int = 0


## 每轮递减 buff
func _on_round_started(_round: int) -> void:
	if _buff_rounds_left > 0:
		_buff_rounds_left -= 1
		if _buff_rounds_left <= 0:
			_attack_buff = 0.0


## 学习异能: 校验角色/技能点/前置/未学
func learn_ability(ability_id: String) -> bool:
	var data := DataManager.get_ability(ability_id)
	if data.is_empty():
		push_warning("[Player] 异能不存在: ", ability_id)
		return false
	if int(data.get("character", 0)) != int(GameManager.current_character):
		return false
	var cost := int(data.get("cost", 1))
	if skill_points < cost:
		print("[Player] 技能点不足 (", skill_points, "/", cost, ")")
		return false
	if _is_ability_learned(ability_id):
		return false
	if not DataManager.ability_unlockable(ability_id, get_learned_ids()):
		print("[Player] 前置异能未学习: ", ability_id)
		return false

	skill_points -= cost
	var action := DataManager.get_ability_action(ability_id)
	if action:
		learned_abilities.append(action)
	else:
		learned_passives.append(ability_id)
	print("[Player] 学会异能: ", data.get("name"), " (剩余技能点 ", skill_points, ")")
	return true


func _is_ability_learned(ability_id: String) -> bool:
	if learned_passives.has(ability_id):
		return true
	for a in learned_abilities:
		if a is Resource and a.get("action_id") == ability_id:
			return true
	return false


## 公开: 是否已学会某异能
func has_ability(ability_id: String) -> bool:
	return _is_ability_learned(ability_id)


## 已学异能 id 列表 (公开: 异能树 UI 前置校验用)
func get_learned_ids() -> Array:
	var ids: Array = []
	ids.append_array(learned_passives)
	for a in learned_abilities:
		if a is Resource:
			ids.append(a.get("action_id"))
	return ids


## 吸收背包中的能量晶石 → 技能点 (点数 = 晶石值 × 吸收功率)
func absorb_crystal() -> int:
	var gained := 0
	for crystal_id in ["crystal_shard", "crystal_smooth", "crystal_cluster", "crystal_huge"]:
		var count := InventoryBackpack.count_item(crystal_id)
		if count <= 0:
			continue
		var item := DataManager.get_item(crystal_id)
		var base: int = int(item.properties.get("crystal_value", 10)) if item else 10
		var per: int = int(base * absorption_power)
		InventoryBackpack.remove_item(crystal_id, count)
		skill_points += per * count
		gained += per * count
	if gained > 0:
		print("[Player] 吸收晶石 +", gained, " 技能点 (功率 ", int(absorption_power * 100), "%), 当前 ", skill_points)
	else:
		print("[Player] 背包中没有能量晶石")
	return gained


## 施放异能 (伤害型 / 治疗型 / 增益型)
func execute_ability(ability: Resource, target: Node) -> bool:
	if ability.get("action_type") != CA.ActionType.ABILITY:
		return false

	var cost := TurnManager.get_combat_action_cost(ability)
	if ap_current < cost:
		return false

	# 治疗型 (对自己)
	var effects: Dictionary = ability.get("effects") if ability.get("effects") is Dictionary else {}
	var heal_val := _eff_f(effects, "heal")
	if heal_val > 0.0:
		var amount: float = heal_val * max_hp if _eff_b(effects, "heal_percent") else heal_val
		heal(amount)
	# 增益型 (对自己)
	var buff_type := _eff_s(effects, "buff_type")
	if buff_type != "":
		_apply_buff(buff_type, _eff_f(effects, "buff_value"), _eff_i(effects, "buff_rounds", 1))
	# 自伤 (狂化代价)
	var self_damage := _eff_f(effects, "self_damage")
	if self_damage > 0.0:
		take_damage(max_hp * self_damage)

	# 伤害型 (对目标)
	if target and is_instance_valid(target) and float(ability.get("damage_multiplier")) > 0.0:
		var dist := int(global_position.distance_to(target.global_position) / tile_size)
		var att_stats := get_combat_stats()
		var def_stats: Dictionary = target.get_combat_stats() if target.has_method("get_combat_stats") else {}
		var calc := CC.new()
		var result := calc.calculate_damage(att_stats, def_stats, ability, dist)
		if result.get("damage", 0.0) > 0.0 and target.has_method("take_damage"):
			target.take_damage(result.damage, bool(result.get("did_crit", false)))
		combat_action_executed.emit(ability, target, result)

	TurnManager.player_acted(ability.get("action_name"), cost)
	return true


# --- 效果字典读取 (effects) ---

func _eff_f(effects: Dictionary, key: String) -> float:
	return float(effects.get(key, 0.0))

func _eff_s(effects: Dictionary, key: String) -> String:
	return str(effects.get(key, ""))

func _eff_i(effects: Dictionary, key: String, default: int = 0) -> int:
	return int(effects.get(key, default))

func _eff_b(effects: Dictionary, key: String) -> bool:
	return bool(effects.get(key, false))


func _apply_buff(buff_type: String, value: float, rounds: int) -> void:
	match buff_type:
		"attack":
			_attack_buff = value
			_buff_rounds_left = rounds
			show_float_text("攻击力 +%d%%" % int(value * 100), Color(1.0, 0.8, 0.2), 20)
	print("[Player] 增益: ", buff_type, " +", value, " 持续 ", rounds, " 轮")


# --- 装备武器 ---

## 资源式装备 (开局手枪/武器工厂): 同步写 equipped_slots, 让 HUD 装备栏正确显示
func equip_weapon(weapon: Resource) -> void:
	equipped_weapon = weapon
	if weapon and weapon.get("weapon_id") != null and weapon.weapon_id != "":
		equipped_slots[DataManager.EQUIP_SLOT_WEAPON] = weapon.weapon_id
	print("[Player] 装备: ", weapon.get("weapon_name"))

func unequip_weapon() -> void:
	equipped_weapon = null
	if equipped_slots.has(DataManager.EQUIP_SLOT_WEAPON):
		equipped_slots.erase(DataManager.EQUIP_SLOT_WEAPON)


# --- 死亡 (玩家) ---

## 死亡差异化钩子: 玩家不 queue_free (由 GameManager.game_over 处理后续)
func _on_died() -> void:
	print("[Player] 主角死亡!")
	if GameManager:
		GameManager.game_over()


# --- 属性查询 (覆盖) ---

func get_combat_stats() -> Dictionary:
	return {
		"name": get_display_name(),
		"attack": attack_power * (1.0 + _attack_buff),
		"defense": get_total_defense(),
		"hp": hp,
		"max_hp": max_hp,
		"ap": ap_current,
		"ap_max": ap_max,
		"accuracy_bonus": accuracy_bonus,
		"crit_bonus": crit_bonus,
		"armor_pierce": armor_pierce,
	}


## 总防御 = 基础 + 防具 + 被动异能 (钢铁皮肤 +20%)
func get_total_defense() -> float:
	var total := super.get_total_defense()
	if learned_passives.has("sf_iron_skin"):
		total *= 1.2
	return total


func get_stats() -> Dictionary:
	var penalty := 0.0
	if WorldTime:
		penalty = WorldTime.get_pollution_stat_penalty(GameManager.current_character)
	# 精力(AP) 不足时按比例扣属性 (逼迫节约消耗, 肾上腺素应急)
	penalty += get_energy_penalty()
	var effective_atk := attack_power * (1.0 + penalty)
	# 防御 = 基础 + 装备护甲 (get_total_defense), 再乘状态惩罚
	var effective_def := get_total_defense() * (1.0 + penalty)
	return {
		"hp": hp, "max_hp": max_hp,
		"attack": effective_atk, "defense": effective_def,
		"ap": ap_current, "ap_max": ap_max,
		"pollution": WorldTime.get_pollution(GameManager.current_character) if WorldTime else 0.0,
		"stamina": stamina,
		"luck": luck,
	}


## 精力不足惩罚: 精力 < ap_max*30% 时按比例扣属性 (-10% ~ -30%)
## (取代旧 get_sleep_penalty — 精力度量 AP 比例而非绝对值, 避免 ap_max 提升后仍 0 扣)
func get_energy_penalty() -> float:
	var threshold: float = float(ap_max) * 0.3
	if ap_current >= threshold or ap_max <= 0:
		return 0.0
	var lack: float = (threshold - float(ap_current)) / threshold
	return -0.30 * lack  # 精力=0 时 -30%


func get_ap_cost_modifier(base_cost: int) -> int:
	# 可由武器/装备/异能提供 AP 减免
	return base_cost


# --- 序列化 (P0 存档: 生存属性/技能点/异能/装备/位置 全量保存) ---

func serialize() -> Dictionary:
	# learned_abilities 存的是 action_id (可反查 DataManager), 不存 Resource 对象
	var ability_ids: Array[String] = []
	for a in learned_abilities:
		if a is Resource and a.get("action_id") != null:
			ability_ids.append(a.get("action_id"))
	return {
		"hp": hp,
		"max_hp": max_hp,
		"ap_current": ap_current,
		"ap_max": ap_max,
		"attack_power": attack_power,
		"defense": defense,
		"hunger": hunger,
		"thirst": thirst,
		# 注意: sleep 字段已移除 (AP+睡眠合并为精力), 老存档该字段忽略
		"skill_points": skill_points,
		"absorption_power": absorption_power,
		"learned_abilities": ability_ids,
		"learned_passives": learned_passives,
		"equipped_slots": equipped_slots,
		"position": {"x": global_position.x, "y": global_position.y},
	}


## 读档恢复 Player 状态 (场景加载后由 GameManager 调用)
func deserialize(data: Dictionary) -> void:
	hp = float(data.get("hp", max_hp))
	max_hp = float(data.get("max_hp", max_hp))
	ap_current = int(data.get("ap_current", ap_max))
	ap_max = int(data.get("ap_max", ap_max))
	attack_power = float(data.get("attack_power", attack_power))
	defense = float(data.get("defense", defense))
	hunger = float(data.get("hunger", 100.0))
	thirst = float(data.get("thirst", 100.0))
	# sleep 字段已移除 (老存档忽略)
	stamina = float(data.get("stamina", 20.0))
	luck = float(data.get("luck", 5.0))
	# 读档后负重上限按体力重新计算
	if InventoryBackpack:
		InventoryBackpack.max_weight = get_carry_capacity()
	skill_points = int(data.get("skill_points", 3))
	absorption_power = float(data.get("absorption_power", 1.0))
	learned_passives = data.get("learned_passives", [])

	# 异能: 按 action_id 从数据库重建 Resource (被动保持 id 列表)
	learned_abilities.clear()
	for aid in data.get("learned_abilities", []):
		var action: Resource = DataManager.get_ability_action(aid)
		if action:
			learned_abilities.append(action)

	# 装备: 恢复三槽 (触发装备加成)
	equipped_slots.clear()
	var slots: Dictionary = data.get("equipped_slots", {})
	for slot in slots:
		var item_id: String = str(slots[slot])
		if item_id != "" and DataManager.get_item(item_id):
			equipped_slots[slot] = item_id
	if equipped_slots.has(DataManager.EQUIP_SLOT_WEAPON):
		equipped_weapon = _weapon_to_action(equipped_slots[DataManager.EQUIP_SLOT_WEAPON])
	_update_weight_bonus()

	# 位置
	var pos: Dictionary = data.get("position", {})
	if pos.has("x") and pos.has("y"):
		global_position = Vector2(float(pos.x), float(pos.y))

	hp_changed.emit(hp, max_hp)
	ap_changed.emit(ap_current, ap_max)
	survival_updated.emit(hunger, thirst)
	print("[Player] 读档恢复: HP=", hp, " 技能点=", skill_points, " 异能=", learned_abilities.size(), "+", learned_passives.size())
