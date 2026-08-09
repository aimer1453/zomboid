# 素材资源规范 (assets/)

> 所有游戏素材统一放在 `assets/` 下，按类别分目录。代码内引用统一使用 `res://assets/...` 路径（Godot 会自动忽略大小写，但请保持小写命名）。

## 目录结构

```
assets/
├── sounds/           # 音效 (脚步声/攻击/命中/拾取/UI 点击...)
├── sprites/          # 精灵图 (PNG, 透明背景优先)
│   ├── units/        #   单位: 玩家/敌人/NPC (player_idle_0.png, zombie_walk_0.png)
│   ├── items/        #   物品图标 (canned_food.png, pistol.png)
│   └── ui/           #   UI 图标 (btn_backpack.png, icon_ability.png)
├── tilesets/         # 地图瓦片贴图 (floor_brick.png, wall_apartment.png)
├── fonts/            # 字体文件 (.ttf/.otf/.woff)
└── README.md         # 本规范
```

## 命名规范（重要）

| 类别 | 命名规则 | 示例 | 说明 |
|------|----------|------|------|
| 脚步音效 | `footstep_N.扩展名` | `footstep_1.mp3` | N 从 1 开始；代码自动扫描该前缀，随机播放 |
| 其他音效 | `[类别]_[名称].扩展名` | `attack_sword.wav`, `ui_click.wav` | 类别前缀 + 下划线 + 描述 |
| 精灵图 | `[单位]_[动作]_[帧].png` | `zombie_walk_0.png`, `player_idle_0.png` | 序列帧用 0 起始连续编号 |
| 物品图标 | `[物品id].jpg/png` | `crystal_huge.jpg`, `bandage.png` | 与 DataManager 物品 id 一一对应 |
| 瓦片贴图 | `[地形]_[变体].png` | `floor_apartment.png`, `wall_brick.png` | 后续接入 TileSet 用 |

- 一律**小写**文件名，用 `_` 分隔单词（勿用空格/中文/特殊字符）
- 音频格式：`.wav`（无损）/ `.ogg` / `.mp3`（体积小）
- 图片格式：`.png`（透明支持）优先，`.jpg` 仅用于无透明背景

## 常用音效文件约定（已接入）

代码通过文件名硬引用，以下文件放好后**无需改代码**即自动生效：

| 文件名 | 触发场景 |
|--------|----------|
| `footstep_*.mp3/wav/ogg` | 角色每移动一格，随机播一个（玩家 -8dB / 丧尸 -14dB） |
| `swing.wav` | 近战攻击挥击 |
| `gunshot.wav` | 远程枪声 |
| `hit.wav` | 攻击命中 |
| `miss.wav` | 攻击落空 |
| `spit.wav` | 喷射丧尸酸液 |
| `alert.mp3` | 被丧尸发现警报（横幅滑入时播放） |

## 已接入的物品图标

| 文件名 | 物品 id | 名称 | 说明 |
|--------|---------|------|------|
| `crystal_shard.jpg` | `crystal_shard` | 晶石碎片 | 击杀普通感染者掉落 (crystal_value 5) |
| `crystal_smooth.jpg` | `crystal_smooth` | 能量晶石 | 击杀特殊感染者掉落 (crystal_value 15) |
| `crystal_cluster.jpg` | `crystal_cluster` | 晶簇 | 精英感染者掉落 (crystal_value 35) |
| `crystal_huge.jpg` | `crystal_huge` | 大能量晶石 | Boss 掉落 (crystal_value 60) |

> **约定**: 物品图标命名 = 物品 id，DataManager.get_icon_path(id) 自动按 `res://assets/sprites/items/[id].jpg` 查找。需自定义路径的物品可显式填 `ItemData.icon_path`。新物品的图标直接放入 `assets/sprites/items/` 即可被 HUD 加载。

## 添加素材步骤

1. 把文件放入对应目录，按上面规则命名
2. 重开 Godot（或点编辑器右上角"重新导入"）——Godot 会自动导入新文件
3. 若为音效，确认文件名匹配约定即可播放；若为新贴图，需在代码/场景中引用

## 代码目录规范（scripts/）

```
scripts/
├── scenes/       # 场景基类 GameSceneBase (通用层, 所有场景继承)
├── combat/       # 战斗: 动作数据表/伤害计算/状态机/移动格/测试场景
├── dungeons/     # 副本: BSP 生成/副本场景/占位 TileSet
├── items/        # 物品: 武器工厂
├── tiles/        # 格子: Tile 基类 / Furniture 家具容器
├── ui/           # 界面: HUD/动作菜单/容器/异能树/飘字/血条
├── units/        # 单位: Character 基类 / Player / EnemyBase / 敌人工厂
│   └── enemies/  #   敌人变体: 普通/疾速/喷射/坦克
└── (根)          # 仅剩 main_map.gd 主地图场景脚本
```

- 新增系统脚本放入对应目录；**禁止**在 `scripts/` 根目录或项目根目录新增 `.gd` 文件
- 跨文件引用统一 `preload("res://...")` + 路径 `extends`（Godot 4.7.1 严格模式铁律）

## 注意

- 不要修改 `assets/sounds/` 内文件的**前缀**（`footstep_`），否则扫描不到
- 若删除了音频文件，SoundManager 会静默跳过，不影响游戏运行
- 大体积贴图建议用 `.png` + Godot 导入设置压缩（导入面板可调）
