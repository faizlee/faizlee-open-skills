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
from typing import Dict, List, Any, Any


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

        # 计算权重
        weight = self.calculate_weight(file_path, content, doc_type)

        # 评估文档质量
        quality, status, quality_factors = self.assess_document_quality(file_path, content)

        # 提取相关文档
        related = self.extract_related_documents(content)

        return {
            "file": str(file_path.relative_to(self.project_root)),
            "title": title,
            "keywords": keywords,
            "module": module,
            "type": doc_type,
            "related_documents": related,
            "quality": quality,
            "status": status,
            "quality_factors": quality_factors,
            "created_date": datetime.fromtimestamp(file_path.stat().st_ctime).isoformat(),
            "last_updated": datetime.fromtimestamp(file_path.stat().st_mtime).isoformat(),
            "reference_count": 0,
            "weight": weight
        }

    def extract_keywords(self, content: str, title: str) -> List[str]:
        """提取高质量中文关键词"""
        keywords = set()

        # 停用词列表 - 无意义的词
        stop_words = {
            # 数字
            '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
            # 英文字母和单词
            'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
            'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
            'C', 'Q3', 'DON', 'Auto', 'Magic', 'Link', 'H1', 'H2', 'H3', 'E2E',
            'API', 'UI', 'UX', 'CI', 'CD', 'OK', 'NG',
            # 常见疑问词
            '如何', '怎么', '什么', '哪些', '是否', '能否', '吗', '呢',
            # 常见连接词
            '的', '了', '和', '与', '或', '及', '等',
            # 无意义标记
            '选项', '步骤', '错误', '正确', '推荐', '建议', '注意', '说明', '概述',
            # 泛化词汇 (新增)
            '项目', '相关', '配置', '系统', '功能', '模块', '文件', '代码',
            '使用', '实现', '添加', '创建', '生成', '更新', '修改', '处理',
            '需要', '可以', '应该', '必须', '每个', '所有', '多个', '单个',
            '主要', '重要', '关键', '核心', '基本', '详细', '完整', '简单',
            '第一', '第二', '第三', '最后', '接下来', '然后', '之后',
            '数据', '内容', '信息', '结果', '问题', '方法', '方式', '形式',
            '音频', '音乐', '视频', '图片', '图像', '文本', '文字',
        }

        # 从标题提取 - 只保留中文词汇（2字以上）
        title_words = re.findall(r'[\u4e00-\u9fff]{2,}', title)
        keywords.update(title_words[:5])

        # 从 H2、H3 标题提取
        headings = re.findall(r'^#{2,3}\s+(.+)$', content, re.MULTILINE)
        for heading in headings:
            # 过滤掉疑问句（包含吗、呢等疑问词）
            if any(question_word in heading for question_word in ['吗', '呢', '如何', '怎么', '什么', '是否', '能否']):
                continue
            # 只保留中文词汇（2字以上）
            words = re.findall(r'[\u4e00-\u9fff]{2,}', heading)
            keywords.update(words[:5])

        # 过滤停用词
        keywords = keywords - stop_words

        # 过滤包含动词的关键词（检查是否包含常见动词）
        verb_patterns = [
            r'.*需要$',
            r'.*使用$',
            r'.*实现$',
            r'.*添加$',
            r'.*创建$',
            r'.*生成$',
            r'.*更新$',
            r'.*修改$',
            r'.*处理$',
            r'.*配置$',
            r'每个.*$',
            r'.*中都$',
            r'^.*中使用$',
            r'^.*相关$',
        ]
        keywords = {kw for kw in keywords if not any(re.match(pattern, kw) for pattern in verb_patterns)}

        # 转换为列表并排序（按长度降序，优先保留长关键词）
        result = sorted(keywords, key=len, reverse=True)

        return result[:8]  # 返回前 8 个高质量关键词

    def detect_module(self, file_path: Path, content: str) -> str:
        """检测文档所属模块（增强版 v2）"""
        path_str = str(file_path).lower()

        # 保持现有分类
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

        # 新增细分分类
        elif any(keyword in path_str for keyword in ['database', 'db', 'sql', 'migration', 'schema']):
            return "database"
        elif any(keyword in path_str for keyword in ['api', 'route', 'endpoint', 'rest']):
            return "api"
        elif any(keyword in path_str for keyword in ['deploy', 'deployment', 'production', 'vercel']):
            return "deployment"
        elif any(keyword in path_str for keyword in ['performance', 'optimization', 'optimize']):
            return "performance"
        elif any(keyword in path_str for keyword in ['troubleshoot', 'error', 'fix', 'debug', 'diagnosis']):
            return "troubleshooting"
        elif any(keyword in path_str for keyword in ['env', 'environment', 'config', 'setup']):
            return "environment"
        elif any(keyword in path_str for keyword in ['git', 'hook', 'commit']):
            return "git"

        # 新增更多细分分类
        elif any(keyword in path_str for keyword in ['report', 'summary', 'summary-', '-summary']):
            # 进一步细分报告类型
            if 'phase' in path_str or 'progress' in path_str:
                return "progress-report"
            elif 'test' in path_str:
                return "testing"
            else:
                return "general"
        elif any(keyword in path_str for keyword in ['doc', 'docs', 'index', 'readme', 'guide']):
            # 文档相关
            if 'knowledge' in path_str or 'index' in path_str:
                return "documentation"
            else:
                return "general"
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

    def calculate_weight(self, file_path: Path, content: str, doc_type: str) -> int:
        """计算文档权重"""
        weight = 50  # 基础权重

        # 根据文档类型调整
        type_weights = {
            'implementation': 20,  # 实现文档很重要
            'guide': 15,
            'design': 10,
            'refactor': 10,
            'test': 5,
            'bug': 5,
            'report': 0,
            'general': 0,
        }
        weight += type_weights.get(doc_type, 0)

        # 根据文件名判断重要性
        name = file_path.name.lower()

        # 核心实现文档（包含 implementation, summary, complete）
        if any(keyword in name for keyword in ['implementation', 'summary', 'complete', 'final']):
            weight += 15

        # 快速参考文档（quick, quick-ref, guide）
        if any(keyword in name for keyword in ['quick', 'guide', 'ref', 'tutorial']):
            weight += 10

        # 官方文档（README, CLAUDE, 官方指南）
        if any(keyword in name for keyword in ['readme', 'claude', 'official']):
            weight += 10

        # 测试和报告通常权重较低
        if 'test' in name and 'report' in name:
            weight -= 5

        # 检查文档完整性
        if self.is_document_complete(content, file_path):
            weight += 10

        # 检查文档是否最近更新（30天内）
        file_age_days = (datetime.now() - datetime.fromtimestamp(file_path.stat().st_mtime)).days
        if file_age_days < 30:
            weight += 5
        elif file_age_days > 180:
            weight -= 10

        # 检查文档长度（太短可能不完整）
        content_length = len(content)
        if content_length < 500:
            weight -= 10
        elif content_length > 5000:
            weight += 5

        return max(20, min(weight, 100))  # 限制在 20-100 之间

    def is_document_complete(self, content: str, file_path: Path) -> bool:
        """检查文档是否完整"""
        # 检查是否包含必要的章节
        required_sections = ['#', '##']
        return all(section in content for section in required_sections)

    def assess_document_quality(self, file_path: Path, content: str) -> tuple:
        """评估文档质量和状态"""

        # 质量评分
        quality_score = 0
        quality_factors = []

        # 检查文档结构
        if content.count('##') >= 3:  # 至少3个小节
            quality_score += 20
            quality_factors.append("结构完整")

        if '```' in content:  # 包含代码示例
            quality_score += 20
            quality_factors.append("有代码示例")

        if content.count('![') >= 1 or content.count('- [x]') >= 1:  # 有图片或任务列表
            quality_score += 15
            quality_factors.append("有任务清单")

        if len(content) > 2000:  # 内容充实
            quality_score += 20
            quality_factors.append("内容充实")

        if any(keyword in content for keyword in ['## 概述', '## 总结', '## 结论']):
            quality_score += 15
            quality_factors.append("有总结概述")

        if any(keyword in content for keyword in ['## 参考资料', '## 相关文档', '## 参考资源']):
            quality_score += 10
            quality_factors.append("有参考资料")

        # 质量等级
        if quality_score >= 80:
            quality = "high"
        elif quality_score >= 50:
            quality = "medium"
        else:
            quality = "low"

        # 时效性检查
        file_age_days = (datetime.now() - datetime.fromtimestamp(file_path.stat().st_mtime)).days
        if file_age_days > 365:
            status = "deprecated"  # 超过1年
        elif file_age_days > 180:
            status = "needs_review"  # 超过6个月
        else:
            status = "active"

        return quality, status, quality_factors

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
                    f.write(f"- **关键词**: {', '.join(doc['keywords'][:8])}\n")
                    f.write(f"- **类型**: {doc['type']}\n")
                    f.write(f"- **模块**: {doc['module']}\n")
                    f.write(f"- **权重**: {doc['weight']}\n")
                    f.write(f"- **质量**: {doc['quality']}\n")
                    f.write(f"- **状态**: {doc['status']}\n")
                    f.write(f"- **最后引用**: {doc['last_updated']}\n")

                    if doc.get('quality_factors'):
                        f.write(f"- **质量因素**: {', '.join(doc['quality_factors'])}\n")

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
