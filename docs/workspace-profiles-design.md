# ZoneBox 工作区（Workspace Profiles）技术设计

| 字段 | 值 |
| --- | --- |
| **标题** | 整桌窗口排布的一键捕获与一键归位 |
| **状态** | 已实现；2026-09-11 由「应用 → 分区」模型改为「应用 → 窗口位置」模型 |
| **日期** | 2026-09-02 初稿 · 2026-09-11 改版 |
| **作用范围** | 运行时（真实窗口的批量归位 + 缺失应用启动补位），跨全部显示器 |
| **关联文档** | `docs/design.md`（整体架构与"纯函数进 Core、只测 reducer/几何"原则）、`docs/runtime-divider-design.md`（`WindowCatalog` 扩展与本方案共用） |

---

## 1. 背景与问题

用户日常有一组固定搭配的应用（例如：左半屏 Chrome、右半屏 Cursor，第二块屏 WeChat 独占），并希望它们**长期保持同一种排布**。重启、应用更新、投屏、插拔显示器之后窗口位置全乱，逐个窗口重新贴一遍很烦。

初版方案把工作区记成「应用 → 当前布局的某个分区」：捕获时把每个窗口对到当前激活布局里覆盖最多的分区，恢复时再把窗口吸进那个分区。实际使用中它保存的是**布局槽位**而不是用户的窗口：右半屏的 Cursor 被记成「优先3等分」的分区 3，独占整屏的 WeChat 被记成「三列」的分区 1，恢复出来与捕获时完全不同。

改版后的原则：**工作区保存的是捕获那一刻每个窗口真实的位置和大小；恢复时原样复现，和当前用哪套布局无关。**

目标体验：把当前摆好的整桌排布存成一个命名工作区；之后任何时刻一个快捷键，所有应用窗口回到各自的位置；工作区里的应用没开的自动启动并补位。

## 2. 目标 / 非目标

### 目标

1. **捕获**：一个动作把「当前整桌排布」（每个有窗口的显示器上：每个可见应用窗口相对该显示器可用区域的归一化矩形）存为命名工作区，可存多套。
2. **一键归位**：快捷键 / 菜单 / HUD 应用某工作区——跨全部显示器，把匹配窗口事务性地批量移回保存的位置；复用 `WindowOrganizeExecutor` 的回滚与顽固窗口处理。
3. **缺失应用自动启动**：工作区里的应用没在运行时自动启动或重新打开，窗口出现后补位；有超时和反馈。
4. **多显示器**：按显示器分节存储；默认保存所有有窗口的显示器，也可只保存指针所在的那一屏；显示器插拔后靠 `DisplayIdentity.bestMatch` 重识别，未接的节跳过并提示。
5. **不与布局耦合**：删除/编辑布局不影响任何工作区；恢复不切换显示器的布局。
6. 不破坏既有交互：拖拽贴靠、QuickSnapper、编辑器、Pin、分隔杆行为不变。

### 非目标

- 按窗口标题/文档区分同应用多窗口的**语义**匹配（只按 z-order 顺序消费，见 §6.2）。
- macOS Space（虚拟桌面）级工作区；`SpaceKey.spaceUUID` 已预留但恒为 nil。
- 场景自动切换（接显示器自动应用等）。
- 「跟随模式」（工作区激活期间新开窗口自动进位）：数据模型不再有分区可跟随，本版不做。
- 规则的图形化逐条编辑（通过「重新捕获」整体更新，设置页只做重命名/删除/开关）。

## 3. 总体架构

```
AppRuntime
 ├─ engine:    SnapEngine                （已有，单窗贴靠）
 ├─ overlay:   OverlayController         （已有，flashWorkspaceFrames 复用做归位确认闪现）
 ├─ catalog:   WindowCatalog             （已有，归位后按落点写 membership）
 ├─ workspace: WorkspaceCenter           （Services/WorkspaceCenter.swift）
 │    ├─ capture / captureImmediately / updateProfileFromCurrent
 │    ├─ apply(profileID:)              分节事务归位（复用 WindowOrganizeExecutor）
 │    ├─ pending: [PendingPlacement]     待归位登记簿（启动中的应用）
 │    └─ census: 1Hz 窗口普查            仅在 pending 非空时运行
 ├─ workspaceSwitcher: WorkspaceSwitcherController（UI/Workspace，HUD 切换器）
 └─ document:  StoreDocument
      └─ profiles: [WorkspaceProfile] + activeProfileID

纯逻辑（ZoneBoxCore，无 AppKit，全部单测）：
 Domain/WorkspaceProfile.swift           数据模型、排布等价、反馈文案
 Domain/WorkspaceProfileMigration.swift  旧「分区」规则 → 位置规则的解码迁移
 Domain/ProfileCapture.swift             可见性判定、窗口 → 归一化位置、范围过滤、重捕获合并
 Domain/ProfilePlan.swift                规则 × 候选窗口 × 实时可用区域 → placements / missing
 Domain/WorkspaceRestore.swift           启动/重开/超时/显示器重映射策略
 Domain/WorkspaceSwitcher.swift          HUD 切换器 reducer
 Domain/WorkspaceLayoutPreview.swift     预览图几何（按保存的位置画窗口）
```

`WorkspaceCenter` 与 `PinCenter` 平级，持 `unowned var runtime`，生命周期在 `AppRuntime.start/teardown` 接线。

## 4. 数据模型与持久化

```swift
public struct AppPlacementRule: Codable, Hashable, Sendable {
    public var bundleID: String
    /// 窗口相对显示器可用区域（visibleFrame，去掉菜单栏/Dock）的归一化矩形，0…1。
    public var frame: NormalizedRect
    public static let matchTolerance: Double = 0.02
    public func matches(_ other: AppPlacementRule, tolerance: Double = matchTolerance) -> Bool
    /// 展示顺序：先按 x 再按 y 分桶，再按 bundleID；存储顺序保持前后层级（front-to-back）。
    public static func readingOrder(_ rules: [AppPlacementRule]) -> [AppPlacementRule]
}

public struct ProfileSection: Codable, Hashable, Sendable {
    public var space: SpaceKey            // displayID + 预留 spaceUUID
    public var rules: [AppPlacementRule]  // 有序（front-to-back）；同 bundleID 允许多条
}

public struct WorkspaceProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sections: [ProfileSection]
    public var launchMissingApps: Bool    // 默认 true
    public var createdAt: Date
    public var updatedAt: Date
}
```

`StoreDocument`：`profiles: [WorkspaceProfile]`（`decodeIfPresent ?? []`）、`activeProfileID: WorkspaceProfile.ID?`（最近应用的工作区，HUD 默认高亮它）。

- **为什么是归一化矩形而不是像素帧**：同一块显示器上精确还原；换分辩率、换 Dock 位置或菜单栏高度时按比例还原，不会把窗口推出屏幕。`NormalizedRect.normalize(_:in:)` 会把超出可用区域的部分裁到 0…1，最小尺寸 0.02。
- **为什么规则键是 `bundleID` 而不是 `WindowIdentity`**：pid/windowNumber 重启即变，跨会话唯一稳定且用户可理解的身份就是应用；同应用多窗口靠规则顺序 × z-order 消费（§6.2）。
- **排布等价**（`WorkspaceProfile.hasSameArrangement`）：忽略节顺序与规则顺序，每条规则在 2% 容差内贪心配对；空工作区永不相等。快捷键「立即保存」用它避免重复保存同一排布。
- **归一化**（`normalizeReferences`）：只剔除没有规则的节和没有节的工作区，`activeProfileID` 悬空则置 nil。**不再**检查布局引用。
- **`deleteLayout(id:)` 不再级联**到工作区；删除布局的确认弹窗也不再提示受影响的工作区数。

### 4.1 旧数据迁移（`WorkspaceProfileMigration`）

初版把规则存成 `{bundleID, zoneID, zoneNumber}` 且节上有 `layoutID`。`StoreDocument.init(from:)` 通过宽松 DTO（`StoredProfile / StoredSection / StoredRule`，`frame`、`zoneID`、`zoneNumber`、`layoutID` 全部可选）解码，再按下列规则转换：

1. 规则已有 `frame` → 原样使用。
2. 否则用节的 `layoutID` 找布局，`LayoutTemplates.thumbnailPanes(for:)` 得到每个分区的画布矩形；先按 `zoneID` 命中，再按 `zoneNumber` 回退，命中的分区矩形即为 `frame`。
3. 两者都无法解析（布局被删、分区不存在）→ 该规则丢弃；节空则丢节；工作区空则丢工作区。

迁移只能拿到分区几何，拿不到当时真实的窗口位置，所以迁移出来的工作区建议重新捕获一次。重新编码后 JSON 里不再出现 `zoneNumber` / `layoutID`；`schemaVersion` 保持 1。

## 5. 捕获

### 5.1 采样与归属（`WorkspaceCenter.captureSections`）

1. `CGWindowQuery.windows(excludingPID:)` 取 WindowServer 前后序的 layer 0 窗口。
2. `ProfileCapture.visibleWindowIdentities` 过滤**可见**窗口：不透明前置窗口覆盖其面积 ≥ 25% 即视为被遮住，不入工作区（贴靠相邻窗口常见的 1pt 接缝不算遮挡）。透明度 ≤ 0.01 的窗口忽略。
3. 排除 `settings.excludedBundleIDs`、无 bundleID 的窗口。
4. 每个窗口按 `DisplayTargetResolver.workArea(containingWindowFrameAX:)` 归到「占其大部分面积」的显示器，一个显示器一节；节内保持 front-to-back。
5. `ProfileCapture.rules(windows:workAreaAX:)`：一条规则一个窗口，`frame = NormalizedRect.normalize(窗口 AX 帧, in: 该显示器可用区域 AX 帧)`。**没有任何分区匹配**：跨两个分区、或根本不理布局的窗口，都原样记下。

### 5.2 多显示器范围

默认保存**所有**有窗口的显示器。只有当 ≥ 2 块显示器上都有可保存窗口、且能确定指针所在显示器时，才提供「只保存这一屏（显示器名）」的选择（`WorkspaceCapturePromptContext.offersDisplayChoice`）：

| 入口 | 范围选择方式 |
| --- | --- |
| 备用 NSMenu「保存当前排布为工作区…」 | `WorkspaceCapturePrompt` 命名弹窗内的复选框；勾选后建议名只列该屏应用 |
| HUD 切换器 `S` → 命名 | 命名框下方同名复选框；键盘 `Tab` 切换；头部提示随之显示「Tab 切换只保存这一屏」；摘要行显示所选范围的应用数/显示器数 |
| 快捷键「立即保存」（默认 ⌃⌥⇧P）、控制台「保存当前排布」按钮 | 无 UI，始终保存全部显示器 |

范围只影响**新建**工作区。「更新为当前排布」（重捕获）按 §5.3 合并。

### 5.3 重捕获合并（`ProfileCapture.mergedRecaptureSections`）

更新已有工作区时只刷新**当前已连接**显示器的节：已连接的节用新捕获替换（该屏没窗口则删掉该节），未连接的节原样保留（在笔记本上单屏更新，不会抹掉外接屏那半）；新出现的显示器追加。若这次什么都没捕到，返回 nil，工作区保持原样并提示「没有可保存的窗口」，**失败的重捕获不会清空工作区**。

### 5.4 命名

建议名由 `WorkspaceProfile.suggestedName(appNames:fallback:)` 生成：按 `AppPlacementRule.readingOrder` 取应用名去重后用「+」连接（如 `Google Chrome+Cursor+WeChat`），超长截断；`LayoutEditTransaction.uniqueName` 去重。「立即保存」若发现已有工作区与当前排布等价（§4），只刷新其 `updatedAt` 并设为 `activeProfileID`，提示「已保存过」。

## 6. 归位

### 6.1 计划（`ProfilePlan.make`，纯函数）

```swift
public static func make(
    profile: WorkspaceProfile,
    workAreasBySection: [DisplayIdentity.ID: CGRect],   // 未接显示器缺席
    candidates: [ProfileCapture.WindowSample]           // 全桌、z-order
) -> Outcome   // sections: [SectionPlan]、missingBundleIDs、skippedDisplayIDs

public struct SectionPlan {
    var displayID: DisplayIdentity.ID
    var workAreaAX: CGRect
    var placements: [WindowOrganizePlacement]   // identity + 目标 AX 帧，直接喂 executor
    var targetFramesAX: [CGRect]                // 该屏所有保存的位置（含应用未开的），供闪现
}
```

1. 候选窗口按 `bundleID` 分组，**全桌共享**一份队列：双显示器两节都要 Chrome 时各拿一个不同窗口，同一窗口绝不被两条规则占用。
2. 逐节、逐规则：`target = rule.frame.denormalize(in: 该屏实时可用区域)`。从该 bundle 队列中选窗口时按 `preferredIndex` 打分：已经坐在目标位置的窗口 2 分 > 本屏上的窗口 1 分 > 其它 0 分，同分取最前（z-order）。
3. 队列空 → 记入 `missingBundleIDs`（去重）；显示器未接 → 记入 `skippedDisplayIDs`。
4. 不在任何规则里的窗口一律不动。

### 6.2 执行（`WorkspaceCenter.applyNow`）

每节独立跑一次 `WindowOrganizeExecutor.execute(acceptance: .placement)`（节间串行）：

- `makePlan` 用固定目标帧构造 `WindowOrganizeAttemptPlan`；executor 要求携带一个 `Layout`，这里传该显示器当前布局**仅作占位**，不会 `assign` 也不会 `markLayoutUsed`。
- `.placement` 语义下 `sizeConstrained`（窗口最小尺寸大于保存尺寸）接受并记 issue，只有 position/immutable/unstable 才拒绝；行为缓存与 Organize 共用。
- 成功后每个 move 写 `catalog.record(UnsnapRecord(zoneIDs:))`：落点若与该屏当前布局的某个分区重合（`ZoneOccupancy.preferredZone`），就加入该分区的 membership，unsnap / 相邻贴靠 / 同区轮换照常可用；不重合则无归属。
- 成功或「没有可移动窗口」时 `flashWorkspaceFrames(area:framesAX:)`：把 `targetFramesAX` 作为匿名 `ResolvedZone` 闪现 1.2s，**不显示分区编号**，让用户看到窗口将落在哪里。
- 全部节完成后：激活每个保存的应用并 raise 其恢复的窗口（AXRaise 不能跨应用抬升，所以要 activate；但不激活全部窗口以免被拽去别的 Space），`activeProfileID = profile.id`，`persist()`，刷新菜单/设置页，重置普查基线，登记缺失应用（§7）。
- 反馈：`WorkspaceApplyFeedback.make` 汇总「已完整归位 N 个」「X 需要更大空间」「N 个未能移动」「N 个应用未打开 / 正在启动」「N 台显示器未连接」为一条 toast。

### 6.3 显示器重映射（`WorkspaceRestore.remappedSections`）

当保存的显示器**全部**都不在线（合盖/外出只带笔记本），把第一节映射到当前显示器恢复；只要有任一保存的显示器仍在线，未接的节就保持原 displayID 并被跳过，不会抢占兄弟显示器。

## 7. 缺失应用：启动并补位

`Outcome.missingBundleIDs` 非空且 `profile.launchMissingApps`：

```swift
struct PendingPlacement {
    var bundleID: String
    var frame: NormalizedRect        // 保存的位置，窗口出现时再对实时可用区域反算
    var displayID: DisplayIdentity.ID
    var expiresAt: Date              // now + 45s（WorkspaceRestore.launchTimeout）
}
```

1. `ProfilePlan.openAction`：应用未运行 → `openApplication`（不抢焦点），失败最多重试 3 次；已运行但无窗口 → 发 reopen 事件，2s 内仍无窗口再用 openApplication 补一下。找不到应用 → 直接提示「未安装」。
2. 该 bundleID 的全部规则（含多窗口）登记进 `pending`，启动 1Hz 普查：`CGWindowQuery` diff 上一帧。
3. 新窗口的 bundleID 命中 pending → AX 解析 → 连续两拍帧稳定 → 单窗写帧到 `frame.denormalize(in: 实时可用区域)` + 写 catalog → 移除该条 pending。被拒绝（窗口还在自调尺寸）最多重试 3 次，之后忽略该窗口但保留 pending；忽略过的窗口尺寸变化 ≥ 80pt（启动图变成文档窗口）会被重新接纳。
4. 同 bundleID 的辅助进程退出不会取消 pending（1.5s 后复查是否真的没有该应用在跑）。
5. 到期未出窗 → 移除并提示「××未能归位」；pending 清空后普查停止，零静息开销。

## 8. 入口

| 入口 | 行为 |
| --- | --- |
| 控制台（`MenuBarConsoleController` + `WorkspaceConsoleStrip`） | 工作区卡片：点击应用；卡片菜单更新/重命名/删除；「保存当前排布」按钮立即以建议名保存并进入行内重命名 |
| 备用 NSMenu（VoiceOver 回退，`MenuBarController`） | 「工作区」子菜单：每个工作区一项（活跃者打勾）、「保存当前排布为工作区…」（命名弹窗，含只保存这一屏复选框）、「更新〈活跃工作区〉」 |
| 快捷键 | `applyWorkspace` 默认 ⌃⌥P：呼出 HUD 切换器，再按一次应用高亮项；`captureWorkspace` 默认 ⌃⌥⇧P：立即保存。均走 `ShortcutCatalog` 冲突校验与设置页自定义 |
| HUD 切换器（`WorkspaceSwitcherReducer` + `WorkspaceSwitcherController`） | 浏览：1–9 / 方向键 / Tab / ⏎ 应用，`U` 更新高亮项，`S` 进入命名，Esc 关闭。命名：⏎ 保存，Esc 返回浏览，`Tab` 或复选框切换「只保存这一屏」（未编辑过的建议名跟随范围切换；手输的名字不动），应用数为 0 时保存 beep |
| 设置页「工作区」Tab | 卡片列表（名称、每屏「显示器 · N 个窗口」、位置示意图、每个应用旁 `W% × H%` 徽标）、重命名、删除、「用当前排布重新捕获」、`launchMissingApps` 开关 |

HUD 切换器 reducer 输入除 `captureCount / suggestedName`（全桌）外还带 `displayChoice: WorkspaceSwitcherDisplayChoice?`（指针所在屏的 id、建议名、应用数），只在提供范围选择时非 nil；命名阶段 `thisDisplayOnly` 只有在 `displayChoice` 仍存在时才生效——保存瞬间显示器被拔掉则自动退回全桌。

所有入口共用 `StoreDocument.orderedProfilesForSettings()` 的顺序：`activeProfileID` 指向的工作区永远排第 1（编号 1），其余按存储顺序（新建追加末尾）；应用或保存只把那一张卡移到最前，存储数组本身不变。

## 9. 互斥与安全

| 冲突点 | 处理 |
| --- | --- |
| 与 Organize / 另一次归位并发 | `beginWindowTransaction` 事务门，同一时刻全桌至多一个批量改帧事务 |
| 用户正在拖拽 / QuickSnapper / 编辑器打开 | 捕获与归位前检查 `runtime.mode == .idle`，否则 beep 不执行 |
| Accessibility 未授权 | `isTrusted()` 失败 → `openAccessibility()` 引导 |
| 归位进行中显示器插拔 | 节开始前校验 `isActive(displayID:)`；pending 在窗口出现时才对实时可用区域反算，显示器没了则丢弃该 pending |
| 应用退出 | `didTerminateApplicationNotification` → `catalog.drop(pid:)`；pending 按 §7.4 复查 |
| 排除名单 | `settings.excludedBundleIDs` 内的应用捕获与归位一律跳过 |

## 10. 边界情况

| 场景 | 行为 |
| --- | --- |
| 同应用多窗口 | 捕获生成多条规则（各自位置）；归位按「已在位 > 本屏 > z-order」消费。窗口比规则多 → 多余的不动；比规则少 → 差额进 missing（提示，不再启动新实例） |
| 重叠窗口 | 都保存，保持前后层级；预览从后到前绘制，被完全盖住的窗口不画图标；恢复后按保存的层级 raise |
| 窗口最小尺寸 > 保存尺寸 | `AXFrameMutator` clamp 到 minSize，`.placement` 接受并记 issue，toast「××需要更大空间」 |
| 最小化 / 隐藏应用的窗口 | 归位时对保存的应用取消最小化 / unhide 后再消费；原生全屏或其它 Space 的窗口不可达，只提示 |
| 应用无 bundleID / LSUIElement 无窗 | 捕获跳过；启动补位走 45s 超时提示 |
| 布局被编辑或删除 | 与工作区无关，无影响 |
| 显示器未接 | 该节跳过 + toast「N 台显示器未连接」；全部未接时第一节映射到当前屏（§6.3） |
| 显示器换了但同型号 | `DisplayIdentity.bestMatch` 打分重识别 |
| 不同分辩率 / Dock 位置 | 归一化矩形对实时可用区域反算，按比例还原 |
| 旧版本 ZoneBox 覆写 store.json | `profiles` 丢失（Codable 忽略未知键后重编码）；接受，与 `recentLayoutIDs` 先例一致 |
| 旧「分区」格式的工作区 | 启动解码时按 §4.1 迁移为位置规则；建议重新捕获 |

## 11. 性能预算

- **静息（无 pending）**：零开销，无定时器。
- **捕获预览**（应用数、建议名、这一屏的应用数/建议名）：一次 CG 枚举（~1.3ms）+ 几何归一化，无 AX 调用，共用同一次枚举；HUD 命名阶段每次按键都重算一次。**正式捕获**多一轮按应用的 AX 枚举，与一次 Organize 同量级。
- **归位**：瓶颈是 `setFrame`（每窗 16–50ms，AX 队列串行）+ 判稳采样 → 8 窗全桌 ≈ 2–3s；`.placement` 把「整批回滚重跑」从常见路径中移除。
- **普查循环**：1Hz × ~1.3ms `CGWindowListCopyWindowInfo`，只在 pending 非空时运行。

## 12. 测试

Core（`ZoneBoxTests`，`make test`）：

1. **`ProfileCaptureTests`**：窗口按实际位置保存而非分区（左半 Chrome → `(0,0,0.5,1)`，右半 Cursor → `(0.5,0,0.5,1)`，独占 → `(0,0,1,1)`）；归一化/反算往返精度；z-order 保持；无 bundleID / 零可用区域 → 空；重叠窗口都保存；`readingOrder`；`matches` 容差；可见性（遮挡 ≥ 25% 才算）；范围过滤与重捕获合并（未接节保留、空捕获返回 nil）。
2. **`ProfilePlanTests`**：跨节共享队列不重复占用窗口；缺失 / 未接显示器 / `targetFramesAX`；位置随实时可用区域缩放；已在位窗口优先、本屏优先、其余按 z-order；`restorableBundleIDs`、`openAction`。
3. **`WorkspaceRestoreTests`**：启动/重开/放弃策略、超时常量、合盖重映射、兄弟显示器不被抢占、重映射后仍能计划与启动缺失应用。
4. **`WorkspaceSwitcherTests`**：浏览/命名状态机；`toggleCaptureScope` 无范围选择时忽略、有选择时翻转并在建议名未被编辑时跟随、手输名字保留；只保存这一屏时 `capture(displayID:)` 带该屏 id、该屏应用数为 0 时 beep、范围选择消失时退回全桌；排布等价忽略顺序与 2% 抖动、不同显示器/位置/数量不等价。
5. **`WorkspaceLayoutPreviewTests`**：预览按位置从后到前绘制、被盖住的窗口不画图标、过小窗口不画图标、图标落在窗口内。
6. **`LayoutStoreTests`**：`profiles` 往返、空节剔除；旧 zoneID/zoneNumber JSON 迁移（id 优先、编号回退、无法解析丢弃、重编码不含 `zoneNumber`）；删除布局不影响工作区；`mergeDisplay` 迁移节。
7. **`WorkspaceApplyFeedbackTests` / `L10nTests`**：反馈文案组合与中英文案。

手工验收清单：

- 双显示器摆好窗口（例如左 Chrome / 右 Cursor，第二屏 WeChat 独占）→ 保存 → 设置页每个应用旁的 `W% × H%` 与示意图和实际一致 → 拖乱、换屏 → 快捷键 → 全部回到原位，闪现的是恢复位置而不是分区编号，显示器布局未被切换。
- HUD `S` 命名时两屏都有窗口：出现「只保存这一屏」复选框，Tab 切换后建议名与摘要随之变化；保存后设置页只有一节。
- 退出其中两个应用 → 归位 → 应用被自动启动、窗口出现后落到保存位置、无焦点抢占。
- 最小尺寸受限的应用在工作区里 → 其余窗口不回滚不闪动，toast 提示需要更大空间。
- 拔掉外接屏 → 归位 → 内屏节正常，toast 提示跳过；在单屏上「更新」工作区，外接屏那一节仍保留。
- 用初版保存的旧 store.json 启动 → 工作区可见、无 `layoutID`，位置为原分区几何；重新捕获后为真实位置。

## 13. 未来扩展

- **标题正则规则**：`AppPlacementRule` 加可选 `titlePattern`，区分「Chrome 的工作窗 vs 娱乐窗」。
- **Space 级工作区**：`SpaceKey.spaceUUID` 已预留。
- **场景自动切换**：接上外接屏 / 时间段 → 自动应用对应工作区（`didChangeScreenParametersNotification` 已有挂点）。
- **跟随模式**：工作区激活期间，其应用新开的窗口自动放到该应用的首条保存位置。
- **导入导出**：工作区 JSON 导出/导入，便于多机同步。
