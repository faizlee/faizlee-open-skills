# Matching Algorithm

This document details the confidence scoring algorithm for matching documents to user questions.

## Overview

When candidate documents are found, the following checks are performed to determine if the solution is applicable:

1. **Context Match** (30 points) - Compare user context with document context
2. **Time Validation** (20 points) - Check document recency
3. **Condition Match** (30 points) - Verify prerequisites
4. **Keyword Overlap** (20 points) - Calculate keyword similarity

**Total Score**: 0-100 points

**Confidence Levels**:
- **High** (≥70): Quote solution directly
- **Medium** (50-69): Quote solution with verification prompt
- **Low** (<50): Ask user or rethink

---

## 1. Context Match (30 points)

Compare the user's question context with the document's context.

```python
def match_context(document: Dict, user_context: Dict) -> Tuple[int, Optional[str]]:
    score = 0

    # Module match (10 points)
    if document.get("module") == user_context.get("module"):
        score += 10

    # Tech stack match (10 points)
    doc_stack = set(document.get("tech_stack", []))
    user_stack = set(user_context.get("tech_stack", []))

    if user_stack.issubset(doc_stack):
        score += 10

    # File path match (10 points)
    doc_files = document.get("related_files", [])
    user_files = user_context.get("files", [])

    if any(file in doc_files for file in user_files):
        score += 10

    return score, None
```

**Scoring Breakdown**:
- Module matches: +10 points
- Tech stack matches: +10 points
- File path matches: +10 points

---

## 2. Time Validation (20 points)

Check the document's recency and warn if outdated.

```python
def check_time(document: Dict) -> Tuple[int, Optional[str]]:
    age_days = (current_date - document["last_updated"]).days

    if age_days < 180:  # Less than 6 months
        return 20, None
    elif age_days < 365:  # 6-12 months
        return 10, "⚠️ Document not updated in 6+ months, please verify"
    else:  # More than 1 year
        return 0, "⚠️ Document not updated in 1+ year, may be outdated"
```

**Scoring Breakdown**:
- Less than 6 months: +20 points
- 6-12 months: +10 points (with warning)
- More than 1 year: 0 points (with warning)

---

## 3. Condition Match (30 points)

Check if prerequisites are satisfied.

```python
def check_prerequisites(document: Dict, user_context: Dict) -> Tuple[int, Optional[str]]:
    doc_prereqs = document.get("prerequisites", [])
    user_features = user_context.get("available_features", [])

    # Check if all prerequisites are available
    for prereq in doc_prereqs:
        if prereq not in user_features:
            return 0, f"❌ Prerequisite not met: {prereq}"

    return 30, None
```

**Scoring Breakdown**:
- All prerequisites met: +30 points
- Any prerequisite missing: 0 points (with error)

---

## 4. Keyword Overlap (20 points)

Calculate the overlap between document keywords and query keywords.

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

**Scoring Breakdown**:
- All keywords match: +20 points
- 75% match: +15 points
- 50% match: +10 points
- 25% match: +5 points
- No match: 0 points

---

## Confidence Scoring

Combine all scores to determine confidence level.

```python
def calculate_confidence(document: Dict, user_context: Dict, query: str) -> Dict:
    scores = {}
    warnings = []

    # Context match
    context_score, context_warning = match_context(document, user_context)
    scores["context"] = context_score
    if context_warning:
        warnings.append(context_warning)

    # Time validation
    time_score, time_warning = check_time(document)
    scores["time"] = time_score
    if time_warning:
        warnings.append(time_warning)

    # Condition match
    prereq_score, prereq_warning = check_prerequisites(document, user_context)
    scores["prerequisites"] = prereq_score
    if prereq_warning:
        warnings.append(prereq_warning)

    # Keyword overlap
    query_keywords = extract_keywords(query)
    keyword_score = calculate_overlap(document["keywords"], query_keywords)
    scores["keywords"] = keyword_score

    # Total score
    total_score = sum(scores.values())

    # Determine confidence level
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

## Score Breakdown Examples

### Example 1: High Confidence (92/100)

**Scenario**: Bug fix in the same module with recent documentation

```python
{
  "context": 30,      # Module matches + tech stack matches + file matches
  "time": 20,         # Updated 2 weeks ago
  "prerequisites": 30, # All prerequisites met
  "keywords": 12,     # 60% keyword overlap
  "total": 92,
  "confidence": "high"
}
```

**Action**: Quote solution directly

---

### Example 2: Medium Confidence (65/100)

**Scenario**: Feature implementation with outdated documentation

```python
{
  "context": 20,      # Module matches
  "time": 10,         # Updated 8 months ago (warning)
  "prerequisites": 30, # All prerequisites met
  "keywords": 5,      # 25% keyword overlap
  "total": 65,
  "confidence": "medium",
  "warnings": [
    "⚠️ Document not updated in 6+ months, please verify"
  ]
}
```

**Action**: Quote solution with verification prompt

---

### Example 3: Low Confidence (35/100)

**Scenario**: Bug fix in different module with old documentation

```python
{
  "context": 10,      # Only tech stack matches
  "time": 0,          # Updated 2 years ago (warning)
  "prerequisites": 30, # All prerequisites met
  "keywords": 5,      # 25% keyword overlap
  "total": 45,
  "confidence": "low",
  "warnings": [
    "⚠️ Document not updated in 1+ year, may be outdated"
  ]
}
```

**Action**: Ask user or rethink

---

## Best Practices

1. **Context Matters**: Prioritize documents from the same module and with matching files
2. **Time Sensitivity**: Always warn about outdated documents
3. **Prerequisites**: Don't quote solutions if prerequisites aren't met
4. **Keyword Quality**: Extract relevant keywords, not just any words
5. **Threshold Tuning**: Adjust confidence thresholds based on your project's needs

---

## Algorithm Complexity

- **Time Complexity**: O(n) where n is the number of candidate documents
- **Space Complexity**: O(1) for scoring, O(m) for storing results where m is the number of matches

---

**Version**: 1.0.0
**Last Updated**: 2026-02-08
