# Agent Workloop 本地上下文

这份文件是给 Codex / Claude Code 新对话快速恢复上下文用的。维护 AI Relay / Agent Workloop 时，优先读本文件；只有需要细节时再读同目录专题文档。

## 当前定位

Agent Workloop 是用户级本机协作工具。它让同一项目内多个 Codex / Claude Code pair 通过项目内 `.ai-relay/pairs/<pair>/` 文件互通。

当前主流程：

1. 用户创建或绑定 pair。
2. Codex 负责规划、验收、裁决、风险判断和下一轮最小任务。
3. Claude Code 负责执行、验证、写压缩报告。
4. Workloop runner 根据 pair 状态把 `cc-report.md` 送给 Codex，或把 Codex 指令送给 Claude Code。
5. Dashboard 作为本机控制面板展示状态、启动 runner、打开终端、生成总结和审计。

## 绝对边界

- 不使用 Codex subagent。
- 不启动 `codex-with-cc`。
- 不使用 `--last`。
- Codex 恢复会话必须使用明确 `codexSessionId`。
- 不做 daemon。
- 不做窗口注入。
- 不自动控制另一个已有终端。
- 默认不修改业务代码；只改本工具脚本、文档和项目内 `.ai-relay` 数据。

## 重要路径

源码：

```text
E:\work\project\faizlee-open-skills\ai-relay\
```

全局安装：

```text
C:\Users\faizl\.ai-tools\bin\
C:\Users\faizl\.ai-tools\ai-relay\
```

项目数据：

```text
<project>\.ai-relay\pairs\<pair>\
```

## 核心文件

工具源码脚本：

```text
ai-relay/scripts/_ai-relay-common.ps1
ai-relay/scripts/ai-workloop.ps1
ai-relay/scripts/ai-workloop-runner.ps1
ai-relay/scripts/ai-workloop-cc-runner.ps1
ai-relay/scripts/ai-workloop-plan-runner.ps1
ai-relay/scripts/ai-workloop-summary-runner.ps1
ai-relay/scripts/ai-workloop-dashboard-server.ps1
ai-relay/scripts/ai-workloop-dashboard.ps1
```

pair 数据：

```text
pair.json
goal.json
cc-inbox.md
cc-report.md
codex-prompt.md
codex-reply.md
relay-log.md
history/
summary/
*-runner-status.json
*-runner-output.md
*-runner-process.*.log
```

## Runner 是什么

Runner 是一次性前台或后台进程包装器，不是常驻 daemon。

- `ai-workloop-runner.ps1`：执行完整状态机，决定拉任务、送审、收裁决、继续下一轮。
- `ai-workloop-cc-runner.ps1`：启动 Claude Code 执行任务，写 `cc-report.md`。
- `ai-workloop-plan-runner.ps1`：启动 Codex 根据用户目标规划 `cc-inbox.md`。
- `ai-workloop-summary-runner.ps1`：生成或检查 pair 总结。

Runner 的状态文件只描述进程状态，不等同于业务结果。比如 summary runner `completed` 只代表进程结束；总结业务结果还要看缓存命中、缓存未命中、是否生成 markdown/html。

## Dashboard 当前设计

Dashboard 是本机 localhost 控制器：

- 只在本机 dev/local 使用。
- 可以扫描项目、创建 pair、选择 Codex/Claude session。
- 可以启动 Workloop、CC runner、Codex planner、summary runner。
- 可以打开 pair 目录、报告、裁决、项目目录、Codex/Claude 前台终端。
- 应把“需要用户处理”的 pair 推到前面。
- 应清楚区分“进程状态”和“业务状态”。

## 新对话维护流程

1. 读本文件。
2. 需要架构时读 `architecture.md`。
3. 需要修状态判断时读 `state-machine.md`。
4. 需要修页面和按钮时读 `dashboard.md`。
5. 需要判断方向或边界时读 `decisions.md`。
6. 遇到历史坑时读 `known-issues.md`。
7. 修改源码后同步到全局 `C:\Users\faizl\.ai-tools\bin\`。
8. 对 PowerShell 脚本做 Parser 语法检查。

## 验证最低要求

```powershell
$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile('<script.ps1>', [ref]$tokens, [ref]$errors) | Out-Null
$errors
```

如果改了 Dashboard server，全局同步后需要重启：

```powershell
ai-workloop-dashboard-server.ps1 -Open
```

