extends Node

# ============================================================
# PartyManager — 小队成员管理与 AI 指令
# ============================================================

enum AICommand { FOLLOW, ATTACK_TARGET, DEFEND, IDLE }

## 小队成员数据
class MemberData:
	var character_id: int
	var name: String
	var hp: float
	var max_hp: float
	var ap_current: int
	var ap_max: int
	var command: AICommand
	var learned_abilities: Array[String]
	var skill_points: int
	var absorption_rate: float
	var level: int

	func _init(p_id: int, p_name: String):
		character_id = p_id; name = p_name
		max_hp = 100.0; hp = max_hp
		ap_max = 10; ap_current = ap_max
		command = AICommand.FOLLOW
		learned_abilities = []
		skill_points = 0
		absorption_rate = 1.0
		level = 1


var _members: Array[MemberData] = []
var _active_tab_index: int = 0


# --- 成员管理 ---

func add_member(character_id: int) -> void:
	var name: String = GameManager.get_character_name(character_id)
	var member := MemberData.new(character_id, name)
	_members.append(member)
	print("[PartyManager] 新成员: ", name)


func get_members() -> Array[MemberData]:
	return _members


func get_member(idx: int) -> MemberData:
	if idx >= 0 and idx < _members.size():
		return _members[idx]
	return null


func get_member_count() -> int:
	return _members.size()


# --- AI 指令 ---

func set_command(member_idx: int, command: AICommand) -> void:
	var member := get_member(member_idx)
	if member:
		member.command = command


func get_command_name(cmd: AICommand) -> String:
	match cmd:
		AICommand.FOLLOW: return "跟随"
		AICommand.ATTACK_TARGET: return "攻击目标"
		AICommand.DEFEND: return "防守"
		AICommand.IDLE: return "待命"
	return "未知"


# --- 晶石吸收 ---

func absorb_crystal(member_idx: int, crystal_value: int, bonus_mult: float = 0.0) -> int:
	var member := get_member(member_idx)
	if not member:
		return 0
	var efficiency := member.absorption_rate + bonus_mult
	var gained := int(float(crystal_value) * efficiency)
	member.skill_points += gained
	return gained


# --- 属性管理 ---

func get_character_data(character_id: int) -> Dictionary:
	var base_stats := {
		1: {"hp": 120, "atk": 15, "def": 12, "desc": "近战专家，肉身强化"},
		2: {"hp": 90,  "atk": 12, "def": 8,  "desc": "远程专精，陷阱大师"},
		3: {"hp": 85,  "atk": 8,  "def": 6,  "desc": "生化改造，辅助治疗"},
		4: {"hp": 80,  "atk": 10, "def": 7,  "desc": "电磁操控，科技流"},
		5: {"hp": 75,  "atk": 14, "def": 5,  "desc": "精神异能，超自然"},
	}
	return base_stats.get(character_id, {"hp": 100, "atk": 10, "def": 8, "desc": "未知"})


# --- 序列化 ---

func serialize() -> Dictionary:
	var data := []
	for m in _members:
		data.append({
			"character_id": m.character_id,
			"name": m.name,
			"hp": m.hp, "max_hp": m.max_hp,
			"ap_current": m.ap_current, "ap_max": m.ap_max,
			"command": m.command,
			"learned_abilities": m.learned_abilities,
			"skill_points": m.skill_points,
			"absorption_rate": m.absorption_rate,
			"level": m.level,
		})
	return {"members": data}


func deserialize(data: Dictionary) -> void:
	_members.clear()
	for d in data.get("members", []):
		var m := MemberData.new(d.character_id, d.name)
		m.hp = d.get("hp", 100.0)
		m.max_hp = d.get("max_hp", 100.0)
		m.ap_current = d.get("ap_current", 10)
		m.ap_max = d.get("ap_max", 10)
		m.command = d.get("command", AICommand.FOLLOW)
		m.learned_abilities = d.get("learned_abilities", [])
		m.skill_points = d.get("skill_points", 0)
		m.absorption_rate = d.get("absorption_rate", 1.0)
		m.level = d.get("level", 1)
		_members.append(m)
