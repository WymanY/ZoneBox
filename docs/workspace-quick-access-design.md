# ZoneBox 工作区快速访问设计（Workspace Quick Access）

| 字段 | 值 |
| --- | --- |
| **标题** | 工作区的一键应用与一键保存：切换器 HUD、直接捕获快捷键、控制台卡片区块 |
| **状态** | 已实现；2026-09-11 补充：工作区改为保存窗口位置（见 `workspace-profiles-design.md`），HUD `S` 命名态新增「只保存这一屏」范围切换 |
| **日期** | 2026-09-10 · 2026-09-11 更新 |
| **作用范围** | 工作区（Workspace Profiles）的「应用」与「保存」入口；不改捕获推断与归位引擎 |
| **关联文档** | `docs/workspace-profiles-design.md`（数据模型、捕获、归位事务）、`docs/layout-picker-design.md`（reducer-only 测试原则、HUD 先例）、`docs/runtime-architecture.md`（RuntimeMode 归属） |

---

## 1. 背景与问题

工作区功能（`WorkspaceCenter` / `WorkspaceProfile` / `ProfileCapture` / `ProfilePlan`）已上线，但两条日常路径都太深。

### 1.1 应用一个工作区

| 入口 | 步骤 | 问题 |
| --- | --- | --- |
| 控制台 | 菜单栏图标 → 底部「工作区」小按钮 → 弹出 `NSMenu` → 点一项（`MenuBarConsoleController.showWorkspaceMenu`） | 3 次点击；列表是纯文字，无预览、无编号、无快捷键提示；按 `updatedAt` 倒序，位置总在变 |
| 快捷键 | `⌃⌥P` → `WorkspaceCenter.applyCurrentOrMostRecent()` | 只能应用「上次应用 / 保存的那一个」（`activeProfileID ?? max(updatedAt)`），多方案时无法选择 |
| 右键 / VoiceOver 备用菜单 | Workspaces 子菜单（`MenuBarController.makeWorkspacesMenu`） | 有「更新最近应用的工作区」，但控制台弹出菜单里没有，两处入口不一致 |
| 设置 → 工作区 | 重命名 / 删除 / 重新捕获 / 启动缺失应用 | 没有「应用」按钮 |

### 1.2 保存一个工作区

菜单栏图标 → 工作区 → 「保存当前排布…」→ 模态 `NSAlert` 输名字（已预填 `suggestedCaptureName()` 给出的 `Xcode+Safari` 这类建议名）→ 保存。4 次点击 + 1 个模态，没有快捷键。

捕获逻辑本身已经很好（自动命名、逐显示器推断规则、空结果有 toast），瓶颈完全在入口深度和模态。

### 1.3 可直接复用的资产

| 能力 | 位置 | 用途 |
| --- | --- | --- |
| HUD + 数字键选择模式 | `Domain/QuickSnapper.swift`（`QuickSnapperReducer`，纯函数 + 单测）、`SnapEngine.handleQuickSnapper`、`HotkeyCenter.handleKeyEvent` 的「HUD 显示时拦截数字 / Tab / Esc」分支 | 切换器 HUD 的 reducer 与键路由同构照搬 |
| 不抢焦点的可收键面板 | `MenuBarConsoleController` 的 `ConsolePanel`：`.nonactivatingPanel` + `canBecomeKey` | HUD 面板基类 |
| 工作区缩略图 | `Domain/WorkspaceLayoutPreview.swift` + `UI/Settings/WorkspaceLayoutPreviewView.swift`（按保存的窗口位置画矩形 + 应用图标，设置页已在用） | HUD 与控制台卡片 |
| 控制台卡片与网格 | `LayoutCardView` / `LayoutGridView` | 控制台工作区区块 |
| toast（可带两个动作按钮） | `UI/Overlay/OrganizeFeedbackController.swift`（`restoreTitle` / `ignoreTitle`） | 「已更新」+ 撤销 |
| 快捷键管线 | `ShortcutCatalog` + `ShortcutCustomizationID` + `HotkeyCenter` | 新增一条 chord 自动铺到设置页 Keyboard、快捷键面板、冲突校验、`L10nTests` |
| 方案顺序 | `StoreDocument.profiles` 数组序已持久化，`orderedProfilesForSettings()` 在其上把 `activeProfileID` 提到最前 | 当前 = 1 号，其余编号稳定 |
| 更新语义 | `WorkspaceCenter.capture(name:replacing:)` | HUD `U` / 卡片菜单「更新」共用 |

## 2. 目标 / 非目标

### 目标

1. 应用任一工作区：键盘 ≤ 2 键（`⌃⌥P` + 数字），鼠标 ≤ 2 次点击（图标 → 卡片）。
2. 保存当前排布：键盘 1 个组合键、无模态；鼠标 2 次点击。
3. 工作区在控制台里成为一等公民：可见、有预览、有编号、有快捷键提示。
4. 编号稳定，可形成肌肉记忆（「3 永远是会议」）。
5. 不改捕获 / 归位算法；不破坏拖拽贴靠、Quick Snapper、编辑器、分隔杆、Pin；Pro 门禁不变。

### 非目标（本轮不做）

- 自动切换（接显示器 / 时间段 / Focus 模式触发 apply）。
- 「蓝图式」新建：不先摆窗口、直接把应用图标拖进 zone 来定义工作区（见 §9 可选项，需单独设计）。
- 多窗口语义规则（标题正则）、Spaces。
- 官网文案（独立仓库 `zonebox-site`）。

## 3. 方案选型

| 方案 | 结论 | 理由 |
| --- | --- | --- |
| A1 每个方案独立全局快捷键 | 采用，P2 | 最快，但要记键、占槽位、有冲突成本，适合作为进阶层而非唯一路径 |
| A2 工作区切换器 HUD（与 Quick Snapper 同构） | **采用，P0 主路径** | 一个键学会全部；可见、可扩展到 N 个方案；架构现成 |
| A3 控制台工作区卡片区块 | 采用，P1 鼠标主路径 | 3 次点击压到 2 次，并解决「看不见预览」 |
| A4 `⌥` + 点击状态栏图标直达 HUD | 采用，P2 | 几行代码 |
| A5 URL scheme（Raycast / Alfred / 快捷指令） | 可选 P3 | 成本低，权力用户单键直达 |
| C1 直接捕获快捷键，免命名 | 采用，P0 | 「先存后改名」，像截图 |
| C2 HUD 内 `S` 保存 + 行内命名 | 采用，P0 | 键盘全流程不断 |
| C3 控制台「+ 保存当前」即时保存 | 采用，P1 | |
| 模态命名弹窗 | 淘汰（VoiceOver 备用菜单保留） | 被行内命名与「先存后改名」替代 |
| 按 `updatedAt` 排序 | 淘汰 | 每次应用/更新都整体重排，编号漂移 |
| 纯数组稳定序（初版实现） | 2026-09-11 调整 | 用户期望「当前」在第 1 位；改为**当前置顶 + 其余保持数组序**，一次只动一张卡 |

## 4. 交互规格

### 4.1 工作区切换器 HUD（`⌃⌥P`）

**触发**

- `⌃⌥P`：沿用现有 `applyWorkspaceHotkey` 默认 chord，标题从「应用当前工作区」改为「工作区切换器」。
- P2：`⌥` + 点击状态栏图标。

**前置条件**（与今天的 apply 一致）

- 未授权 Pro → `requestProAccess(for: .workspace)` 弹 paywall。
- `runtime.mode != .idle`（拖拽中 / 分隔杆 / 归位中）或编辑器打开 → beep，不显示。
- Accessibility 未授权 → `openAccessibility()`。

**可见状态**

- 鼠标所在显示器居中，非激活浮动面板（材质同控制台），前台应用不失活。
- 标题行「工作区」+ 右侧灰字提示：`1–9 应用 · ⏎ 应用高亮项 · S 保存当前 · U 更新高亮项 · Esc`。
- 卡片网格：每行 3 张，最多 9 张带编号；第 10 张起只能方向键 + `⏎`。每张卡片：
  - 左上编号徽标 `1`…`9`（= 数字键）；
  - 名称（单行截断）；
  - 预览：每个 section 一张 `WorkspaceLayoutPreviewView`（≤ 2 台显示器并排，更多显示 `+N`），按保存位置画窗口并放应用图标；
  - 底部应用图标行（≤ 5 + `+N`）；
  - 「当前」徽标（`activeProfileID`）；
  - P2：若配了独立快捷键，显示 chord 字形；
  - 该 section 的显示器当前未连接（不在 `runtime.workAreas`）→ 灰显 + `⚠` 角标。
- 默认高亮：`activeProfileID` 对应卡片，无则第 1 张。
- 空状态：一张虚线「按 S 保存当前排布」卡片 + 一行说明「先摆好窗口，再保存」。同时充当功能发现。

**按键（HUD 显示中）**

| 键 | 行为 |
| --- | --- |
| `1`–`9` | 隐藏 HUD → 应用对应编号 |
| `⏎` 或再按一次 `⌃⌥P` | 应用高亮项 |
| `←→↑↓` / `Tab` / `⇧Tab` | 移动高亮（3 列网格环绕） |
| `S` | 进入「保存」态（§4.2） |
| `U` | 用当前排布更新高亮项（`capture(name:replacing:)`）；toast「已更新 “X”」带 7s **撤销**按钮（内存保留旧 profile，撤销即 `upsertProfile(old)`） |
| `Esc` / 点面板外 / 切到其它应用 / 开始拖窗口 | 关闭 |
| 鼠标点卡片 | 应用；悬停出现 `…`：更新 / 重命名 / 删除 |
| `⌫` | 不做删除，避免误删；删除留在卡片菜单和设置页 |

**成功**：HUD 先隐藏（不遮挡窗口移动），再走现有 `WorkspaceCenter.apply(profileID:)`；闪 zone + toast 反馈不变。

**失败**：事务门被占（`beginWindowTransaction` 返回 false）→ beep，HUD 关闭；编号无对应 → 忽略。

**运行时归属**：HUD 显示期间不占 `RuntimeMode`（纯 UI）；apply 仍走 `.organizing` 事务门。`SnapEngine` 收到 `leftDown` 时关闭 HUD（同 Quick Snapper 现有处理）。

### 4.2 保存当前排布

三条路径，都不再出现模态弹窗：

| 路径 | 流程 | 成本 |
| --- | --- | --- |
| HUD 内 `S` | 卡片区切换为保存态：行内文本框（预填建议名，全选）+ 实时摘要「将保存 N 个应用 · M 台显示器」（`WorkspaceCenter.captureSummary()`，一次 `collectVisibleSamples()` + `captureSections()` 同时算出全桌与这一屏的应用数/建议名）。`⏎` 保存并关闭，`Esc` 回到列表。N = 0 时文本框禁用、摘要变「没有可保存的窗口」、`⏎` 只 beep。当 ≥ 2 台显示器都有窗口且能确定指针所在屏时，文本框下方出现「只保存这一屏（显示器名）」复选框，`Tab` 或点击切换（头部提示变为「⏎ 保存 · Tab 切换只保存这一屏 · Esc 返回」）；未编辑过的建议名跟随范围切换，手输的名字不动；摘要与 N = 0 判定按所选范围计算 | 3 键 |
| 直接快捷键 `⌃⌥⇧P`（新 `captureWorkspace`，可自定义） | 立即以建议名保存，不问名字。toast「已保存为 “Xcode+Safari” · ⌃⌥P 可随时恢复」 | 1 键 |
| 控制台「+ 保存当前」（P1） | 同上；保存后新卡片出现并进入行内重命名，`Esc` 保留建议名 | 2 次点击 |

**去重规则**：纯函数 `WorkspaceProfile.hasSameArrangement(as:)`（各 section 的 `displayID` 一致、规则在 2% 容差内一一配对，与规则顺序无关）。与某已有方案完全相同 → 不新建，把该方案设为 active、刷新 `updatedAt`，toast「当前排布已保存为 “X”」。连按 `⌃⌥⇧P` 不会产生 `X 2`、`X 3`。

**命名冲突**：仍用 `LayoutEditTransaction.uniqueName`。

**「更新」语义统一**：HUD `U`、卡片菜单「用当前排布更新」、备用菜单现有项，都走 `capture(name:replacing:)`，保留名字、`launchMissingApps` 和（P2）快捷键。

### 4.3 控制台工作区区块（P1）

- 位置：「其它布局」网格之下、分隔线之上。section header「工作区」（左）+「+ 保存当前」文字按钮（右，accent 色，样式同「新建」）+「管理…」。
- 内容：一行横向卡片条（高约 84pt，卡宽约 100pt，横向滚动，稳定顺序）。卡片 = 编号徽标 + 名称 + 迷你预览（首个 section）+ 当前徽标。点击 = 关闭控制台后应用（`dismiss(handoff:)`）。悬停 `…` → 更新 / 重命名 / 删除（删除用 sheet 确认，同布局删除）。
- 空状态：虚线「+ 保存当前排布」卡片 + 一句说明。
- 高度预算：新增约 18 + 10 + 84 + 10 ≈ 122pt；把「其它布局」最大行数从 3 降到 2（`Metrics.maxGridHeight`，−98pt），净增约 24pt。
- 移除底部「工作区」按钮及其 `NSMenu`（`showWorkspaceMenu` / `applyConsoleWorkspace` / `captureConsoleWorkspace`）；底部保留「设置 | 退出」，中间放 `⌃⌥P 切换器` 灰字提示。
- 右键 / VoiceOver 备用菜单：菜单项加编号前缀「1. Xcode+Safari」，顺序与 HUD 一致；保留「保存当前排布…」（VoiceOver 下保留模态命名，可访问性最好）、「更新…」「管理…」。

### 4.4 每方案独立快捷键（P2）

- `WorkspaceProfile.hotkey: KeyChord?`（`decodeIfPresent`）。
- 设置 → 工作区每行加录制器（复用 Keyboard 页的 recorder）。`ShortcutCatalog.validate` 把 profile chord 集合加入 `seen` 检查，双向防撞（新 chord 不能撞 profile，profile chord 也不能撞既有 chord）。
- `HotkeyCenter.rebuildChordIndex` / `registerAll` 额外读取 `runtime.document.profiles`，hotkey ID 区间 `200 + index`（上限 50）；profile 增删改后 `reregister()`。
- HUD 卡片、控制台卡片显示 chord 字形；快捷键面板「全局」分区列出「应用工作区：X」。
- 设置页加上下移动（稳定编号可调）与「应用」按钮。

### 4.5 `⌥` + 点击状态栏图标（P2）

`MenuBarController.statusItemClicked` 检测 `.option` → 关闭控制台，直接 `switcher.handle(.invoke)`。右键仍为完整备用菜单（VoiceOver 对等）。

### 4.6 可选 P3：URL scheme

`zonebox://workspace/apply?id=…`（或 `name=`）与 `zonebox://workspace/capture`。`project.yml` 加 `CFBundleURLTypes`，`NSAppleEventManager` 处理。供 Raycast / Alfred / 快捷指令做单键直达。同样经过 Pro 门禁与事务门。

## 5. 架构与文件边界

### 5.1 Core（`ZoneBoxCore`，纯逻辑，可无 AppKit 单测）

| 文件 | 改动 |
| --- | --- |
| `Domain/WorkspaceSwitcher.swift`（新） | `WorkspaceSwitcherPhase { hidden, browsing(highlight: Int), naming(text: String, highlight: Int, thisDisplayOnly: Bool = false) }`；`Event { invoke, digit(Int), move(dx: Int, dy: Int), confirm, beginSave, textChanged(String), toggleCaptureScope, save, update, dismiss }`；`Effect { show, hide, apply(WorkspaceProfile.ID), capture(name: String, displayID: DisplayIdentity.ID? = nil), updateProfile(WorkspaceProfile.ID), beep }`；`Input`（phase、event、profileIDs、activeProfileID、isIdle、trusted、captureCount、suggestedName、`displayChoice: WorkspaceSwitcherDisplayChoice?`——指针所在屏的 id / 建议名 / 应用数，仅在提供范围选择时非 nil）。`WorkspaceSwitcherReducer.reduce` + 3 列网格导航 helper |
| `Domain/WorkspaceProfile.swift` | `hasSameArrangement(as:)`；P2 `hotkey: KeyChord?` |
| `Domain/DisplayIdentity.swift` | P2 `moveProfile(id:to:)`；`orderedProfilesForSettings()` = 活跃工作区置顶 + 其余数组序（存储顺序本身不变） |
| `Domain/ShortcutCatalog.swift` | `captureWorkspaceHotkeyID = 111`、`ShortcutCustomizationID.captureWorkspace`、对应 `ShortcutSpec`；`applyWorkspace` 标题 key 文案改「工作区切换器」；P2 profile chord 参与 `carbonHotkeys` 与 `validate` |
| `Domain/AppSettings.swift` | `captureWorkspaceHotkey: KeyChord`（默认 `⌃⌥⇧P`，`decodeIfPresent` 回落默认值） |
| `Domain/L10n.swift` | 新文案 EN + zh-Hans（`L10nTests` 强制齐全） |

### 5.2 App / Services

| 文件 | 改动 |
| --- | --- |
| `UI/Workspace/WorkspaceSwitcherController.swift`（新） | 面板（照 `ConsolePanel` 模式：`.borderless, .nonactivatingPanel`、`canBecomeKey`、`.floating`、`.canJoinAllSpaces`）、卡片视图（复用 `WorkspaceLayoutPreviewView`）、行内命名框；键事件喂 reducer，effects 落地。通过 `RuntimeHost.swift` 新窄协议 `WorkspaceSwitcherHosting` 访问 runtime，不持有具体 `AppRuntime` |
| `Services/WorkspaceCenter.swift` | 新增 `captureImmediately()`（建议名 + 去重）、`capturePreview() -> (applicationCount: Int, displayCount: Int)`、`captureSummary() -> WorkspaceCaptureSummary`（全桌 + 这一屏的应用数/建议名，供 HUD 命名态）、`updateProfileFromCurrent(id:)` 带撤销快照；apply 前先隐藏 HUD |
| `Services/HotkeyCenter.swift` | `applyWorkspaceHotkeyID`：HUD 未显示 → `.invoke`，已显示 → `.confirm`；`captureWorkspaceHotkeyID` → `captureImmediately()`；`handleKeyEvent` 新增 `switcher.isShowing` 分支拦截数字 / `⏎` / `Esc` / `S` / `U` / 方向键 / Tab（本地 monitor 吞掉、全局不吞，与 Quick Snapper 同权衡）；命名态只拦 `⏎`（保存）与 `Tab`（`.toggleCaptureScope`），其余键交给文本框；Escape 路由新增 `.dismissWorkspaceSwitcher` |
| `UI/MenuBar/MenuBarConsoleController.swift`（P1） | 工作区区块、卡片、`+`、卡片菜单；删除 footer `NSMenu` 相关方法 |
| `App/MenuBarController.swift` | 备用菜单编号；P2 `⌥` 点击 |
| `UI/Settings/SettingsWindowController.swift`（P2） | 录制器、上下移、「应用」按钮；Keyboard 页因 `ShortcutCatalog` 自动多一行 |
| `App/AppRuntime.swift` / `App/RuntimeHost.swift` | 接线 `switcher`，`start` / `teardown`，`displaysDidChange` 时刷新 HUD，`closeConsoleIfOpen` 同类的 `closeSwitcherIfOpen` |

### 5.3 数据流（一次 `⌃⌥P` + 数字）

```
HotkeyCenter(applyWorkspaceHotkeyID) ─.invoke─▶ WorkspaceSwitcherController
  ├─ input = (phase, event, profileIDs(数组序), activeProfileID, isIdle, trusted)
  ▼
WorkspaceSwitcherReducer.reduce ─▶ [.show]  → 面板显示、默认高亮
  ...
HotkeyCenter.handleKeyEvent(数字 n, switcher.isShowing) ─.digit(n)─▶ reduce
  ─▶ [.hide, .apply(id)]
  ▼
面板隐藏 → WorkspaceCenter.apply(profileID:)（Pro 门禁 → 事务门 → applyNow → 闪 zone → toast）
```

## 6. 设置与默认值

| 项 | 默认 |
| --- | --- |
| `⌃⌥P` | 工作区切换器（原「应用当前工作区」）；见 §10 决策 1 |
| `⌃⌥⇧P` | 保存当前排布为工作区（新，可自定义）。已核对与现有 `⌃⌥` + 数字 / Z / U / O / P / [ / ] / Space / `/` 无冲突 |
| 排序 | 「当前」（`activeProfileID`）永远第 1 张，其余按 `profiles` 数组序（新建追加末尾）；应用或保存只把那一张移到最前。HUD / 控制台 / 备用菜单 / 设置页一致；控制台条会把当前卡片滚到可见 |
| HUD 位置 | 鼠标所在显示器居中 |
| 每方案快捷键 | 无，P2 由用户自配 |
| 新增偏好开关 | 不增加。单方案用户按 `⌃⌥P ⏎`（或再按一次 `⌃⌥P`），或在 P2 配独立快捷键 |

## 7. 边界与风险

| 风险 | 对策 |
| --- | --- |
| HUD 抢焦点让目标应用失活 | `.nonactivatingPanel` + `orderFrontRegardless` + `makeKey`，`ConsolePanel` 已验证；apply 前先隐藏 |
| 数字键被前台应用吃掉 | HUD 面板为 key window 时按键进本地 monitor（与 Quick Snapper 同）；一旦失去 key（用户点了别处）HUD 直接关闭，不会出现「HUD 开着但键不响应」 |
| 安全输入（密码框）期间 | 同 Quick Snapper 限制；`Esc` / 点外部仍可关闭 |
| 方案 > 9 个 | 第 10 张起用方向键 + `⏎`；设置页可重排把常用的放前 9 |
| VoiceOver | 备用菜单保留全部功能与模态命名；HUD 卡片设 accessibility label「1，Xcode+Safari，当前」；`⌃⌥` chord 仍受 `ShortcutVoiceOverPolicy` 暂停策略约束 |
| HUD 打开时插拔显示器 | `displaysDidChange` → 重建卡片，未连接 section 灰显 |
| 连按 `⌃⌥⇧P` | 去重规则，不产生重复方案 |
| `U` 误触 | 7s toast 带撤销 |
| Pro 试用过期 | invoke 即 paywall（同 Quick Snapper） |
| 与 Organize / 另一次归位并发 | apply 仍走事务门，失败 beep |
| 旧版本覆写 `store.json` | 新字段均 `decodeIfPresent`；P2 `hotkey` 丢失可接受，与 `profiles` 引入时的取舍一致 |

## 8. 测试与验收

### 8.1 单测（Core，`make test`）

- `WorkspaceSwitcherTests`：invoke 默认高亮 = active / 首项；digit 越界忽略；digit 命中 → `[.hide, .apply]`；confirm 应用高亮项；move 网格环绕（3 列）；beginSave → naming；save 空名 → beep；save → `[.hide, .capture(name, displayID: nil)]`；update → `[.updateProfile(highlight)]`；dismiss；非 idle / 未 trusted → 不显示且不产生 effect；HUD 显示中再收到 invoke 等价 confirm；captureCount = 0 时 save → beep；`toggleCaptureScope` 无 `displayChoice` 时忽略、有则翻转并让未编辑的建议名跟随、手输名字保留；只保存这一屏时 `capture(displayID:)` 带该屏 id、该屏应用数为 0 时 beep、`displayChoice` 消失时退回全桌。
- `WorkspaceProfileArrangementTests`：`hasSameArrangement` 与规则顺序无关且容忍 2% 抖动；显示器、位置或应用数不同判不同；空 sections 不相等。
- `ShortcutCatalogTests`：`captureWorkspace` 默认 `⌃⌥⇧P`、与现有无冲突、reset 路径；P2 profile chord 冲突双向检测。
- `AppSettings` 解码：旧 JSON 无 `captureWorkspaceHotkey` → 默认值。
- `L10nTests` 自动强制新 key 双语齐全。
- P2：`StoreDocument.moveProfile` 与 `hotkey` round-trip；`normalizeReferences` 不清掉 `hotkey`。

### 8.2 手工验收

1. 有 3 个方案，任意应用前台：`⌃⌥P` → HUD 出现、前台应用不失活 → 按 `2` → HUD 消失 → 窗口归位 → toast；`activeProfileID` 变为 2 号。
2. `⌃⌥P`、`⌃⌥P` → 应用高亮（active）项。
3. `⌃⌥P`、`S` → 文本框预填 `A+B`，摘要 N/M 正确 → `⏎` → 新卡片出现在末尾编号 4 → 排布不动再按 `⌃⌥⇧P` → 不新建，toast 提示已存在。
4. 没有可保存的窗口：`⌃⌥⇧P` → toast「没有可保存的窗口」；HUD `S` 态文本框禁用。
4a. 两台显示器都有窗口：`⌃⌥P`、`S` → 文本框下方出现「只保存这一屏（显示器名）」→ `Tab` → 复选框勾上、建议名只列该屏应用、摘要变「… · 1 台显示器」→ `⏎` → 新工作区只有一节；再 `Tab` 一次可切回全桌。
5. 控制台：图标 → 点卡片 3 → 应用（2 次点击）；「+ 保存当前」→ 新卡片 + 行内重命名；`…` → 更新 / 重命名 / 删除。
6. 拖拽中或编辑器打开时按 `⌃⌥P` → beep，无 HUD。
7. VoiceOver 开启：右键菜单显示「1. …」，保存仍为模态命名。
8. 拔掉外接屏 → HUD 对应 section 灰显 `⚠`；应用后 toast 报告跳过的显示器。
9. P2：给方案 2 录 `⌃⌥⇧2` → 任意位置按下直接应用，与 `⌃⌥2` 不冲突，HUD 卡片显示字形。
10. 未授权 Pro：`⌃⌥P`、`⌃⌥⇧P`、控制台卡片都弹 paywall。

## 9. 分期

| PR | 内容 | 规模 |
| --- | --- | --- |
| PR-1（P0，键盘闭环） | reducer + HUD + `⌃⌥P` 新语义 + `⌃⌥⇧P` 捕获 + 行内命名 + 去重 + 更新撤销 + L10n + 单测 | M |
| PR-2（P1，鼠标闭环） | 控制台工作区区块 + `+` + 卡片菜单 + 备用菜单编号 + 移除 footer `NSMenu` | M |
| PR-3（P2） | 每方案快捷键 + 设置页重排 / 应用按钮 + `⌥` 点击图标 | S–M |
| 可选 | URL scheme（S）；蓝图式新建（L，需单独设计：选布局 → 把应用图标拖进 zone，不必先摆真实窗口） | |

PR-1 单独发布就已经解决「进菜单找场景」这个核心痛点。

## 10. 待决策

1. **`⌃⌥P` 语义**（推荐方案 A）
   - A：`⌃⌥P` 改为「打开切换器」，默认高亮 active，再按一次即应用。代价：单方案用户从 1 键变 2 键。
   - B：`⌃⌥P` 保持直接应用 active，切换器改到 `⌃⌥⇧P`，保存只留 HUD 内 `S` 和控制台 `+`。
   - 两者实现量相同，是使用习惯的选择。
2. **蓝图式新建是否列入后续**：如果「创建麻烦」还包括「要先把每个窗口一个个贴好才能保存」，值得单独做一份设计；如果只是入口太深，本方案已覆盖。

## 11. 未来扩展

- 场景自动切换：接上外接屏 / 时间段 / Focus 模式 → 自动 apply 对应 profile（`didChangeScreenParametersNotification` 已有挂点）。
- 蓝图式工作区编辑器（§9 可选项）。
- 导入导出 profile JSON，便于多机同步。
