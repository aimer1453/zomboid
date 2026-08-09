extends Node

# ============================================================
# SoundManager — 全局声音管理器 (Autoload)
# ============================================================
# 对象池 AudioStreamPlayer, 支持并发音效。
# 音频文件约定: 放在 res://assets/sounds/ 下, 通过文件名播放。
#
# 用法: SoundManager.play("footstep_1.wav", -8.0)
#       SoundManager.play_bgm("fight.mp3", -4.0)  # 战斗/探索切换, 传 "" 停止

const POOL_SIZE := 8

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
## BGM 播放器 (与 SFX 池分离, BGM 循环播放)
var _bgm_player: AudioStreamPlayer = null
var _current_bgm: String = ""


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Music"
	# 兜底循环: 万一 stream 的 loop 标记没生效(导入设置丢失), 播完自动重播
	_bgm_player.finished.connect(_on_bgm_finished)
	add_child(_bgm_player)
	print("[SoundManager] 就绪 (池 ", POOL_SIZE, ", BGM 通道 OK)")


## BGM 播完 → 自动重播 (双保险: 除了 stream.loop, 再加信号兜底)
func _on_bgm_finished() -> void:
	if _current_bgm == "" or _bgm_player == null:
		return
	if _bgm_player.stream == null:
		return
	_bgm_player.play()
	print("[BGM] 循环重播: ", _current_bgm)


## 播放音效 (sound_name 是 assets/sounds/ 下的文件名, 如 "footstep_1.wav")
func play(sound_name: String, volume_db: float = 0.0) -> void:
	if sound_name.is_empty():
		return
	var path := "res://assets/sounds/" + sound_name
	if not ResourceLoader.exists(path):
		push_warning("[SoundManager] 缺少音频: ", path)
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.play()


## BGM 切换: 循环播放 (战斗 BGM / 探索 BGM)
## 传空字符串停止 BGM; 同名且正在播放则忽略
func play_bgm(sound_name: String, volume_db: float = -6.0) -> void:
	if not _bgm_player:
		return
	if sound_name == "":
		_bgm_player.stop()
		_current_bgm = ""
		return
	if sound_name == _current_bgm and _bgm_player.playing:
		return  # 已在播放
	var path := "res://assets/sounds/" + sound_name
	if not ResourceLoader.exists(path):
		push_warning("[SoundManager] 缺少 BGM: ", path)
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	_force_loop(stream)
	_bgm_player.stream = stream
	_bgm_player.volume_db = volume_db
	_bgm_player.play()
	_current_bgm = sound_name
	print("[BGM] 切换: ", sound_name, " (循环=on)")


## 运行时强制把 BGM 流设为循环 — 不依赖 .import 里的 loop 参数
## (WAV 的采样点循环区间不好推算, 交给 finished 信号兜底重播)
func _force_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true


## 随机播放一组音效中的一个 (如 ["footstep_1.wav", "footstep_2.wav"])
func play_random(sound_names: Array, volume_db: float = 0.0) -> void:
	if sound_names.is_empty():
		return
	play(sound_names[randi() % sound_names.size()], volume_db)


# --- 脚步声 (自动扫描 assets/sounds/footstep_*) ---

var _footstep_cache: Array[String] = []
var _footstep_scanned: bool = false
var _footstep_warned: bool = false

## 播放一步脚步声: 自动收集 assets/sounds/ 下所有 footstep_* 音频, 随机播一个。
## 支持 .wav / .ogg / .mp3, 文件多则随机更自然; 没有文件时静默 (仅警告一次)。
func play_footstep(volume_db: float = 0.0) -> void:
	if not _footstep_scanned:
		_footstep_scanned = true
		_scan_footsteps()
	if _footstep_cache.is_empty():
		if not _footstep_warned:
			_footstep_warned = true
			push_warning("[SoundManager] 未找到脚步音频 (assets/sounds/footstep_*.wav/ogg/mp3), 已静默")
		return
	play(_footstep_cache[randi() % _footstep_cache.size()], volume_db)


func _scan_footsteps() -> void:
	var dir := DirAccess.open("res://assets/sounds")
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.begins_with("footstep") \
				and (f.ends_with(".wav") or f.ends_with(".ogg") or f.ends_with(".mp3")):
			_footstep_cache.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	if not _footstep_cache.is_empty():
		print("[SoundManager] 脚步音频已加载: ", _footstep_cache.size(), " 个 (", str(_footstep_cache), ")")
