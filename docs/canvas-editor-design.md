# ZoneBox 画布模式编辑效率优化 — 技术实施方案

| 字段 | 值 |
| --- | --- |
| **标题** | 画布（Canvas）模式窗格的新建可发现性与编辑效率优化 |
| **状态** | 设计稿（未实现） |
| **日期** | 2026-09-01 |
| **作用范围** | 布局编辑器（`ZoneBox/UI/Editor/*`）+ 新增 Core 纯几何层，不涉及运行时贴靠 |
| **关联文档** | `docs/design.md`（架构与"纯函数进 Core、只测 reducer/几何"原则）、`docs/runtime-divider-design.md`（同类设计的写法基准） |

---

## 1. 背景与问题

用户反馈两件事：

1. **"在画布里单击新建这个东西，用户有些不一定能知道。"** —— 画布模式下"空白处单击 = 新建一个窗格"这条主要入口完全没有任何可视线索或文案。
2. **"画布模式创建、编辑、修改、复制窗格的效率很低。"** —— 尤其"复制"根本不存在。

以下是对应的代码事实（不是推测）：

### 1.1 可发现性缺口

| 现象 | 代码位置 |
| --- | --- |
| 空白处单击新建（位移 < 8pt 判定）只有行为、没有任何提示 | `LayoutEditorCanvasView.mouseUp` → `createDefaultZone(at:)` |
| canvas 模式空白处光标是 `NSCursor.arrow`（"这里不能操作"的暗示）；grid 模式反而是 `crosshair` | `applyCursor()`：canvas 分支 `guard let edge = visibleSplitHandle() else { NSCursor.arrow.set() }` |
| canvas 提示文案一个字都没提"新建"：`"拖边缘缩放。可输入像素或锁定长宽比。WASD 选格。⌘Z 撤销。Esc 退出。"`；grid 文案反而写了"点击竖切" | `L10n.editorHint` / `.editorGridHint` |
| 新建 canvas 布局时画布**完全空白**（0 个窗格），没有空状态引导；同时 `canCommit == false` 让保存按钮变灰，也没有解释为什么 | `LayoutTemplates.emptyCanvas` = `zones: []`；`LayoutEditTransaction.canCommit` |
| 没有右键菜单（`NSView.menu` 未实现），没有"新建窗格"按钮，工具栏只有 模式/模板/保存/另存/取消/删除 + 像素输入 | `LayoutEditorController.makeToolbar()` |
| 快捷键面板的 `.editor` 分区只列了 Esc / Tab / ⇧Tab / Delete / ⌘S / ⌘Z / 滚轮，没有任何"新建/复制窗格" | `ShortcutCatalog.specs`（`surface: .editor` 段） |
| canvas 的 hover 刷新不像 grid 那样排除工具栏区域（`isPointOverChrome` 只在 `refreshGridHover` 里用），鼠标划过悬浮工具栏时仍在算边缘命中 | `refreshHover(at:)` vs `refreshGridHover(at:)` |

### 1.2 效率缺口

| 能力 | 现状 |
| --- | --- |
| **复制窗格** | **完全没有**（无 ⌘D、无 ⌥ 拖拽克隆、无 ⌘C/⌘V）。要做 4 个等大窗格必须手画 4 次 |
| **吸附/对齐** | 创建、移动、缩放全程**无吸附、无参考线**。工作区边缘、兄弟窗格边、中线都不吸；运行时已有 `MagneticResize`，编辑器没用它。canvas 布局因此总留 1–2px 缝隙或重叠 |
| **切分窗格** | grid 有 `GridEditing.split`（点击竖切、Shift+点击横切），canvas **没有对应能力**，只能手画第二个窗格再对齐 |
| **键盘微调** | 方向键**未绑定**（`arrowDirection(for:)` 只映射 a/s/d/w 三个字母键 → 那是"选择邻居"）。没有 1pt/10pt nudge |
| **多选与批量** | `selectedID: UUID?` 单选。无 Shift/⌘ 加选、无框选，因此没有批量移动、对齐、分布、等宽等高 |
| **数值输入** | 只有 W/H 像素 + 长宽比，**没有 X/Y**，也没有"贴左/贴右/居中"命令 |
| **撤销** | 只有 undo（`LayoutEditTransaction.undoStack`），**没有 redo** |
| **编号** | `packedNumbers()` 强制按当前 `number` 排序重编，用户无法把某个窗格指定成 3 号（而运行时数字键 1–9 贴靠依赖编号，语义重要） |
| **重叠窗格** | 命中测试 `layout.zones.reversed()`（数组末位最上），绘制却按 `number` 排序 → z 序与画序不一致；重叠处只能选到最后添加的那个，无法轮换 |

**一句话诊断**：画布模式目前只有"一个一个手画 + 手对齐"这一条路径，缺少所有现代画布编辑器的标准加速器（吸附、复制、切分、微调、批量），并且这条唯一路径本身还是隐形的。

## 2. 目标 / 非目标

### 目标

1. 让"如何新建窗格"在**不看文档、不试错**的前提下三处可见：空状态引导、光标处幽灵预览、工具栏 + 右键菜单里的显式命令。
2. 把创建/编辑/修改/复制的核心操作从"手画 + 手对齐"降到**一次手势或一个快捷键**：吸附对齐、⌘D 复制、⌥ 拖拽克隆、二等分切分、方向键微调、多选批量对齐。
3. 所有几何决策落在 **Core 的纯函数**里（`ZoneBox/Geometry/*`），可单测，AppKit 层只做事件转发与绘制。
4. **零数据迁移**：不改 `Layout` / `Zone` / `GridSpec` / `store.json` 结构。
5. 不改变现有键位语义：WASD 选格、Tab 轮换、滚轮缩放、⌘S 另存、⌘Z 撤销、Enter 保存、Esc 取消、Delete 删除，行为全部保留。
6. grid 模式行为完全不变（本方案只新增 canvas 路径，grid 只跟随两处共用改动：redo 与右键菜单）。

### 非目标

- 不重写编辑器为 SwiftUI（`make test` 里有 `! grep -R 'import SwiftUI'` 硬门禁）。
- 不做 canvas 的自动 tiling / 自动填补空隙求解器（`GridEditing.convertingCanvasToGrid` 已提供"转 grid 后规整"的路径）。
- 不做窗格自定义命名 / 颜色 / 备注。
- 不做运行时（桌面真实窗口）的任何改动。
- 不做无限画布缩放平移（编辑器画布 = 1:1 工作区，保持所见即所得）。

## 3. 现状盘点：可复用的既有能力

| 能力 | 位置 | 复用方式 |
| --- | --- | --- |
| 归一化矩形与 clamp | `Geometry/NormalizedRect.swift`（`clamped()` 最小 0.02、`scaled(...)`、`normalize/denormalize`） | 所有新几何函数的输入输出类型 |
| 相邻缝拖动 | `Geometry/ZoneSplit.swift`（`movingVerticalSeam` / `movingHorizontalSeam`，`minSize = 0.05`） | 切分后两个窗格的缝仍走这条路径 |
| 像素 ↔ 归一化、长宽比 | `Geometry/ZonePixelMetrics.swift`（`resizing`、`applying(pixelWidth:pixelHeight:)`、`minPixels = 40`） | 新增 X/Y 输入与 ⌘D 偏移量的像素换算 |
| grid 的切分/合并/删除范式 | `Geometry/GridEditing.swift`（`split` / `merge` / `deletingZone` / `moveLine`） | canvas 版切分函数照抄其"纯函数 + 返回新 Layout + 内部 reindex"的形状与命名习惯 |
| 编号打包 | `Layout.packedNumbers()` | 复制/切分/删除后统一收尾 |
| 邻居选择、Tab 轮换 | `Layout.neighborZoneID(from:direction:rects:)` / `cycledZoneID` | 多选后仍用它们决定 primary 移动 |
| 编辑事务与撤销 | `Domain/LayoutEditTransaction.swift`（`beginInteraction` / `previewDraft` / `finishInteraction` / `undo`，栈上限 50） | 所有新命令都必须经过它，redo 在此扩展 |
| 编辑器内 ⌘ 键路由先例 | `EditorPanel.performKeyEquivalent`（⌘S / ⌘Z）；`AppRuntime.handleEditorKey` 对含 ⌘/⌃ 的事件一律 `return false` | 所有新增 ⌘ 快捷键必须走 `performKeyEquivalent`，不能指望 `handleLocalKey` |
| 悬浮工具栏与命中排除 | `EditorToolbarChrome` + `canvas.chromeView` + `isPointOverChrome` | 幽灵预览、右键菜单必须复用这套排除逻辑（并补齐 canvas 分支） |
| 缩略图渲染 | `UI/Editor/LayoutThumbnailRenderer.swift` | 空状态"从模板起手"按钮里画 mini 布局 |
| 模板 | `Domain/LayoutTemplates.swift`（`editorPresets()`：Columns 2/3、Rows 2、Grid 2×2、Priority、Focus） | 空状态一键填充。⚠️ 除 `focus()` 外这些 preset 都是 `kind: .grid`，在 canvas 模式套用会把草稿切成 grid 模式（现有 `templateChanged` 就是这个行为）。空状态按钮要显式走 `convertingGridToCanvas(workAreaAX:)`，避免"我在画布模式选了 2 列，结果模式被换了"的困惑 |

**结论**：几何算法都是新写的纯函数，但形状、命名、测试方式全部有成熟先例；AppKit 层的风险集中在"键位路由"与"悬浮 chrome/菜单与失焦取消的互斥"。

## 4. 方案选型

| 方向 | 备选 | 结论 |
| --- | --- | --- |
| **可发现性** | (a) 只改 hint 文案；(b) 首次使用时弹 onboarding 气泡；(c) 空状态引导 + 光标处幽灵预览 + 显式命令入口（工具栏按钮 + 右键菜单） | **选 (c)**。(a) 无人读长文案（现有 canvas hint 已经塞了 5 句还是没人知道能点击新建）；(b) 只教一次，且 `handleAppResign` 会因为额外窗口失焦而取消编辑器，风险高。(c) 是"随时可见、零记忆成本"，且幽灵预览与 grid 模式已有的 `hoverSplit` 虚线预览完全同构，实现路径已验证 |
| **对齐效率** | (a) 全局固定网格吸附（如 8pt 栅格）；(b) 对象吸附 + 参考线（Sketch/Figma 式）；(c) 输入框硬算 | **选 (b)**。canvas 的核心诉求是"和兄弟窗格严丝合缝"，固定栅格解决不了任意比例（例如 0.618 分割）；(b) 顺带免费提供"贴工作区边缘"和"居中"。(c) 保留（本方案顺带补 X/Y 输入） |
| **复制** | (a) 只做 ⌘D；(b) ⌘D + ⌥ 拖拽克隆；(c) 走系统剪贴板 ⌘C/⌘V | **选 (b) 为 v1，(c) 降级为 PR-5**。⌥ 拖拽克隆是"复制 + 定位"一步完成，是这个场景效率最高的手势；系统剪贴板会污染用户剪贴板且需要定义 pasteboard type，收益小 |
| **批量** | (a) 不做多选；(b) 多选 + 对齐/分布/等尺寸 | **选 (b)，但排在最后一期**。它需要把 `selectedID: UUID?` 升级成 `Set<UUID>`，是本方案唯一的结构性改动，必须在前面几期的收益落地后再动 |
| **框选手势** | (a) Shift+拖拽；(b) ⌘+拖拽 | **选 (b)**。空白处裸拖拽已经是"橡皮筋新建"（必须保留），Shift 在编辑器里语义已偏向"反向/加速"（⇧Tab、⇧+方向键），⌘+拖拽与"新建"区分度最高 |

## 5. 总体架构

```
Core（ZoneBoxCore，纯函数，XCTest 覆盖）
 ├─ Geometry/CanvasSnapping.swift    新增：吸附候选边 + 吸附求解 + 命中参考线
 ├─ Geometry/CanvasEditing.swift     新增：插入 / 复制 / 二等分 / 批量删除（返回新 Layout）
 ├─ Geometry/CanvasAlignment.swift   新增：对齐 / 等尺寸 / 等距分布（纯 rect 字典变换）
 ├─ Geometry/ZonePixelMetrics.swift  扩展：moving(_:toX:y:workAreaAX:)
 ├─ Domain/LayoutEditTransaction.swift 扩展：redoStack + canRedo + redo()
 ├─ Domain/ShortcutCatalog.swift     扩展：新增 chord 常量 + .editor specs + nudge 键白名单
 └─ Domain/L10n.swift                扩展：新增文案键（en / zh 双语同步）

App（AppKit，无单测）
 ├─ UI/Editor/LayoutEditorCanvasView.swift
 │    ├─ CanvasCommand 命令总线（键盘 / 右键菜单 / 工具栏按钮三入口共用）
 │    ├─ 幽灵预览（ghost）+ crosshair 光标 + 空状态引导绘制
 │    ├─ drag 三条路径接入吸附（create / move / resize）+ 参考线绘制
 │    ├─ DragKind 新增 .clone / .marquee
 │    └─ selection: Set<UUID> + primaryID（PR-4，保留 selectedID 兼容 shim）
 ├─ UI/Editor/CanvasContextMenu.swift 新增：按上下文构造 NSMenu
 ├─ UI/Editor/LayoutEditorController.swift
 │    ├─ 工具栏新增"窗格操作"行（+ / 复制 / 竖切 / 横切 / 对齐 / 删除）
 │    ├─ metrics 行新增 X / Y 输入
 │    └─ redo 接线 + 空状态"从模板起手"回调
 └─ App/AppRuntime.swift / Services/HotkeyCenter.swift：仅键位放行的最小改动
```

**边界纪律**：`LayoutEditorCanvasView` 不做任何几何决策，只做"事件 → 命令 → 调 Core 纯函数 → 写回 `layout` → `previewDraft/commit`"。所有新算法都能在 `ZoneBoxTests` 里脱离 AppKit 单测。

## 6. 详细设计

### 6.1 空状态引导（解决"打开就是一片空白"）

零窗格（过滤掉正在创建的那个）时，在画布中心绘制引导块：

- 一个占画布 42% 宽 / 30% 高的虚线圆角矩形（8pt 圆角、4-3 虚线、白色 0.5 alpha），中心一个 28pt `plus` SF Symbol。
- 两行文案：主行 `.canvasEmptyTitle`「点击任意位置新建窗格」，副行 `.canvasEmptySubtitle`「或拖出一个矩形；也可以从模板起手」。
- 引导块下方三枚模板按钮（`Columns 2` / `Grid 2×2` / `Rows 2`），图标用 `LayoutThumbnailRenderer.image(for:size:...)`。点击 = 该 preset 经 `convertingGridToCanvas(workAreaAX:)` 转成 canvas 后填入草稿（**保持在画布模式**，不静默切成 grid 模式）。
- 引导块只是绘制，不吃事件：`mouseDown` 落在它上面依旧是"新建窗格"（这正是我们要教的动作，命中即成功）。三枚模板按钮是真实 `NSButton`，放在 `chromeView` 同层，因此自动被 `isPointOverChrome` 排除。

实现落点：`draw(_:)` 开头 `if layout.kind == .canvas, visibleZones.isEmpty { drawEmptyGuide() }`；模板按钮由 controller 创建并在 `zones.isEmpty` 变化时 `isHidden` 切换。

### 6.2 幽灵预览 + 光标（解决"单击不知道会发生什么"）

canvas 模式下，`drag == nil` 且指针落在"空白处"（不在任何窗格、不在关闭按钮、不在 `chromeView`、不在任何边缘命中区）时：

```swift
private var ghostRect: NormalizedRect?   // 单击将创建出的窗格，已过吸附
```

- 计算：`CanvasEditing.defaultRect(at: normalizedPoint, workAreaAX:, bounds:)` 得到与现有 `createDefaultZone` 完全一致的默认尺寸，再过一遍 `CanvasSnapping.snapping(intent: .move, ...)`，让幽灵框在靠近兄弟窗格/工作区边时就已经贴齐 —— 用户看到的预览就是松手后的结果。
- 绘制：虚线圆角矩形 + 中心 `plus` 符号 + 右下角像素尺寸标签（与已有 `"W × H"` 标签同字体）；alpha 0.45，避免与真实窗格混淆。
- 光标：空白处设 `NSCursor.crosshair`（与 grid 模式一致，形成跨模式一致性）。
- 复用现有刷新通道：`mouseMoved` → `refreshHover(at:)` → 计算 `ghostRect` → `needsDisplay = true`；`mouseExited` / `drag != nil` 时清空。
- **顺带修复**：`refreshHover(at:)`（canvas 分支）补 `isPointOverChrome(point)` 判定，与 `refreshGridHover` 对齐 —— 否则鼠标划过悬浮工具栏时会在工具栏底下画幽灵框。

### 6.3 右键上下文菜单（命令的集中展示位）

覆写 `LayoutEditorCanvasView.menu(for event:)`，按命中上下文构造（新文件 `UI/Editor/CanvasContextMenu.swift`，纯构造 + 目标 selector）：

**空白处**：`新建窗格`（⏎ 提示为"单击"）/ `粘贴窗格 ⌘V`（PR-5）/ 分隔线 / `从模板填充…`（子菜单：6 个 preset）/ `全选 ⌘A`

**窗格上**（右键会先把该窗格设为 primary 选中）：

```
复制窗格            ⌘D
垂直二等分          ⌘⇧\
水平二等分          ⌘-
─────────────────
贴到工作区左半 / 右半 / 上半 / 下半     （子菜单，一步做出常见半屏窗格）
居中
─────────────────
对齐 ▸  左 / 水平居中 / 右 / 上 / 垂直居中 / 下      （多选时可用）
尺寸 ▸  等宽 / 等高 / 等宽高                        （多选时可用）
分布 ▸  水平等距 / 垂直等距                          （≥3 选时可用）
─────────────────
编号 ▸ 1…9                                        （PR-5）
删除窗格            ⌫
```

要点与风险：

- 每个菜单项都发一条 `CanvasCommand`，与快捷键、工具栏按钮**共用同一个 `perform(_:)`**，撤销记账只有一处。
- `EditorPanel` 是 borderless `NSPanel`（`canBecomeKey = true`，`show()` 里已 `NSApp.activate`），`NSMenu.popUp` 在同进程弹出**不会**触发 `NSApplication.didResignActiveNotification`，因此不会被 `handleAppResign` 误取消编辑器。**但这是必须实测的一条**（见 §10 手工验收），因为 `handleOtherAppActivated` 对任意其它 app 激活都会 `cancel()`。
- 菜单弹出期间把 `drag` 置 nil、清幽灵框，避免菜单关闭后残留 hover 状态。

### 6.4 吸附与对齐参考线（效率的最大单点收益）

新增 `ZoneBox/Geometry/CanvasSnapping.swift`（Core，纯函数）：

```swift
public struct CanvasSnapCandidates: Equatable, Sendable {
    public var x: [Double]      // 归一化竖线：其它窗格 minX/midX/maxX + 0 / 0.5 / 1
    public var y: [Double]      // 归一化横线：其它窗格 minY/midY/maxY + 0 / 0.5 / 1
    public static func from(rects: [NormalizedRect]) -> CanvasSnapCandidates
}

public struct CanvasSnapResult: Equatable, Sendable {
    public var rect: NormalizedRect
    public var hitX: [Double]   // 实际吸上的竖线，供视图画参考线
    public var hitY: [Double]
}

public enum CanvasSnapping {
    public static let thresholdPoints: CGFloat = 8

    public enum Intent: Equatable, Sendable {
        case move                          // 平移：三条竖线(min/mid/max)择近，整体位移
        case edges(left: Bool, right: Bool, top: Bool, bottom: Bool)   // 创建/缩放：只有在动的边参与
    }

    public static func snapping(
        _ rect: NormalizedRect,
        intent: Intent,
        candidates: CanvasSnapCandidates,
        thresholdX: Double,
        thresholdY: Double,
        minSize: Double = ZoneSplit.minSize
    ) -> CanvasSnapResult
}
```

语义定义（这些就是单测断言）：

1. `.move`：分别用 `minX / midX / maxX` 去找最近候选竖线，取 |delta| 最小且 ≤ `thresholdX` 的那个，整体平移（尺寸不变）；y 轴独立同理。x、y 可以各自命中，也可以只命中一个。
2. `.edges`：只有 `true` 的边参与吸附，另一侧边固定不动；吸附后若尺寸 < `minSize` 则放弃该边的吸附（保证不会因吸附把窗格压扁）。
3. 命中的候选线写入 `hitX/hitY`，视图用它画 1px 青色（`systemTeal`）参考线，横跨整个画布，两端不加箭头。
4. `thresholdX = 8 / bounds.width`、`thresholdY = 8 / bounds.height`（视图侧换算，x/y 阈值不同是刻意的：像素等距而非归一化等距）。
5. 拖拽过程中按住 **⌃（Control）** 临时关闭吸附（`thresholdX = thresholdY = 0`），并清空参考线。

接入点（`LayoutEditorCanvasView.mouseDragged`）：

| DragKind | Intent | 说明 |
| --- | --- | --- |
| `.create` | `.edges(...)`：起点两条边固定，跟手的两条边参与 | 橡皮筋创建即对齐 |
| `.move` | `.move` | 平移不改尺寸 |
| `.resize(handle:)` | `.edges` 由 handle 推导（`.e` → right、`.nw` → left+top …） | 与 `resize(_:handle:dx:dy:lockAspect:)` 串联，锁长宽比时吸附在长宽比修正**之后**再跑一次，且只允许命中一条边 |
| `.split`（相邻缝联动） | 不吸附 | 缝拖动已由 `ZoneSplit` 保证严丝合缝，再吸附会打架 |

候选边在 `mouseDown` 时算一次并缓存（排除正在拖的窗格自身；多选时排除整个选区）。

**顺带收益**：`.create` 与 `.move` 都吸附后，"贴满工作区左半屏"这种最常见需求变成"随便画一个，往左上一甩"，不再需要输入像素。

### 6.5 复制窗格（当前完全缺失）

`Geometry/CanvasEditing.swift`（Core）：

```swift
public enum CanvasEditing {
    /// 单击新建时的默认矩形（与现有 createDefaultZone 的尺寸规则一致，抽出来便于幽灵预览共用）
    public static func defaultRect(centeredAt point: (x: Double, y: Double),
                                  workAreaAX: CGRect) -> NormalizedRect

    public static func inserting(_ layout: Layout, rect: NormalizedRect)
        -> (layout: Layout, newID: UUID)

    /// 复制：偏移 offset（归一化）；越界时回落为"紧贴源窗格右侧"，右侧也放不下则"紧贴下方"，再不行则原地叠放
    public static func duplicating(_ layout: Layout, ids: Set<UUID>,
                                  offset: (x: Double, y: Double))
        -> (layout: Layout, newIDs: [UUID])?

    /// 二等分：把一个窗格按 fraction 切成两个，第二个编号 = max + 1
    public static func splitting(_ layout: Layout, id: UUID,
                                axis: GridAxis, at fraction: Double = 0.5)
        -> (layout: Layout, newID: UUID)?

    public static func deleting(_ layout: Layout, ids: Set<UUID>) -> Layout
}
```

约定（全部可单测）：

- 输入 `kind == .grid` 时一律返回 `nil`（canvas 专用；grid 走 `GridEditing`）。
- 所有函数内部过滤"正在创建"的临时窗格，返回前统一 `packedNumbers()`。
- 复制默认偏移 `16pt`（视图侧用 `ZonePixelMetrics` 换算成归一化传入），保证新窗格可见且立刻可拖。

交互：

| 手势 | 行为 |
| --- | --- |
| `⌘D` | 复制当前选中（多选时整组），选中新窗格；一次撤销回退整组 |
| `⌥ + 拖拽窗格` | 拖拽克隆：`mouseDown` **那一刻**若按住 ⌥ 则先 `duplicating(offset: .zero)`，随后把 drag 切成 `.move(id: 新窗格)`。新增 `DragKind.clone` 只为撤销记账（`beginInteraction` 必须在复制前调用，保证"克隆 + 移动"是一步撤销） |
| 右键 → 复制窗格 | 同 ⌘D |

**修饰键取值时机（实现要点）**：⌥ 的克隆判定只取 `mouseDown` 时刻的 `event.modifierFlags`；⌃ 的"关吸附"在每次 `mouseDragged` 实时取值。这样两个修饰键不会互相干扰（这也是 §7 里刻意不把"关吸附"绑到 ⌥ 的原因）。

### 6.6 canvas 二等分（补上 grid 早就有的能力）

- `⌘⇧\`（⌘|，"竖线" 助记）= 垂直二等分 → 左右两个窗格；`⌘-`（"横线" 助记）= 水平二等分 → 上下两个。
- 走 `CanvasEditing.splitting`，新窗格继承源窗格外框，缝落在中点，两半严丝合缝（复用 `ZoneSplit.minSize` 作为下限，切不动则返回 nil 并 `NSSound.beep()`）。
- 右键菜单与工具栏按钮同命令。选中新产生的**第二个**窗格（与 grid 模式 `handleGridMouseUp` 里 `selectedID = layout.zones.last?.id` 的习惯一致）。
- 连续按 `⌘⇧\` 三次即可从 1 个窗格得到 4 列，配合吸附无需任何手工对齐 —— 这是"创建效率"的主路径之一。

### 6.7 键盘微调

| 键 | 行为 |
| --- | --- |
| `← → ↑ ↓` | 移动选中窗格 1pt（多选整组） |
| `⇧ + 方向键` | 移动 10pt |
| `⌥ + 方向键` | 改尺寸 1pt（作用于右/下边；`⌥⇧` = 10pt） |

实现注意：

- 方向键当前**完全未占用**（`arrowDirection(for:)` 只映射 `a/s/d/w` 字母键，WASD 的"选择邻居"语义不动）。
- `HotkeyCenter` 在 `editorClaimsKeyboard` 分支对 `isARepeat` 事件做白名单（`isEditorPaneNavigation` = a/s/d/w + Delete/Return）。nudge 需要"长按连续移动"，所以要给 `HardwareKeyCode` 加 `isEditorNudge(_:)`（left/right/up/down = 123–126）并纳入该白名单；同时 `LayoutEditorCanvasView.handleKeyEvent` 对方向键**不要**像 WASD 那样 `if event.isARepeat { return true }` 提前返回。
- nudge 属于"一串连续操作"，撤销记账用 `beginInteraction()` + 250ms 静默后 `finishInteraction()`，避免长按产生 50 条撤销记录顶掉整个栈（栈上限 50）。

### 6.8 多选与对齐 / 分布 / 等尺寸（PR-4）

`selectedID: UUID?` → `selection: Set<UUID>` + `primaryID: UUID?`（最后点中的那个，作为对齐基准与 metrics 显示对象）。为把改动面控制住，保留兼容 shim：

```swift
var selectedID: UUID? {                  // controller 侧（metrics / applyCanvasRect）零改动
    get { primaryID }
    set { primaryID = newValue; selection = newValue.map { [$0] } ?? [] }
}
```

手势：

| 手势 | 行为 |
| --- | --- |
| `⇧ 点击` / `⌘ 点击` 窗格 | 加入 / 移出选区，被点者成为 primary |
| `⌘ + 空白拖拽` | 框选（新增 `DragKind.marquee`，虚线白框，相交即入选） |
| `⌘A` | 全选 |
| Tab / ⇧Tab / WASD | 折回单选（primary 移动到目标） |

`Geometry/CanvasAlignment.swift`（Core，纯 rect 变换，完全无 Layout 依赖，最好测）：

```swift
public enum CanvasAlignment {
    public enum Edge: Sendable { case left, centerX, right, top, centerY, bottom }
    public enum SizeMatch: Sendable { case width, height, both }
    public enum Axis: Sendable { case horizontal, vertical }

    /// 以选区并集包围盒为基准对齐
    public static func aligning(_ rects: [UUID: NormalizedRect], to edge: Edge) -> [UUID: NormalizedRect]
    /// 以 primary 的尺寸为基准，保持各自左上角
    public static func matchingSize(_ rects: [UUID: NormalizedRect], primary: UUID, match: SizeMatch) -> [UUID: NormalizedRect]
    /// ≥3 个时按中心等距重排；< 3 个返回原字典（no-op）
    public static func distributing(_ rects: [UUID: NormalizedRect], axis: Axis) -> [UUID: NormalizedRect]
}
```

批量删除 / 批量复制 / 批量 nudge 都走同一条 `perform(_ command:)`，一次撤销回退整批。

### 6.9 工具栏：窗格检查器（可发现性的兜底）

`LayoutEditorController.makeToolbar()` 现有 3 行（模式+模板+动作 / hint / metrics）。新增第 4 行"窗格操作"，图标按钮（SF Symbols）：

| 按钮 | 符号 | 命令 | 禁用条件 |
| --- | --- | --- | --- |
| 新建窗格 | `plus.rectangle` | `.insertDefault`（在画布中心创建） | 无（**永远可用** —— 这是"不知道能单击"的用户的保底出口） |
| 复制 | `plus.square.on.square` | `.duplicate` | 选区为空 |
| 竖切 / 横切 | `rectangle.split.2x1` / `rectangle.split.1x2` | `.split(.vertical/.horizontal)` | 选区为空 |
| 对齐 | `align.horizontal.left` + 下拉 | `.align/.matchSize/.distribute` | 选区 < 2（分布 < 3） |
| 删除 | `trash` | `.delete` | 选区为空 |

metrics 行补 **X / Y** 两个输入框（复用 `EditorMetricsField`，Tab 顺序 X → Y → W → H → 画布），新增纯函数：

```swift
extension ZonePixelMetrics {
    public static func moving(_ rect: NormalizedRect, toX: Int?, y: Int?, workAreaAX: CGRect) -> NormalizedRect
}
```

X/Y 以**工作区左上角为原点、单位像素**（与 `NormalizedRect.y` 向下增长一致，用户心智模型也是屏幕坐标）。

工具栏会变宽变高：`layoutToolbar()` 已经在做 `fittingSize` + `clampToolbarOrigin`，只需确认在 13" 屏（1440pt 宽）下不超宽 —— 若超宽，按钮行与 metrics 行合并为一行并把 hint 缩成单行（hint 已是 `wrappingLabel`，`maximumNumberOfLines = 3`）。工具栏可拖动、拖动中 `alphaValue` 降到 0.12 的现有行为不变。

### 6.10 undo / redo

`LayoutEditTransaction` 扩展（Core，已有 `LayoutEditTransactionTests` 可扩）：

```swift
private var redoStack: [Layout] = []
public var canRedo: Bool { !redoStack.isEmpty }
@discardableResult public mutating func redo() -> Layout?
```

规则：`undo()` 把当前 draft 压入 redoStack；任何 `updateDraft` / `finishInteraction` 产生的新编辑清空 redoStack；上限同为 50。

键位：`⌘⇧Z` → `ShortcutCatalog.editorRedoChord`（+ `⌃⇧Z` 备用，与现有 `editorUndoAlternateChord` 对称），在 `EditorPanel.performKeyEquivalent` 注册，并加入 `HotkeyCenter` 的 `isARepeat` 白名单（与 undo 一致）。grid 模式一并受益。

### 6.11 编号重排（PR-5）

选中窗格后按 `1…9`：把该窗格的 `number` 与当前占用该编号的窗格互换，然后 `packedNumbers()`。编辑器内裸数字键目前未被占用（`ShortcutCatalog` 的 zone 快捷键都带修饰键，`handleOverlayDigit` 只在 armed 贴靠会话里生效）。这一项直接影响运行时"数字键贴到第 N 格"的可用性。

### 6.12 文案与快捷键面板

- `L10n` 新增键（en / zh 同步，两张表都要补，否则 `L10nTests` 的完整性断言会红）：`canvasEmptyTitle`、`canvasEmptySubtitle`、`canvasNewPane`、`canvasDuplicate`、`canvasSplitVertical`、`canvasSplitHorizontal`、`canvasAlign*`、`canvasMatchSize*`、`canvasDistribute*`、`canvasSnapOff`、`editorRedo` 等。
- `editorHint`（canvas）改写为：**「空白处点击或拖拽新建窗格。⌘D 复制，⌘⇧\ / ⌘- 二等分，方向键微调。拖动时按 ⌃ 关闭吸附。⌘Z 撤销，Esc 退出。」**（把"新建"提到第一句；像素/长宽比说明移到 metrics 行的 tooltip）。
- `ShortcutCatalog` 的 `.editor` 分区补：新建窗格（单击手势）、复制 ⌘D、竖切 ⌘⇧\、横切 ⌘-、微调 方向键、框选 ⌘拖拽、关吸附 ⌃、重做 ⌘⇧Z。同时保证 `ShortcutCatalogTests` 的"无重复绑定"断言仍绿。

## 7. 键位与手势冲突守恒表

| 输入 | 现状 | 方案后 |
| --- | --- | --- |
| 空白处单击 | 新建默认窗格（无提示） | **不变**，但有幽灵预览 + crosshair 提前告知 |
| 空白处拖拽 | 橡皮筋新建 | **不变**，新增吸附 + 参考线 |
| ⌘ + 空白拖拽 | 无 | 框选（PR-4） |
| 窗格上拖拽 | 移动 | 不变 + 吸附 |
| ⌥ + 窗格拖拽 | 无 | 拖拽克隆（⌥ 只在 mouseDown 时刻判定） |
| 拖拽中按住 ⌃ | 无 | 临时关闭吸附（每帧实时判定） |
| 边缘 / 角 / 相邻缝拖拽 | 缩放 / 联动缩放 | 不变（缝拖动不吸附） |
| 滚轮 | 缩放选中窗格 | 不变 |
| WASD | 选择邻居窗格 | 不变（多选时折回单选） |
| 方向键 | **未使用** | 移动 1pt；⇧ = 10pt；⌥ = 改尺寸 |
| Tab / ⇧Tab | 轮换选中 | 不变（折回单选） |
| Delete / ⌦ | 删除选中 | 支持多选整批 |
| 数字 1–9 | **未使用** | 设置编号（PR-5） |
| ⌘A | **未使用** | 全选（PR-4） |
| ⌘D | **未使用** | 复制窗格 |
| ⌘⇧\ / ⌘- | **未使用** | 竖切 / 横切 |
| ⌘Z / ⌃Z | 撤销 | 不变 |
| ⌘⇧Z / ⌃⇧Z | **未使用** | 重做 |
| ⌘S | 另存副本 | 不变 |
| Enter | 保存 | 不变 |
| Esc | 取消编辑 | 不变（菜单打开时先关菜单） |
| 右键 | 无 | 上下文菜单 |

**路由铁律**：新增的 ⌘ 系快捷键一律在 `EditorPanel.performKeyEquivalent` 处理 —— `AppRuntime.handleEditorKey` 对含 `.command`/`.control` 的事件直接 `return false`（仅 ⌘S / ⌘Z 例外），走 `handleLocalKey` 是死路。

## 8. 边界情况

| 场景 | 行为 |
| --- | --- |
| 右键菜单弹出 | 编辑器**不得**被 `handleAppResign` / `handleOtherAppActivated` 取消（同进程菜单不改变 active app）。必须实测，若发现被取消则在菜单显示期间置 `canCancelOnAppSwitch = false`（`observeAppSwitchToCancel` 已有该开关） |
| 幽灵预览与悬浮工具栏重叠 | `refreshHover` 补 `isPointOverChrome` 判定后不再绘制 |
| 吸附把窗格压到 < `minSize` | `CanvasSnapping` 放弃该边吸附（不产生退化矩形）；`NormalizedRect.clamped()` 兜底 0.02 |
| 复制越界（源窗格贴在右下角） | `duplicating` 回落顺序：右侧紧贴 → 下方紧贴 → 原地叠放（永不失败，避免"按了 ⌘D 什么都没发生"） |
| 二等分到不可再分 | 返回 nil + `NSSound.beep()`，不产生 0 宽窗格 |
| grid 模式下按 canvas 专属键 | `CanvasEditing.*` 对 grid 返回 nil；⌘D / ⌘⇧\ / ⌘- 在 grid 模式 beep（grid 的切分本来就是"点击 / Shift+点击"） |
| 正在创建的临时窗格（`name == "__creating"`） | 所有新纯函数都过滤它。**建议在 PR-1 顺手把这个哨兵从 model 挪到视图状态**（`private var creatingID: UUID?`），`Layout.cycledZoneID` / `neighborZoneID` / `LayoutTemplates.canvasGeometry` 里的既有过滤保留不动，向后兼容 |
| 多选后切 grid 模式 | `switchEditorMode(toGrid:)` 走 `GridEditing.convertingCanvasToGrid`，选区折回单选（primary） |
| metrics 输入框获得焦点时 | `isEditingMetrics == true` 时所有画布快捷键让路（现有 `handleLocalKey` 首行已如此），新命令沿用 |
| 撤销栈被 nudge 长按刷爆 | nudge 合并成一次交互（§6.7）；批量命令一次一记录 |
| 重叠窗格的选择 | v1 不改（数组末位最上）。`⌥ 点击`轮换重叠窗格列入 §12 |
| 零窗格保存 | `canCommit == false` 行为不变，但空状态引导已把用户导向"先建一个" |

## 9. 性能预算

- 吸附候选边：`mouseDown` 时一次 `O(n)` 收集（n = 窗格数，实际 < 30），拖拽中每帧只做 `O(候选数)` 的最近值比较 —— 微秒级。
- 幽灵预览：`mouseMoved` 一次 `defaultRect` + 一次 `snapping` + `needsDisplay`，与现有 grid 的 `hoverSplit` 同量级。
- 绘制：参考线最多 6 条直线；空状态引导只在零窗格时画。
- 无新增计时器、无新增窗口/面板（右键菜单是系统 `NSMenu`，模板按钮挂在既有 chrome 层）。

## 10. 测试方案

### Core 单测（`ZoneBoxTests`，XCTest，无 AppKit）

1. **`CanvasSnappingTests`**（新）
   - 兄弟窗格右边 vs 目标左边：阈值内吸附、阈值外不动、恰好等于阈值吸附（边界）。
   - 中线吸附（0.5）与工作区边（0、1）吸附。
   - `.move` 保持尺寸不变；`.edges` 只动指定边、另一边 bitwise 不变。
   - x、y 各自独立命中；`hitX/hitY` 只包含真正吸上的线。
   - 阈值 0（⌃ 关吸附）时 `rect` 原样返回、`hit*` 为空。
   - 吸附会导致尺寸 < `minSize` 时放弃该边。
2. **`CanvasEditingTests`**（新）
   - `defaultRect` 与现有 `createDefaultZone` 的尺寸规则一致（golden 值）。
   - `duplicating`：偏移正确、编号 = max+1、返回 `newIDs` 顺序稳定、右下角越界三级回落、多选整组复制、`__creating` 被过滤。
   - `splitting`：竖切/横切几何为严丝合缝二等分、编号顺延、不可再分返回 nil、grid 输入返回 nil。
   - `deleting`：批量删除后 `packedNumbers()` 连续、删空返回零窗格布局。
3. **`CanvasAlignmentTests`**（新）：6 种对齐、3 种等尺寸（以 primary 为基准）、2 种分布（含 <3 个时 no-op）、空输入 no-op。
4. **`ZonePixelMetricsTests`** 扩展：`moving(toX:y:)` 的 clamp（负值、超出工作区、只给 X 不给 Y）。
5. **`LayoutEditTransactionTests`** 扩展：undo → redo 往返得到同一 draft；redo 后再编辑清空 redoStack；redo 栈上限 50；`canRedo` 初始为 false。
6. **`ShortcutCatalogTests`** 扩展：新 chord 与既有绑定无冲突；`.editor` specs 数量与内容；`isEditorNudge` 覆盖 123–126。
7. **`L10nTests`** 扩展：新键在 en / zh 两张表都存在（现有测试模式）。

### 手工验收清单

**可发现性**
- 菜单栏「新建画布布局」→ 画布中央出现虚线引导 + 三枚模板按钮；点模板后**仍在画布模式**（模式段控停在 Canvas）。
- 鼠标在空白处移动 → 出现虚线幽灵框 + `+` + 尺寸标签，光标为 crosshair；单击后新建的窗格与幽灵框**完全重合**。
- 鼠标移到悬浮工具栏上 → 幽灵框消失、光标恢复箭头。
- 右键空白 / 右键窗格 → 菜单内容符合 §6.3；**菜单弹出与关闭期间编辑器不被取消**，Esc 先关菜单不退编辑器。

**效率**
- 画一个窗格往工作区左边缘甩 → 8pt 内吸附贴边并出现青色参考线；按住 ⌃ 拖 → 不吸附、无参考线。
- 两个窗格边靠边 → 吸附后无缝（保存后 Preview Zones 无 1px 缝隙）。
- ⌘D → 右下偏移 16pt 的副本；对贴在右下角的窗格 ⌘D → 落在源窗格左侧/上方而不是画布外。
- ⌥ 拖拽窗格 → 克隆并跟手；⌘Z 一次回到克隆前。
- 1 个窗格连按 ⌘⇧\ 三次 → 4 个等宽列，无缝、编号 1–4。
- 方向键 1pt / ⇧ 10pt / ⌥ 改尺寸；长按连续移动，⌘Z 一次撤销整段。
- ⌘Z / ⌘⇧Z 往返 10 次，画布状态一致。
- 多选（⇧点击、⌘框选、⌘A）→ 对齐/等宽/等距分布；一次撤销回退整批。
- grid 模式全部旧行为不变（点击竖切、Shift 横切、拖线、拖过合并、⌘Z）。
- 双屏：在副屏打开编辑器，以上全部复验（`workAreaAX` 与 `primaryFlipHeight` 换算）。

命令：`make test`（含 `import SwiftUI` 门禁），UI 部分手工验收。

## 11. 分期交付

| PR | 内容 | 风险 |
| --- | --- | --- |
| **PR-1 可发现性** | 空状态引导 + 模板按钮、幽灵预览 + crosshair、`refreshHover` 补 chrome 排除、hint 文案改写、工具栏「窗格操作」行（先只接 新建/删除）、`ShortcutCatalog` 文案条目、`__creating` 哨兵改为视图状态 | 低（无新几何，无模型改动）。**单独发这一个 PR 就已经解决"用户不知道能单击新建"** |
| **PR-2 吸附与参考线** | `CanvasSnapping` + 单测 + 接入 create/move/resize 三条路径 + ⌃ 关吸附 + 参考线绘制 | 中（触碰核心 drag 路径，但纯函数可测） |
| **PR-3 复制与切分** | `CanvasEditing` + 单测、⌘D、⌥ 拖拽克隆、⌘⇧\ / ⌘-、右键菜单（`CanvasContextMenu`）、redo（`LayoutEditTransaction` + ⌘⇧Z）、`EditorPanel.performKeyEquivalent` 路由 | 中（键位路由 + 菜单与失焦取消的互斥需实测） |
| **PR-4 多选与批量** | `selection: Set<UUID>` + primary + 兼容 shim、⇧/⌘ 点选、⌘ 框选、⌘A、`CanvasAlignment` + 单测、对齐/尺寸/分布菜单与工具栏下拉 | 中高（唯一的结构性重构，放在收益已落地之后） |
| **PR-5 打磨** | X/Y 像素输入（`ZonePixelMetrics.moving`）、数字键重排编号、⌘C/⌘V、贴半屏/居中快捷命令、双语文案与快捷键面板补全、README/本文档状态更新 | 低 |

## 12. 未来扩展

- **⌥ 点击轮换重叠窗格** + 命中顺序与绘制顺序统一（`hitZone` 用 `number` 排序的逆序）。
- **智能间距吸附**（Figma 式等距提示）：吸附候选里加入"与相邻窗格保持相同间距"。
- **canvas → grid 的一键规整**：`GridEditing.convertingCanvasToGrid` 已存在，可在窗格接近 tiling 时主动提示"要不要转成网格布局（可拖线联动）"。
- **窗格模板库**：把常用窗格尺寸（如 16:9 视频窗）存成可复用的窗格 preset。
- **与运行时分隔杆联动**：`docs/runtime-divider-design.md` 的 canvas 扩展需要本方案的 `allSharedSeams` 邻接判定，两者共用同一套"缝"抽象。

## 13. 决策记录

| 决策点 | 结论 |
| --- | --- |
| 可发现性做法 | 空状态引导 + 幽灵预览 + 显式命令入口（工具栏 + 右键菜单）三处并行，不依赖长文案，不做一次性 onboarding |
| 吸附类型 | 对象吸附 + 参考线（非固定栅格），阈值 8pt，⌃ 临时关闭 |
| 复制手势 | ⌘D + ⌥ 拖拽克隆为 v1；⌘C/⌘V（应用内剪贴板，不污染系统剪贴板）延后 |
| 二等分键位 | ⌘⇧\（竖）/ ⌘-（横），字形助记；grid 模式仍是点击 / Shift+点击 |
| 框选键位 | ⌘ + 空白拖拽（裸拖拽必须保留为"新建"） |
| 微调键位 | 方向键（当前空闲），WASD 继续做"选择邻居" |
| 多选改造时机 | 最后一期，用 `selectedID` 计算属性 shim 把 controller 侧改动面压到零 |
| 数据结构 | 零 schema 变更；`__creating` 哨兵从 model 移出到视图状态 |
| 新增 ⌘ 快捷键路由 | 一律走 `EditorPanel.performKeyEquivalent`（`handleEditorKey` 会丢弃 ⌘/⌃ 事件） |
