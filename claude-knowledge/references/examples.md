# Working Examples

This document provides practical examples of how claude-knowledge works in real scenarios.

## Example 1: Bug Fix Question

### User Question

> "Why is credit freezing failing in the cover generator?"

### Search Flow

1. **Problem Log Match**
   ```
   Search: problem-log.json
   Found: PROB-001 (5 occurrences)
   Question: "小红书封面生成器积分冻结失败"
   First seen: 2026-02-05
   Last seen: 2026-02-07
   ```

2. **Return Solution**
   ```
   Document: xiaohongshu-cover-implementation.md
   Section: "积分冻结"
   Confidence: high
   ```

3. **Verification**
   - ✅ Context: Same module (xiaohongshu-cover)
   - ✅ Time: Updated 1 day ago
   - ✅ Prerequisites: All met
   - ✅ Keywords: ["credit", "freeze", "cover"] → 100% match

4. **Confidence Score**
   ```python
   {
     "context": 30,
     "time": 20,
     "prerequisites": 30,
     "keywords": 20,
     "total": 92,
     "confidence": "high"
   }
   ```

5. **Action**: Quote solution directly

### Update Records

```json
{
  "occurrence_count": 6,  // Increased from 5
  "last_seen": "2026-02-08",
  "solutions": [
    {
      "document": "xiaohongshu-cover-implementation.md",
      "section": "积分冻结",
      "confidence": "high",
      "success_count": 13,
      "success_rate": 0.93
    }
  ]
}
```

### Document Weight Update

```python
document["reference_count"] += 1  // Now 123
document["last_referenced"] = "2026-02-08"
document["weight"] = calculate_weight(document)
// Result: 85 → 90
```

---

## Example 2: New Feature Question

### User Question

> "How to implement history feature for cover generator?"

### Search Flow

1. **Problem Log Match**
   ```
   Search: problem-log.json
   Found: No exact match
   ```

2. **Keyword Search**
   ```
   Keywords extracted: ["history", "cover", "implement"]
   Search: INDEX.md → Match by tags
   Found: xiaohongshu-cover-history-implementation.md
   ```

3. **Module Classification**
   ```
   Module: xiaohongshu-cover
   Search: INDEX.md → In xiaohongshu-cover module
   Found: xiaohongshu-cover-history-implementation.md
   ```

4. **Return Solution**
   ```
   Document: xiaohongshu-cover-history-implementation.md
   Type: [implementation, guide]
   ```

5. **Verification**
   - ✅ Context: Same module
   - ✅ Time: Updated 3 weeks ago
   - ✅ Type: Implementation guide
   - ✅ Keywords: ["history", "cover"] → 66% match

6. **Confidence Score**
   ```python
   {
     "context": 30,
     "time": 20,
     "prerequisites": 30,
     "keywords": 13,
     "total": 93,
     "confidence": "high"
   }
   ```

7. **Action**: Quote implementation guide

### Create New Problem Record

```json
{
  "id": "PROB-XXX",
  "question": "How to implement history feature for cover generator?",
  "normalized": "history feature implementation cover generator",
  "first_seen": "2026-02-08",
  "last_seen": "2026-02-08",
  "occurrence_count": 1,
  "module": "xiaohongshu-cover",
  "type": "feature",
  "solutions": [
    {
      "document": "xiaohongshu-cover-history-implementation.md",
      "section": "Implementation",
      "confidence": "high"
    }
  ],
  "status": "active"
}
```

---

## Example 3: Quality Issue Question

### User Question

> "Why do mobile tests only have 15.4% pass rate?"

### Search Flow

1. **Problem Log Match**
   ```
   Search: problem-log.json
   Found: PROB-002 (3 occurrences)
   Question: "移动端测试通过率低"
   First seen: 2026-02-06
   ```

2. **Return Solution**
   ```
   Document: mobile-responsive-test-report-2026-02-07.md
   Type: [test, report]
   ```

3. **Verification**
   - ✅ Context: Testing module
   - ✅ Time: Updated 1 day ago
   - ✅ Type: Test report
   - ⚠️ Quality check needed

4. **Quality Check**
   ```
   Document metadata:
   - Quality mark: "low (selector issue, functionality works)"
   - Status: active
   - Success rate: N/A (test report, not solution)
   ```

5. **Confidence Score**
   ```python
   {
     "context": 30,
     "time": 20,
     "prerequisites": 30,
     "keywords": 15,
     "total": 95,
     "confidence": "high"
   }
   ```

6. **Action**: Quote solution with explanation

### Response Example

```
Found solution in mobile-responsive-test-report-2026-02-07.md:

📊 Test Results:
- Pass rate: 15.4% (4/26 tests)
- Root cause: Selector issues, not functional problems
- Functionality: ✅ Working correctly
- Recommendation: Update selectors for mobile testing

⚠️ Note: The low pass rate is due to selector configuration issues,
not functional problems. All features work correctly on mobile.
```

---

## Example 4: No Match Scenario

### User Question

> "How to integrate Web3 wallet payment?"

### Search Flow

1. **Problem Log Match**
   ```
   Search: problem-log.json
   Found: No match
   ```

2. **Keyword Search**
   ```
   Keywords: ["web3", "wallet", "payment", "integration"]
   Search: INDEX.md → No match
   ```

3. **Module Classification**
   ```
   Module: payment
   Search: INDEX.md → In payment module
   Found: [stripe-integration.md, creem-payment.md]
   ⚠️ But no Web3-related docs
   ```

4. **Confidence Score**
   ```python
   {
     "context": 10,      # Only module matches
     "time": 20,         # Payment docs are recent
     "prerequisites": 30,
     "keywords": 0,      # No Web3 keywords match
     "total": 60,
     "confidence": "medium",
     "warnings": [
       "⚠️ No exact match found. Related payment docs available."
     ]
   }
   ```

5. **Action**: Record new problem, design solution

### Create New Problem Record

```json
{
  "id": "PROB-XXX",
  "question": "How to integrate Web3 wallet payment?",
  "normalized": "web3 wallet payment integration",
  "first_seen": "2026-02-08",
  "last_seen": "2026-02-08",
  "occurrence_count": 1,
  "module": "payment",
  "type": "feature",
  "solutions": [],  // Empty - needs to be implemented
  "status": "pending"
}
```

### Design Solution

After implementing the feature:
1. Create new document: `web3-payment-integration.md`
2. Add to INDEX.md
3. Update problem record with solution
4. Link to related documents

---

## Example 5: Related Documents Search

### User Question

> "How is state management designed for cover generator?"

### Search Flow

1. **Problem Log Match**
   ```
   Search: problem-log.json
   Found: No exact match
   ```

2. **Keyword Search**
   ```
   Keywords: ["state", "management", "cover"]
   Search: INDEX.md → Match by tags
   Found: xiaohongshu-cover-implementation.md
   ```

3. **Related Documents Search**
   ```
   Base: xiaohongshu-cover-implementation.md
   Related: related_documents → [
     "xiaohongshu-cover-state-management.md",
     "xiaohongshu-cover-zustand-store.md"
   ]

   Recursive search:
   - xiaohongshu-cover-state-management.md
     → related: ["zustand-patterns.md", "state-architecture.md"]
   - xiaohongshu-cover-zustand-store.md
     → related: ["zustand-best-practices.md"]
   ```

4. **Return All Related**
   ```
   Found 5 related documents:
   1. xiaohongshu-cover-implementation.md (base)
   2. xiaohongshu-cover-state-management.md
   3. xiaohongshu-cover-zustand-store.md
   4. zustand-patterns.md
   5. state-architecture.md
   ```

5. **Action**: Provide comprehensive overview with all related docs

---

## Key Takeaways

1. **High Confidence (≥70)**: Quote directly, update records
2. **Medium Confidence (50-69)**: Quote with verification warnings
3. **Low Confidence (<50)**: Ask user, record new problem
4. **No Match**: Design solution, implement, add to index
5. **Related Docs**: Always include related documents for context

---

## Success Metrics

Track these metrics to improve the system:

- **Solution Success Rate**: % of quoted solutions that solved the problem
- **User Satisfaction**: User feedback ratings (1-5 stars)
- **Problem Frequency**: Problems occurring ≥5 times need refactoring
- **Document Quality**: Average success rate per document
- **Response Time**: Time to find and quote solution

---

**Version**: 1.0.0
**Last Updated**: 2026-02-08
