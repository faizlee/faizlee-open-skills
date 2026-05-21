# AI Relay

用户级轻量 relay 工具，用于让同一项目中的 Codex / Claude Code pair 通过项目内文件互通。

## 适用场景

- 你希望一个项目里同时存在多个 Codex / Claude Code pair。
- Codex 负责验收、裁决、风险判断和下一轮最小任务指令。
- Claude Code 负责执行、验证和写压缩报告。
- 你不想使用 subagent、不想启动 codex-with-cc、不想用 `--last` 恢复错误会话。

## 核心规则

- 一个 pair = 一个明确的 Codex session id + 一个 Claude Code 会话 + 一组中转文件。
- 全局工具只安装一次，所有项目复用。
- 每个项目只保存自己的 `.ai-relay/pairs/<pair>/` 数据。
- 禁止使用 `--last`。
- 禁止使用 subagent。
- 禁止启动 codex-with-cc。
- 不自动控制另一个终端，不做 daemon，不做窗口注入。
- 后台 Codex 回复会写入文件，并可导出中文审计报告。

## 安装

在本目录运行：

```powershell
.\install.ps1
```

安装位置：

```text
$HOME\.ai-tools\ai-relay\
$HOME\.ai-tools\bin\
$HOME\.codex\skills\ai-relay\
$HOME\.claude\skills\relay\
$HOME\.claude\commands\
```

如果安装脚本把 `$HOME\.ai-tools\bin` 加入 User PATH，需要重启 PowerShell / Terminal。

## 基本流程

Claude Code 侧：

```text
/bind bug-typeerror
```

这会生成：

```text
.ai-relay/pairs/bug-typeerror/bind-request.md
```

如果 Codex 在同一项目目录，可以直接在 Codex 里执行：

```text
/bind bug-typeerror
```

Codex 侧绑定会使用明确的当前 Codex session id，写入：

```text
.ai-relay/pairs/bug-typeerror/pair.json
```

Codex 发指令给 Claude Code：

```text
/relay
```

Claude Code 拉取并执行：

```text
/relay
```

Claude Code 完成后写 `cc-report.md`，再执行 `/relay` 汇报给 Codex。

## 常用命令

```powershell
ai-relay-bind-cc.ps1 -Pair <pair>
ai-relay-bind-codex.ps1 -Pair <pair> -CodexSessionId <id>
ai-relay-codex.ps1 -Pair <pair> -Message "<message>"
ai-relay-cc.ps1 -Pair <pair> -Mode pull
ai-relay-cc.ps1 -Pair <pair> -Mode report
ai-relay-use.ps1 -Pair <pair>
ai-relay-current.ps1
ai-relay-list.ps1
ai-relay-open.ps1 -Pair <pair>
ai-relay-export.ps1 -Pair <pair> -Format both
ai-relay-review.ps1 -Pair <pair> -Format both
```

## 审计报告

导出当前 pair 的中文 Markdown + HTML 报告：

```powershell
ai-relay-export.ps1 -Pair bug-typeerror -Format both
```

报告会包含：

- Pair 绑定信息
- Codex 发给 Claude Code 的最新指令
- Claude Code 最新汇报
- 实际发送给 Codex 的完整 prompt
- Codex 最新回复
- Relay 时间线
- 历史归档

## 历史归档

每次执行：

```powershell
ai-relay-cc.ps1 -Pair <pair> -Mode report
```

都会保存：

```text
.ai-relay/pairs/<pair>/history/<轮次>/
  cc-report.md
  codex-prompt.md
  codex-reply.md
  summary.json
```

查看历史：

```powershell
ai-relay-codex.ps1 -Pair <pair> -History
ai-relay-codex.ps1 -Pair <pair> -HistoryId <id>
```

## 工作复盘

生成本地规则复盘报告，不调用 Codex，不消耗 Codex 额度：

```powershell
ai-relay-review.ps1 -Pair bug-typeerror -Format both
```

复盘报告会分析：

- 总轮数
- 部分接受 / 不接受轮数
- 返工轮数
- 乱码或报告质量问题
- 验证信息是否缺失
- 反复出现的文件
- 反复出现的问题关键词
- 是否可能进入低效循环
- 下一步建议

如果要让 Claude Code 基于复盘材料写人工总结，可以把生成的 review markdown 交给 Claude Code；默认脚本只做本地规则分析。

## 验证

```powershell
.\tests\verify.ps1
```

验证内容包括脚本语法、禁用项、明确 session id、read-only sandbox、dry-run bind。

## 限制

- 不会自动把后台 Codex 输出插入当前 Codex UI。
- 需要用户在 Codex / Claude Code 两侧手动触发 `/relay`。
- 多个写代码 pair 同时修改同一工作区可能冲突，建议使用 git worktree。
- 已被覆盖且未归档的旧轮次无法完整恢复。
