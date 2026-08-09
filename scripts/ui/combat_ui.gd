class_name CombatUI
extends Control

const CSM := preload("res://scripts/combat/combat_state_machine.gd")
const CA := preload("res://scripts/combat/combat_actions.gd")

## 战斗状态机引用
var combat_sm: Node = null

## UI 节点
var _ap_bar: ProgressBar
var _ap_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _round_label: Label
var _action_container: HBoxContainer
var _target_indicator: ColorRect
var _end_turn_btn: Label
var _phase_label: Label
var _alert_banner: PanelContainer
var _alert_banner_label: Label

## 警报横幅动画: 从右滑入 → 停留 → 向左滑出 (横条方块)
const BANNER_HOLD_TIME: float = 2.2
const BANNER_SIZE := Vector2(600, 64)

## 动作按钮 (已废弃: 点击情境交互替代)
var _action_buttons: Array[Button] = []

## 面板是否可见
var is_visible: bool = true
## 当前监听 AP 的玩家单位引用 (战斗结束时断开信号)
var _player_unit: Node = null

signal action_clicked(action: Resource)
signal end_turn_clicked()
signal target_clicked(target: Node)


func _ready() -> void:
	_build_ui()
	_connect_signals()


## 显示警报横幅: 从右侧滑入, 停在屏幕正中央(垂直偏上), 停留后滑出 (带警报音效)
func show_alert_banner(msg: String) -> void:
	if _alert_banner == null:
		return
	_alert_banner_label.text = msg
	var vw: float = get_viewport_rect().size.x
	var vh: float = get_viewport_rect().size.y
	var bw: float = _alert_banner.size.x if _alert_banner.size.x > 0 else BANNER_SIZE.x
	var center_y: float = vh * 0.4  # 垂直偏上一点 (用户反馈: 被发现提示要在屏幕正中间)
	# 起点: 屏幕右侧外
	_alert_banner.position = Vector2(vw + 24, center_y)
	_alert_banner.visible = true
	var target_x: float = (vw - bw) * 0.5
	var tween := create_tween()
	tween.tween_property(_alert_banner, "position", Vector2(target_x, center_y), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(BANNER_HOLD_TIME)
	tween.tween_property(_alert_banner, "position:x", -bw - 24, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _alert_banner.visible = false)
	if SoundManager:
		SoundManager.play("alert.mp3", -6.0)


func set_combat_state_machine(sm: Node) -> void:
	combat_sm = sm
	if combat_sm:
		combat_sm.phase_changed.connect(_on_phase_changed)
		combat_sm.player_actions_ready.connect(_on_actions_ready)
		combat_sm.target_selected.connect(_on_target_selected)
		combat_sm.target_deselected.connect(_on_target_deselected)

	var player := TurnManager.get_player()
	if player:
		if player.has_signal("hp_changed") and not player.hp_changed.is_connected(_update_hp):
			player.hp_changed.connect(_update_hp)
		if player.has_signal("ap_changed") and not player.ap_changed.is_connected(_update_ap):
			player.ap_changed.connect(_update_ap)


func _build_ui() -> void:
	# 底部面板 (回合/AP/阶段/结束提示) 已按用户要求删除.
	# 仅保留: 警报横幅 (show_alert_banner) + _input 物理选靶.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 警报横幅 (独立定位, 从右往左滑动)
	_build_alert_banner()


## 警报横幅方块 (深红底 + 亮红边框 + 大字, 从右往左滑入滑出)
func _build_alert_banner() -> void:
	_alert_banner = PanelContainer.new()
	_alert_banner.name = "AlertBanner"
	_alert_banner.visible = false
	_alert_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不挡地图点击
	_alert_banner.custom_minimum_size = BANNER_SIZE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.45, 0.08, 0.06, 0.95)
	style.border_color = Color(1.0, 0.35, 0.2)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_alert_banner.add_theme_stylebox_override("panel", style)

	_alert_banner_label = Label.new()
	_alert_banner_label.text = "⚠ 惊动了丧尸！"
	_alert_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_alert_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_alert_banner_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_alert_banner_label.add_theme_font_size_override("font_size", 26)
	_alert_banner_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	_alert_banner_label.add_theme_color_override("font_outline_color", Color(0.2, 0.02, 0.0))
	_alert_banner_label.add_theme_constant_override("outline_size", 6)
	_alert_banner.add_child(_alert_banner_label)

	add_child(_alert_banner)


func _connect_signals() -> void:
	TurnManager.round_started.connect(_on_round_started)
	TurnManager.combat_started.connect(_on_combat_started)
	TurnManager.combat_ended.connect(_on_combat_ended)


# --- 更新 ---

func _update_hp(_new_hp: float, _max_hp_val: float) -> void:
	# HP UI 已移除 (走 Character.health_bar + HUD 状态栏); 回调保留兼容但无操作
	pass


func _update_ap(_new_ap: int, _max_ap_val: int) -> void:
	# AP 条 UI 已删除, 回调保留兼容
	pass


func _on_round_started(_round_num: int) -> void:
	# 回合标签 UI 已删除, 回调保留兼容
	pass


func _on_combat_started() -> void:
	# 面板视觉已删除, 不再 show() 底部横条; 仅弹警报横幅
	show_alert_banner("⚠ 惊动了丧尸！")


func _on_combat_ended(_victory: bool) -> void:
	# 面板视觉已删除, 战斗结束不做淡出/隐藏 (本来就没显示)
	pass


func _on_phase_changed(_old_phase: int, _new_phase: int) -> void:
	# 面板视觉已删除, 阶段变化仅保留信号连接兼容 (不 crash)
	pass


func _on_actions_ready(_actions: Array) -> void:
	# 面板视觉已删除, 动作就绪不再刷新 AP/HP 条
	pass


## 日志已迁移到 HUD.CombatLog (GameSceneBase 负责转发 combat_sm 信号)


func _on_target_selected(_target: Node) -> void:
	pass


func _on_target_deselected() -> void:
	pass


func _on_end_turn_pressed() -> void:
	end_turn_clicked.emit()
	if combat_sm:
		combat_sm.skip_turn()


# --- 目标选择辅助 ---

func _input(event: InputEvent) -> void:
	if not combat_sm or combat_sm.input_locked:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var space_state := get_viewport().get_world_2d().direct_space_state if get_viewport() else null
		if space_state:
			var params := PhysicsPointQueryParameters2D.new()
			params.collide_with_areas = true
			params.position = get_global_mouse_position()
			var results := space_state.intersect_point(params)
			for result in results:
				var collider: Node = result.collider
				if collider.has_method("take_damage") and int(collider.get("hp") if collider.get("hp") != null else 0) > 0:
					combat_sm.select_target(collider)
					return
		combat_sm.clear_target()
