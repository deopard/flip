import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @State private var testState: TestState = .idle
    @State private var accessibilityGranted = TextAccess.hasAccessibilityPermission()

    enum TestState: Equatable {
        case idle, running
        case ok(String)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                permissionBanner
                connection
                languages
                style
                shortcuts
                footer
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 580, height: 830)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibilityGranted = TextAccess.hasAccessibilityPermission()
        }
    }

    // MARK: - Permission

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(accessibilityGranted ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(accessibilityGranted ? "Accessibility access granted" : "Accessibility access needed")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(accessibilityGranted
                     ? "Flip can read your selection and paste the translation back."
                     : "Without it the shortcuts cannot read your selection or paste anything back. Turn Flip on under Privacy & Security, then Accessibility. If the switch is already on, macOS decided this at launch and will not change its mind while Flip is running: relaunch to pick up the permission.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !accessibilityGranted {
                VStack(spacing: 6) {
                    Button("Open Settings") {
                        TextAccess.requestAccessibilityPermission()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                    Button("Already on? Relaunch") { Relauncher.relaunch() }
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((accessibilityGranted ? Color.green : Color.orange).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sections

    private var connection: some View {
        section("Connection", "Your key is stored in the macOS login Keychain, never in a plain file.") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 9) {
                GridRow {
                    label("Provider")
                    Picker("", selection: Binding(get: { settings.provider },
                                                  set: { settings.providerChanged(to: $0) })) {
                        ForEach(Provider.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    label("Base URL")
                    TextField("", text: $settings.baseURL).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    label("API key")
                    SecureField(settings.provider.keyHint, text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    label("Model")
                    HStack(spacing: 8) {
                        ComboBoxField(text: $settings.model,
                                      options: settings.provider.suggestedModels,
                                      placeholder: "model id")
                            .frame(width: 240, height: 24)
                        Text("Pick one or type any model id.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
                GridRow {
                    label("Effort")
                    HStack(spacing: 8) {
                        ComboBoxField(text: $settings.effort,
                                      options: settings.provider.effortLevels,
                                      placeholder: "effort")
                            .frame(width: 240, height: 24)
                        Text("How hard the model thinks.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    HStack(spacing: 9) {
                        Button("Test connection") { runTest() }
                            .disabled(testState == .running || settings.apiKey.isEmpty)
                        testResult
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var testResult: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .ok(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.system(size: 11)).lineLimit(2)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.system(size: 11))
                .lineLimit(3).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var languages: some View {
        section("Languages", "Pick \"Auto swap\" in either row and Flip flips between the two languages below, based on what you selected.") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 9) {
                GridRow {
                    label("Replace \(settings.replaceHotkey.display)")
                    languagePicker($settings.replaceLanguage)
                }
                GridRow {
                    label("Peek \(settings.peekHotkey.display)")
                    languagePicker($settings.peekLanguage)
                }
            }
        }
    }

    private var style: some View {
        section("Custom style prompt",
                "Added to every request. Example: \"Business casual. Short sentences. Never use exclamation marks.\"") {
            TextEditor(text: $settings.stylePrompt)
                .font(.system(size: 12))
                .frame(height: 80)
                .padding(5)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }

    private var shortcuts: some View {
        section("Shortcuts", "Click a shortcut and press the keys you want. It must include command, option or control.") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                shortcutRow($settings.replaceHotkey, fallback: .defaultReplace,
                            "Translate the selection and replace it in place. With nothing selected, translates the whole text field.")
                shortcutRow($settings.peekHotkey, fallback: .defaultPeek,
                            "Translate the selection and show it in a popup. Nothing on screen changes.")
            }
        }
    }

    private func shortcutRow(_ binding: Binding<HotkeyBinding>,
                             fallback: HotkeyBinding,
                             _ description: String) -> some View {
        let registration = HotkeyManager.shared.registration(for: binding.wrappedValue)
        let broken = registration != nil && registration?.isOK == false
        return GridRow {
            HotkeyRecorder(binding: binding, fallback: fallback)
                .gridColumnAlignment(.trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(description)
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if broken, let registration {
                    Label("This shortcut is \(registration.explanation). Nothing will happen when you press it. Pick another one.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var footer: some View {
        Text("History is stored on this Mac at ~/Library/Application Support/Flip/history.json")
            .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            .textSelection(.enabled)
    }

    // MARK: - Helpers

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .gridColumnAlignment(.trailing)
    }

    private func languagePicker(_ binding: Binding<String>) -> some View {
        Picker("", selection: binding) {
            Text(Language.autoSwap).tag(Language.autoSwap)
            Divider()
            ForEach(Language.all, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(width: 240)
    }

    private func section<Content: View>(_ title: String, _ note: String?,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let note {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func runTest() {
        testState = .running
        let probe = "안녕하세요. 오늘 회의는 3시에 시작합니다."
        Task {
            do {
                let out = try await Translator.translate(text: probe, settings: settings, mode: .replace)
                testState = .ok("\(out.latencyMs) ms \u{2192} \(out.text.prefix(60))")
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }
}
