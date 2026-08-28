import Foundation

/// Uses the credential that Anthropic's own CLI stores, so you do not have to paste an API key.
///
/// `ant auth login` writes a profile under ~/.config/anthropic. `ant auth print-credentials
/// --access-token` prints a short-lived OAuth access token from it, which the Messages API
/// accepts as `Authorization: Bearer` together with the `oauth-2025-04-20` beta header.
///
/// This is the supported route. Flip deliberately does not ship an OAuth client id of its own:
/// signing in with someone else's first-party client, which is how several tools graft a
/// subscription onto a third-party app, breaks the provider's terms and would be published in
/// the clear in this repository anyway.
enum AnthropicCLICredentials {

    enum Failure: LocalizedError {
        case notInstalled
        case notLoggedIn(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Anthropic's CLI (ant) is not installed, so there is no login to read. Install it, run `ant auth login`, or switch the credential back to an API key."
            case .notLoggedIn(let detail):
                return "Anthropic's CLI has no active login. Run `ant auth login` in a terminal. (\(detail))"
            case .failed(let detail):
                return "Could not read the Anthropic CLI credential: \(detail)"
            }
        }
    }

    /// A GUI app inherits a bare PATH, so look where the CLI actually installs.
    private static let searchPaths = [
        "\(NSHomeDirectory())/.local/bin/ant",
        "/opt/homebrew/bin/ant",
        "/usr/local/bin/ant",
        "/usr/bin/ant"
    ]

    static func executable() -> String? {
        searchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isInstalled: Bool { executable() != nil }

    // Tokens are short lived; re-reading on every keystroke would be wasteful, and holding one
    // for long would outlive it.
    private static var cachedToken: String?
    private static var cachedAt: Date = .distantPast
    private static let cacheLifetime: TimeInterval = 240

    static func accessToken(forceRefresh: Bool = false) throws -> String {
        if !forceRefresh, let cachedToken, Date().timeIntervalSince(cachedAt) < cacheLifetime {
            return cachedToken
        }
        guard let path = executable() else { throw Failure.notInstalled }

        let result = try run(path, ["auth", "print-credentials", "--access-token"])
        let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.status == 0, !token.isEmpty else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.lowercased().contains("login") || detail.lowercased().contains("credential") {
                throw Failure.notLoggedIn(detail.isEmpty ? "exit \(result.status)" : detail)
            }
            throw Failure.failed(detail.isEmpty ? "exit \(result.status)" : detail)
        }

        cachedToken = token
        cachedAt = Date()
        return token
    }

    static func invalidate() {
        cachedToken = nil
        cachedAt = .distantPast
    }

    /// One line describing the login state, for Settings and for --doctor.
    static func statusSummary() -> String {
        guard let path = executable() else { return "ant not installed" }
        guard let result = try? run(path, ["auth", "status"]) else { return "ant found at \(path), but it could not be run" }
        let text = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        return result.status == 0 ? "logged in (\(firstLine))" : "not logged in (\(firstLine))"
    }

    private static func run(_ path: String, _ arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "")
    }
}
