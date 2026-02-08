#!/usr/bin/env python3
"""
项目知识索引 - 构建索引脚本

扫描 docs/ 目录下的所有文档，提取关键词和元数据，
生成结构化索引 (INDEX.md) 和问题记录 (problem-log.json)
"""

import os
import re
import json
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any


class IndexBuilder:
    def __init__(self, project_root: str = ".", docs_dir: str = "docs"):
        self.project_root = Path(project_root).resolve()
        self.docs_dir = self.project_root / docs_dir
        self.index_dir = self.docs_dir / "knowledge-index"
        self.documents = []
        self.problems = []

    def detect_project_root(self) -> Path:
        """检测项目根目录"""
        current = Path.cwd()
        while current != current.parent:
            if (current / ".git").exists() or (current / "package.json").exists():
                return current
            current = current.parent
        return Path.cwd()

    def scan_documents(self) -> List[Path]:
        """扫描所有 Markdown 文档"""
        print(f"[Search] Scanning documents directory: {self.docs_dir}")
        md_files = list(self.docs_dir.glob("**/*.md"))
        print(f"[OK] Found {len(md_files)} documents")
        return md_files

    def extract_metadata(self, file_path: Path) -> Dict[str, Any]:
        """从文档中提取元数据"""

        # 读取文档内容
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # 提取标题（第一个 # 标题）
        title_match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
        title = title_match.group(1) if title_match else file_path.stem

        # 提取关键词（从标题和内容中）
        keywords = self.extract_keywords(content, title)

        # 检测模块（基于文件路径和内容）
        module = self.detect_module(file_path, content)

        # 检测类型（基于文件名）
        doc_type = self.detect_type(file_path)

        # 提取相关文档
        related = self.extract_related_documents(content)

        return {
            "file": str(file_path.relative_to(self.project_root)),
            "title": title,
            "keywords": keywords,
            "module": module,
            "type": doc_type,
            "related_documents": related,
            "quality": "medium",  # 默认质量
            "status": "active",
            "created_date": datetime.fromtimestamp(file_path.stat().st_ctime).isoformat(),
            "last_updated": datetime.fromtimestamp(file_path.stat().st_mtime).isoformat(),
            "reference_count": 0,
            "weight": 50
        }

    def extract_keywords(self, content: str, title: str) -> List[str]:
        """提取关键词"""
        keywords = set()

        # 从标题提取
        title_words = re.findall(r'[\w\u4e00-\u9fff]+', title)
        keywords.update(title_words[:5])

        # 从 H2、H3 标题提取
        headings = re.findall(r'^#{2,3}\s+(.+)$', content, re.MULTILINE)
        for heading in headings:
            words = re.findall(r'[\w\u4e00-\u9fff]+', heading)
            keywords.update(words[:3])

        # 从文件内容提取高频词（简化版）
        # TODO: 可以使用更复杂的 NLP 算法

        return list(keywords)[:10]

    def detect_module(self, file_path: Path, content: str) -> str:
        """检测文档所属模块"""
        path_str = str(file_path).lower()

        # 基于文件路径判断
        if "xiaohongshu" in path_str or "cover" in path_str:
            return "xiaohongshu-cover"
        elif "video" in path_str or "generator" in path_str:
            return "video-generator"
        elif "auth" in path_str:
            return "auth"
        elif "test" in path_str:
            return "testing"
        elif "refactor" in path_str:
            return "refactor"
        elif "thumbnail" in path_str:
            return "thumbnail"
        elif "progress" in path_str:
            return "progress-display"
        else:
            return "general"

    def detect_type(self, file_path: Path) -> str:
        """检测文档类型"""
        name = file_path.name.lower()

        if "bug" in name or "fix" in name or "error" in name:
            return "bug"
        elif "test" in name:
            return "test"
        elif "refactor" in name:
            return "refactor"
        elif "guide" in name or "tutorial" in name:
            return "guide"
        elif "report" in name:
            return "report"
        elif "implementation" in name:
            return "implementation"
        elif "design" in name:
            return "design"
        else:
            return "general"

    def extract_related_documents(self, content: str) -> List[str]:
        """提取相关文档"""
        related = []

        # 查找 Markdown 链接
        links = re.findall(r'\[([^\]]+)\]\(([^)]+\.md)\)', content)
        for text, url in links:
            # 清理 URL（去除 ../ 等）
            clean_url = url.lstrip('../')
            related.append(clean_url)

        return list(set(related))[:5]

    def build_index(self):
        """构建索引"""
        print("\n[Build] Starting to build index...")

        # 扫描文档
        md_files = self.scan_documents()

        # 提取元数据
        print("\n[Metadata] Extracting document metadata...")
        for md_file in md_files:
            try:
                metadata = self.extract_metadata(md_file)
                self.documents.append(metadata)
                print(f"  [OK] {metadata['file']}")
            except Exception as e:
                print(f"  [FAIL] {md_file}: {e}")

        # 按模块分类
        print("\n[Classify] Classifying by modules...")
        modules = {}
        for doc in self.documents:
            module = doc['module']
            if module not in modules:
                modules[module] = []
            modules[module].append(doc)

        # 生成 INDEX.md
        print("\n[Write] Generating INDEX.md...")
        self.generate_index_md(modules)

        # 生成 problem-log.json
        print("\n[Write] Generating problem-log.json...")
        self.generate_problem_log()

        print("\n[OK] Index build completed!")
        print(f"   - Total documents: {len(self.documents)}")
        print(f"   - Module count: {len(modules)}")
        print(f"   - Index location: {self.index_dir}")

    def generate_index_md(self, modules: Dict[str, List[Dict]]):
        """生成 INDEX.md"""
        self.index_dir.mkdir(parents=True, exist_ok=True)
        index_file = self.index_dir / "INDEX.md"

        with open(index_file, 'w', encoding='utf-8') as f:
            f.write("# 项目知识索引\n\n")
            f.write(f"> 最后更新: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"> 总文档数: {len(self.documents)}\n")
            f.write(f"> 模块数量: {len(modules)}\n\n")
            f.write("---\n\n")

            # 按模块生成索引
            for module_name, docs in sorted(modules.items()):
                f.write(f"## {module_name}\n\n")

                for doc in sorted(docs, key=lambda x: x['weight'], reverse=True):
                    f.write(f"### {doc['title']}\n\n")
                    f.write(f"- **文件**: `{doc['file']}`\n")
                    f.write(f"- **关键词**: {', '.join(doc['keywords'][:10])}\n")
                    f.write(f"- **类型**: {doc['type']}\n")
                    f.write(f"- **模块**: {doc['module']}\n")
                    f.write(f"- **权重**: {doc['weight']}\n")
                    f.write(f"- **最后引用**: {doc['last_updated']}\n")

                    if doc['related_documents']:
                        f.write(f"- **相关文档**: {', '.join(doc['related_documents'][:5])}\n")

                    f.write("\n")

        print(f"[OK] Index saved to: {index_file}")

    def generate_problem_log(self):
        """生成 problem-log.json"""
        problem_file = self.index_dir / "problem-log.json"

        data = {
            "version": "1.0",
            "last_updated": datetime.now().isoformat(),
            "problems": [],  # 初始为空，随着使用逐渐填充
            "frequent_problems": []
        }

        with open(problem_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        print(f"[OK] Problem log saved to: {problem_file}")


def main():
    import argparse

    parser = argparse.ArgumentParser(description="构建项目知识索引")
    parser.add_argument("--project-root", default=".", help="项目根目录")
    parser.add_argument("--docs-dir", default="docs", help="文档目录")
    parser.add_argument("--auto-classify", action="store_true", help="自动分类模块")
    parser.add_argument("--extract-keywords", action="store_true", help="自动提取关键词")

    args = parser.parse_args()

    builder = IndexBuilder(args.project_root, args.docs_dir)
    builder.build_index()


if __name__ == "__main__":
    main()
