import Foundation

/// `Flip --bench [runs] [model,model,...]` translates the same text with each model and prints
/// median latency next to the output, so choosing one is a measurement rather than an opinion.
///
/// Runs against whatever provider and key are configured. Every run costs money.
enum Bench {

    static let defaultSample = """
    🚨 [Action Needed] – Please categorise your card transactions by today

    @Tom @Ducky Chang @Jay

    Hi all, could you check your transactions and add a category to any that don't have one yet?
    This keeps our expense records accurate and makes the monthly close much faster.

    *Once you're done, please leave a :white_check_mark: as a reply.
    """

    static func run(runs: Int, models: [String], text: String) async {
        let settings = Settings.shared
        let original = settings.model
        defer { settings.model = original }

        print("provider  \(settings.provider.rawValue)")
        print("effort    \(settings.effort)")
        print("target    \(settings.resolvedTarget(for: .replace).label)")
        print("runs      \(runs) per model")
        print("input     \(text.count) characters, \(text.split(separator: "\n", omittingEmptySubsequences: false).count) lines")
        print(String(repeating: "-", count: 74))

        var results: [(model: String, median: Int, spread: String, output: String?, error: String?)] = []

        for model in models {
            settings.model = model
            var timings: [Int] = []
            var lastOutput: String?
            var failure: String?

            for _ in 0..<runs {
                do {
                    let outcome = try await Translator.translate(text: text, settings: settings, mode: .replace)
                    timings.append(outcome.latencyMs)
                    lastOutput = outcome.text
                } catch {
                    failure = error.localizedDescription
                    break
                }
            }

            if let failure {
                print(String(format: "%-34s  FAILED  %@", (model as NSString).utf8String!, failure))
                results.append((model, 0, "", nil, failure))
                continue
            }

            let sorted = timings.sorted()
            let median = sorted[sorted.count / 2]
            let spread = "\(sorted.first ?? 0)-\(sorted.last ?? 0)"
            print(String(format: "%-34s  %5d ms median   range %@", (model as NSString).utf8String!, median, spread))
            results.append((model, median, spread, lastOutput, nil))
        }

        print(String(repeating: "-", count: 74))
        print("\nTranslations, so you can judge whether the cheap ones are good enough:\n")
        for result in results where result.output != nil {
            print("=== \(result.model)  (\(result.median) ms) ===")
            print(result.output!)
            print()
        }

        let ok = results.filter { $0.error == nil }
        if let fastest = ok.min(by: { $0.median < $1.median }) {
            print("Fastest: \(fastest.model) at \(fastest.median) ms median.")
        }
        print("Latency is not quality. Read the outputs above before switching.")
    }
}
