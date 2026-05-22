使用 Agent Workloop。它不是普通 `/relay`，而是“目标 -> Agent 执行 -> 报告 -> Codex 裁决 -> Agent 继续执行/完成”的协作闭环。

参数约定：
- 第一个参数是 pair。
- 后面的内容是 goal，可选。
- 如果没有写 goal，不要要求用户补充目标；直接执行 workloop auto，用它替代旧 `/relay`。

始终在当前项目根目录运行统一入口脚本：

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-workloop.ps1" $ARGUMENTS

行为：

- `/workloop com_main`：检查未读 Codex 裁决、未读任务、等待裁决或空闲状态，相当于旧 `/relay com_main`。
- `/workloop com_main 完成治理地图第二模块`：启动 Agent Workloop 目标闭环。

如果脚本打印 workloop 任务，直接执行它。每一轮完成后：

1. 写 `.ai-relay/pairs/<pair>/cc-report.md`。
2. 立即运行：

powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ai-tools\bin\ai-relay-cc.ps1" -Pair "<pair>" -Mode report

3. 读取脚本输出的 Codex 裁决。
4. 如果 Codex 裁决里有下一轮指令，直接继续执行，不需要请求用户确认。
5. `ai-relay-cc.ps1 -Mode report` 会自动更新 `goal.json` 和 `goal/goal-summary-latest.md`。
6. 只在 Codex 接受/完成目标、达到最大轮数、或出现需要用户裁决的冲突时停止。

不要使用 subagents、codex-with-cc、--last。
