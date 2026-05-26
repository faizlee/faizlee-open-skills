# Dashboard 设计说明

## 目标

Dashboard 的目标不是展示所有文件，而是回答用户进入面板后最关心的三个问题：

1. 哪些 pair 需要我处理？
2. 每个 pair 当前到底在做什么，是否正常？
3. 这个 pair 主要目标、最新结论和下一步是什么？

## 首页信息架构

首页优先级：

1. 顶部统计：pair 总数、项目数、需要处理、正在运行、空闲、未读裁决、未读任务。
2. “需要你处理”区：放报告待送审、未读裁决、未读任务、stale/failed 的 pair。
3. Pair 卡片：目标、状态说明、当前结论、轮次、最新裁决、最后更新。
4. 详情区：绑定字段、runner 状态、历史轮次、数据路径。
5. 操作按钮按用途分组。

## Pair 卡片按钮分组

建议分组：

流程：

- 执行 `/workloop`
- 让 Codex 规划任务
- 打开 Codex 终端
- 打开 CC 原会话

查看：

- 打开 Pair
- 打开报告
- 打开裁决
- 打开项目
- 查看 Workloop 输出
- 查看 CC 输出
- 查看 Codex 规划
- 查看总结生成

绑定：

- 绑定/重绑 Codex
- 绑定/重绑 CC

总结 / 审计：

- 查看总结
- 重新生成总结（CC）
- 重新生成总结（Codex）
- 重新生成本地摘要
- 生成审计
- 生成复盘

复制 / 调试：

- 复制 `/workloop`
- 复制 PowerShell
- 复制 Pair 路径

归档：

- 归档 Pair

## 创建 Pair 表单

表单应支持：

- 项目选择。
- Pair 名称，自动规范化为安全文件名。
- 目标。
- Codex session 选择框：
  - `None - 创建新 Codex 会话`
  - 最近 session，支持搜索 title/sessionId/cwd。
  - 显示是否已被其他 pair 绑定。
  - Advanced 手动输入 fallback。
- Claude Code session 选择框：
  - `None - 执行时打开新的 Claude Code 终端`
  - 扫描 `.claude/projects/**/*.jsonl`。
  - 显示是否已被其他 pair 绑定。
  - Advanced 手动输入 fallback。

选 None 的含义：

- Codex None：先创建 bind-request，用户去新 Codex 会话绑定，或后续由面板创建/绑定。
- Claude None：执行时打开新的 Claude Code session，并写回 `ccSessionId`。

## 状态页

状态页必须避免只给原始 JSON。

应显示：

- 进程状态。
- 业务状态。
- 当前可行动作。
- stdout/stderr/output 摘要。
- 关键文件链接。
- 如果是 stream-json，应渲染成接近 TUI 的事件流：思考状态、工具调用、文件修改、报告写入、Codex 裁决。

### Workloop runner 状态页

Workloop runner 状态页需要优先显示结构化阶段，而不是让用户读 stdout：

- `phase`: 当前阶段，例如 `codex_review`、`cc_execute`、`cc_followup`、`completed`、`needs_user`、`idle`。
- `route`: 当前文件路由，例如 `cc-report.md -> Codex` 或 `codex-reply.md -> Claude Code`。
- `nextAction`: 用户或系统下一步应该做什么。
- `snapshot`: 当前 pair 文件快照，包括 report/reply/inbox 是否存在、是否未读、goal 状态和轮次。

页面展示顺序：

1. 当前阶段卡片：一句话说明现在卡在哪、下一步是什么。
2. 阶段列表：检查状态 -> Codex 裁决 -> Claude Code 执行 -> 收口。
3. 原始 runner 输出、stdout、stderr 作为诊断资料放在下方。

`running -> stale` 时不能只提示“看 stderr”。如果 `cc-report.md`、`codex-reply.md` 或 `cc-inbox.md` 已经更新，应按文件快照判断实际状态。

### CC runner 状态页

CC runner 状态页优先展示 `cc-runner-stream.jsonl` 的可读事件流：

- 系统事件：状态、hook、重试。
- Assistant 消息：Claude Code 的文本输出。
- 工具调用：工具名和输入摘要。
- 工具结果：结果摘要。

原始 stdout/stderr 仍保留在下方用于诊断，但不是主要阅读入口。

## Summary HTML Artifact

Summary HTML 是主要阅读入口，不是简单把 Markdown 包进 `<pre>`。

结构：

- 顶部：当前结论、目标偏移、执行效率、是否需要用户介入。
- 粘性导航：结论、结构图、分析、时间线、证据、下一步。
- 中部：目标状态、AI 分析摘要、轮次时间线。
- 结构图：对可识别主题生成专用视觉结构。例如 Knowledge Pyramid 自动展示 L0-L7、Schema、Concept 实例、Domain 决策、工作流集成。
- 下部：文件热点、问题热点、偏移信号、可展开证据片段、原始 Markdown 折叠。
- 右侧：推荐动作、下一步指令、风险快照。
- 交互：下一步可复制，文件热点尽量链接到本地文件。
- 渲染：AI 摘要中的 Markdown 表格转成真实 HTML table；短文件名会按项目根、`docs/project/`、`docs/`、`.ai-relay/` 顺序尝试解析为本地链接。

Markdown 继续保留，作为原始文本、归档和可 diff 产物；HTML 负责阅读和决策。

## 视觉原则

- 需要用户处理的内容放前面。
- 首页固定优先级为：需要你处理、正在运行、最近完成 / 可归档。
- Pair 卡片主状态必须优先表达“用户动作状态”，例如报告待送审、未读裁决、未读任务、总结过期；runner 的 raw 状态只放在详情区。
- 不把所有按钮堆成一排。
- “执行类按钮”和“查看类按钮”要分开。
- `failed`、`stale`、`cache miss` 要有清楚的人话解释。
- 打不开的文件不要给可点击操作，显示“尚不可用”。

## 通用状态解释

所有 runner 状态页都要区分两层状态：

- Runner 状态：进程是否启动、运行、完成、失败或过期。
- 结果状态：是否真的生成了可用结果，例如总结 HTML、Codex 裁决、CC 报告。

状态页顶部必须显示统一的“当前解释”卡片：

- 当前到底发生了什么。
- 是否需要用户介入。
- 下一步应该做什么。
- 原始 stdout/stderr 只作为诊断区，不作为主要阅读入口。

## Review HTML

复盘报告 HTML 也使用结构化视图：

- 总览指标：部分接受/不接受、返工、乱码、缺少验证。
- 低效循环信号。
- 轮次时间线。
- 文件热点，本地可解析路径应生成 `file://` 链接。
- 命令/验证线索。
- 原始 Markdown 折叠保存，作为事实源和可 diff 文本。
