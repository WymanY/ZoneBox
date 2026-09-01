# ZoneBox 拖拽中布局选择效率优化 — 设计方案

- 日期：2026-09-01
- 状态：已在 `layout-picker` 分支实现（PR-1 → PR-3 同批落地）
- 关联文档：`docs/design.md`（整体架构与 reducer-only 测试原则）

## 0. 问题与结论

**问题**：晃动 / Shift 拖拽 arm 后，overlay 只能显示当前显示器"已指派布局"的 zones（菜单栏面板里点选的那一个）。想用别的布局必须：松手 → 开面板 → 点卡片 → 重新拖拽，流程完全断裂。

**结论**：把"先选布局、再选格子"压成"直接选格子，布局跟着格子走"。

- **主路径**：光标处跨布局候选轮换——armed 时滚轮/Tab 在光标点命中的所有布局 zone 间轮换，松手贴入。
- **辅路径**：顶部布局缩略条——把窗口直接拖到缩略卡内的 mini 格上松手，一步完成"换布局 + 落位"（Windows 11 Snap Layouts flyout 式）。
- **持久化**：snap 成功才把该布局指派给当前屏；Esc / 未 snap 不改任何设置。
- **排序**：候选与缩略卡均按 MRU（最近使用优先）。

## 1. 现状（代码事实）

- 数据模型是「一屏一布局」：`StoreDocument.assignments` 把每个显示器指到一个 `layoutID`，`document.layout(for: displayID)` 只返回这一个布局（`Domain/DisplayIdentity.swift`）。
- 菜单栏面板点选布局卡 = `runtime.selectLayout()` → 改 assignment 并持久化（`App/AppRuntime.swift`）。
- 晃动/Shift arm 后，`SnapEngine` 每个鼠标事件都用 `resolvedZones(for: 光标所在屏)` 取**当前指派布局**的 zones 渲染 overlay 并做命中测试。会话内没有任何切换布局的入口。
- 对设计有利的事实：
  - `OverlayController.show` 在 zones 变化时自动重绘，拖拽中途换布局、实时刷新在渲染层天然支持；
  - 数字键 1–9 在 armed 时已被 `HotkeyCenter` 的 key monitor 截走用于选 zone（`handleOverlayDigit`），「拖拽中截键盘」已有先例与权衡。

## 2. 设计约束

1. 晃动是**纯鼠标单手手势**，方案不能强制依赖键盘。
2. 不与现有会话内语义冲突：数字 1–9 = 选 zone，Ctrl = grid 跨格 span，Shift = arm，Esc = 取消。
3. 兼容「reducer 纯函数 + 单元测试只测 reducer」的架构。
4. 不操作时行为必须与现状 100% 一致（零学习成本兜底）。

## 3. 方案对比（已评审）

| 方案 | 交互 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| A. 会话内轮换 | armed 时滚轮/Tab 在布局间轮换 | 改动小；单手 | 布局多时不能直达 | 演化为主路径（轮换对象从"布局"改为"光标处候选 zone"） |
| B. 顶部缩略条 | armed 显示缩略卡，悬停切布局 | 直达；可发现性最好 | 仍是两步：切完还要拖回 zone | 升级为"直落 mini-zone"一步完成，作辅路径 |
| C. Option+数字直达布局 | armed 时 Option+1..9 切第 N 布局 | 最快 | 记序号、双手、可发现性差 | 暂不做，留作后续可选 |
| D. 二段式（armed 后再晃进"选布局模式"） | — | — | 模式套模式、shake 噪声易误触 | 否决 |
| E. 多布局 zones 叠加显示 | 面板勾选多布局同时显示 | — | 视觉混乱、编号/重叠策略冲突 | 否决 |

**核心洞察**：用户的真实意图从来不是"换布局"，而是"把这个窗口放进某个形状的格子"。布局只是格子的容器，应当从流程中隐身。

## 4. 交互规格

### 4.1 主路径：光标处跨布局候选轮换（"格子跟手"）

```
晃动/Shift arm → (可选: 滚轮/Tab 轮换候选) → 松手贴入 → 该布局被指派给当前屏
```

- **候选集**：armed 期间，对光标点命中**所有已存布局**解析出的 zones，收集包含该点的矩形，按 frame 去重（0.5pt 容差），排序：当前指派布局的命中 zone 永远排第 1（默认高亮，保证不操作时行为与现状一致），其余按 MRU → 面积升序。
- **轮换**：滚轮上/下 或 Tab / Shift+Tab 在候选间循环（如拖到左半屏：左 1/2 → 左 1/3 → 左 2/3，分别来自三个布局）。
- **渲染**：底层照旧画"当前高亮候选所属布局"的全部 zones（淡色），其余候选画同心细轮廓；高亮矩形角上带小标签：`布局名 · 2/4`。
- **松手**：贴入高亮候选；若其所属布局 ≠ 当前指派 → `document.assign` + persist + 刷新 MRU。Esc / 未 snap 松手 → 不改任何指派。
- 顺带收益：Canvas 布局内部重叠 zone 原本只能按 `smallestArea` 硬裁决，现在重叠时也能滚轮挑。

### 4.2 辅路径：顶部缩略条直落 mini-zone（Win11 flyout 式）

- armed 即在**光标所在屏**顶部中央显示一排布局缩略卡（MRU 排序，当前指派布局第 1 且带选中描边），每张卡内绘制该布局的 mini zones。
- 拖拽点进入某张卡的某个 mini 格 → 该格高亮放大 10%；**松手 = 一步完成"换布局 + 贴入对应真实 zone + 指派"**。无 dwell、无二次拖拽。
- 拖拽点在条内但不在任何 mini 格上 → 高亮清空，此处松手 = 不贴（等同拖出所有 zone）。
- 条区域与真实 zone 重叠时，条优先（条在最上层）。
- 服务两个场景：想要的 zone 不在光标附近（浏览型选择）；可发现性载体（armed 就能看见所有布局）。

### 4.3 不变项（冲突守恒）

| 已有交互 | 保持 |
|---|---|
| 数字 1–9 | 仍选**当前高亮候选所属布局**的 zone（轮换后数字跟着新布局走，`lockedTarget` 在轮换时清除） |
| Ctrl 拖拽 grid span | 作用于当前高亮候选所属布局的 grid |
| Shift 松开 / Esc | 现有取消逻辑不变 |
| QuickSnapper | 一期不动；二期让 Tab 在 HUD 中同样轮换布局（复用同一 reducer 逻辑） |

## 5. 架构改动清单（按文件）

### 5.1 Core（ZoneBoxCore，纯逻辑，可测）

**`Domain/SnapMouseEvent.swift`** — `Kind` 增加：

```swift
case cycleCandidate(Int)   // +1 / -1，来自滚轮或 Tab/Shift+Tab
```

**新文件 `Domain/ZoneCandidates.swift`**：

```swift
public struct ZoneCandidate: Equatable, Sendable {
    public var layoutID: Layout.ID
    public var layoutName: String
    public var zone: ResolvedZone
}
public enum ZoneCandidateResolver {
    // 输入: 各布局在该 WorkArea 的解析结果 + 光标 AX 点 + 指派布局ID + MRU 序
    // 输出: 去重排序后的候选数组。纯函数，golden tests。
}
```

**`Domain/SnapSession.swift`** — `SnapReducerInput` 增加：

- `candidates: [ZoneCandidate]`（引擎按光标点算好传入，reducer 保持纯函数）
- `candidateIndex: Int`（当前会话选中的候选序号，由引擎持有，同 `lockedTarget` 模式）

`SnapEffect` 增加：

```swift
case assignLayout(Layout.ID)   // leftUp 成功贴入跨布局候选时发出
```

**`Domain/SnapSessionReducer.swift`**：

- `currentTarget(_:)`：改为取 `candidates[candidateIndex]`（无候选时回落现有 HitTester 路径）；
- `reduceCycleCandidate`：仅 `armed/highlighting` 响应，`idle/resizing/dragging` 忽略；轮换后发 `.highlight`、清 `lockedTarget`；
- `reduceLeftUp`：贴入的候选布局 ≠ 指派布局时，effects 追加 `.assignLayout(id)`；
- `reduceDigit`：`resolvedZones` 输入改为"高亮候选所属布局"的 zones（见引擎改动）。

**新文件 `Domain/LayoutStripGeometry.swift`**（纯几何，引擎命中测试与视图绘制共享同一套 frame）：

```swift
public struct LayoutStripGeometry {
    // 输入: workArea、布局列表(含 mini zone rects)、卡尺寸(约 128×80)、间距
    // 输出: 条 frame、每卡 frame、每卡内每 zone 的 frame（AppKit 坐标）
    public func hitZone(at point: CGPoint) -> (layoutID: Layout.ID, zoneNumber: Int)?
}
```

`SnapTarget` 不需要新 case：条命中直接换算成对应布局的真实 `ResolvedZone`，走 `.zone`。

**`Domain/DisplayIdentity.swift`** — `StoreDocument` 增加 `recentLayoutIDs: [Layout.ID]`。

> ⚠️ **数据安全红线**：必须手写 `init(from:)` 用 `decodeIfPresent`。`StoreDocument` 目前是合成 Codable，直接加字段会让旧 `store.json` 解码失败，而 `LayoutStore.load()` 把解码失败当损坏文件处理（改名 `.corrupt-*` 并**重置用户全部布局**）。此项先做、先测。

### 5.2 App 层

**`App/AppRuntime.swift`**：

- `resolvedZones(for:)` / `gridCoverage(for:)` 增加 `layoutOverride: Layout.ID?` 参数（默认 nil = 现行为）；
- 新增 `allResolvedLayouts(for area:) -> [(Layout, [ResolvedZone])]`，带 `(layoutID, displayID, gutter, workArea 尺寸)` 缓存，display 变更/布局编辑时失效；
- `markLayoutUsed(_ id:)`：更新 `recentLayoutIDs`（去重前插，截断到 20），`deleteLayout` 顺带清理。

**`Services/SnapEngine.swift`**：

- 会话状态加 `candidateIndex: Int`、`sessionLayoutID: Layout.ID?`（当前高亮候选布局）；`leftDown` 重置；
- 每次事件构造 input 前：先算 `candidates`（光标点 + 全布局缓存），`resolvedZones`/`gridCells` 用 `sessionLayoutID` 覆盖解析；
- 处理 `.assignLayout` effect：`document.assign` + `persist()` + `markLayoutUsed` + `menuBar?.reloadMenu()`；
- 新增 `handleCycleCandidate(_ delta: Int)`（仿 `handleOverlayDigit` 合成事件）；
- 条命中：drag 事件先查 `LayoutStripGeometry.hitZone`，命中则将该布局对应真实 zone 设为强制 target（同 `lockedTarget` 通道，离开条即解除）。

**`Services/DragMonitor.swift`**：监听 mask 加 `.scrollWheel`；仅 `engine.isOverlayArmed` 时把 `scrollingDeltaY` 聚合成 ±1 的 `cycleCandidate`（阈值 ~10pt 防触摸板抖动）。拖标题栏时光标必在被拖窗口上，滚轮不会滚到背景窗口，副作用可接受。

**`Services/HotkeyCenter.swift`**：`handleKeyEvent` 中 `isOverlayArmed` 分支增加 Tab（keyCode 48）：`engine.handleCycleCandidate(shift ? -1 : 1)`，本地 monitor 吞掉、全局不吞（与数字键同权衡）。

**`Services/OverlayController.swift` / `UI/Overlay/ZoneOverlayView`**：

- view 增加 `candidateOutlines: [CGRect]`、`candidateLabel: (text, anchor)`、`strip: StripRenderModel?`（卡 frame + mini zones + 高亮格），`show()` 按相等性判断刷新（沿用现有 diff 模式）；
- 条直接画在同一块 click-through overlay 上（不新建 panel，不需要真实鼠标事件）。

**其他**：

- `ShortcutPanelController` / `ShortcutCatalog` 加两条说明行（滚轮/Tab 轮换候选）；
- `Domain/L10n.swift` 补"拖拽中换布局"相关文案；
- `SettingsWindowController` 加开关「拖拽时显示布局条」（默认开；候选轮换无 UI 成本，不加开关）。

## 6. 数据流（armed 期间一次 drag 事件）

```
DragMonitor ─mouse/scroll─▶ SnapEngine
  ├─ stripGeometry.hitZone(光标)? ──命中──▶ 强制 target(该布局真实 zone)
  ├─ candidates = ZoneCandidateResolver(全布局缓存, 光标点, 指派ID, MRU)
  ├─ sessionLayoutID = candidates[candidateIndex].layoutID
  ├─ input.resolvedZones/gridCells ← 按 sessionLayoutID 解析
  ▼
SnapSessionReducer.reduce ──▶ effects
  .highlight / .applyFrame / .assignLayout / .recordUnsnap
  ▼
SnapEngine.apply ──▶ OverlayController(zones+outlines+label+strip) / AX setFrame / document.assign+persist
```

## 7. 边界与风险

| 风险 | 对策 |
|---|---|
| 旧 store.json 解码失败被当损坏重置 | `StoreDocument` 手写容错 decoder（红线，先做+先测） |
| 多屏跨屏拖拽 | 候选、条、`sessionLayoutID` 均随光标屏重算；`candidateIndex` 跨屏归零 |
| 布局重名/同形状 zone | 去重后标签显示布局名；完全同形状时只留 MRU 靠前者 |
| 全局 monitor 吞不掉 Tab/滚轮 | 与数字键同先例；拖拽中前台即被拖窗口，实害极小 |
| VoiceOver | Tab 无修饰键、滚轮无键盘，均不触碰 VO 的 Control+Option 政策 |
| 小屏/布局很多 | 条最多显示 6 卡 + "⋯"（溢出布局仍可滚轮轮换到）；候选集本身无上限问题 |
| 性能 | 全布局解析按 (layout, area, gutter) 缓存；每帧只剩矩形包含测试，<10 布局无压力 |

## 8. 测试计划（沿用 reducer-only 原则）

- `ZoneCandidateResolverTests`：去重、指派优先、MRU 次序、空候选回落。
- `SnapEngineTests` 新增：armed 时 cycle 换高亮并清 lockedTarget；idle/resizing 忽略 cycle；跨布局候选 leftUp 产生 `.assignLayout`+`.applyFrame`；同布局 leftUp 不产生 assign；Esc 不产生 assign；digit 作用于会话布局。
- `LayoutStripGeometryTests`：卡/格 frame golden、边缘命中、溢出截断。
- `StoreDocument` 解码兼容测试：旧 JSON（无 `recentLayoutIDs`）必须成功解码。

## 9. 分期交付

1. **PR-1 数据与主路径**：StoreDocument 容错 decoder + MRU、ZoneCandidateResolver、reducer cycle/assign、DragMonitor 滚轮、HotkeyCenter Tab、overlay 轮廓+标签。→ 交付后已可"不进菜单换布局"。
2. **PR-2 缩略条**：LayoutStripGeometry、overlay 条渲染、引擎条命中、设置开关。
3. **PR-3 打磨**：QuickSnapper 内 Tab 换布局、快捷键面板/onboarding 文案、动效（高亮矩形 12ms 内插值过渡）。

## 10. 已确认的决策记录

| 决策点 | 结论 |
|---|---|
| 主交互 | 光标处跨布局候选轮换（主）+ 缩略条 mini-zone 直落（辅），两个都要 |
| 持久化时机 | snap 成功才把布局指派给该屏；Esc/未 snap 不改 |
| 键盘轮换键 | Tab / Shift+Tab（滚轮同时可用） |
| 缩略条出现时机 | armed 即显示（可发现性优先） |
| 排序 | 候选与缩略卡均按 MRU |
