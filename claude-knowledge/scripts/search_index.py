#!/usr/bin/env python3
"""
项目知识索引 - 搜索脚本

在索引中搜索相关文档和解决方案
"""

import json
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple
from datetime import datetime


class IndexSearcher:
    def __init__(self, project_root: str = "."):
        self.project_root = Path(project_root).resolve()
        self.index_dir = self.project_root / "docs" / "knowledge-index"
        self.index_file = self.index_dir / "INDEX.md"
        self.problem_log = self.index_dir / "problem-log.json"

    def search(self, query: str, context: Dict = None) -> Dict[str, Any]:
        """执行搜索（复合模式）"""

        print(f"🔍 搜索查询: {query}")

        results = {
            "query": query,
            "found": False,
            "results": [],
            "warnings": []
        }

        # 模式 1: 问题记录匹配
        problem_results = self.search_problem_log(query)
        if problem_results:
            results["results"].extend(problem_results)
            print(f"  ✓ 问题记录匹配: {len(problem_results)} 个")

        # 模式 2: 关键词搜索
        keywords = self.extract_keywords(query)
        keyword_results = self.search_by_keywords(keywords)
        if keyword_results:
            results["results"].extend(keyword_results)
            print(f"  ✓ 关键词匹配: {len(keyword_results)} 个")

        # 模式 3: 模块分类搜索
        module = self.detect_module(query)
        if module:
            module_results = self.search_by_module(module)
            if module_results:
                results["results"].extend(module_results)
                print(f"  ✓ 模块匹配: {len(module_results)} 个")

        # 模式 4: 类型搜索
        doc_type = self.detect_type(query)
        if doc_type:
            type_results = self.search_by_type(doc_type)
            if type_results:
                results["results"].extend(type_results)
                print(f"  ✓ 类型匹配: {len(type_results)} 个")

        # 去重
        results["results"] = self.deduplicate(results["results"])

        # 排序
        results["results"] = self.rank_results(results["results"], query)

        # 检查质量
        for result in results["results"]:
            warnings = self.check_quality(result)
            if warnings:
                result["warnings"] = warnings
                results["warnings"].extend(warnings)

        results["found"] = len(results["results"]) > 0

        return results

    def search_problem_log(self, query: str) -> List[Dict]:
        """模式 1: 问题记录匹配"""
        if not self.problem_log.exists():
            return []

        with open(self.problem_log, 'r', encoding='utf-8') as f:
            data = json.load(f)

        results = []
        query_lower = query.lower()

        for problem in data.get("problems", []):
            # 完全匹配
            if query_lower in problem["question"].lower():
                for solution in problem["solutions"]:
                    results.append({
                        "type": "exact_match",
                        "problem": problem["question"],
                        "occurrence_count": problem["occurrence_count"],
                        "document": solution["document"],
                        "section": solution.get("section", ""),
                        "confidence": solution.get("confidence", "medium"),
                        "source": "problem-log"
                    })

        return results

    def search_by_keywords(self, keywords: List[str]) -> List[Dict]:
        """模式 2: 关键词搜索"""
        if not self.index_file.exists():
            return []

        results = []
        content = self.index_file.read_text(encoding='utf-8')

        # 解析 INDEX.md（简化版）
        # 实际应该使用更复杂的解析器

        current_doc = None
        for line in content.split('\n'):
            # 检测文档标题
            if line.startswith('### '):
                if current_doc and any(kw in current_doc.get('keywords', '').lower() for kw in keywords):
                    results.append(current_doc)
                current_doc = None

            # 提取元数据
            elif line.startswith('- **文件**:'):
                current_doc = {"file": line.split('`')[1]}
            elif line.startswith('- **关键词**:') and current_doc:
                current_doc["keywords"] = line.split(': ')[1]
            elif line.startswith('- **权重**:') and current_doc:
                current_doc["weight"] = int(line.split(': ')[1])
            elif line.startswith('- **类型**:') and current_doc:
                current_doc["type"] = line.split(': ')[1]
                current_doc["source"] = "index"

        # 最后一个文档
        if current_doc and any(kw in current_doc.get('keywords', '').lower() for kw in keywords):
            results.append(current_doc)

        return results

    def search_by_module(self, module: str) -> List[Dict]:
        """模式 3: 模块分类搜索"""
        if not self.index_file.exists():
            return []

        # 在 INDEX.md 中查找对应模块的部分
        # 简化实现，实际应该更精确

        return []

    def search_by_type(self, doc_type: str) -> List[Dict]:
        """模式 4: 类型搜索"""
        if not self.index_file.exists():
            return []

        # 在 INDEX.md 中查找对应类型的文档
        # 简化实现

        return []

    def extract_keywords(self, query: str) -> List[str]:
        """提取关键词"""
        # 简化版关键词提取
        keywords = re.findall(r'[\w\u4e00-\u9fff]+', query)
        return keywords[:10]

    def detect_module(self, query: str) -> str:
        """检测模块"""
        query_lower = query.lower()

        if "小红书" in query_lower or "封面" in query_lower:
            return "xiaohongshu-cover"
        elif "视频" in query_lower:
            return "video-generator"
        elif "认证" in query_lower or "auth" in query_lower:
            return "auth"
        elif "测试" in query_lower:
            return "testing"
        else:
            return ""

    def detect_type(self, query: str) -> str:
        """检测类型"""
        query_lower = query.lower()

        if "bug" in query_lower or "错误" in query_lower or "失败" in query_lower:
            return "bug"
        elif "如何" in query_lower or "怎么" in query_lower:
            return "guide"
        elif "测试" in query_lower:
            return "test"
        else:
            return ""

    def deduplicate(self, results: List[Dict]) -> List[Dict]:
        """去重"""
        seen = set()
        unique = []

        for result in results:
            # 使用文件名作为唯一标识
            key = result.get("file", result.get("document", ""))
            if key and key not in seen:
                seen.add(key)
                unique.append(result)

        return unique

    def rank_results(self, results: List[Dict], query: str) -> List[Dict]:
        """排序结果"""
        def calculate_score(result):
            score = 0

            # 问题记录匹配优先
            if result.get("type") == "exact_match":
                score += 50

            # 权重
            weight = result.get("weight", 50)
            score += weight * 0.3

            # 关键词匹配度
            keywords = self.extract_keywords(query)
            doc_keywords = result.get("keywords", "")
            matches = sum(1 for kw in keywords if kw.lower() in doc_keywords.lower())
            score += matches * 10

            return score

        return sorted(results, key=calculate_score, reverse=True)

    def check_quality(self, result: Dict) -> List[str]:
        """检查文档质量"""
        warnings = []

        # 时间检查
        if "last_updated" in result:
            last_updated = datetime.fromisoformat(result["last_updated"])
            age_days = (datetime.now() - last_updated).days

            if age_days > 365:
                warnings.append("⚠️ 文档超过1年未更新，可能已过时")
            elif age_days > 180:
                warnings.append("⚠️ 文档超过6个月未更新，请验证")

        # 质量标记
        if result.get("quality") == "low":
            warnings.append("⚠️ 文档质量标记为 low，谨慎使用")

        return warnings


def main():
    import argparse

    parser = argparse.ArgumentParser(description="搜索项目知识索引")
    parser.add_argument("query", help="搜索查询")
    parser.add_argument("--project-root", default=".", help="项目根目录")

    args = parser.parse_args()

    searcher = IndexSearcher(args.project_root)
    results = searcher.search(args.query)

    # 输出结果
    print("\n" + "="*60)
    if results["found"]:
        print(f"✅ 找到 {len(results['results'])} 个结果:\n")

        for i, result in enumerate(results["results"][:10], 1):
            print(f"{i}. {result.get('document', result.get('file', 'Unknown'))}")

            if result.get("type") == "exact_match":
                print(f"   📍 问题: {result.get('problem', '')}")
                print(f"   📍 出现次数: {result.get('occurrence_count', 0)}")

            if "warnings" in result:
                for warning in result["warnings"]:
                    print(f"   {warning}")

            print()
    else:
        print("❌ 未找到相关文档")
        print("💡 建议:")
        print("  1. 尝试其他关键词")
        print("  2. 运行 build_index.py 重建索引")
        print("  3. 检查文档是否存在")


if __name__ == "__main__":
    main()
