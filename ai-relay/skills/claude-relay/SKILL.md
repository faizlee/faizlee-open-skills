# Agent Workloop Skill

## 目的
让 Claude Code 与绑定的 Codex 指挥线程通过 .ai-relay/pairs/<pair>/ 互通，并支持 Agent Workloop 目标闭环。

## /bind <pair>
当用户输入 /bind <pair>：
1. 调用：
   ai-relay-bind-cc.ps1 -Pair <pair>
   如果能获取当前 Claude Code session id，必须传入：
   ai-relay-bind-cc.ps1 -Pair <pair> -CcSessionId <当前 Claude Code session id>
2. 生成 bind-request.md。
3. 复制 bind-request.md 到剪贴板。
4. 告诉用户：如果 Codex 在同一项目工作区，可直接在 Codex 中执行 /bind <pair>；否则把剪贴板内容粘贴到对应 Codex 会话，并执行 /bind <pair>。
5. 如果用户说这是已有 pair，只是要补充或刷新 Claude Code session id，不要使用 -Force 重新 bind；调用：
   ai-workloop-rebind-cc.ps1 -Pair <pair> -CcSessionId <当前 Claude Code session id>
   这个脚本会保留已有 cc-report.md、codex-reply.md、relay-log.md 和 codexSessionId。

## /workloop <pair> [goal]
当用户输入 /workloop：
1. 这是唯一推荐的 Claude Code 侧入口，替代旧 `/relay`。
2. 必须先调用统一入口脚本：
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-workloop.ps1" <pair> <goal...>
3. 如果用户只输入 pair、没有 goal，不要要求用户补充目标；脚本会执行 workloop auto，检查未读裁决、未读任务、等待裁决或空闲状态。
   - 如果 `cc-report.md` 已写好且新于 `codex-reply.md`，脚本会直接送审给 Codex。
4. 如果用户输入 pair + goal，脚本会启动 Agent Workloop 目标闭环。
5. 执行脚本输出的任务或裁决。
6. 每完成一轮任务后：
   - 写 `.ai-relay/pairs/<pair>/cc-report.md`
   - 立即调用 `ai-workloop.ps1 <pair>` 或 `ai-relay-cc.ps1 -Pair <pair> -Mode report`
   - 读取脚本输出的 Codex 裁决；该脚本会自动更新 `goal.json` 和 `goal/goal-summary-latest.md`
   - 如果 Codex 给出下一轮指令，直接继续执行，不需要用户确认
   - 如果 Codex 接受/完成，停止
7. 不要自动 push，除非用户明确要求。
8. 达到 max rounds、出现冲突风险、验证无法安全完成时停止。
9. 禁止在写完 `cc-report.md` 后只说“等待 Codex 读取”。
10. 禁止提示用户“请在 Codex 中执行 /relay <pair>”。`/relay` 已废弃，送审由 `/workloop <pair>` 或 `Mode report` 完成。

## 旧 relay 行为
用户侧不再安装 `/relay` 命令。旧 relay 的状态同步行为已经并入 `/workloop <pair>`。

如果需要解释旧行为：
1. 不要自行读取 `cc-inbox.md` / `cc-report.md` / `codex-reply.md` 做时间比较。
2. 必须先调用用户级脚本，让脚本处理 relay 状态机：
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-cc.ps1" -Pair <pair> -Mode auto
3. 该脚本会按顺序检查：
   - `codex-reply.md` 是否有未读 Codex 裁决。
   - `cc-inbox.md` 是否有未读 Codex 新任务。
   - `cc-report.md` 是否比 `codex-reply.md` 新，是否需要送审。
   - 是否空闲。
4. 必须优先读取脚本输出的机器状态：
   - `AI_RELAY_STATUS=CODEX_REPLY_UNREAD`：读取并执行脚本输出的 Codex 裁决。
   - `AI_RELAY_STATUS=CC_INBOX_UNREAD`：读取并执行脚本输出的 Codex 新任务。
   - `AI_RELAY_STATUS=WAITING_FOR_CODEX`：报告比回复新，应立即执行 `ai-workloop.ps1 <pair>` 或 `ai-relay-cc.ps1 -Pair <pair> -Mode report` 送审。
   - `AI_RELAY_STATUS=IDLE`：没有新消息，也没有未读裁决；不要说“等待 Codex 裁决”。
5. 普通 relay 中，如果当前任务已完成或需要汇报，则先把本轮压缩报告写入 cc-report.md，再调用：
   ai-relay-cc.ps1 -Pair <pair> -Mode report
6. 不要启动 Codex subagent。
7. 不要启动 codex-with-cc。
8. 不要写入其他 pair 目录。

## cc-report.md 格式

# CC Report

## 当前任务
一句话说明当前任务。

## Claude Code 本轮做了什么
只列关键动作，不贴大段日志。

## 修改文件
列出文件路径。

## 验证结果
列出运行过的测试/命令和结果。

## 风险 / 疑问
列出未解决问题、可疑点、可能超范围的地方。

## 是否可能与其他 pair 冲突
说明是否可能改到其他 pair 也在处理的文件。
如果无法判断，写无法判断。

## 需要 Codex 裁决的问题
明确问 Codex：
1. 是否接受本轮结果
2. 是否需要返工
3. 下一步做什么

## 规则
- 不要贴完整 diff。
- 不要贴长日志。
- 报告是给 Codex 做裁决的压缩事实。
- 如果当前 pair 不明确，先读取 .ai-relay/current-pair.json；若仍不明确，要求用户指定 pair。
