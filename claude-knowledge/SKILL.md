---
name: claude-knowledge
description: |
  【最高优先级 - 总是先检查】项目知识索引系统
  Intelligent project knowledge indexing system with 5-mode search. ALWAYS search existing solutions before answering.

  ⚠️ 强制触发 / Triggers (中英双语):
  项目问题、技术文档、实现方案、Bug修复、功能开发、代码审查、架构设计、集成部署、配置环境、测试调试、性能优化、重构改进
  Project issues, technical docs, implementation, bug fix, feature development, code review, architecture, integration, deployment, testing, debugging, optimization, refactoring

  前置条件 / Prerequisite: docs/knowledge-index/ 存在 / exists

  工作流程 / Workflow: 搜索索引 → 找到?直接引用 : 记录问题 → 持续学习
  Search index → Found? Quote solution : Record problem → Continuous learning

  功能 / Features: 5种搜索模式、智能匹配(上下文/时间/条件/关键词)、持续学习(自动记录/动态权重/问题频率)、质量保证(三层检查)、跨项目支持
  5-mode search, smart matching (context/time/conditions/keywords), continuous learning (auto-record/dynamic weights/frequency), quality assurance (3-layer checks), cross-project
---

# 项目知识索引系统

> **核心理念**: 在回答任何问题前，先搜索已有解决方案。避免重复工作，持续积累知识。

## 快速开始

### 首次使用 - 自动初始化

当技能首次加载时，会自动检测：

1. **检测项目根目录** - 查找 `.git/` 或 `package.json`
2. **检测文档目录** - 检查 `docs/` 是否存在
3. **检测索引目录** - 检查 `docs/knowledge-index/` 是否存在

**如果索引不存在，会提示**:
```
🤖 检测到项目中有 104 个文档，是否创建知识索引？

选项:
  1. 自动创建（推荐）- 5-10秒
  2. 手动配置 - 自定义模块和关键词
  3. 跳过 - 不创建索引

请选择 (1/2/3): _
```

### 核心工作流程

```
用户提问 → 搜索索引 → 找到方案？
                     ↓ 是          ↓ 否
              直接引用方案      记录新问题
              更新权重          设计方案
                                实现后添加到索引
```

## 搜索模式

详见 [搜索模式详解](references/search-patterns.md)

### 模式 1: 问题记录匹配（最高优先级）

直接在 `problem-log.json` 中查找完全相同的问题。

**适用场景**: 用户之前问过类似问题

**示例**:
```
问题: "积分冻结失败"
搜索: problem-log.json → 找到 PROB-001（已出现5次）
结果: 直接返回解决方案
```

### 模式 2: 关键词搜索

提取问题中的关键词，在 `INDEX.md` 的 tags 字段中查找。

**关键词提取**:
- 模块名（auth、video、payment等）
- 技术栈（React、TypeScript、PostgreSQL等）
- 错误信息（积分冻结、测试失败等）
- 功能名（历史记录、状态管理等）

**示例**:
```
问题: "如何实现历史记录功能？"
关键词: ["历史", "记录", "实现"]
搜索: INDEX.md → 按关键词匹配
结果: history-implementation.md
```

### 模式 3: 模块分类搜索

按功能模块分类搜索。

**模块分类**:
- `auth` - 认证系统
- `video` - 视频生成
- `payment` - 支付计费
- `testing` - 测试相关
- `refactor` - 重构文档

### 模式 4: 问题类型搜索

按文档类型搜索：bug、feature、refactor、test、guide、report

### 模式 5: 关联搜索

找到文档后，递归查找其 `related_documents`

## 智能匹配判断

详见 [匹配算法详解](references/matching-algorithm.md)

找到候选文档后，执行以下检查（总分100分）：

- **上下文匹配**（30分）- 比较模块、技术栈、文件路径
- **时间验证**（20分）- 检查文档时效性
- **条件匹配**（30分）- 验证前置条件
- **关键词重合度**（20分）- 计算关键词相似度

**置信度**:
- **高** (≥70): 直接引用解决方案
- **中** (50-69): 引用并提示验证
- **低** (<50): 询问用户或重新思考

## 持续学习

### 添加新方案

当找到解决方案后：

```python
def add_solution(problem, document, section, confidence):
    # 1. 检查问题是否已存在
    existing = find_problem(problem)

    if existing:
        # 更新现有问题
        existing.occurrence_count += 1
        existing.last_seen = current_date
        existing.solutions.append({
            "document": document,
            "section": section,
            "confidence": confidence
        })

        # 检查是否需要整改
        if existing.occurrence_count >= 5:
            existing.needs_refactor = True
            add_to_frequent_problems(existing)
    else:
        # 创建新问题记录
        create_problem(problem, document, section, confidence)

    # 2. 更新文档权重
    doc = find_document(document)
    doc.reference_count += 1
    doc.last_referenced = current_date
    doc.weight = calculate_weight(doc)

    # 3. 保存更新
    save_index()
    save_problem_log()
```

### 权重算法

```python
def calculate_weight(document):
    weight = 50  # 基础权重

    # 引用次数（每次 +5）
    weight += document.reference_count * 5

    # 问题关联次数（每次 +3）
    weight += document.problem_links * 3

    # 关键词密度
    keyword_density = calculate_keyword_density(document)
    weight += keyword_density * 2

    # 时间衰减（每周 -1，最多 -20）
    age_weeks = (current_date - document.created_date).weeks
    weight -= min(age_weeks, 20)

    # 最近提升（最近7天有引用，+10）
    if recently_referenced(document, days=7):
        weight += 10

    # 文档质量
    if document.quality == "high":
        weight += 15
    elif document.quality == "low":
        weight -= 10

    return max(0, min(weight, 100))
```

### 问题频率分析

定期检查高频问题（≥5次）→ 标记需要整改 → 生成重构建议

## 质量保证

### Layer 1: 文档元数据

每个文档包含质量信息：
- 质量标记: high/medium/low
- 状态: active/deprecated/archived
- 最后审核日期
- 置信度（基于历史成功率）

### Layer 2: 时间衰减警告

- 超过1年未更新 → 警告：可能已过时，权重 -15
- 超过6个月未更新 → 警告：请验证
- 历史成功率低于50% → 警告：建议验证

### Layer 3: 用户反馈循环

记录用户反馈：
- 有帮助评分（1-5星）
- 成功次数/失败次数
- 成功率计算

## 索引维护

### 添加新文档

自动触发（无需确认）:
1. 检测到新的 `.md` 文件添加到 `docs/`
2. 自动扫描新文件，提取关键词
3. 添加到 `INDEX.md`

### 更新文档

自动触发（无需确认）:
1. 监控文档的 `last_modified` 时间
2. 如果文档更新，更新 `last_updated` 字段
3. 重新提取关键词

### 删除文档

需要用户确认

## 脚本工具

### 构建索引
```bash
python scripts/build_index.py
```

### 搜索索引
```bash
python scripts/search_index.py "关键词"
```

### 更新权重
```bash
python scripts/update_weights.py
```

## 工作流程示例

详见 [工作流程示例](references/examples.md)

### 示例 1: Bug 修复问题

**用户问题**: "积分冻结失败"

**搜索流程**:
1. 问题记录匹配 → 找到 PROB-001（5次出现）
2. 返回解决方案: `implementation.md#积分冻结`
3. 验证: 上下文✓、时间✓、条件✓
4. 置信度: 92/100 (高)
5. 直接引用解决方案

**更新**:
- PROB-001.occurrence_count += 1 (变为 6)
- implementation.md.reference_count += 1
- implementation.md.weight += 5

### 示例 2: 新功能询问

**用户问题**: "如何实现历史记录功能？"

**搜索流程**:
1. 问题记录匹配 → 无匹配
2. 关键词搜索 → "历史", "记录"
3. 模块分类 → 对应模块
4. 找到: `history-implementation.md`
5. 验证: 上下文✓、功能实现文档
6. 置信度: 85/100 (高)
7. 引用实现指南

**更新**:
- 创建新问题记录 PROB-XXX
- 关联到 `history-implementation.md`

## 配置文件

项目根目录创建 `.knowledge-index-config.json`:

```json
{
  "project_name": "MyProject",
  "docs_dir": "docs/",
  "index_dir": "docs/knowledge-index/",
  "modules": {
    "auth": {
      "keywords": ["auth", "login", "session"],
      "patterns": ["auth-*.md"]
    },
    "video": {
      "keywords": ["video", "generate", "ai"],
      "patterns": ["video-*.md", "generator-*.md"]
    }
  },
  "auto_update": true,
  "quality_threshold": 0.7
}
```

## 故障排查

### 索引不存在

**问题**: 提示"索引不存在，需要初始化"

**解决**: 选择"自动创建"选项，技能会自动扫描并构建索引

### 搜索无结果

**问题**: 搜索返回空结果

**可能原因**:
1. 关键词不准确 → 尝试其他关键词
2. 文档未索引 → 运行 `build_index.py` 重建索引
3. 文档被删除 → 检查文档状态

### 权重异常

**问题**: 搜索结果排序不合理

**解决**: 运行 `update_weights.py` 重新计算权重

## 参考文档

- [搜索模式详解](references/search-patterns.md) - 5种搜索模式的详细说明
- [匹配算法详解](references/matching-algorithm.md) - 置信度计算和匹配算法
- [工作流程示例](references/examples.md) - 实际场景示例

---

**技能版本**: 1.0.0
**最后更新**: 2026-02-08
**维护者**: Faizlee & Claude
