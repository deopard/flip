import Foundation
import Combine

// MARK: - Provider

enum Provider: String, CaseIterable, Codable, Identifiable {
    case openai
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI (and OpenAI-compatible)"
        case .anthropic: return "Anthropic (Claude)"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        }
    }

    /// Reasoning effort. Both providers take one, under different names, and both reject
    /// values a given model does not support, so this is a plain list plus an opt out.
    var effortLevels: [String] {
        switch self {
        case .openai: return [Settings.effortUnset, "minimal", "low", "medium", "high"]
        case .anthropic: return [Settings.effortUnset, "low", "medium", "high", "xhigh", "max"]
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .openai: return ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-5.5"]
        case .anthropic: return ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"]
        }
    }

    var keyHint: String {
        switch self {
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        }
    }
}

// MARK: - Languages

enum CredentialSource: String, CaseIterable, Codable, Identifiable {
    case apiKey
    case cliLogin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apiKey: return "API key"
        case .cliLogin: return "Anthropic CLI login (ant)"
        }
    }
}

enum Language {
    /// Sentinel used by both direction pickers: translate into whichever of the two
    /// configured languages the input is NOT already written in.
    static let autoSwap = "Auto swap"

    static let all: [String] = [
        "English", "Korean", "Japanese", "Chinese (Simplified)", "Chinese (Traditional)",
        "Spanish", "French", "German", "Portuguese (Brazil)", "Italian", "Dutch",
        "Russian", "Vietnamese", "Thai", "Indonesian", "Hindi", "Arabic", "Turkish",
        "Polish", "Swedish"
    ]
}

// MARK: - Settings

final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var provider: Provider { didSet { defaults.set(provider.rawValue, forKey: "provider") } }
    @Published var baseURL: String { didSet { defaults.set(baseURL, forKey: "baseURL") } }
    @Published var model: String { didSet { defaults.set(model, forKey: "model") } }
    /// Sent as `reasoning_effort` to OpenAI and as `output_config.effort` to Anthropic.
    @Published var effort: String { didSet { defaults.set(effort, forKey: "effort") } }
    /// Anthropic only. `cliLogin` reuses the credential `ant auth login` stored, so no key is
    /// pasted anywhere.
    @Published var credentialSource: CredentialSource {
        didSet { defaults.set(credentialSource.rawValue, forKey: "credentialSource") }
    }

    /// Target language for the replace shortcut (option+command+apostrophe).
    @Published var replaceLanguage: String { didSet { defaults.set(replaceLanguage, forKey: "replaceLanguage") } }
    /// Target language for the peek shortcut (option+command+semicolon).
    @Published var peekLanguage: String { didSet { defaults.set(peekLanguage, forKey: "peekLanguage") } }

    @Published var stylePrompt: String { didSet { defaults.set(stylePrompt, forKey: "stylePrompt") } }
    @Published var launchAtLoginEnabled: Bool { didSet { defaults.set(launchAtLoginEnabled, forKey: "launchAtLogin") } }

    @Published var replaceHotkey: HotkeyBinding { didSet { Settings.store(replaceHotkey, forKey: "replaceHotkey") } }
    @Published var peekHotkey: HotkeyBinding { didSet { Settings.store(peekHotkey, forKey: "peekHotkey") } }

    private static func store(_ binding: HotkeyBinding, forKey key: String) {
        guard let data = try? JSONEncoder().encode(binding) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadBinding(_ key: String, default fallback: HotkeyBinding) -> HotkeyBinding {
        guard let data = UserDefaults.standard.data(forKey: key),
              let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else { return fallback }
        return binding
    }

    /// Stored in the login Keychain, never in UserDefaults.
    @Published var apiKey: String { didSet { Keychain.set(Settings.sanitize(apiKey), account: keychainAccount) } }

    static let effortUnset = "Not set"

    private var keychainAccount: String { "apiKey.\(provider.rawValue)" }

    /// A pasted key often carries a trailing newline, a stray space, or an invisible
    /// character. Any of those makes Foundation drop the whole Authorization header, and the
    /// API then reports a missing key rather than a bad one. Strip anything that cannot
    /// legally appear in an HTTP header value.
    static func sanitize(_ raw: String) -> String {
        String(raw.unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F })
    }

    /// The key as it should be sent. Always use this, never `apiKey`, when building a request.
    var usableAPIKey: String { Settings.sanitize(apiKey) }

    /// True when this configuration takes its credential from the Anthropic CLI rather than a
    /// pasted key. Only Anthropic offers this; OpenAI has no supported equivalent.
    var usesCLILogin: Bool { provider == .anthropic && credentialSource == .cliLogin }

    private init() {
        let p = Provider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .openai
        provider = p
        baseURL = defaults.string(forKey: "baseURL") ?? p.defaultBaseURL
        model = defaults.string(forKey: "model") ?? "gpt-5.6-luna"
        effort = defaults.string(forKey: "effort") ?? "medium"
        credentialSource = CredentialSource(rawValue: defaults.string(forKey: "credentialSource") ?? "") ?? .apiKey
        replaceLanguage = defaults.string(forKey: "replaceLanguage") ?? "English"
        peekLanguage = defaults.string(forKey: "peekLanguage") ?? "Korean"
        stylePrompt = defaults.string(forKey: "stylePrompt") ?? ""
        launchAtLoginEnabled = defaults.bool(forKey: "launchAtLogin")
        replaceHotkey = Settings.loadBinding("replaceHotkey", default: .defaultReplace)
        peekHotkey = Settings.loadBinding("peekHotkey", default: .defaultPeek)
        apiKey = Settings.sanitize(Keychain.get(account: "apiKey.\(p.rawValue)") ?? "")
    }

    /// Called when the provider changes so the key/base URL follow it.
    func providerChanged(to newProvider: Provider) {
        provider = newProvider
        baseURL = newProvider.defaultBaseURL
        apiKey = Settings.sanitize(Keychain.get(account: "apiKey.\(newProvider.rawValue)") ?? "")
        if !newProvider.suggestedModels.contains(model) {
            model = newProvider.suggestedModels[0]
        }
        if !newProvider.effortLevels.contains(effort) {
            effort = Settings.effortUnset
        }
    }

    /// Resolves "Auto swap" against the two configured languages.
    func resolvedTarget(for mode: Mode) -> ResolvedTarget {
        let raw = (mode == .replace) ? replaceLanguage : peekLanguage
        if raw == Language.autoSwap {
            let a = (replaceLanguage == Language.autoSwap) ? "English" : replaceLanguage
            let b = (peekLanguage == Language.autoSwap) ? "Korean" : peekLanguage
            return .swap(a, b)
        }
        return .fixed(raw)
    }
}

enum ResolvedTarget {
    case fixed(String)
    case swap(String, String)

    var label: String {
        switch self {
        case .fixed(let l): return l
        case .swap(let a, let b): return "\(a) / \(b)"
        }
    }
}

enum Mode: String, Codable {
    case replace
    case peek

    var label: String { self == .replace ? "Replace" : "Peek" }
}
