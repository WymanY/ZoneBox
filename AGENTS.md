# Agent notes

These rules apply only to this ZoneBox repository (`/Users/wyman/Documents/fancyzone_mac`).

## Issue tracking

Do not create Linear issues, sub-issues, comments, or status updates for work in this project.

Do not file leftover work in Linear.

## Pull requests

Do not open a GitHub pull request unless the user explicitly asked to create one.

Implement and verify on a branch or worktree if needed, then wait. If the user later asks for a PR, open it with `gh pr create` and give the link.

Do not merge into `main` unless the user explicitly asks to merge.

## Website

The product site is a separate project. Do not add website files to this app repository.

| What | Where |
| --- | --- |
| Site checkout | `/Users/wyman/Documents/zonebox-site` |
| Site GitHub | https://github.com/WymanY/zonebox-site |
| Live site | https://zonebox-site.wuyun768.workers.dev |
| Previous Vercel site | https://zonebox-site.vercel.app |

For site copy and feature explanations, read this app's `README.md`, `docs/onboarding-design.md`, and `ZoneBox/Domain/L10n.swift`, then edit the site repo.

## Project status

When asked to analyze this project's status, including worktrees, git state, stashes, running ZoneBox processes, or PR state, spawn the `zonebox_status` custom agent, wait for its report, and return it. Keep that pass read-only: do not implement, create PRs, merge, touch Linear, or clean worktrees unless the user explicitly asks for that separate work.

## Agent routing and model budget

Use the project roles in `.codex/agents/` for bounded specialist work. This section authorizes delegation for the scenarios below; the user's current instructions take precedence. Prefer one worker at a time, and at most two independent workers by default. Do not launch every role for every task. The parent retains responsibility for completing all authorized work and reporting the result.

- `zonebox_design` (Claude Opus): requirements, interaction design and implementation plans. Respect analysis-only requests; approved implementation goes to a worker.
- `zonebox_macos` (Grok): app implementation, repairs and build/run requests. Give it an exact checkout, ownership and acceptance conditions.
- `zonebox_verify` (Claude Opus): independent review and nontrivial behavioral verification. Routine build commands can stay with the Grok worker. Verification findings return to the implementation worker.
- `zonebox_release` (Grok): authorized PR, merge, signing/notarization, release and safe matching-worktree cleanup. PR creation and merge each still require explicit authorization.
- `zonebox_web` (Grok): website and server-side checkout/license work in the separate site checkout. Give it access to the assigned site directory; do not relocate site code into this repository.
- `zonebox_diagnose` (Astra, read-only): one difficult root-cause or architecture question. Use only when the user asks for expert diagnosis, two evidence-based repair attempts fail, or collected evidence demonstrates a critical unresolved cross-module contradiction. Tell the user why OpenAI is being used. Provide a compact evidence packet, then return implementation to Grok. Do not use it for routine review, broad exploration, build loops, or task coordination.

Keep explicit per-role model choices. Do not silently substitute OpenAI for a unavailable routed model. If a configured role is not yet exposed in the current session, report that limitation; use an explicitly model-selected equivalent only when the available tools support it, otherwise continue with the current model only within the user's budget instructions. Never claim a role ran when it did not.

For independent bounded diagnoses, pass a concise evidence packet instead of the full conversation when the tool supports it. Include the assigned checkout/commit, original acceptance conditions, reproduction, logs, relevant files, attempted repairs and scope of authorization. Pass enough context to preserve all user constraints. Do not perform overlapping edits in the same files concurrently.

See `docs/agent-usage.md` for everyday invocation examples and model configuration notes.
