# Claude Knowledge

> **Intelligent Project Knowledge Indexing System** - Make Claude Code smarter by avoiding repetitive problem-solving

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Skill Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/faizlee/faizlee-open-skills)
[![Platform](https://img.shields.io/badge/Platform-Claude%20Code-informational.svg)](https://claude.ai/code)

**English | [简体中文](./README.zh-CN.md)**

---

## Available Skills

- [Claude Knowledge](./claude-knowledge/) - Intelligent project knowledge indexing system.
- [Todo Database](./todo-database/) - Project TODO database management.
- [AI Relay](./ai-relay/) - User-level Codex / Claude Code file relay with bind, relay, history archive, Chinese audit reports, and local rule-based reviews.

---

## 🎯 Core Features

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

---

## 📦 Installation

### Method 1: Clone Repository (Recommended)

```bash
# Clone repository
git clone https://github.com/faizlee/faizlee-open-skills.git

# Copy skill to local
cp -r faizlee-open-skills/claude-knowledge ~/.claude/skills/

# Or use symlink (recommended)
ln -s $(pwd)/faizlee-open-skills/claude-knowledge ~/.claude/skills/claude-knowledge
```

### Method 2: Manual Installation

```bash
# 1. Create skill directory
mkdir -p ~/.claude/skills/claude-knowledge

# 2. Download SKILL.md
curl -o ~/.claude/skills/claude-knowledge/SKILL.md \
  https://raw.githubusercontent.com/faizlee/faizlee-open-skills/main/claude-knowledge/SKILL.md

# 3. Download scripts (optional)
cd ~/.claude/skills/claude-knowledge
curl -O https://raw.githubusercontent.com/faizlee/faizlee-open-skills/main/claude-knowledge/scripts/build_index.py
curl -O https://raw.githubusercontent.com/faizlee/faizlee-open-skills/main/claude-knowledge/scripts/search_index.py
```

---

## 🚀 Quick Start

### 1. Initialize Index

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

### 2. Start Using

After initialization, just ask questions:

```
You: "Credit freezing failed"
Claude: [Search index → Found PROB-001 (5 occurrences) → Quote solution directly]
```

---

## 💡 Use Cases

### Scenario 1: Bug Fix

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

### Scenario 2: New Feature Question

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

---

## 🔧 Trigger Conditions

### Auto-Trigger Scenarios

The skill will auto-trigger in these scenarios:

**English Triggers**:
- Project issues, technical docs, implementation
- Bug fix, feature development, code review
- Architecture, integration, deployment, testing
- Debugging, optimization, refactoring

**Chinese Triggers (中文触发词)**:
- 项目问题、技术文档、实现方案
- Bug修复、功能开发、代码审查
- 架构设计、集成部署、配置环境
- 测试调试、性能优化、重构改进

### Prerequisites

- Project has `docs/knowledge-index/` directory
- First use will auto-create index

---

## 📂 Index Structure

```
docs/knowledge-index/
├── INDEX.md              # Document index (structured)
└── problem-log.json      # Problem records (error log)
```

### INDEX.md Format

```markdown
## auth

### Core Implementation
- **File**: `auth-implementation.md`
- **Keywords**: [login, register, session, token]
- **Types**: [implementation, guide, production]
- **Module**: auth
- **Weight**: 85
- **Last Referenced**: 2026-02-07
- **Related Docs**: [session-management.md, auth-middleware.md]
```

### problem-log.json Format

```json
{
  "version": "1.0",
  "last_updated": "2026-02-08",
  "problems": [
    {
      "id": "PROB-001",
      "question": "Credit freezing failed",
      "normalized": "credit freeze failed",
      "first_seen": "2026-02-05",
      "last_seen": "2026-02-07",
      "occurrence_count": 5,
      "module": "payment",
      "type": "bug",
      "solutions": [
        {
          "document": "implementation.md",
          "section": "Credit Freeze",
          "confidence": "high"
        }
      ],
      "status": "active",
      "needs_refactor": false
    }
  ]
}
```

---

## 🛠️ Advanced Usage

### Manual Index Build

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

### Configuration File

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

---

## ❓ FAQ

### Q: What if index doesn't exist?

**A**: Select "Auto-create" option, skill will automatically scan and build index

### Q: Search returns empty results?

**A**: Possible reasons:
1. Inaccurate keywords → Try other keywords
2. Document not indexed → Run `build_index.py` to rebuild
3. Document deleted → Check document status

### Q: Skill not auto-triggering?

**A**: Check:
1. Skill correctly installed in `~/.claude/skills/`
2. Trigger words in SKILL.md match your question keywords
3. Project has `docs/knowledge-index/` directory

---

## 📊 Technical Details

### Search Modes

1. **Problem Log Match** (Highest priority) - Find solved problems
2. **Keyword Search** - Extract keywords and search in tags
3. **Module Classification** - Search by functional module
4. **Type Search** - Search by Bug/Feature/Refactor types
5. **Related Documents** - Recursively search related docs

### Smart Matching Algorithm

- **Context Match** (30 pts) - Compare module, tech stack, file paths
- **Time Validation** (20 pts) - Check document recency
- **Condition Match** (30 pts) - Verify prerequisites
- **Keyword Overlap** (20 pts) - Calculate keyword similarity

**Confidence Levels**:
- **High** (≥70): Quote solution directly
- **Medium** (50-69): Quote with verification prompt
- **Low** (<50): Ask user or rethink

---

## 🤝 Contributing

Contributions welcome! Please follow these steps:

1. Fork this repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'feat: add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

### Development Guide

```bash
# Clone repository
git clone https://github.com/faizlee/faizlee-open-skills.git

# Enter skill directory
cd faizlee-open-skills/claude-knowledge

# Edit skill
vim SKILL.md

# Test skill
python tests/test_skill.py

# Commit changes
git add .
git commit -m "feat: update skill"
git push
```

---

## 📝 License

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
