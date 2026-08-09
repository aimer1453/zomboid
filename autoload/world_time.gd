extends Node

# ============================================================
# WorldTime — 世界时间、天气、污染值管理
# ============================================================

## 当前天数 (从游戏开始算)
var day: int = 1
## 一天中的时间 (0.0 ~ 24.0)
var hour: float = 6.0
## 每天的小时长度 (可配置)
const DAY_HOURS: float = 24.0

## 时间消耗常量 (小时)
## 所有"消耗时间"的动作都走 advance_time(), 生存属性随之衰减
const ROUND_TIME_HOURS: float = 0.02    # 战斗一个完整回合消耗的时间
const WALK_TIME_HOURS: float = 0.05     # 玩家走一步消耗的时间
const SLEEP_TIME_HOURS: float = 6.0     # 睡一觉消耗的时间
const CRAFT_TIME_HOURS: float = 0.5     # 制作一件物品消耗的时间 (Phase 6 用)

## 天气
enum Weather { CLEAR, CLOUDY, RAIN, HEAVY_RAIN, STORM }
var current_weather: Weather = Weather.CLOUDY

## 污染值系统
var _pollution_by_character: Dictionary = {}
const POLLUTION_LIGHT_THRESHOLD: float = 30.0
const POLLUTION_HEAVY_THRESHOLD: float = 80.0
const POLLUTION_MAX: float = 100.0

## 污染随世界时间增长: 下雨时每小时增加
const RAIN_POLLUTION_PER_HOUR: float = 0.5
const HEAVY_RAIN_MULTIPLIER: float = 3.0

signal time_changed(day: int, hour: float)
## 世界时间推进 (elapsed_hours = 本次推进的小时数, 生存属性衰减依赖此信号)
signal time_advanced(day: int, hour: float, elapsed_hours: float)
signal weather_changed(weather: Weather)
signal pollution_updated(character_id: int, value: float, level: String)
signal pollution_critical(character_id: int)


func _ready() -> void:
	print("[WorldTime] 起始: Day ", day, " ", hour, ":00")


## 【统一时间入口】推进世界时间 hours 小时。
## 所有消耗时间的动作 (回合/行走/睡觉/制作) 都必须走这里,
## 生存属性 (饱腹/水分/心情) 和污染值随之按时间衰减。
func advance_time(hours: float) -> void:
	if hours <= 0.0:
		return
	hour += hours
	var days_passed := 0
	while hour >= DAY_HOURS:
		hour -= DAY_HOURS
		days_passed += 1
	if days_passed > 0:
		day += days_passed
		_on_new_day()

	time_changed.emit(day, hour)
	time_advanced.emit(day, hour, hours)

	# 随机天气变化
	if randi() % 20 == 0:
		_roll_weather()

	# 污染随经过的时间增长
	_apply_pollution(hours)


func tick_round() -> void:
	advance_time(ROUND_TIME_HOURS)


func _on_new_day() -> void:
	print("[WorldTime] 新的一天: Day ", day)
	_roll_weather()


func _roll_weather() -> void:
	var roll := randf()
	var new_weather: Weather
	if roll < 0.35:
		new_weather = Weather.CLEAR
	elif roll < 0.60:
		new_weather = Weather.CLOUDY
	elif roll < 0.80:
		new_weather = Weather.RAIN
	elif roll < 0.95:
		new_weather = Weather.HEAVY_RAIN
	else:
		new_weather = Weather.STORM

	if new_weather != current_weather:
		current_weather = new_weather
		weather_changed.emit(current_weather)


func is_raining() -> bool:
	return current_weather in [Weather.RAIN, Weather.HEAVY_RAIN, Weather.STORM]


func get_rain_multiplier() -> float:
	match current_weather:
		Weather.CLEAR, Weather.CLOUDY: return 0.0
		Weather.RAIN: return 1.0
		Weather.HEAVY_RAIN: return HEAVY_RAIN_MULTIPLIER
		Weather.STORM: return HEAVY_RAIN_MULTIPLIER * 1.5
	return 0.0


# --- 污染值 ---

func register_character_pollution(id: int, initial: float = 0.0) -> void:
	_pollution_by_character[id] = initial


func get_pollution(id: int) -> float:
	return _pollution_by_character.get(id, 0.0)


func add_pollution(id: int, amount: float) -> void:
	if not _pollution_by_character.has(id):
		_pollution_by_character[id] = 0.0
	_pollution_by_character[id] = mini(_pollution_by_character[id] + amount, POLLUTION_MAX)
	var val: float = _pollution_by_character[id]
	var level: String = _get_pollution_level(val)
	pollution_updated.emit(id, val, level)
	if val >= POLLUTION_MAX:
		pollution_critical.emit(id)


func reduce_pollution(id: int, amount: float) -> void:
	if _pollution_by_character.has(id):
		_pollution_by_character[id] = maxf(0.0, _pollution_by_character[id] - amount)


func get_pollution_stat_penalty(id: int) -> float:
	var p := get_pollution(id)
	if p >= POLLUTION_HEAVY_THRESHOLD:
		return -0.40
	elif p >= POLLUTION_LIGHT_THRESHOLD:
		return -0.15
	return 0.0


func _apply_pollution(elapsed_hours: float) -> void:
	if not is_raining():
		return
	var outdoor_mult := get_rain_multiplier()
	if outdoor_mult <= 0.0:
		return
	# 户外角色受到雨水污染 (按经过的时间)
	for id in _pollution_by_character:
		if _is_character_outdoors(id):
			add_pollution(id, RAIN_POLLUTION_PER_HOUR * outdoor_mult * elapsed_hours)


func _is_character_outdoors(_id: int) -> bool:
	# 简化: 假设在探索状态下的角色在户外
	return GameManager.current_state == GameManager.GameState.EXPLORING


func _get_pollution_level(val: float) -> String:
	if val >= POLLUTION_HEAVY_THRESHOLD:
		return "heavy"
	elif val >= POLLUTION_LIGHT_THRESHOLD:
		return "light"
	return "clean"


# --- 序列化 ---

func serialize() -> Dictionary:
	return {
		"day": day,
		"hour": hour,
		"weather": current_weather,
		"pollution": _pollution_by_character,
	}


func deserialize(data: Dictionary) -> void:
	day = data.get("day", 1)
	hour = data.get("hour", 6.0)
	current_weather = data.get("weather", Weather.CLOUDY)
	_pollution_by_character = data.get("pollution", {})
