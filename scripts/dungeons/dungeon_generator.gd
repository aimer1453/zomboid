class_name DungeonGenerator
extends RefCounted

# ============================================================
# DungeonGenerator — BSP 二叉空间分割随机副本生成器
# ============================================================
# 1. 递归把地图矩形二分, 直到最小尺寸 → 叶子节点为房间
# 2. 每个房间随机缩小内边距, 得到可用房间矩形
# 3. L 形走廊连接相邻节点的房间中心
# 4. 输出: 房间列表 / 走廊格集合 / 入口 / 出口

const MIN_ROOM_SIZE := 5   # 最小房间边长 (格)
const MAX_DEPTH := 4       # BSP 最大分割深度

## 地图数据: 0=空(墙) 1=地板 2=出口
var grid: Array = []
var map_w: int = 0
var map_h: int = 0

var rooms: Array[Rect2i] = []
var corridors: Array[Vector2i] = []
var entrance: Vector2i = Vector2i.ZERO
var exit_cell: Vector2i = Vector2i.ZERO

var _rng := RandomNumberGenerator.new()


func generate(width: int, height: int, seed_val: int = 0) -> void:
	map_w = width
	map_h = height
	_rng.seed = seed_val if seed_val != 0 else int(Time.get_ticks_msec())

	# 初始化全墙
	grid = []
	for y in range(height):
		var row: Array = []
		for x in range(width):
			row.append(0)
		grid.append(row)

	rooms.clear()
	corridors.clear()

	# BSP 分割
	var root := Rect2i(1, 1, width - 2, height - 2)
	_split(root, MAX_DEPTH)

	# 每层叶子生成房间 + 连接
	if rooms.is_empty():
		# 兜底: 至少一个房间
		rooms.append(Rect2i(2, 2, maxi(width - 4, MIN_ROOM_SIZE), maxi(height - 4, MIN_ROOM_SIZE)))

	for r in rooms:
		_carve_room(r)

	# L 形走廊连接相邻房间
	for i in range(1, rooms.size()):
		var a := rooms[i - 1].get_center()
		var b := rooms[i].get_center()
		_carve_corridor(a, b)

	# 入口 = 出口 (同一扇门, 从哪进从哪出, 和真实建筑一致)
	entrance = rooms[0].get_center()
	exit_cell = entrance
	grid[exit_cell.y][exit_cell.x] = 2


## BSP 递归分割
func _split(rect: Rect2i, depth: int) -> void:
	if depth <= 0 or _too_small(rect):
		_add_room(rect)
		return

	# 决定分割方向: 按宽高比选择更长的轴
	var vertical := rect.size.x > rect.size.y
	if absi(rect.size.x - rect.size.y) < 3:
		vertical = _rng.randf() < 0.5

	var split_pos: int
	if vertical:
		# 垂直分割 (左右两半), 需要足够的宽
		if rect.size.x < MIN_ROOM_SIZE * 2 + 1:
			_add_room(rect)
			return
		split_pos = rect.position.x + _rng.randi_range(MIN_ROOM_SIZE, rect.size.x - MIN_ROOM_SIZE)
		var left := Rect2i(rect.position.x, rect.position.y, split_pos - rect.position.x, rect.size.y)
		var right := Rect2i(split_pos, rect.position.y, rect.position.x + rect.size.x - split_pos, rect.size.y)
		_split(left, depth - 1)
		_split(right, depth - 1)
	else:
		# 水平分割 (上下两半)
		if rect.size.y < MIN_ROOM_SIZE * 2 + 1:
			_add_room(rect)
			return
		split_pos = rect.position.y + _rng.randi_range(MIN_ROOM_SIZE, rect.size.y - MIN_ROOM_SIZE)
		var top := Rect2i(rect.position.x, rect.position.y, rect.size.x, split_pos - rect.position.y)
		var bottom := Rect2i(rect.position.x, split_pos, rect.size.x, rect.position.y + rect.size.y - split_pos)
		_split(top, depth - 1)
		_split(bottom, depth - 1)


func _too_small(rect: Rect2i) -> bool:
	return rect.size.x < MIN_ROOM_SIZE + 1 or rect.size.y < MIN_ROOM_SIZE + 1


## 叶子矩形缩边成房间 (随机 0~2 格内边距)
func _add_room(rect: Rect2i) -> void:
	var inset := _rng.randi_range(0, 2)
	var room := Rect2i(
		rect.position.x + inset,
		rect.position.y + inset,
		maxi(rect.size.x - inset * 2, MIN_ROOM_SIZE - 2),
		maxi(rect.size.y - inset * 2, MIN_ROOM_SIZE - 2)
	)
	# 防止房间重叠过多 (不完美但可用)
	for existing in rooms:
		if room.intersects(existing):
			room = Rect2i(
				rect.position.x, rect.position.y,
				maxi(rect.size.x, MIN_ROOM_SIZE - 1),
				maxi(rect.size.y, MIN_ROOM_SIZE - 1)
			)
			break
	rooms.append(room)


func _carve_room(room: Rect2i) -> void:
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			if x >= 0 and x < map_w and y >= 0 and y < map_h:
				grid[y][x] = 1


func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	var cur := from
	# 先水平走到目标 x, 再垂直走到目标 y
	while cur.x != to.x:
		cur.x += signi(to.x - cur.x)
		if cur.x >= 0 and cur.x < map_w and cur.y >= 0 and cur.y < map_h:
			grid[cur.y][cur.x] = 1
			corridors.append(cur)
	while cur.y != to.y:
		cur.y += signi(to.y - cur.y)
		if cur.x >= 0 and cur.x < map_w and cur.y >= 0 and cur.y < map_h:
			grid[cur.y][cur.x] = 1
			corridors.append(cur)


## 查询格子类型 (0=墙 1=地板 2=出口)
func get_cell(x: int, y: int) -> int:
	if x < 0 or x >= map_w or y < 0 or y >= map_h:
		return 0
	return grid[y][x]


## 随机选一个房间内可站立的格子
func random_floor_cell_in_room(room_index: int) -> Vector2i:
	var room := rooms[room_index % rooms.size()]
	for attempt in 20:
		var x := _rng.randi_range(room.position.x + 1, room.position.x + room.size.x - 2)
		var y := _rng.randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
		if get_cell(x, y) == 1:
			return Vector2i(x, y)
	return room.get_center()
