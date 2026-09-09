# ZoneBox Agent 使用指南

## 日常入口

在 ZoneBox 项目里开启任务，主模型使用 `xai/grok-4.6`，推理强度 `medium`。直接用自然语言说明需求即可；也可以明确点名下列角色。角色是子 Agent，不是需要手动创建的七个聊天窗口。

| 角色 | 固定模型 / 推理 | 示例 |
| --- | --- | --- |
| `zonebox_status` | `xai/grok-4.6` / high | 用 zonebox_status 查看项目状态，只读检查。 |
| `zonebox_design` | `google-antigravity/claude-opus-4-6-thinking` / high | 用 zonebox_design 设计布局选择器，先给方案，不改代码。 |
| `zonebox_macos` | `xai/grok-4.6` / high | 用 zonebox_macos 在指定 worktree 实现这个方案，构建后交给我验证。 |
| `zonebox_verify` | `google-antigravity/claude-opus-4-6-thinking` / high | 用 zonebox_verify 独立检查这次改动，复现问题并列出回归风险。 |
| `zonebox_release` | `xai/grok-4.6` / medium | 用 zonebox_release 给当前改动开 PR，不合并。 |
| `zonebox_web` | `xai/grok-4.6` / high | 用 zonebox_web 修改官网购买流程，在 zonebox-site 仓库开发。 |
| `zonebox_diagnose` | `gpt-6-astra` / high，只读 | 这个拖拽问题两次修复仍无效，用 zonebox_diagnose 定位根因，再交给 Grok 修复。 |

普通修复不需要经过所有角色。复杂工作通常按“设计 → 实现 → 独立验证”进行；诊断专家只在需要时加入。PR 创建、合并和发布遵循当次授权；所有角色禁止操作 Linear。

## OpenAI 额度控制

- 日常入口和代码实施使用 Grok。
- 设计和独立验证使用 Google Antigravity 路由的 Claude。
- 搜索辅助使用 xAI Grok；图片辅助使用 Google Antigravity Gemini 3.8 Flash。
- Astra 只处理有边界的诊断问题，返回证据和修复方案，不承担持续实施。
- 默认不将 OpenAI 放入自动故障回退链。第三方服务有自己的额度，并不等于免费或无限。
- 默认一个工作 Agent，有独立任务时最多两个；角色数量不代表同时运行数量。

## 配置位置与生效

角色定义位于本仓库 `.codex/agents/zonebox-*.toml`，项目路由规则位于 `AGENTS.md`。

用户级 Codex 默认模型在 `~/.codex/config.toml`；OpenCodex 的子 Agent 默认值、模型列表、搜索和图片辅助设置是用户级设置，会影响其他项目。已有任务可能保留原模型；在旧任务继续工作前检查模型选择器。修改文件不会把当前正在运行的回合切换成 Grok。

新角色需要由新的 Codex 会话加载。新任务如果未显示新角色，保存其他工作后重启 Codex，再在本项目开启任务。其他独立 worktree 如果没有这些未提交的角色文件和 AGENTS.md 更新，不应假定它们已经安装；先把这组配置带入目标 checkout。

可用以下只读命令检查运行时设置：

```sh
ocx agent status --json
ocx effort model xai/grok-4.6
ocx config validate
```

本机 Grok 的 `max` 和 `ultra` 被映射为 `xhigh`，日常无需使用它们。
