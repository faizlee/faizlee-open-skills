# Agent Workloop Skill

## 目的
用户级 Agent Workloop 工作流，用于让同一项目内多个 Codex / Claude Code pair 通过项目内文件互通，并支持可追踪的协作闭环。

## 核心规则
- 一个 pair = 一个 Codex session id + 一个 Claude Code 会话。
- 每个 pair 使用项目内 .ai-relay/pairs/<pair>/ 保存状态。
- 禁止使用 --last。
- 禁止使用 subagent。
- 禁止启动 codex-with-cc。
- 禁止把完整项目代码塞进 prompt。
- Codex 只做验收、裁决、风险判断、下一步指令。
- 不要重新发明脚本。
- 不要修改业务代码，除非用户明确要求。

## /bind <pair>
当用户在 Codex 中输入 /bind <pair>：
1. 优先读取当前项目 .ai-relay/pairs/<pair>/bind-request.md。
2. 如果文件不存在，再要求用户粘贴 Claude Code 生成的 bind-request.md 内容。
3. 获取当前 Codex session id。可让用户运行 /status，或读取当前 Codex CLI 可用的 session 信息。
4. 调用：
   ai-relay-bind-codex.ps1 -Pair <pair> -CodexSessionId <id>
5. 绑定完成后，该 Codex 会话就是此 pair 的指挥线程。

## /workloop [pair]
当用户在 Codex 中输入 /workloop：
1. 如果用户给出 pair，则使用该 pair。
2. 如果没有给出 pair，则读取 .ai-relay/current-pair.json。
3. 基于当前 Codex 对话上下文，生成“给 Claude Code 的下一轮最小任务指令”。
4. 调用：
   ai-relay-codex.ps1 -Pair <pair> -Message "<指令>"
5. 指令必须边界清晰、最小化、可执行。
6. 如果信息不足，不要编造；要求 Claude Code 补充压缩事实。
7. 如果可能和其他 pair 冲突，必须提示。

## /workloop reply|report|prompt [pair]
当用户要查看后台记录：
1. /workloop reply 读取并展示最新 codex-reply.md。
2. /workloop report 读取并展示最新 cc-report.md。
3. /workloop prompt 读取并展示最新 codex-prompt.md。
4. 可调用：
   ai-relay-codex.ps1 -Pair <pair> -ShowReply
   ai-relay-codex.ps1 -Pair <pair> -ShowReport
   ai-relay-codex.ps1 -Pair <pair> -ShowPrompt
5. 这些模式只读，不给 Claude Code 写新指令。

## Codex 输出原则
- 每轮只给一个最小可执行目标。
- 不要求 Claude Code 返回大段日志。
- 只要求 Claude Code 写压缩报告。
- 控制额度。
