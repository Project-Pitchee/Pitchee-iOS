import os
import glob

docs_dir = '/Users/dannyfeng/Documents/Pitchee/Docs/Voice-Training-Library'
files = glob.glob(f'{docs_dir}/**/*.md', recursive=True)

replacements = {
    '言语治疗师': '嗓音支持专家',
    '患者报告': '个人报告',
    '治疗动作': '探索动作',
    '嗓音治疗中用来治疗': '嗓音探索中用来缓解',
    '治疗和预防': '缓解和预防',
    '物理疗法': '物理实践',
    '真正的成功是': '真正的探索目标是',
    '睾酮治疗': '睾酮肯定性激素应用',
    '言语治疗科': '嗓音康复科',
    '正常的暂时性': '自然的暂时性',
    '必须把喉结提到嗓子眼': '一定要把喉结提到嗓子眼',
    '才算女性化': '才算达到预期目标',
    '成功把喉咙共鸣收紧': '有效把喉咙共鸣收紧',
    '正常生理状态下': '自然生理状态下',
    '正常松弛状态下': '自然松弛状态下',
    '正常的生理振动': '自然的生理振动',
    '正常的声门开闭': '自然的声门开闭',
    '正常的黏膜波动': '自然的黏膜波动',
    '言语治疗室': '嗓音支持室',
    '言语病理科': '嗓音病理科'
}

for filepath in files:
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    new_content = content
    for old, new in replacements.items():
        new_content = new_content.replace(old, new)
        
    if new_content != content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Updated {filepath}")

print("Done.")
