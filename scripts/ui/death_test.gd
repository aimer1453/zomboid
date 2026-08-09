extends Node2D

# 临时自测: 死亡界面 + 存档/读档 联动
# 跑法: godot --headless --fixed-fps 60 --path . --quit-after 20 scenes/death_test.tscn

func _ready() -> void:
	var ok := true
	var msgs: PackedStringArray = []

	# 清理可能存在的旧档, 从"无档"状态开始
	GameManager.delete_save()
	if GameManager.has_save():
		ok = false; msgs.append("初始应无存档")

	# 场景1: 无存档时死亡 → 死亡界面显示 + 暂停 + 读档按钮禁用
	GameManager.game_over("无档死因")
	if GameManager._death_screen == null or not GameManager._death_screen.visible:
		ok = false; msgs.append("死亡界面应显示")
	if not get_tree().paused:
		ok = false; msgs.append("死亡应暂停游戏树")
	if not GameManager._death_screen._load_btn.disabled:
		ok = false; msgs.append("无存档时读档按钮应禁用")
	GameManager.hide_death_screen()
	if get_tree().paused:
		ok = false; msgs.append("隐藏死亡界面应恢复暂停")

	# 场景2: 存档后死亡 → 读档按钮可用
	GameManager.save_game()
	if not GameManager.has_save():
		ok = false; msgs.append("存档后应存在存档")
	GameManager.game_over("有档死因")
	if GameManager._death_screen._load_btn.disabled:
		ok = false; msgs.append("有存档时读档按钮应可用")
	GameManager.hide_death_screen()

	# 场景3: 重新开始 → 解除暂停
	GameManager.restart_from_death()
	if get_tree().paused:
		ok = false; msgs.append("重新开始应解除暂停")

	print("=== 死亡/存档/读档 自测 ===")
	for m in msgs:
		print("  FAIL: ", m)
	print("结果: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
