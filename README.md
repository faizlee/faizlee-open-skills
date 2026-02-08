# Faizlee Open Skills

> 公开 Claude Code 技能仓库 - 由 Faizlee 维护的开源技能集合

[![License](https://img.shields.io/badge/license-MIT-green)]()
[![Claude Code](https://img.shields.io/badge/Claude_Code-compatible-orange)]()

## 📚 技能列表

### [claude-knowledge](./claude-knowledge/)

**智能项目知识索引系统** - 让 Claude Code 更聪明，避免重复解决问题

- ⚡ **5 种搜索模式**: 问题记录、关键词、模块、类型、关联文档
- 🧠 **智能匹配**: 上下文、时间、条件、关键词置信度评分
- 📈 **持续学习**: 自动记录、动态权重、问题频率追踪
- ✅ **质量保证**: 三层检查、时间衰减、用户反馈循环
- 🌐 **跨项目支持**: 每个项目独立索引

**[→ 查看详情](./claude-knowledge/README.md)**

## 🚀 快速开始

### 安装单个技能

```bash
# 克隆仓库
git clone https://github.com/faizlee/faizlee-open-skills.git

# 复制技能到本地
cp -r faizlee-open-skills/claude-knowledge ~/.claude/skills/

# 或者使用软链接（推荐）
ln -s $(pwd)/faizlee-open-skills/claude-knowledge ~/.claude/skills/claude-knowledge
```

### 安装所有技能

```bash
# 克隆仓库
git clone https://github.com/faizlee/faizlee-open-skills.git

# 批量安装
cd faizlee-open-skills
for skill in */; do
  ln -s $(pwd)/"$skill" ~/.claude/skills/"$skill"
done
```

## 🛠️ 技能开发

### 技能结构

```
skill-name/
├── SKILL.md              # 技能主文件（必需）
├── README.md             # 技能说明（推荐）
├── scripts/              # 脚本工具（可选）
├── references/           # 参考文档（可选）
└── assets/               # 资源文件（可选）
```

### 提交新技能

欢迎提交新的技能！请确保：

1. ✅ 技能通过测试
2. ✅ 包含完整的 README.md
3. ✅ SKILL.md 有清晰的触发词
4. ✅ 遵循 MIT 许可证

## 🤝 贡献指南

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-skill`)
3. 提交更改 (`git commit -m 'feat: add amazing skill'`)
4. 推送到分支 (`git push origin feature/amazing-skill`)
5. 开启 Pull Request

## 📝 许可证

MIT License - 详见 [LICENSE](./LICENSE) 文件

## 🌟 致谢

- [Claude Code](https://claude.ai/code) - AI 编程助手
- 所有贡献者

## 📮 联系方式

- GitHub: [@faizlee](https://github.com/faizlee)
- Issues: [提交问题](https://github.com/faizlee/faizlee-open-skills/issues)

---

**仓库版本**: 1.0.0
**最后更新**: 2026-02-08
**维护者**: Faizlee
