---
name: todo-database
description: |
  【优先触发 - 任务管理】通用项目级持久化 TODO 管理系统

  🚨 强制触发词（中英文，覆盖所有场景）：

  【任务添加 - Add Task】
  添加、新建、创建、记录、加入、增加、写到、保存到
  add, create, new, record, save, add to, put in
  + TODO/待办/任务/task/todo/task

  【任务操作 - Task Action】
  更新、修改、标记、完成、解决、关闭、删除、移除
  update, modify, mark, complete, resolve, close, delete, remove
  + TODO/任务/task

  【任务查看 - View Task】
  查看、显示、列出、有什么、有哪些、所有
  view, show, list, what, all, display
  + TODO/待办/任务/task/todo list

  【询问式 - Question】
  有没有、是否存在、在哪儿、位置在哪、状态如何
  is there, where, status, how about, what about
  + TODO/任务/task

  【描述式 - Description】
  把这个、把这个任务、需要做、应该做、记住
  this, this task, need to, should, remember
  + 添加/记录/保存 (add/record/save)

  🔴 绝对优先级（最高）：
  - 任何"添加/记录" TODO 的请求：立即触发
  - 任何"查看/列出" TODO 的请求：立即触发
  - 任何"更新/标记" TODO 的请求：立即触发

  📌 核心功能：
  - 添加、更新、搜索、删除 TODO
  - 支持优先级 P0-P3
  - 支持类型 Bug/Feature/Refactor/Test/Doc/UI
  - 状态追踪（待办/进行中/已完成/已拒绝/已延期）
  - Git 持久化，对话重启不丢失

  📍 适用所有项目：Web、移动端、Unity、Python、通用项目
---

# TODO Database Skill

> **核心承诺**: "重启对话不会丢失 TODO,所有任务都有记录和跟踪"

通用的项目级持久化 TODO 管理系统，通过 Git 追踪的 Markdown 文档存储所有 TODO，确保在 AI 对话重启后依然保留所有有意义的任务和想法。

## 🎯 触发关键词

**直接触发关键词 (任一出现即触发)**:

| 中文关键词 | 英文关键词 | 动作 |
|-----------|-----------|------|
| "添加 TODO" | "add TODO" | 添加新任务 |
| "添加到 TODO 数据库" | "add to TODO database" | 添加新任务 |
| "记录到 TODO" | "record to TODO" | 添加新任务 |
| "新建 TODO" | "create new TODO" | 添加新任务 |
| "更新 TODO" | "update TODO" | 更新状态 |
| "修改 TODO 状态" | "change TODO status" | 更新状态 |
| "标记 TODO" | "mark TODO" | 更新状态 |
| "完成 TODO" | "complete TODO" | 标记完成 |
| "解决 TODO" | "resolve TODO" | 标记完成 |
| "关闭 TODO" | "close TODO" | 标记完成 |
| "查看 TODO" | "view TODO" | 显示列表 |
| "TODO 列表" | "TODO list" | 显示列表 |
| "待办事项" | "pending tasks" | 显示列表 |
| "待办任务" | "backlog" | 显示列表 |
| "TODO 数据库" | "TODO database" | 显示信息 |
| "项目 TODO" | "project TODO" | 显示信息 |
| "搜索 TODO" | "search TODO" | 搜索任务 |
| "查找 TODO" | "find TODO" | 搜索任务 |
| "过滤 TODO" | "filter TODO" | 过滤任务 |
| "TODO 统计" | "TODO statistics" | 生成报告 |
| "TODO 报告" | "TODO report" | 生成报告 |
| "生成 TODO 报告" | "generate TODO report" | 生成报告 |
| "添加任务" | "add task" | 添加新任务 |
| "记录任务" | "record task" | 添加新任务 |

**场景触发 (结合上下文)**:

1. **发现问题时**:
   - "发现一个 bug" → 创建 Bug 类型 TODO
   - "有个问题需要修复" → 创建 Bug 类型 TODO
   - "这里有个错误" → 创建 Bug 类型 TODO

2. **功能想法时**:
   - "应该添加这个功能" → 创建 Feature 类型 TODO
   - "可以改进一下" → 创建 Feature 类型 TODO
   - "有个新想法" → 创建 Feature 类型 TODO

3. **代码审查时**:
   - "这里需要重构" → 创建 Refactor 类型 TODO
   - "代码有坏味道" → 创建 Refactor 类型 TODO
   - "需要优化" → 创建 Refactor 类型 TODO

4. **测试相关**:
   - "测试覆盖不够" → 创建 Test 类型 TODO
   - "需要写测试" → 创建 Test 类型 TODO
   - "缺少测试" → 创建 Test 类型 TODO

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

**版本**: v2.0
**创建**: 2026-02-05
**更新**: 2026-02-07
**维护者**: Faizlee & Claude
