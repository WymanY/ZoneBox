# ZoneBox 首次启动引导（Welcome Tour）技术设计

| 字段 | 值 |
| --- | --- |
| **标题** | 首次启动时的分步引导：认识产品、开权限、选布局、完成第一次吸附 |
| **状态** | 已实现 |

| **日期** | 2026-09-04 |
| **作用范围** | App 层新增一个可重入的分步引导窗口；Core 层新增触发策略与页面状态机（纯函数）；对既有 Accessibility 引导做一次职责拆分 |
| **关联文档** | `docs/design.md`（整体架构、"纯函数进 Core、只测 reducer/几何"、`UISession`/TCC 决策）、`docs/runtime-divider-design.md`（写法基准）、`docs/workspace-profiles-design.md`（同类设计） |

---

## 1. 背景与问题

ZoneBox 是 `LSUIElement` 菜单栏应用（`Info.plist` 里 `LSUIElement = true`，`AppDelegate.main()` 设 `.accessory`），**启动后没有任何主窗口**。当前首次启动的用户体验取决于一个偶然条件——辅助功能权限是否已授予（`AppRuntime.start()` 末尾：`if !trust.isTrusted() { onboarding?.show() }`）：

1. **未授权**：弹出 `OnboardingWindowController`。这个窗口虽然叫 onboarding，实际只讲"怎么在系统设置里打开 ZoneBox 的开关"（4 个 Phase：`needsPermission / waiting / granted / needsRelaunch`），一个字都没提 ZoneBox 是做什么的。授权成功 1.2 秒后自动关窗，用户面前又是一片空白。
2. **已授权**（例如按 README 的 Quit & Relaunch 路径重开、或升级安装）：**什么都不显示**。用户只能靠自己发现菜单栏里多了一个 `rectangle.split.3x1` 图标，再靠猜摸索出 Shift-drag。

用户反馈归结为三个"不知道"：不知道这个 App 在哪（菜单栏）、不知道它能干什么（分区/布局/吸附）、不知道第一步该做什么（开权限 → 选布局 → 拖一个窗口试试）。README 的 "Use it" 六步其实就是标准答案，但它在仓库里，不在产品里。

同时存在一个命名债：`ZoneBox/UI/Onboarding/` 目录及 `L10nKey.onboarding*` 承载的是**权限引导**而不是产品引导。新方案要把两者的职责说清楚，避免以后两个"onboarding"互相踩。

## 2. 目标 / 非目标

### 目标（v1）

1. **首次启动必有窗口**：无论权限状态如何，第一次启动都弹出"欢迎引导"（Welcome Tour），让用户在 2 分钟内知道 ZoneBox 是什么、住在哪、怎么用。
2. **讲清四件事**：① 产品是什么 + 在菜单栏；② 分区（zone）与布局（layout）是什么，并**当场选一个起始布局、在真实屏幕上闪现预览**；③ 为什么需要辅助功能权限并当场开好（复用现有权限引导的全部逻辑）；④ 三种吸附方式，并**实时检测用户完成第一次吸附**给出正反馈。
3. **顺带介绍进阶能力**（布局编辑器、分隔杆、工作区方案、Quick Snapper 与置顶 Pin）和最重要的几条快捷键（从当前 `AppSettings` 实时读取，尊重用户自定义）。
4. **可重入**：菜单栏右键菜单、设置 → 通用里都能再次打开；支持 `--show-welcome` 调试参数。
5. **可跳过、只弹一次**：任何方式关闭（完成 / 跳过 / 红叉 / Escape）都记录"已看过本版引导"；用版本号门控为以后的"新版本有什么新功能"页面留口子。
6. **不破坏既有行为**：`UISession` 引用计数、Escape 路由（`ShortcutRouteContext.escapeAction`）、fail-closed 的权限门、语言实时切换、多显示器语义（"鼠标所在显示器"）全部保持；标准权限引导在"已看过引导但未授权"时行为与今天完全一致。
7. **遵守仓库工程约束**：无 SwiftUI（`make test` 会 grep 拒绝）；页面状态机与触发策略是 Core 里的纯函数，用 `ZoneBoxTests` 无 AppKit 单测覆盖；所有文案走 `L10nKey`，en / zh-Hans 双语齐全。

### 非目标（v1 明确不做）

- 视频、GIF、Lottie 等外部动效资源（仓库只有 `SnapPreview.png` 和 SVG 图标；v1 用矢量绘制 + 真实屏幕上的 overlay 闪现代替，动画列入 §12）。
- 桌面级"coach mark"气泡（把提示锚在菜单栏图标或别人家窗口上）。菜单栏图标位置可取，但其他锚点不稳定，收益不抵复杂度。
- 任何使用统计 / 遥测（项目没有网络层，`design.md` 的隐私立场是"nothing is uploaded"）。
- 在引导里申请屏幕录制权限（Pin 镜像用）。该权限按需在 Pin 首次使用时申请（现有 `pinScreenRecording*` 流程），引导只做一句话提及。
- 介绍 Organize（`WindowOrganize.isPubliclyAvailable = false`，入口已下线）。
- 每次版本升级自动弹"更新说明"。v1 只搭版本门控，不填内容。

## 3. 现状盘点（可复用的既有能力）

| 能力 | 位置 | 说明 |
| --- | --- | --- |
| 权限引导视图 + 轮询状态机 | `UI/Onboarding/OnboardingView.swift`（4 Phase 视图）、`OnboardingWindowController.swift`（0.5s `Timer` 轮询 `trust.isTrusted()`、打开系统设置 14s 后转 `needsRelaunch`、`accessibilityGranted()` 回调） | **整段逻辑原样复用**为引导的"权限"页；只需把"轮询 + Phase 推导"从窗口控制器里抽成一个无窗口的模型对象（§6.6）。 |
| 打开系统设置 / 重启应用 | `Services/TrustMonitor.swift` → `openAccessibilitySettings()`、`relaunchApp()` | 直接调用。`relaunchApp()` 用 `/bin/sh -c "sleep 0.7; /usr/bin/open -n <path>"`，追加 `--args` 即可把"重启后回到哪一页"带过去（§6.4）。 |
| 布局缩略图渲染 | `UI/Editor/LayoutThumbnailRenderer.image(for:size:fill:stroke:gutterPoints:showNumbers:)` | 已支持任意尺寸、gutter、编号。"选布局"页的 6 张大缩略图和"分区是什么"的示意图零新增绘制代码。 |
| 内置布局模板 | `Domain/LayoutTemplates.editorPresets()`（Columns 2/3、Rows 2、Grid 2×2、Priority 3、Focus）、`matchingEditorPresetIndex(for:workAreaAX:)` | 前者是候选集；后者按几何去重，避免用户点 "Columns 2" 时和 `DisplayWatcher.refresh` 已创建的默认 "Columns 2" 重复入库。 |
| 首启默认布局 | `Services/DisplayWatcher.refresh(document:)` → `LayoutTemplates.defaultForVisible`（横屏 Columns 2 / 竖屏 Rows 2）并 `document.assign` | 引导打开时每个显示器**已经有**一套布局；"选布局"页默认选中它，用户不选也能直接进入吸附。 |
| 布局指派 + 预览闪现 | `AppRuntime.saveLayout(_:to:)`（`upsertAndAssign` + `persist` + `reloadMenu`）、`selectLayout(_:)`、`previewZones()`（1.6s 闪现，鼠标所在显示器） | 选布局页复用；需要补一个按显示器 ID 闪现的重载（§6.3）。 |
| 吸附完成的确定性落点 | `Services/SnapEngine.swift`：键盘/QuickSnapper 路径的 `snap(_:to:)` 与拖拽路径的 `.recordUnsnap` effect 都会调 `runtime.catalog.record(_:displayID:)` | "检测第一次吸附"只需在这两个调用点后各加一行通知（§6.5），不引入轮询。 |
| 快捷键的实时展示 | `ShortcutCatalog.grouped(from: settings)`、`KeyChord.displayCaps` | 引导里的所有快捷键文字从 `runtime.settings` 现算，用户改过绑定也正确；`ShortcutPanelController.caps(for:)` 的胶囊样式可参考。 |
| 登录时启动 | `SettingsWindowController.toggleLogin(_:)` → `SMAppService.mainApp.register()/unregister()`，`.requiresApproval` 时 `openSystemSettingsLoginItems()` | 抽成共享的 `LoginItemController`，设置页和引导"完成"页共用（§6.7）。 |
| 窗口生命周期样板 | `SettingsWindowController`（`uiSession.enterRegular()`、`windowWillClose` → `runtime.settingsDidClose()` → `leaveRegular()`）、`ShortcutPanelController` | 新窗口控制器照搬这套"runtime 持有 optional、关闭回调置 nil"的模式。 |
| Escape 路由 | `Domain/ShortcutCatalog.swift` → `ShortcutRouteContext.escapeAction`（已有 `onboardingIsKey → .closeOnboarding`） | 语义扩展为"任一引导窗口是 key"，Core 不改，App 层 `runtime.onboardingIsKey` / `closeOnboardingIfOpen()` 覆盖两个窗口即可（§6.8）。 |
| 语言实时切换 | `LanguageCenter.didChangeNotification` → `AppRuntime.applyLanguage()` 逐窗口下发 | 新控制器实现 `applyLanguage()` 并加入分发链。 |
| 设置持久化的前后兼容惯例 | `AppSettings.init(from:)` 的 `decodeIfPresent ?? default`（`hoverPinEnabled`、`showLayoutStrip` 即先例） | 新字段 `onboardingCompletedVersion` 同法，旧 `settings.json` 解出 0。 |
| 调试启动参数 | `AppDelegate.applicationDidFinishLaunching` 的 `#if DEBUG` `--open-settings` | 新增 `--show-welcome` / `--skip-welcome` / `--welcome-page` 走同一处。 |

**结论：权限引导、缩略图、布局指派、吸附落点、快捷键展示、登录项全部有现成轮子。新增工作集中在"一个纯函数状态机 + 一个分页窗口控制器 + 六个页面视图 + 入口接线"。**

## 4. 方案选型

| 方案 | 描述 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- | --- |
| **A. 给现有权限引导加几页** | 在 `OnboardingView` 前后各塞一页介绍 | 改动最小 | 权限引导是"未授权才弹"，已授权用户依旧什么都看不到；`OnboardingView` 是单一 `NSStackView`，没有分页骨架，硬塞会把 4 Phase 逻辑搅成一团 | 否决 |
| **B. 独立的分步引导窗口，权限引导作为其中一页（本设计）** | 新建 `WelcomeWindowController`，6 页线性流程；权限页复用现有视图；"选布局""试吸附"两页驱动真实屏幕上的 overlay 和真实窗口 | 首启必有窗口；讲功能的同时让用户**真的做一次**（选布局、开权限、吸附）；权限逻辑零重复；独立权限引导保留给"已看过引导但权限掉了"的场景 | 多一个窗口控制器 + 一次权限引导的职责拆分；要处理与既有子系统的互斥（§6.8） | **采用** |
| **C. 桌面 coach mark（无窗口）** | 半透明全屏 overlay + 指向菜单栏图标的气泡 | 沉浸 | 除菜单栏图标外没有稳定锚点；与 `OverlayPanel` 争层级和键盘；VoiceOver 不友好；无法承载权限引导那种需要来回切系统设置的流程 | 否决 |
| **D. 首启只打开设置窗口** | 复用 `SettingsWindowController` | 零新 UI | 设置页是"调参"不是"教学"，五个分类的开关会淹没首次用户；依旧不解决"不知道怎么吸附" | 否决 |
| **E. 首启打开 README / 网页** | `NSWorkspace.open` 文档 | 零成本 | 割裂、不可交互、离线不可用 | 否决 |

## 5. 总体架构

```
AppRuntime.start()
 └─ OnboardingPolicy.launchDecision(…)            Core 纯函数（§6.1）
      ├─ .welcomeTour        → welcome = WelcomeWindowController(runtime:); show(resume:)
      ├─ .accessibilityGuide → accessibilityGuide = AccessibilityGuideWindowController(runtime:); show()   （= 今天的行为）
      └─ .none

WelcomeWindowController（App 层，UI/Onboarding/）
 ├─ state: OnboardingFlowState        Core 纯状态（页序、当前页、trusted、didSnap）
 ├─ reduce(event) → [effect]          Core 纯函数 OnboardingFlowReducer（§6.2）
 ├─ pageHost: NSView                  当前页容器，crossfade 切页
 ├─ navBar                            [跳过引导] ···步骤点··· [上一步] [继续 / 完成]
 └─ pages: [OnboardingPage: WelcomePage]
      ├─ WelcomeIntroPage             欢迎 + 菜单栏定位
      ├─ WelcomeLayoutsPage           分区/布局概念 + 起始布局选择（真实屏幕闪现）
      ├─ WelcomeAccessibilityPage     复用 AccessibilityGuideView + AccessibilityGuideModel
      ├─ WelcomeFirstSnapPage         三种吸附方式 + 实时"第一次吸附"检测
      ├─ WelcomeMorePage              四张能力卡片 + 打开布局编辑器
      └─ WelcomeFinishPage            关键快捷键 + 登录时启动 + 完成

既有权限引导（重命名，职责不变）
 ├─ AccessibilityGuideView            ← OnboardingView
 ├─ AccessibilityGuideModel           ← 从 OnboardingWindowController 抽出的轮询 + Phase 推导（新，无窗口）
 └─ AccessibilityGuideWindowController ← OnboardingWindowController（只剩开窗/关窗/转发）
```

分层原则与仓库既有做法一致：**能不碰 AppKit 就不碰**。"什么时候弹、弹哪几页、按了继续去哪、什么时候算完成"全部在 `ZoneBoxCore` 的 `Domain/Onboarding.swift`；App 层只负责把 effect 变成窗口操作。

## 6. 详细设计

### 6.1 触发策略（OnboardingPolicy，纯函数）

```swift
public enum OnboardingPolicy {
    /// 引导内容版本。改了页面内容想让老用户再看一次时 +1。
    public static let currentVersion = 1

    public static func launchDecision(_ input: OnboardingLaunchInput) -> OnboardingLaunchDecision
    public static func pages(trusted: Bool) -> [OnboardingPage]
    public static func initialIndex(resume: OnboardingPage?, pages: [OnboardingPage]) -> Int
}

public struct OnboardingLaunchInput: Equatable, Sendable {
    public var completedVersion: Int     // settings.onboardingCompletedVersion
    public var currentVersion: Int       // OnboardingPolicy.currentVersion
    public var trusted: Bool             // trust.isTrusted()
    public var forceTour: Bool           // --show-welcome
    public var suppressTour: Bool        // --skip-welcome
    public var resumePage: OnboardingPage?   // --welcome-page <raw>
}

public enum OnboardingLaunchDecision: Equatable, Sendable {
    case welcomeTour, accessibilityGuide, none
}
```

判定顺序：

1. `forceTour` → `.welcomeTour`（调试/复现用，无视已完成标记）。
2. `!suppressTour && completedVersion < currentVersion` → `.welcomeTour`。
3. 否则 `trusted ? .none : .accessibilityGuide`——**即今天 `AppRuntime.start()` 的行为**，一字不改地保留给"已看过引导但权限掉了"的场景。

`pages(trusted:)`：已授权时去掉 `.accessibility` 页（不让用户为一个已经打开的开关翻一页）。**页序在流程开始时算一次**，中途授权成功不增删页面，只改页面内容（§6.2 的 `.trustChanged`），避免步骤点数量跳变。

`initialIndex(resume:pages:)`：`resume` 为 nil 返回 0；否则返回该页下标；若该页因 `trusted` 被移除（典型：在权限页点了"退出并重新打开"，重启后已授权），落到**它之后第一个存在的页**（权限页 → 试吸附页），保证重启不会把用户扔回第一页。

### 6.2 页面状态机（OnboardingFlowReducer，纯函数）

```swift
public enum OnboardingPage: String, CaseIterable, Sendable {
    case welcome, layouts, accessibility, firstSnap, more, finish
}

public struct OnboardingFlowState: Equatable, Sendable {
    public var pages: [OnboardingPage]
    public var index: Int
    public var trusted: Bool
    public var didSnap: Bool
    public var page: OnboardingPage { pages[index] }
    public var isFirst: Bool { index == 0 }
    public var isLast: Bool { index == pages.count - 1 }
}

public enum OnboardingFlowEvent: Equatable, Sendable {
    case next, back, skip, closeRequested, finish
    case trustChanged(Bool)
    case snapCompleted
}

public enum OnboardingFlowEffect: Equatable, Sendable {
    case showPage(OnboardingPage)     // 切页（含步骤点、导航按钮刷新）
    case refreshCurrentPage           // 不切页，只让当前页按新 state 重绘
    case markCompleted                // settings.onboardingCompletedVersion = currentVersion; persist
    case close
}

public enum OnboardingFlowReducer {
    public static func reduce(_ state: inout OnboardingFlowState,
                              _ event: OnboardingFlowEvent) -> [OnboardingFlowEffect]
}
```

转移规则：

| 事件 | 条件 | 状态变化 | effects |
| --- | --- | --- | --- |
| `.next` | `!isLast` | `index += 1` | `[.showPage(page)]` |
| `.next` | `isLast` | — | `[.markCompleted, .close]`（等价于 `.finish`） |
| `.back` | `!isFirst` | `index -= 1` | `[.showPage(page)]` |
| `.back` | `isFirst` | — | `[]` |
| `.skip` / `.closeRequested` / `.finish` | — | — | `[.markCompleted, .close]` |
| `.trustChanged(t)` | `t != trusted` | `trusted = t` | `[.refreshCurrentPage]` |
| `.snapCompleted` | `!didSnap` | `didSnap = true` | `page == .firstSnap ? [.refreshCurrentPage] : []` |

导航按钮文案也由 Core 派生，便于单测：

```swift
public enum OnboardingNavigation {
    /// 主按钮：最后一页 → 完成；权限页且未授权 → 暂时跳过；其余 → 继续
    public static func primaryTitle(_ s: OnboardingFlowState) -> L10nKey
    public static func showsSkip(_ s: OnboardingFlowState) -> Bool      // !isLast
    public static func showsBack(_ s: OnboardingFlowState) -> Bool      // !isFirst
    public static func stepLabel(_ s: OnboardingFlowState) -> (current: Int, total: Int)
}
```

关闭一律视为"已看过"（决策 D-4）：不区分完成、跳过、红叉、Escape。想再看走菜单入口。

### 6.3 页面规格

窗口：`NSWindow`，`[.titled, .closable, .fullSizeContentView]`，`titlebarAppearsTransparent`，固定 760×560、不可缩放，`center()`，`isMovableByWindowBackground`。层级默认 `.normal`；**仅权限页可见期间**提升为 `.floating`（与现有权限引导一致，避免被系统设置盖住），离开权限页恢复 `.normal`——试吸附页需要让用户随意拖别的窗口，引导窗口被盖住是正常的。`collectionBehavior = [.managed, .fullScreenAuxiliary]` 与设置窗口一致。

切页：单个 `pageHost` 容器，新旧页面 150ms alpha crossfade（`NSAnimationContext`），不引入 `NSPageController`。每页是一个 `NSView` 子类，实现协议：

```swift
@MainActor protocol WelcomePage: NSView {
    func willAppear(state: OnboardingFlowState)    // 拿 runtime 数据刷一遍
    func willDisappear()                            // 停轮询 / 停动画
    func refresh(state: OnboardingFlowState)        // .refreshCurrentPage
    func applyLanguage()
}
```

导航栏（固定在窗口底部）：左侧 `跳过引导`（最后一页隐藏）；中间步骤点（`NSStackView` 里 N 个 8pt 圆点，当前页实心，`setAccessibilityLabel("第 2 步，共 6 步")`）；右侧 `上一步` + 主按钮（`keyEquivalent = "\r"`）。

**P1 欢迎（`.welcome`）**

- 视觉：应用图标（`NSApp.applicationIconImage`）+ 一行价值主张 + 一条**模拟菜单栏**（深色圆角条，右端放 `MenuBarIcon` 模板图与一个时钟文字），图标下方标注"ZoneBox 在这里"。
- 文案：`welcomeIntroTitle`（"欢迎使用 ZoneBox"）、`welcomeIntroSubtitle`（"在屏幕上划出分区，拖一下或按个快捷键，窗口就吸附进去。"）、`welcomeIntroMenuBar`（"ZoneBox 常驻菜单栏（时钟旁边），没有 Dock 图标。左键点图标打开面板，右键打开菜单。"）。
- 交互：`welcomeIntroLocate` 按钮（"指给我看"）→ `runtime.menuBar?.pulseStatusItem()`：状态项按钮 `alphaValue` 1 → 0.2 → 1 三次（`NSAnimationContext`，共 1.2s）。新增 `MenuBarController.pulseStatusItem()` 一个方法。

**P2 分区与布局（`.layouts`）**

- 概念一句话：`welcomeLayoutsTitle`（"分区就是窗口的落点"）、`welcomeLayoutsBody`（"一套布局 = 一个显示器上的一组带编号分区。先选一个起始布局，之后随时可以改，或者自己画。"）、脚注 `welcomeLayoutsPerDisplay`（"每个显示器各自记住一套布局。"）。
- 选择器：3×2 网格，每格 `LayoutThumbnailRenderer.image(for:size: 148×92, fill: 强调色, stroke: 白, gutterPoints: settings.gutterPoints, showNumbers: true)` + 名称（`L10n.layoutDisplayName`）。候选 = `LayoutTemplates.editorPresets()`。
- 目标显示器 = **引导窗口所在显示器**（`runtime.displays.area(containingAppKit: window.frame 中心)`），不用鼠标位置——多屏时鼠标在窗口上，两者一致；单靠鼠标会在用户把窗口拖到另一屏后出错。
- 默认选中：该显示器当前指派的布局（`document.layout(for:)`），用 `LayoutTemplates.matchingEditorPresetIndex(for:workAreaAX:)` 映射到某个模板格；映射不到（用户自定义布局，重入场景）则不选中任何格，并在网格下方显示"当前：<名称>"。
- 点击某格：
  1. 用 `matchingEditorPresetIndex` 在 `document.layouts` 里找几何相同的既有布局；找到 → `runtime.selectLayout(existing)`（只改指派，不产生重复的 "Columns 2"）；
  2. 找不到 → `runtime.saveLayout(preset, to: displayID)`（`upsertAndAssign` + `persist` + `reloadMenu`）；
  3. 再调 `runtime.previewZones(on: displayID)`（新增重载，把现有 `previewZones()` 的"鼠标所在显示器"参数化）在真实屏幕上闪现 1.6s。`selectLayout` 自带的 `previewLayoutOnSelect` 闪现是 0.5s 且受设置开关影响，引导里不依赖它。
- `didChangeScreenParametersNotification` 到来时（已在 `AppRuntime.observeSystem` 观察）重算目标显示器并 `refresh`。

**P3 辅助功能权限（`.accessibility`，已授权则不出现）**

- 页头：`welcomeAccessTitle`（"允许 ZoneBox 移动窗口"）；正文不新增 key，直接复用现有 `onboardingSubtitle`（"macOS 要求先开启辅助功能，ZoneBox 才能移动和调整其他应用的窗口。权限只留在这台 Mac 上，不会上传。"）。
- 页体：**原样嵌入 `AccessibilityGuideView`**（三步说明 + 模拟开关列表 + 状态行 + 按钮行），去掉它自己的大图标和标题（加一个 `showsHeader` 开关）。按钮语义不变：主按钮"打开辅助功能设置"、`我已打开开关`、`退出并重新打开`。
- 驱动：`AccessibilityGuideModel`（§6.6）在 `willAppear` 启动 0.5s 轮询、`willDisappear` 停止。Phase 变化 → 视图 `apply(phase)`；`isTrusted()` 翻真 → `runtime.accessibilityGranted()`（与今天一样只触发一次：重启 `DragMonitor`、`hotkeys.reregister()`、刷新菜单栏警告）并向状态机发 `.trustChanged(true)`。
- **不自动翻页**（现有引导是 1.2s 后自动关窗）：授权成功后状态行显示绿色对勾，主导航按钮文案从"暂时跳过"变为"继续"并高亮，由用户决定何时前进。
- "退出并重新打开"：调用 `runtime.trust.relaunchApp(arguments: ["--welcome-page", OnboardingPage.firstSnap.rawValue])`（§6.4），重启后直接落在试吸附页。

**P4 吸附第一个窗口（`.firstSnap`，交互式）**

- 页头：`welcomeSnapTitle`（"吸附第一个窗口"）、`welcomeSnapBody`（"三种方式任选一种，试试把任意窗口放进一个分区。"）。
- 三张方式卡片（图标 + 一句话，文案里的快捷键从 `runtime.settings` 现算）：
  1. `hand.draw` — `welcomeSnapShiftDrag`："按住标题栏拖动窗口，同时按住 Shift，放到分区上。"（`snapOnShiftDrag` 关闭时隐藏此卡）
  2. `computermouse.fill` — `welcomeSnapRightClick`："拖动时按一下右键，也会显示分区。"（`snapOnRightClickDrag` 关闭时隐藏）
  3. `keyboard` — `welcomeSnapKeyboard`："先点一下别的窗口，再按 %@。" 参数 = `KeyChord(keyCode: AppSettings.zoneKeyCodes[0], carbonModifiers: settings.zoneHotkeyModifiers).displayCaps` 拼成 "⌃⌥1"（`snapZoneHotkeysEnabled` 关闭时隐藏）
  - 脚注 `welcomeSnapWhileArmed`："分区显示时按 1–9 可直接落到对应编号；拖动时左右晃动标题栏也能呼出分区。"（后半句仅 `shakeToSnapEnabled` 时显示）
- 按钮 `welcomeSnapShowZones`（"在这个屏幕上显示分区"）→ `runtime.previewZones(on: displayID)`。
- 状态行：
  - 未授权：橙色 `exclamationmark.triangle.fill` + `welcomeSnapNeedsAccess`（"辅助功能未开启，吸附暂时不可用。"）+ 链接按钮 `welcomeSnapGoToAccess`（"去开启"）。页序里有权限页 → `.back` 回到它；没有（流程开始时已授权、中途被撤销的罕见情况）→ `runtime.openAccessibility()` 打开独立权限引导。
  - 已授权、未吸附：小 spinner + `welcomeSnapWaiting`（"等待你的第一次吸附…"）。
  - `didSnap`：绿色对勾 + `welcomeSnapDone`（"成功！按 %@ 可以把窗口放回原处。" 参数 = `settings.unsnapHotkey.displayCaps`）。
- 检测源：`runtime.noteUserSnapCompleted()`（§6.5）→ 状态机 `.snapCompleted`。**不轮询 `WindowCatalog`。**
- 已知限制（写进文案而不是绕过）：引导窗口是 key window 时按 `⌃⌥1`，`ax.focusedWindow()` 会因自家 bundle 在 `excludedBundleIDs` 里返回 nil，什么都不会发生——所以键盘卡片明确写"先点一下别的窗口"。Shift-drag 不受影响，是本页的主推路径。

**P5 更多能力（`.more`）**

- 页头：`welcomeMoreTitle`（"吸附之外，还能做这些"）。
- 2×2 卡片（SF Symbol + 标题 + 一句话，快捷键现算）：
  1. `slider.horizontal.3` — `welcomeMoreEditor`："布局编辑器：列、行、2×2，或自由画分区。%@ 打开。"（`editorHotkey`）
  2. `arrow.left.and.right.square` — `welcomeMoreDivider`："分隔杆：两个相邻分区各放一个窗口后，拖动它们之间的缝，一次改两边比例，并保存回布局。"
  3. `square.grid.3x3.square` — `welcomeMoreWorkspaces`："工作区方案：记住每个应用住在哪个分区，%@ 一键全部归位。"（`applyWorkspaceHotkey`）
  4. `pin.fill` — `welcomeMoreQuickAndPin`："%@ 为当前窗口呼出分区编号；悬停标题栏出现置顶按钮，可把窗口固定在最前。"（`quickSnapperHotkey`）
- 按钮 `welcomeMoreOpenEditor`（"打开布局编辑器"）→ `runtime.openEditor()`。编辑器快捷键在 `ShortcutCatalog.trustExemptIDs` 里，未授权也能打开；编辑器面板会盖在引导窗口之上，关闭后（`editorDidClose`）引导仍在原处。

**P6 完成（`.finish`）**

- 页头：`welcomeFinishTitle`（"一切就绪"）、`welcomeFinishBody`（"以下是最常用的快捷键，都可以在设置 → 键盘里改。"）。
- 快捷键表（5 行，`KeyChord.displayCaps` 渲染成胶囊）：吸附到分区 `⌃⌥1…9`、取消吸附 `unsnapHotkey`、布局编辑器 `editorHotkey`、Quick Snapper `quickSnapperHotkey`、快捷键面板 `shortcutsPanelHotkey`。文案来自 `ShortcutCatalog.grouped(from:)` 对应条目的标题 key，不另写一套。
- `登录时启动` 开关（`settingsLaunchAtLogin` 复用）→ `LoginItemController.set(enabled:)`（§6.7）。
- 脚注 `welcomeFinishReopen`："想再看一遍：右键菜单栏图标 → 欢迎引导。"
- 按钮：`打开设置`（次要，→ `runtime.openSettings()`，引导随之关闭并标记完成）、`完成`（主，→ `.finish`）。

### 6.4 重启后续接（不落盘）

权限页的"退出并重新打开"是常见路径（TCC 授权偶尔要重启进程才生效）。不把"当前页"写进 `settings.json`（多一个只在 0.7 秒内有意义的持久字段），而是随进程参数带过去：

```swift
// TrustMonitor
func relaunchApp(arguments: [String] = []) {
    // sleep 0.7; /usr/bin/open -n "<bundle>" --args <arguments…>
}
```

`AppDelegate` 解析 `--welcome-page <raw>` 为 `OnboardingPage(rawValue:)` 放进 `OnboardingLaunchInput.resumePage`；`launchDecision` 见到 `resumePage` 且未完成 → `.welcomeTour`；`initialIndex` 处理"权限页已不存在"的落点（§6.1）。参数解析放在 `#if DEBUG` 之外——这是正式功能不是调试开关。

### 6.5 吸附完成通知（两行接线）

`SnapEngine` 里两处 `runtime.catalog.record(_:displayID:)`（`snap(_:to:)` 与 `.recordUnsnap`）之后各加一行 `runtime.noteUserSnapCompleted()`。`AppRuntime`：

```swift
func noteUserSnapCompleted() { welcome?.handle(.snapCompleted) }
```

`WorkspaceCenter.apply` / Organize 也会 `catalog.record`，但那不是"用户亲手吸附"，**不**接这个通知。

### 6.6 既有权限引导的职责拆分（重命名 + 抽模型）

| 现状 | 变为 | 说明 |
| --- | --- | --- |
| `UI/Onboarding/OnboardingView.swift` | `UI/Onboarding/AccessibilityGuideView.swift` | 类名同步改；新增 `showsHeader: Bool`（引导页里为 false）。逻辑不变。 |
| `OnboardingWindowController` 里的轮询 + Phase 推导 | 新 `AccessibilityGuideModel`（`@MainActor final class`，无窗口） | 持有 `Timer`、`openedSettingsAt`、`hasReportedGranted`；API：`start() / stop() / openSettings() / userSaysEnabled() / relaunch(resumePage:)`；输出 `onPhaseChange: (Phase) -> Void`、`onTrusted: () -> Void`。`tick()` 内容照搬（`refreshTrustChrome()`、14s 转 `needsRelaunch`、授权后调 `runtime.accessibilityGranted()`）。 |
| `OnboardingWindowController` | `AccessibilityGuideWindowController` | 只剩开窗、关窗、`UISession` 进出、把 model 输出转发给 view；`show()` 后授权成功仍 1.2s 自动关闭（独立引导保留今天的体验）。 |
| `AppRuntime.onboarding` | `AppRuntime.accessibilityGuide` | `openAccessibility()`、`accessibilityGuideClosed()`、`teardown()`、`applyLanguage()` 同步改名。 |
| `L10nKey.onboarding*`（24 个） | 不改名 | 引导页复用其中 `onboardingSubtitle`、三步说明、状态行与按钮文案；改名只会制造无意义 diff。 |
| `ShortcutEscapeAction.closeOnboarding`、`ShortcutRouteContext.onboardingIsKey` | 不改名 | 语义扩展为"任一引导窗口是 key"（§6.8）。 |

### 6.7 登录项共享

把 `SettingsWindowController.toggleLogin(_:)` 里的 `SMAppService` 分支抽到 `Services/LoginItemController.swift`：

```swift
@MainActor enum LoginItemController {
    static func set(enabled: Bool, runtime: AppRuntime)   // 写 settings.launchAtLogin + register/unregister + requiresApproval → openSystemSettingsLoginItems()
    static var isRegistered: Bool                          // SMAppService.mainApp.status == .enabled
}
```

设置页和引导完成页都调它；`persistSettings()` 后设置页若已打开，`loginSwitch` 状态同步刷新（`applyLanguage()` 已在做 switch 同步，顺路加一行）。

### 6.8 与现有子系统的互斥（关键正确性点）

| 冲突点 | 现状 | 处理 |
| --- | --- | --- |
| Dock 图标 / Cmd-Tab | `UISession.enterRegular()` 引用计数 | 引导窗口 `show()` 时 `enterRegular()`，`windowWillClose` 时 `leaveRegular()`，**恰好一次**；权限页嵌入的 view 不再单独计数（它不再拥有窗口）。 |
| Escape | `escapeAction` 顺序：录制快捷键 → 快捷键面板 → 编辑器 → QuickSnapper → 分隔杆 → 设置 → **onboarding** → 面板 → 取消吸附 | `runtime.onboardingIsKey = welcome?.isKey == true \|\| accessibilityGuide?.isKey == true`；`closeOnboardingIfOpen()` 关闭是 key 的那一个。引导上按 Escape = 关闭并标记完成（决策 D-4）。Core 不改。 |
| 同时出现两个引导窗口 | `openAccessibility()`（菜单"Enable Accessibility"、设置页"管理权限"、组织/工作区的未授权兜底）会新建独立权限引导 | 引导窗口打开期间：若页序含 `.accessibility` → 跳到该页并 `makeKeyAndOrderFront`；否则才开独立引导。反向：独立引导打开时用户从菜单点"欢迎引导" → 先 `accessibilityGuide?.close()` 再开引导。 |
| 全局快捷键 | Carbon 热键不看 key window | 引导期间全部照常工作。`⌃⌥Z` 打开编辑器、`⌃⌥/` 打开快捷键面板都允许，两者关闭后引导原地不动（它们各自的 `didClose` 只处理自己）。 |
| 吸附目标 | 自家 bundle 在 `AppSettings.default.excludedBundleIDs` | 引导窗口永不成为吸附目标；`PinHoverMonitor` / `PinCenter` 用 `excludingPID: ownPID`，也不会在引导标题栏上出置顶按钮。 |
| Overlay 层级 | `OverlayPanel.level = .screenSaver` | 闪现的分区始终盖在引导窗口（`.normal` / `.floating`）之上，用户在 P2/P4 能看到完整预览。 |
| 权限轮询 | 独立引导 0.5s `Timer` 只在窗口存活期间 | 引导里只在权限页可见期间轮询（`willAppear/willDisappear`）；离开权限页后不再消耗。 |
| 语言切换 | `AppRuntime.applyLanguage()` 分发 | 加 `welcome?.applyLanguage()`；当前页 `applyLanguage()` + 导航按钮 + 步骤点 accessibility label 重算。 |
| 显示器插拔 | `didChangeScreenParametersNotification` | P2/P4 的目标显示器重算；窗口若所在显示器消失，AppKit 会把它挪到主屏，随后 `refresh` 即可。 |
| 锁屏 / 休眠 | `hideAllOverlays()` | 与引导无关；引导是普通窗口不需处理。 |
| VoiceOver | `usesFallbackMenu` 时状态项用系统菜单 | "欢迎引导…" 放在 fallback 菜单（右键菜单 / VoiceOver 菜单）与应用菜单中；控制台面板不加（保持精简）。所有按钮、缩略图格（`setAccessibilityLabel(布局名)`）、步骤点有 accessibility label。 |
| 单测进程 | `applicationDidFinishLaunching` 已用 `XCTestConfigurationFilePath` 提前 return | 不受影响；`ZoneBoxTests` 无 app host。 |

### 6.9 数据模型与持久化

`AppSettings` 新增：

```swift
public var onboardingCompletedVersion: Int      // default 0；decodeIfPresent ?? 0
```

- `SettingsStore.load()` 首启写入 `.default` → 0 → 弹引导。
- 老用户的 `settings.json` 没有该键 → 0 → 升级后弹一次（决策 D-3）。
- `.markCompleted` → `settings.onboardingCompletedVersion = OnboardingPolicy.currentVersion; persistSettings()`。
- `schemaVersion` 不变（加字段是向后兼容的，与 `hoverPinEnabled` 等先例一致）。

不新增任何文件；不写 `UserDefaults`（项目所有偏好都在 `settings.json`）。

### 6.10 入口与接线清单（按文件）

**Core（`ZoneBoxCore`）**

| 文件 | 改动 |
| --- | --- |
| `Domain/Onboarding.swift`（新） | `OnboardingPage`、`OnboardingLaunchInput/Decision`、`OnboardingPolicy`、`OnboardingFlowState/Event/Effect`、`OnboardingFlowReducer`、`OnboardingNavigation` |
| `Domain/AppSettings.swift` | `onboardingCompletedVersion` 字段 + 解码 |
| `Domain/L10n.swift` | `welcome*` 键（约 40 个，见 §6.11）、`menuWelcomeTour`、`settingsWelcomeTour`、`settingsShowWelcomeTour`；en / zh-Hans 各一份 |
| `Services/Logging.swift` | `Log.onboarding` |

**App（`ZoneBox`）**

| 文件 | 改动 |
| --- | --- |
| `UI/Onboarding/WelcomeWindowController.swift`（新） | 窗口、`pageHost`、导航栏、步骤点、状态机驱动、`UISession`、`applyLanguage`、`handle(_ event:)` |
| `UI/Onboarding/WelcomePages.swift`（新） | `WelcomePage` 协议 + `WelcomeIntroPage` / `WelcomeMorePage` / `WelcomeFinishPage`（静态为主） |
| `UI/Onboarding/WelcomeLayoutsPage.swift`（新） | 缩略图网格、去重选择、闪现 |
| `UI/Onboarding/WelcomeFirstSnapPage.swift`（新） | 方式卡片、状态行、显示分区按钮 |
| `UI/Onboarding/WelcomeAccessibilityPage.swift`（新） | 包装 `AccessibilityGuideView` + `AccessibilityGuideModel` |
| `UI/Onboarding/AccessibilityGuideView.swift`（← `OnboardingView.swift`，`git mv`） | 改类名；`showsHeader` |
| `UI/Onboarding/AccessibilityGuideModel.swift`（新） | 从旧控制器抽出的轮询与 Phase 逻辑 |
| `UI/Onboarding/AccessibilityGuideWindowController.swift`（← `OnboardingWindowController.swift`，`git mv`） | 瘦身为开窗/关窗/转发 |
| `App/AppRuntime.swift` | `welcome` / `accessibilityGuide` 属性；`start()` 改走 `launchDecision`；`openWelcomeTour(resume:)`、`welcomeDidClose()`、`markOnboardingCompleted()`、`noteUserSnapCompleted()`、`previewZones(on:)`；`onboardingIsKey` / `closeOnboardingIfOpen()` 覆盖两窗；`openAccessibility()` 的互斥（§6.8）；`teardown()` / `applyLanguage()` 补分发 |
| `App/AppDelegate.swift` | 解析 `--welcome-page`（正式）；`#if DEBUG` 下 `--show-welcome` / `--skip-welcome` |
| `App/MenuBarController.swift` | fallback 菜单与应用菜单加 "欢迎引导…"（紧随 "键盘快捷键"）；`pulseStatusItem()` |
| `UI/Settings/SettingsWindowController.swift` | 通用分组加一行（`questionmark.circle` / `settingsWelcomeTour` / 按钮 `settingsShowWelcomeTour`）；`toggleLogin` 改调 `LoginItemController` |
| `Services/LoginItemController.swift`（新） | §6.7 |
| `Services/SnapEngine.swift` | 两处 `noteUserSnapCompleted()` |
| `Services/TrustMonitor.swift` | `relaunchApp(arguments:)` |

**工程与文档**

- `project.yml` 不需改（`ZoneBox/UI/Onboarding` 与 `ZoneBox/Domain` 都是目录级 source）；新增/重命名文件后跑 `make project`（`xcodegen generate`）。
- `README.md` "Use it" 第 1–2 步改为："首次启动会弹出欢迎引导……"，并在菜单说明里加 "Welcome Tour…"。
- 本文档状态在实现后更新为"已实现"。

### 6.11 文案键（L10nKey）

命名前缀 `welcome`（与既有 `onboarding*` = 权限引导区分）。下面是完整清单与建议文案，实施时按 `L10n.english` / `L10n.chinese` 两张表落地；含占位符的走 `String(format:locale:)` 辅助方法（参照 `L10n.organizeNeedsSpace`）。

| Key | en | zh-Hans |
| --- | --- | --- |
| `welcomeWindowTitle` | Welcome to ZoneBox | 欢迎使用 ZoneBox |
| `welcomeSkip` | Skip Tour | 跳过引导 |
| `welcomeBack` | Back | 上一步 |
| `welcomeContinue` | Continue | 继续 |
| `welcomeSkipForNow` | Skip for Now | 暂时跳过 |
| `welcomeDone` | Done | 完成 |
| `welcomeStepOf` | Step %d of %d | 第 %d 步，共 %d 步 |
| `welcomeIntroTitle` | Welcome to ZoneBox | 欢迎使用 ZoneBox |
| `welcomeIntroSubtitle` | Draw zones on your screen, then snap windows into them with a drag or a keystroke. | 在屏幕上划出分区，拖一下或按个快捷键，窗口就吸附进去。 |
| `welcomeIntroMenuBar` | ZoneBox lives in the menu bar, next to the clock. There is no Dock icon. Left-click the icon for the panel, right-click for the menu. | ZoneBox 常驻菜单栏（时钟旁边），没有 Dock 图标。左键点图标打开面板，右键打开菜单。 |
| `welcomeIntroLocate` | Show Me | 指给我看 |
| `welcomeLayoutsTitle` | Zones are where windows land | 分区就是窗口的落点 |
| `welcomeLayoutsBody` | A layout is a set of numbered zones for one display. Pick a starting layout. You can change it or draw your own later. | 一套布局就是一个显示器上的一组带编号分区。先选一个起始布局，之后随时可以改，或者自己画。 |
| `welcomeLayoutsPerDisplay` | Each display keeps its own layout. | 每个显示器各自记住一套布局。 |
| `welcomeLayoutsCurrent` | Current: %@ | 当前：%@ |
| `welcomeAccessTitle` | Allow ZoneBox to move windows | 允许 ZoneBox 移动窗口 |
| `welcomeSnapTitle` | Snap your first window | 吸附第一个窗口 |
| `welcomeSnapBody` | Pick any of these and try placing a window in a zone. | 三种方式任选一种，试试把任意窗口放进一个分区。 |
| `welcomeSnapShiftDrag` | Drag a window by its title bar, hold Shift, and drop it on a zone. | 按住标题栏拖动窗口，同时按住 Shift，放到分区上。 |
| `welcomeSnapRightClick` | Right-click once while dragging to show the zones. | 拖动时按一下右键，也会显示分区。 |
| `welcomeSnapKeyboard` | Click another window first, then press %@. | 先点一下别的窗口，再按 %@。 |
| `welcomeSnapWhileArmed` | While zones are showing, press 1–9 to pick one. | 分区显示时，按 1–9 直接落到对应编号。 |
| `welcomeSnapShake` | Shaking the title bar while dragging also shows the zones. | 拖动时左右晃动标题栏也能呼出分区。 |
| `welcomeSnapShowZones` | Show Zones on This Display | 在这个屏幕上显示分区 |
| `welcomeSnapNeedsAccess` | Snapping is paused until Accessibility is on. | 辅助功能未开启，吸附暂时不可用。 |
| `welcomeSnapGoToAccess` | Turn It On | 去开启 |
| `welcomeSnapWaiting` | Waiting for your first snap… | 等待你的第一次吸附… |
| `welcomeSnapDone` | Snapped! Press %@ to put the window back. | 成功！按 %@ 可以把窗口放回原处。 |
| `welcomeMoreTitle` | Beyond snapping | 吸附之外，还能做这些 |
| `welcomeMoreEditor` | Layout Editor: columns, rows, 2×2, or draw zones freely. Open with %@. | 布局编辑器：列、行、2×2，或自由画分区。%@ 打开。 |
| `welcomeMoreDivider` | Divider handles: snap two neighbors, then drag the seam between them to resize both and save the ratio. | 分隔杆：相邻两个分区各放一个窗口后，拖动它们之间的缝，一次改两边比例并保存回布局。 |
| `welcomeMoreWorkspaces` | Workspaces: remember which app lives in which zone, then bring them all back with %@. | 工作区方案：记住每个应用住在哪个分区，%@ 一键全部归位。 |
| `welcomeMoreQuickAndPin` | %@ shows zone numbers for the focused window. Hover a title bar to pin a window on top. | %@ 为当前窗口呼出分区编号；悬停标题栏出现置顶按钮，可把窗口固定在最前。 |
| `welcomeMoreOpenEditor` | Open Layout Editor | 打开布局编辑器 |
| `welcomeFinishTitle` | You're all set | 一切就绪 |
| `welcomeFinishBody` | These are the shortcuts you'll use most. Change any of them in Settings → Keyboard. | 以下是最常用的快捷键，都可以在设置 → 键盘里改。 |
| `welcomeFinishReopen` | To see this tour again: right-click the menu bar icon → Welcome Tour. | 想再看一遍：右键菜单栏图标 → 欢迎引导。 |
| `welcomeFinishOpenSettings` | Open Settings | 打开设置 |
| `menuWelcomeTour` | Welcome Tour… | 欢迎引导… |
| `settingsWelcomeTour` | Welcome tour | 欢迎引导 |
| `settingsWelcomeTourDetail` | Replay the first-launch walkthrough. | 重看首次启动的分步引导。 |
| `settingsShowWelcomeTour` | Show Tour | 查看引导 |

复用不新增：`onboardingSubtitle`（权限页正文）、`onboardingStep1–3*`、`onboardingStatus*`、`onboardingOpenSettings*`、`onboardingIveTurnedItOn`、`onboardingQuitRelaunch*`、`settingsLaunchAtLogin`、`layoutDisplayName`、快捷键条目标题（`ShortcutCatalog` 内既有 key）。

## 7. 边界情况

| 场景 | 行为 |
| --- | --- |
| 首启 + 未授权（最常见） | 6 页全出。P3 授权成功 → 状态行绿勾、主按钮变"继续"；不自动翻页。 |
| 首启 + 已授权 | 5 页（无 P3）。P4 直接进入"等待第一次吸附"。 |
| P3 点"退出并重新打开" | `relaunchApp(arguments: ["--welcome-page","firstSnap"])`；重启后 `completedVersion` 仍为 0 → `.welcomeTour`；已授权则页序无 P3，`initialIndex` 落到 P4。 |
| 引导打开期间权限被撤销（系统设置里手动关） | P3 若在页序里，轮询发现 → `.trustChanged(false)` → 状态行回到 `needsPermission`；P4 状态行切到"未开启"。`refreshTrustChrome()` 照常把菜单栏图标变橙。 |
| 用户在 P2 选了布局后又点"上一步" | 指派已经持久化（`saveLayout` 即写盘）；再进 P2 默认选中它。引导不做"撤销"。 |
| P2 的模板与用户既有布局几何相同但名字不同（重入场景） | `matchingEditorPresetIndex` 按几何匹配 → 选中既有布局、不新建。名称显示用既有布局的名字。 |
| P4 用户吸附发生在**另一个显示器** | `noteUserSnapCompleted()` 不分显示器，一样算成功——目标是"学会吸附"，不是"吸附到这块屏"。 |
| P4 期间用户用 `⌃⌥U` 取消吸附 | 不撤销 `didSnap`；成功状态保留。 |
| 引导打开时从菜单点"Enable Accessibility" / 设置页"管理权限" | 不开第二个窗口：页序含 P3 → 跳到 P3 并置前；否则开独立引导（§6.8）。 |
| 独立权限引导打开时从菜单点"欢迎引导…" | 先关独立引导，再开引导窗口（避免两处轮询、两次 `enterRegular`）。 |
| `--show-welcome` 且已完成 | 照常弹出；关闭时再次写入 `currentVersion`（幂等）。 |
| `--skip-welcome` 且首启未授权 | 落到 `.accessibilityGuide`（今天的行为），便于脚本化验证权限流程。 |
| 未来 `currentVersion` 升到 2 | 所有 `completedVersion == 1` 的用户重新看到引导。若只想展示"新功能"，在 `pages(trusted:)` 加 `completedVersion` 参数筛页即可（§12）。 |
| VoiceOver 开启 | 状态项走系统菜单（`usesFallbackMenu`），"欢迎引导…" 在其中；引导内所有控件可达；`⌃⌥` 系热键若被 `ShortcutVoiceOverPolicy` 暂停，P4/P6 的快捷键文案仍显示绑定值（与快捷键面板一致），不做特殊处理。 |
| 窗口所在显示器被拔掉 | AppKit 迁窗到主屏；`didChangeScreenParametersNotification` → 当前页 `refresh`，目标显示器按新位置重算。 |
| 极小屏（1280×800） | 760×560 固定窗口可完整显示；不做自适应缩放。 |

## 8. 性能预算

- 静息：引导关闭后零常驻对象（`welcome = nil`），无定时器、无观察者残留（页面 `willDisappear` 与 `windowWillClose` 双保险）。
- 打开：6 张 148×92 缩略图渲染 < 5ms（`LayoutThumbnailRenderer` 是纯 `NSBezierPath`）；窗口构建一次性 < 50ms。
- 权限页：0.5s 轮询（`AXIsProcessTrusted` + 最多一次 `probeAX`），与现有独立引导相同，仅在该页可见时运行。
- 吸附检测：直接函数调用，零开销。
- 闪现分区：复用 `flashZones` 路径（`resolveLayout` 微秒级 + `orderFront`）。

## 9. 测试方案

Core（无 AppKit，进 `ZoneBoxTests`）：

1. **`OnboardingPolicyTests`**（新）
   - `launchDecision`：`(completed 0, trusted false)` → tour；`(0, true)` → tour；`(1, false)` → accessibilityGuide；`(1, true)` → none；`forceTour` 覆盖已完成；`suppressTour` + 未授权 → accessibilityGuide；`resumePage` + 已完成 → none（不能靠参数绕过完成标记之外的规则——只有 `forceTour` 可以）。
   - `pages(trusted:)`：false → 6 页含 `.accessibility`；true → 5 页不含。
   - `initialIndex`：nil → 0；`.firstSnap` 在 6 页 → 3、在 5 页 → 2；`.accessibility` 在 5 页（已被移除）→ 落到 `.firstSnap` 的下标。
2. **`OnboardingFlowReducerTests`**（新）
   - 逐页 `.next` 到最后一页再 `.next` → `[.markCompleted, .close]`；首页 `.back` → 空。
   - `.skip` / `.closeRequested` / `.finish` 在任意页 → `[.markCompleted, .close]`。
   - `.trustChanged(true)` 只在值变化时产生 `.refreshCurrentPage`；重复发送不产生。
   - `.snapCompleted` 在 `.firstSnap` 页 → `refresh`；在其他页 → 置 `didSnap` 但无 effect；第二次 → 无变化。
   - `OnboardingNavigation.primaryTitle`：权限页 + 未授权 → `.welcomeSkipForNow`；权限页 + 已授权 → `.welcomeContinue`；末页 → `.welcomeDone`。
3. **`SettingsStoreTests`** 补充：`{"schemaVersion":1}` 解出 `onboardingCompletedVersion == 0`；设为 1 后 encode/decode 往返。
4. **`L10nTests`** 补充：抽查 `welcomeIntroTitle`、`menuWelcomeTour` 双语。既有的 `testEveryKeyHasBothLanguages` 遍历 `L10nKey.allCases`，新键漏译任一语言会直接失败，无需再加断言；`testOnboardingCopyDoesNotMentionXcode` 同样自动覆盖新文案。
5. **`ShortcutCatalogTests`** 不需改：`escapeAction` 的 `onboardingIsKey` 分支已有覆盖。

手工验收清单：

- 删除 `~/Library/Application Support/com.fancyzone.app.debug/settings.json` 后启动（未授权）→ 6 页引导出现，Dock 出现 ZoneBox 图标；关闭后 Dock 图标消失（`UISession` 归零）。
- P1 "指给我看" → 菜单栏图标闪三下。
- P2 点 "Priority 3" → 屏幕上闪现 3 个编号分区 1.6s；右键菜单 Layouts 子菜单中 Priority 3 被勾选且**没有**出现重复的 Columns 2。
- P3 打开系统设置并授权 → 5 秒内状态行变绿、菜单栏警告三角消失、主按钮变"继续"；不自动翻页。
- P3 "退出并重新打开" → 重启后直接落在 P4，页序无 P3，步骤点显示 3/5。
- P4 Shift-drag 任意窗口进分区 → 状态行 1 秒内变"成功"；`⌃⌥U` 后成功状态保留。
- P4 引导窗口为 key 时按 `⌃⌥1` → 无动作（预期）；点别的窗口再按 → 吸附成功。
- P5 "打开布局编辑器" → 编辑器覆盖出现；Escape 关闭编辑器后引导仍在。
- P6 打开"登录时启动" → 系统设置 → 通用 → 登录项 中出现 ZoneBox；设置页 General 的开关同步为开。
- 任意页按 Escape → 引导关闭；重启不再弹出；右键菜单 "欢迎引导…" 与 设置 → 通用 → "查看引导" 都能重新打开。
- 已完成引导 + 撤销权限后启动 → 只弹独立权限引导（与当前版本一致）。
- 引导打开时切换系统语言（或菜单 Language）→ 当前页与导航栏文案即时切换。
- VoiceOver 开启：右键菜单含 "欢迎引导…"；引导内 Tab 可遍历所有按钮与缩略图格。

## 10. 实施拆分（建议 3 个 PR）

1. **PR-1 Core**：`Domain/Onboarding.swift`、`AppSettings.onboardingCompletedVersion`、全部 `welcome*` 文案、`Log.onboarding`、`OnboardingPolicyTests` / `OnboardingFlowReducerTests` / `SettingsStoreTests` / `L10nTests` 补充。无 UI 风险，`make test` 可独立通过。
2. **PR-2 权限引导拆分 + 引导窗口**：`git mv` 重命名两文件、抽 `AccessibilityGuideModel`、`WelcomeWindowController` + 五个页面文件、`LoginItemController`、`AppRuntime` / `AppDelegate` / `MenuBarController` / `SettingsWindowController` / `SnapEngine` / `TrustMonitor` 接线、`make project`、README。验证 §9 手工清单。
3. **PR-3 打磨**：P4 的 Core Animation 迷你演示（一个圆角矩形滑进分区、循环，`CABasicAnimation`，无资源文件）；P1 模拟菜单栏改为按当前外观取色；步骤点 hover 显示页名；本文档状态改"已实现"。

## 11. 决策记录

| # | 决策 | 理由 |
| --- | --- | --- |
| D-1 | 新建独立引导窗口，而不是扩展现有权限引导 | 权限引导只在未授权时弹；分页骨架与 4 Phase 逻辑分离更清晰（§4） |
| D-2 | 权限页复用 `AccessibilityGuideView`，把轮询抽成 `AccessibilityGuideModel`，独立权限引导保留 | TCC 流程（14s 转 relaunch、`probeAX`、`accessibilityGranted()` 只触发一次）是踩过坑的逻辑，不复制第二份 |
| D-3 | 老用户升级后也看一次引导 | `settings.json` 无字段 → 0；0.2.x 用户量小，且引导本身能介绍近期新增的分隔杆/工作区；比"猜测谁是老用户"（例如看 `store.json` 布局数）可靠 |
| D-4 | 任何方式关闭都记为已完成 | 可预测；避免"红叉关掉后每次启动都弹"的骚扰；重入入口在菜单与设置两处 |
| D-5 | 页序在流程开始时固定，中途授权不增删页 | 步骤点数量不跳变；授权状态用 `.trustChanged` 改页面内容 |
| D-6 | 授权成功不自动翻页 | 用户可能正在看系统设置，自动翻页会丢上下文；独立权限引导保留 1.2s 自动关闭 |
| D-7 | 重启续接用进程参数 `--welcome-page`，不落盘 | 只在 0.7 秒内有意义的状态不该进 `settings.json` |
| D-8 | 第一次吸附检测用 `SnapEngine` 两个落点的直接通知，不轮询 `WindowCatalog` | 确定、零开销；工作区归位/Organize 的 `record` 不算"用户亲手吸附" |
| D-9 | P2 目标显示器 = 引导窗口所在显示器 | 比鼠标位置稳定；与用户"我在这块屏上看引导"的直觉一致 |
| D-10 | 不介绍 Organize、不申请屏幕录制 | 前者入口已下线；后者按需申请是既有设计 |
| D-11 | 控制台面板不加入口 | 面板寸土寸金；右键菜单 + 设置页两处足够 |
| D-12 | 快捷键文案全部从 `settings` 现算 | 用户改过绑定后引导不说谎；与快捷键面板同源 |

## 12. 未来扩展

- **"新版本有什么新功能"**：`pages(trusted:completedVersion:)` 按版本筛出新增页；`currentVersion` +1 即可让老用户只看新增内容。
- **P4 动效**：Core Animation 迷你演示（PR-3）；若日后引入资源管线，可换成录屏 GIF。
- **按显示器数量分支**：检测到 ≥2 显示器时，P2 增加一句"当前在为「<显示器名>」选布局"并允许切换目标显示器。
- **工作区方案的引导式首捕获**：在 P5 工作区卡片上加"现在保存一套"→ `workspace.capture(name:)`，需要先有 ≥2 个已吸附窗口，可用 `catalog` 判定后再显示按钮。
- **分隔杆的交互式演示**：P5 检测到相邻两分区各有一窗时，高亮把手位置（`DividerController` 已能算出 `DividerHandleSpec`）。
- **首启后 24 小时内的"你还没试过 X"提示**：需要轻量的使用状态（`didUseEditor` 等），在有明确需求前不做。
