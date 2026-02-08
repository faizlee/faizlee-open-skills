---
name: claude-knowledge
description: |
  Intelligent project knowledge indexing system.

  Triggers: Query docs, implement features, fix bugs, review architecture, debug issues.

  Prerequisite: docs/knowledge-index/ exists.

  Workflow: Search → Found? Quote : Record.

  Features: 5-mode search, smart matching, continuous learning, quality assurance, cross-project.
---

# Project Knowledge Indexing System

> **Core Philosophy**: Always search existing solutions before answering. Avoid repetitive work, continuously accumulate knowledge.

## Quick Start

### First Use - Auto Initialization

When the skill loads, it automatically detects:

1. **Project root** - Finds `.git/` or `package.json`
2. **Docs directory** - Checks if `docs/` exists
3. **Index directory** - Checks if `docs/knowledge-index/` exists

**If index doesn't exist, prompts**:
```
🤖 Detected 104 documents in project. Create knowledge index?

Options:
  1. Auto-create (Recommended) - 5-10 seconds
  2. Manual config - Customize modules and keywords
  3. Skip - Don't create index

Select (1/2/3): _
```

### Core Workflow

```
User question → Search index → Found solution?
                     ↓ Yes          ↓ No
              Quote solution    Record problem
              Update weight      Design solution
                                Add to index after implementation
```

## Search Modes

See [Search Patterns](references/search-patterns.md) for details.

1. **Problem Log Match** (Highest priority) - Find identical problems in `problem-log.json`
2. **Keyword Search** - Extract keywords and search in `tags` field
3. **Module Classification** - Search by functional module
4. **Type Classification** - Search by document type (bug/feature/refactor/test)
5. **Related Documents** - Recursively search `related_documents`

## Smart Matching

See [Matching Algorithm](references/matching-algorithm.md) for details.

After finding candidate documents, perform checks (total 100 points):

- **Context Match** (30 pts) - Compare module, tech stack, file paths
- **Time Validation** (20 pts) - Check document recency
- **Condition Match** (30 pts) - Verify prerequisites
- **Keyword Overlap** (20 pts) - Calculate keyword similarity

**Confidence Levels**:
- **High** (≥70): Quote solution directly
- **Medium** (50-69): Quote with verification prompt
- **Low** (<50): Ask user or rethink

## Continuous Learning

### Add New Solution

When solution is found:

```python
def add_solution(problem, document, section, confidence):
    # 1. Check if problem exists
    existing = find_problem(problem)

    if existing:
        # Update existing problem
        existing.occurrence_count += 1
        existing.last_seen = current_date
        existing.solutions.append({
            "document": document,
            "section": section,
            "confidence": confidence
        })

        # Check if refactor needed
        if existing.occurrence_count >= 5:
            existing.needs_refactor = True
            add_to_frequent_problems(existing)
    else:
        # Create new problem record
        create_problem(problem, document, section, confidence)

    # 2. Update document weight
    doc = find_document(document)
    doc.reference_count += 1
    doc.last_referenced = current_date
    doc.weight = calculate_weight(doc)

    # 3. Save updates
    save_index()
    save_problem_log()
```

### Weight Algorithm

```python
def calculate_weight(document):
    weight = 50  # Base weight

    # Reference count (+5 each)
    weight += document.reference_count * 5

    # Problem links (+3 each)
    weight += document.problem_links * 3

    # Keyword density
    keyword_density = calculate_keyword_density(document)
    weight += keyword_density * 2

    # Time decay (-1 per week, max -20)
    age_weeks = (current_date - document.created_date).weeks
    weight -= min(age_weeks, 20)

    # Recent boost (+10 if referenced in 7 days)
    if recently_referenced(document, days=7):
        weight += 10

    # Document quality
    if document.quality == "high":
        weight += 15
    elif document.quality == "low":
        weight -= 10

    return max(0, min(weight, 100))
```

### Problem Frequency Analysis

Regularly check high-frequency problems:

```python
def analyze_frequent_problems():
    frequent = filter(lambda p: p.occurrence_count >= 5, all_problems)

    for problem in frequent:
        module_stats = get_module_stats(problem.module)

        print(f"""
        ⚠️ High-frequency problem alert:
        Problem: {problem.question}
        Occurrences: {problem.occurrence_count}
        Module: {problem.module}
        Module total problems: {module_stats.total_problems}
        Suggestion: {generate_refactor_suggestion(problem, module_stats)}
        """)
```

## Quality Assurance

### Layer 1: Document Metadata

Each document contains quality information:

```markdown
### Core Implementation
- **File**: `xiaohongshu-cover-implementation.md`
- **Quality**: high/medium/low
- **Status**: active/deprecated/archived
- **Last audit**: 2026-02-07
- **Auditor**: @faizlee
- **Confidence**: 95 (based on historical success rate)
```

### Layer 2: Time Decay Warnings

```python
def get_document_with_warnings(document):
    warnings = []

    # Time check
    age_days = (current_date - document.last_updated).days
    if age_days > 365:
        warnings.append("⚠️ Document not updated in 1+ year, may be outdated")
        document.weight -= 15
    elif age_days > 180:
        warnings.append("⚠️ Document not updated in 6+ months, please verify")

    # Quality mark
    if document.quality == "low":
        warnings.append("⚠️ Document quality marked as low, use with caution")
        document.weight -= 20

    # Historical success rate
    if document.success_rate < 0.5:
        warnings.append("⚠️ Historical success rate below 50%, verify recommended")

    return document, warnings
```

### Layer 3: User Feedback Loop

```json
{
  "solutions": [
    {
      "document": "xiaohongshu-cover-implementation.md",
      "section": "Credit Freeze",
      "confidence": "high",
      "user_feedback": {
        "helpful": true,
        "rating": 5,
        "comment": "Solution effective",
        "timestamp": "2026-02-07"
      },
      "success_count": 12,
      "fail_count": 1,
      "success_rate": 0.92
    }
  ]
}
```

## Index Maintenance

### Add New Document

Auto-triggered (no confirmation):

1. Detect new `.md` file added to `docs/`
2. Auto-scan new file, extract keywords
3. Add to `INDEX.md`

### Update Document

Auto-triggered (no confirmation):

1. Monitor document `last_modified` time
2. If document updated, update `last_updated` field
3. Re-extract keywords

### Delete Document

Requires user confirmation:

```
🤖 Detected document old-feature.md deleted
Delete document from index? 3 related problem records will also be deleted.

Options:
  1. Delete document and problem records
  2. Keep problem records (mark document as deleted)
  3. Cancel
```

## Script Tools

### Build Index
```bash
python scripts/build_index.py
```

### Search Index
```bash
python scripts/search_index.py "keywords"
```

### Update Weights
```bash
python scripts/update_weights.py
```

## Examples

See [Working Examples](references/examples.md) for detailed scenarios.

### Example 1: Bug Fix Question

**User**: "Why is credit freezing failing?"

**Flow**:
1. Problem log match → Found PROB-001 (5 occurrences)
2. Return solution: `implementation.md#credit-freeze`
3. Verify: Context ✓, Time ✓, Conditions ✓
4. Confidence: 92/100 (high)
5. Quote solution directly

**Update**:
- PROB-001.occurrence_count += 1 (becomes 6)
- implementation.md.reference_count += 1
- implementation.md.weight += 5

### Example 2: New Feature Question

**User**: "How to implement history feature?"

**Flow**:
1. Problem log match → No match
2. Keyword search → "history", "cover"
3. Module classification → xiaohongshu-cover
4. Found: `history-implementation.md`
5. Verify: Context ✓, implementation guide
6. Confidence: 85/100 (high)
7. Quote implementation guide

**Update**:
- Create new problem record PROB-XXX
- Link to `history-implementation.md`

## Configuration

Create `.knowledge-index-config.json` in project root:

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

## Troubleshooting

### Index Doesn't Exist

**Problem**: Prompt "Index doesn't exist, needs initialization"

**Solution**: Select "Auto-create" option, skill will auto-scan and build index

### Search Returns No Results

**Problem**: Search returns empty results

**Possible causes**:
1. Inaccurate keywords → Try other keywords
2. Document not indexed → Run `build_index.py` to rebuild
3. Document deleted → Check document status

### Weight Anomaly

**Problem**: Search result ranking unreasonable

**Solution**: Run `update_weights.py` to recalculate weights

## Reference Documents

- [Search Patterns](references/search-patterns.md) - Detailed explanation of 5 search modes
- [Matching Algorithm](references/matching-algorithm.md) - Confidence calculation and matching
- [Working Examples](references/examples.md) - Real-world workflow examples

---

**Skill Version**: 1.0.0
**Last Updated**: 2026-02-08
**Maintainer**: Faizlee & Claude
