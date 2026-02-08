# GitHub 仓库设置指南

## 仓库信息

- **仓库名称**: `faizlee-open-skills`
- **技能名称**: `claude-knowledge`
- **位置**: `~/faizlee-open-skills/`
- **许可证**: MIT License

## 文件结构

```
faizlee-open-skills/
├── .git/                          # Git 仓库
├── README.md                      # 仓库主 README
└── claude-knowledge/              # 技能目录
    ├── LICENSE                    # MIT 许可证
    ├── README.md                  # 技能说明
    ├── SKILL.md                   # 技能主文件
    ├── scripts/                   # Python 脚本
    │   ├── build_index.py        # 构建索引
    │   └── search_index.py       # 搜索索引
    ├── references/                # 参考文档目录
    └── assets/                    # 资源文件目录
```

## 推送到 GitHub 的步骤

### 方法 1: 使用 GitHub CLI (推荐)

```bash
# 1. 登录 GitHub（如果未登录）
gh auth login

# 2. 创建仓库并推送
cd ~/faizlee-open-skills
gh repo create faizlee-open-skills --public --source=. --remote=origin --push
```

### 方法 2: 手动创建 + Git 推送

**步骤 1: 在 GitHub 上创建仓库**

1. 访问 https://github.com/new
2. 仓库名称: `faizlee-open-skills`
3. 选择 **Public**
4. **不要**勾选 "Add a README file"（我们已经有了）
5. 点击 "Create repository"

**步骤 2: 推送到 GitHub**

```bash
cd ~/faizlee-open-skills

# 添加远程仓库
git remote add origin https://github.com/faizlee/faizlee-open-skills.git

# 推送到 main 分支
git branch -M main
git push -u origin main
```

### 方法 3: 使用 SSH (如果已配置 SSH 密钥)

```bash
cd ~/faizlee-open-skills

# 添加 SSH 远程仓库
git remote add origin git@github.com:faizlee/faizlee-open-skills.git

# 推送
git branch -M main
git push -u origin main
```

## 推送后的操作

### 1. 安装技能到本地

```bash
# 移除旧的 project-knowledge 技能（可选）
rm -rf ~/.claude/skills/project-knowledge

# 创建软链接到新技能
ln -s ~/faizlee-open-skills/claude-knowledge ~/.claude/skills/claude-knowledge

# 验证安装
ls -la ~/.claude/skills/ | grep claude-knowledge
```

### 2. 更新 VideoFly 项目

```bash
cd /e/work/project/faizleecom

# 更新 CLAUDE.md 中的技能名称引用
# 将 project-knowledge 改为 claude-knowledge

# 测试技能
# 在 Claude Code 中提问，验证技能是否正常触发
```

### 3. 验证 GitHub 仓库

访问 https://github.com/faizlee/faizlee-open-skills 查看：
- ✅ README.md 正确显示
- ✅ claude-knowledge/ 目录结构完整
- ✅ LICENSE 文件存在
- ✅ 所有文件已推送

## 发布技能

### 在 Claude Code 技能市场发布（如果可用）

1. 访问 Claude Code 技能市场
2. 提交技能审核
3. 等待批准

### 共享技能

将仓库链接分享给其他用户：
```
https://github.com/faizlee/faizlee-open-skills
```

用户可以通过以下命令安装：
```bash
git clone https://github.com/faizlee/faizlee-open-skills.git
ln -s $(pwd)/faizlee-open-skills/claude-knowledge ~/.claude/skills/claude-knowledge
```

## 维护指南

### 更新技能

```bash
cd ~/faizlee-open-skills/claude-knowledge

# 编辑技能文件
vim SKILL.md

# 提交更改
git add .
git commit -m "feat: update skill description"
git push origin main
```

### 发布新版本

```bash
# 更新版本号
vim SKILL.md  # 更新"技能版本"字段

# 创建 Git tag
git tag -a v1.1.0 -m "Release v1.1.0"

# 推送 tag
git push origin v1.1.0

# 更新 CHANGELOG.md
vim claude-knowledge/CHANGELOG.md
git add . && git commit -m "docs: update changelog" && git push
```

## 注意事项

1. **不要在公开仓库中包含敏感信息**
   - API keys
   - 密码
   - 个人数据
   - 项目特定的配置

2. **保持技能通用性**
   - 避免硬编码项目名称
   - 使用配置文件代替硬编码
   - 提供清晰的文档说明

3. **版本控制**
   - 使用语义化版本（Semantic Versioning）
   - 每次发布创建 Git tag
   - 维护 CHANGELOG.md

4. **许可证**
   - MIT License 允许自由使用、修改和分发
   - 保留版权声明
   - 不提供担保

## 故障排查

### 推送失败

```bash
# 检查远程仓库
git remote -v

# 如果需要，更新远程 URL
git remote set-url origin https://github.com/faizlee/faizlee-open-skills.git

# 强制推送（谨慎使用）
git push -f origin main
```

### 技能未生效

```bash
# 检查技能是否安装
ls -la ~/.claude/skills/ | grep claude-knowledge

# 检查 SKILL.md 语法
head -20 ~/.claude/skills/claude-knowledge/SKILL.md

# 重启 Claude Code
```

## 下一步

1. ✅ 推送到 GitHub
2. ✅ 安装到本地
3. ✅ 测试技能功能
4. ✅ 更新 VideoFly 项目
5. ✅ 编写使用文档
6. ✅ 分享给社区

---

**创建时间**: 2026-02-08
**维护者**: Faizlee
