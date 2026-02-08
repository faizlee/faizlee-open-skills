# Search Modes

This document details the 5 search modes used by claude-knowledge.

## Mode 1: Problem Log Match (Highest Priority)

Directly search `problem-log.json` for identical or similar questions.

**Use Case**: User has asked similar questions before.

**Example**:
```
Question: "Why is credit freezing failing?"
Search: problem-log.json → Found PROB-001 (5 occurrences)
Result: Return solution directly
```

**Implementation**:
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

## Mode 2: Keyword Search

Extract keywords from the question and search in the `tags` field of `INDEX.md`.

**Keyword Extraction**:
- Module names (e.g., "auth", "video", "payment")
- Tech stack (e.g., "React", "TypeScript", "PostgreSQL")
- Error messages (e.g., "credit freeze", "test failed")
- Feature names (e.g., "history", "state management")

**Example**:
```
Question: "How to implement history feature for cover generator?"
Keywords: ["history", "cover", "implement"]
Search: INDEX.md → Match by tags
Result: cover-history-implementation.md
```

**Implementation**:
```python
def extract_keywords(query: str) -> List[str]:
    keywords = []

    # Extract module names
    for module in config["modules"]:
        if module.lower() in query.lower():
            keywords.extend(config["modules"][module]["keywords"])

    # Extract tech stack terms
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

## Mode 3: Module Classification

Search by functional module.

**Module Categories**:
- `auth` - Authentication system
- `video` - Video generation
- `payment` - Payment & billing
- `testing` - Testing related
- `refactor` - Refactoring docs

**Example**:
```
Question: "How does the credit system work in video generator?"
Module: video
Search: INDEX.md → Search in video module
Result: video-credit-system.md
```

**Implementation**:
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

## Mode 4: Type Classification

Search by document type.

**Type Categories**:
- `bug` - Bug fixes
- `feature` - Feature implementation
- `refactor` - Code refactoring
- `test` - Testing docs
- `guide` - Usage guides
- `report` - Test reports

**Example**:
```
Question: "Why are mobile tests failing?"
Type: test + report
Search: INDEX.md → Search in test type
Result: mobile-responsive-test-report-2026-02-07.md
```

**Implementation**:
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

## Mode 5: Related Documents

After finding documents, recursively search their `related_documents`.

**Example**:
```
Question: "How is state management designed?"
Search: cover-implementation.md
Related: related_documents → [state-management.md, zustand-store.md]
Result: Return all related documents
```

**Implementation**:
```python
def get_related_documents(document: Dict, depth: int = 1) -> List[Dict]:
    if depth <= 0:
        return []

    related = []
    for ref in document.get("related_documents", []):
        ref_doc = find_document_by_path(ref)
        if ref_doc:
            related.append(ref_doc)
            # Recursive search
            related.extend(get_related_documents(ref_doc, depth - 1))

    return related
```

---

## Composite Search

Multiple search modes are used simultaneously, results are merged and ranked.

```python
def search(query: str, context: Dict = None) -> Dict[str, Any]:
    results = []

    # Mode 1: Problem log match (highest priority)
    problem_results = search_problem_log(query)
    results.extend(problem_results)

    # Mode 2: Keyword search
    keywords = extract_keywords(query)
    keyword_results = search_by_keywords(keywords)
    results.extend(keyword_results)

    # Mode 3: Module classification
    module = detect_module(query)
    if module:
        module_results = search_by_module(module)
        results.extend(module_results)

    # Mode 4: Type search
    doc_type = detect_type(query)
    if doc_type:
        type_results = search_by_type(doc_type)
        results.extend(type_results)

    # Mode 5: Related documents
    for doc in results:
        related = get_related_documents(doc, depth=1)
        results.extend(related)

    # Deduplicate and rank
    results = deduplicate(results)
    results = rank_results(results, query)

    # Check quality
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

## Best Practices

1. **Prioritize Problem Log**: Always check problem-log.json first
2. **Extract Relevant Keywords**: Avoid over-matching with generic terms
3. **Module Detection**: Use context clues to detect the right module
4. **Type Classification**: Combine multiple types for better results
5. **Recursive Related Search**: Limit depth to avoid infinite loops

---

**Version**: 1.0.0
**Last Updated**: 2026-02-08
