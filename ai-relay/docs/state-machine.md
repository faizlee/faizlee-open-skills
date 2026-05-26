# Agent Workloop 状态机

## 核心状态文件

pair 业务文件：

```text
cc-inbox.md       Codex 给 Claude Code 的任务
cc-report.md      Claude Code 的压缩执行报告
codex-prompt.md   送给 Codex 的裁决 prompt
codex-reply.md    Codex 的裁决和下一步
goal.json         当前目标、最大轮次、轮次计数
relay-log.md      事件流水
history/          每轮归档
```

runner 状态文件：

```text
cc-runner-status.json
workloop-runner-status.json
codex-plan-status.json
summary-runner-status.json
```

注意：runner 状态是“进程状态”，不是最终业务判断。

## Workloop 主流程

用户输入目标或点击面板规划：

1. Codex planner 基于用户目标和 pair 上下文生成最小任务。
2. 任务写入 `cc-inbox.md`。
3. Claude Code 执行任务，写 `cc-report.md`。
4. Workloop runner 读取 `cc-report.md`，生成 `codex-prompt.md`。
5. 使用明确 `codexSessionId` 调用 `codex exec resume <id>`。
6. Codex 裁决写入 `codex-reply.md`。
7. 如果 Codex 给下一轮任务，写回 `cc-inbox.md` 并继续。
8. 如果 Codex 接受或判定完成，pair 进入 idle。

## 状态判断优先级

Dashboard 应把需要处理的 pair 放前面：

1. `cc-report.md` 新于 `codex-reply.md`：报告待送审。
2. `codex-reply.md` 新于已读标记：有未读裁决。
3. `cc-inbox.md` 新于已读标记：有未读任务。
4. runner 状态 running 且进程存在：正在运行。
5. runner 状态 running 但进程不存在：stale，需要看输出和报告。
6. 无待处理：idle。

## Runner 状态

通用 runner 状态：

```text
queued
started
running
completed
failed
stopped
stale
unknown
```

解释：

- `completed`：runner 进程结束，退出码或输出表明命令完成。
- `failed`：runner 进程失败，需要看 stderr/output。
- `stale`：状态文件还写 running，但进程已经不存在。

`completed` 不一定代表业务完成。例子：

- Summary runner `completed` + `cache miss` = 只是缓存检查结束，没有生成总结。
- Workloop runner `completed` = 状态机本轮结束，但可能只是送审完成或已写下一轮任务。

## Summary 状态

Summary 页面必须拆成两层：

```text
Runner 状态：started/running/completed/failed
总结结果：生成中/缓存命中/缓存未命中/已生成/失败/无总结
```

规则：

- `Pair summary cache miss.`：显示“缓存未命中”，提示重新生成，不显示为“总结完成”。
- `Pair summary cache hit.`：显示“缓存命中”，可以打开 HTML。
- `Pair summary generated:`：显示“已生成”，可以打开 HTML。
- 没有 HTML 文件时，不要提供会失败的“打开总结 HTML”动作。

## 前台终端和自动化

前台终端适合观察 Codex / Claude Code 原生输出。

限制：

- 原生 TUI 通常不会在任务结束后自动退出。
- 如果任务需要自动串下一步，优先使用 `--print` 或 runner 输出文件。
- 前台终端可用于查看过程，但不应依赖窗口注入推进流程。

