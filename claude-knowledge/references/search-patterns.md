# 搜索模式详解

本文档详细说明项目知识索引系统的 5 种搜索模式。

## 模式 1: 问题记录匹配（最高优先级）

直接在 `problem-log.json` 中查找完全相同或相似的问题。

**适用场景**: 用户之前问过类似问题

**示例**:
```
问题: "积分冻结失败"
搜索: problem-log.json → 找到 PROB-001（已出现5次）
结果: 直接返回解决方案
```

**实现逻辑**:
```python
def search_problem_log(query: str) -> List[Dict]:
    normalized = normalize_query(query)
    problems = load_problem_log()

    matches = [
        p for p in problems["problems"]
        if p["normalized"] == normalized
    ]

    return sorted(matches, key=lambda p: p["occurrence_count"], reverse=True)
```

---

## 模式 2: 关键词搜索

提取问题中的关键词，在 `INDEX.md` 的 tags 字段中查找。

**关键词提取策略**:
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

**实现逻辑**:
```python
def extract_keywords(query: str) -> List[str]:
    keywords = []

    # 提取模块名
    for module in config["modules"]:
        if module.lower() in query.lower():
            keywords.extend(config["modules"][module]["keywords"])

    # 提取技术栈术语
    tech_terms = ["react", "typescript", "nextjs", "postgresql", "drizzle"]
    keywords.extend([t for t in tech_terms if t.lower() in query.lower()])

    return keywords

def search_by_keywords(keywords: List[str]) -> List[Dict]:
    index = load_index()
    results = []

    for doc in index["documents"]:
        keyword_overlap = len(set(doc["keywords"]) & set(keywords))
        if keyword_overlap > 0:
            results.append({
                "document": doc,
                "score": keyword_overlap
            })

    return sorted(results, key=lambda r: r["score"], reverse=True)
```

---

## 模式 3: 模块分类搜索

按功能模块分类搜索。

**模块分类**:
- `auth` - 认证系统
- `video` - 视频生成
- `payment` - 支付计费
- `testing` - 测试相关
- `refactor` - 重构文档

**示例**:
```
问题: "视频生成的积分系统如何工作？"
模块: video
搜索: INDEX.md → 在 video 模块下查找
结果: video-credit-system.md
```

**实现逻辑**:
```python
def detect_module(query: str) -> Optional[str]:
    query_lower = query.lower()

    module_keywords = {
        "auth": ["login", "register", "auth", "session", "token"],
        "video": ["video", "generate", "ai", "task"],
        "payment": ["payment", "billing", "stripe", "creem", "credit"],
        "testing": ["test", "e2e", "playwright", "jest"],
        "refactor": ["refactor", "cleanup", "optimize"]
    }

    for module, keywords in module_keywords.items():
        if any(kw in query_lower for kw in keywords):
            return module

    return None

def search_by_module(module: str) -> List[Dict]:
    index = load_index()
    return [doc for doc in index["documents"] if doc.get("module") == module]
```

---

## 模式 4: 问题类型搜索

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

**实现逻辑**:
```python
def detect_type(query: str) -> Optional[str]:
    query_lower = query.lower()

    type_keywords = {
        "bug": ["bug", "fix", "error", "issue", "fail"],
        "feature": ["feature", "implement", "add", "create"],
        "refactor": ["refactor", "cleanup", "optimize"],
        "test": ["test", "e2e", "playwright"]
    }

    for doc_type, keywords in type_keywords.items():
        if any(kw in query_lower for kw in keywords):
            return doc_type

    return None

def search_by_type(doc_type: str) -> List[Dict]:
    index = load_index()
    return [doc for doc in index["documents"] if doc_type in doc.get("types", [])]
```

---

## 模式 5: 关联搜索

找到文档后，递归查找其 `related_documents`。

**示例**:
```
问题: "状态管理是如何设计的？"
搜索: cover-implementation.md
关联: related_documents → [state-management.md, zustand-store.md]
结果: 返回所有相关文档
```

**实现逻辑**:
```python
def get_related_documents(document: Dict, depth: int = 1) -> List[Dict]:
    if depth <= 0:
        return []

    related = []
    for ref in document.get("related_documents", []):
        ref_doc = find_document_by_path(ref)
        if ref_doc:
            related.append(ref_doc)
            # 递归搜索
            related.extend(get_related_documents(ref_doc, depth - 1))

    return related
```

---

## 复合搜索

多个搜索模式同时使用，结果合并后排序。

```python
def search(query: str, context: Dict = None) -> Dict[str, Any]:
    results = []

    # 模式 1: 问题记录匹配（最高优先级）
    problem_results = search_problem_log(query)
    results.extend(problem_results)

    # 模式 2: 关键词搜索
    keywords = extract_keywords(query)
    keyword_results = search_by_keywords(keywords)
    results.extend(keyword_results)

    # 模式 3: 模块分类
    module = detect_module(query)
    if module:
        module_results = search_by_module(module)
        results.extend(module_results)

    # 模式 4: 类型搜索
    doc_type = detect_type(query)
    if doc_type:
        type_results = search_by_type(doc_type)
        results.extend(type_results)

    # 模式 5: 关联文档
    for doc in results:
        related = get_related_documents(doc, depth=1)
        results.extend(related)

    # 去重并排序
    results = deduplicate(results)
    results = rank_results(results, query)

    # 质量检查
    for result in results:
        warnings = check_quality(result)
        if warnings:
            result["warnings"] = warnings

    return {
        "found": len(results) > 0,
        "results": results
    }
```

---

## 最佳实践

1. **优先问题日志**: 总是先检查 problem-log.json
2. **提取相关关键词**: 避免用通用词过度匹配
3. **模块检测**: 使用上下文线索检测正确模块
4. **类型分类**: 结合多种类型获得更好结果
5. **递归关联搜索**: 限制深度避免无限循环

---

**版本**: 1.0.0
**最后更新**: 2026-02-08
