# 已知问题和历史坑

## PowerShell 5.1 编码

问题：

- Windows PowerShell 5.1 对 UTF-8 BOM、控制台编码和管道输出敏感。
- 脚本里大量中文字符串可能在 runner 输出中变成乱码。

处理：

- 脚本逻辑尽量 ASCII。
- 面向用户的长中文文案可以放 HTML/Markdown，避免作为 PowerShell 错误消息反复拼接。
- 必要时设置 `[Console]::OutputEncoding` 和 `$OutputEncoding`。

## 参数绑定错误

问题：

- PowerShell 函数参数如果是 `[int]$ExitCode`，但调用时字符串拼接错位，可能出现“无法将值转换为 System.Int32”。

处理：

- 长参数调用优先显式命名。
- runner 状态写入函数避免复杂位置参数。
- 修改后必须 Parser 检查。

## `completed` 被误解

问题：

- Summary runner `completed` 曾被显示为“Pair 总结完成”，但实际只是缓存检查结束，stdout 里是 `Pair summary cache miss.`。

处理：

- 页面拆成 `Runner 状态` 和 `总结结果`。
- cache miss 显示“缓存未命中”，并提示重新生成。

## 总结缓存自我失效

问题：

- 早期 `Get-SummarySourceHash` 把 `relay-log.md` 纳入缓存签名。
- 生成或检查总结会追加 `relay-log.md`，导致刚生成过的总结下一次就 cache miss。

处理：

- 总结缓存签名排除 `relay-log.md`。
- 缓存签名只看 pair 绑定、目标、任务、报告、Codex 裁决和历史轮次等真实会影响总结内容的文件。

## stale 状态

问题：

- 状态文件仍是 running，但进程已退出。
- 可能是状态文件未能最终回写，也可能是进程异常退出。

处理：

- Dashboard 检查 PID 是否存在。
- 同时读取 stdout、stderr、runner output、`cc-report.md`、`codex-reply.md`。
- 如果 report 已更新，不要直接判失败，提示可能已完成但状态回写缺失。

## 前台 TUI 不自动退出

问题：

- Claude Code / Codex 原生 TUI 适合观察，但通常不会自动退出。
- 如果用前台 TUI 执行任务，后续自动状态机可能无法继续。

处理：

- 自动流程使用 runner / `--print` / 文件状态。
- 前台终端用于观察和人工接管。
- 不要用窗口注入强行控制 TUI。

## Hook 审核弹窗

问题：

- Codex 进入项目时可能提示 Hooks need review。
- 选择“不信任继续”后，下次仍可能出现，因为 hook 仍是 new/changed。

处理：

- 如果 hook 是已知来源且需要保留，Review 后 Trust。
- 如果插件不需要，例如 `codex-plugin-cc` 或 `codex-with-cc`，可以移除配置，减少干扰。

## Session ID 缺失

问题：

- 旧 pair 可能只有 `ccSessionName`，没有 `ccSessionId`。
- Dashboard 需要 `ccSessionId` 才能打开原 Claude Code 会话。

处理：

- 用绑定/重绑 CC 功能补 `ccSessionId`。
- 创建 pair 时如果选择 Claude None，应在执行时打开新 Claude Code session，并写回 session id。

## 面板按钮太多

问题：

- 所有按钮堆在一起时，用户找不到重点。

处理：

- 按“流程、查看、绑定、总结/审计、复制/调试、归档”分组。
- 首页只露出主动作，更多动作放详情。

## 进程堆积

问题：

- 多次打开前台终端、MCP、Dashboard server，可能留下很多 PowerShell/cmd/node 进程。

处理：

- Dashboard 提供进程诊断页。
- 标记可能的孤儿 MCP 子进程。
- 不自动杀用户终端，清理必须由用户明确触发。
