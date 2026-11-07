// Deterministic synthetic backtest for readiness v0.8. Production constants stay
// UNCALIBRATED / 未校准. This executable owns synthetic history, quality gates,
// baseline statistics, reporting and counterfactuals; the engine owns none of them.
import Foundation

nonisolated private struct Recording: Sendable {
    let day: Int
    var sequence: Int = 0
    var finalScore: Double = 70
    var canCompare: Bool = true
    var speechSeconds: Double = 100
    var hnrWindowCount: Int = 12
    var hnr: Double? = 20
    var naturalness: Double? = 80
    var pitchVariation: Double? = 10
    var voiceValue: Double? = 100
}

nonisolated private enum Caller {
    // End-of-practiceDay snapshots include today's samples in the inclusive
    // [day - 29, day] baseline. No database or calendar time is needed here.
    static func input(
        history: [Recording], day: Int, heavyYesterday: Bool = false,
        returnedAfterAbsence: Int? = nil, hnrSigmaFloor: Double = 0.5
    ) -> ReadinessInput {
        let available = history.filter { $0.day <= day }.sorted {
            $0.day == $1.day ? $0.sequence > $1.sequence : $0.day > $1.day
        }
        let window = available.filter { $0.day >= day - 29 }
        let recent = Array(available.prefix(3)) // Select first, then quality-gate; never refill.
        let practiceDays = Set(window.map(\.day))
        let gap = available.first.map { day - $0.day } ?? 0
        let qualified = window.filter(\.canCompare)
        let dailySeconds = Dictionary(grouping: window, by: \.day).values.map {
            $0.reduce(0.0) { $0 + $1.speechSeconds }
        }
        func gated(_ row: Recording, _ value: Double?) -> Double? {
            guard row.canCompare, let value, value.isFinite else { return nil }
            return value
        }
        func hnr(_ row: Recording) -> Double? {
            row.hnrWindowCount >= 10 ? gated(row, row.hnr) : nil
        }
        var input = ReadinessInput()
        input.practiceDaysLast7 = practiceDays.filter { $0 >= day - 6 }.count
        // On a recorded day, the latest practiced day is today and gap is zero.
        input.gapDays = gap
        input.isHabitualUser = practiceDays.count >= 12
        let today = available.filter { $0.day == day }
        input.speechSecondsToday = today.isEmpty ? nil : today.reduce(0) { $0 + $1.speechSeconds }
        input.speechSecondsP90 = percentile90(dailySeconds)
        input.heavyYesterday = heavyYesterday
        input.consecutiveAbsenceDays = returnedAfterAbsence ?? gap
        input.validAssessments = available.filter { $0.canCompare && $0.finalScore.isFinite }.count
        input.recentFinalScores = available.map {
            .init(finalScore: $0.finalScore, canCompare: $0.canCompare)
        }
        input.finalScoreBaseline = baseline(qualified.map(\.finalScore))
        input.hnrRecent3 = recent.map(hnr)
        input.hnrBaseline = baseline(qualified.compactMap(hnr), sigmaFloor: hnrSigmaFloor)
        input.natRecent3 = recent.map { gated($0, $0.naturalness) }
        input.natBaseline = baseline(qualified.compactMap { gated($0, $0.naturalness) })
        input.pvRecent3 = recent.map { gated($0, $0.pitchVariation) }
        input.pvBaseline = baseline(qualified.compactMap { gated($0, $0.pitchVariation) })
        input.vRecent3 = recent.map { gated($0, $0.voiceValue) }
        let voiceSamples = qualified.compactMap { gated($0, $0.voiceValue) }
        input.vBaselineMean = voiceSamples.count >= 5 ? voiceSamples.reduce(0, +) / Double(voiceSamples.count) : nil
        return input
    }

    static func baseline(_ values: [Double], sigmaFloor: Double? = nil) -> BaselineStats? {
        let values = values.filter(\.isFinite)
        guard values.count >= 5 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let sumSquares = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) }
        let sampleSigma = sqrt(sumSquares / Double(values.count - 1))
        let sigma = sigmaFloor.map { max($0, sampleSigma) } ?? sampleSigma
        // No invented n/p/v floor. An unusable (zero/nonfinite) SD is missing.
        guard mean.isFinite, sigma.isFinite, sigma > 0 else { return nil }
        return .init(mean: mean, stdev: sigma)
    }

    static func percentile90(_ values: [Double]) -> Double? {
        guard values.count >= 5 else { return nil }
        let sorted = values.sorted()
        let position = Double(sorted.count - 1) * 0.9
        let lower = Int(position)
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }
}

nonisolated private struct Probe: Sendable {
    let label: String
    let input: ReadinessInput
    // Keep raw synthetic data so caller-owned HNR-floor sensitivity is a real
    // re-preprocessing pass, not an after-the-fact edit to a computed z-score.
    var history: [Recording]? = nil
    var day: Int? = nil
}

nonisolated private struct Profile: Sendable {
    let id: String
    let name: String
    let probes: [Probe]
    let note: String
}

nonisolated private struct Check: Sendable {
    let name: String
    let passed: Bool
    let detail: String
}

nonisolated private struct B2Experiment: Sendable {
    let name: String
    let input: ReadinessInput
    let expectedToFire: Bool
}

nonisolated private struct ScanRow: Sendable {
    let name: String
    let current: Double
    let scale: Double
    let flips: [Int]
    let counts: [Int]
    var unstable: Bool { zip(flips, counts).contains { Double($0.0) / Double($0.1) >= 0.10 } }
}

@main
nonisolated private enum ReadinessBacktest {
    static func main() throws {
        let profiles = fixtures()
        let b2 = b2Experiments()
        let invariants = invariants(profiles)
        let checks = supplementaryChecks(profiles, experiments: b2)
        let scans = sensitivity(profiles)
        let failed = (invariants + checks).filter { !$0.passed }
        let report = report(profiles: profiles, invariants: invariants, checks: checks,
                            experiments: b2, scans: scans)
        let arguments = Array(CommandLine.arguments.dropFirst())
        if !arguments.isEmpty {
            guard arguments.count == 2, arguments[0] == "--report" else {
                throw HarnessError.message("Usage: test-readiness-backtest.sh [--report /absolute/path/report.md]")
            }
            try report.write(toFile: arguments[1], atomically: true, encoding: .utf8)
            print("Report: \(arguments[1])")
        }
        print("Readiness backtest: 9 profiles (P3a/P3b), \(profiles.reduce(0) { $0 + $1.probes.count }) observations")
        print("Invariants: \(invariants.filter(\.passed).count)/7; supplementary checks: \(checks.filter(\.passed).count)/\(checks.count)")
        for experiment in b2.prefix(2) {
            let current = ReadinessScoring.evaluate(experiment.input)
            let noB2 = ReadinessScoring.evaluate(experiment.input, parameters: .init(overrides: [.b2Penalty: 0]))
            print("B2 risk — \(experiment.name): \(number(noB2.score))/\(noB2.level) → \(number(current.score))/\(current.level)")
        }
        let unstable = Set(scans.filter(\.unstable).map(\.name)).sorted()
        print("Sensitivity: \(ReadinessParameter.allCases.count) engine + 1 caller parameters, ±20%, \(unstable.count) unstable (>=10% flips)")
        print("Unstable: \(unstable.joined(separator: ", "))")
        let p2b = ReadinessScoring.evaluate(p2bControl())
        print("P2b slope >1 control: \(summary(p2b)), B1=\(number(delta(p2b, "B1")))")
        let p9 = profiles.first { $0.id == "P9" }!.probes.map { ReadinessScoring.evaluate($0.input) }
        print("P9: 15 recordings / 30 daily evaluations, \(distribution(p9)); A=\(percentage(p9.filter { $0.level == "A" }.count, p9.count))")
        print("P1 accepted: no cap/C, 21 S + 9 A (7 B2 days + 2 cold-start days). P2 +2 per 5 remains below B1 slope >1.")
        if !failed.isEmpty {
            for check in failed {
                let message = "FAIL: \(check.name) — \(check.detail)\n"
                FileHandle.standardError.write(Data(message.utf8))
            }
            throw HarnessError.message("Readiness backtest failed \(failed.count) checks")
        }
    }

    enum HarnessError: Error { case message(String) }

    static func baseRecording(day: Int, index: Int, score: Double = 70) -> Recording {
        let offset = Double([-1, 0, 1, 0, 1, -1][index % 6])
        return Recording(day: day, finalScore: score, hnr: 20 + offset,
                         naturalness: 80 + offset, pitchVariation: 10 + offset, voiceValue: 100 + offset)
    }

    static func probe(_ label: String, history: [Recording], day: Int,
                      heavy: Bool = false, absence: Int? = nil) -> Probe {
        .init(label: label, input: Caller.input(history: history, day: day, heavyYesterday: heavy,
                                                returnedAfterAbsence: absence), history: history, day: day)
    }

    static func acousticHistory(direction: Int, magnitude: Double = 4, corroborated: Bool) -> [Recording] {
        var rows = (0..<14).map { baseRecording(day: $0 * 2, index: $0) }
        for day in [28, 30, 32] {
            rows.append(Recording(day: day, hnr: 20 + Double(direction) * magnitude,
                                  naturalness: corroborated ? 72 : 80,
                                  pitchVariation: corroborated ? 18 : 10))
        }
        return rows
    }

    static func fixtures() -> [Profile] {
        let stable = (0..<30).map {
            baseRecording(day: $0, index: $0, score: stableNoiseScore(recordingIndex: $0))
        }
        let p1 = (0..<30).map { probe("day \($0 + 1)", history: stable, day: $0) }
        let moderate = (0..<15).map {
            baseRecording(day: $0 * 2, index: $0, score: stableNoiseScore(recordingIndex: $0))
        }
        // A rest day is an evaluation date, not an invented recording. Available
        // history and its recent windows remain unchanged until the next record.
        let p9 = (0..<30).map { day in
            probe("day \(day + 1)（\(day.isMultiple(of: 2) ? "录音" : "休息")）", history: moderate, day: day)
        }
        let improving = (0..<30).map {
            baseRecording(day: $0 * 2, index: $0, score: 60 + Double($0 / 5) * 2)
        }
        let p2 = (0..<30).map { probe("assessment \($0 + 1)", history: improving, day: $0 * 2) }
        let down = acousticHistory(direction: -1, corroborated: true)
        let up = acousticHistory(direction: 1, corroborated: true)
        var repeatedLoad = [-12, -10, -8, -6, -4].enumerated().map { baseRecording(day: $0.element, index: $0.offset) }
        for day in 0..<8 {
            for sequence in 0..<2 {
                var row = baseRecording(day: day, index: day * 2 + sequence)
                row.sequence = sequence
                row.speechSeconds = day == 2 ? 200 : 50
                repeatedLoad.append(row)
            }
        }
        var p4: [Probe] = []
        var heavy = false
        for day in 0..<8 {
            let snapshot = probe("day \(day + 1)", history: repeatedLoad, day: day, heavy: heavy)
            p4.append(snapshot)
            heavy = ReadinessScoring.evaluate(snapshot.input).markHeavyYesterday
        }
        // A fixed-seed LCG gives reproducible bidirectional recording-condition
        // shifts. Each probe has its own aligned three-recording shifted window.
        var random: UInt64 = 0x5EED
        var p5: [Probe] = []
        for index in 0..<12 {
            random = random &* 6_364_136_223_846_793_005 &+ 1
            let direction = index.isMultiple(of: 2) ? -1 : 1
            let magnitude = 3.5 + Double((random >> 32) % 100) / 100
            let history = acousticHistory(direction: direction, magnitude: magnitude, corroborated: false)
            p5.append(probe("\(direction > 0 ? "high" : "low") \(index + 1)", history: history, day: 32))
        }
        let habitual = [3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 26, 27, 28]
            .enumerated().map { baseRecording(day: $0.element, index: $0.offset) }
        let p6 = (1...3).map { probe("absence \($0)", history: habitual, day: 28 + $0) }
        let cold = [baseRecording(day: 0, index: 0), baseRecording(day: 2, index: 1)]
        let returning = habitual + [baseRecording(day: 45, index: 15)]
        return [
            .init(id: "P1", name: "基线稳定（逐字负荷）", probes: p1,
                  note: "修订后的核心断言通过：无封顶、无 C。接受全勤 21 S/9 A；其中 7 个 A 日触发 B2、2 个为冷启动。"),
            .init(id: "P2", name: "稳步进步", probes: p2,
                  note: "每五次台阶 +2，隔日练习。最近五次最大斜率 0.6，B1 不触发；另有 P2b >1 正控。"),
            .init(id: "P3a", name: "HNR 下降 + 双旁证", probes: [probe("low", history: down, day: 32)],
                  note: "HNR 下降、naturalness 下降、pitchVariation 上升；必须 59/B。"),
            .init(id: "P3b", name: "HNR 上升 + 双旁证", probes: [probe("high", history: up, day: 32)],
                  note: "仅改变 HNR 方向；必须同为 59/B。"),
            .init(id: "P4", name: "连续八天，每天两次", probes: p4,
                  note: "五个历史练习日建立 P90；第 3 天超量、第 4 天次日封顶 64/B；八天均不被强制定为 C。"),
            .init(id: "P5", name: "录音条件双向抖动", probes: p5,
                  note: "固定种子，12 个双向 HNR 偏移窗口，旁证正常；C1 可扣 10，但不得双异常封顶。"),
            .init(id: "P6", name: "习惯用户缺席三天", probes: p6,
                  note: "窗口内 15 个有记录日；连续缺席 1/2/3 天，A2 必须为零。"),
            .init(id: "P7", name: "仅两次有效评分", probes: [probe("two assessments", history: cold, day: 2)],
                  note: "返回占位 70/A、isColdStart=true；没有因子扣分。"),
            .init(id: "P8", name: "缺席十六天后回归", probes: [probe("return", history: returning, day: 45, absence: 16)],
                  note: "调用方保留回归前 16 天连续缺席信号；#7 强制定级 C，reason=welcomeBack。"),
            .init(id: "P9", name: "隔日练习的中等频率", probes: p9,
                  note: "30 个日历日、15 条录音、30 次逐日评估；沿用 P1 的每条录音噪声。A 超过半数，无封顶/C；录音/休息及冷暖分层见下表。")
        ]
    }

    static func stableNoiseScore(recordingIndex: Int) -> Double {
        70 + Double([-3, 0, 3, 0][recordingIndex % 4])
    }

    static func b2Experiments() -> [B2Experiment] {
        let history = (0..<24).map { baseRecording(day: $0 * 2, index: $0, score: 55 + Double($0) * 0.4) }
        func sparse(_ drop: Double) -> ReadinessInput {
            let rows = history + [Recording(day: 50, finalScore: 72.4),
                                  Recording(day: 55, finalScore: 72.4 - drop),
                                  Recording(day: 60, finalScore: 72.4 - 2 * drop)]
            return Caller.input(history: rows, day: 60)
        }
        var simultaneous = ReadinessInput(practiceDaysLast7: 1, validAssessments: 5)
        simultaneous.recentFinalScores = [70, 72.5, 75, 66, 61].map { .init(finalScore: $0, canCompare: true) }
        return [
            .init(name: "进步期偶发 3.2 分双降", input: sparse(3.2), expectedToFire: true),
            .init(name: "B1 +5 与 B2 −10 同时触发", input: simultaneous, expectedToFire: true),
            .init(name: "边界正控：两次均降 2.01", input: sparse(2.01), expectedToFire: true),
            .init(name: "严格边界负控：两次均降 2.00", input: sparse(2), expectedToFire: false),
            .init(name: "小幅负控：两次均降 1.90", input: sparse(1.9), expectedToFire: false)
        ]
    }

    static func p2bControl() -> ReadinessInput {
        var input = ReadinessInput(validAssessments: 5)
        input.recentFinalScores = [68, 66, 64, 62, 60].map { .init(finalScore: $0, canCompare: true) }
        return input
    }

    static func invariants(_ profiles: [Profile]) -> [Check] {
        func results(_ id: String) -> [ReadinessResult] {
            profiles.first { $0.id == id }!.probes.map { ReadinessScoring.evaluate($0.input) }
        }
        let p3a = results("P3a")[0], p3b = results("P3b")[0]
        let p5 = results("P5")
        let p8 = results("P8")[0]
        let quality = qualityChecks()
        return [
            .init(name: "1 诚实缺席", passed: (results("P6") + results("P7")).allSatisfy { $0.level != "C" }
                  && results("P6").allSatisfy { delta($0, "A2") == 0 }, detail: "P6 A2=0；P6/P7 均不为 C。"),
            .init(name: "2 双异常门控", passed: p5.allSatisfy { fired($0, "C1") && !fired($0, "decision.4") && !hasCap($0) }
                  && Set(p5.compactMap(direction)) == Set([-1, 1])
                  && [p3a, p3b].allSatisfy { $0.score == 59 && $0.level == "B" && fired($0, "decision.4") },
                  detail: "P5 无封顶；P3a/P3b 都为 59/B。"),
            .init(name: "3 质量门控", passed: quality.allSatisfy(\.passed),
                  detail: "调用方先取时间窗口，再把不合格记录映射为 nil；B 保留 canCompare=false，绝不回填旧样本。"),
            .init(name: "4 归因可解释", passed: profiles.allSatisfy { profile in
                let results = profile.probes.map { ReadinessScoring.evaluate($0.input) }
                return results.allSatisfy { explained($0) }
                    && zip(results, results.dropFirst()).allSatisfy { transitionExplained($0, $1) }
            }, detail: "全部观测 score=70+贡献总和；每个因子都有行，等级覆盖有触发证据（可以为零分）。"),
            .init(name: "5 等级与 reason 分离", passed: p8.level == "C" && p8.reason == .welcomeBack,
                  detail: "P8 回归态必须为 C/welcomeBack。"),
            .init(name: "6 方向无关性", passed: p3a.level == p3b.level
                  && direction(p3a) == -1 && direction(p3b) == 1, detail: "HNR 方向相反、等级同为 B。"),
            .init(name: "7 版本标记", passed: [p3a, p3b].allSatisfy {
                $0.formulaVersion == "c1-bidirectional-v1"
                && $0.contributions.first { $0.factorId == "C1" }?.formulaVersion == "c1-bidirectional-v1"
                && $0.contributions.first { $0.factorId == "decision.4" }?.formulaVersion == "dual-anomaly-v1"
            }, detail: "结果、C1 与双异常证据都携带对应版本。")
        ]
    }

    static func qualityChecks() -> [Check] {
        let original = acousticHistory(direction: -1, corroborated: true)
        var checks: [Check] = []
        for index in (original.count - 3)..<original.count {
            var rows = original
            rows[index].canCompare = false
            let input = Caller.input(history: rows, day: 32)
            let result = ReadinessScoring.evaluate(input)
            let alignedIndex = rows.count - 1 - index
            let arrays = [input.hnrRecent3, input.natRecent3, input.pvRecent3, input.vRecent3]
            checks.append(.init(name: "quality slot \(alignedIndex)", passed:
                arrays.allSatisfy { $0.count == 3 && $0[alignedIndex] == nil && $0.compactMap { $0 }.count == 2 }
                && ["B1", "B2", "C1", "C2", "C3", "C4", "decision.4"].allSatisfy { !fired(result, $0) },
                detail: "中间不合格记录也不能被过滤后回填。"))
        }
        var poisoned = original
        for index in (poisoned.count - 3)..<poisoned.count {
            poisoned[index].canCompare = false
            poisoned[index].finalScore = -10_000 + Double(index)
            poisoned[index].hnr = -10_000
        }
        let input = Caller.input(history: poisoned, day: 32)
        let result = ReadinessScoring.evaluate(input)
        checks.append(.init(name: "quality excludes B/C and baseline", passed:
            ["B1", "B2", "B3", "C1", "C2", "C3", "C4"].allSatisfy { !fired(result, $0) && delta(result, $0) == 0 }
            && (input.hnrBaseline?.mean ?? 0) > 19 && input.finalScoreBaseline == nil,
            detail: "恶化到极值的不合格记录也不能进入基线或 B/C。"))
        return checks
    }

    static func supplementaryChecks(_ profiles: [Profile], experiments: [B2Experiment]) -> [Check] {
        var checks = qualityChecks()
        let b2Penalty = ReadinessParameter.b2Penalty.currentValue
        let b2AbsPenalty = abs(b2Penalty)
        let b2Minus20 = b2Penalty * 0.8
        let b2Plus20 = b2Penalty * 1.2
        for experiment in experiments {
            let result = ReadinessScoring.evaluate(experiment.input)
            let zero = ReadinessScoring.evaluate(experiment.input, parameters: .init(overrides: [.b2Penalty: 0]))
            checks.append(.init(name: experiment.name, passed: fired(result, "B2") == experiment.expectedToFire
                && close(zero.score - result.score, experiment.expectedToFire ? b2AbsPenalty : 0)
                && (experiment.expectedToFire || zero.level == result.level),
                detail: "B2=0 仅为配对反事实；生产 B2 \(signed(b2Penalty)) 保持 G 未校准。"))
        }
        for experiment in experiments.prefix(2) {
            let reduced = ReadinessScoring.evaluate(experiment.input, parameters: .init(overrides: [.b2Penalty: b2Minus20]))
            let increased = ReadinessScoring.evaluate(experiment.input, parameters: .init(overrides: [.b2Penalty: b2Plus20]))
            checks.append(.init(name: "B2 ±20% risk: \(experiment.name)", passed:
                close(reduced.score - increased.score, abs(b2Minus20 - b2Plus20))
                    && reduced.level == increased.level,
                detail: "以 B2 \(signed(b2Penalty)) 为基准单独扫描 \(signed(b2Minus20))/\(signed(b2Plus20))，不能被不触发 B2 的普通画像稀释。"))
        }
        let risk = ReadinessScoring.evaluate(experiments[1].input)
        checks.append(.init(name: "B2 false positive retains paired score impact", passed:
            delta(risk, "B1") == 5 && delta(risk, "B2") == b2Penalty
                && close(risk.score, 70 + 4 + 5 + b2Penalty) && risk.level == "A",
            detail: "同一个最近五次窗口总体进步仍被局部双降扣除 B2 \(signed(b2Penalty))；B2=0 保留为配对反事实。"))
        let p2 = profiles.first { $0.id == "P2" }!
        checks.append(.init(name: "P2 literal trend is below B1 threshold", passed:
            p2.probes.allSatisfy { !fired(ReadinessScoring.evaluate($0.input), "B1") },
            detail: "每五次 +2 不能通过 slope>1。"))
        let slopeResult = ReadinessScoring.evaluate(p2bControl())
        checks.append(.init(name: "P2b slope >1 positive control", passed: delta(slopeResult, "B1") == 5
                            && slopeResult.score == 75 && slopeResult.level == "A",
                            detail: "每次 +2（不是每五次 +2）得到奖励。"))
        let stableHistory = (0..<30).map { baseRecording(day: $0, index: $0,
                                              score: 70 + Double([-3, -1, 1, 3, 1, -1, 0][$0 % 7])) }
        let stableResults = (4..<30).map { day in
            var input = Caller.input(history: stableHistory, day: day)
            input.practiceDaysLast7 = 0
            return ReadinessScoring.evaluate(input)
        }
        checks.append(.init(name: "P1 stable acoustics with isolated neutral load", passed:
            stableResults.allSatisfy { $0.level == "A" && !hasCap($0) },
            detail: "明确隔离 A 类负荷的控制组；不冒充每日练习画像。"))
        let p4 = profiles.first { $0.id == "P4" }!.probes.map { ReadinessScoring.evaluate($0.input) }
        checks.append(.init(name: "P4 next-day heavy behavior without forced C", passed:
            p4[2].markHeavyYesterday && p4[3].score == 64 && p4[3].level == "B" && p4[3].reason == .heavyYesterday
            && p4.allSatisfy { $0.level != "C" && explained($0) },
            detail: "第 3 天超量标记、第 4 天 64/B，八天均不因连续练习被强制定为 C。"))
        let p4Probes = profiles.first { $0.id == "P4" }!.probes
        for dayIndex in [6, 7] {
            var input = p4Probes[dayIndex].input
            input.recentFinalScores = [60, 65, 70, 68, 65].map { .init(finalScore: $0, canCompare: true) }
            input.hnrRecent3 = [14, 14, 14]
            input.hnrBaseline = .init(mean: 20, stdev: 1)
            input.natRecent3 = [75, 75, 75]
            input.natBaseline = .init(mean: 80, stdev: 1)
            input.pvRecent3 = [15, 15, 15]
            input.pvBaseline = .init(mean: 10, stdev: 1)
            input.vRecent3 = [60, 60, 60]
            input.vBaselineMean = 100
            input.speechSecondsToday = 300
            input.speechSecondsP90 = 100
            let result = ReadinessScoring.evaluate(input)
            checks.append(.init(name: "P4 day \(dayIndex + 1) still evaluates B/C and next-day flag", passed:
                ["B2", "C1", "C2", "C3", "C4"].allSatisfy { fired(result, $0) }
                && result.markHeavyYesterday && result.level == "B" && result.reason == .voiceTired
                && explained(result), detail: "第七/八天附加异常与超量正控继续计算，不按练习天数提前返回。"))
        }
        let p1 = profiles.first { $0.id == "P1" }!.probes.map { ReadinessScoring.evaluate($0.input) }
        checks.append(.init(name: "P1 daily practice has no cap or forced C", passed:
            p1.allSatisfy { !hasCap($0) && $0.level != "C" },
            detail: "按最新画像预期接受全勤 S/A 分布，核心断言为无封顶/C。"))
        let p1Probes = profiles.first { $0.id == "P1" }!.probes
        let p1B2Days = p1.enumerated().filter { fired($0.element, "B2") }.map { $0.offset + 1 }
        let p1ColdDays = p1.enumerated().filter { $0.element.isColdStart }.map { $0.offset + 1 }
        let p1WithoutB2 = p1Probes.map {
            ReadinessScoring.evaluate($0.input, parameters: .init(overrides: [.b2Penalty: 0]))
        }
        checks.append(.init(name: "P1 9 A days split into 7 B2 and 2 cold-start", passed:
            p1.filter { $0.level == "S" }.count == 21 && p1.filter { $0.level == "A" }.count == 9
            && p1B2Days == [5, 9, 13, 17, 21, 25, 29] && p1ColdDays == [1, 2]
            && p1.enumerated().allSatisfy { index, result in
                if fired(result, "B2") {
                    return result.score == 80 && result.level == "A"
                        && p1WithoutB2[index].score == 90 && p1WithoutB2[index].level == "S"
                }
                return result.score == p1WithoutB2[index].score && result.level == p1WithoutB2[index].level
            }, detail: "纠正规格括注：9 个 A 日并非全由 B2 导致；B2=0 只改变 7 个日子。"))
        let p9Probes = profiles.first { $0.id == "P9" }!.probes
        let p9 = p9Probes.map { ReadinessScoring.evaluate($0.input) }
        checks.append(.init(name: "P9 A majority with no cap or C", passed:
            p9.count == 30 && p9.filter { $0.level == "A" }.count * 2 > p9.count
            && p9.allSatisfy { !hasCap($0) && $0.level != "C" },
            detail: "A 必须严格超过 50%；可能出现的 B 如实报告，不改变负荷或 B2。"))
        checks.append(.init(name: "P9 15 actual recordings and 30 evaluations without synthetic fill", passed:
            p9Probes.count == 30 && p9Probes.allSatisfy { probe in
                guard let day = probe.day, let history = probe.history else { return false }
                return history.count == 15 && Set(history.map(\.day)) == Set(stride(from: 0, to: 30, by: 2))
                    && probe.input.recentFinalScores.count == day / 2 + 1
                    && probe.input.recentFinalScores.first?.finalScore == stableNoiseScore(recordingIndex: day / 2)
                    && (probe.input.speechSecondsToday == nil) == !day.isMultiple(of: 2)
                    && history.enumerated().allSatisfy { $0.element.finalScore == stableNoiseScore(recordingIndex: $0.offset) }
            }, detail: "每条记录沿用 P1 的 [-3,0,3,0] 噪声；休息日不新增 0 或 nil 录音槽。"))
        let constant = Array(repeating: 20.0, count: 5)
        checks.append(.init(name: "caller sample SD and HNR-only floor", passed:
            Caller.baseline([1, 2, 3, 4, 5]) == .init(mean: 3, stdev: sqrt(2.5))
            && Caller.baseline(constant) == nil && Caller.baseline(constant, sigmaFloor: 0.5)?.stdev == 0.5
            && Caller.baseline([1, 2, 3, 4], sigmaFloor: 0.5) == nil
            && Caller.percentile90([1, 2, 3, 4]) == nil,
            detail: "n−1 样本 SD；<5 不建基线/P90；只为 HNR 施加 0.5。"))
        let old = Recording(day: -30, finalScore: -10_000, hnr: -10_000)
        let current = (0..<5).map { baseRecording(day: $0, index: $0) }
        checks.append(.init(name: "caller inclusive 30-day window", passed:
            Caller.input(history: current + [old], day: 4).hnrBaseline
                == Caller.input(history: current, day: 4).hnrBaseline,
            detail: "30 天之外的极值不污染基线。"))
        var legacy = acousticHistory(direction: -1, corroborated: true)
        legacy[legacy.count - 1].hnr = nil
        let legacyResult = ReadinessScoring.evaluate(Caller.input(history: legacy, day: 32))
        checks.append(.init(name: "legacy voiceQuality missing", passed:
            !fired(legacyResult, "C1") && !fired(legacyResult, "decision.4") && delta(legacyResult, "C1") == 0,
            detail: "旧录音 hnr=nil 是缺席，不补零。"))
        var lowWindows = acousticHistory(direction: -1, corroborated: true)
        lowWindows[lowWindows.count - 1].hnrWindowCount = 9
        let lowWindowsInput = Caller.input(history: lowWindows, day: 32)
        checks.append(.init(name: "HNR w<10 gate", passed: lowWindowsInput.hnrRecent3[0] == nil
            && !fired(ReadinessScoring.evaluate(lowWindowsInput), "C1"), detail: "HNR 的 10 窗口质量门控在调用方。"))
        return checks
    }

    static func sensitivity(_ profiles: [Profile]) -> [ScanRow] {
        let originals = profiles.map { $0.probes.map { ReadinessScoring.evaluate($0.input) } }
        var rows: [ScanRow] = []
        for parameter in ReadinessParameter.allCases {
            for scale in [0.8, 1.2] {
                let parameters = ReadinessParameters(overrides: [parameter: parameter.currentValue * scale])
                var flips: [Int] = []
                for (index, profile) in profiles.enumerated() {
                    var changed = 0
                    var heavy = false
                    for (probeIndex, probe) in profile.probes.enumerated() {
                        var input = probe.input
                        // Propagate the changed A4 predicate into tomorrow's P4
                        // input; all other profiles are independent snapshots.
                        if profile.id == "P4" { input.heavyYesterday = heavy }
                        let result = ReadinessScoring.evaluate(input, parameters: parameters)
                        precondition(explained(result, parameters: parameters), "Sensitivity attribution")
                        if result.level != originals[index][probeIndex].level { changed += 1 }
                        heavy = result.markHeavyYesterday
                    }
                    flips.append(changed)
                }
                rows.append(.init(name: parameter.rawValue, current: parameter.currentValue, scale: scale,
                                  flips: flips, counts: profiles.map { $0.probes.count }))
            }
        }
        for scale in [0.8, 1.2] {
            let flips = profiles.enumerated().map { index, profile in
                profile.probes.enumerated().reduce(0) { count, item in
                    let (probeIndex, probe) = item
                    guard let history = probe.history, let day = probe.day else { return count }
                    var input = Caller.input(history: history, day: day, hnrSigmaFloor: 0.5 * scale)
                    input.heavyYesterday = probe.input.heavyYesterday
                    input.consecutiveAbsenceDays = probe.input.consecutiveAbsenceDays
                    return count + (ReadinessScoring.evaluate(input).level == originals[index][probeIndex].level ? 0 : 1)
                }
            }
            rows.append(.init(name: "caller.hnrSigmaFloor", current: 0.5, scale: scale, flips: flips,
                              counts: profiles.map { $0.probes.count }))
        }
        return rows
    }

    static func report(profiles: [Profile], invariants: [Check], checks: [Check],
                       experiments: [B2Experiment], scans: [ScanRow]) -> String {
        let b2Penalty = ReadinessParameter.b2Penalty.currentValue
        let b2Minus20 = b2Penalty * 0.8
        let b2Plus20 = b2Penalty * 1.2
        let b2RiskExperiments = Array(experiments.prefix(2))
        let b2RiskCurrent = b2RiskExperiments.map { ReadinessScoring.evaluate($0.input) }
        let b2RiskReduced = b2RiskExperiments.map { ReadinessScoring.evaluate($0.input, parameters: .init(overrides: [.b2Penalty: b2Minus20])) }
        let b2RiskIncreased = b2RiskExperiments.map { ReadinessScoring.evaluate($0.input, parameters: .init(overrides: [.b2Penalty: b2Plus20])) }
        let b2ReducedFlips = zip(b2RiskCurrent, b2RiskReduced).filter { $0.0.level != $0.1.level }.count
        let b2IncreasedFlips = zip(b2RiskCurrent, b2RiskIncreased).filter { $0.0.level != $0.1.level }.count
        let allB2Reduced = experiments.map { ReadinessScoring.evaluate($0.input, parameters: .init(overrides: [.b2Penalty: b2Minus20])) }
        let allB2Increased = experiments.map { ReadinessScoring.evaluate($0.input, parameters: .init(overrides: [.b2Penalty: b2Plus20])) }
        let allCurrent = experiments.map { ReadinessScoring.evaluate($0.input) }
        let allReducedFlips = zip(allCurrent, allB2Reduced).filter { $0.0.level != $0.1.level }.count
        let allIncreasedFlips = zip(allCurrent, allB2Increased).filter { $0.0.level != $0.1.level }.count
        var lines = ["# Readiness 合成回测报告", "", "规格：readiness v0.8（2026-10-10 修订）；规则证据版本 `readiness-v0.8-r2-uncalibrated`。全部 G 级数值 **未校准**；B2 = −10（2026-10-10 #29 裁决，仍 G 未校准）。",
                     "", "复现：`sh Scripts/test-readiness-backtest.sh --report .build/readiness-backtest-report.md`。Swift 6、完整并发检查、默认 MainActor 隔离、warnings-as-errors；不依赖 Core 或 UI。",
                     "", "## 第一优先级：B2 误伤画像", "",
                     "B2=0 仅是 harness 内的配对反事实，不改变生产默认。它量化 \(signed(b2Penalty)) 的独立影响；没有据此调参。总体进步与最近三次连续下滑可以同时存在。",
                     "", "| 画像/控制 | 最近五次（早→晚） | B1 | B2 | B3 | 当前 \(signed(b2Penalty)) | B2=\(signed(b2Minus20)) | B2=\(signed(b2Plus20)) | B2=0 | 当前 vs 0 分数 / 等级变化 |", "|---|---|---:|---:|---:|---|---|---|---|---|"]
        for experiment in experiments {
            let current = ReadinessScoring.evaluate(experiment.input)
            let zero = ReadinessScoring.evaluate(experiment.input, parameters: .init(overrides: [.b2Penalty: 0]))
            let reduced = ReadinessScoring.evaluate(experiment.input, parameters: .init(overrides: [.b2Penalty: b2Minus20]))
            let increased = ReadinessScoring.evaluate(experiment.input, parameters: .init(overrides: [.b2Penalty: b2Plus20]))
            let scores = experiment.input.recentFinalScores.prefix(5).reversed().map { number($0.finalScore) }.joined(separator: " → ")
            lines.append("| \(experiment.name) | \(scores) | \(number(delta(current, "B1"))) | \(number(delta(current, "B2"))) | \(number(delta(current, "B3"))) | \(summary(current)) | \(summary(reduced)) | \(summary(increased)) | \(summary(zero)) | \(number(current.score - zero.score)) / \(zero.level)→\(current.level) |")
        }
        lines += ["", "这组可复现实例证明误伤风险存在，不是人群发生率或临床效果的估计。严格 `>2`：恰好 2.00 与 1.90 的双降不会触发；2.01 会触发。",
                  "", "**B2 误伤组独立敏感度：**前两行主要风险画像，\(signed(b2Minus20))（扣分幅值 −20%）相对 \(signed(b2Penalty)) 为 \(b2ReducedFlips)/\(b2RiskExperiments.count) 等级翻转（\(percentage(b2ReducedFlips, b2RiskExperiments.count))）；\(signed(b2Plus20))（幅值 +20%）为 \(b2IncreasedFlips)/\(b2RiskExperiments.count)（\(percentage(b2IncreasedFlips, b2RiskExperiments.count))）。包含三组阈值控制的整张表则分别为 \(allReducedFlips)/\(experiments.count)（\(percentage(allReducedFlips, experiments.count))）与 \(allIncreasedFlips)/\(experiments.count)（\(percentage(allIncreasedFlips, experiments.count))）。该风险组不混入下方 P1–P9 的分母。普通画像可能没有 B2，或被高优先级决策封顶遮住；其 B2 等级翻转率为零不能排除误伤。"]
        let p1Probes = profiles.first { $0.id == "P1" }!.probes
        let p1 = p1Probes.map { ReadinessScoring.evaluate($0.input) }
        let p1WithoutB2 = p1Probes.map {
            ReadinessScoring.evaluate($0.input, parameters: .init(overrides: [.b2Penalty: 0]))
        }
        let p1B2Indices = p1.indices.filter { fired(p1[$0], "B2") }
        let p1ColdIndices = p1.indices.filter { p1[$0].isColdStart }
        lines += ["", "### P1 稳定噪声的归因审计（决策 #29 补充证据）", "",
                  "实际 \(p1.filter { $0.level == "A" }.count) 个 A 日分为 **\(p1B2Indices.count) 个 B2 日**（\(p1B2Indices.map { p1Probes[$0].label }.joined(separator: "、"))）和 **\(p1ColdIndices.count) 个冷启动日**（\(p1ColdIndices.map { p1Probes[$0].label }.joined(separator: "、"))）。新版规格括注‘9 个 A 天系 B2 所致’不准确；以下按实际触发贡献拆分。",
                  "", "| P1 的 A 日 | 实际归因 | 当前 | B2=0 反事实 | B2 分数影响 |", "|---|---|---|---|---:|"]
        for index in p1.indices where p1[index].level == "A" {
            lines.append("| \(p1Probes[index].label) | \(p1[index].isColdStart ? "冷启动占位；B2 未参与" : "B2 连续两次下降 3 分") | \(summary(p1[index])) | \(summary(p1WithoutB2[index])) | \(number(p1[index].score - p1WithoutB2[index].score)) |")
        }
        lines += ["", "P1 的 B2=0 配对结果为 \(distribution(p1WithoutB2))；仅上述 \(p1B2Indices.count) 个 B2 日从 A 变 S，两个冷启动日仍为 70/A。这是噪声触发 \(signed(b2Penalty)) 的可复现证据，不作为擅自调参依据。",
                  "", "## 全部画像", "", "9 类画像中 P3 分 a/b，故有 \(profiles.count) 行、\(profiles.reduce(0) { $0 + $1.probes.count }) 次观测；每个参数的两次扫描均覆盖 P1–P9 全部行、全部观测。P9 包含 15 条真实合成录音和 30 次逐日评估。",
                  "", "| 画像 | 观测数 | 等级分布 | 分数范围 | 决策封顶次数 | 结果与解释 |", "|---|---:|---|---|---:|---|"]
        for profile in profiles {
            let results = profile.probes.map { ReadinessScoring.evaluate($0.input) }
            lines.append("| \(profile.id) \(profile.name) | \(results.count) | \(distribution(results)) | \(number(results.map(\.score).min()!))–\(number(results.map(\.score).max()!)) | \(results.filter(hasCap).count) | \(profile.note) |")
        }
        let p9Probes = profiles.first { $0.id == "P9" }!.probes
        let p9 = p9Probes.map { ReadinessScoring.evaluate($0.input) }
        let recorded = p9.indices.filter { p9Probes[$0].input.speechSecondsToday != nil }
        let resting = p9.indices.filter { p9Probes[$0].input.speechSecondsToday == nil }
        let cold = p9.indices.filter { p9[$0].isColdStart }
        let warm = p9.indices.filter { !p9[$0].isColdStart }
        let strata: [(String, [Int])] = [
            ("全部日历日", Array(p9.indices)), ("录音日", recorded), ("休息日", resting),
            ("冷启动", cold), ("已过冷启动", warm),
            ("录音日 × 冷启动", recorded.filter { p9[$0].isColdStart }),
            ("录音日 × 已过冷启动", recorded.filter { !p9[$0].isColdStart }),
            ("休息日 × 冷启动", resting.filter { p9[$0].isColdStart }),
            ("休息日 × 已过冷启动", resting.filter { !p9[$0].isColdStart })
        ]
        lines += ["", "## P9：每日状态与录音频率的分层", "",
                  "连续 30 个日历日，在 day1/3/…/29 各录一次，共 15 条。每条录音按 P1 同一 `[-3,0,3,0]` 循环生成 finalScore；录音日和休息日都计算 Readiness。休息日不补 0、不插入 nil 录音，B/C 保留最近真实录音窗口；A2 使用实际 gapDays。下面同时展示全体和冷启动后的分布，录音日的 S 占比不会被休息日合计掩盖。",
                  "", "| 分层 | 评估数 | S | A | B | C | A 占比 |", "|---|---:|---:|---:|---:|---:|---:|"]
        for (name, indices) in strata {
            let results = indices.map { p9[$0] }
            let counts = ["S", "A", "B", "C"].map { level in results.filter { $0.level == level }.count }
            lines.append("| \(name) | \(results.count) | \(counts.map(String.init).joined(separator: " | ")) | \(percentage(counts[1], results.count)) |")
        }
        let p9BDays = p9.indices.filter { p9[$0].level == "B" }.map { index in
            "\(p9Probes[index].label)：\(summary(p9[index]))（\(evidence(p9[index]))）"
        }
        let p9Summary = p9BDays.isEmpty ? "没有 B 日" : p9BDays.joined(separator: "；")
        let p9Explanation = p9BDays.isEmpty
            ? "没有 B 日；这些结果来自普通分数映射，无封顶、无 C"
            : "\(p9Summary)；这些 B 来自普通分数映射，无封顶、无 C"
        lines += ["", "全体 A 占比 \(percentage(p9.filter { $0.level == "A" }.count, p9.count))，已过冷启动 A 占比 \(percentage(warm.filter { p9[$0].level == "A" }.count, warm.count))。\(p9Explanation)；严格保留 B2 \(signed(b2Penalty))，不为得到只含 A/S 的结果改动噪声或休息日。"]
        let a1Maximum = ReadinessParameter.a1MaximumDays.currentValue * ReadinessParameter.a1PointsPerDay.currentValue
        let b1Reward = ReadinessParameter.b1Reward.currentValue
        lines += ["", "## 画像预期修正与未校准观察", "",
                  "1. P1 原‘始终 A 档’预期未计入全勤 A1 奖励，最新规格已将核心断言修正为‘无封顶、无 C’，现有 21 S/9 A 被接受；这是已解决的画像预期问题。A1 上限 +\(number(a1Maximum)) 是 B1 单次 +\(number(b1Reward)) 的 \(number(a1Maximum / b1Reward)) 倍，记为 G 级慷慨度未校准观察，保持原值。上文按实际归因纠正了规格对 9 个 A 日的括注。",
                  "2. P2 按字面每五次台阶 +2，五点 OLS 最高 0.6；如果解释成线性每次 +0.4，斜率仍只有 0.4。两者都不满足 B1 的 `slope >1`。按修订规格增加独立 P2b（每次 +2），确认 +5 奖励；原始 P2 保留不变。",
                  "3. #7 只覆盖等级，不改写分数；因此回归态 C 可以伴随高于 40 的分数。#4 即使扣分后低于 40，仍按规格强制 B。证据中的零分触发项记录此区别；本回测不补造低分，也不提高低分。",
                  "", "| 画像 | 时点 | score / level | reason | 触发贡献（含零分决策） |", "|---|---|---|---|---|"]
        for profile in profiles.filter({ ["P1", "P3a", "P3b", "P4", "P6", "P7", "P8", "P9"].contains($0.id) }) {
            for probe in profile.probes {
                let result = ReadinessScoring.evaluate(probe.input)
                lines.append("| \(profile.id) | \(probe.label) | \(summary(result)) | \(result.reason?.rawValue ?? "—") | \(evidence(result)) |")
            }
        }
        let p2Last = profiles.first { $0.id == "P2" }!.probes.last!.input
        let p2b = ReadinessScoring.evaluate(p2bControl())
        lines += ["", "P2 最终 finalScore=\(number(p2Last.recentFinalScores[0].finalScore))，30 天个人分数基线均值=\(number(p2Last.finalScoreBaseline?.mean ?? .nan))；呈现基线滞后，但 B3 只惩罚负向异常。",
                  "", "P2b 独立隔离对照：最近五次按早→晚为 `60 → 62 → 64 → 66 → 68`，OLS=+2/次；B1=+\(number(delta(p2b, "B1")))，结果 **\(summary(p2b))**。它不替代 P2，也不混入九画像敏感度扫描分母。",
                  "", "## 七个不变量", "", "| 不变量 | 结果 | 证据 |", "|---|---|---|"]
        for check in invariants { lines.append("| \(check.name) | \(check.passed ? "PASS" : "FAIL") | \(check.detail) |") }
        lines += ["", "补充断言：\(checks.filter(\.passed).count)/\(checks.count) 通过。包括 B2 >2 边界/反事实、P1 的 7 B2+2 冷启动归因、P9 A>50% 且无封顶/C、P9 15 录音/30 评估且不补缺失、P2b 正控、P4 次日超量且八天无强制 C、第七/八天仍计算 B/C 与次日标记、质量窗口对齐、30 天过滤、n−1 SD、HNR-only floor、基线/P90 至少 5 样本、旧录音 nil 与 HNR w<10。",
                  "", "## ±20% 单参数敏感度扫描", "",
                  "\(scans.count) 行扫描，每行只改变一个参数，并覆盖 P1–P9 所有 \(profiles.reduce(0) { $0 + $1.probes.count }) 个观测（包括 P9 的所有休息日）。翻转率=该画像中等级不同于现行参数的观测数/该画像观测总数；上下方向分别报告。任一画像 **≥10%** 即标记该方向及参数‘不稳定’。单观测画像只有 0%/100%，不作人群统计解释。P4 重算 A4 后会把超量标记传入下一天。全局阈值虽未逐项明确标 G，也保守纳入扫描；C 的三时刻对齐和 B2 三点模式属于结构约束。",
                  "", "| 参数 | 现值 | 变化后 | \(profiles.map(\.id).joined(separator: " | ")) | 标记 |",
                  "|---|---:|---:|\(profiles.map { _ in "---:" }.joined(separator: "|"))|---|"]
        for row in scans {
            let rates = zip(row.flips, row.counts).map { "\($0.0)/\($0.1) (\(number(100 * Double($0.0) / Double($0.1)))%)" }.joined(separator: " | ")
            lines.append("| \(row.name) | \(number(row.current)) | \(number(row.current * row.scale)) (\(row.scale < 1 ? "−20%" : "+20%")) | \(rates) | \(row.unstable ? "**不稳定**" : "<10%") |")
        }
        let unstable = Set(scans.filter(\.unstable).map(\.name)).sorted()
        lines += ["", "不稳定参数（\(unstable.count)）：\(unstable.map { "`\($0)`" }.joined(separator: "、"))。所有数值仍保持现行默认，未校准；这份结果不宣称通过‘全部参数翻转率 <10%’的稳定性目标。",
                  "", "| 画像 | 全部单参数扰动合计翻转数 / 评估数 | 合计翻转率 |", "|---|---:|---:|"]
        for (index, profile) in profiles.enumerated() {
            let flips = scans.reduce(0) { $0 + $1.flips[index] }
            let count = scans.reduce(0) { $0 + $1.counts[index] }
            lines.append("| \(profile.id) | \(flips)/\(count) | \(number(100 * Double(flips) / Double(count)))% |")
        }
        let pooledFlips = scans.reduce(0) { $0 + $1.flips.reduce(0, +) }
        let pooledCount = scans.reduce(0) { $0 + $1.counts.reduce(0, +) }
        lines.append("| P1–P9 全部观测合计 | \(pooledFlips)/\(pooledCount) | \(percentage(pooledFlips, pooledCount)) |")
        lines += ["", "## 调用方与可复现性", "",
                  "- 合成数据使用整数 practiceDay，窗口为 `[day−29, day]`，按天去重负荷；当日结束后计算，今天有记录时 gapDays=0。P90 按日总 speechSeconds 的线性分位数计算；少于五个练习日传 nil。",
                  "- 基线样本按 canCompare 质量门控；HNR 还要求 w≥10 且值非 nil。基线至少五个样本，SD 使用 n−1；只有 HNR 应用 0.5 dB floor。n/p 不设 floor，零/非有限 SD 传 nil；C4 只需要有效均值。",
                  "- 最近三次保留真实录音的时间槽。质量不合格和旧录音的缺失特征映射为 nil，不补 0、不插值、不用更老记录回填。休息日不凭空创建录音槽；未满三次真实录音时保留不足三次的窗口。HNR floor 的 ±20% 使用原始合成历史重新计算基线，单独列为 caller 参数；其它调用方策略不被冒充为引擎参数。",
                  "- P5 使用固定种子 0x5EED；所有输入、参数枚举与报告均来自同一可执行 harness，无文件取数或随机时钟依赖。冷启动/短路也保留所有因子零贡献行。",
                  "- 这是合成逻辑验证，尚无真实人群校准；P1 的原始预期问题已通过更新验收口径解决，P2 的已知画像冲突、B2 风险和参数敏感性仍如实保留；除 B2 按 #29 裁决更新外，没有其他生产默认参数变更。", ""]
        return lines.joined(separator: "\n")
    }

    static func explained(_ result: ReadinessResult, parameters: ReadinessParameters = .current) -> Bool {
        let ids = Set(result.contributions.map(\.factorId))
        let expected = ["A1", "A2", "A4", "B1", "B2", "B3", "C1", "C2", "C3", "C4"]
        let allowed = Set(expected + ["coldStart", "decision.4", "decision.5", "decision.6", "decision.7"])
        let levelExplained: Bool
        if result.isColdStart {
            levelExplained = result.level == "A" && result.reason == nil && fired(result, "coldStart")
        } else {
            switch result.reason {
            case .welcomeBack:
                levelExplained = result.level == "C" && fired(result, "decision.7")
            case .voiceTired:
                levelExplained = result.level == "B" && fired(result, "decision.4")
            case .heavyYesterday:
                levelExplained = result.level == ReadinessScoring.level(for: result.score, parameters: parameters)
                    && fired(result, "decision.6")
            case nil:
                levelExplained = result.level == ReadinessScoring.level(for: result.score, parameters: parameters)
            }
        }
        return result.score.isFinite && close(result.score, parameters.value(.initialScore) + result.contributions.reduce(0) { $0 + $1.contribution })
            && expected.allSatisfy(ids.contains) && ids.isSubset(of: allowed) && ids.count == result.contributions.count
            && result.contributions.allSatisfy { $0.contribution.isFinite && ($0.isTriggered || $0.contribution == 0) }
            && levelExplained
    }

    static func transitionExplained(_ previous: ReadinessResult, _ current: ReadinessResult) -> Bool {
        guard previous.level != current.level else { return true }
        let previousByID = Dictionary(uniqueKeysWithValues: previous.contributions.map { ($0.factorId, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.contributions.map { ($0.factorId, $0) })
        return Set(previousByID.keys).union(currentByID.keys).contains { id in
            let before = previousByID[id]
            let after = currentByID[id]
            return (before?.isTriggered == true || after?.isTriggered == true)
                && (before?.contribution != after?.contribution || before?.isTriggered != after?.isTriggered)
        }
    }

    static func fired(_ result: ReadinessResult, _ id: String) -> Bool {
        result.contributions.contains { $0.factorId == id && $0.isTriggered }
    }
    static func delta(_ result: ReadinessResult, _ id: String) -> Double {
        result.contributions.first { $0.factorId == id }?.contribution ?? 0
    }
    static func direction(_ result: ReadinessResult) -> Int? {
        result.contributions.first { $0.factorId == "C1" }?.direction
    }
    static func hasCap(_ result: ReadinessResult) -> Bool {
        ["decision.4", "decision.6"].contains { fired(result, $0) }
    }
    static func close(_ first: Double, _ second: Double) -> Bool { abs(first - second) < 0.000_001 }
    static func number(_ value: Double) -> String {
        if value.rounded() == value { return String(format: "%.0f", value) }
        return String(format: "%.2f", value)
    }
    static func summary(_ result: ReadinessResult) -> String { "\(number(result.score))/\(result.level)" }
    static func distribution(_ results: [ReadinessResult]) -> String {
        ["S", "A", "B", "C"].compactMap { level in
            let count = results.filter { $0.level == level }.count
            return count == 0 ? nil : "\(level):\(count)"
        }.joined(separator: ", ")
    }
    static func percentage(_ numerator: Int, _ denominator: Int) -> String {
        denominator > 0 ? "\(number(100 * Double(numerator) / Double(denominator)))%" : "—"
    }
    static func evidence(_ result: ReadinessResult) -> String {
        result.contributions.filter(\.isTriggered).map { "\($0.factorId):\(number($0.contribution))" }.joined(separator: ", ")
    }
    static func signed(_ value: Double) -> String {
        value < 0 ? "−\(number(abs(value)))" : number(value)
    }
}
