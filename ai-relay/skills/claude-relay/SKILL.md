# relay Skill

## 目的
让 Claude Code 与绑定的 Codex 指挥线程通过 .ai-relay/pairs/<pair>/ 互通。

## /bind <pair>
当用户输入 /bind <pair>：
1. 调用：
   ai-relay-bind-cc.ps1 -Pair <pair>
2. 生成 bind-request.md。
3. 复制 bind-request.md 到剪贴板。
4. 告诉用户：如果 Codex 在同一项目工作区，可直接在 Codex 中执行 /bind <pair>；否则把剪贴板内容粘贴到对应 Codex 会话，并执行 /bind <pair>。

## /relay [pair]
当用户输入 /relay：
1. 如果 cc-inbox.md 有未读 Codex 指令，读取并执行。
2. 如果当前任务已完成或需要汇报，则先把本轮压缩报告写入 cc-report.md，再调用：
   ai-relay-cc.ps1 -Pair <pair> -Mode report
3. 不要启动 Codex subagent。
4. 不要启动 codex-with-cc。
5. 不要写入其他 pair 目录。

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
