# Claude Knowledge

> **智能项目知识索引系统** - 让 Claude Code 更聪明，避免重复解决问题

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Skill Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/faizlee/faizlee-open-skills)
[![Platform](https://img.shields.io/badge/Platform-Claude%20Code-informational.svg)](https://claude.ai/code)

---

## 🎯 核心功能

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

---

## 📦 安装

### 方式 1: 克隆仓库（推荐）

```bash
# 克隆仓库
git clone https://github.com/faizlee/faizlee-open-skills.git

# 复制技能到本地
cp -r faizlee-open-skills/claude-knowledge ~/.claude/skills/

# 或者使用软链接（推荐）
ln -s $(pwd)/faizlee-open-skills/claude-knowledge ~/.claude/skills/claude-knowledge
```

### 方式 2: 手动安装

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

---

## 🚀 快速开始

### 1. 初始化索引

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

### 2. 开始使用

初始化后，直接提问即可：

```
你: "积分冻结失败"
Claude: [搜索索引 → 找到 PROB-001（5次出现）→ 直接引用解决方案]
```

---

## 💡 使用场景

### 场景 1: Bug 修复

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

### 场景 2: 新功能询问

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

### 场景 3: 质量问题处理

```
用户问题: "移动端测试为什么只有15.4%通过率？"

搜索流程:
1. 问题记录匹配 → 找到 PROB-002（3次出现）
2. 返回解决方案: mobile-test-report-2026-02-07.md
3. 验证: 上下文✓、时间✓
4. **质量检查**: 文档标记 "选择器问题，功能正常"
5. 置信度: 88/100 (高)
6. ✅ 引用解决方案并说明原因
```

---

## 🔧 触发条件

### 自动触发场景

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

### 前置条件

- 项目根目录存在 `docs/knowledge-index/` 目录
- 首次使用会自动创建索引

---

## 📂 索引结构

```
docs/knowledge-index/
├── INDEX.md              # 文档索引（结构化）
└── problem-log.json      # 问题记录（错题集）
```

### INDEX.md 格式

```markdown
## auth

### 核心实现
- **文件**: `auth-implementation.md`
- **关键词**: [登录, 注册, session, token]
- **类型**: [implementation, guide, production]
- **模块**: auth
- **权重**: 85
- **最后引用**: 2026-02-07
- **相关文档**: [session-management.md, auth-middleware.md]
```

### problem-log.json 格式

```json
{
  "version": "1.0",
  "last_updated": "2026-02-08",
  "problems": [
    {
      "id": "PROB-001",
      "question": "积分冻结失败",
      "normalized": "credit freeze failed",
      "first_seen": "2026-02-05",
      "last_seen": "2026-02-07",
      "occurrence_count": 5,
      "module": "payment",
      "type": "bug",
      "solutions": [
        {
          "document": "implementation.md",
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

---

## 🛠️ 高级用法

### 手动构建索引

```bash
python scripts/build_index.py
```

### 搜索索引

```bash
python scripts/search_index.py "关键词"
```

### 更新权重

```bash
python scripts/update_weights.py
```

### 配置文件

项目根目录创建 `.knowledge-index-config.json`:

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

## ❓ 常见问题

### Q: 索引不存在怎么办？

**A**: 选择"自动创建"选项，技能会自动扫描并构建索引

### Q: 搜索返回空结果？

**A**: 可能原因：
1. 关键词不准确 → 尝试其他关键词
2. 文档未索引 → 运行 `build_index.py` 重建索引
3. 文档被删除 → 检查文档状态

### Q: 技能没有自动触发？

**A**: 检查：
1. 技能是否正确安装到 `~/.claude/skills/`
2. SKILL.md 中的触发词是否包含你的问题关键词
3. 项目是否有 `docs/knowledge-index/` 目录

---

## 📊 技术细节

### 搜索模式

1. **问题记录匹配**（最高优先级）- 查找已解决的问题
2. **关键词搜索** - 提取关键词在 tags 中查找
3. **模块分类** - 按功能模块分类搜索
4. **类型搜索** - 按 Bug/Feature/Refactor 等类型搜索
5. **关联搜索** - 递归查找相关文档

### 智能匹配算法

- **上下文匹配**（30分）- 比较模块、技术栈、文件路径
- **时间验证**（20分）- 检查文档时效性
- **条件匹配**（30分）- 验证前置条件
- **关键词重合度**（20分）- 计算关键词相似度

**置信度**:
- **高** (≥70): 直接引用解决方案
- **中** (50-69): 引用并提示验证
- **低** (<50): 询问用户或重新思考

---

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
python tests/test_skill.py

# 提交更改
git add .
git commit -m "feat: update skill"
git push
```

---

## 📝 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

---

## 🌟 致谢

- [Claude Code](https://claude.ai/code) - AI 编程助手
- 所有贡献者

---

## 📮 联系方式

- GitHub: [@faizlee](https://github.com/faizlee)
- Issues: [提交问题](https://github.com/faizlee/faizlee-open-skills/issues)

---

**仓库版本**: 1.0.0
**最后更新**: 2026-02-08
**维护者**: Faizlee & Claude
