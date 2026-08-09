# 僵尸生存（Zomboid Survivor）

基于 **Godot 4.7.1 (mono)** + **GDScript** 的 2D 俯视角僵尸生存游戏，包含家园经营、世界地图探索、多地牢副本、背包/装备、战斗与技能树等系统。

---

## 运行环境

- 引擎：`Godot_v4.7.1-stable_mono_win64`
- 路径示例：`/e/Godot/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe`
- 入口场景：`res://scenes/home_base.tscn`（编辑器内按 Play 直接进家，金色门可见）
- 真实路由：`main.tscn` → `GameManager` → `home_base`（新游戏）/ `world_map`（读档）

---

## 自动测试（headless）

无需窗口即可验证核心逻辑，三套场景各跑各的回归项：

Any applications or scripts using this token will no longer be able to access the GitHub API. You cannot undo this action.



> ⚠️ `--auto-test` 必须放在 `--` 之后，否则 `OS.get_cmdline_user_args()` 读不到参数，游戏会卡在无窗口等待。  
> headless 下视口=窗口，`get_screen_transform()` 为单位矩阵，无法覆盖「编辑器内真实鼠标事件」路径，涉及坐标/点击的改动需额外在编辑器内验证。

---

## 目录结构

```
project.godot
scripts/
  units/        # player, character, enemy_factory, enemy_base, zombie_*
  ui/           # hud, item_action_menu, combat_ui, ability_tree_ui, container_ui, damage_popup
  scenes/       # game_scene_base(基类), dungeon_base, home_base, draw_tile_map
  world/        # world_map_data(autoload), world_map
  tiles/        # furniture, home_furniture, ground_item, tile_set_builder
  dungeons/     # dungeon_base
scenes/         # *.tscn 场景文件
```

---

## Git 工作流约定

仓库以 `master` 为稳定基线，每个可玩/可验证的状态都应对应一个清晰的提交。

### 分支策略（轻量 Git Flow）

- **`master`** — 稳定基线。每个提交应保证三套自动测试全绿、0 运行期 SCRIPT ERROR。
- **日常改动** — 直接在 `master` 做**原子提交**（一个功能点 = 一个 commit），提交信息写清改动范围。
- **大型 / 高风险 / 实验性改动** — 从 `master` 切 `feature/功能名` 分支开发，验证通过后合并回 `master` 并删除分支：
  ```bash
  git checkout -b feature/xxx
  # ... 开发 + 自动测试通过 ...
  git checkout master
  git merge feature/xxx
  git branch -d feature/xxx
  ```

### Commit 规范

`<type>: <简述>`（中文简述即可），type ∈

| type       | 含义        |
| ---------- | --------- |
| `feat`     | 新功能       |
| `fix`      | 修复 bug    |
| `refactor` | 重构（无行为变化） |
| `docs`     | 文档        |
| `test`     | 测试        |
| `chore`    | 杂项（配置/清理） |

### 常用回退

```bash
git log --oneline          # 查看历史
git diff HEAD~1            # 比对上一次改动
git checkout d9f849d       # 回到「视觉缩放基线」(720 分辨率 / zoom 1.8 / 原始 UI)
```

---

## 已知遗留问题（非阻断，待处理）

- `combat_test` 中 `_test_zombie_wall_block` 偶发「丧尸越墙」——属 RNG（时间种子）随机巡逻导致测试断言过严，非真实穿墙 bug。
- `scenes/main_map.tscn` / `main_map.gd` 已弃用（被 `world_map` 取代），文件保留未删。
- 武器耐久未随攻击下降（既有 durability 系统问题），不在视觉/路由修复范围内。

---

## 约定速记（高频踩坑，跨会话复用）

- **点击坐标转换**：只用 `get_canvas_transform().affine_inverse() * event.position`，与 `get_global_mouse_position()` 一致。**不要多乘 `get_screen_transform()`**（编辑器内真机会整体偏移数格）。
- **纯视觉 Control**（`ColorRect`/`Label`/`TextureRect` 等）一律 `mouse_filter = MOUSE_FILTER_IGNORE`，否则会吞点击 / 触发 `gui_get_hovered_control()` 误判。
- **地图渲染走 `DrawTileMap`**：只认 `_cells[cell]=tile_index` + `TILE_COLORS` 查表上色，**不读 TileSet atlas 像素**；改地形外观只能改 `TILE_COLORS` 字典。
- **血量全程用 float**：任何 `int(hp)` 截断都会把 `0<hp<1` 的残血单位误判为死亡（选不中）。
- **Godot 4.7 严格模式**：成员/数组元素类型未声明时 `var x := expr` 无法推断，需显式标注 `var x: T = ...`；lambda 对 `int/bool` 是值捕获，跨回调改状态需用 `Array/Dictionary/对象引用`。
