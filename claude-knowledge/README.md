# Claude Knowledge

> **智能项目知识索引系统** - 让 Claude Code 更聪明，避免重复解决问题

[![Skill Version](https://img.shields.io/badge/version-1.0.0-blue)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()
[![Claude Code](https://img.shields.io/badge/Claude_Code-compatible-orange)]()

## 🎯 核心理念

**在回答任何问题前，先搜索已有解决方案。避免重复工作，持续积累知识。**

### 为什么需要这个技能？

- ❌ **问题**: AI 经常重复回答相同的问题，浪费时间
- ❌ **问题**: 现有的文档缺乏智能关联和检索机制
- ❌ **问题**: 问题没有追踪机制，无法识别需要整改的模块
- ❌ **问题**: 新方案没有自动积累到知识库

### 解决方案

Claude Knowledge 是一个智能索引系统，可以：

✅ **快速找到**已有解决方案（5 种搜索模式）
✅ **智能匹配**判断适用性（置信度评分）
✅ **持续学习**新方案（动态权重 + 问题频率）
✅ **质量保证**（三层检查 + 时间衰减）
✅ **跨项目支持**（每个项目独立索引）

## 🚀 快速开始

### 安装

```bash
# 克隆仓库
git clone https://github.com/faizlee/faizlee-open-skills.git

# 复制技能到本地技能目录
cp -r faizlee-open-skills/claude-knowledge ~/.claude/skills/

# 或者使用软链接（推荐）
ln -s ~/faizlee-open-skills/claude-knowledge ~/.claude/skills/claude-knowledge
```

### 首次使用

1. **打开项目**
   ```bash
   cd /path/to/your/project
   ```

2. **确保项目有 `docs/` 目录**
   ```bash
   mkdir -p docs
   ```

3. **让 Claude 使用技能**
   - 技能会自动检测 `docs/` 目录
   - 提示创建知识索引
   - 选择"自动创建"（推荐）

4. **开始提问**
   - Claude 会先搜索索引
   - 找到方案直接引用
   - 找不到记录新问题

## 🔍 核心功能

### 1. 多重搜索模式

**模式 1: 问题记录匹配**（最高优先级）
- 直接在 `problem-log.json` 中查找完全相同的问题
- 适用场景：用户之前问过类似问题

**模式 2: 关键词搜索**
- 提取问题中的关键词（模块名、技术栈、错误信息）
- 在索引的 tags 字段中查找匹配

**模式 3: 模块分类搜索**
- 按功能模块分类（小红书/视频/认证等）
- 适用于"XX模块的XX问题"

**模式 4: 问题类型搜索**
- 按类型分类（Bug/Feature/Refactor/Test/Doc）
- 快速定位相关文档

**模式 5: 关联搜索**
- 找到文档后，递归查找其 `related_documents`
- 扩展搜索范围

### 2. 智能匹配判断

找到候选文档后，执行以下检查：

| 检查项 | 权重 | 说明 |
|--------|------|------|
| 上下文匹配 | 30分 | 比较模块、环境、技术栈 |
| 时间验证 | 20分 | 6个月内+20分，超过1年-10分 |
| 条件匹配 | 30分 | 检查前置条件是否满足 |
| 关键词重合度 | 20分 | 关键词匹配比例 |

**置信度评分**:
- **高 (≥70)**: 直接引用解决方案
- **中 (50-69)**: 引用并提示验证
- **低 (<50)**: 询问用户或重新思考

### 3. 持续学习机制

**自动记录**:
- 每次问题解决后自动记录
- 更新问题出现次数
- 关联解决方案文档

**动态权重**:
```python
weight = 50  # 基础权重
weight += references × 5  # 引用次数
weight += problem_links × 3  # 问题关联
weight += keyword_density × 2  # 关键词密度
weight -= time_decay  # 时间衰减
weight += recent_boost  # 最近提升
weight += quality_adjustment  # 质量调整
```

**问题频率分析**:
- 问题出现次数 ≥ 5 → 标记需要整改
- 生成重构建议
- 优先级排序

### 4. 质量保证

**Layer 1: 文档元数据**
- 质量标记 (high/medium/low)
- 状态 (active/deprecated/archived)
- 最后审核日期
- 置信度（基于历史成功率）

**Layer 2: 时间衰减警告**
- 超过 1 年未更新 → 警告：可能已过时
- 超过 6 个月未更新 → 警告：请验证
- 自动降低权重

**Layer 3: 用户反馈循环**
- 成功率追踪
- 用户评分
- 评论记录
- 自动调整质量评估

## 📁 索引结构

```
docs/knowledge-index/
├── INDEX.md              # 文档索引（结构化）
└── problem-log.json      # 问题记录（错题集）
```

### INDEX.md 格式

```markdown
## xiaohongshu-cover

### 核心实现
- **文件**: `xiaohongshu-cover-implementation.md`
- **关键词**: [积分冻结, 两阶段生成, FIFO, 批量生成]
- **类型**: [implementation, guide, production]
- **模块**: xiaohongshu-cover
- **权重**: 85
- **最后引用**: 2026-02-07
- **相关文档**: [xiaohongshu-cover-state-management.md, credit.ts]
```

### problem-log.json 格式

```json
{
  "version": "1.0",
  "last_updated": "2026-02-08",
  "problems": [
    {
      "id": "PROB-001",
      "question": "小红书封面生成器积分冻结失败",
      "normalized": "xiaohongshu credit freeze failed",
      "first_seen": "2026-02-05",
      "last_seen": "2026-02-07",
      "occurrence_count": 5,
      "module": "xiaohongshu-cover",
      "type": "bug",
      "solutions": [
        {
          "document": "xiaohongshu-cover-implementation.md",
          "section": "积分冻结",
          "confidence": "high"
        }
      ],
      "status": "active",
      "needs_refactor": false
    }
  ]
}
```

## 🛠️ 脚本工具

### 构建索引

```bash
# 自动扫描 docs/ 并构建索引
python scripts/build_index.py

# 指定项目根目录
python scripts/build_index.py --project-root /path/to/project

# 自动分类和提取关键词
python scripts/build_index.py --auto-classify --extract-keywords
```

### 搜索索引

```bash
# 搜索关键词
python scripts/search_index.py "小红书封面"

# 指定项目
python scripts/search_index.py "积分冻结" --project-root /path/to/project
```

### 更新权重

```bash
# 重新计算所有文档权重
python scripts/update_weights.py

# 基于问题频率调整
python scripts/update_weights.py --frequency-based
```

## 📖 使用示例

### 示例 1: Bug 修复问题

**用户**: "小红书封面生成器积分冻结失败"

**Claude**:
1. 搜索索引 → 找到 PROB-001（5次出现）
2. 返回解决方案: `xiaohongshu-cover-implementation.md#积分冻结`
3. 验证: 上下文✓、时间✓、条件✓
4. 置信度: 92/100 (高)
5. ✅ 直接引用解决方案

**更新**:
- PROB-001.occurrence_count += 1 (变为 6)
- xiaohongshu-cover-implementation.md.reference_count += 1
- xiaohongshu-cover-implementation.md.weight += 5

### 示例 2: 新功能询问

**用户**: "如何实现小红书封面的历史记录功能？"

**Claude**:
1. 搜索索引 → 无完全匹配
2. 关键词搜索 → "历史记录", "小红书"
3. 模块分类 → xiaohongshu-cover
4. 找到: `xiaohongshu-cover-history-implementation.md`
5. 验证: 上下文✓、功能实现文档
6. 置信度: 85/100 (高)
7. ✅ 引用实现指南

**更新**:
- 创建新问题记录 PROB-XXX
- 关联到 `xiaohongshu-cover-history-implementation.md`

### 示例 3: 质量问题处理

**用户**: "移动端测试为什么只有15.4%通过率？"

**Claude**:
1. 搜索索引 → 找到 PROB-002（3次出现）
2. 返回解决方案: `mobile-responsive-test-report-2026-02-07.md`
3. 验证: 上下文✓、时间✓
4. **质量检查**: ⚠️ 文档标记 "测试失败原因是选择器问题，功能正常"
5. 置信度: 88/100 (高)
6. ✅ 引用解决方案并说明原因

## ⚙️ 配置选项

### 项目配置文件

在项目根目录创建 `.knowledge-index-config.json`:

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

### 环境变量

```bash
# 禁用自动更新
export CLAude_KNOWLEDGE_AUTO_UPDATE=false

# 设置质量阈值
export CLAUDE_KNOWLEDGE_QUALITY_THRESHOLD=0.7

# 启用文件监听（可选）
export CLAUDE_KNOWLEDGE_WATCH_FILES=true
```

## 🔧 故障排查

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

### 技能未触发

**问题**: 技能没有被自动触发

**解决**:
1. 检查 `CLAUDE.md` 是否包含工作流程优先级章节
2. 确保技能已正确安装到 `~/.claude/skills/`
3. 尝试手动触发技能："使用 claude-knowledge 技能"

## 🤝 贡献指南

欢迎贡献！请遵循以下步骤：

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'feat: add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启 Pull Request

### 开发指南

```bash
# 克隆仓库
git clone https://github.com/faizlee/faizlee-open-skills.git

# 进入技能目录
cd faizlee-open-skills/claude-knowledge

# 编辑技能
vim SKILL.md

# 测试技能
# 1. 复制到本地技能目录
cp -r . ~/.claude/skills/claude-knowledge

# 2. 在项目中测试
cd /path/to/your/project
# Claude 会自动加载技能

# 3. 提交更改
git add .
git commit -m "feat: update skill"
git push
```

## 📝 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 🌟 致谢

- [Claude Code](https://claude.ai/code) - AI 编程助手
- [VideoFly](https://github.com/faizlee/videofly) - 测试项目

## 📮 联系方式

- GitHub: [@faizlee](https://github.com/faizlee)
- Issues: [提交问题](https://github.com/faizlee/faizlee-open-skills/issues)

---

**技能版本**: 1.0.0
**最后更新**: 2026-02-08
**维护者**: Faizlee & Claude
