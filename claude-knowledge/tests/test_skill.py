"""
Claude Knowledge Skill - Basic Test Suite

Tests the core functionality of the claude-knowledge skill.
"""

import json
import os
import sys
from pathlib import Path
from typing import Dict, List


def test_skill_file_exists():
    """Test if SKILL.md exists and has valid frontmatter."""
    # Get parent directory (claude-knowledge/)
    skill_path = Path(__file__).parent.parent / "SKILL.md"

    assert skill_path.exists(), "SKILL.md not found"

    content = skill_path.read_text(encoding="utf-8")

    # Check frontmatter
    assert content.startswith("---"), "Missing frontmatter start"
    assert "name: claude-knowledge" in content, "Missing skill name"
    assert "description:" in content, "Missing description"

    # Extract description
    desc_start = content.find("description: |") + len("description: |")
    desc_end = content.find("---", desc_start)
    description = content[desc_start:desc_end].strip()

    # For bilingual descriptions, allow up to 1000 chars
    assert len(description) < 1000, f"Description too long: {len(description)} chars (bilingual allows up to 1000)"

    print("✓ SKILL.md exists with valid frontmatter")


def test_references_exist():
    """Test if reference documents exist."""
    refs_dir = Path(__file__).parent.parent / "references"

    assert refs_dir.exists(), "references/ directory not found"

    required_files = [
        "search-patterns.md",
        "matching-algorithm.md",
        "examples.md"
    ]

    for ref_file in required_files:
        ref_path = refs_dir / ref_file
        assert ref_path.exists(), f"Reference file {ref_file} not found"
        print(f"✓ Reference file exists: {ref_file}")


def test_scripts_exist():
    """Test if Python scripts exist."""
    scripts_dir = Path(__file__).parent.parent / "scripts"

    assert scripts_dir.exists(), "scripts/ directory not found"

    required_scripts = [
        "build_index.py",
        "search_index.py"
    ]

    for script in required_scripts:
        script_path = scripts_dir / script
        assert script_path.exists(), f"Script {script} not found"
        print(f"✓ Script exists: {script}")


def test_skill_length():
    """Test if SKILL.md is within recommended length (< 500 lines)."""
    skill_path = Path(__file__).parent.parent / "SKILL.md"
    content = skill_path.read_text(encoding="utf-8")
    lines = content.split("\n")

    line_count = len(lines)
    assert line_count < 500, f"SKILL.md too long: {line_count} lines (recommended < 500)"

    print(f"✓ SKILL.md length OK: {line_count} lines")


def test_no_readme_in_skill():
    """Test that README.md doesn't exist in skill package (per official guidelines)."""
    readme_path = Path(__file__).parent.parent / "README.md"

    assert not readme_path.exists(), "README.md should not exist in skill package"

    print("✓ No README.md in skill package (complies with official guidelines)")


def test_description_quality():
    """Test if description follows best practices."""
    skill_path = Path(__file__).parent.parent / "SKILL.md"
    content = skill_path.read_text(encoding="utf-8")

    # Extract description
    desc_start = content.find("description: |") + len("description: |")
    desc_end = content.find("---", desc_start)
    description = content[desc_start:desc_end].strip()

    # Check for key elements
    checks = {
        "has_triggers": "Triggers" in description or "触发" in description,
        "has_prerequisite": "Prerequisite" in description or "前置条件" in description,
        "has_workflow": "Workflow" in description or "工作流程" in description,
        "has_features": "Features" in description or "功能" in description,
        "is_bilingual": description.count("触发") > 0 or description.count("Triggers") > 0,  # Bilingual support
        "no_project_specific": "VideoFly" not in description  # No project-specific terms
    }

    for check, passed in checks.items():
        assert passed, f"Description check failed: {check}"

    print("✓ Description quality checks passed")


def test_references_linked():
    """Test if SKILL.md links to reference documents."""
    skill_path = Path(__file__).parent.parent / "SKILL.md"
    content = skill_path.read_text(encoding="utf-8")

    required_links = [
        "references/search-patterns.md",
        "references/matching-algorithm.md",
        "references/examples.md"
    ]

    for link in required_links:
        assert link in content, f"Missing link to {link}"

    print("✓ Reference documents are linked in SKILL.md")


def run_all_tests():
    """Run all tests."""
    tests = [
        test_skill_file_exists,
        test_references_exist,
        test_scripts_exist,
        test_skill_length,
        test_no_readme_in_skill,
        test_description_quality,
        test_references_linked
    ]

    print("Running Claude Knowledge Skill tests...\n")

    passed = 0
    failed = 0

    for test in tests:
        try:
            test()
            passed += 1
        except AssertionError as e:
            print(f"✗ {test.__name__}: {e}")
            failed += 1
        except Exception as e:
            print(f"✗ {test.__name__}: Unexpected error: {e}")
            failed += 1

    print(f"\n{'='*50}")
    print(f"Tests passed: {passed}/{len(tests)}")
    print(f"Tests failed: {failed}/{len(tests)}")
    print(f"{'='*50}")

    return failed == 0


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
