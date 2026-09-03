# ZoneBox 实时分隔杆（Runtime Divider）技术设计

| 字段 | 值 |
| --- | --- |
| **标题** | 已贴靠窗口之间的可拖动分隔杆 |
| **状态** | 已实现（v1） |
| **日期** | 2026-09-01 |
| **作用范围** | 运行时（桌面上已贴靠的真实窗口），非布局编辑器 |

---

## 1. 背景与问题

当前 ZoneBox 已支持把窗口贴靠进布局区域（zone）。但贴靠完成后，如果用户想调整比例——例如两分屏想"左小右大"、三分屏想拉宽中间一列——只能：

1. 打开布局编辑器拖网格线（`LayoutEditorCanvasView` 的 `.gridLine` 拖动 → `GridEditing.moveLine`），保存后**再把每个窗口重新贴一遍**；或
2. 手动拖窗口边缘，靠磁吸（`MagneticResize`）对齐到 zone 边，但**相邻窗口不会跟随**，需要每个窗口各拖一次。

用户期望的交互是 macOS 原生 Split View / PowerToys FancyZones 的"分隔杆"体验：**抓住两个（或三个）紧贴窗口之间的缝，一次拖动，所有相邻窗口同步缩放，始终紧贴、始终铺满整个工作区**。

## 2. 目标 / 非目标

### 目标（v1）

1. 当某显示器的当前布局是 **grid 布局**，且分隔线两侧的 zone 都各有**恰好一个**已贴靠、且仍在位的窗口时，在缝的中点显示一个可拖动的把手（胶囊 + 双箭头，风格对齐编辑器里的 `ResizeGlyph.drawSystemDivider`）。
2. 拖动把手 = 移动该条网格线：两侧（含跨越该线的所有行/列上的）窗口实时同步改帧，外边缘不动，整体仍铺满工作区，gutter 间隙保持。
3. 松手后把新比例**持久化回该布局**（下次贴靠、Preview Zones、编辑器打开时看到的都是新比例）。
4. 覆盖用户列举的场景：两列（Columns 2）、三列（Columns 3）、以及 Priority 类"左一大 + 右上/右下"布局（竖缝拖动同时联动 3 个窗口）。
5. 不破坏既有交互：普通拖拽贴靠、Shift-drag、QuickSnapper、磁吸缩放、编辑器全部行为不变。

### 非目标（v1 明确不做）

- Canvas 布局的分隔杆（canvas 相邻关系是隐式的，缝可能重叠/错位；见 §11 未来扩展）。
- 一个 zone 里叠了多个窗口时的联动（v1 直接不显示把手）。
- 拖窗口边缘时"推挤"邻居（FancyZones 式 push-resize，是另一条交互路线，见 §4 方案 A）。
- 键盘调整分隔线。

## 3. 现状盘点（可复用的既有能力）

| 能力 | 位置 | 说明 |
| --- | --- | --- |
| 网格线移动（纯函数） | `ZoneBox/Geometry/GridEditing.swift` → `moveLine(_:axis:afterIndex:toNormalized:)` | 在相邻两列/行之间重分配权重，`minWeight = 80`（0.8%）下限，权重总和恒为 10 000，`validated` 保证 tiling 不破。**分隔杆的核心几何直接复用它，零新增几何代码。** |
| 布局 → 像素帧 | `resolveLayout` / `GridResolver.resolve` + `Gutter.apply` | 输入 workAreaAX + gutter，输出每个 zone 的 `frameAX`。拖动过程中每帧调用即可得到所有目标窗口帧。 |
| 窗口 ↔ zone 归属 | `Services/WindowCatalog.swift` → `membership: [WindowIdentity: (zoneID, displayID, snappedAt)]` | 每次成功贴靠都会 `record(_:displayID:)` 写入。这是"缝两侧是否有贴靠窗口"的数据源。 |
| 快速读窗口当前帧 | `CGWindowQuery.frameAX(ofWindow:)` | ~0.2 ms/窗口，可用于校验"窗口仍在 zone 上"。 |
| 写窗口帧 | `AccessibilityClientLive.setFrame` → `AXFrameMutator.setFrame` | 已处理 AXEnhancedUserInterface、min/max size、3 次重试。 |
| 透明覆盖面板样板 | `UI/Overlay/OverlayPanel.swift` | borderless、`draggingWindow+1` 层级、全 Space。分隔杆面板复制此配置，仅把 `ignoresMouseEvents` 改为 `false` 并用 `hitTest` 限定命中区域。 |
| 把手绘制样板 | `LayoutEditorCanvasView` 内 `ResizeGlyph.drawSystemDivider` | 白色胶囊 + 两枚黑色三角 tick，直接照搬视觉。 |
| 显示器变化 rebuild | `AppRuntime.observeSystem` 里 `didChangeScreenParametersNotification` → `overlay.rebuild` | 分隔杆面板在同一处一起 rebuild。 |

**结论：几何层不需要新算法，工作量集中在"运行时服务 + 覆盖面板 + 与现有事件链路的互斥"。**

## 4. 方案选型

| 方案 | 描述 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- | --- |
| **A. 磁吸推挤（push-resize）** | 用户拖某个窗口的边缘，检测到该边贴在 zone 缝上时，松手后把邻居窗口也改帧（挂在 `SnapSessionReducer` 的 `.resizing` 分支 / `MagneticResize` 之后） | 无新 UI；入口自然 | 只能在 mouse-up 后联动（拖动中我们收不到逐帧的可靠 resize 事件，`DragMonitor` 是采样式的）；"哪条缝、哪些邻居"要从像素反推，歧义多；不改布局本身，下次贴靠又回旧比例 | 否决（可作 v2 补充） |
| **B. 缝上把手 + 覆盖面板（本设计）** | 常驻的每显示器透明 `NSPanel`，只在缝中点开一个小命中区，拖动即移动网格线并同步窗口 | 交互明确（用户原话就是"中间的杆"）；几何走 `GridEditing.moveLine`，天然保证铺满/最小宽度；顺手把新比例写回布局 | 需要新面板 + 与 `DragMonitor` 的互斥；把手常驻需要控制视觉干扰 | **采用** |
| **C. 仅编辑器** | 引导用户去编辑器拖线 | 零成本 | 不满足需求（改完还要重新贴窗口） | 否决 |

## 5. 总体架构

新增一个运行时服务 `DividerController`（`ZoneBox/Services/DividerController.swift`，app target，不进 Core），生命周期与 `OverlayController` 平行：

```
AppRuntime
 ├─ overlay:  OverlayController      （已有，贴靠高亮）
 ├─ divider:  DividerController      （新增）
 │    ├─ panels: [DisplayID: [DividerPanel]]        每个把手一个小尺寸透明面板
 │    ├─ views:  [DisplayID: [DividerOverlayView]]  绘制把手 + 接收鼠标
 │    ├─ 可见性刷新（定时 + 事件触发）
 │    └─ 拖动状态机（见 §6.3）
 ├─ catalog: WindowCatalog           （扩展两个查询/更新方法，见 §6.6）
 └─ drag:    DragMonitor             （加一条互斥判断，见 §6.5）
```

纯逻辑部分（把手推导，见 §6.1）抽成 Core 内的纯函数 `Domain/DividerPlan.swift`，便于无 AppKit 单测。

## 6. 详细设计

### 6.1 把手推导（DividerPlan，纯函数，可单测）

输入：`layout: Layout`（grid）、`resolvedFrames: [UUID: CGRect]`（含 gutter 的 zone 帧）、`snapped: [zoneID: [WindowIdentity]]`（该显示器上"仍在位"的贴靠窗口，见 6.2）。

对 `spec.columns - 1` 条竖线、`spec.rows - 1` 条横线逐一判定：

```swift
public struct DividerHandleSpec: Equatable, Sendable {
    public var axis: GridAxis          // 复用 GridEditing 的 GridAxis
    public var afterIndex: Int         // 与 GridEditing.moveLine 的参数一致
    public var lineAX: CGFloat         // 缝的 AX 坐标（由权重前缀和算出）
    public var spanAX: ClosedRange<CGFloat>  // 缝上有真实相邻关系的区段
    public var slots: [(zoneID: UUID, identity: WindowIdentity)]  // 受影响窗口
}
```

判定规则（以竖线 `afterIndex` 为例）：

1. 遍历每一行 `r`：`left = cellMap[r][afterIndex]`，`right = cellMap[r][afterIndex + 1]`。`left == right`（合并 zone 横跨该线）的行跳过；该行贡献 `zoneIndices += {left, right}`，并用两侧 resolved 帧的纵向重叠累计 `spanAX`。
2. 若 `zoneIndices` 为空（整条线都被合并 zone 覆盖）→ 无把手。
3. **每个受影响 zone 必须恰好有 1 个在位窗口**，否则该缝不出把手（v1 的保守策略；多窗口/空 zone 都视为"不可联动"）。
4. 缝位置：`lineAX = workAreaAX.minX + workAreaAX.width * prefix(columnWeights)[afterIndex + 1]`。把手中心取 `(lineAX, mid(spanAX))`。

Priority 3（`cellMap = [[0,1],[0,2]]`）验证：
- 竖线 0：两行都是 `0 vs 1`、`0 vs 2` → slots = {zone0, zone1, zone2}，拖动 = 三窗联动，左列外边缘不动 ✓。
- 横线 0：第 0 列 `0 vs 0` 跳过，第 1 列 `1 vs 2` → slots = {zone1, zone2}，span 只覆盖右半屏 → 把手画在右半屏中间，拖动只改右侧两窗高度 ✓（`moveLine` 改的是整行权重，但左列是合并 zone，帧不变）。

### 6.2 "窗口仍在位"校验

`WindowCatalog.membership` 只记录"上次贴到了哪"，窗口可能已被用户拖走/缩放/关闭。把手刷新时逐条校验：

```
actual = CGWindowQuery.frameAX(ofWindow: identity.windowNumber)   // nil ⇒ 已关/最小化/别的 Space
inPlace = WindowOrganize.didApply(actual, to: resolvedFrames[zoneID],
                                  sizeTolerance: 28, originTolerance: 28)
```

- 复用 `WindowOrganize.didApply` 的容差比较；28pt 容差吸收 AX/CG 阴影与标题栏差异。
- 校验失败 ⇒ 该窗口不算在位 ⇒ 对应缝不出把手。窗口挪回去后下一轮刷新自动恢复。

### 6.3 拖动状态机

```
idle ──mouseDown(把手命中)──▶ resolving ──AX 窗口解析完成──▶ dragging ──mouseUp──▶ committing ──▶ idle
  ▲                                │ 任一窗口解析失败/消失                                │
  └────────────── cancel ◀─────────┴──────────────── escape / 显示器变化 / 编辑器打开 ────┘
```

- **resolving**：`mouseDown` 时异步 `ax.window(matching:)` 解析所有 slot 的 `AXWindow`（Priority 布局最多 3 个）。解析期间已可以接收 drag 点位，先缓存。
- **dragging**：每次鼠标移动
  1. 把 `NSEvent.mouseLocation` 转 AX（`CoordinateConverter.axPoint`），再归一化成 `t = (x - workAreaAX.minX) / width`；
  2. `next = GridEditing.moveLine(baseLayout, axis:, afterIndex:, toNormalized: t)`（clamp、minWeight、权重归一全部由它兜底；返回 nil 时保持上一帧）；
  3. `resolveLayout(next, workAreaAX:, gutter:)` 取 slots 对应的目标帧；
  4. 经**串行写入队列**下发 `ax.setFrame`（见 §6.4）。
- **committing**（mouse-up）：
  1. 等最后一批 `setFrame` 落地；
  2. 若 `finalLayout.grid != baseLayout.grid`：`document.upsertAndAssign(finalLayout, displayID)` + `markLayoutUsed` + `persist()`（会自动 `invalidateResolvedLayoutCache`）+ `menuBar?.reloadMenu()`；
  3. 用 `catalog.updateSnappedFrame`（见 §6.6）把每个 slot 的 `snappedFrameAX` 刷成实际落点，保证后续 unsnap/`snapAdjacent` 语义正确；
  4. 回到 idle，重算把手位置。
- **cancel**：不回滚窗口帧（拖到一半取消就停在当前位置，布局不持久化），只清状态。回滚需要再写一轮 AX 帧，收益低、闪动明显。

### 6.4 窗口帧写入：coalescing 串行队列

`AXFrameMutator.setFrame` 每窗最坏 ~50ms（3 次重试 × 16ms sleep）。拖动事件频率远高于此，策略：

- 单一 in-flight `Task`：写入期间新的拖动点只更新 `latestLayout`；任务完成后若 `latestLayout` 变了就立刻开下一轮（**只追最新，不排队**）。
- 一轮内按 slot 顺序串行写（AX 队列本身是串行 `com.fancyzone.ax`，并发无收益）。
- 视觉上等价于"跟手但限速"，与系统 Split View 的分隔杆手感一致（Split View 也不是逐像素跟随）。

### 6.5 与现有子系统的互斥（关键正确性点）

| 冲突点 | 现状 | 处理 |
| --- | --- | --- |
| `DragMonitor.beginHold` 会把把手下方的**别人家窗口**捕获成贴靠会话（`CGWindowQuery.topmostWindow` 排除自家 PID，命中不到我们的面板） | 已有先例：`pinHover.consumesPoint(mouse.locationAppKit)` 直接短路 | 在 `beginHold` 的 guard 链加 `!runtime.divider.consumesPoint(...)`；`consumesPoint` = 拖动进行中恒 true，否则命中任一把手 hitRect 为 true |
| 贴靠会话进行中（overlay armed / QuickSnapper 显示） | — | `engine.isSessionActive == true` 时隐藏所有把手面板，避免和贴靠高亮叠加 |
| 编辑器打开 | `isEditorOpen` | 隐藏把手；编辑器保存后布局变化会走刷新自然恢复 |
| 显示器插拔/分辨率变化 | `didChangeScreenParametersNotification` → `overlay.rebuild` | 同一处调用 `divider.rebuild(workAreas:screens:)`，拖动中则先 cancel |
| 贴靠/取消贴靠改变 membership | `catalog.record/drop` | 不加回调，靠低频轮询刷新（§6.7），简单且够用 |
| 锁屏/休眠 | `hideAllOverlays()` | 一并隐藏把手 |

### 6.6 WindowCatalog 扩展（两个方法）

```swift
// 某显示器上全部贴靠归属，供把手推导使用
func snappedMemberships(on displayID: UUID) -> [(identity: WindowIdentity, zoneID: UUID)]

// 分隔杆改帧后同步记录：保留 originalFrameAX（unsnap 仍回最初位置），
// 仅更新 snappedFrameAX / zoneIDs；membership 的 snappedAt 不变（不扰动同 zone 轮换顺序）
func updateSnappedFrame(_ frame: CGRect, for identity: WindowIdentity,
                        zoneID: UUID, displayID: UUID)
```

### 6.7 把手可见性刷新

- 定时器 30Hz 太奢侈也没必要；**2Hz 轮询 + 事件触发**（贴靠完成、布局切换、`persist()` 后、显示器变化）即可。轮询做的事：membership 过滤 + 每窗口一次 `frameAX(ofWindow:)`（0.2ms 级）+ 把手重算，代价可忽略。
- 无把手时面板 `orderOut`，完全零开销。
- 可选打磨（v1.1）：把手默认半透明，鼠标移入 hitRect 时高亮放大（`NSTrackingArea`）。

### 6.8 面板与视图

- `DividerPanel`：复制 `OverlayPanel` 的浮层配置，但窗口本身只占一个把手的 hitRect（竖缝 36×48、横缝 48×36），每个显示器按当前把手数维护一个小面板池。层级 `draggingWindow + 1` 保证盖在普通窗口之上、低于贴靠 overlay 的 key sink。
- `DividerOverlayView.hitTest` 仅处理自己对应的把手；把手区域外根本没有 ZoneBox 窗口，鼠标在窗口层直接命中下方应用，**不影响任何日常点击**。
- 绘制：8×36 白色胶囊 + 左右（或上下）两组黑色 tick，视觉与编辑器 `ResizeGlyph.drawSystemDivider` 一致。
- 光标：hover 时 `resizeLeftRight` / `resizeUpDown`。

## 7. 边界情况

| 场景 | 行为 |
| --- | --- |
| 窗口有 AXMinSize，缝拖过头 | `AXFrameMutator` 已 clamp 到 minSize；窗口实际帧与目标不符时 `updateSnappedFrame` 记录实际值；下一轮把手刷新用 28pt 容差判断，若彻底脱离 zone 则把手消失。`GridEditing.minWeight`（0.8%）另兜一层布局下限 |
| 拖动中窗口被外力关闭 | `setFrame` 返回 nil → 该 slot 跳过；mouse-up 照常提交布局；下一轮刷新把手消失 |
| 同一 zone 两个窗口（轮换栈） | 不显示把手（v1）；未来可取 `snappedAt` 最新者 |
| gutter > 0 | 缝位置按无 gutter 的权重线计算，把手正好落在两窗中间的缝隙里；resolve 时 gutter 自动保持 |
| 双显示器 | 每显示器独立面板、独立布局、互不影响；拖动锁定在起始显示器 |
| 布局在拖动中被别处修改（菜单切布局） | commit 时以 `baseLayout` 为基（拖动开始那份）做 `moveLine`，`upsertAndAssign` 覆盖写入；竞态窗口极小，接受"后写赢" |

## 8. 性能预算

- 静息：无贴靠窗口 ⇒ 面板 orderOut，仅 2Hz 空轮询（一次字典过滤）。
- 有把手静息：2Hz × N 窗口 × 0.2ms `frameAX` ≈ 可忽略。
- 拖动中：`moveLine` + `resolveLayout` 均为微秒级纯计算；瓶颈是 AX `setFrame`（每窗 16–50ms），coalescing 队列保证不堆积。

## 9. 测试方案

Core（无 AppKit，进 `ZoneBoxTests`）：

1. **`DividerPlanTests`**（新）：
   - Columns 2/3：每条内缝各产出一个把手；lineAX 与权重前缀和一致。
   - Priority 3：竖缝 slots=3、span 全高；横缝 slots=2、span 只覆盖右列。
   - 合并 zone 完全覆盖某缝 ⇒ 无把手；某 zone 0 个或 2 个窗口 ⇒ 无把手。
2. **`GridEditingTests`** 补充：`moveLine` 在 Columns 3 上移动第 0 条线不影响第 2 列宽度（现有已覆盖 2 列，补 3 列断言）。
3. **`WindowCatalogTests`**（新或并入现有）：`updateSnappedFrame` 保留 `originalFrameAX`、更新 `snappedFrameAX`、不改 `snappedAt`；`snappedMemberships(on:)` 只返回目标显示器。

手工验收清单：

- 两列布局左右各贴一窗 → 把手出现 → 拖动左小右大、始终无缝铺满 → 松手 → Preview Zones 显示新比例 → 重贴窗口落在新比例。
- Priority 3 三窗联动竖缝、右侧两窗联动横缝。
- 把手区域外点击/拖动窗口，贴靠行为与现在完全一致；把手上按下拖动**不**触发贴靠 overlay。
- 拖走其中一个窗口 → 把手 1 秒内消失；拖回 zone → 恢复。
- 断开外接屏拖动中 → 无崩溃，状态清空。

## 10. 实施拆分（建议 3 个 PR）

1. **PR-1 Core**：`Domain/DividerPlan.swift`（把手推导纯函数）+ `WindowCatalog` 两个方法 + 全部单测。无 UI 风险。
2. **PR-2 服务**：`Services/DividerController.swift`（面板/视图/状态机/coalescing 队列）+ `AppRuntime` 接线（start/stop/rebuild/persist 后 refresh）+ `DragMonitor.consumesPoint` 互斥。
3. **PR-3 打磨**：hover 高亮、光标、`isSessionActive`/编辑器互斥细化、锁屏隐藏、README/设计文档更新。

## 11. 未来扩展

- **Canvas 布局**：复用编辑器的 `allSharedSeams` 邻接判定 + `ZoneSplit.movingVerticalSeam/movingHorizontalSeam`，把"缝"抽象成 `enum DividerTarget { case gridLine(...), case canvasSeam(...) }`；难点是 canvas 缝只影响两个 zone、不保证铺满。
- **多窗口 zone**：对 zone 内全部在位窗口同帧写入。
- **push-resize（方案 A）补充**：磁吸松手后检测"贴到缝上"并把邻居对齐，作为不点把手时的快捷路径。
- **键盘微调**：把手获得焦点后方向键 ±1% 权重。
