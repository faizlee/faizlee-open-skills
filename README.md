# Claude Knowledge

> **智能项目知识索引系统** - 让 Claude Code 更聪明，避免重复解决问题
>
> **Intelligent Project Knowledge Indexing System** - Make Claude Code smarter by avoiding repetitive problem-solving

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Skill Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/faizlee/faizlee-open-skills)
[![Platform](https://img.shields.io/badge/Platform-Claude%20Code-informational.svg)](https://claude.ai/code)

**[English](#english) | [简体中文](#简体中文)**

---

## 简体中文

### 🎯 核心功能

**问题**: AI 经常重复回答相同的问题，浪费时间，缺乏智能关联和检索机制

**解决方案**: Claude Knowledge 是一个智能索引系统，在回答任何问题前先搜索已有解决方案

### 主要特性

- ✅ **5种搜索模式** - 问题记录、关键词、模块、类型、关联文档
- ✅ **智能匹配** - 上下文、时间、条件、关键词置信度评分
- ✅ **持续学习** - 自动记录、动态权重、问题频率追踪
- ✅ **质量保证** - 三层检查、时间衰减、用户反馈循环
- ✅ **跨项目支持** - 每个项目独立索引
- ✅ **中英双语** - 24个触发场景，覆盖全球用户

### 效果对比

| 场景 | 使用前 | 使用后 |
|------|--------|--------|
| **Bug修复** | 重新分析代码 | 直接引用历史解决方案 |
| **功能实现** | 从零开始设计 | 引用已有实现方案 |
| **文档查询** | 手动搜索文档 | 智能索引秒级响应 |
| **知识积累** | 遗忘经验 | 持续学习，越用越聪明 |

### 📦 安装

#### 方式 1: 克隆仓库（推荐）

```bash
# 克隆仓库
git clone https://github.com/faizlee/faizlee-open-skills.git

# 复制技能到本地
cp -r faizlee-open-skills/claude-knowledge ~/.claude/skills/

# 或者使用软链接（推荐）
ln -s $(pwd)/faizlee-open-skills/claude-knowledge ~/.claude/skills/claude-knowledge
```

#### 方式 2: 手动安装

```bash
# 1. 创建技能目录
mkdir -p ~/.claude/skills/claude-knowledge

# 2. 下载 SKILL.md
curl -o ~/.claude/skills/claude-knowledge/SKILL.md \
  https://raw.githubusercontent.com/faizlee/faizlee-open-skills/main/claude-knowledge/SKILL.md

# 3. 下载脚本（可选）
cd ~/.claude/skills/claude-knowledge
curl -O https://raw.githubusercontent.com/faizlee/faizlee-open-skills/main/claude-knowledge/scripts/build_index.py
curl -O https://raw.githubusercontent.com/faizlee/faizlee-open-skills/main/claude-knowledge/scripts/search_index.py
```

### 🚀 快速开始

#### 1. 初始化索引

首次使用时，技能会自动检测 `docs/` 目录并提示创建索引：

```bash
cd /path/to/your/project

# 确保有 docs/ 目录
mkdir -p docs

# 在 Claude Code 中提问，技能会自动初始化
```

**提示示例**:
```
🤖 检测到项目中有 104 个文档，是否创建知识索引？

选项:
  1. 自动创建（推荐）- 5-10秒
  2. 手动配置 - 自定义模块和关键词
  3. 跳过 - 不创建索引
```

#### 2. 开始使用

初始化后，直接提问即可：

```
你: "积分冻结失败"
Claude: [搜索索引 → 找到 PROB-001（5次出现）→ 直接引用解决方案]
```

### 💡 使用场景

#### 场景 1: Bug 修复

```
用户问题: "积分冻结失败"

搜索流程:
1. 问题记录匹配 → 找到 PROB-001（5次出现）
2. 返回解决方案: implementation.md#积分冻结
3. 验证: 上下文✓、时间✓、条件✓
4. 置信度: 92/100 (高)
5. ✅ 直接引用解决方案

更新:
- PROB-001.occurrence_count += 1 (变为 6)
- implementation.md.reference_count += 1
- implementation.md.weight += 5
```

#### 场景 2: 新功能询问

```
用户问题: "如何实现历史记录功能？"

搜索流程:
1. 问题记录匹配 → 无匹配
2. 关键词搜索 → "历史", "记录"
3. 模块分类 → 对应模块
4. 找到: history-implementation.md
5. 验证: 上下文✓、功能实现文档
6. 置信度: 85/100 (高)
7. ✅ 引用实现指南

更新:
- 创建新问题记录 PROB-XXX
- 关联到 history-implementation.md
```

### 🔧 触发条件

#### 自动触发场景

技能会在以下场景自动触发：

**中文触发词**:
- 项目问题、技术文档、实现方案
- Bug修复、功能开发、代码审查
- 架构设计、集成部署、配置环境
- 测试调试、性能优化、重构改进

**英文触发词**:
- Project issues, technical docs, implementation
- Bug fix, feature development, code review
- Architecture, integration, deployment, testing
- Debugging, optimization, refactoring

### ❓ 常见问题

#### Q: 索引不存在怎么办？

**A**: 选择"自动创建"选项，技能会自动扫描并构建索引

#### Q: 搜索返回空结果？

**A**: 可能原因：
1. 关键词不准确 → 尝试其他关键词
2. 文档未索引 → 运行 `build_index.py` 重建索引
3. 文档被删除 → 检查文档状态

#### Q: 技能没有自动触发？

**A**: 检查：
1. 技能是否正确安装到 `~/.claude/skills/`
2. SKILL.md 中的触发词是否包含你的问题关键词
3. 项目是否有 `docs/knowledge-index/` 目录

### 🤝 贡献指南

欢迎贡献！请遵循以下步骤：

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'feat: add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启 Pull Request

### 📝 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

---

## English

### 🎯 Core Features

**Problem**: AI often repeats answers to the same questions, wasting time without intelligent association and retrieval mechanisms

**Solution**: Claude Knowledge is an intelligent indexing system that searches existing solutions before answering any question

### Key Features

- ✅ **5 Search Modes** - Problem log, keywords, module, type, related documents
- ✅ **Smart Matching** - Context, time, conditions, keyword confidence scoring
- ✅ **Continuous Learning** - Auto-record, dynamic weights, problem frequency tracking
- ✅ **Quality Assurance** - 3-layer checks, time decay, user feedback loop
- ✅ **Cross-project Support** - Independent index per project
- ✅ **Bilingual** - 24 trigger scenarios, global coverage

### Before & After

| Scenario | Before | After |
|----------|--------|-------|
| **Bug Fix** | Re-analyze code | Quote historical solution directly |
| **Feature Implementation** | Design from scratch | Quote existing implementation |
| **Documentation Query** | Manual search | Intelligent index, instant response |
| **Knowledge Accumulation** | Forget experience | Continuous learning, smarter over time |

### 📦 Installation

#### Method 1: Clone Repository (Recommended)

```bash
# Clone repository
git clone https://github.com/faizlee/faizlee-open-skills.git

# Copy skill to local
cp -r faizlee-open-skills/claude-knowledge ~/.claude/skills/

# Or use symlink (recommended)
ln -s $(pwd)/faizlee-open-skills/claude-knowledge ~/.claude/skills/claude-knowledge
```

#### Method 2: Manual Installation

```bash
# 1. Create skill directory
mkdir -p ~/.claude/skills/claude-knowledge

# 2. Download SKILL.md
curl -o ~/.claude/skills/claude-knowledge/SKILL.md \
  https://raw.githubusercontent.com/faizlee/faizlee/open-skills/main/claude-knowledge/SKILL.md

# 3. Download scripts (optional)
cd ~/.claude/skills/claude-knowledge
curl -O https://raw.githubusercontent.com/faizlee/faizlee/open-skills/main/claude-knowledge/scripts/build_index.py
curl -O https://raw.githubusercontent.com/faizlee/faizlee/open-skills/main/claude-knowledge/scripts/search_index.py
```

### 🚀 Quick Start

#### 1. Initialize Index

On first use, the skill will automatically detect the `docs/` directory and prompt to create an index:

```bash
cd /path/to/your/project

# Ensure docs/ directory exists
mkdir -p docs

# Ask in Claude Code, skill will auto-initialize
```

**Prompt Example**:
```
🤖 Detected 104 documents in project. Create knowledge index?

Options:
  1. Auto-create (Recommended) - 5-10 seconds
  2. Manual config - Customize modules and keywords
  3. Skip - Don't create index
```

#### 2. Start Using

After initialization, just ask questions:

```
You: "Credit freezing failed"
Claude: [Search index → Found PROB-001 (5 occurrences) → Quote solution directly]
```

### 💡 Use Cases

#### Scenario 1: Bug Fix

```
User Question: "Credit freezing failed"

Search Flow:
1. Problem log match → Found PROB-001 (5 occurrences)
2. Return solution: implementation.md#credit-freeze
3. Verify: Context✓, Time✓, Conditions✓
4. Confidence: 92/100 (high)
5. ✅ Quote solution directly

Update:
- PROB-001.occurrence_count += 1 (becomes 6)
- implementation.md.reference_count += 1
- implementation.md.weight += 5
```

#### Scenario 2: New Feature Question

```
User Question: "How to implement history feature?"

Search Flow:
1. Problem log match → No match
2. Keyword search → "history", "record"
3. Module classification → Corresponding module
4. Found: history-implementation.md
5. Verify: Context✓, implementation guide
6. Confidence: 85/100 (high)
7. ✅ Quote implementation guide

Update:
- Create new problem record PROB-XXX
- Link to history-implementation.md
```

### 🔧 Trigger Conditions

#### Auto-Trigger Scenarios

The skill will auto-trigger in these scenarios:

**Chinese Triggers**:
- 项目问题、技术文档、实现方案
- Bug修复、功能开发、代码审查
- 架构设计、集成部署、配置环境
- 测试调试、性能优化、重构改进

**English Triggers**:
- Project issues, technical docs, implementation
- Bug fix, feature development, code review
- Architecture, integration, deployment, testing
- Debugging, optimization, refactoring

### ❓ FAQ

#### Q: What if index doesn't exist?

**A**: Select "Auto-create" option, skill will automatically scan and build index

#### Q: Search returns empty results?

**A**: Possible reasons:
1. Inaccurate keywords → Try other keywords
2. Document not indexed → Run `build_index.py` to rebuild
3. Document deleted → Check document status

#### Q: Skill not auto-triggering?

**A**: Check:
1. Skill correctly installed in `~/.claude/skills/`
2. Trigger words in SKILL.md match your question keywords
3. Project has `docs/knowledge-index/` directory

### 🤝 Contributing

Contributions welcome! Please follow these steps:

1. Fork this repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'feat: add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

### 📝 License

MIT License - see [LICENSE](LICENSE) file for details

---

## 🌟 Acknowledgments

- [Claude Code](https://claude.ai/code) - AI programming assistant
- All contributors

---

## 📮 Contact

- GitHub: [@faizlee](https://github.com/faizlee)
- Issues: [Submit issues](https://github.com/faizlee/faizlee-open-skills/issues)

---

**Repository Version**: 1.0.0
**Last Updated**: 2026-02-08
**Maintainer**: Faizlee & Claude
