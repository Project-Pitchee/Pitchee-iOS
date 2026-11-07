// Fixed input scenarios exercise production ReadinessScoring with each Core's
// measured HNR/naturalness. They are not estimates of a real person's readiness.
import Foundation

@main
enum CoreReadinessProbe {
    struct Sample: Decodable {
        let file: String
        let hnr: Double?
        let naturalness: Double
        let speechSeconds: Double
    }
    static func row(_ result: ReadinessResult) -> [String: Any] {
        ["score": result.score, "level": result.level,
         "reason": result.reason?.rawValue as Any? ?? NSNull(),
         "formulaVersion": result.formulaVersion,
         "contributions": result.contributions.map { factor -> [String: Any] in
             ["id": factor.factorId, "delta": factor.contribution,
              "triggered": factor.isTriggered,
              "direction": factor.direction as Any? ?? NSNull()]
         }]
    }
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "readiness-probe", code: 2)
        }
        let samples = try JSONDecoder().decode([Sample].self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        var result: [String: Any] = [:]
        for sample in samples {
            var input = ReadinessInput(validAssessments: 3)
            input.hnrBaseline = BaselineStats(mean: 15, stdev: 1)
            input.natBaseline = BaselineStats(mean: 80, stdev: 2)
            input.hnrRecent3 = Array(repeating: sample.hnr, count: 3)
            input.natRecent3 = Array(repeating: sample.naturalness, count: 3)
            input.speechSecondsToday = sample.speechSeconds
            result[sample.file] = row(ReadinessScoring.evaluate(input))
        }
        var synthetic = ReadinessInput(validAssessments: 3)
        synthetic.hnrBaseline = BaselineStats(mean: 15, stdev: 1)
        synthetic.hnrRecent3 = [12, 12, 12]
        let present = ReadinessScoring.evaluate(synthetic)
        synthetic.hnrRecent3 = [nil, nil, nil]
        let absent = ReadinessScoring.evaluate(synthetic)
        precondition(present.contributions.contains { $0.factorId == "C1" && $0.isTriggered })
        precondition(!absent.contributions.contains { $0.factorId == "C1" && $0.isTriggered })
        precondition(absent.score - present.score == 10)
        result["synthetic-hnr-present"] = row(present)
        result["synthetic-hnr-absent"] = row(absent)
        synthetic.natBaseline = BaselineStats(mean: 80, stdev: 2)
        synthetic.natRecent3 = [70, 70, 70]
        let missingDual = ReadinessScoring.evaluate(synthetic)
        synthetic.hnrRecent3 = [12, 12, 12]
        let fullDual = ReadinessScoring.evaluate(synthetic)
        precondition(fullDual.reason == .voiceTired)
        precondition(missingDual.reason != .voiceTired)
        result["synthetic-dual-hnr-present"] = row(fullDual)
        result["synthetic-dual-hnr-absent"] = row(missingDual)
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
