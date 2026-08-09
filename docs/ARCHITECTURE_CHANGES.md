# 架构改动记录（2026-08-05）

> 改动来源：`TECH_REVIEW.md` 代码审查报告 P0/P1 级问题治理
> 改动人：Senior Developer（高级开发工程师）
> 验证方式：Godot 4.7.1 headless 回归（combat_test 全流程 + main_map + dungeon_base 三场景）✅

---

## 一、本次改动总览

| 编号 | 改动 | 文件 | 状态 |
|------|------|------|------|
| A-1 | 清理武器物品表死数据（damage/range/ap_cost） | `autoload/data_manager.gd` | ✅ 已完成 |
| A-2 | 新增启动期数据一致性校验 | `autoload/data_manager.gd` | ✅ 已完成 |
| A-3 | 修复双向漂移：补 `crowbar`/`baseball_bat` 物品、补 `bow` 武器工厂 | `data_manager.gd` + `weapon.gd` | ✅ 已完成 |
| A-4 | 护甲减伤公式收敛为单一出口 `apply_defense` | `scripts/combat/combat_calculator.gd` | ✅ 已完成 |
| A-5 | 修复双重减伤 bug：`take_damage` 不再自行算护甲 | `scripts/units/character.gd` | ✅ 已完成 |
| A-6 | 坦克猛击改走统一护甲公式 | `scripts/units/enemies/zombie_tank.gd` | ✅ 已完成 |
| B-1 | TurnManager 类型化：消灭 `unit.get()/set()` 鸭子访问 | `turn_manager.gd` + `character.gd` + `game_scene_base.gd` | ✅ 已完成 |
| B-2 | 注释契约审计：AP 扣减契约与实现对齐 | `autoload/turn_manager.gd` | ✅ 已完成 |
| B-3 | 私有方法提升公开：`move_in_direction`/`get_default_attack`/`get_learned_ids` | 6 个文件 | ✅ 已完成 |
| B-4 | 死亡流程统一：`die()` + `_on_died()` 模板方法 | `character.gd` + `enemy_base.gd` + `player.gd` | ✅ 已完成 |
| C-1 | 修复点尸体无反应：基类 `_on_interact` 通用容器打开 + 容器 UI 默认启用 + 尸体搜空注销 | `game_scene_base.gd` + `dungeon_base.gd` + `corpse.gd` | ✅ 已完成 |
| C-2 | 战斗日志从 CombatUI 底部固定区迁到 HUD.CombatLog | `hud.gd` + `combat_ui.gd` + `game_scene_base.gd` | ✅ 已完成 |
| D-1 | 物品稀有度系统：`Rarity` 枚举 + `RARITY_COLORS` + 物品表分级 | `data_manager.gd` + `inventory_backpack.gd` + `furniture.gd` | ✅ 已完成 |
| D-2 | 容器 UI 4×4 网格化（与背包一致）+ 稀有度边框 | `container_ui.gd` + `hud.gd` | ✅ 已完成 |
| E-1 | 扩充丧尸掉落：低级装备（破旧衣衫/长裤/脏鞋/生锈小刀）70%+ 掉率 | `enemy_base.gd` + `data_manager.gd` + `weapon.gd` | ✅ 已完成 |
| E-2 | 容器"全部拿走"按钮（批量拾取至超重停止） | `container_ui.gd` | ✅ 已完成 |
| E-3 | 容器格子右键拿走（与左键一致） | `container_ui.gd` | ✅ 已完成 |
| F-1 | 生存属性系统：饱腹/水分/心情 + 每轮衰减 + 消耗品效果 | `player.gd` + `data_manager.gd` | ✅ 已完成 |
| F-2 | 背包格子右键食用/饮用消耗品 | `hud.gd` | ✅ 已完成 |
| F-3 | HUD 主角状态栏：HP 红条 / AP 蓝条 / 饥饿 / 口渴 / 心情 | `hud.gd` | ✅ 已完成 |
| G-1 | 世界时间驱动重构：`advance_time(hours)` 统一入口 + `time_advanced` 信号 | `world_time.gd` | ✅ 已完成 |
| G-2 | 生存属性按世界时间衰减（每小时 -1.5 饱腹 / -2.5 水分 / -0.5 心情） | `player.gd` | ✅ 已完成 |
| G-3 | 走路消耗时间（探索每步 +WALK_TIME）+ 睡觉/制作时间消耗 API | `player.gd` + `world_time.gd` | ✅ 已完成 |
| G-4 | HUD 显示游戏内时间（Day HH:MM），随 `time_changed` 更新 | `hud.gd` | ✅ 已完成 |
| H-1 | Player 全量序列化：生存/技能点/异能/装备/位置 | `player.gd` | ✅ 已完成 |
| H-2 | 硬核单槽存档 + 读档应用链 + 死亡删档 | `game_manager.gd` + `game_scene_base.gd` | ✅ 已完成 |
| H-3 | HUD 存档按钮（右上角，硬核单槽保存） | `hud.gd` | ✅ 已完成 |
| I-1 | 家园场景：房间（衣柜含棒球棍）+ 花园（初级丧尸），新游戏开场醒来 | `home_base.gd` + `home_base.tscn` + `game_manager.gd` | ✅ 已完成 |
| I-2 | 新手引导：拿棒球棍→装备→击杀丧尸，状态机 + HUD 横幅提示 | `home_base.gd` + `hud.gd` + `character.gd` | ✅ 已完成 |
| J-1 | 家园功能家具系统：床/净化器/收集器/种植区/工作台 + 交互分发 | `home_furniture.gd` + `home_base.gd` | ✅ 已完成 |
| J-2 | 生存流水线：雨水收集→污染水→净化→净水→种植→收获 + 时间驱动 | `home_furniture.gd` + `home_base.gd` | ✅ 已完成 |
| K-1 | 生存属性改造：心情→睡眠（每小时 -1.2，困倦战斗惩罚 -30%） | `player.gd` + `hud.gd` | ✅ 已完成 |
| K-2 | 床等级升级：草席/木床/软床，材料升级，恢复效率递增 | `home_furniture.gd` + `home_base.gd` + `data_manager.gd` | ✅ 已完成 |
| K-3 | 修复"全部拿走"按钮失效：场景 `_input` 抢事件 → `is_point_on_panel` 区分面板内外 | `container_ui.gd` + `game_scene_base.gd` | ✅ 已完成 |
| K-4 | 修复容器负重显示误导：改为"容器剩余 Xkg · 背包 Y/Ykg" | `container_ui.gd` | ✅ 已完成 |
| K-5 | 容器始终渲染 4×4 网格（空位显示空格子）+ 尸体搜空后保留为"已搜刮" | `container_ui.gd` + `corpse.gd` | ✅ 已完成 |
| L-1 | 容器格子点击弹操作菜单（拿走/丢弃），与点击丧尸弹动作菜单同一交互模式 | `container_ui.gd` | ✅ 已完成 |
| L-2 | 丢弃到地面生成 GroundItem（稀有度色顶边 + 物品名），点击可拾取回背包 | `ground_item.gd` + `game_scene_base.gd` | ✅ 已完成 |
| M-1 | 背包面板去 Tab 改上下布局：装备栏（上）+ 4×4 背包（下） | `hud.gd` | ✅ 已完成 |
| M-2 | 双向拖拽：背包→装备槽（装备/更换）、装备槽→背包格（卸下） | `hud.gd` | ✅ 已完成 |
| M-3 | 修复 `equip_weapon` 未写 `equipped_slots` → 装备栏 UI 显示与实际不符 | `player.gd` | ✅ 已完成 |
| M-4 | 战场点击分发 `_input` → `_unhandled_input`：GUI 按钮 consume 后场景不处理，修复战斗点背包/按钮角色挪一步 | `game_scene_base.gd` + `home_base.gd` | ✅ 已完成 |
| N-1 | 修复点丧尸无法显示攻击技能：探索模式 `_handle_explore_click` 增加点丧尸弹菜单分支（之前只处理交互物和移动） | `game_scene_base.gd` | ✅ 已完成 |
| N-2 | 家园房间视野遮挡：玩家在房间内只显示房间（花园黑幕），穿门切换。用 4 矩形挖洞 + `CanvasLayer.follow_viewport_enabled` 跟随相机 | `home_base.gd` | ✅ 已完成 |
| O-1 | 移动范围格子蓝→红 | `move_grid.gd` | ✅ 已完成 |
| O-2 | 丧尸触发战斗后隐藏警戒红圈 | `enemy_base.gd` | ✅ 已完成 |
| O-3 | 背包面板居中偏上 + 背包/存档按钮移到底部 | `hud.gd` | ✅ 已完成 |
| O-4 | 被发现警报横幅居中显示（垂直偏上 40%） | `combat_ui.gd` | ✅ 已完成 |
| O-5 | 丧尸攻击吼叫音效（程序合成 zombie_growl.wav） | `enemy_base.gd` + `assets/sounds/` | ✅ 已完成 |
| O-6 | 初始负重 50kg→10kg + 水/污染水重量 1L=1kg（符合实际）+ force_add_item 防止卸下装备丢失 | `inventory_backpack.gd` + `character.gd` + `data_manager.gd` | ✅ 已完成 |
| O-7 | 探索迷雾：未探索区域全黑，每走一步点亮当前视野圆，昼夜视野不同（白天 5/晚上 2），感叹号 z=300 穿透黑幕 | `home_base.gd` + `enemy_base.gd` | ✅ 已完成 |
| O-8 | 饰品栏系统：4 件饰品（瞄准镜/手套/幸运吊坠/战斗护目镜），装备槽 trinket，视野/射程/命中/暴击/幸运加成查询 | `data_manager.gd` + `character.gd` + `hud.gd` | ✅ 已完成 |
| O-9 | 背包第二个标签页"角色状态"：命中率/暴击率/幸运/体力/负重/视野/射程/攻击/防御 + 锻炼按钮 | `hud.gd` | ✅ 已完成 |
| O-10 | 体力系统：stamina 属性 + 负重上限 = 基础 10kg + stamina*0.5，Player.train() 锻炼 +1 体力 消耗 2h 世界时间 | `player.gd` | ✅ 已完成 |
| P-1 | 修复攻击丧尸时好时坏+优先级：①优先级改为敌人>交互物>移动 ②`_raycast_enemy` 加 1 格半径容差（移动中跨格也能命中）③事件坐标 `event.position` 替代 `get_global_mouse_position()` 避免滞后 | `game_scene_base.gd` | ✅ 已完成 |
| P-2 | 锻炼改健身器材家具：home_furniture 加 Kind.GYM + 颜色，home_base 在房间内 (4,2) 生成 GYM，点击调 `Player.train(1, 2)`（+1 体力, 2h 世界时间） | `home_furniture.gd` + `home_base.gd` | ✅ 已完成 |
| P-3 | 清理 logs/home_shot.wav 空文件（导致 Godot 资源扫描错误 → RichTextLabel 字体回退显示金黄豆腐块，误以为是"主角出生地块"）+ project 防御: 4 个黄方块不是出生地块而是 CombatLog 字体异常 | 清理 `logs/` 残留 | ✅ 已完成 |
| Q-1 | 修复装备护甲不生效：`Player.get_stats` 的 defense 改用 `get_total_defense()`（含装备护甲） | `player.gd` | ✅ 已完成 |
| Q-2 | 修复点丧尸地块弹菜单：`_event_to_world` 改用 Camera2D 显式属性手动计算（避免 canvas_transform/DPI/camera-smoothing 偏移）+ `_raycast_enemy` 容差扩到 1.5 格 | `game_scene_base.gd` | ✅ 已完成 |
| Q-3 | 装备磨损度系统：物品表配耐久（武器20-50/护甲15-60/饰品30-40）；攻击磨损武器、受击磨损护甲；磨损后攻击力/防御按耐久比衰减；`get_item_value` 含磨损折扣（商人交易用）；HUD 装备槽显示耐久；序列化 | `inventory_backpack.gd` + `character.gd` + `data_manager.gd` + `hud.gd` | ✅ 已完成 |
| R-1 | 修复尸体点击"没反应"：点击优先级改为精确格敌人 > 精确格交互物(尸体/家具) > 容差敌人 > 移动（`_raycast_enemy` 加 exact_only 参数）——尸体被邻格丧尸 1.5 格容差抢走导致点不动 | `game_scene_base.gd` | ✅ 已完成 |
| R-2 | 丧尸视野受墙遮挡：`patrol_action` 发现检测加 `has_line_of_sight`（**定义在 Character 基类**，所有单位通用视觉感知：玩家/丧尸/NPC；Bresenham 直线 + 每格查 is_cell_walkable） | `character.gd` + `enemy_base.gd` | ✅ 已完成 |
| R-3 | 移除红色移动范围格子标注（`MoveGrid.set_range` 加 show_visual 参数，`is_cell_in_range` 改查 range_tiles 不依赖 show）——视野由战争迷雾体现 | `move_grid.gd` + `game_scene_base.gd` | ✅ 已完成 |
| S1 | UI快速项 4 件：异能按钮从 AbilityTreeUI 右上角移到 HUD 底部按钮栏（统一背包/异能/存档）；血条数字居中显示在血条内部（不再是下方独立 Label）；战斗 UI 移除额外 HP 行（左上状态栏已有）；物品 tooltip 中文化（kg→千克, 价值→售价, [可装备]→（可拖到上方装备栏穿戴）） | `hud.gd` + `ability_tree_ui.gd` + `unit_health_bar.gd` + `combat_ui.gd` | ✅ 已完成 |
| S2 | 强化点丧尸地块弹菜单：`get_canvas_transform().affine_inverse()` 改回官方 API（兼容 DPI/缩放/camera-smoothing），`_raycast_enemy` 容差扩到 2 格半径 | `game_scene_base.gd` | ✅ 已完成 |
| S3 | **AP+睡眠合并为精力**：删除 `sleep` 字段、`SURVIVAL_SLEEP_PER_HOUR`、`SLEEP_EXHAUSTED_THRESHOLD`；`take_sleep` → `take_rest`；`get_sleep_penalty` → `get_energy_penalty`（按 AP 比例 30% 阈值）；HUD 状态栏 sleep 条删除、AP 条改 label "精力"；新加消耗品 `adrenaline`（精力+40）/ `energy_drink`（精力+20）应急用；开局送 1 肾上腺素 + 2 能量饮料 | `player.gd` + `data_manager.gd` + `hud.gd` + `home_furniture.gd` + 测试 | ✅ 已完成 |
| T1 | 装备详情面板：点击 EquipSlot 弹 Modal 显示**属性**（properties 解析 defense/vision_bonus/accuracy/crit/luck/...）、**磨损**（durability cur/max + 比例条 + 完整度%）、**价值**（带磨损折扣显示）、卸下按钮 | `hud.gd` | ✅ 已完成 |
| T2 | 异能树面板从屏幕居中改到屏幕底部（CENTER_BOTTOM，与底部按钮栏对齐），整个异能交互"全在下面" | `ability_tree_ui.gd` | ✅ 已完成 |
| T3 | BGM 系统：`SoundManager.play_bgm` 独立 BGM 通道；战斗时自动切换 `fight.mp3`，战斗结束/探索时切换 `round.mp3` | `sound_manager.gd` + `game_scene_base.gd` + `assets/sounds/fight.mp3` + `round.mp3` | ✅ 已完成 |
| T4 | 晶石图转透明底 PNG：用 PIL 抠白底（threshold=235，RGB>=235 → alpha=0），4 张线稿（晶石1-4）→ `crystal_shard/smooth/huge/cluster.png`（按用户编号匹配物品稀有度），删除旧 jpg | `assets/sprites/items/crystal_*.png` | ✅ 已完成 |

---

## 二、P1 质量治理（同日第二批）

### P1-1 TurnManager 类型化（消除鸭子访问）

**问题**：`TurnManager` 里 10+ 处 `unit.get("ap_current")` / `unit.set("ap_current", x)` 反射式读写——属性改名编译期不报错，运行期才炸。

**改动**：
- `Character` 基类新增类型化访问器：`get_ap/set_ap/get_ap_max/get_hp/get_max_hp/get_is_moving/set_is_moving`
- `TurnManager` 全部读写收口到 helper（`_unit_ap` / `_set_unit_ap` / `_unit_is_moving` 等），**优先调用类型化方法，非 Character 单位回退反射**（兼容性兜底）
- `game_scene_base.gd:_try_move_one_step` 的 `get("is_moving")/get("ap_current")` 一并替换

**收益**：属性改名即编译报错；helper 集中了唯一的知识点，新人不用猜。

### P1-2 注释契约审计

**问题**：顶部注释声称"player_acted 是 AP 扣除的唯一入口"，但 `spend_player_ap_only`（探索模式）也在扣 AP——注释与实现背离。

**改动**：注释重写为准确契约——
- 战斗模式扣 AP：只能走 `player_acted` / `end_player_phase`，禁止直接 `set_ap`
- 探索模式扣 AP：只能走 `spend_player_ap_only`
- 不要手动 set_ap（除 `_start_new_round` 回满逻辑）

### P1-3 禁止跨类调用私有方法

**问题**：3 处跨类调用 `_` 前缀私有方法——`game_scene_base.gd` 调 `_move_in_direction`/`_get_default_attack`、`ability_tree_ui.gd` 调 `_get_learned_ids`、`combat_test.gd` 调 `_get_default_attack`。

**改动**：私有方法提升为公开方法（有真实业务语义）：`move_in_direction` / `get_default_attack` / `get_learned_ids`，全部调用点更新。

### P1-4 死亡流程统一

**问题**：`Character.die()`（注销+queue_free）被 `EnemyBase` 和 `Player` 覆写且**都不调 super**——注销逻辑复制三份，后续行为会持续分叉。

**改动**：模板方法模式——
- 基类 `die()`：统一处理注销 → 调用 `_on_died()` 钩子
- `EnemyBase._on_died()`：设 DEAD 状态 + 发信号 + 生成尸体 + queue_free
- `Player._on_died()`：触发 `GameManager.game_over()`（玩家不 queue_free）
- **规则**：子类禁止覆写 `die()`，差异化只写 `_on_died()`

---

## 三、P0-1 数据双源治理：单一数据源原则

### 问题背景

物品表（`data_manager.gd`）和武器工厂（`weapon.gd`）是两套独立定义的静态数据，靠 `item_id` 字符串硬关联：

```gdscript
# 旧：物品表里手枪带了 damage/range/ap_cost（实际从未被读取！）
_add_item(ItemData.new("pistol", "手枪", ItemType.WEAPON, "9mm 半自动手枪",
    Vector2i(1,2), 1, "", {"damage": 15, "range": 6, "ap_cost": 4, "ammo_type": "9mm"}))

# 实际生效的是 weapon.gd 工厂（character.gd:_weapon_to_action 只查这里）
# weapon.gd 里手枪：create_ranged_attack("shoot", ..., 4, 1.0, 5, ...)
```

**后果**：改物品表数值不生效、改 weapon.gd 又怕不一致，策划调平衡必踩"改了没生效"的坑。

### 架构决策（2026-08-05）

- **物品表 = 物品元数据**：id / name / type / 描述 / 重量 / 价值 / 槽位 / ammo_type
- **weapon.gd = 武器战斗数值唯一真源**：动作资源（AP/射程/伤害倍率/暴击）
- 两表通过 `item_id` 双向关联，**启动时校验**（见下）

### 校验函数（A-2）

```gdscript
func _validate_data_consistency() -> void:
    # 1. 物品表里每把 WEAPON 都必须在武器工厂里有对应
    # 2. 武器工厂里每把武器都能在物品表里找到物品
    # 发现漂移立即 push_error
```

**实测效果**：首次运行立刻抓到 2 处真实漂移——物品表有 `bow` 但武器工厂缺失（→ 装备复合弓会失败）；武器工厂有 `crowbar`/`baseball_bat` 但物品表缺失（→ 这两把武器永远无法通过背包获得）。已修复（A-3）。

### 团队约定（从此生效）

- **新增武器**：物品表 + 武器工厂**必须同时添加**，否则启动时报错
- **调整武器数值**：只改 `weapon.gd`，禁止在物品表加 `damage/range/ap_cost` 等战斗字段

---

## 三、P0-2 护甲公式统一：修复双重减伤

### 问题背景

护甲减伤存在**两套公式**，且叠加导致双重减伤：

```gdscript
# 公式 1（攻击结算）: CombatCalculator 已算护甲
final_damage = raw_damage * (1.0 - minf(defense * 0.06, 0.75))

# 公式 2（受伤结算）: take_damage 内部又减一次防御！
actual = maxf(amount - get_total_defense() * 0.5, 1.0)
```

**后果**：一次攻击经过两次护甲结算，防御 10 的敌人实际减伤远超预期（60% 后又再减 5 点），数值语义完全分裂。

### 架构决策（2026-08-05）

- **护甲减伤公式唯一出口**：`CombatCalculator.apply_defense(base_damage, defense, pierce) -> float`
- **`take_damage` 只接收最终伤害**：不再自行计算护甲，只负责扣血 + 飘字 + 死亡
- **真实伤害（自伤/DOT）**：调用方直接传原值，不走护甲

### 各调用方行为（改动后语义）

| 调用方 | 传入值 | 语义 |
|--------|--------|------|
| `character.execute_attack` | `result.damage`（已含护甲） | 常规攻击 ✅ |
| `player.execute_ability` | `result.damage`（已含护甲） | 异能伤害 ✅ |
| `zombie_spitter._perform_attack` | `result.damage`（已含护甲） | 酸液 ✅ |
| `zombie_spitter` DOT | 原值 × 0.2 | 酸蚀（穿透）✅ |
| `player` 狂化自伤 | 原值 | 真实伤害 ✅ |
| `zombie_tank._do_slam` | `CC.apply_defense(base, 玩家防御)` | 物理猛击 ✅ |

---

## 四、验证记录

### 1. 数据一致性校验（combat_test 启动场景）

```
[DataManager] 数据一致性校验通过: 7 把武器双向映射完整
```

### 2. combat_test 全流程回归（--auto-test）

```
探索连续移动 → 遭遇丧尸 → 进入战斗 → 玩家行动 → 敌人并行行动 → 回合结束 → 新回合
```
✅ 流程完整闭环，无 SCRIPT ERROR

### 3. main_map 场景回归

```
城市就绪, 点击建筑入口进入副本
```
✅ 零错误

### 4. dungeon_base 场景回归（P1 改动后）

```
[Dungeon] 生成副本... type=APARTMENT  → 玩家/6 敌人全部就绪
```
✅ 零错误

### 5. 尸体交互链路回归（C-1, combat_test 新增 auto-test 段）

```
=== 自动测试: 尸体交互链路 (生成→命中→容器打开) ===
尸体命中=true (应为 true)        ← _raycast_interactable 命中尸体
容器打开=true (应为 true)        ← _on_interact 打开 ContainerUI
尸体列表大小=1                   ← 尸体已注册到场景 _corpses
```
✅ 全链路通过

---

## 六、C 批次修复记录（用户反馈驱动）

### C-1 点开丧尸尸体没反应

**根因**（两个断点叠加）：
1. 基类 `GameSceneBase._on_interact` 是空实现 `pass`——只有副本 `dungeon_base` 覆写了它，**主地图/战斗测试点尸体直接无反应**
2. `_use_container_ui()` 默认返回 `false` → 非副本场景根本不创建 `ContainerUI`，即使命中尸体也没界面可开

**修复**：
- 基类 `_on_interact` 提供**通用实现**：有 `ContainerUI` 且交互物有 `list_inventory` → 打开容器（删除 dungeon_base 冗余覆写，走基类）
- `_use_container_ui()` 默认返回 `true`（尸体搜刮是核心玩法，所有场景都该支持）
- `Corpse.remove_internal_item` 搜空后通知场景 `remove_corpse`，避免 `_corpses` 数组残留失效引用

**遗留**：`enemy_base._spawn_corpse` 用 `world.add_corpse(corpse)` 注册，`world` 是 `get_parent()`；若未来敌人挂到非场景节点下需显式注入世界引用。

### C-2 战斗日志在固定位置而非 HUD 上

**根因**：`_log_panel`（RichTextLabel）是 `CombatUI` 的一部分，而 CombatUI 被 `PRESET_BOTTOM_WIDE` 锚定在屏幕底部 250px 固定区域——日志跟着"焊死"在底部。

**修复**：
- 新建 `HUD.CombatLog` 面板（左上角常驻，半透明，可滚动，`MOUSE_FILTER_IGNORE` 不挡点击）
- 场景基类把 `combat_sm.combat_log_updated` 信号转发到 `_hud.append_log`；HUD 同时监听 `unit_action_executed` 记录动作
- `CombatUI` 删除日志面板及相关连接（`_on_log_updated` 清理）

---

## 七、D 批次记录（玩法增强：物品稀有度）

### D-1 物品稀有度系统

- `ItemData` 新增 `rarity` 字段 + `Rarity` 枚举（COMMON/UNCOMMON/RARE/EPIC/LEGENDARY）
- `DataManager.RARITY_COLORS` 统一管理边框颜色（灰/绿/蓝/紫/金），`RARITY_NAMES` 中文名
- 物品表按品质分级：消耗品/弹药普通、急救包/近战武器优秀、手枪/弓稀有、步枪/防弹衣史诗、大晶石/蓝图传说
- `InventoryBackpack.list_items()` 和 `Furniture.list_inventory()` 输出 `rarity` 字段

### D-2 容器 UI 4×4 网格化 + 稀有度边框

- `ContainerUI` 从 VBox 列表改为 **4×4 网格**（与玩家背包一致，格子 70px，手机友好）
- 每个物品格带**稀有度边框**（2px 稀有度色），tooltip 显示品质名称
- 背包格子同步支持稀有度边框（捡到的物品在背包里同样可辨识品质）
- 回归测试新增稀有度断言段：绷带=普通、急救包=优秀、手枪=稀有、大晶石=传说 ✅

---

## 八、E 批次记录（掉落扩充 + 容器交互增强）

### E-1 丧尸掉落扩充（低级装备）

- 新增 4 件低级装备：`torn_clothes` 破旧衣衫 / `torn_pants` 破旧长裤 / `dirty_shoes` 脏旧鞋子（ARMOR 防 1）/ `rusty_knife` 生锈小刀（WEAPON，weapon.gd 同步注册）
- 掉落规则：**所有丧尸 70% 出 1 件低级装备，25% 出 2 件**（从身上扒下来的），血肉 1-2 不变，变体专属掉落（晶石）保留
- 回归验证：普通丧尸实测掉出 `[zombie_flesh, zombie_flesh, torn_pants]` ✅

### E-2 / E-3 容器交互增强

- **"全部拿走"按钮**：批量拾取直到容器清空或背包超重（超重弹提示，剩余保留）
- **右键拿走**：格子 `gui_input` 拦截右键，与左键同样触发拾取（手机无右键，左键为主路径）

---

## 九、F 批次记录（生存系统 + 状态栏）

### F-1 生存属性系统

- `Player` 新增 `hunger`（饱腹）/ `thirst`（水分）/ `morale`（心情），0~100 满值健康
- **每轮衰减**（`WorldTime` 推进时同步）：饱腹 -0.6 / 水分 -0.9 / 心情 -0.1（绑定 `round_started`）
- 消耗品效果字段：`food`（饱腹）/ `water`（水分）/ `morale`（心情）/ `heal`（生命）/ `reduce_pollution`（污染）
- 新增物品：面包（饱腹 35+心情 5）/ 汽水（水分 12+心情 8）/ 巧克力（饱腹 10+心情 20）
- `consume_item()` 统一处理所有消耗品效果，返回结果字典
- 开局送 2 面包 + 2 净水（体验食用）

### F-2 / F-3 右键食用 + HUD 状态栏

- **右键食用**：背包格子右键点击消耗品 → `consume_item`（tooltip 提示"[右键食用/饮用]"）；左键点击消耗品同样可用
- **HUD 状态栏**（顶部两行）：HP 红条 + AP 蓝条 / 饱食·饮水·心情三条（黄/蓝/粉），随 `hp_changed`/`ap_changed`/`survival_updated` 信号实时更新
- 战斗日志下移至状态栏下方（避免重叠）
- 回归测试新增生存属性段：面包 饱腹 30→65、净水 水分 20→40 ✅

---

## 十、G 批次记录（世界时间驱动重构）

### 架构决策：从"回合驱动"到"时间驱动"

**问题**：生存属性按战斗回合衰减，但走路/睡觉/制作不消耗回合——玩家站着不动时间静止、狂走却不饿，生存压力体系失真。

**新模型**：
```
世界时间 = 唯一时钟
  ├─ 回合推进   → advance_time(ROUND_TIME_HOURS=0.02h)   (战斗每回合)
  ├─ 走路       → advance_time(WALK_TIME_HOURS=0.05h)    (探索每步)
  ├─ 睡觉       → advance_time(SLEEP_TIME_HOURS=6h)      (恢复 HP+心情)
  └─ 制作(未来) → advance_time(CRAFT_TIME_HOURS=0.5h)
生存属性衰减 = 监听 time_advanced(day, hour, elapsed) → 按经过小时数衰减
```

**改动**：
- `WorldTime.advance_time(hours)` 成为**唯一时间推进入口**（跨天/天气/污染全部在内部处理），发 `time_advanced(day, hour, elapsed_hours)` 信号
- `tick_round()` 内部改为调 `advance_time(ROUND_TIME_HOURS)`（战斗回合照旧）
- `Player` 生存衰减从监听 `round_started` 改为监听 `time_advanced`：**每小时 -1.5 饱腹 / -2.5 水分 / -0.5 心情**
- 探索模式每走一格 → `advance_time(WALK_TIME_HOURS)`（主角不动 → 世界静止的设计被强化）
- 新增 `sleep(hours)`（睡觉回 40% HP + 心情 +20，消耗 6h）和 `craft_item()`（制作时间消耗契约，Phase 6 用）
- 污染值改按经过时间计算（`RAIN_POLLUTION_PER_HOUR`）
- HUD 状态栏新增游戏内时间显示（Day HH:MM），随 `time_changed` 实时更新

**验证**：推进 2h → 饱腹 100→97 / 水分 100→95 / 心情 100→99 ✅（精确符合每小时衰减率）

---

## 十二、H 批次记录（P0 存档系统）

### 问题背景

战斗/探索/背包/生存/异能全部完成，但**没有完整存档**——玩家关游戏进度全丢，是上线级硬伤。且存档是"系统收口"，晚做会导致每个模块都要回来补。

### 改动

- **H-1 Player 全量序列化**：`serialize()`/`deserialize()` 保存 生存属性/技能点/异能（存 action_id 可反查数据库，不存 Resource 对象）/装备三槽/位置。异能读档按 id 从 DataManager 重建 Resource。
- **H-2 硬核单槽 + 读档应用链**：
  - `GameManager` 固定 `HARDCORE_SAVE_SLOT=0`，`save_game()/load_game()` 无参简化
  - 读档数据暂存 `_pending_player_data`，场景基类在 Player 创建后调 `apply_pending_player_data(player)` 应用（解决"Player 场景重建导致数据丢失"）
  - `game_over()` → 删档 → GAME_OVER（硬核死亡惩罚）
  - `DataManager.save_exists()` 查询接口
- **H-3 HUD 存档按钮**：右上角背包按钮下方，点击保存（硬核单槽），日志面板提示"[存档成功]"

### 验证

```
=== 自动测试: 存档链路=true (应为 true)  ← 保存→修改→读档→恢复 闭环
```
✅ 全流程回归通过（饱腹 60/技能点 5/HP 150 读档精确恢复）

### 遗留

- 自动存档时机未接（进入副本前/离开副本后）——当前仅手动按钮存档
- 地图进度（建筑入口已探索标记）未入档——Phase 后续

---

## 十三、I 批次记录（家园开场 + 新手引导）

### I-1 家园场景（新游戏开场醒来）

- 新建 `scenes/home_base.tscn` + 重写 `scripts/home_base.gd`（继承 GameSceneBase）
- 布局（16×16 格）：**房间**（左上 6×6，玩家出生 + 衣柜）+ **门**（房间右下）+ **花园**（右侧，1 只初级丧尸）
- 衣柜固定放 `baseball_bat`（棒球棍），花园丧尸削弱（HP 40、移速 80）——新手可击杀
- `GameManager.start_new_game` 改为加载 `home_base.tscn`（原来是 main_map）
- **空手开局**：`Player._ready` 在引导模式下不装备手枪/不送道具（`is_tutorial_mode()` 判断）

### I-2 新手引导状态机

- 步骤：`wake_up → chest_opened → equip_bat → equipped → kill_zombie → zombie_killed → done`
- 触发链：点衣柜 → 引导提示"获得棒球棍! 打开背包穿戴"；`equipment_changed` 信号（Character 新增）→ "穿过后门打丧尸"；`enemy_died` 信号 → "教程完成" + `GameManager.set_tutorial_done()`
- HUD 新增引导横幅（顶部浮动提示，点击关闭）
- 回归：完整链路 `装备=true → 步骤=done → 教程完成=true` ✅

### 遗留

- 引导状态未入档（读档进家园需恢复引导/空手状态）——后续
- 家园后续扩展（Phase 6：雨水收集/种植/净化器）在 `home_base.gd` 骨架上叠加

---

## 十四、J 批次记录（家园生存流水线 Phase 6）

### J-1 家园功能家具系统

- 新增 `scripts/tiles/home_furniture.gd`（`HomeFurniture`，与容器家具 Furniture 区分）：
  - **床**：睡觉（回 40% HP + 心情 +20，消耗 6h 世界时间）
  - **雨水收集器**：下雨时自动积攒污染水（容量 6），点击收获入背包
  - **雨水净化器**：2 污染水 → 2 净水
  - **室内种植区**：消耗 1 种子 + 1 净水种植，随时间生长（约 50h 成熟），点击收获 2-3 食物
  - **工作台**：预留（制作功能 Phase 后续）
- 每家具带状态标签（收集器存量/种植进度），点击交互经 `home_base._handle_home_furniture` 分发

### J-2 生存流水线 + 时间驱动

- 流水线闭环：**雨水收集（下雨）→ 污染水 → 净化器 → 净水 → 种植区 → 食物**
- 时间驱动：挂 `WorldTime.time_advanced`，收集器按经过小时积攒、种植区按经过小时生长
- 玩家开局送 3 种子 + 3 净水（体验种植）
- 回归验证：净化→种植→生长 60h→收获→收集→睡觉 全链路 ✅（净水 6、污染水 4）
- 家园家具/收集器/种植区状态暂未入档（存档扩展 Phase 后续）

---

## 十五、K 批次记录（睡眠机制 + 床升级）

### K-1 生存属性：心情 → 睡眠

- `Player.morale` 移除，新增 `sleep`（睡眠值 0~100，**只能回家睡觉恢复**——食物/药品不提供）
- 每小时衰减 -1.2（三属性中最快，逼迫玩家定期回家睡觉，核心生存节奏）
- **困倦惩罚**：睡眠 < 30 时战斗属性按缺觉程度下降（睡眠=0 时 -30%），`get_sleep_penalty()` 接入 `get_stats()`
- `consume_item` 移除 morale 效果；`sleep()` 改名 `take_sleep(hours, sleep_restore)`（变量/方法同名冲突坑）
- HUD 第三槽"心情"→"睡眠"（紫色条），信号参数同步

### K-2 床等级升级

- 床 3 级：**草席(Lv1) 回40 / 木床(Lv2) 回60 / 软床(Lv3) 回80** 睡眠值
- 升级消耗：Lv1→2 需 丧尸血肉x3 + 木材x2；Lv2→3 需 血肉x5 + 木材x4 + 布料x2
- 新增材料物品：木材/布料（DataManager 注册）
- 交互：床**左键睡觉、右键升级**（home_base `_input` 右键标记）
- 回归：睡觉恢复睡眠+回血、升级 Lv1→2、恢复量 40→60 ✅

### K-3 修复"全部拿走"按钮失效（用户反馈）

**根因**：Godot 事件顺序——场景 `_input`（Node 层）**先于** Control 的 GUI 输入。容器打开时 `game_scene_base._input` 对任何左键点击直接 `close()`，导致点击"全部拿走"按钮的瞬间容器先被关闭，按钮无法正常响应。

**修复**：
- `ContainerUI.is_point_on_panel(screen_pos)`：判断点击是否在面板矩形内（复用 ActionMenu 已有模式）
- 场景 `_input` 改为：**点面板外才关闭容器，点面板内交给 GUI**（按钮/格子正常响应）
- 回归测试新增"全部拿走"段：2 件物品全拿走 → 尸体清空 → 物品进背包 → 尸体注销 ✅

**经验沉淀**：任何"点击 UI 按钮但界面提前关闭"的 bug，先查场景 `_input` 是否抢了 GUI 事件。规则：**打开模态界面时，点面板内的事件必须交给 GUI 处理**。

### K-4 修复容器负重显示误导（用户反馈）

**根因**：容器 UI 的"负重 X/Y"标签显示的是**玩家背包**的重量（`InventoryBackpack.get_total_weight()`），不是容器本身的重量。拿走尸体物品 → 物品进背包 → 背包变重 → 数字变大——玩家看到"负重增加了"，实际是背包在涨，容器在减。

**修复**：标签改为双信息：
```
容器剩余 Xkg · 背包 Y/Ykg
```
- 容器剩余 = 当前容器内物品总重量（拿走一件 → 数字变小，符合直觉）
- 背包 = 玩家负重（跟随变化，方便观察是否超重）

**回归**：拿完 2 件后标签显示 `容器剩余 0.0kg · 背包 3/50kg` ✅

**经验沉淀**：UI 上任何带单位的数据，必须标明"属于谁"。单写"负重"会让玩家默认认为是当前界面的主体（容器）的重量。

### K-5 容器 4×4 网格恒显 + 尸体搜空保留（用户反馈）

**需求**：尸体背包应该是 4×4 格子；拿走全部物品后显示 4×4 空格子。

**改动**：
- `ContainerUI._refresh` 始终渲染 16 格（4×4）：前 N 个是物品格（稀有度边框+点击拿走），剩余是**空格子**（灰底、不可交互）——不再显示"里面空空如也..."文字
- `Corpse` 搜空后**不再 queue_free**，保留为"已搜刮"尸体：变暗 + 标签改"已搜刮"——玩家可再次打开看空格子，也方便识别哪些翻过
- 回归：拿完 2 件后格子数=16（4×4）、尸体保留（列表=1）✅

### U-1 血条数字居中（用户反馈）

**反馈**：血条 200/200 数字显示在血条**左下方**，要求居中。

**根因**：之前修的 `label.size = (_width, _height)` = `(56, 7)`，但字号 11 + outline 4 = 文字实际占 15px > 容器 7px → 文字溢出到容器下方 + X 居中按 56 算 = "左下"视觉。

**修复**：
- `label.size = (_width, 14.0)` 给 11px 字号 + 4px outline 足够空间
- `position.y = -3.5` 让 label 中心 y=3.5 对齐血条中心 y=3.5
- `vertical_alignment = CENTER` 强制内容垂直居中

**经验沉淀**：**Label 容器 size 必须 ≥ 字号 + outline 2倍**，否则内容会溢出 size 外，但 alignment 仍按 size 算，导致位置算错。Godot Label 不像 Panel 自动扩展。

### V-1 SoundManager 结构错位修复（用户反馈: 战斗结束 BGM 不切回）

**反馈**：战斗结束 BGM 没有切回探索曲。

**根因**：`sound_manager.gd` 上次插入 `play_bgm` 时把 `play()` 函数体（SFX 池逻辑）挤到 `play_bgm` 中间——`play()` 只剩 `if is_empty: return` 提前结束，**所有 SFX（脚步声/吼叫/枪声）全部失效**；SFX 残留代码被并入 `play_bgm` 尾部，每次切 BGM 还会往 SFX 池多播一遍（音效叠加）。

**修复**：重写 `sound_manager.gd`：`play()` / `play_bgm()` / `play_random()` / `play_footstep()` 各归其位，`play_bgm` 纯净（同名且播放中忽略 + 空串停止）。

**验证**：`[BGM] 切换: fight.mp3` 正常打印；战斗信号链路完整（`exit_combat → combat_ended.emit → _on_combat_ended → play_bgm("round.mp3")`）✅

**经验沉淀**：**往函数中间插入新函数必须检查函数体是否被截断**——GDScript 缩进语法下，新函数若插在旧函数体中间，旧函数提前 return、后半段并入新函数，静默产生双重 bug（SFX 全灭 + BGM 叠加）。

### V-2 尸体标注文字恢复（用户反馈）

**反馈**：尸体上面的标注文字没了。

**原因**：U-2 里 `_label.visible = false` 把尸体名（"丧尸尸体"）也一起隐藏了——用户只是不想要"已搜刮"文字，尸体名标签要保留。

**修复**：`corpse._apply_corpse_look` 恢复 label 显示（`furniture_name` + 暗红亮色 `CORPSE_LABEL_COLOR`），搜空仍 `queue_free` 消失。

### X-1 墙体不显示：TileMapLayer 渲染不可靠 → DrawTileMap 自定义绘制（用户反馈）

**反馈**："墙体还是没有显示出来，我需要地面和墙体有区分"——多次反馈后像素分析定位。

**根因**（通过截图像素分析确认，不是猜测）：
- 截图像素统计：家具（Node2D+ColorRect）正常渲染（金色/蓝色在），迷雾（Node2D+ColorRect）正常渲染（12.8% 黑），**但 TileMapLayer 的地板+墙几乎为 0**（墙红 0.1%、地板 0.3%，剩余 82.7% 是灰背景）
- 与之前迷雾 TileMap 不渲染是**同一个坑**：本项目里 `TileMapLayer` 渲染不可靠（cell 数据/atlas 像素全对，但屏幕上看不到）

**修复**：新建 `scripts/scenes/draw_tile_map.gd`（class_name DrawTileMap extends Node2D）
- 接口与 TileMapLayer 兼容：`set_cell(cell, source, coords)` / `get_cell_source_id` / `get_cell_atlas_coords` / `get_used_cells`
- 内部 `_draw()` 一次绘制所有格子（1 个 draw call，性能优于几百个 ColorRect）
- 墙加了砖缝纹理（3 条横线 + 错开竖缝）+ 所有格子浅描边，强化"墙"和"地板"区分
- 替换：home_base / main_map / dungeon_base / combat_test 四个场景 `TileMapLayer.new()` → `DTM.new()`

**验证**（截图 + 像素分析，三个场景全过）：
```
home_base: 墙 0.1% → 0.54%, 地板 0.3% → 0.95%
main_map:  墙 10.17%, 地板 46.55%, 40 行连续墙体块 ✅
dungeon:   墙 8.38%, 地板 23.78%, 29 行连续墙体块 ✅
combat_test 0 SCRIPT ERROR, home_base 生存流水线 ✅
```

**踩坑**：
- class_name 全局注册在 headless 下不生效 → 改用 preload 常量 `DTM`（父类 game_scene_base 已声明，**子类不能重复声明** `const DTM`，否则 "member already exists in parent class"）
- `get_cell_atlas_coords` 返回 Variant 时 `var coords := ...` 推断失败 → 显式 `var coords: Vector2i`
- 子类重写 `_on_scene_ready` 不调 `super._on_scene_ready()` → 截图钩子失效（home_base/dungeon_base 都补上）

**经验沉淀**：**TileMapLayer 在本项目不可用，地图一律用 DrawTileMap（Node2D 自定义绘制）**。这是第二次踩同一个坑（迷雾+地图），教训够深了。

### V-3 恢复"已搜刮"标记 + 居中于尸体中心（用户澄清）

**反馈**："我不是不想要已搜刮，我要的，只是需要居中于尸体中心而已"——U-2 理解错了。

**修复**（撤销 V-2 的 queue_free 行为，恢复 K-5 的"已搜刮"保留 + 加居中）：
- `corpse.remove_internal_item` 搜空后**保留**尸体 + 调 `_apply_searched_look`（变暗 `CORPSE_SEARCHED_COLOR` + 标签"已搜刮"）
- 新增 `_center_label()`：`label.size = _rect.size` + `label.position = _rect.position` + 双 `CENTER` —— **"已搜刮"文字精确居中于尸体方块中心**（之前 label 在方块上方偏左）
- `_apply_corpse_look`（尸体名）和 `_apply_searched_look`（已搜刮）都调 `_center_label`
- `combat_test` 断言恢复"尸体保留 + searched=true" ✅

**经验沉淀**：U-2 被用户"删掉尸体已搜刮"的表述误导，实际意图是"位置居中"而非"删除功能"。**修复视觉问题时先确认是"删功能"还是"移位置"**——用户对功能的情感依附往往比字面表述更深。

### U-2 删除"已搜刮"尸体残留 + 尸体居中（用户反馈）

**反馈**：尸体方块上"已搜刮"文字 + 尸体方块没居中，全删。

**改动**（逆转 K-5 设计）：
- `Corpse.remove_internal_item` 搜空后 → `queue_free()` 直接消失（不再保留"已搜刮"尸体）
- 删除 `_apply_searched_look`、`searched` 标记、`CORPSE_SEARCHED_COLOR`、`CORPSE_LABEL_COLOR`
- `Corpse._apply_corpse_look` 设置 `_label.visible = false`（不显示"丧尸尸体"浮字）
- `Furniture._build_visual` label 居中重算：
  - 旧：`position = (-_tile_size * 0.7, -_tile_size * 0.55)` 偏左偏上
  - 新：`size = (0.75 * ts, 12)` + `position = (-0.375 * ts, _rect.position.y - 12)` 居中在主体上方
- `combat_test` 断言改"尸体 queue_free（is_instance_valid OR is_queued_for_deletion 为真）" ✅

**经验沉淀**：用户反馈"保留已搜刮尸体方便识别"实际是累赘（4×4 空格子=地图污染）。**设计师的"贴心的细节"用户可能不买账**，跟随用户反馈及时简化。

### L-1 / L-2 容器格子操作菜单 + 丢弃到地面可拾取（用户反馈）

**需求**：点击容器（非角色背包）里的物品格，应弹出**可执行操作列表**（像点击丧尸弹出拳击那样），包含"拿走"和"丢弃"；丢弃的物品掉到地上后可以再捡起来。

**改动**：
- `ContainerUI` 新增**格子操作菜单**（PanelContainer：拿走 / 丢弃 / 取消），点击物品格弹出（左键/右键一致），定位在格子旁——与 `ActionMenu`（点击丧尸弹攻击）同一交互范式
- 菜单"拿走" → 原拾取逻辑（背包超重弹提示）；菜单"丢弃" → 从容器移除 + 发 `item_discarded` 信号
- 新增 `scripts/tiles/ground_item.gd`（**GroundItem**）：黄褐色半透明块 + **稀有度色顶边**（品质一眼可辨）+ 物品名标签（多件显示 ×N），不阻挡通行
- `game_scene_base` 连接丢弃信号 → `_spawn_ground_item()`：落在**玩家相邻空位**（找不到就玩家脚下），注册进 `_ground_items` 列表，参与 `_raycast_interactable` 命中检测
- `_on_interact` 增加地面物品分支：点击 → `pick_up()` 拾回背包（成功则场景注销 + 移除；背包满/超重留在原地）
- 回归：点格子弹菜单 → 丢弃（容器减少 + 地面生成 + 背包数量不变）→ 点地面拾取（物品回背包 + 地面注销）→ 菜单拿走（背包 +1 + 容器清空）全链路 ✅

**设计说明**：地面物品的"落点 = 玩家相邻格"而非容器位置——从容器扔东西掉在脚下，符合直觉；稀有度色顶边延续 D 批次的"品质一眼可辨"原则。

### M-1 / M-2 / M-3 背包面板上下布局 + 双向拖拽（用户反馈）

**需求**：点开背包应该是上面装备栏、下面背包；支持拖动更换或装备。

**改动**：
- `_build_panel` 去掉 Tab 双页（背包/装备切换），改为**上下布局**：负重条 → **装备栏**（武器/防具/背包 3 槽）→ **4×4 背包网格** → 关闭
- **双向拖拽**：
  - 背包物品 → 拖到装备栏对应槽 = **装备**（`EquipSlot._drop_data` → `equip_item`，同槽位旧装备自动放回背包 = **更换**）
  - 装备槽 → 拖回背包格 = **卸下**（`EquipSlot._get_drag_data` 带 `from_slot` 标记 → `InvSlot._drop_data` → `unequip_item`）
  - 点击已装备物品 = 卸下（保留原交互）
- `InvSlot` 增加 `hud` 引用；装备槽拖拽预览用深紫色区分来源
- **顺带修复隐藏 bug**：`Player.equip_weapon()`（资源式装备，开局手枪）只设 `equipped_weapon`、**没写 `equipped_slots`** → HUD 装备栏读 `get_equipped_item` 返回空，UI 与实际不符。修复：`equip_weapon` 同步 `equipped_slots["weapon"] = weapon.weapon_id`
- 回归：拖拽装备闭环（装备→替换旧武器回背包→拖回卸下→点击卸下→恢复）✅

### M-4 战斗点背包/按钮角色挪一步（用户反馈）

**需求**：战斗时点击背包会移动一下，点背包物品应该静止。

**根因**：场景点击分发用 `_input`（Node 层先于 GUI）。点右上角"背包"按钮的那次点击，**背包还没打开**，`HUD.is_open()` 兜底不生效 → 场景把它当战场点击 → `_try_move_one_step` 让角色往按钮方向挪一格，然后事件才落到 GUI 打开背包。同类问题影响所有 HUD 边缘按钮（存档等）。

**修复**：战场点击分发 `_input` → **`_unhandled_input`**（Godot 标准实践）：GUI 按钮/格子 `consume` 事件后，场景根本收不到点击——从根上消除"点 UI 触发战场逻辑"。保留 HUD/容器打开时的兜底 return（点面板内空白未 consume 的场景仍会被拦截）。
- `home_base._input` 同步改 `_unhandled_input`（右键床升级标记 + `super` 链）
- 回归：新增"背包打开时点击不移动"断言（打开背包 → 模拟左键 → 位置不变）✅

**经验沉淀**：**Godot 中"点 UI 同时触发世界逻辑"的 bug，标准解法是把世界交互从 `_input` 挪到 `_unhandled_input`**——GUI 消费的事件自动与战场逻辑解耦，比逐个按钮做 `is_point_on_panel` 判断更彻底。

### N-1 探索模式点丧尸弹菜单（用户反馈）

**反馈**：点击丧尸无法显示攻击技能（之前只战斗模式可弹菜单，探索模式点丧尸只会走过去）。

**改动**：`_handle_explore_click` 增加敌人命中分支——点丧尸 → `_raycast_enemy` → `_open_action_menu`（与战斗模式一致），玩家可主动开战。
- 回归：`_test_enemy_menu`（菜单打开 + 动作列表非空）✅

### N-2 家园房间视野遮挡（用户反馈）

**反馈**：在房间内能看到花园，违反"在房间里看不到外面"的预期。

**实现**：
- `home_base` 加 `_vision_layer`（CanvasLayer layer=40 在 HUD 下）+ `_player_in_room` 状态
- `_setup_vision_overlay` → `_rebuild_vision_masks`：根据 `_player_in_room` 用 4 个黑色矩形"框"出非玩家区（房间外黑幕 / 房间黑幕），实现挖洞效果
- `_process` 每帧检测玩家 `grid_pos` 是否进出房间（`_is_room_cell(2..7, 2..7)`），变化时重建遮罩
- **关键**：`CanvasLayer.follow_viewport_enabled = true` 让 CanvasLayer 跟随玩家 Camera2D，遮罩在世界坐标上正确覆盖（否则 Camera2D 偏移房间位置而 CanvasLayer 用屏幕坐标，盖错位置）
- 截图验证：玩家在房间内 → 房间亮 + 移动范围可见 + 家具可见，花园全黑（丧尸/收集器/种植区看不到）✅

**经验沉淀**：**CanvasLayer 默认不跟随 Camera2D**——做"世界坐标的覆盖层"（视野/暗幕/标记）必须 `follow_viewport_enabled = true`，否则遮罩盖错屏幕位置。这是 CanvasLayer 最容易踩的坑。

---

## 十六、后续路线（未在本轮处理）

- [x] **P1-1** TurnManager 类型化：消除 `unit.get("ap_current")` 鸭子访问（已完成 2026-08-05）
- [x] **P1-2** 注释-实现契约审计（AP 扣减契约与实现对齐）
- [x] **P1-3** 禁止跨类调用私有方法（`move_in_direction`/`get_default_attack`/`get_learned_ids` 公开化）
- [x] **P1-4** 死亡流程统一（`die()` + `_on_died()` 模板方法）
- [ ] **P2** 引入 GUT 单元测试（`CombatCalculator` 是完美单测对象）
- [ ] **P2** 日志分级（`print` → `Log.info/warn/error`）

> 完整审查报告见 `TECH_REVIEW.md`
