import Foundation

/// Formula and pipeline contract tests. Synthetic population backtests live in
/// ReadinessBacktest.swift; this suite concentrates on rule boundaries and holes.
@main
enum ReadinessScoringTests {
    static func main() async {
        var checks = 0
        var evaluated: [ReadinessResult] = []

        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        func close(_ actual: Double, _ expected: Double) -> Bool {
            actual.isFinite && abs(actual - expected) < 0.000_001
        }
        func input(_ configure: (inout ReadinessInput) -> Void) -> ReadinessInput {
            var value = ReadinessInput(validAssessments: 3)
            configure(&value)
            return value
        }
        func evaluate(_ value: ReadinessInput = ReadinessInput(validAssessments: 3)) -> ReadinessResult {
            let result = ReadinessScoring.evaluate(value)
            evaluated.append(result)
            return result
        }
        func row(_ result: ReadinessResult, _ id: String) -> FactorContribution {
            guard let contribution = result.contributions.first(where: { $0.factorId == id }) else {
                preconditionFailure("Missing contribution row: \(id)")
            }
            return contribution
        }
        func expectFactor(_ result: ReadinessResult, _ id: String, _ amount: Double, fired: Bool) {
            let contribution = row(result, id)
            check(close(contribution.contribution, amount), "\(id): expected contribution \(amount), got \(contribution.contribution)")
            check(contribution.isTriggered == fired, "\(id): expected triggered=\(fired)")
        }
        func scores(_ values: [Double]) -> [ScoredAssessment] {
            values.map { .init(finalScore: $0, canCompare: true) }
        }
        func acousticInput(hnr: Double = 18) -> ReadinessInput {
            input {
                $0.practiceDaysLast7 = 5
                $0.hnrRecent3 = [hnr, hnr, hnr]
                $0.hnrBaseline = .init(mean: 20, stdev: 1)
                $0.natRecent3 = [60, 60, 60]
                $0.natBaseline = .init(mean: 70, stdev: 5)
                $0.pvRecent3 = [12, 12, 12]
                $0.pvBaseline = .init(mean: 10, stdev: 1)
            }
        }

        let factorIDs = ["A1", "A2", "A4", "B1", "B2", "B3", "C1", "C2", "C3", "C4"]
        let deletedFactorIDs: Set<String> = ["A3", "decision.1", "decision.2"]
        check(ReadinessReason(rawValue: "overtrained") == nil && ReadinessReason(rawValue: "streakRest") == nil, "Deleted load-only reasons are absent from the result schema")
        check(!ReadinessParameter.allCases.contains { $0.rawValue.hasPrefix("a3") }, "Deleted load-only parameters are absent from sensitivity scans")
        let baseline = evaluate()
        check(baseline.score == 70 && baseline.level == "A", "Empty optional data preserves score 70 / A")
        check(baseline.reason == nil && !baseline.isColdStart && !baseline.markHeavyYesterday, "Validated empty optional input is an ordinary, unflagged evaluation")
        for id in factorIDs {
            expectFactor(baseline, id, 0, fired: false)
        }
        for (score, level) in [(-10.0, "C"), (39.999, "C"), (40, "B"), (64.999, "B"), (65, "A"), (84.999, "A"), (85, "S"), (110, "S")] {
            check(ReadinessScoring.level(for: score) == level, "String level boundary at \(score)")
        }

        // A1/A2: exact limits and the habitual-user exemption at three days.
        for (days, reward) in [(0, 0.0), (1, 4), (4, 16), (5, 20), (7, 20)] {
            let result = evaluate(input { $0.practiceDaysLast7 = days })
            check(result.score == 70 + reward, "A1 day limit: \(days)")
            expectFactor(result, "A1", reward, fired: reward != 0)
        }
        for (gap, penalty) in [(0, 0.0), (1, -5), (3, -15), (4, -20), (5, -25), (12, -25)] {
            let result = evaluate(input { $0.gapDays = gap })
            check(result.score == 70 + penalty, "A2 absence limit: \(gap)")
            expectFactor(result, "A2", penalty, fired: penalty != 0)
        }
        for gap in 0...3 {
            let result = evaluate(input { $0.gapDays = gap; $0.isHabitualUser = true })
            check(result.score == 70 && result.level == "A", "Habitual absence of \(gap) days is exempt")
            expectFactor(result, "A2", 0, fired: false)
        }
        let habitualFourthDay = evaluate(input { $0.gapDays = 4; $0.isHabitualUser = true })
        expectFactor(habitualFourthDay, "A2", -20, fired: true)

        let dailyPractice = evaluate(input { $0.practiceDaysLast7 = 7 })
        check(dailyPractice.score == 90 && dailyPractice.level == "S" && dailyPractice.reason == nil, "Practicing every day earns the capped reward without a load-only grade override")

        // A4 emits tomorrow's flag, while the input flag affects today's cap.
        for (today, expected) in [(199.0, false), (200, false), (200.001, true)] {
            let value = input { $0.speechSecondsToday = today; $0.speechSecondsP90 = 100 }
            let result = evaluate(value)
            check(ReadinessScoring.markHeavyYesterday(for: value) == expected && result.markHeavyYesterday == expected, "A4 strict two-times boundary")
            check(result.score == 70 && result.level == "A" && result.reason == nil, "Today's heavy load has no same-day cap")
            expectFactor(result, "A4", 0, fired: expected)
        }
        let heavyNextDay = evaluate(input { $0.heavyYesterday = true })
        check(heavyNextDay.score == 64 && heavyNextDay.level == "B" && heavyNextDay.reason == .heavyYesterday, "A4 next-day cap is 64")
        expectFactor(heavyNextDay, "decision.6", -6, fired: true)
        for value in [
            input { $0.speechSecondsToday = 300 },
            input { $0.speechSecondsP90 = 100 },
            input { $0.speechSecondsToday = .infinity; $0.speechSecondsP90 = 100 },
            input { $0.speechSecondsToday = 300; $0.speechSecondsP90 = .nan }
        ] {
            let result = evaluate(value)
            check(!ReadinessScoring.markHeavyYesterday(for: value) && !result.markHeavyYesterday, "A4 missing/nonfinite input cannot set a flag")
        }

        // B1/B2 arrays are newest first. A slope is calculated in time order.
        let rising = evaluate(input { $0.recentFinalScores = scores([78, 76, 74]) })
        expectFactor(rising, "B1", 5, fired: true)
        expectFactor(rising, "B2", 0, fired: false)
        for values in [[72.0, 71, 70], [74, 72], [70, 71, 72]] {
            expectFactor(evaluate(input { $0.recentFinalScores = scores(values) }), "B1", 0, fired: false)
        }
        let risingOLS = evaluate(input { $0.recentFinalScores = scores([74, 85, 70, 60, 70]) })
        expectFactor(risingOLS, "B1", 5, fired: true)
        let fallingOLS = evaluate(input { $0.recentFinalScores = scores([78, 60, 70, 90, 70]) })
        expectFactor(fallingOLS, "B1", 0, fired: false)
        let falling = evaluate(input { $0.recentFinalScores = scores([70, 73, 76]) })
        expectFactor(falling, "B1", 0, fired: false)
        expectFactor(falling, "B2", -10, fired: true)
        check(falling.score == 60 && falling.reason == nil, "B2 keeps its uncalibrated -10 exactly, without a decision reason")
        for values in [[70.0, 72, 74], [70, 72, 75], [70, 73, 75], [70, 74]] {
            expectFactor(evaluate(input { $0.recentFinalScores = scores(values) }), "B2", 0, fired: false)
        }
        let atFive = input { $0.recentFinalScores = scores([80, 78, 76, 74, 72]) }
        var beyondFive = atFive
        beyondFive.recentFinalScores += [.init(finalScore: .nan, canCompare: false)]
        expectFactor(evaluate(beyondFive), "B1", 5, fired: true)
        let newerDecline = evaluate(input {
            $0.recentFinalScores = scores([70, 73, 76]) + [.init(finalScore: .nan, canCompare: false)]
        })
        expectFactor(newerDecline, "B2", -10, fired: true)
        expectFactor(newerDecline, "B1", 0, fired: false)
        for invalidIndex in 0..<3 {
            let result = evaluate(input {
                $0.recentFinalScores = scores([70, 73, 76, 79, 82, 85])
                $0.recentFinalScores[invalidIndex] = .init(finalScore: [70.0, 73, 76][invalidIndex], canCompare: false)
            })
            expectFactor(result, "B1", 0, fired: false)
            expectFactor(result, "B2", 0, fired: false)
        }
        let noRefill = evaluate(input {
            $0.recentFinalScores = scores([80, 78, 76, 74, 72, 70])
            $0.recentFinalScores[4] = .init(finalScore: 72, canCompare: false)
        })
        expectFactor(noRefill, "B1", 0, fired: false)
        for invalid in [Double.nan, .infinity, -.infinity] {
            let result = evaluate(input { $0.recentFinalScores = scores([70, invalid, 76, 79, 82]) })
            expectFactor(result, "B1", 0, fired: false)
            expectFactor(result, "B2", 0, fired: false)
        }
        let overflowingDrop = evaluate(input {
            let maximum = Double.greatestFiniteMagnitude
            $0.recentFinalScores = scores([-maximum, maximum * 0.5, maximum])
        })
        expectFactor(overflowingDrop, "B2", 0, fired: false)

        for (latest, penalty) in [(55.0, 0.0), (54.999, -5), (90, 0)] {
            let result = evaluate(input {
                $0.recentFinalScores = scores([latest])
                $0.finalScoreBaseline = .init(mean: 70, stdev: 10)
            })
            expectFactor(result, "B3", penalty, fired: penalty != 0)
        }
        expectFactor(evaluate(input { $0.recentFinalScores = scores([20]) }), "B3", 0, fired: false)
        expectFactor(evaluate(input { $0.finalScoreBaseline = .init(mean: 70, stdev: 10) }), "B3", 0, fired: false)
        let latestExcluded = evaluate(input {
            $0.recentFinalScores = [.init(finalScore: 20, canCompare: false)] + scores([25, 30, 35])
            $0.finalScoreBaseline = .init(mean: 70, stdev: 10)
        })
        expectFactor(latestExcluded, "B3", 0, fired: false)
        let olderExcluded = evaluate(input {
            $0.recentFinalScores = scores([20]) + [.init(finalScore: .nan, canCompare: false)]
            $0.finalScoreBaseline = .init(mean: 70, stdev: 10)
        })
        expectFactor(olderExcluded, "B3", -5, fired: true)

        // C1 is bidirectional and strictly beyond one standard deviation.
        for (hnr, penalty, direction) in [(19.0, 0.0, 0), (21, 0, 0), (18.999, -10, -1), (21.001, -10, 1)] {
            let result = evaluate(input {
                $0.hnrRecent3 = [hnr, hnr, hnr]
                $0.hnrBaseline = .init(mean: 20, stdev: 1)
            })
            expectFactor(result, "C1", penalty, fired: penalty != 0)
            check(row(result, "C1").direction == (direction == 0 ? nil : direction), "C1 preserves anomaly direction without assigning valence")
            check(result.reason == nil, "HNR alone never triggers the voice-tired cap")
        }
        let meanBasedHNR = evaluate(input {
            $0.hnrRecent3 = [16, 20, 24]
            $0.hnrBaseline = .init(mean: 20, stdev: 1)
        })
        expectFactor(meanBasedHNR, "C1", 0, fired: false)

        for (value, penalty) in [(62.5, 0.0), (62.499, -6), (80, 0)] {
            let result = evaluate(input {
                $0.natRecent3 = [value, value, value]
                $0.natBaseline = .init(mean: 70, stdev: 5)
            })
            expectFactor(result, "C2", penalty, fired: penalty != 0)
            check(result.reason == nil, "Naturalness alone cannot trigger the voice-tired cap")
        }
        for (value, penalty) in [(11.5, 0.0), (11.501, -4), (8, 0)] {
            let result = evaluate(input {
                $0.pvRecent3 = [value, value, value]
                $0.pvBaseline = .init(mean: 10, stdev: 1)
            })
            expectFactor(result, "C3", penalty, fired: penalty != 0)
        }
        for (value, penalty) in [(80.0, 0.0), (79.999, -2), (120, 0)] {
            let result = evaluate(input { $0.vRecent3 = [value, value, value]; $0.vBaselineMean = 100 })
            expectFactor(result, "C4", penalty, fired: penalty != 0)
        }

        // Every position must be present. A fourth, valid sample cannot repair a
        // missing aligned sample, nor can compactMap turn four entries into three.
        let missingWindows: [[Double?]] = [[], [1, 1], [nil, 1, 1], [1, nil, 1], [1, 1, nil], [nil, nil, nil], [1, 1, 1, 1], [nil, 1, 1, 1], [.nan, 1, 1], [1, .infinity, 1], [1, 1, -.infinity]]
        for window in missingWindows {
            let result = evaluate(input {
                $0.hnrRecent3 = window; $0.hnrBaseline = .init(mean: 20, stdev: 1)
                $0.natRecent3 = window; $0.natBaseline = .init(mean: 70, stdev: 5)
                $0.pvRecent3 = window; $0.pvBaseline = .init(mean: -10, stdev: 1)
                $0.vRecent3 = window; $0.vBaselineMean = 100
            })
            for id in ["C1", "C2", "C3", "C4"] {
                expectFactor(result, id, 0, fired: false)
            }
            check(result.reason == nil && result.score == 70, "Missing/invalid C windows remain absent")
        }
        let oldSchema = evaluate(input { $0.hnrRecent3 = [nil, nil, nil]; $0.hnrBaseline = .init(mean: 20, stdev: 1) })
        expectFactor(oldSchema, "C1", 0, fired: false)
        let noBaselines = evaluate(input {
            $0.hnrRecent3 = [1, 1, 1]
            $0.natRecent3 = [1, 1, 1]
            $0.pvRecent3 = [100, 100, 100]
            $0.vRecent3 = [1, 1, 1]
        })
        for id in ["C1", "C2", "C3", "C4"] { expectFactor(noBaselines, id, 0, fired: false) }
        for invalidBaseline in [
            BaselineStats(mean: .nan, stdev: 1), .init(mean: .infinity, stdev: 1),
            .init(mean: 70, stdev: 0), .init(mean: 70, stdev: -1),
            .init(mean: 70, stdev: .nan), .init(mean: 70, stdev: .infinity)
        ] {
            let result = evaluate(input {
                $0.recentFinalScores = scores([20]); $0.finalScoreBaseline = invalidBaseline
                $0.hnrRecent3 = [20, 20, 20]; $0.hnrBaseline = invalidBaseline
                $0.natRecent3 = [20, 20, 20]; $0.natBaseline = invalidBaseline
                $0.pvRecent3 = [100, 100, 100]; $0.pvBaseline = invalidBaseline
            })
            for id in ["B3", "C1", "C2", "C3"] { expectFactor(result, id, 0, fired: false) }
        }
        for invalidMean in [0.0, .nan, .infinity] {
            expectFactor(evaluate(input { $0.vRecent3 = [1, 1, 1]; $0.vBaselineMean = invalidMean }), "C4", 0, fired: false)
        }
        let noInventedFloors = evaluate(input {
            $0.hnrRecent3 = [20.3, 20.3, 20.3]; $0.hnrBaseline = .init(mean: 20, stdev: 0.25)
            $0.natRecent3 = [69.98, 69.98, 69.98]; $0.natBaseline = .init(mean: 70, stdev: 0.01)
            $0.pvRecent3 = [10.02, 10.02, 10.02]; $0.pvBaseline = .init(mean: 10, stdev: 0.01)
        })
        expectFactor(noInventedFloors, "C1", -10, fired: true)
        expectFactor(noInventedFloors, "C2", -6, fired: true)
        expectFactor(noInventedFloors, "C3", -4, fired: true)
        let overflowingZ = evaluate(input {
            $0.recentFinalScores = scores([-2]); $0.finalScoreBaseline = .init(mean: 0, stdev: .leastNonzeroMagnitude)
            $0.hnrRecent3 = [2, 2, 2]; $0.hnrBaseline = .init(mean: 0, stdev: .leastNonzeroMagnitude)
            $0.natRecent3 = [-2, -2, -2]; $0.natBaseline = .init(mean: 0, stdev: .leastNonzeroMagnitude)
            $0.pvRecent3 = [2, 2, 2]; $0.pvBaseline = .init(mean: 0, stdev: .leastNonzeroMagnitude)
        })
        for id in ["B3", "C1", "C2", "C3"] { expectFactor(overflowingZ, id, 0, fired: false) }

        // Dual anomaly uses C2 OR C3. C4 does not count as corroboration.
        let lowHNR = evaluate(acousticInput())
        let highHNR = evaluate(acousticInput(hnr: 22))
        for result in [lowHNR, highHNR] {
            check(result.score == 59 && result.level == "B" && result.reason == .voiceTired, "Either HNR direction and a corroborating signal cap at 59 / B")
            expectFactor(result, "decision.4", -11, fired: true)
            check(row(result, "decision.4").formulaVersion == "dual-anomaly-v1", "Dual gate carries its own formula version")
        }
        for missingSide in ["C2", "C3"] {
            var value = acousticInput()
            if missingSide == "C2" { value.natRecent3 = [60, nil, 60] }
            if missingSide == "C3" { value.pvRecent3 = [12, nil, 12] }
            let result = evaluate(value)
            check(result.score == 59 && result.reason == .voiceTired, "A missing \(missingSide) still allows the other corroborating signal")
            expectFactor(result, missingSide, 0, fired: false)
        }
        var noHNR = acousticInput()
        noHNR.hnrRecent3 = [18, nil, 18]
        let noAnchor = evaluate(noHNR)
        check(noAnchor.reason == nil && noAnchor.score == 80, "C2 and C3 cannot replace missing HNR")
        let c4OnlyCorroboration = evaluate(input {
            $0.hnrRecent3 = [18, 18, 18]; $0.hnrBaseline = .init(mean: 20, stdev: 1)
            $0.vRecent3 = [70, 70, 70]; $0.vBaselineMean = 100
        })
        check(c4OnlyCorroboration.score == 58 && c4OnlyCorroboration.reason == nil, "C1 + C4 deduct their factors but never force a cap")

        // Priority is #7 > #4 > #6. Forced levels must not be
        // reclassified by numeric score, nor should a cap ever increase score.
        var allRules = acousticInput()
        allRules.practiceDaysLast7 = 7
        allRules.gapDays = 2
        allRules.consecutiveAbsenceDays = 16
        allRules.heavyYesterday = true
        allRules.speechSecondsToday = 300
        allRules.speechSecondsP90 = 100
        allRules.recentFinalScores = scores([80, 83, 86, 50, 45])
        allRules.finalScoreBaseline = .init(mean: 100, stdev: 5)
        allRules.vRecent3 = [70, 70, 70]
        allRules.vBaselineMean = 100
        let returning = evaluate(allRules)
        check(returning.level == "C" && returning.reason == .welcomeBack, "#7 overrides #4 and #6")
        check(returning.score == 48, "#7 preserves all computed factor contributions without a lower-priority cap")
        check(returning.markHeavyYesterday, "Daily practice and a return override still run A4's next-day flag")
        for (id, amount) in [("A1", 20.0), ("A2", -10), ("A4", 0), ("B1", 5), ("B2", -10), ("B3", -5), ("C1", -10), ("C2", -6), ("C3", -4), ("C4", -2)] {
            expectFactor(returning, id, amount, fired: true)
        }
        expectFactor(returning, "decision.7", 0, fired: true)
        let returnHigh = evaluate(input { $0.practiceDaysLast7 = 5; $0.consecutiveAbsenceDays = 14; $0.heavyYesterday = true })
        check(returnHigh.score == 90 && returnHigh.level == "C" && returnHigh.reason == .welcomeBack, "#7 is a level override, not a numeric clamp")
        for days in [13, 14] {
            let result = evaluate(input { $0.consecutiveAbsenceDays = days })
            check(result.level == (days == 14 ? "C" : "A"), "Return-state threshold is inclusive at 14 days")
        }
        var voiceAndHeavyLoad = acousticInput()
        voiceAndHeavyLoad.practiceDaysLast7 = 7
        voiceAndHeavyLoad.heavyYesterday = true
        voiceAndHeavyLoad.speechSecondsToday = 300
        voiceAndHeavyLoad.speechSecondsP90 = 100
        let voicePriority = evaluate(voiceAndHeavyLoad)
        check(voicePriority.reason == .voiceTired && voicePriority.score == 59, "#4 wins over #6")
        check(voicePriority.markHeavyYesterday, "The voice-tired cap retains today's next-day flag")
        let belowB = input { $0.gapDays = 5; $0.recentFinalScores = scores([60, 65, 70]) }
        var belowBVoice = acousticInput()
        belowBVoice.practiceDaysLast7 = 0
        belowBVoice.gapDays = 5
        let forcedVoice = evaluate(belowBVoice)
        check(forcedVoice.score == 25 && forcedVoice.level == "B" && forcedVoice.reason == .voiceTired, "#4 forces B even below 40, without increasing score")
        expectFactor(forcedVoice, "decision.4", 0, fired: true)
        var belowBHeavy = belowB
        belowBHeavy.heavyYesterday = true
        let mappedHeavy = evaluate(belowBHeavy)
        check(mappedHeavy.score == 35 && mappedHeavy.level == "C" && mappedHeavy.reason == .heavyYesterday, "#6 caps score then uses the ordinary numeric level mapping")
        expectFactor(mappedHeavy, "decision.6", 0, fired: true)

        for count in 0..<3 {
            var coldInput = allRules
            coldInput.validAssessments = count
            let cold = evaluate(coldInput)
            check(cold.isColdStart && cold.score == 70 && cold.level == "A" && cold.reason == nil, "Cold start returns 70 / A before every other rule")
            check(!cold.markHeavyYesterday, "Cold start does not run A4")
            for id in factorIDs { expectFactor(cold, id, 0, fired: false) }
            expectFactor(cold, "coldStart", 0, fired: true)
        }
        let omittedAssessmentCount = evaluate(ReadinessInput())
        check(omittedAssessmentCount.isColdStart && omittedAssessmentCount.score == 70 && omittedAssessmentCount.level == "A", "Omitting the valid-assessment count safely leaves the user in cold start")

        // Prove public constructors, values, helpers, and evaluation remain
        // usable away from MainActor under the app's default-isolation mode.
        let detachedResult = await Task.detached {
            var value = ReadinessInput(validAssessments: 3)
            value.recentFinalScores = [ScoredAssessment(finalScore: 60, canCompare: true)]
            value.finalScoreBaseline = BaselineStats(mean: 80, stdev: 5)
            let parameters = ReadinessParameters.current
            let result = ReadinessScoring.evaluate(value, parameters: parameters)
            precondition(ReadinessScoring.level(for: result.score) == result.level)
            precondition(!ReadinessScoring.markHeavyYesterday(for: value, parameters: parameters))
            return result
        }.value
        check(detachedResult.score == 65 && detachedResult.level == "A", "Sendable values and nonisolated pure functions work in a detached task")
        evaluated.append(detachedResult)

        // Evidence is an exact additive explanation: cap entries carry their
        // actual delta, while level-only overrides carry a triggered zero.
        for result in evaluated {
            check(result.score.isFinite, "An invalid optional input never contaminates the final score")
            check(result.formulaVersion == "c1-bidirectional-v1", "Every result identifies the current formula")
            check(close(70 + result.contributions.reduce(0) { $0 + $1.contribution }, result.score), "Contribution ledger reconstructs the score including caps")
            check(Set(result.contributions.map(\.factorId)).count == result.contributions.count, "Evidence rows have unique factor IDs")
            check(deletedFactorIDs.isDisjoint(with: result.contributions.map(\.factorId)), "Deleted load-only factors never appear in evidence")
            for id in factorIDs {
                check(result.contributions.filter { $0.factorId == id }.count == 1, "Each result contains exactly one \(id) row")
            }
            for contribution in result.contributions {
                let expectedVersion = contribution.factorId == "C1" ? "c1-bidirectional-v1"
                    : contribution.factorId == "decision.4" ? "dual-anomaly-v1"
                    : "readiness-v0.8-r2-uncalibrated"
                check(contribution.formulaVersion == expectedVersion, "Every contribution identifies the correct revised formula")
                if !contribution.isTriggered {
                    check(contribution.contribution == 0, "An absent factor never contributes a number")
                }
                if contribution.contribution != 0 {
                    check(contribution.isTriggered, "Every nonzero contribution identifies a triggered rule")
                }
            }
            if result.level != "A" || result.score != 70 {
                check(result.contributions.contains(where: \.isTriggered), "Each changed outcome has a triggered explanation")
            }
        }

        let repeated = ReadinessScoring.evaluate(acousticInput())
        check(repeated.score == lowHNR.score && repeated.level == lowHNR.level && repeated.reason == lowHNR.reason, "Repeated pure evaluation is deterministic")
        print("Readiness scoring: \(checks) checks passed across \(evaluated.count) evaluations (Swift 6 strict concurrency, MainActor default isolation)")
    }
}
