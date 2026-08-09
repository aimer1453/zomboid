# 《晶石禁区》代码审查报告 + 团队技术提升方案

> 审查人：Senior Developer（高级开发工程师）
> 审查日期：2026-08-05
> 审查范围：7 个 Autoload 单例、场景基类、单位基类、战斗计算、数据层（约 3000 行核心代码）
> 审查方式：代码通读 + 交叉验证（双数据源实测比对）

---

## 一、总体评价（先说结论）

**这是一支有架构意识的团队，正在正确的方向上快速演进。** 具体亮点：

| 做得好的地方 | 证据 |
|------|------|
| 模板方法模式（基类抽取） | `GameSceneBase` 将三个场景 1000+ 行重复代码收敛到通用层，子类只覆写钩子 |
| 敌人并行行动的异步陷阱规避 | "同步启动 + 统一等待动画" 正确绕开了 Godot async/await 的深坑 |
| 网格命中替代物理射线 | 对网格制游戏是**正确**的工程决策，比 Area2D 射线可靠得多 |
| 踩坑记录制度化 | PROJECT_STATUS.md 的踩坑表 + 测试方法段落，非常有价值 |
| 注释质量 | 每个文件的职责、核心模型、关键修正都有清晰注释 |

**但存在 3 个架构级隐患（P0）和若干质量级问题（P1/P2）**，如不及时治理，会在 NPC、存档、家园系统上线后集中爆发——那时候改造成本是指数级的。

---

## 二、P0 级问题（架构级，建议 2 周内治理）

### P0-1 双数据源漂移：同一件物品，两套数值定义 ⚠️ 最严重

**实测证据**：同一把手枪——

```
autoload/data_manager.gd:107   pistol  damage: 15, range: 6, ap_cost: 4   ← 物品表
scripts/items/weapon.gd:96     pistol  primary_action: 倍率1.0, range: 5  ← 武器表
```

装备后实际生效的是 `weapon.gd` 的 primary_action（`character.gd:_weapon_to_action` 按 item_id 查武器表），**物品表里的 damage/range/ap_cost 成了死数据**。后续策划调平衡时，改错表→"我明明调了手枪伤害怎么没生效"的 bug 一定会上演。

**根因**：物品数据表（DataManager）与武器动作资源（weapon.gd）是两套独立定义的静态数据，靠 `item_id` 字符串硬关联，无校验。

**修复方向**：确立**单一数据来源（Single Source of Truth）**：
- 方案 A（推荐）：所有数值定义收敛到 DataManager，`weapon.gd` 改为从 item_id 读取数据再构建动作资源，删掉 duplicate 的数值
- 方案 B：定义一条 `_validate_data_consistency()` 启动时自动比对两表，不一致直接 `push_error`
- 无论选哪个，**先加校验再重构**，让漂移第一时间暴露

### P0-2 两套护甲公式并存，防御数值行为不一致

**实测证据**：

```
scripts/combat/combat_calculator.gd:73   减伤 = minf(defense * 0.06, 0.75)      ← 攻击时
scripts/units/character.gd:558           实际伤害 = maxf(amount - defense * 0.5, 1.0)  ← 受伤时
```

同一个 `defense` 值，攻击方计算和受击方结算走**完全不同**的公式。当 `defense=10` 时：攻击公式减伤 60%，受击公式减伤 5 点（对 20 伤害就是 25%）——数值语义完全分裂。未来 NPC/敌人/装备全接入后，这个矛盾会直接毁掉平衡性。

**修复方向**：伤害结算统一走 `CombatCalculator`（它是纯静态类，天然适合单测）。`take_damage` 不应自行算减伤，只接收已算好的最终伤害。

### P0-3 单例耦合：基类直接依赖 7 个全局单例

**实测证据**：`character.gd`（所有单位的基类）直接调用 `TurnManager`、`InventoryBackpack`、`DataManager`、`SoundManager`。`player.gd` 又加 `GameManager`、`WorldTime`、`PartyManager`。

**后果**：
- 任何需要 Character 的测试场景（GUT 单元测试、demo 场景、未来 NPC）都必须先挂全部 7 个 Autoload，否则 `if SoundManager:` 这类守卫开始散布
- 单例是"隐式全局变量"，依赖关系完全不透明，新人读代码无法从签名判断依赖

**修复方向（渐进式，不用推翻重来）**：
- 第一步：**依赖注入**——基类增加 `var world: Node`（已存在）、`var inventory: Node`（待加）等可注入引用，默认回退到 Autoload
- 第二步：`SoundManager` 这种"表现层"依赖从基类下沉到子类或信号处理，基类不该知道"脚步声"这种细节
- 第三步：核心逻辑（回合、背包、战斗计算）逐步抽成**纯逻辑类**（不依赖场景树），可独立单测——`CombatCalculator` 已经是好榜样，`TurnManager` 的 AP 调度逻辑也完全可以抽出来

---

## 三、P1 级问题（质量级，建议纳入迭代节奏）

### P1-1 鸭子类型访问泛滥，类型安全缺失

`unit.get("ap_current")` / `unit.set("ap_current", x)` 在 turn_manager.gd、game_scene_base.gd、character.gd 中反复出现（仅 turn_manager 就有 10+ 处）。`Node.get("prop")` 是运行期反射，**属性改名不报编译错，运行期才炸**，且团队已在踩坑表里记录过 `Node.get` 的参数限制问题——这说明已经踩过坑，但模式仍在使用。

**建议**：TurnManager 面向的类型其实只有两种形态（玩家/敌人），定义一个 `UnitStats` 接口或让 `Character` 提供类型化 getter（`get_ap() -> int`），TurnManager 里全量替换掉 `.get()`。

### P1-2 注释声称的规范与实现不符

`turn_manager.gd:13` 注释：*"player_acted 是 AP 扣除的唯一入口，调用方不应再手动扣 AP"*——但 `spend_player_ap_only` 同样在扣 AP，`_end_turn` 里又直接 `set("ap_current", 0)`。**注释与实现背离比没有注释更危险**，新人会拿注释当契约写代码。

**建议**：要么统一到单一入口，要么更新注释。这类"注释-实现"契约审计应该进 code review checklist。

### P1-3 私有方法越权调用

`game_scene_base.gd:265` 调用 `_player._move_in_direction(dir)`——带下划线前缀的私有方法被外部类直接调用。GDScript 的私有前缀是约定不是语法，但团队内部要立规：**下划线方法不得跨类调用**，需要跨类时提升为公开方法或走信号。

### P1-4 死亡流程分叉

`character.gd:die()` 会 `unregister_unit + queue_free`；`player.gd:die()` 覆写后**不调 super**，只 `unregister + game_over`。未来玩家死亡场景（尸体、掉落、复活）出现时，两条路径行为会继续分叉。建议 `Player.die()` 在收尾前调用 `super.die()` 或至少显式注释为何不调。

### P1-5 魔法字符串散落

- 动作名 `"move"/"attack"/"use_item"` 在 character.gd、game_scene_base.gd、turn_manager.gd 中手写
- 物品 id `"bandage"` 硬编码在 `game_scene_base.gd:296` 和 `character.gd` 的 `use_item_on_self("bandage")`
- 建议：动作名收敛为枚举或常量表；物品 id 至少加 `const ITEM_BANDAGE := "bandage"` 类常量

---

## 四、P2 级问题（工程化，随迭代改进）

| 问题 | 现状 | 建议 |
|------|------|------|
| 日志无分级 | 全部 `print()`，正式版刷屏 | 封装 `Log.info/debug/warn/error`，保留 warn/error 即够调试 |
| 无单元测试 | 只有 headless 冒烟测试 | `CombatCalculator`（纯静态）、AP 调度是**完美的 GUT 单测对象**，先补这两个 |
| 魔法数字 | 180 帧超时、血量 200、伤害 22 散落 | 数值配置收敛到 DataManager 或 Config 常量类 |
| 方法职责重叠 | `player.gd` 同时有 `get_combat_stats()` 和 `get_stats()` | 明确区分：战斗计算用 / UI 展示用，或合并 |
| 命名不一致 | 文件名 `player.gd` 与注释类名 `PlayerUnit` 不符 | 统一：`class_name` 与文件名对齐 |

---

## 五、团队技术提升方案（分阶段执行）

> 目标：把"个人能力"沉淀为"团队能力"。核心抓手就三个——**规范、评审、测试**。

### Phase A：立规矩（第 1-2 周）——建立《团队编码规范》

建议立即落地一份 `docs/CODING_STANDARDS.md`，内容最小集：

1. **GDScript 规范**
   - 类型化优先：`var units: Array[Node]`，禁止裸 `Array`/`Dictionary` 当签名
   - 禁止跨类调用 `_` 私有方法
   - `class_name` 与文件名必须一致
   - 每个文件头部保留现有职责注释模板（团队做得很好，规范化为模板）
2. **数据规范（治 P0-1）**
   - 数值定义只允许出现在 DataManager，动作资源一律由数据构建
   - 新增物品必须走 `_add_item`，禁止旁路静态定义
3. **契约规范（治 P1-2）**
   - 公共方法写清楚"谁调用、何时调用、副作用是什么"
   - 注释与实现不一致 = 必须当场修复的缺陷

**落地方式**：找半天开一次"代码规范工作坊"，把本报告 P0/P1 作为案例逐条讲，让团队自己把规范写出来（参与感决定执行力）。

### Phase B：架构治理（第 3-4 周）——专治 P0

按依赖安全程度排序，每项独立小任务、可回滚：

1. **先加校验**：`_validate_data_consistency()` 比对双数据源（半天工作量，立刻止血）
2. **护甲公式统一**：`take_damage` 改走 CombatCalculator（小改动，立刻止血）
3. **TurnManager 类型化**：删 `.get("ap_current")` 一类鸭子访问（中等，逐文件替换）
4. **依赖注入化**：character.gd 的 Autoload 引用改为可注入（渐进，不动现有调用）

每完成一项，更新 PROJECT_STATUS.md 的踩坑表——把"修了什么、为什么、以后怎么避免"写进去，这就是团队的活教材。

### Phase C：质量闭环（第 5-8 周）——测试 + 评审流程

1. **引入 GUT 单元测试框架**
   - 第一批测试对象（收益最高）：`CombatCalculator`（伤害/暴击/护甲/状态）、`TurnManager` AP 调度（回合推进/并行行动/巡逻节奏）、`InventoryBackpack`（负重/格子/序列化）
   - 目标：核心逻辑覆盖率 ≥ 70%
   - 跑法：`godot --headless -s addons/gut/gut_cmdln.gd` 并入现有回归脚本
2. **建立代码评审流程**
   - 规则：**任何功能分支合入前必须过一次评审**，哪怕只有两个人互审
   - 评审 checklist 第一版（贴进 PR 模板）：
     - [ ] 是否有重复数值定义（双数据源检查）
     - [ ] 是否有跨类调用私有方法
     - [ ] 是否有裸 `print`（应走 Log）
     - [ ] 是否有新魔法字符串/数字
     - [ ] 类型化了吗（Array/Dictionary 裸用）
     - [ ] 注释与实现一致吗
     - [ ] 改动是否影响了单测（GUT 全绿？）
3. **回归自动化**：把现有 headless 命令固化成 `tools/run_tests.sh`（或 Makefile），新人一键跑

### Phase D：能力建设（持续）——把经验变成资产

1. **每周 1 小时技术分享**（轮值制）：本周踩坑 → 本周解决 → 沉淀到踩坑表
2. **结对编程试点**：NPC 系统（下一个大模块）安排 1 老带 1 新，老将负责架构、新人负责实现，正好验证 Character 继承树是否经得起扩展
3. **代码走查日**：每月一次全员走查核心文件（从本报告 P0 文件开始），谁发现的问题最多谁下月讲分享
4. **文档即知识库**：PROJECT_STATUS.md 已经很好，建议拆出 `docs/ARCHITECTURE.md`（系统架构图 + 依赖关系 + 数据流），新人入职第一课

---

## 六、优先级速查表

| 优先级 | 事项 | 工作量 | 收益 |
|--------|------|--------|------|
| 🔴 立即 | 双数据源一致性校验（P0-1） | 0.5 天 | 止血，防漂移 |
| 🔴 立即 | 护甲公式统一（P0-2） | 0.5 天 | 数值语义正确 |
| 🟠 2 周内 | 编码规范文档 + 工作坊（Phase A） | 1 天 | 团队共识 |
| 🟠 2 周内 | TurnManager 类型化（P1-1） | 2-3 天 | 消灭运行期炸弹 |
| 🟡 3-4 周 | GUT 单测第一批（Phase C） | 3-5 天 | 回归保护 |
| 🟡 持续 | 评审流程 + 分享机制（Phase C/D） | 制度化 | 长期复利 |

---

## 七、给团队的寄语

这个项目最大的资产不是代码量，而是**已经把架构演进做成了习惯**（场景基类重构就是最好的证明）。现在最需要的不是更多功能，而是**把质量关制度化**——当"谁都能改、改了要能验证"成为默认状态，团队就真正上了一个台阶。

有任何一项想深入（比如先做双数据源校验，或设计 GUT 测试骨架），随时叫我，我可以直接落代码。
