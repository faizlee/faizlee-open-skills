# 匹配算法详解

本文档详细说明用于匹配文档与用户问题的置信度评分算法。

## 概述

当找到候选文档后，执行以下检查来确定方案是否适用：

1. **上下文匹配**（30分）- 比较用户上下文与文档上下文
2. **时间验证**（20分）- 检查文档时效性
3. **条件匹配**（30分）- 验证前置条件
4. **关键词重合度**（20分）- 计算关键词相似度

**总分**: 0-100分

**置信度等级**:
- **高** (≥70): 直接引用解决方案
- **中** (50-69): 引用解决方案并提示验证
- **低** (<50): 询问用户或重新思考

---

## 1. 上下文匹配（30分）

比较用户问题的上下文和文档的上下文。

```python
def match_context(document: Dict, user_context: Dict) -> Tuple[int, Optional[str]]:
    score = 0

    # 模块匹配（10分）
    if document.get("module") == user_context.get("module"):
        score += 10

    # 技术栈匹配（10分）
    doc_stack = set(document.get("tech_stack", []))
    user_stack = set(user_context.get("tech_stack", []))

    if user_stack.issubset(doc_stack):
        score += 10

    # 文件路径匹配（10分）
    doc_files = document.get("related_files", [])
    user_files = user_context.get("files", [])

    if any(file in doc_files for file in user_files):
        score += 10

    return score, None
```

**评分细则**:
- 模块匹配: +10分
- 技术栈匹配: +10分
- 文件路径匹配: +10分

---

## 2. 时间验证（20分）

检查文档的时效性，对过时文档发出警告。

```python
def check_time(document: Dict) -> Tuple[int, Optional[str]]:
    age_days = (current_date - document["last_updated"]).days

    if age_days < 180:  # 少于6个月
        return 20, None
    elif age_days < 365:  # 6-12个月
        return 10, "⚠️ 文档超过6个月未更新，请验证"
    else:  # 超过1年
        return 0, "⚠️ 文档超过1年未更新，可能已过时"
```

**评分细则**:
- 少于6个月: +20分
- 6-12个月: +10分（有警告）
- 超过1年: 0分（有警告）

---

## 3. 条件匹配（30分）

检查前置条件是否满足。

```python
def check_prerequisites(document: Dict, user_context: Dict) -> Tuple[int, Optional[str]]:
    doc_prereqs = document.get("prerequisites", [])
    user_features = user_context.get("available_features", [])

    # 检查所有前置条件是否可用
    for prereq in doc_prereqs:
        if prereq not in user_features:
            return 0, f"❌ 前置条件不满足: {prereq}"

    return 30, None
```

**评分细则**:
- 所有前置条件满足: +30分
- 任何前置条件缺失: 0分（有错误提示）

---

## 4. 关键词重合度（20分）

计算文档关键词与查询关键词的重合度。

```python
def calculate_overlap(doc_keywords: List[str], query_keywords: List[str]) -> int:
    if not query_keywords:
        return 0

    doc_set = set(kw.lower() for kw in doc_keywords)
    query_set = set(kw.lower() for kw in query_keywords)

    matches = len(doc_set & query_set)
    overlap_ratio = matches / len(query_set)

    return int(overlap_ratio * 20)
```

**评分细则**:
- 所有关键词匹配: +20分
- 75%匹配: +15分
- 50%匹配: +10分
- 25%匹配: +5分
- 无匹配: 0分

---

## 置信度计算

综合所有评分确定置信度等级。

```python
def calculate_confidence(document: Dict, user_context: Dict, query: str) -> Dict:
    scores = {}
    warnings = []

    # 上下文匹配
    context_score, context_warning = match_context(document, user_context)
    scores["context"] = context_score
    if context_warning:
        warnings.append(context_warning)

    # 时间验证
    time_score, time_warning = check_time(document)
    scores["time"] = time_score
    if time_warning:
        warnings.append(time_warning)

    # 条件匹配
    prereq_score, prereq_warning = check_prerequisites(document, user_context)
    scores["prerequisites"] = prereq_score
    if prereq_warning:
        warnings.append(prereq_warning)

    # 关键词重合度
    query_keywords = extract_keywords(query)
    keyword_score = calculate_overlap(document["keywords"], query_keywords)
    scores["keywords"] = keyword_score

    # 总分
    total_score = sum(scores.values())

    # 确定置信度等级
    if total_score >= 70:
        confidence = "high"
    elif total_score >= 50:
        confidence = "medium"
    else:
        confidence = "low"

    return {
        "confidence": confidence,
        "total_score": total_score,
        "breakdown": scores,
        "warnings": warnings
    }
```

---

## 评分示例

### 示例 1: 高置信度（92/100）

**场景**: 同模块的Bug修复，文档最近更新

```python
{
  "context": 30,      # 模块匹配 + 技术栈匹配 + 文件匹配
  "time": 20,         # 2周前更新
  "prerequisites": 30, # 所有前置条件满足
  "keywords": 12,     # 60%关键词重合
  "total": 92,
  "confidence": "high"
}
```

**操作**: 直接引用解决方案

---

### 示例 2: 中置信度（65/100）

**场景**: 功能实现，文档过时

```python
{
  "context": 20,      # 模块匹配
  "time": 10,         # 8个月前更新（警告）
  "prerequisites": 30, # 所有前置条件满足
  "keywords": 5,      # 25%关键词重合
  "total": 65,
  "confidence": "medium",
  "warnings": [
    "⚠️ 文档超过6个月未更新，请验证"
  ]
}
```

**操作**: 引用解决方案并提示验证

---

### 示例 3: 低置信度（45/100）

**场景**: 不同模块的Bug修复，文档过时

```python
{
  "context": 10,      # 仅技术栈匹配
  "time": 0,          # 2年前更新（警告）
  "prerequisites": 30, # 所有前置条件满足
  "keywords": 5,      # 25%关键词重合
  "total": 45,
  "confidence": "low",
  "warnings": [
    "⚠️ 文档超过1年未更新，可能已过时"
  ]
}
```

**操作**: 询问用户或重新思考

---

## 最佳实践

1. **上下文优先**: 优先选择来自相同模块且匹配文件的文档
2. **时效敏感**: 始终警告过时文档
3. **前置条件**: 前置条件不满足时不要引用解决方案
4. **关键词质量**: 提取相关关键词，而非任意词语
5. **阈值调优**: 根据项目需求调整置信度阈值

---

## 算法复杂度

- **时间复杂度**: O(n)，n为候选文档数量
- **空间复杂度**: O(1)用于评分，O(m)用于存储结果，m为匹配数量

---

**版本**: 1.0.0
**最后更新**: 2026-02-08
