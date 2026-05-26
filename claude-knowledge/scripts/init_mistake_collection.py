#!/usr/bin/env python3
"""
初始化错题集系统

自动将错题集模板复制到项目文档目录，并更新索引
"""

import shutil
import subprocess
from pathlib import Path


def init_mistake_collection(project_root: Path = None):
    """初始化错题集系统"""

    if project_root is None:
        project_root = Path.cwd()

    # 检测项目根目录
    while project_root != project_root.parent:
        if (project_root / ".git").exists() or (project_root / "package.json").exists():
            break
        project_root = project_root.parent

    print(f"🔍 检测到项目根目录: {project_root}")

    # 1. 创建目录
    knowledge_dir = project_root / "docs" / "knowledge"
    knowledge_dir.mkdir(parents=True, exist_ok=True)
    print(f"✅ 创建目录: {knowledge_dir}")

    # 2. 查找模板
    script_dir = Path(__file__).parent
    template = script_dir.parent / "templates" / "DEVELOPMENT_MISTAKES_LOG.md"
    target = knowledge_dir / "DEVELOPMENT_MISTAKES_LOG.md"

    if not template.exists():
        print(f"❌ 模板文件不存在: {template}")
        print(f"   请确认 claude-knowledge skill 安装正确")
        return False

    # 3. 复制模板
    if target.exists():
        response = input(f"⚠️  错题集已存在: {target}\n   是否覆盖? (y/N): ")
        if response.lower() != 'y':
            print("ℹ️  跳过，保留现有错题集")
            return True
        else:
            backup = target.with_suffix('.md.backup')
            shutil.copy(target, backup)
            print(f"💾 已备份现有错题集: {backup}")

    shutil.copy(template, target)
    print(f"✅ 错题集模板已创建: {target}")

    # 4. 更新索引
    print("\n📊 更新知识索引...")
    try:
        build_script = script_dir / "build_index.py"
        subprocess.run(
            ["python", str(build_script),
             "--project-root", str(project_root),
             "--docs-dir", "docs"],
            cwd=script_dir,
            check=True
        )
        print("✅ 索引更新完成")
    except subprocess.CalledProcessError as e:
        print(f"⚠️  索引更新失败: {e}")
        print(f"   请手动运行: python {build_script}")
        return False

    # 5. 完成
    print("\n" + "="*60)
    print("🎉 错题集系统初始化完成！")
    print("="*60)
    print(f"\n📝 错题集位置: {target}")
    print(f"💡 下一步:")
    print(f"   1. 编辑错题集，填写实际问题")
    print(f"   2. 参考维护指南: {script_dir.parent / 'references' / 'mistake-collection-guide.md'}")
    print(f"   3. 查看示例数据: {script_dir.parent / 'templates' / 'problem-log.example.json'}")

    return True


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1:
        project_root = Path(sys.argv[1])
    else:
        project_root = None

    success = init_mistake_collection(project_root)
    sys.exit(0 if success else 1)
