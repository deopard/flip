import Foundation
import Combine

// MARK: - Provider

enum Provider: String, CaseIterable, Codable, Identifiable {
    case openai
    case openrouter
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI (and OpenAI-compatible)"
        case .openrouter: return "OpenRouter (everything else)"
        case .anthropic: return "Anthropic (Claude)"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        }
    }

    /// Reasoning effort. Both providers take one, under different names, and both reject
    /// values a given model does not support, so this is a plain list plus an opt out.
    var effortLevels: [String] {
        switch self {
        case .openai, .openrouter: return [Settings.effortUnset, "minimal", "low", "medium", "high"]
        case .anthropic: return [Settings.effortUnset, "low", "medium", "high", "xhigh", "max"]
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .openai: return ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-5.5"]
        case .openrouter:
            // Ordered by measured round trip, not by price, because the two do not track each
            // other: the cheapest model here was also the slowest by five times. Latencies are
            // medians of three runs translating the same Korean message through OpenRouter,
            // reproducible with --bench. Prices are dollars per million tokens weighted 3:1
            // input to output, from OpenRouter's own model list.
            return [
                "z-ai/glm-5.3-flash",            //  2337 ms   0.119
                "openai/gpt-5.6-luna",           //  2805 ms   0.450
                "google/gemini-2.5-flash-lite",  //  4604 ms   0.175
                "deepseek/deepseek-v4-flash",    //  7832 ms   0.107
                "qwen/qwen3.7-flash",            // 12255 ms   0.055
                "openai/gpt-5-nano",             // 15212 ms   0.137
                "anthropic/claude-haiku-4.5",    //  not measured   2.000
                "google/gemini-3.1-flash-lite"   //  not measured   0.562
            ]
        case .anthropic: return ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"]
        }
    }

    /// What a key from this provider starts with, where that is reliable enough to check.
    var keyPrefix: String? {
        switch self {
        case .openai: return nil            // several shapes in circulation, and gateways differ
        case .openrouter: return "sk-or-"
        case .anthropic: return "sk-ant-"
        }
    }

    var keyHint: String {
        switch self {
        case .openai: return "sk-..."
        case .openrouter: return "sk-or-v1-..."
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
        "Cantonese", "Spanish", "Spanish (Latin America)", "Portuguese (Brazil)",
        "Portuguese (Portugal)", "French", "French (Canada)", "German", "Italian", "Dutch",
        "Russian", "Ukrainian", "Polish", "Czech", "Slovak", "Hungarian", "Romanian",
        "Bulgarian", "Greek", "Turkish", "Arabic", "Hebrew", "Persian", "Hindi", "Bengali",
        "Urdu", "Tamil", "Telugu", "Marathi", "Gujarati", "Punjabi", "Kannada", "Malayalam",
        "Thai", "Vietnamese", "Indonesian", "Malay", "Filipino", "Burmese", "Khmer", "Lao",
        "Mongolian", "Nepali", "Sinhala", "Swedish", "Norwegian", "Danish", "Finnish",
        "Icelandic", "Estonian", "Latvian", "Lithuanian", "Serbian", "Croatian", "Bosnian",
        "Slovenian", "Albanian", "Macedonian", "Georgian", "Armenian", "Azerbaijani",
        "Kazakh", "Uzbek", "Swahili", "Amharic", "Yoruba", "Igbo", "Hausa", "Zulu",
        "Afrikaans", "Catalan", "Basque", "Galician", "Welsh", "Irish", "Latin"
    ]
}

// MARK: - Settings

/// Carries a value out of the background read without capturing a mutable local.
private final class KeyBox: @unchecked Sendable { var value: String? }

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

    @Published var hotkey: HotkeyBinding { didSet { Settings.store(hotkey, forKey: "hotkey") } }

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
    /// Stored in the login Keychain, never in a plain file.
    ///
    /// Never read during init. A Keychain item's access control is bound to the path of the app
    /// that created it, so moving the app makes macOS put up a password dialog, and
    /// `SecItemCopyMatching` blocks until it is answered. Doing that on the main thread during
    /// launch freezes the whole app, menu bar included, behind a dialog the user may not have
    /// noticed.
    @Published var apiKey: String {
        didSet {
            guard apiKeyLoaded else { return }      // do not write back what we just read
            let value = Settings.sanitize(apiKey)
            let account = keychainAccount
            DispatchQueue.global(qos: .utility).async { Keychain.set(value, account: account) }
        }
    }

    private var apiKeyLoaded = false
    private let keychainQueue = DispatchQueue(label: "video.cutback.flip.keychain", qos: .userInitiated)

    static let effortUnset = "Not set"

    private var keychainAccount: String { "apiKey.\(provider.rawValue)" }

    /// A pasted key often carries a trailing newline or a stray space. Either makes Foundation
    /// drop the whole Authorization header, and the API then reports a missing key rather than
    /// a bad one. Trim the ends and drop control characters; leave everything else, so a paste
    /// that was not a key stays visibly wrong instead of being quietly filed into shape.
    static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F })
    }

    /// Why the stored value cannot be an API key, or nil if it looks like one.
    ///
    /// The field shows dots, so a wrong paste is invisible: a clipboard full of something else
    /// gets stored and every request fails with an error about the key that reads as though the
    /// key were merely wrong. These checks are deliberately shallow. They catch pasting the
    /// wrong thing, not a key with a typo in it, which only the API can tell you about.
    var keyProblem: String? {
        // Blocking read, for the same reason --doctor uses one: the published property is
        // filled in asynchronously and a one-shot process checks before it lands.
        let key = usableAPIKeyBlocking()
        guard !key.isEmpty else { return nil }

        if !key.allSatisfy({ $0.isASCII }) {
            return "This is not an API key: it contains characters outside the Latin alphabet. Something else was pasted here."
        }
        if key.contains(where: { $0.isWhitespace }) {
            return "This is not an API key: it contains spaces. Something else was pasted here."
        }
        if key.count < 20 {
            return "This is too short to be an API key (\(key.count) characters)."
        }
        if key.count > 400 {
            return "This is far too long to be an API key (\(key.count) characters). Something else was pasted here."
        }
        if let expected = provider.keyPrefix, !key.hasPrefix(expected) {
            return "\(provider.displayName) keys start with \(expected). This one starts with \(key.prefix(min(6, key.count)))."
        }
        return nil
    }

    /// Writes the key and waits for it, for callers with no run loop to publish into. The
    /// property's own setter only writes once a background read has landed, which a one-shot
    /// command-line process never gives it time to do.
    func storeAPIKey(_ raw: String) {
        let value = Settings.sanitize(raw)
        Keychain.set(value, account: keychainAccount)
        apiKeyLoaded = true
        apiKey = value
    }

    /// Reads the key off the main thread and publishes it. Safe to call repeatedly.
    func loadAPIKey() {
        let account = keychainAccount
        keychainQueue.async { [weak self] in
            let value = Settings.sanitize(Keychain.get(account: account) ?? "")
            DispatchQueue.main.async {
                guard let self, self.keychainAccount == account else { return }
                self.apiKeyLoaded = true
                self.apiKey = value
            }
        }
    }

    /// The key as it should be sent, waiting for the Keychain if it has not been read yet.
    /// Never call this from the main thread.
    ///
    /// Bounded, because the wait is not always short. A Keychain item's access control names the
    /// executable that created it, so installing a new build makes macOS put up a password
    /// dialog and hold the read until someone answers. A command-line process has no window to
    /// show that in, and would otherwise sit there indefinitely with no output at all.
    func usableAPIKeyBlocking(timeout: TimeInterval = 6) -> String {
        if apiKeyLoaded { return Settings.sanitize(apiKey) }

        let account = keychainAccount
        let semaphore = DispatchSemaphore(value: 0)
        let box = KeyBox()
        DispatchQueue.global(qos: .userInitiated).async {
            box.value = Keychain.get(account: account)
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            keychainTimedOut = true
            return ""
        }
        return Settings.sanitize(box.value ?? "")
    }

    /// True when the last Keychain read gave up waiting, which means a dialog is on screen.
    private(set) var keychainTimedOut = false

    static let keychainBlockedMessage = "macOS is asking for your login password before it will hand the API key to this copy of Flip, and is waiting on a dialog somewhere on screen. Answer it and choose Always Allow. A Keychain item is bound to the exact program that saved it, so a new build has to be let in once."

    /// What the interface shows. Empty until `loadAPIKey()` has finished.
    var usableAPIKey: String { Settings.sanitize(apiKey) }

    /// True when this configuration takes its credential from the Anthropic CLI rather than a
    /// pasted key. Only Anthropic offers this; OpenAI has no supported equivalent.
    var usesCLILogin: Bool { provider == .anthropic && credentialSource == .cliLogin }

    private init() {
        let p = Provider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .openrouter
        provider = p
        baseURL = defaults.string(forKey: "baseURL") ?? p.defaultBaseURL
        // The provider's first preset is its default, so the two cannot drift apart.
        model = defaults.string(forKey: "model") ?? p.suggestedModels[0]
        effort = defaults.string(forKey: "effort") ?? "medium"
        credentialSource = CredentialSource(rawValue: defaults.string(forKey: "credentialSource") ?? "") ?? .apiKey
        replaceLanguage = defaults.string(forKey: "replaceLanguage") ?? "English"
        peekLanguage = defaults.string(forKey: "peekLanguage") ?? "Korean"
        stylePrompt = defaults.string(forKey: "stylePrompt") ?? ""
        launchAtLoginEnabled = defaults.bool(forKey: "launchAtLogin")
        hotkey = Settings.loadBinding("hotkey", default: Settings.loadBinding("autoHotkey", default: .standard))
        apiKey = ""                                  // filled in by loadAPIKey(), off the main thread
    }

    /// Called when the provider changes so the key/base URL follow it.
    func providerChanged(to newProvider: Provider) {
        provider = newProvider
        baseURL = newProvider.defaultBaseURL
        apiKeyLoaded = false
        apiKey = ""
        loadAPIKey()
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
