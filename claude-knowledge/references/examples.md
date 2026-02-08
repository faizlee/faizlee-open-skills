# 工作流程示例

本文档提供项目知识索引系统在实际场景中的工作流程示例。

## 示例 1: Bug 修复问题

### 用户提问

> "积分冻结失败"

### 搜索流程

1. **问题记录匹配**
   ```
   搜索: problem-log.json
   找到: PROB-001（5次出现）
   问题: "积分冻结失败"
   首次出现: 2026-02-05
   最后出现: 2026-02-07
   ```

2. **返回解决方案**
   ```
   文档: implementation.md
   章节: "积分冻结"
   置信度: high
   ```

3. **验证**
   - ✅ 上下文: 同一模块
   - ✅ 时间: 1天前更新
   - ✅ 前置条件: 全部满足
   - ✅ 关键词: ["积分", "冻结"] → 100%匹配

4. **置信度评分**
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

5. **操作**: 直接引用解决方案

### 更新记录

```json
{
  "occurrence_count": 6,  // 从5增加到6
  "last_seen": "2026-02-08",
  "solutions": [
    {
      "document": "implementation.md",
      "section": "积分冻结",
      "confidence": "high",
      "success_count": 13,
      "success_rate": 0.93
    }
  ]
}
```

### 文档权重更新

```python
document["reference_count"] += 1  // 现在是123
document["last_referenced"] = "2026-02-08"
document["weight"] = calculate_weight(document)
// 结果: 85 → 90
```

---

## 示例 2: 新功能询问

### 用户提问

> "如何实现历史记录功能？"

### 搜索流程

1. **问题记录匹配**
   ```
   搜索: problem-log.json
   结果: 无完全匹配
   ```

2. **关键词搜索**
   ```
   提取关键词: ["历史", "记录", "实现"]
   搜索: INDEX.md → 按标签匹配
   找到: history-implementation.md
   ```

3. **模块分类**
   ```
   模块: 对应功能模块
   搜索: INDEX.md → 在该模块下查找
   找到: history-implementation.md
   ```

4. **返回解决方案**
   ```
   文档: history-implementation.md
   类型: [implementation, guide]
   ```

5. **验证**
   - ✅ 上下文: 同一模块
   - ✅ 时间: 3周前更新
   - ✅ 类型: 实现指南
   - ✅ 关键词: ["历史", "记录"] → 66%匹配

6. **置信度评分**
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

7. **操作**: 引用实现指南

### 创建新问题记录

```json
{
  "id": "PROB-XXX",
  "question": "如何实现历史记录功能？",
  "normalized": "history feature implementation",
  "first_seen": "2026-02-08",
  "last_seen": "2026-02-08",
  "occurrence_count": 1,
  "module": "feature-module",
  "type": "feature",
  "solutions": [
    {
      "document": "history-implementation.md",
      "section": "实现",
      "confidence": "high"
    }
  ],
  "status": "active"
}
```

---

## 示例 3: 质量问题处理

### 用户提问

> "移动端测试为什么只有15.4%通过率？"

### 搜索流程

1. **问题记录匹配**
   ```
   搜索: problem-log.json
   找到: PROB-002（3次出现）
   问题: "移动端测试通过率低"
   ```

2. **返回解决方案**
   ```
   文档: mobile-test-report-2026-02-07.md
   类型: [test, report]
   ```

3. **验证**
   - ✅ 上下文: 测试模块
   - ✅ 时间: 1天前更新
   - ✅ 类型: 测试报告
   - ⚠️ 质量检查需要

4. **质量检查**
   ```
   文档元数据:
   - 质量标记: "low（选择器问题，功能正常）"
   - 状态: active
   - 成功率: N/A（测试报告，非解决方案）
   ```

5. **置信度评分**
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

6. **操作**: 引用解决方案并说明

### 回应示例

```
在 mobile-test-report-2026-02-07.md 中找到解决方案：

📊 测试结果:
- 通过率: 15.4% (4/26 测试)
- 根本原因: 选择器问题，非功能性问题
- 功能状态: ✅ 正常工作
- 建议: 更新移动端测试选择器

⚠️ 注意: 低通过率是由于选择器配置问题，
非功能问题。所有功能在移动端正常工作。
```

---

## 关键要点

1. **高置信度 (≥70)**: 直接引用，更新记录
2. **中置信度 (50-69)**: 引用并验证警告
3. **低置信度 (<50)**: 询问用户，记录新问题
4. **无匹配**: 设计解决方案，实现后添加到索引

---

## 成功指标

追踪以下指标以改进系统：

- **解决方案成功率**: 引用的解决方案中解决问题的百分比
- **用户满意度**: 用户反馈评分（1-5星）
- **问题频率**: 出现≥5次的问题需要重构
- **文档质量**: 每个文档的平均成功率
- **响应时间**: 查找和引用解决方案的时间

---

**版本**: 1.0.0
**最后更新**: 2026-02-08
