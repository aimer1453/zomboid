extends Node2D

# ============================================================
# AlertRange — 丧尸警戒范围 (逻辑保留, 视觉移除)
# ============================================================
# 视觉移除 (用户反馈: "室内柱子太多", 红色警戒格子像柱子; 视野由迷雾/距离体现, 不画格子)
# 仍保留 set_range 更新 range_tiles 给战斗触发逻辑使用

var range_tiles: int = 5
var tile_size: int = 32
## 视觉显示开关: 默认 false, 永远不画红色格子 (视觉用迷雾/距离体现)
var show: bool = false


func set_range(tiles: int, t_size: int) -> void:
	range_tiles = maxi(tiles, 0)
	tile_size = maxi(t_size, 1)
	# show 始终 false: 不画红色警戒格子 (用户反馈: 柱子太多)
	show = false
	queue_redraw()


## 抵消父节点走路倾斜, 保持红圈水平 (父角色走动时 rotation 会左右摆)
func _process(_delta: float) -> void:
	var p := get_parent()
	if p and p.rotation != 0.0:
		rotation = -p.rotation
	elif rotation != 0.0:
		rotation = 0.0


func hide_range() -> void:
	show = false
	queue_redraw()


func _draw() -> void:
	# 视觉不画 (用户反馈): 只保留 set_range 更新数据给战斗触发用
	pass