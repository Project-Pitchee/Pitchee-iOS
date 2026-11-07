#!/usr/bin/env python3
"""
normalize_articles.py
Normalizes all 49 Markdown articles in Documents/Articles and Pitchee/Docs/Voice-Training-Library
so that EVERY article uses the exact same four standardized section headings:
  ## 一、声学机制与算法原理  (SF Symbol: gearshape.2.fill)
  ## 二、症状自查与代偿排查  (SF Symbol: stethoscope)
  ## 三、训练动作与实操指南  (SF Symbol: figure.run)
  ## 四、权威文献与延伸参考  (SF Symbol: books.vertical.fill)
"""

import os
import glob
import re

STANDARDIZED_HEADINGS = [
    "## 一、声学机制与算法原理",
    "## 二、症状自查与代偿排查",
    "## 三、训练动作与实操指南",
    "## 四、权威文献与延伸参考"
]

def normalize_file(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.splitlines()
    filename = os.path.basename(filepath)

    h2_indices = [i for i, line in enumerate(lines) if line.startswith("## ")]
    num_h2 = len(h2_indices)

    new_lines = []

    if num_h2 == 4:
        # Direct replacement of the 4 headings
        h_idx = 0
        for i, line in enumerate(lines):
            if line.startswith("## "):
                new_lines.append(STANDARDIZED_HEADINGS[h_idx])
                h_idx += 1
            else:
                new_lines.append(line)

    elif num_h2 == 5 and "HEALTH-HYGIENE-01" in filename:
        # Merge sections 2 and 3 into Section 2
        for i, line in enumerate(lines):
            if i == h2_indices[0]:
                new_lines.append(STANDARDIZED_HEADINGS[0])
            elif i == h2_indices[1]:
                new_lines.append(STANDARDIZED_HEADINGS[1])
                new_lines.append("")
                new_lines.append("### 隐患自查一：谢菲尔德大学反流管理守则（Reflux Management Advice）")
            elif i == h2_indices[2]:
                new_lines.append("---")
                new_lines.append("")
                new_lines.append("### 隐患自查二：根除暴力清嗓与两大替代性排痰法（Alternatives to Throat Clearing）")
            elif i == h2_indices[3]:
                new_lines.append(STANDARDIZED_HEADINGS[2])
            elif i == h2_indices[4]:
                new_lines.append(STANDARDIZED_HEADINGS[3])
            else:
                new_lines.append(line)

    elif num_h2 == 3:
        # Carefully split Section 2 into Section 2 (Symptoms/Self-check) and Section 3 (Training/Action)
        sec1_idx = h2_indices[0]
        sec2_idx = h2_indices[1]
        sec3_idx = h2_indices[2]

        sec2_lines = lines[sec2_idx + 1: sec3_idx]

        # Determine split point in sec2_lines or insert structured headings
        # Let's inspect specific files
        split_pos = -1

        # Check for specific split markers based on file
        if "RULE-F0-UNAVAILABLE-02" in filename:
            # Lines before ### 从纯气流到纯净实声的三步过渡法 are self-check / onset types
            for idx, l in enumerate(sec2_lines):
                if "三步过渡法" in l or "### 练习" in l or "从纯气流" in l or "第一步" in l:
                    split_pos = idx
                    break
        elif "RULE-HIGH-F0-STYLIZED-03" in filename:
            for idx, l in enumerate(sec2_lines):
                if "渐进训练" in l or "第一步" in l or "练习 1" in l:
                    split_pos = idx
                    break
        elif "SCORE-ADVANCED-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "练习 1" in l or "三项“去技术化”练习" in l or "去技术化" in l:
                    split_pos = idx
                    break
        elif "SCORE-MASTER-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "无痛泛化" in l or "步骤 1" in l or "练习 1" in l:
                    split_pos = idx
                    break
        elif "SCORE-STARTER-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "三周计划" in l or "第一周" in l:
                    split_pos = idx
                    break
        elif "METRIC-DURATION-SHORT-01" in filename:
            # 练习 1 is sssss check, 练习 3 is airflow check, 练习 2 is silent breathing
            for idx, l in enumerate(sec2_lines):
                if "谢菲尔德无声呼吸法" in l or "练习 2" in l:
                    split_pos = idx
                    break
        elif "METRIC-NATURAL-LOW-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "探索动作" in l or "纠偏方向 B" in l:
                    # Let's find first action
                    if "探索动作" in l:
                        split_pos = idx
                        break
        elif "METRIC-PITCH-HIGH-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "第二步" in l or "向下半音阶回落" in l:
                    split_pos = idx
                    break
        elif "METRIC-PITCH-MONOTONE-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "练习 1" in l or "控制矩阵" in l:
                    split_pos = idx
                    break
        elif "METRIC-VFP-DARK-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "练习 1" in l:
                    split_pos = idx
                    break
        elif "METRIC-VFP-THIN-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "练习 1" in l:
                    split_pos = idx
                    break
        elif "METRIC-VOLUME-PROJECTION-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "训练 1" in l:
                    split_pos = idx
                    break
        elif "MASCULINE-BASICS-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "练习 1" in l:
                    split_pos = idx
                    break
        elif "MASCULINE-INTONATION-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "练习 1" in l:
                    split_pos = idx
                    break
        elif "MASCULINE-ON-T-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "铁律 2" in l or "每日吸管水泡理疗" in l:
                    split_pos = idx
                    break
        elif "MASCULINE-PRE-T-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "技巧 1" in l:
                    split_pos = idx
                    break
        elif "NONBINARY-EXPLORE-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "配方实验 1" in l:
                    split_pos = idx
                    break
        elif "PRACTICE-AB-DROP-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "评估准则" in l or "实操建议" in l or "1. **" in l or "第一步" in l:
                    split_pos = idx
                    break
        elif "PRACTICE-AB-SUBJECTIVE-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "健康发声决策树" in l or "实操" in l:
                    split_pos = idx
                    break
        elif "PRACTICE-AB-UNSURE-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "阶段 1" in l or "练习 1" in l:
                    split_pos = idx
                    break
        elif "QUALITY-CLIPPING-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "要领 1" in l:
                    split_pos = idx
                    break
        elif "QUALITY-ENVIRONMENT-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "步骤 1" in l:
                    split_pos = idx
                    break
        elif "HEALTH-REDLINE-01" in filename:
            for idx, l in enumerate(sec2_lines):
                if "急救 SOP" in l or "第一步" in l or "急救" in l:
                    split_pos = idx
                    break

        if split_pos == -1:
            # Fallback split around halfway of section 2
            split_pos = max(1, len(sec2_lines) // 2)

        # Build lines
        # Up to sec2_idx
        for i in range(sec1_idx):
            new_lines.append(lines[i])

        new_lines.append(STANDARDIZED_HEADINGS[0])

        for i in range(sec1_idx + 1, sec2_idx):
            new_lines.append(lines[i])

        new_lines.append(STANDARDIZED_HEADINGS[1])

        # First half of section 2
        for l in sec2_lines[:split_pos]:
            new_lines.append(l)

        new_lines.append("")
        new_lines.append("---")
        new_lines.append("")
        new_lines.append(STANDARDIZED_HEADINGS[2])

        # Second half of section 2
        for l in sec2_lines[split_pos:]:
            new_lines.append(l)

        # Section 4
        new_lines.append("")
        new_lines.append("---")
        new_lines.append("")
        new_lines.append(STANDARDIZED_HEADINGS[3])

        for i in range(sec3_idx + 1, len(lines)):
            new_lines.append(lines[i])

    # Clean up double blank lines around dividers
    normalized_content = "\n".join(new_lines) + "\n"
    # Ensure exactly standard headings
    h2_check = [l.strip() for l in normalized_content.splitlines() if l.startswith("## ")]
    assert h2_check == STANDARDIZED_HEADINGS, f"Error in {filename}: got {h2_check} instead of {STANDARDIZED_HEADINGS}"

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(normalized_content)

    return True

def main():
    target_dirs = [
        "/Users/dannyfeng/Documents/Articles",
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Docs", "Voice-Training-Library")
    ]

    for d in target_dirs:
        if not os.path.exists(d):
            continue
        files = sorted(glob.glob(os.path.join(d, "**", "*.md"), recursive=True))
        print(f"Normalizing {len(files)} files in {d}...")
        for f in files:
            normalize_file(f)
        print(f"✓ Successfully normalized all {len(files)} files in {d}!")

if __name__ == "__main__":
    main()
