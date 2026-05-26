# Agent Workloop 架构

## 分层

Agent Workloop 分四层：

1. 全局 CLI 层：安装在 `$HOME\.ai-tools\bin`，所有项目复用。
2. 项目数据层：每个项目只保存 `.ai-relay/` 数据，不保存工具脚本。
3. Pair 协议层：每个 pair 保存绑定信息、任务、报告、裁决、历史。
4. Dashboard 层：本机 localhost 控制面板，负责扫描、展示和触发安全操作。

## Pair 模型

一个 pair 表示：

```text
pair = codexSessionId + Claude Code session + projectRoot + pairDir
```

pair 的职责边界：

- Codex session：同一个 pair 的长期指挥线程。
- Claude Code session：同一个 pair 的执行工程师会话。
- pairDir：该 pair 的全部中转文件、历史、状态、总结。

多个 pair 可以在同一个项目内并存，但多个写代码 pair 并行会冲突。建议同一工作区同一时间只有一个写代码 pair，其余 pair 做只读分析或 review；真正并行写代码建议用 git worktree。

## 关键脚本

Relay 基础脚本：

```text
ai-relay-bind-cc.ps1
ai-relay-bind-codex.ps1
ai-relay-codex.ps1
ai-relay-cc.ps1
ai-relay-export.ps1
ai-relay-review.ps1
```

Workloop 脚本：

```text
ai-workloop.ps1
ai-workloop-runner.ps1
ai-workloop-cc-runner.ps1
ai-workloop-plan-runner.ps1
ai-workloop-summary.ps1
ai-workloop-summary-runner.ps1
ai-workloop-dashboard.ps1
ai-workloop-dashboard-server.ps1
```

## 数据结构

项目内结构：

```text
.ai-relay/
  current-pair.json
  pairs/
    <pair>/
      pair.json
      goal.json
      bind-request.md
      context.md
      cc-inbox.md
      cc-report.md
      codex-prompt.md
      codex-reply.md
      relay-log.md
      history/
      reviews/
      summary/
      *-runner-status.json
      *-runner-output.md
      *-runner-process.*.log
```

## 进程模型

没有常驻 daemon。Dashboard server 是用户主动启动的 localhost 控制器，关闭 PowerShell 窗口即停止。

Runner 是一次请求触发的一次性进程：

- 可后台执行，状态写入文件。
- 可打开前台终端，让用户看到 Codex 或 Claude Code 原生输出。
- 不注入已有终端，不向已有窗口自动输入。

## Session 扫描

Codex session 扫描：

```text
C:\Users\<user>\.codex\sessions\**\*.jsonl
```

Claude Code session 扫描：

```text
C:\Users\<user>\.claude\projects\**\*.jsonl
```

Dashboard 只读扫描这些文件，用于选择和绑定 session。已经被其他 pair 绑定的 session 应显示绑定标记，但不强制禁止选择；用户可以显式重绑。

## 同步规则

源码修改后，常见同步目标：

```text
E:\work\project\faizlee-open-skills\ai-relay\scripts\*.ps1
  -> C:\Users\faizl\.ai-tools\bin\*.ps1
```

技能和命令文档修改后，同步到：

```text
C:\Users\faizl\.codex\skills\ai-relay\
C:\Users\faizl\.claude\skills\relay\
C:\Users\faizl\.claude\commands\
```

