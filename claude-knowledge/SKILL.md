---
name: claude-knowledge
description: |
  【最高优先级 - 总是先检查】项目知识索引系统

  ⚠️ 强制触发（任何项目问题都先搜索索引）:
  提问、问题、解决方案、技术决策、Bug、修复、实现、开发、功能、错误、故障、排查、调试、优化、重构、测试、文档、代码审查、Code Review、架构、设计、集成、部署、配置、环境、安装、设置、使用、教程、指南、参考、API、数据库、查询、前端、后端、全栈、Next.js、React、TypeScript、PostgreSQL、Drizzle、认证、支付、视频、生成、AI、积分、小红书、封面、缩略图、历史记录、状态管理、Zustand、Store、性能、优化、E2E、测试、Playwright、文档、知识库、索引、搜索、查找、定位、解决、处理、修复、改进、增强、新增、删除、更新、修改、变更。

  工作流程: ①搜索索引 ②找到方案直接引用 ③找不到记录新问题 ④持续学习更新权重

  功能: 多重搜索（关键词/模块/类型/问题记录/关联）、智能匹配（上下文/时间/条件/置信度）、持续学习（自动记录/动态权重/问题频率）、质量保证（三层质量检查/用户反馈/时间衰减）、跨项目支持（每个项目独立索引）、自动初始化（检测docs/并提示创建）。

  首次使用: 自动检测 docs/ 目录并提示初始化索引。跨项目支持，每个项目独立索引在 docs/knowledge-index/。

  适用所有项目场景: 问题、Bug、功能、技术决策、代码实现、文档查询、测试、优化、重构等。
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

### 模式 1: 问题记录匹配（最高优先级）

直接在 `problem-log.json` 中查找完全相同的问题。

**适用场景**: 用户之前问过类似问题

**示例**:
```
问题: "小红书封面生成器积分冻结失败"
搜索: problem-log.json → 找到 PROB-001（已出现5次）
结果: 直接返回解决方案
```

### 模式 2: 关键词搜索

提取问题中的关键词，在 `INDEX.md` 的 tags 字段中查找。

**关键词提取**:
- 模块名（小红书、视频、认证等）
- 技术栈（Next.js、React、TypeScript等）
- 错误信息（积分冻结、测试失败等）
- 功能名（历史记录、状态管理等）

**示例**:
```
问题: "如何实现小红书封面的历史记录功能？"
关键词: ["小红书", "封面", "历史记录", "实现"]
搜索: INDEX.md → 按关键词匹配
结果: xiaohongshu-cover-history-implementation.md
```

### 模式 3: 模块分类搜索

按功能模块分类搜索。

**模块分类**:
- `xiaohongshu-cover` - 小红书封面生成器
- `video-generator` - 视频生成器
- `auth` - 认证系统
- `testing` - 测试相关
- `refactor` - 重构文档

**示例**:
```
问题: "视频生成器的积分系统如何工作？"
模块: video-generator
搜索: INDEX.md → 在 video-generator 模块下查找
结果: video-credit-system.md
```

### 模式 4: 问题类型搜索

按文档类型搜索。

**类型分类**:
- `bug` - Bug 修复
- `feature` - 功能实现
- `refactor` - 代码重构
- `test` - 测试文档
- `guide` - 使用指南
- `report` - 测试报告

**示例**:
```
问题: "移动端测试为什么失败？"
类型: test + report
搜索: INDEX.md → 在 test 类型下查找
结果: mobile-responsive-test-report-2026-02-07.md
```

### 模式 5: 关联搜索

找到文档后，递归查找其 `related_documents`。

**示例**:
```
问题: "小红书封面生成器的状态管理如何设计？"
搜索: xiaohongshu-cover-implementation.md
关联: related_documents → [state-management.md, zustand-store.md]
结果: 返回所有相关文档
```

### 复合触发

多个搜索模式同时使用，结果合并后排序。

```python
results = []

# 1. 问题记录匹配
results.extend(search_problem_log(query))

# 2. 关键词搜索
keywords = extract_keywords(query)
results.extend(search_by_keywords(keywords))

# 3. 模块分类
module = detect_module(query)
if module:
    results.extend(search_by_module(module))

# 4. 问题类型
doc_type = detect_type(query)
if doc_type:
    results.extend(search_by_type(doc_type))

# 5. 关联搜索
for doc in results:
    results.extend(get_related_documents(doc))

# 去重并排序
return deduplicate_and_rank(results)
```

## 智能匹配判断

找到候选文档后，执行以下检查：

### 1. 上下文匹配（30分）

比较用户问题的上下文和文档的上下文。

```python
def match_context(document, user_context):
    score = 0

    # 模块匹配
    if document.module == user_context.module:
        score += 10

    # 技术栈匹配
    if all(tech in document.tech_stack for tech in user_context.tech_stack):
        score += 10

    # 文件路径匹配
    if any(file in document.related_files for file in user_context.files):
        score += 10

    return score
```

### 2. 时间验证（20分）

检查文档的时效性。

```python
def check_time(document):
    age_days = (current_date - document.last_updated).days

    if age_days < 180:  # 6个月内
        return 20, None
    elif age_days < 365:  # 6-12个月
        return 10, "⚠️ 文档超过6个月未更新，请验证"
    else:  # 超过1年
        return 0, "⚠️ 文档超过1年未更新，可能已过时"
```

### 3. 条件匹配（30分）

检查前置条件是否满足。

```python
def check_prerequisites(document, user_context):
    # 检查文档的前置条件
    for prereq in document.prerequisites:
        if prereq not in user_context.available_features:
            return 0, f"不满足前置条件: {prereq}"

    return 30, None
```

### 4. 关键词重合度（20分）

计算关键词匹配比例。

```python
def calculate_overlap(doc_keywords, query_keywords):
    if not query_keywords:
        return 0

    matches = len(set(doc_keywords) & set(query_keywords))
    overlap = matches / len(query_keywords)

    return int(overlap * 20)
```

### 置信度评分

```python
total_score = context_score + time_score + prereq_score + keyword_score

if total_score >= 70:
    return "high", total_score  # 直接引用
elif total_score >= 50:
    return "medium", total_score  # 引用并提示验证
else:
    return "low", total_score  # 询问用户或重新思考
```

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

    # 时间衰减（每周 -1）
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

定期检查高频问题：

```python
def analyze_frequent_problems():
    frequent = filter(lambda p: p.occurrence_count >= 5, all_problems)

    for problem in frequent:
        module_stats = get_module_stats(problem.module)

        print(f"""
        ⚠️ 高频问题警报:
        问题: {problem.question}
        出现次数: {problem.occurrence_count}
        模块: {problem.module}
        模块总问题数: {module_stats.total_problems}
        建议: {generate_refactor_suggestion(problem, module_stats)}
        """)
```

## 质量保证

### Layer 1: 文档元数据

每个文档包含质量信息：

```markdown
### 核心实现
- **文件**: `xiaohongshu-cover-implementation.md`
- **质量标记**: high/medium/low
- **状态**: active/deprecated/archived
- **最后审核**: 2026-02-07
- **审核人**: @faizlee
- **置信度**: 95 (基于历史成功率)
```

### Layer 2: 时间衰减警告

```python
def get_document_with_warnings(document):
    warnings = []

    # 时间检查
    age_days = (current_date - document.last_updated).days
    if age_days > 365:
        warnings.append("⚠️ 文档超过1年未更新，可能已过时")
        document.weight -= 15
    elif age_days > 180:
        warnings.append("⚠️ 文档超过6个月未更新，请验证")

    # 质量标记
    if document.quality == "low":
        warnings.append("⚠️ 文档质量标记为 low，谨慎使用")
        document.weight -= 20

    # 历史成功率
    if document.success_rate < 0.5:
        warnings.append("⚠️ 历史成功率低于50%，建议验证")

    return document, warnings
```

### Layer 3: 用户反馈循环

```json
{
  "solutions": [
    {
      "document": "xiaohongshu-cover-implementation.md",
      "section": "积分冻结",
      "confidence": "high",
      "user_feedback": {
        "helpful": true,
        "rating": 5,
        "comment": "解决方案有效",
        "timestamp": "2026-02-07"
      },
      "success_count": 12,
      "fail_count": 1,
      "success_rate": 0.92
    }
  ]
}
```

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

需要用户确认:

```
🤖 检测到文档 old-feature.md 已删除
是否从索引中删除该文档？关联的 3 个问题记录也将被删除。

选项:
  1. 删除文档和问题记录
  2. 保留问题记录（文档标记为已删除）
  3. 取消
```

### 手动触发

```bash
# 添加新文档到索引
python scripts/update_index.py --add docs/new-doc.md

# 重建整个索引
python scripts/rebuild_index.py --confirm

# 更新权重
python scripts/update_weights.py

# 搜索索引
python scripts/search_index.py "关键词"
```

## 工作流程示例

### 示例 1: Bug 修复问题

**用户问题**: "小红书封面生成器积分冻结失败"

**搜索流程**:
1. 问题记录匹配 → 找到 PROB-001（5次出现）
2. 返回解决方案: `xiaohongshu-cover-implementation.md#积分冻结`
3. 验证: 上下文✓、时间✓、条件✓
4. 置信度: 92/100 (高)
5. 直接引用解决方案

**更新**:
- PROB-001.occurrence_count += 1 (变为 6)
- xiaohongshu-cover-implementation.md.reference_count += 1
- xiaohongshu-cover-implementation.md.weight += 5

### 示例 2: 新功能询问

**用户问题**: "如何实现小红书封面的历史记录功能？"

**搜索流程**:
1. 问题记录匹配 → 无匹配
2. 关键词搜索 → "历史记录", "小红书"
3. 模块分类 → xiaohongshu-cover
4. 找到: `xiaohongshu-cover-history-implementation.md`
5. 验证: 上下文✓、功能实现文档
6. 置信度: 85/100 (高)
7. 引用实现指南

**更新**:
- 创建新问题记录 PROB-XXX
- 关联到 `xiaohongshu-cover-history-implementation.md`

### 示例 3: 质量问题处理

**用户问题**: "移动端测试为什么只有15.4%通过率？"

**搜索流程**:
1. 问题记录匹配 → 找到 PROB-002（3次出现）
2. 返回解决方案: `mobile-responsive-test-report-2026-02-07.md`
3. 验证: 上下文✓、时间✓
4. **质量检查**: 文档标记 "测试失败原因是选择器问题，功能正常"
5. 置信度: 88/100 (高)
6. 引用解决方案并说明原因

## 参考文档

- [搜索模式详解](references/search-patterns.md) - 5种搜索模式的详细说明
- [匹配规则详解](references/matching-rules.md) - 置信度计算和匹配算法
- [权重算法详解](references/weight-algorithm.md) - 权重计算公式和调优

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

## 配置文件

项目根目录创建 `.knowledge-index-config.json`:

```json
{
  "project_name": "VideoFly",
  "docs_dir": "docs/",
  "index_dir": "docs/knowledge-index/",
  "modules": {
    "xiaohongshu-cover": {
      "keywords": ["小红书", "封面", "xiaohongshu", "cover"],
      "patterns": ["xiaohongshu-cover-*.md", "cover-*.md"]
    },
    "video-generator": {
      "keywords": ["视频", "生成", "video", "generator"],
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

---

**技能版本**: 1.0.0
**最后更新**: 2026-02-08
**维护者**: Faizlee & Claude
