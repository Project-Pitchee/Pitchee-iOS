#!/usr/bin/env python3
"""Reproducible synthetic utility simulation, NEVER production DP noise."""

import argparse
import csv
from dataclasses import replace
import hashlib
import json
from pathlib import Path
import platform
import random
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from Research.score_study_protocol import DIMENSIONS, SCALE, DraftStudy, noise_envelope, postprocess


def synthetic_sum(paired, invited, negative, alternative):
    # One invitation per synthetic installation. Null: delta +/-1, equally
    # likely. Alternative: delta -1/0, equally likely (population mean -0.5).
    total_delta = -negative if alternative else paired - 2 * negative
    sum_squared_delta = negative if alternative else paired
    return tuple(value / SCALE for value in (
        invited, paired, invited - paired, 0, 0, 0, 0, 0, 0,
        paired, paired, total_delta / 4, sum_squared_delta / 16,
        *([0] * 13),
    ))


def simulate(study, trials, seed):
    rows = []
    for releases in sorted({1, study.privacy.max_releases}):
        plan = replace(study.privacy, max_releases=releases)
        for paired in (100, 500, 1000, 5000, 10000, 20000):
            for alternative in (False, True):
                rng = random.Random(f"{seed}:{releases}:{paired}:{alternative}")
                shown = signals = covered = 0
                widths = []
                truth = -0.5 if alternative else 0.0
                for _ in range(trials):
                    negative = rng.getrandbits(paired).bit_count()
                    aggregate = synthetic_sum(paired, 2 * paired, negative, alternative)
                    # Seeded PRNG and ordinary floats: suitable ONLY for this
                    # simulation. Not a secure/finite-precision DP sampler.
                    noisy = tuple(value + rng.gauss(0, plan.sigma) for value in aggregate)
                    result = postprocess(noisy, plan, study.analysis)["feminine"]
                    if result.get("comparison_status") != "estimated":
                        continue
                    shown += 1
                    signals += result["alignment_signal"]
                    lo, hi = result["iid_participant_mean_interval"]
                    covered += lo <= truth <= hi
                    widths.append(hi - lo)
                rows.append({
                    "releases": releases, "invited_installations": 2 * paired,
                    "paired_installations": paired, "true_mean_delta": truth,
                    "trials": trials, "comparison_shown_fraction": shown / trials,
                    "alignment_signal_fraction_all_trials": signals / trials,
                    "coverage_fraction_when_shown": covered / shown if shown else None,
                    "mean_interval_width_when_shown": sum(widths) / shown if shown else None,
                })
    return rows


def write_reports(study, rows, manifest, prefix, trials, seed):
    prefix.parent.mkdir(parents=True, exist_ok=True)
    with prefix.with_suffix(".csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    assumptions = {
        "synthetic_only": True, "seed": seed, "trials_per_scenario": trials,
        "manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
        "protocol_sha256": hashlib.sha256((ROOT / "Research/score_study_protocol.py").read_bytes()).hexdigest(),
        "simulator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "python_version": platform.python_version(),
        "dimensions": DIMENSIONS, "normalization_scale": SCALE,
        "rho_total": study.privacy.total_rho,
        "sigma_normalized_weekly": study.privacy.sigma,
        "sigma_count_units_weekly": study.privacy.sigma * SCALE,
        "simultaneous_count_error_weekly": noise_envelope(study.privacy, study.analysis) * SCALE,
        "readiness": study.readiness,
    }
    prefix.with_suffix(".json").write_text(json.dumps(assumptions, indent=2) + "\n")
    lines = [
        "# 评分研究：合成数据效用报告", "",
        "本文件由 `Scripts/evaluate-score-study.py` 生成；没有读取用户录音、App 状态或真实统计。",
        "结果描述草案机制的效用，不是模型效果证据、生产差分隐私实现或上线许可。", "",
        f"每场景 {trials} 次模拟，固定种子 {seed}。每个合成安装只收到一次邀请；一半具有有效配对，另一半选择无法判断。",
        "零假设的安装差值为等概率 -1/+1；备择为等概率 -1/0（真实均值 -0.5 个等级）。男性向为空，但仍占固定向量和全族校正。",
        f"预算按整个试点 ε ≤ {study.privacy.epsilon_cap:g}、δ = {study.privacy.delta:g}；对比仅发布一次与最多发布 {study.privacy.max_releases} 次。没有使用抽样放大。", "",
        f"26 维向量统一除以 √12，L2 ≤ 1。{study.privacy.max_releases} 次方案每次归一化噪声标准差 {study.privacy.sigma:.3f}，换算计数单位为 {study.privacy.sigma * SCALE:.3f}。",
        f"覆盖全部 {study.privacy.max_releases} 次发布与 26 个坐标的 {1-study.analysis.noise_family_alpha:.1%} 联合噪声包络约为 ±{noise_envelope(study.privacy, study.analysis) * SCALE:.2f} 个计数单位。",
        "只有加噪计数的下界达到 100 才显示对应比较。该门槛是概率性统计规则，不能替代密码协议的参与门槛。", "",
        "区间同时考虑高斯噪声、带噪分母和有界安装均值的 Hoeffding 抽样误差，并按两方向及全部计划发布作保守校正。",
        "抽样区间要求当批安装独立且来自所讨论的参与群体；自愿参加不保证代表全部用户。",
        "“信号”要求区间上界低于 -0.25 等级；统计信号只说明目标符合度假设，不直接批准替换评分。", "",
        "| 发布次数 | 有效配对安装 | 真实均值 | 比较显示率 | 信号率（全部模拟） | 已显示区间平均宽度 |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        width = row["mean_interval_width_when_shown"]
        lines.append(f"| {row['releases']} | {row['paired_installations']} | {row['true_mean_delta']:.1f} | {row['comparison_shown_fraction']:.1%} | {row['alignment_signal_fraction_all_trials']:.1%} | {width:.3f} |" if width is not None else
                     f"| {row['releases']} | {row['paired_installations']} | {row['true_mean_delta']:.1f} | {row['comparison_shown_fraction']:.1%} | {row['alignment_signal_fraction_all_trials']:.1%} | — |")
    lines += ["", "信号率分母包含被抑制的模拟，避免只挑成功发布的批次报告功效。每个模拟都重新抽取安装差值和噪声。",
              "CSV 另含已显示区间的覆盖率；这是选择后的描述性结果，不能据此证明发布后的条件覆盖保证。",
              "二项比例的最大 Monte Carlo 标准误为 0.5/√模拟次数；固定种子只用于复现。",
              "尚未模拟真实招募偏差、同一人的多设备、丢包/串谋、有限精度噪声、模型和标签偏差；不得把模拟功效当成真实研究功效。", ""]
    prefix.with_suffix(".md").write_text("\n".join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=ROOT / "Research/score-study-v1.draft.json")
    parser.add_argument("--output-prefix", type=Path, default=ROOT / ".build/score-study/score-study-utility")
    parser.add_argument("--trials", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=20260930)
    args = parser.parse_args()
    if not 1 <= args.trials <= 100000:
        parser.error("trials must be between 1 and 100000")
    study = DraftStudy.load(args.manifest)
    rows = simulate(study, args.trials, args.seed)
    write_reports(study, rows, args.manifest, args.output_prefix, args.trials, args.seed)
    print(f"Synthetic-only evaluation: {len(rows)} scenarios, {args.trials} trials each; online collection disabled")
    print(args.output_prefix.with_suffix(".md"))


if __name__ == "__main__":
    main()
