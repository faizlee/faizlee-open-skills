---
name: todo-database
description: |
  【优先触发 - 任务管理】通用项目级持久化 TODO 管理系统

  🚨 扩展触发词（中英文，120+词汇）：

  【任务添加 - Add Task】(24个词汇)
  添加、新建、创建、记录、加入、增加、写到、保存到、记住、别忘了、别忘了
  add, create, new, record, save, add to, put in, remember, don't forget
  + TODO/待办/任务/task/todo/task

  【任务相关 - Task Related】(40个词汇) ⭐NEW
  任务、待办、事项、计划、规划、安排、想法、需求、功能、改进、优化、重构
  问题、bug、错误、修复、解决、实现、完成、处理、跟进、追踪、管理
  task, todo, item, plan, planning, schedule, idea, requirement, feature, improve, optimize, refactor
  problem, bug, error, fix, resolve, implement, complete, handle, follow up, track, manage

  【代码标记 - Code Markers】(8个词汇)
  TODO, FIXME, HACK, XXX, NOTE, BUG, TEMP, WORKAROUND

  【询问式 - Question】(12个词汇)
  有没有、是否存在、在哪儿、位置在哪、状态如何、有哪些、还有什么
  is there, where, status, how about, what about, what else, any more

  【行动式 - Action】(20个词汇)
  需要做、应该做、要做、准备做、计划做、打算、考虑、评估、分析、整理
  need to, should, must, going to, plan to, intend, consider, evaluate, analyze, organize

  【回顾式 - Review】(16个词汇)
  回顾、检查、扫描、查找、搜索、过滤、统计、报告、总结、整理
  review, check, scan, find, search, filter, statistics, report, summarize, organize

  🔴 绝对优先级（最高）：
  - 任何"添加/记录"任务/TODO的请求：立即触发
  - 任何"查看/列出"任务/TODO的请求：立即触发
  - 任何"更新/标记"任务/TODO的请求：立即触发
  - 任何提到"计划/规划/安排"的请求：立即触发

  📌 核心功能：
  - 添加、更新、搜索、删除 TODO
  - 支持优先级 P0-P3
  - 支持类型 Bug/Feature/Refactor/Test/Doc/UI/Config/Optimize
  - 状态追踪（待办/进行中/已完成/已拒绝/已延期）
  - Git 持久化，对话重启不丢失
  - 初始化检查清单（防止遗漏）
  - 多来源任务整合（代码/文档/AI对话）

  📍 适用所有项目：Web、移动端、Unity、Python、通用项目
---

# TODO Database Skill

> **核心承诺**: "重启对话不会丢失 TODO,所有任务都有记录和跟踪"

通用的项目级持久化 TODO 管理系统，通过 Git 追踪的 Markdown 文档存储所有 TODO，确保在 AI 对话重启后依然保留所有有意义的任务和想法。

## 🎯 触发关键词 (120+词汇)

**直接触发关键词 (任一出现即触发)**:

### 任务添加类 (24个词汇)
| 中文关键词 | 英文关键词 | 动作 |
|-----------|-----------|------|
| "添加 TODO" | "add TODO" | 添加新任务 |
| "添加到 TODO 数据库" | "add to TODO database" | 添加新任务 |
| "记录到 TODO" | "record to TODO" | 添加新任务 |
| "新建 TODO" | "create new TODO" | 添加新任务 |
| "添加任务" | "add task" | 添加新任务 |
| "记录任务" | "record task" | 添加新任务 |
| "记住这个" | "remember this" | 添加新任务 |
| "别忘了" | "don't forget" | 添加新任务 |

### 任务相关类 (40个词汇) ⭐NEW
| 类别 | 词汇 | 示例 |
|------|------|------|
| **任务名词** | 任务、待办、事项、item | "有什么任务？" |
| | task, todo, item | "What tasks?" |
| **计划类** | 计划、规划、安排、schedule | "有什么计划？" |
| | plan, planning | "Any plans?" |
| **想法类** | 想法、需求、功能、idea | "有个新想法" |
| | requirement, feature | "New feature idea" |
| **改进类** | 改进、优化、重构、improve | "需要改进" |
| | optimize, refactor | "Need optimization" |
| **问题类** | 问题、bug、错误、problem | "发现一个问题" |
| | bug, error, issue | "Found a bug" |
| **行动类** | 修复、解决、实现、fix | "需要修复" |
| | resolve, implement | "Need to fix" |
| **管理类** | 追踪、管理、整理、organize | "整理任务" |
| | track, manage | "Track tasks" |

### 代码标记类 (8个词汇)
| 标记 | 类型 | 优先级 |
|------|------|--------|
| `//TODO:` | 待办任务 | P1-P3 |
| `//FIXME:` | 需要修复 | P0-P1 |
| `//HACK:` | 临时方案 | P2 |
| `//XXX:` | 重要提醒 | P0-P1 |
| `//NOTE:` | 注释说明 | P3 |
| `//BUG:` | 已知bug | P0-P1 |
| `//TEMP:` | 临时代码 | P2 |
| `//WORKAROUND:` | 变通方案 | P1-P2 |

### 询问类 (12个词汇)
| 中文 | 英文 | 用途 |
|------|------|------|
| "有没有 TODO" | "is there TODO" | 查询存在性 |
| "有哪些任务" | "what tasks" | 列出任务 |
| "还有什么" | "what else" | 追加查询 |
| "状态如何" | "how about status" | 状态查询 |

### 行动类 (20个词汇)
| 中文 | 英文 | 示例 |
|------|------|------|
| 需要做 | need to | "需要做测试" |
| 应该做 | should | "应该重构" |
| 要做 | must | "必须修复" |
| 准备做 | going to | "准备实现" |
| 计划做 | plan to | "计划添加" |
| 打算 | intend | "打算优化" |
| 考虑 | consider | "考虑引入" |
| 评估 | evaluate | "评估方案" |
| 分析 | analyze | "分析问题" |
| 整理 | organize | "整理代码" |

### 回顾类 (16个词汇)
| 中文 | 英文 | 用途 |
|------|------|------|
| 回顾 | review | "回顾任务" |
| 检查 | check | "检查TODO" |
| 扫描 | scan | "扫描代码TODO" |
| 统计 | statistics | "生成统计" |
| 报告 | report | "生成报告" |
| 总结 | summarize | "总结任务" |

**场景触发 (结合上下文)**:

1. **发现问题时**:
   - "发现一个 bug" → 创建 Bug 类型 TODO
   - "有个问题需要修复" → 创建 Bug 类型 TODO
   - "这里有个错误" → 创建 Bug 类型 TODO
   - "有个bug" → 创建 Bug 类型 TODO ⭐NEW

2. **功能想法时**:
   - "应该添加这个功能" → 创建 Feature 类型 TODO
   - "可以改进一下" → 创建 Feature 类型 TODO
   - "有个新想法" → 创建 Feature 类型 TODO
   - "有个计划" → 创建 Feature 类型 TODO ⭐NEW

3. **代码审查时**:
   - "这里需要重构" → 创建 Refactor 类型 TODO
   - "代码有坏味道" → 创建 Refactor 类型 TODO
   - "需要优化" → 创建 Refactor 类型 TODO
   - "需要改进" → 创建 Refactor 类型 TODO ⭐NEW

4. **测试相关**:
   - "测试覆盖不够" → 创建 Test 类型 TODO
   - "需要写测试" → 创建 Test 类型 TODO
   - "缺少测试" → 创建 Test 类型 TODO

5. **规划相关** ⭐NEW:
   - "有什么计划" → 列出所有计划任务
   - "有什么安排" → 列出所有安排
   - "有什么规划" → 列出所有规划
   - "整理任务" → 整理和分类任务

6. **多来源整合** ⭐NEW:
   - "扫描代码TODO" → 扫描所有//TODO注释
   - "检查文档TODO" → 扫描所有文档
   - "回顾AI对话TODO" → 检查对话历史
   - "全面扫描" → 执行所有扫描

## 📁 文件结构

Skill 期望项目根目录有以下文件:

```
PROJECT_TODO_DATABASE.md  # 主数据库 (必需)
TODO_TEMPLATE.md           # 快速模板 (推荐)
```

如果文件不存在，询问用户是否要初始化新的 TODO 数据库。

## 🚀 快速开始

### 1. 检查 TODO 数据库是否存在

```bash
# 检查数据库是否存在
ls PROJECT_TODO_DATABASE.md
```

如果不存在，询问用户是否初始化。

### 2. 添加新 TODO

**步骤 1: 收集信息**
- 标题 (简洁，< 50 字符)
- 优先级 (P0/P1/P2/P3)
- 类型 (Bug/Feature/Refactor/Test/Doc/UI)
- 问题描述 (详细)

**步骤 2: 分配 ID**
- 格式: `TODO-YYYY-XXX`
- 查找现有最大 ID: `grep "ID: TODO-" PROJECT_TODO_DATABASE.md | tail -1`
- 递增编号

**步骤 3: 添加到对应章节**
- P0 → `### 🔴 高优先级 (P0)`
- P1 → `### 🟠 中优先级 (P1)`
- P2 → `### 🟡 低优先级 (P2)`
- P3 → `### ⚪ 待评估 (P3)`

**步骤 4: 更新统计**
- TODO 状态统计 (待办 +1)
- 优先级分布 (对应优先级 +1)
- 类型分布 (对应类型 +1)

### 3. 更新 TODO 状态

**状态转换规则**:
```
待办 → 进行中 → 已解决
  ↓         ↓
已拒绝   已延期
```

**操作步骤**:
1. 搜索找到 TODO (通过 ID 或关键词)
2. 更新状态字段
3. 添加更新记录 (日期 + 操作)
4. 移动到对应章节
5. 更新统计数据

### 4. 搜索和过滤

**按 ID 搜索**:
```bash
grep "TODO-2026-002" PROJECT_TODO_DATABASE.md
```

**按关键词搜索**:
```bash
grep -i "翻译" PROJECT_TODO_DATABASE.md
```

**按优先级过滤**:
```bash
grep -A 20 "### 🟠 中优先级" PROJECT_TODO_DATABASE.md
```

**按类型过滤**:
```bash
grep -B 5 "类型.*UI" PROJECT_TODO_DATABASE.md
```

**按状态过滤**:
```bash
grep -B 5 "状态.*待办" PROJECT_TODO_DATABASE.md
```

### 5. 生成统计报告

**报告格式**:
```markdown
## 📊 TODO 统计报告

生成时间: YYYY-MM-DD HH:mm

### 状态分布
| 状态 | 数量 | 百分比 |
|------|------|--------|
| 待办 | X | Y% |
| 进行中 | X | Y% |
| 已解决 | X | Y% |
| 已拒绝 | X | Y% |
| 已延期 | X | Y% |

### 优先级分布
| 优先级 | 数量 | 百分比 |
|--------|------|--------|
| P0 (高) | X | Y% |
| P1 (中) | X | Y% |
| P2 (低) | X | Y% |
| P3 (评估) | X | Y% |

### 类型分布
| 类型 | 数量 | 百分比 |
|------|------|--------|
| Bug | X | Y% |
| Feature | X | Y% |
| Refactor | X | Y% |
| Test | X | Y% |
| Doc | X | Y% |
| UI | X | Y% |

### 本月完成情况
- 新增: X
- 已完成: X
- 完成率: X%

### 建议关注
- 高优先级待办: X 个
- 长期未更新 (> 7 天): X 个
```

## 📋 TODO 模板

```markdown
### [待办] TODO标题

**元数据**:
- **ID**: TODO-2026-XXX
- **创建日期**: YYYY-MM-DD
- **优先级**: P0/P1/P2/P3
- **类型**: Bug/Feature/Refactor/Test/Doc/UI
- **状态**: 待办/进行中/已解决/已拒绝/已延期
- **负责人**: 待定/XXX
- **相关模块**: XXX系统/XXX模块

**问题描述**:
(详细描述问题或需求,至少包含:
- 当前状态是什么?
- 期望状态是什么?
- 差距是什么?)

**影响范围**:
- 影响模块: XXX
- 影响用户: 是/否 (具体影响)
- 阻塞开发: 是/否 (阻塞什么)
- 紧急程度: 非常紧急/紧急/不紧急

**复现步骤** (如果是 Bug):
1. 步骤1
2. 步骤2
3. 错误结果

**期望行为**:
(应该是什么样子)

**解决方案**:
(可选,记录可能的解决方案或实施思路)

**参考链接**:
- 相关文件: `path/to/file.ext:line`
- 相关文档: `docs/XXX.md`
- 相关Issue: #123
- 相关Commit: abc123

**子任务**:
- [ ] 子任务1 (负责人: XXX, 预估: X小时)
- [ ] 子任务2 (负责人: XXX, 预估: X小时)

**依赖项**:
- 依赖TODO: TODO-YYYY-XXX
- 依赖资源: XXX

**验收标准**:
- [ ] 标准1: XXX
- [ ] 标准2: XXX

**备注**:
(任何补充信息)

**更新记录**:
- YYYY-MM-DD: 创建TODO (创建人: XXX)
- YYYY-MM-DD: 状态变更为"进行中" (更新人: XXX)
```

## 🔧 优先级指南

### P0 (Critical) - 高优先级 🔴
**定义**: 不解决会阻塞开发或严重影响用户

**判断标准**:
- ❌ 阻塞开发的 bug
- ❌ 严重影响用户体验的问题
- ❌ 安全漏洞
- ❌ 数据丢失风险

**行动**: 立即修复，停止其他工作

### P1 (High) - 中优先级 🟠
**定义**: 重要但不紧急，可以规划解决

**判断标准**:
- ⚠️ 重要但不紧急的功能
- ⚠️ 影响开发效率的问题
- ⚠️ 代码重构需求

**行动**: 本周或下周处理

### P2 (Medium) - 低优先级 🟡
**定义**: 改进项，有时间再做

**判断标准**:
- ℹ️ 改进建议
- ℹ️ 优化项
- ℹ️ 文档补充

**行动**: 有时间时处理

### P3 (Low) - 待评估 ⚪
**定义**: 不确定是否实施，需要讨论

**判断标准**:
- ❓ 需要讨论的想法
- ❓ 不确定是否实施
- ❓ 长期规划

**行动**: 评估后决定

## 🎨 类型指南

### 🐛 Bug 修复
- 功能缺陷
- 逻辑错误
- 边界条件问题

### ✨ 新功能 (Feature)
- 待开发的功能
- 功能增强
- 用户请求

### 🔧 重构/优化 (Refactor)
- 代码质量改进
- 性能优化
- 架构调整

### 📚 测试 (Test)
- 测试覆盖
- 测试用例
- 测试基础设施

### 📖 文档 (Doc)
- 文档补充
- 示例代码
- 注释完善

### 🎨 UI/UX
- 界面改进
- 交互优化
- 视觉效果

## 🎯 最佳实践

### TODO 粒度

❌ **不好的 TODO**:
- "修复 bug" (太模糊)
- "优化代码" (无具体目标)
- "写测试" (无范围定义)

✅ **好的 TODO**:
- "修复登录接口在并发情况下的竞态条件"
- "重构用户服务层，降低与数据库的耦合度"
- "为支付模块添加 20 个集成测试覆盖边界条件"

### TODO 描述

❌ **不好的描述**:
- "有问题"
- "需要改进"

✅ **好的描述**:
```
问题描述: 登录接口在高并发情况下会出现用户状态不一致，
导致部分用户无法正常登录。

影响范围:
- 影响模块: src/services/auth.ts
- 影响用户: 所有登录用户 (约 10% 用户受影响)
- 阻塞开发: 否
- 紧急程度: 紧急

解决方案: 使用分布式锁解决并发问题，或实现幂等性接口
```

## 🔄 完整工作流示例

### 示例 1: 添加 Bug TODO

**用户输入**: "添加 TODO: 视频生成失败后积分没有退还"

**Skill 响应**:

1. **确认信息**:
   - 标题: "视频生成失败后积分没有退还"
   - 优先级: P1 (影响用户资产)
   - 类型: Bug
   - 模块: 视频生成/积分系统

2. **生成 ID**: TODO-2026-006

3. **添加到数据库**:
```markdown
### 🟠 中优先级 (P1)

#### [待办] 视频生成失败后积分没有退还

**元数据**:
- **ID**: TODO-2026-006
- **创建日期**: 2026-02-07
- **优先级**: P1
- **类型**: Bug
- **状态**: 待办
- **相关模块**: 视频生成/积分系统

**问题描述**:
当 AI 视频生成失败时，冻结的积分没有被释放回用户账户，导致用户积分损失。

**影响范围**:
- 影响模块: src/services/video.ts, src/services/credit.ts
- 影响用户: 是 (用户积分直接损失)
- 阻塞开发: 否
- 紧急程度: 紧急 (影响用户资产)

**复现步骤**:
1. 用户发起视频生成
2. 视频生成失败 (AI 提供商错误)
3. 冻结的积分未释放

**期望行为**:
视频生成失败时，应该调用 `creditService.release()` 释放冻结的积分。

**解决方案**:
在视频生成的 catch 块中添加积分释放逻辑。

**参考链接**:
- 相关文件: `src/services/video.ts:150`
- 相关代码: `src/services/credit.ts:300`

**子任务**:
- [ ] 检查所有视频生成失败场景
- [ ] 添加积分释放逻辑
- [ ] 测试失败场景积分退回
- [ ] 验证积分正确归还

**验收标准**:
- [ ] 视频失败后积分归还
- [ ] 积分历史记录正确
- [ ] 用户余额正确更新

**更新记录**:
- 2026-02-07: 创建TODO (创建人: Claude)
```

4. **更新统计数据**:
   - 待办: 4 → 5
   - P1: 2 → 3
   - Bug: 0 → 1

5. **确认**: "✅ 已添加 TODO-2026-006"

### 示例 2: 更新 TODO 状态

**用户输入**: "标记 TODO-2026-002 为已完成"

**Skill 响应**:

1. **找到 TODO**: "修复工具页面 Hero 部分中文翻译"

2. **更新状态**:
   - 状态: 待办 → 已解决
   - 完成日期: 2026-02-07
   - 解决方案: "添加了缺失的翻译键，验证了所有工具页面的中文显示"

3. **移动章节**: 从 P1 → 已解决

4. **更新统计**:
   - 待办: 5 → 4
   - 已解决: 1 → 2

5. **确认**: "✅ TODO-2026-002 已标记为已完成"

### 示例 3: 生成统计报告

**用户输入**: "生成 TODO 报告"

**Skill 响应**:

```markdown
## 📊 TODO 统计报告

生成时间: 2026-02-07 13:30

### 状态分布
| 状态 | 数量 | 百分比 |
|------|------|--------|
| 待办 | 4 | 67% |
| 进行中 | 0 | 0% |
| 已解决 | 2 | 33% |
| 已拒绝 | 0 | 0% |
| 已延期 | 0 | 0% |

### 优先级分布
| 优先级 | 数量 | 百分比 |
|--------|------|--------|
| P0 (高) | 0 | 0% |
| P1 (中) | 2 | 50% |
| P2 (低) | 2 | 50% |
| P3 (评估) | 0 | 0% |

### 类型分布
| 类型 | 数量 | 百分比 |
|------|------|--------|
| Bug | 0 | 0% |
| Feature | 1 | 17% |
| Refactor | 1 | 17% |
| Test | 2 | 33% |
| Doc | 0 | 0% |
| UI | 2 | 33% |

### 本月完成情况
- 新增: 5
- 已完成: 2
- 完成率: 40%

### 建议关注
- 高优先级待办: 0 个 ✅
- 长期未更新 (> 7 天): 0 个 ✅

### 待办列表

#### P1 (中优先级)
1. TODO-2026-002: 修复工具页面 Hero 部分中文翻译
2. TODO-2026-003: 完成移动端响应式布局测试

#### P2 (低优先级)
1. TODO-2026-004: 实现/修复语言切换器功能
2. TODO-2026-005: 添加自动化 E2E 测试
```

## 🚨 常见错误

### ❌ 不要:
- 创建 TODO 时跳过 ID 分配
- 忘记更新统计数据
- 跳过更新记录
- 把 TODO 放错章节
- 使用模糊的标题或描述

### ✅ 要:
- 始终使用格式 `TODO-YYYY-XXX`
- 每次更改后更新统计
- 始终添加更新记录 (日期 + 操作)
- 始终放在正确的优先级章节
- 始终使用具体、可操作的标题

## 📊 项目类型适配

### Web 项目 (React/Vue/Next.js)

**相关模块示例**:
- 前端组件: `components/UserProfile.tsx`
- API 接口: `api/auth.ts`
- 状态管理: `store/userStore.ts`
- 路由配置: `app/router.tsx`

### 移动应用 (React Native/Flutter)

**相关模块示例**:
- 页面: `screens/HomeScreen.tsx`
- 组件: `components/Button.tsx`
- 导航: `navigation/AppNavigator.tsx`
- 状态: `redux/slices/userSlice.ts`

### Unity 游戏

**相关模块示例**:
- 脚本: `Assets/Scripts/PlayerController.cs`
- 场景: `Assets/Scenes/Level1.unity`
- Prefab: `Assets/Prefabs/Enemy.prefab`
- 管理器: `Assets/Scripts/GameManager.cs`

### 后端服务 (Node.js/Python/Go)

**相关模块示例**:
- 路由: `routes/auth.js`
- 控制器: `controllers/UserController.js`
- 服务层: `services/UserService.js`
- 模型: `models/User.js`

## 🔗 相关工具

- **Read 工具**: 读取 PROJECT_TODO_DATABASE.md
- **Edit 工具**: 修改数据库内容
- **Grep 工具**: 搜索 TODO
- **Bash 工具**: 统计数据

## 📝 注意事项

- 数据库是项目特定的，不是全局的
- 每个项目应该有自己的 PROJECT_TODO_DATABASE.md
- 更改应该提交到 Git 进行版本控制
- 建议每周审查 TODO
- 归档超过 3 个月的已完成 TODO

---

## 🚀 初始化流程 (防止遗漏) ⭐NEW

### 核心原则

> **"所有TODO类型的任务都必须进入统一的TODO数据库"**

### 什么是"TODO类型的任务"？

不仅仅是代码注释中的 `//TODO:`，还包括：

1. **代码TODO注释** (18个)
   - `//TODO:`, `//FIXME:`, `//HACK:`, `//XXX:`

2. **重构任务** (3个大型)
   - 文件拆分、架构调整

3. **功能需求** (未记录)
   - 新功能想法、改进建议

4. **Bug修复** (部分在数据库)
   - 已知bug、用户反馈

5. **技术债务** (部分记录)
   - 代码坏味道、性能问题

6. **文档任务** (未记录)
   - 文档补充、示例代码

7. **测试任务** (部分记录)
   - 测试覆盖、测试用例

8. **配置任务** (未记录)
   - 配置表、环境配置

9. **优化任务** (部分记录)
   - 性能优化、内存优化

10. **规划事项** (未记录)
    - 计划中的工作、未来规划

### TODO来源检查清单 (10类)

#### ✅ 第1类: 代码中的TODO/FIXME注释

**位置**: `Assets/GAS/Scripts/PVP/` 下的所有 `.cs` 文件

**查找命令**:
```bash
grep -rn "TODO\|FIXME\|HACK\|XXX" Assets/GAS/Scripts/PVP/ --include="*.cs"
```

**当前状态**: ✅ 已整理 (18个)

#### ✅ 第2类: 重构规划文档

**位置**: 项目根目录的 `*REFACTOR*.md` 文件

**查找命令**:
```bash
ls -1 *REFACTOR*.md *REFACTOR*.txt 2>/dev/null
```

**当前状态**: ✅ 已整理 (3个大型重构任务)

#### ⚠️ 第3类: 测试相关文档

**位置**: `*TEST*.md` 文件

**查找命令**:
```bash
ls -1 *TEST*.md 2>/dev/null | head -20
```

**当前状态**: ⚠️ 部分未检查

**需要检查的文档**:
- [ ] AI_TDD_QUICKSTART.md
- [ ] FARM_PVP_TDD_STRATEGY.md
- [ ] FARM_PVP_TDD_FINAL_SUMMARY.md
- [ ] FARMPVP_TESTING_BIBLE.md
- [ ] EditMode测试覆盖分析.md
- [ ] PvpTaskTests_Report.md
- [ ] P0_*_REPORT.md (多个P0测试报告)

#### ⚠️ 第4类: 技术债务文档

**位置**: `*TECH*DEBT*.md`, `*DEBT*.md` 文件

**查找命令**:
```bash
ls -1 *TECH*.md *DEBT*.md 2>/dev/null
```

**当前状态**: ⚠️ 未系统整理

#### ⚠️ 第5类: 项目管理文档

**位置**: `PROJECT_*.md`, `*PLAN*.md` 文件

**查找命令**:
```bash
ls -1 PROJECT*.md *PLAN*.md 2>/dev/null
```

**当前状态**: ⚠️ 未检查

#### ❌ 第6类: Bug报告和Issue

**位置**: GitHub Issues, Bug报告文档

**查找命令**:
```bash
ls -1 *BUG*.md *ISSUE*.md *ERROR*.md 2>/dev/null
```

**当前状态**: ❌ 未系统整理

#### ❌ 第7类: 功能需求文档

**位置**: `*FEATURE*.md`, `*REQUIREMENT*.md` 文件

**查找命令**:
```bash
ls -1 *FEATURE*.md *REQUIRE*.md 2>/dev/null
```

**当前状态**: ❌ 未整理

#### ❌ 第8类: 会议和讨论记录

**位置**: `*MEETING*.md`, `*DISCUSSION*.md` 文件

**查找命令**:
```bash
ls -1 *MEETING*.md *DISCUSSION*.md 2>/dev/null
```

**当前状态**: ❌ 未整理

#### ❌ 第9类: AI对话历史

**位置**: Claude Code对话历史

**查找方法**: 回顾最近的AI对话

**当前状态**: ⚠️ 部分整理

#### ❌ 第10类: 配置和环境设置

**位置**: 配置文件、环境文档

**查找命令**:
```bash
ls -1 *CONFIG*.md *SETUP*.md *ENV*.md 2>/dev/null
```

**当前状态**: ❌ 未整理

### 全面扫描命令

#### 代码TODO扫描

```bash
# 查找所有代码TODO
grep -rn "TODO\|FIXME\|HACK\|XXX" Assets/GAS/Scripts/PVP/ --include="*.cs" | tee code_todo_scan.txt

# 统计数量
grep -rn "TODO\|FIXME\|HACK\|XXX" Assets/GAS/Scripts/PVP/ --include="*.cs" | wc -l
```

#### 文档TODO扫描

```bash
# 查找所有文档TODO
grep -rn "待办\|TODO\|FIXME\|任务" *.md --include="*.md" | tee doc_todo_scan.txt

# 统计数量
grep -rn "待办\|TODO\|FIXME\|任务" *.md --include="*.md" | wc -l
```

#### 项目管理文档扫描

```bash
# 查找所有规划相关文档
ls -1 *PLAN*.md *REFACTOR*.md *TODO*.md *STRATEGY*.md 2>/dev/null | tee planning_docs.txt

# 检查每个文档
for file in $(cat planning_docs.txt); do
    echo "=== $file ==="
    grep -i "待办\|任务\|TODO\|FIXME" "$file" | head -20
done
```

### 防止遗漏的关键措施

#### 1. 建立"TODO雷达"

**任何提到"任务"的都要警惕**:

触发词列表:
- 任务、待办、事项
- TODO、FIXME、HACK、XXX
- 计划、规划、安排
- 需要做、应该做、记得
- 问题、bug、错误
- 改进、优化、重构
- 添加、实现、完成

#### 2. 使用todo-database技能

**每次发现任务时，立即调用**:

```
"添加到TODO数据库: XXX"
"记录任务: XXX"
"新建待办: XXX"
```

#### 3. 定期全面扫描

**每周执行一次**:

```bash
# 代码TODO扫描
bash scan_code_todos.sh

# 文档TODO扫描
bash scan_doc_todos.sh

# 对比数据库
bash compare_todos.sh
```

#### 4. 文档模板检查

**所有新文档创建时检查是否包含TODO**:

- [ ] 计划文档 → 提取任务
- [ ] 需求文档 → 提取功能点
- [ ] 会议记录 → 提取行动项
- [ ] 测试报告 → 提取改进项

#### 5. AI对话中主动询问

**在AI对话结束前询问**:

- "有没有遗漏的TODO？"
- "还有哪些任务需要记录？"
- "有没有提到什么计划？"

### 初始化检查清单

#### ✅ 已完成

- [x] 代码TODO (18个)
- [x] 重构任务 (3个)
- [x] 创建UNIFIED_TODO_DATABASE.md
- [x] 添加触发词扩展

#### ⚠️ 待完成

- [ ] 测试文档TODO扫描
- [ ] 技术债务文档扫描
- [ ] 项目管理文档扫描
- [ ] Bug报告整理
- [ ] 功能需求整理
- [ ] AI对话历史回顾
- [ ] 配置任务整理

#### ❌ 未开始

- [ ] 建立定期扫描脚本
- [ ] 创建TODO提取工具
- [ ] 建立TODO雷达意识
- [ ] 团队培训

### 下一步行动

#### 立即行动 (今天)

1. **扫描测试文档** (30分钟)
   ```bash
   grep -rn "待办\|TODO\|FIXME\|任务" *TEST*.md > test_todos.txt
   ```

2. **扫描项目管理文档** (15分钟)
   ```bash
   grep -rn "待办\|TODO\|FIXME\|任务" PROJECT*.md *PLAN*.md > project_todos.txt
   ```

3. **整理到数据库** (30分钟)
   - 手动或使用todo-database技能
   - 更新统计数据

#### 本周行动

1. **回顾AI对话历史** (1小时)
   - 找出所有提到的任务
   - 整理到数据库

2. **检查技术债务文档** (30分钟)
   - 提取技术债任务
   - 整理到数据库

3. **创建扫描脚本** (1小时)
   - `scan_code_todos.sh`
   - `scan_doc_todos.sh`
   - `compare_todos.sh`

#### 持续改进

1. **每周执行一次全面扫描** (30分钟)
2. **每次AI对话结束前询问TODO**
3. **建立文档创建时的TODO检查流程**

---

**版本**: v2.1
**创建**: 2026-02-05
**更新**: 2026-02-11 (扩展触发词 + 初始化流程)
**维护者**: Faizlee & Claude
