# Agent Workloop

面向本机 coding agent 的协作闭环工具。当前核心场景是 Claude Code 执行、Codex 审核裁决，底层通过项目内文件做轻量 relay。

## 适用场景

- 你希望一个项目里同时存在多个 Codex / Claude Code pair。
- Codex 负责验收、裁决、风险判断和下一轮最小任务指令。
- Claude Code 负责执行、验证和写压缩报告。
- 你希望围绕一个目标形成可控、可追踪、可复盘的 Agent Workloop。
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
/workloop
```

Claude Code 拉取并执行：

```text
/workloop bug-typeerror
```

Claude Code 完成后写 `cc-report.md`，再由 workloop 调用 `Mode report` 汇报给 Codex。

Claude Code 侧 `/workloop <pair>` 不带 goal 时，会按顺序检查：

1. `codex-reply.md` 是否有未读 Codex 裁决。
2. `cc-inbox.md` 是否有未读新任务。
3. `cc-report.md` 是否比 `codex-reply.md` 新，若是则由 `/workloop <pair>` 直接送审。
4. 否则提示当前没有新消息。

## 常用命令

```powershell
ai-relay-bind-cc.ps1 -Pair <pair>
ai-relay-bind-codex.ps1 -Pair <pair> -CodexSessionId <id>
ai-workloop.ps1 <pair> [goal...]
ai-workloop-project.ps1 -Mode add -ProjectRoot <path>
ai-workloop-project.ps1 -Mode list
ai-workloop-dashboard.ps1 -ProjectRoot <path> -Open
ai-relay-codex.ps1 -Pair <pair> -Message "<message>"
ai-relay-cc.ps1 -Pair <pair> -Mode pull
ai-relay-cc.ps1 -Pair <pair> -Mode report
ai-relay-use.ps1 -Pair <pair>
ai-relay-current.ps1
ai-relay-list.ps1
ai-relay-open.ps1 -Pair <pair>
ai-relay-export.ps1 -Pair <pair> -Format both
ai-relay-review.ps1 -Pair <pair> -Format both
ai-relay-goal.ps1 -Pair <pair> -Goal "<goal>" -MaxRounds 5
```

Claude Code slash command：

```text
/bind <pair>
/workloop <pair> [goal]
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
- Claude Code 已读 Codex 裁决标记
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

## Dashboard

生成本机只读中文面板，不调用 Codex，不启动服务，不控制终端：

```powershell
ai-workloop-dashboard.ps1 -ProjectRoot "E:\work\project\faizleecom" -Open
```

也可以先注册常用项目：

```powershell
ai-workloop-project.ps1 -Mode add -ProjectRoot "E:\work\project\faizleecom,E:\work\project\faizlee-open-skills"
ai-workloop-project.ps1 -Mode list
ai-workloop-dashboard.ps1 -Open
```

也可以一次扫描多个项目：

```powershell
ai-workloop-dashboard.ps1 -ProjectRoot "E:\work\project\faizleecom","E:\work\project\faizlee-open-skills" -Open
```

默认输出：

```text
$HOME\.ai-tools\workloop-dashboard\index.html
```

面板会展示项目、pair、状态、轮次、最新目标、最新报告、最新 Codex 裁决、历史轮数和下一步命令。

面板会给出健康提示：

- 报告待送审
- 未读 Codex 裁决
- 未读任务
- running 状态长时间未更新
- 接近最大轮次
- 历史轮次较多，可能进入低效循环

面板操作只做安全辅助：

- 复制 `/workloop <pair>`
- 复制 PowerShell 命令
- 复制 pair 路径
- 打开项目目录、pair 目录、history 目录
- 打开最新报告和最新裁决文件

面板按钮不会直接调用 Codex，也不会自动控制 Claude Code / Codex 终端。

## Agent Workloop

Agent Workloop 是基于 relay 的多轮协作闭环：

```text
目标 -> Claude Code 执行 -> cc-report.md -> Codex 裁决 -> Claude Code 继续
```

启动：

```powershell
ai-workloop.ps1 logicmap
ai-workloop.ps1 logicmap 完成治理地图第二模块
ai-relay-goal.ps1 -Pair logicmap -Goal "完成治理地图第二模块" -MaxRounds 5
```

`/workloop <pair>` 不带 goal 时，会执行状态同步能力：检查未读 Codex 裁决、未读任务、等待裁决或空闲状态。如果 `cc-report.md` 已写好且新于 `codex-reply.md`，会直接调用 Codex 送审，不需要用户切到 Codex 读取。

Claude Code 规则：

- 每轮完成后必须写 `cc-report.md`。
- 写完报告后立即执行 `ai-relay-cc.ps1 -Pair <pair> -Mode report`。
- 或直接执行 `ai-workloop.ps1 <pair>`，由统一入口判断并送审。
- `Mode report` 会读取 `cc-report.md`，用 `pair.json` 里的明确 `codexSessionId` 调用 Codex，并把裁决写入 `codex-reply.md`。
- `Mode report` 会自动更新 `goal.json`，并写入 `goal/goal-summary-latest.md`。
- 如果 Codex 回复中有下一轮指令，Claude Code 直接继续执行，不需要用户确认。
- 如果 Codex 接受/完成，workloop 停止。
- 达到 `MaxRounds`、出现冲突风险或验证无法安全完成时停止。
- 不要自动 push，除非用户明确要求。

## 验证

```powershell
.\tests\verify.ps1
```

验证内容包括脚本语法、禁用项、明确 session id、read-only sandbox、dry-run bind。

## 限制

- 不会自动把后台 Codex 输出插入当前 Codex UI。
- `/workloop <pair>` 负责状态同步；`/workloop <pair> <goal>` 负责目标闭环。不会自动把后台 Codex 输出插入当前 Codex UI。
- 多个写代码 pair 同时修改同一工作区可能冲突，建议使用 git worktree。
- 已被覆盖且未归档的旧轮次无法完整恢复。
