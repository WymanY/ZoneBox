# ZoneBox 工作区方案（Workspace Profiles）技术设计

| 字段 | 值 |
| --- | --- |
| **标题** | 多应用固定布局的一键捕获与一键归位 |
| **状态** | 设计稿（未实现） |
| **日期** | 2026-09-02 |
| **作用范围** | 运行时（真实窗口的批量归位 + 新窗口自动进区），跨全部显示器 |
| **关联文档** | `docs/design.md`（整体架构与"纯函数进 Core、只测 reducer/几何"原则）、`docs/runtime-divider-design.md`（同类设计的写法基准，其 §6.6 的 `WindowCatalog` 扩展与本方案共用） |

---

## 1. 背景与问题

用户日常有一组固定搭配的应用（例如：编辑器占左侧大区、浏览器右上、终端右下），并希望它们**长期保持同一种布局**。当前 ZoneBox 只支持逐窗口操作：

1. 重启、应用更新、会议投屏、插拔显示器之后，窗口位置全乱，需要对每个窗口 Shift-drag 或按 `Control+Option+数字` 重新贴一遍；
2. ZoneBox 记住了"布局长什么样"（`StoreDocument.layouts` + 每显示器 `assignments`），但**不记得"哪个应用住在哪个 zone"**，`WindowCatalog.membership` 只是运行时内存态，重启即失；
3. 已被砍掉入口的 Organize（`WindowOrganize.isPubliclyAvailable = false`）虽然能批量摆放，但它按**窗口数量**套模板（2 窗 Split 65/35、4 窗 Grid 2×2……），不认应用身份，摆出来的不是用户想要的那套固定搭配。

目标体验：**把当前摆好的整桌排布存成一个"工作区方案"；之后任何时刻一个快捷键，所有应用窗口回到各自的 zone；方案生效期间，这些应用新开的窗口自动进区；方案里的应用没开的，自动帮忙启动并归位。**

## 2. 目标 / 非目标

### 目标

1. **捕获**：一个动作把"当前整桌排布"（每个活跃显示器上：当前布局 + 每个应用窗口落在哪个 zone）存为命名方案，可存多套。
2. **一键归位（手动，v1 核心）**：快捷键 / 菜单应用某方案——跨全部显示器，把所有匹配窗口事务性地批量移回各自 zone；复用 `WindowOrganizeExecutor` 的回滚与顽固窗口处理。
3. **缺失应用自动启动**：方案里的应用没在运行时自动启动，窗口出现后补位；有超时和反馈。
4. **跟随模式（自动，阶段 4）**：方案处于激活态时，方案内应用**新开**的窗口自动进入其指定 zone；用户手动拖走的窗口绝不强拉回。
5. 多显示器：方案按显示器分节存储，显示器插拔后靠 `DisplayIdentity.bestMatch` 重识别；未接的节跳过并提示。
6. 不破坏既有交互：拖拽贴靠、QuickSnapper、编辑器、Pin、分隔杆（若已实现）全部行为不变。

### 非目标（v1 明确不做）

- 按窗口标题/文档区分同应用多窗口的**语义**匹配（v1 只按 z-order 顺序消费，标题正则见 §12）。
- macOS Space（虚拟桌面）级方案；`SpaceKey.spaceUUID` 字段已预留但 v1 恒为 nil。
- 方案的定时/场景自动切换（接显示器自动应用等，见 §12）。
- 最小化窗口的自动还原、隐藏应用的 unhide（v1 当缺失处理，见 §8）。
- 规则的图形化逐条编辑（v1 通过"重新捕获"整体更新，设置页只做重命名/删除/开关）。

## 3. 现状盘点（可复用的既有能力）

| 能力 | 位置 | 说明 |
| --- | --- | --- |
| 批量改帧事务引擎 | `Domain/WindowOrganize.swift` → `WindowOrganizeExecutor.execute` | 逐窗写帧、任一拒绝则整批回滚、可替换计划重试、剔除顽固窗口后续跑。**归位执行层直接复用，只需新增一个 acceptance 策略参数（§7.3）。** |
| 顽固窗口行为分类与缓存 | `WindowOrganize.behavior` + `AppRuntime.organizeBehaviorCache` | compliant / sizeConstrained / positionConstrained / immutable / unstable 五态判定；缓存避免反复试探网易云音乐这类窗口。 |
| 窗口枚举（z-order） | `CGWindowQuery.windows(excludingPID:)` + `AccessibilityClientLive.resolveAsync(ref:)` | `AppRuntime.snappableWindows(on:)` 已示范"CG 列表 → AX 解析 → 显示器过滤"，front-to-back 顺序天然可用作多窗口消费顺序。 |
| 写窗口帧 | `AXFrameMutator.setFrame` | 已处理 AXEnhancedUserInterface、min/max clamp、3 次重试；跨显示器移动直接可用（全局 AX 坐标）。 |
| 帧到位判定 | `WindowOrganize.didApply(_:to:sizeTolerance:originTolerance:)` | 捕获阶段"窗口是否贴在某 zone"复用同一容差比较。 |
| 布局 → 像素帧 | `resolveLayout` + `AppRuntime.cachedResolvedZones` | 输入 workAreaAX + gutter，输出 zone 帧，带缓存。 |
| 持久化 | `Services/LayoutStore.swift` + `StoreDocument`（`Domain/DisplayIdentity.swift`） | `decodeIfPresent` + 默认值的前后兼容模式已成惯例（`recentLayoutIDs` 即先例），新增 `profiles` 同法。 |
| 显示器重识别 | `DisplayIdentity.score/bestMatch` + `DisplayWatcher.refresh` | 方案节以 `DisplayIdentity.ID`（持久 UUID）为键，插拔后自动对上。 |
| 贴靠归属记录 | `Services/WindowCatalog.swift` | 归位成功后写 `UnsnapRecord` + membership，`snapAdjacent` / 同 zone 轮换 / unsnap 语义自然衔接。 |
| 结果反馈 HUD | `OrganizeFeedbackController` + `L10n.organize*` | "部分归位/已跳过/恢复" 的 toast 样板与文案结构直接复用。 |
| 应用生命周期观察 | `AppRuntime.observeSystem` 已挂 `didTerminateApplicationNotification` | 补一个 `didLaunchApplicationNotification` 观察者即可，位置现成。 |
| 快捷键与自定义 | `HotkeyCenter` + `ShortcutCatalog`（`ShortcutCustomizationID`） | 新增一条 chord 的注册、校验、设置页行、冲突检测全走既有管线。 |
| 菜单入口 | `MenuBarController.makeMenu` / `MenuBarConsoleController` | Layouts 子菜单的构建模式（representedObject + state 勾选）照搬。 |

**结论：执行、几何、持久化、反馈全部有现成轮子。新增工作集中在"数据模型 + 两个纯函数（捕获推断、归位计划）+ 一个编排服务（WorkspaceCenter）+ 入口"。**

## 4. 方案选型

| 方案 | 描述 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- | --- |
| **A. 隐式 app-zone 记忆** | 仿 FancyZones "app zone history"：每次手动贴靠都记 `bundleID → zone`，应用新窗口/一键恢复都按最后记录走 | 零配置 | 隐式状态易被日常临时操作污染（临时把浏览器拖去投屏区，记录就被改了）；只有"一套"记忆，无法在"编码/写作/会议"多套排布间切换；无整桌快照概念 | 否决（其"新窗口自动进区"的体验由方案 B 的跟随模式覆盖，且以显式方案为准绳，不受日常操作污染） |
| **B. 显式工作区方案（本设计）** | 用户显式捕获/命名/应用；`bundleID → zoneID` 规则按显示器分节持久化 | 意图明确、可多套、可预测；捕获即配置，无需手填规则 | 需要用户主动存一次 | **采用** |
| **C. 导出 AppleScript / Shortcuts** | 把排布导出成系统脚本 | 无新 UI | 依赖各应用脚本支持，普适性差；体验割裂 | 否决 |
| **D. 复活 Organize 按窗口数套模板** | 打开 `isPubliclyAvailable` | 零新代码 | 不认应用身份，结果不是用户那套固定搭配 | 否决（但其执行器全量复用） |

## 5. 总体架构

```
AppRuntime
 ├─ engine:    SnapEngine            （已有，单窗贴靠）
 ├─ overlay:   OverlayController     （已有，flashZones 复用做归位成功反馈）
 ├─ catalog:   WindowCatalog         （已有，归位后写 membership）
 ├─ workspace: WorkspaceCenter       （新增，Services/WorkspaceCenter.swift）
 │    ├─ capture()                    整桌捕获 → WorkspaceProfile
 │    ├─ apply(profile)               分节事务归位（复用 WindowOrganizeExecutor）
 │    ├─ pending: PendingPlacementBook 待归位登记簿（启动中的应用 / 跟随模式）
 │    └─ census: 1Hz 窗口普查          仅在 pending 非空或跟随模式激活时运行
 └─ document:  StoreDocument
      └─ profiles: [WorkspaceProfile] （新增字段）+ activeProfileID

纯逻辑（进 ZoneBoxCore，可无 AppKit 单测）：
 Domain/WorkspaceProfile.swift   数据模型 + StoreDocument 扩展
 Domain/ProfileCapture.swift     窗口帧 × zone 帧 → 规则推断
 Domain/ProfilePlan.swift        规则 × 候选窗口 → placements / missing / pending
```

`WorkspaceCenter` 与 `PinCenter` 平级，持 `unowned var runtime`，生命周期在 `AppRuntime.start/teardown` 接线。

## 6. 数据模型与持久化

```swift
public struct AppPlacementRule: Codable, Hashable, Sendable {
    public var bundleID: String
    public var zoneID: UUID        // 主键：布局内 zone 的稳定 id
    public var zoneNumber: Int     // zoneID 失效（布局被编辑）时按编号回退
}

public struct ProfileSection: Codable, Hashable, Sendable {
    public var space: SpaceKey     // 沿用 LayoutAssignment 的键（displayID + 预留 spaceUUID）
    public var layoutID: Layout.ID
    public var rules: [AppPlacementRule]  // 有序；同 bundleID 允许多条（多窗口应用）
}

public struct WorkspaceProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sections: [ProfileSection]
    public var launchMissingApps: Bool     // 默认 true
    public var autoPlaceNewWindows: Bool   // 跟随模式，默认 true（阶段 4 前忽略）
    public var createdAt: Date
    public var updatedAt: Date
}
```

`StoreDocument` 新增：

```swift
public var profiles: [WorkspaceProfile]          // decodeIfPresent ?? []
public var activeProfileID: WorkspaceProfile.ID? // 跟随模式锚点，decodeIfPresent
```

- `schemaVersion` 保持 1：旧版本读新文件时未知键被 `Codable` 忽略，不触发 `load()` 的损坏回退；代价是旧版本一旦覆写保存会丢掉 `profiles`（与 `recentLayoutIDs` 引入时的取舍一致，接受并在此注明）。
- 归一化（仿 `pruneRecentLayoutIDs`，在 `init(from:)` 与变更后调用）：剔除引用不存在布局的 section、剔除空 section、剔除无 section 的 profile、`activeProfileID` 悬空则置 nil。
- `deleteLayout(id:)` 级联：清掉引用该布局的 section（菜单确认弹窗文案追加提示"N 个工作区方案将受影响"）。

**为什么规则键是 `bundleID` 而不是 `WindowIdentity`**：pid/windowNumber 重启即变，跨会话唯一稳定且用户可理解的身份就是应用；同应用多窗口靠规则顺序 × z-order 消费（§7.2）。

## 7. 详细设计

### 7.1 捕获（ProfileCapture，纯函数）

```swift
public enum ProfileCapture {
    public struct WindowSample: Equatable, Sendable {
        public var identity: WindowIdentity   // bundleID 必须非 nil，否则跳过
        public var frameAX: CGRect
    }
    /// windows 按 z-order（front-to-back）传入；返回按 (zone.number, z-order) 排序的规则
    public static func rules(
        windows: [WindowSample],
        zones: [ResolvedZone]
    ) -> [AppPlacementRule]
}
```

窗口 → zone 判定（对每个窗口取第一个命中）：

1. **精确在位**：`WindowOrganize.didApply(frameAX, to: zone.frameAX, sizeTolerance: 28, originTolerance: 28)`——之前用快捷键/拖拽贴上去的窗口走这条。
2. **多数覆盖**：`intersection(frame, zone.frameAX).area / frame.area ≥ 0.5`，取覆盖率最高的 zone——手摆的"大概在那个区"的窗口也能捕获。
3. 都不满足 → 该窗口不入方案（桌面上飘着的便签、播放器不被绑架）。

调用侧（`WorkspaceCenter.capture()`）：遍历 `displays.workAreas` 中每个活跃显示器，取 `document.layout(for:)` 与 `cachedResolvedZones`，窗口集用 `snappableWindows(on:)` 的现成管线；至少一节非空才成方案，否则 beep。默认名 `工作区 N`（`LayoutEditTransaction.uniqueName` 去重）。

### 7.2 归位计划（ProfilePlan，纯函数）

```swift
public enum ProfilePlan {
    public struct SectionPlan: Equatable, Sendable {
        public var displayID: DisplayIdentity.ID
        public var placements: [WindowOrganizePlacement]   // 直接喂 executor
        public var zoneIDByIdentity: [WindowIdentity: UUID] // 成功后写 catalog membership
    }
    public struct Outcome: Equatable, Sendable {
        public var sections: [SectionPlan]
        public var missingBundleIDs: [String]        // 无在运行窗口可消费的规则
        public var staleRules: [AppPlacementRule]    // zoneID 与 zoneNumber 都失效
        public var skippedDisplayIDs: [DisplayIdentity.ID]  // 显示器未接
    }
    public static func make(
        profile: WorkspaceProfile,
        zonesBySection: [DisplayIdentity.ID: [ResolvedZone]],  // 未接显示器缺席
        candidates: [ProfileCapture.WindowSample]              // 全桌、z-order
    ) -> Outcome
}
```

匹配算法：

1. 候选窗口按 `bundleID` 分组为 FIFO 队列（保持 z-order，最前窗口最先被消费）。**全桌共享一份队列**：双显示器两节都要 Chrome 时各拿一个不同窗口，同一窗口绝不被两条规则占用。
2. 逐节、逐规则：`zoneID` 在该节布局中找 zone；找不到则按 `zoneNumber` 回退；再找不到 → 记入 `staleRules`。
3. 规则从其 bundle 队列 `popFirst()`：拿到 → `WindowOrganizePlacement(identity, zone.frameAX)`；队列空 → 记入 `missingBundleIDs`（去重）。
4. 不在任何规则里的窗口一律不动（与 Organize 的"全场重排"根本区别）。

### 7.3 事务执行与 acceptance 扩展

每节独立跑一次 `WindowOrganizeExecutor.execute`（节间串行，先主屏后副屏）：

- `windows`：该节 placements 覆盖的 `(identity, AXWindow)`，AX 句柄经 `ax.window(matching:)` 解析，解析失败进 `initialSkipped`。
- `makePlan`：`{ actives in WindowOrganizeAttemptPlan(layout: sectionLayout, placements: 原 placements 过滤到 actives, workAreaAX: workAX) }`——zone 帧固定，剔除谁都不影响别人，天然满足 executor "每个 active 必有 placement" 的校验。
- `makeFallbackPlan`：nil（无降级布局的概念，被拒窗口由 executor 主循环剔除后重跑即可）。
- `applyFrame`：复用 `AppRuntime.applyOrganizeFrame`（写帧 + 两次 120ms 采样判稳定性）。
- 行为缓存：读写同一个 `organizeBehaviorCache`，已知 immutable/unstable 的窗口直接进 `initialSkipped`，不再骚扰。

**唯一的 Core 改动**——executor 现有 `accepts()` 对 `sizeConstrained` 仅在"唯一主区"放行，其余触发整批回滚再重排；这是 Organize 语义（模板要重选）。归位语义不同：zone 是用户钦定的，一个终端改不了大小不应让其它五个窗口回滚重来一遍（可见闪动）。故增加参数：

```swift
public enum WindowOrganizeAcceptance: Sendable {
    case organize   // 现状，默认值，Organize 与既有测试零变化
    case placement  // sizeConstrained 一律接受并记 issue；仅 position/immutable/unstable 拒绝
}
public static func execute<Handle>(..., acceptance: WindowOrganizeAcceptance = .organize, ...)
```

成功后收尾（每节）：

1. 每个 move 写 `catalog.record(UnsnapRecord(..., zoneIDs: [zoneID]), displayID:)`——`originalFrameAX` 用 move 的原帧，unsnap / `snapAdjacent` / 同 zone 轮换全部自然工作；
2. `document.assign(layoutID:, to: displayID)` + `markLayoutUsed`——归位隐含"这块屏现在用这套布局"；
3. `flashZones(area:layout:duration: 1.2)` 闪一次确认；
4. 不做 raise/activate 链（保持用户当前焦点，与 Organize 抬升首窗的行为刻意不同）。

全部节完成后：`document.activeProfileID = profile.id`，`persist()`，`menuBar?.reloadMenu()`；issues / skipped / missing 汇总进一条 `OrganizeFeedbackController` toast（挂在鼠标所在屏）。

### 7.4 缺失应用：启动并补位（PendingPlacementBook）

`ProfilePlan.Outcome.missingBundleIDs` 非空且 `profile.launchMissingApps`：

```swift
struct PendingPlacement {
    var bundleID: String
    var zoneID: UUID
    var displayID: DisplayIdentity.ID
    var expiresAt: Date          // now + 15s
}
```

1. 对每个缺失 bundleID：`NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` 找不到 → 直接反馈"未安装"；找到 → `openApplication(at:configuration:)`，`configuration.activates = false`（不抢焦点）。
2. 对应规则（该 bundleID 的全部规则，含多窗口）登记进 `pending`，并启动**普查循环**：1Hz 调 `query.windows(excludingPID:)`（实测 ~1.3ms）＋ 与上一帧 diff。
3. 新窗口的 bundleID 命中 pending → `ax.resolveAsync` → 连续两拍帧稳定（应用启动时常自行挪一次窗）→ 单窗 `setFrame` 到 zone 帧 + 写 catalog → 移除该条 pending。
4. 到期未出窗（LSUIElement、登录弹窗卡住等）→ 移除并追加一条 toast"××未能归位"。
5. pending 清空且跟随模式未激活 → 普查循环停止，零静息开销。

### 7.5 跟随模式（阶段 4，autoPlaceNewWindows）

- 激活条件：`document.activeProfileID` 指向的 profile 开了 `autoPlaceNewWindows`。普查循环常驻 1Hz（与 §7.4 同一循环、同一 diff）。
- 触发：普查发现**新出现**的 `WindowIdentity`，其 bundleID 在活跃 profile 当前显示器可达的规则里 → 取该 bundleID 的**首条规则** zone，两拍稳定后单窗写帧 + 写 catalog。
- 三条纪律（防"绑架感"）：
  1. 只管**新**窗口——已存在窗口哪怕被用户拖走也绝不拉回；
  2. 普查 diff 的基线在每次 apply 后重置为当时全量窗口集；
  3. `engine.isSessionActive`（用户正在拖拽/QuickSnapper）或 `isEditorOpen` 时，本拍跳过，窗口留到下一拍再处理。
- 停用入口：菜单"停用工作区"、应用另一 profile（自动切换锚点）、删除活跃 profile。

### 7.6 入口

| 入口 | 行为 |
| --- | --- |
| 菜单（console + VoiceOver fallback NSMenu 双份，仿 Layouts 子菜单） | "工作区"子菜单：每个 profile 一项（点击即 apply，活跃者打勾）；分隔线；"保存当前排布为工作区…"（弹一个命名 alert）；"更新〈活跃方案〉为当前排布"；"停用自动归位"；"管理…"（跳设置页） |
| 快捷键 | 新增 `applyWorkspaceHotkey`，默认 **Control+Option+P**（keyCode 35，与现有默认 chord 无冲突，仍走 `ShortcutCatalog.validate` 冲突检测）：应用 `activeProfileID` ?? 最近更新的 profile；无 profile 时 beep。`ShortcutCustomizationID` 增加 `applyWorkspace`，设置页 Keyboard 行、L10n（EN + zh-Hans，`L10nTests` 会强制补齐）随管线自动铺开 |
| 多方案选择 HUD（阶段 3 可选） | 复用 QuickSnapper 的 reducer + overlay captureKeys 模式：呼出后按 1…9 选 profile；v1 先不做，菜单已可选 |
| 设置页新 Tab「工作区」 | 列表（名称、显示器数、应用数、`launchMissingApps` / `autoPlaceNewWindows` 开关）、重命名、删除、"用当前排布重新捕获" |

### 7.7 互斥与安全（关键正确性点）

| 冲突点 | 处理 |
| --- | --- |
| 与 Organize / 另一次归位并发 | 复用 `isOrganizingWindows` 这把事务门（`beginOrganizingWindows/finishOrganizingWindows` 提为通用 `beginWindowTransaction`），同一时刻全桌至多一个批量改帧事务 |
| 用户正在拖拽 / QuickSnapper | apply 前检查 `engine.isSessionActive`，活跃则 beep 不执行；跟随模式如 §7.5 跳拍 |
| 编辑器打开 | 与 Organize 相同：beep + 不执行 |
| Accessibility 未授权 | `trust.isTrusted()` 失败 → `openAccessibility()` 引导（与 Organize 相同） |
| 归位进行中显示器插拔 | executor 单节原子；节开始前校验 `displays.isActive(displayID:)`，`didChangeScreenParametersNotification` 里让 pending 重挂显示器（重算 zone 帧），拿不到则丢弃该 pending |
| 应用退出 | 已有 `didTerminateApplicationNotification` → `catalog.drop(pid:)`；pending 里同 bundleID 条目一并清除 |
| 锁屏/休眠 | `hideAllOverlays()` 已有；普查循环在 `screensDidSleep` 暂停、唤醒恢复 |
| 排除名单 | `settings.excludedBundleIDs` 内的应用捕获与归位一律跳过（AX 层已过滤，纯函数层再兜一层） |

## 8. 边界情况

| 场景 | 行为 |
| --- | --- |
| 同应用多窗口（如两个 Chrome 窗） | 捕获生成两条规则（不同 zone）；归位按 z-order 消费：最前窗进第一条规则的 zone。窗口比规则多 → 多余的不动；比规则少 → 差额进 missing（不再启动新实例，只提示） |
| 两条规则指向同一 zone | 合法（堆叠）；catalog membership 使同 zone 轮换（`cycleWindowsInFocusedZone`）直接可用 |
| 窗口最小尺寸 > zone | `AXFrameMutator` clamp 到 minSize，acceptance `.placement` 接受并记 issue，toast 提示"××需要更大空间"（复用 `L10n.organizeNeedsSpace`） |
| 最小化窗口 | `AccessibilityClientLive.makeWindow` 已过滤 AXMinimized → 当缺失处理进 missing 提示；不自动 de-minimize（v1，见 §12） |
| 窗口在别的 Space / 全屏 | CG onScreenOnly 枚举不到 → 当缺失；不做跨 Space 搬运（AX 做不到），提示即可 |
| 应用无 bundleID / LSUIElement 无窗 | 捕获跳过；启动补位走 15s 超时提示 |
| 布局被编辑（zone 增删、重新编号） | `zoneID` 优先精确匹配；被删则 `zoneNumber` 回退（`packedNumbers` 保证 1…N 紧凑）；双失效 → staleRule，toast 建议重新捕获 |
| 布局被删除 | `deleteLayout` 级联清 section（§6），确认弹窗提示受影响方案数 |
| 显示器未接（带着笔记本出门） | 该节跳过 + toast"××显示器未连接，已跳过 N 个窗口"；笔记本内屏节正常归位 |
| 显示器换了但同型号 | `DisplayIdentity.bestMatch` 打分重识别，沿用既有语义，方案无感 |
| apply 时窗口恰好被关闭 | `readFrame` 返回 nil → executor 记 skipped，其余照常 |
| 旧版本 ZoneBox 覆写 store.json | `profiles` 丢失（Codable 忽略未知键后重编码）；接受，与 `recentLayoutIDs` 先例一致 |

## 9. 性能预算

- **静息（无 pending、无跟随模式）**：零开销，无定时器。
- **捕获**：一次 CG 枚举 + N 次 AX resolve/readFrame，与一次 Organize 同量级（< 100ms，8 窗）。
- **归位**：瓶颈是 `setFrame`（每窗 16–50ms，AX 队列串行）+ 判稳采样 240ms/窗 → 8 窗全桌 ≈ 2–3s，executor 期间事务门挡住重入；acceptance `.placement` 把"整批回滚重跑"从常见路径中移除。
- **普查循环**：1Hz × ~1.3ms `CGWindowListCopyWindowInfo`，只在 pending 非空或跟随模式激活时运行；diff 是集合运算，微秒级。

## 10. 测试方案

Core（无 AppKit，进 `ZoneBoxTests`，`make test`）：

1. **`ProfileCaptureTests`**（新）：精确在位命中；50% 覆盖率阈值边界；两 zone 重叠取覆盖率高者；无 bundleID / 不达阈值跳过；输出排序稳定。
2. **`ProfilePlanTests`**（新）：同 bundleID 多规则按 z-order 消费且跨节不重复占用；missing 去重；zoneID → zoneNumber 回退；双失效进 staleRules；未接显示器进 skippedDisplayIDs；placements 与输入 zones 帧一致。
3. **`WindowOrganizeTests`** 补充：`acceptance: .placement` 下 sizeConstrained 不触发回滚、issue 照记；默认参数行为与现有断言完全一致（回归保障）。
4. **`LayoutStoreTests` / StoreDocument**：`profiles` 编解码 round-trip；无 `profiles` 键的旧 JSON 正常解出空数组；归一化剔除悬空 section/profile/activeProfileID；`deleteLayout` 级联。
5. **`ShortcutCatalogTests`**：`applyWorkspace` 的默认 chord、冲突校验、reset 路径。

手工验收清单：

- 双显示器摆好 6 窗 → 捕获 → 全部窗口拖乱、换到另一屏 → 快捷键 → 全部跨屏回位、布局 assignment 同步、flashZones 出现。
- 退出其中两个应用 → 归位 → 应用被自动启动、窗口出现后 2s 内落进各自 zone、无焦点抢占。
- 网易云音乐（sizeConstrained）在方案里 → 其余窗口不回滚不闪动，toast 提示需要更大空间。
- 跟随模式开：新开一个方案内应用窗口 → 自动进区；手动把它拖走 → 不被拉回。
- 拔掉外接屏 → 归位 → 内屏节正常，toast 提示跳过外接屏节。
- Organize（若开发开关打开）与归位互斥，同时触发只跑一个。

## 11. 实施拆分（建议 4 个 PR）

1. **PR-1 Core**：`Domain/WorkspaceProfile.swift`（模型 + StoreDocument 扩展与归一化）、`Domain/ProfileCapture.swift`、`Domain/ProfilePlan.swift`、executor `acceptance` 参数 + 上述全部单测。无 UI 风险。
2. **PR-2 手动闭环**：`Services/WorkspaceCenter.swift`（capture/apply/收尾/反馈）、事务门通用化、菜单"工作区"子菜单（console + fallback）、`applyWorkspace` 快捷键全管线、L10n 文案。**发布即解决"一个个调窗口"的核心痛点。**
3. **PR-3 缺失应用补位**：PendingPlacementBook + 1Hz 普查循环 + 启动/超时/反馈；设置页「工作区」管理 Tab。
4. **PR-4 跟随模式**：activeProfile 语义、新窗口自动进区、三条纪律、（可选）QuickSnapper 式方案选择 HUD。

## 12. 未来扩展

- **标题正则规则**：`AppPlacementRule` 加可选 `titlePattern`，解决"Chrome 的工作窗 vs 娱乐窗"语义区分（FancyZones app rules 同构）。
- **Space 级方案**：`SpaceKey.spaceUUID` 已在键上预留，接私有 CGS API 或 `NSWorkspace.activeSpace` 变化通知。
- **场景自动切换**：接上外接屏 / 时间段 / 手动 Focus 模式 → 自动 apply 对应 profile（`didChangeScreenParametersNotification` 已有挂点）。
- **最小化/隐藏还原**：归位时对 AXMinimized 窗口先 `AXUIElementSetAttributeValue(kAXMinimizedAttribute, false)`、对 hidden 应用 `NSRunningApplication.unhide`。
- **导入导出**：profile 的 JSON 导出/导入，便于多机同步。
