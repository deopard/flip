import AppKit
import Foundation

nonisolated(unsafe) var flipDelegate: AppDelegate?

let arguments = Array(CommandLine.arguments.dropFirst())
nonisolated(unsafe) let flipArguments = arguments

// Stores the API key without needing the menu bar icon. Reads from stdin so the key
// never lands in shell history or in the process list.
//   Flip --set-key
if arguments.first == "--set-key" {
    FileHandle.standardError.write(Data("Paste the API key for provider '\(Settings.shared.provider.rawValue)' and press return.\nAn empty line clears the stored key.\n".utf8))
    let line = (readLine(strippingNewline: true) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    Settings.shared.apiKey = line
    let stored = Settings.shared.apiKey
    if line.isEmpty {
        FileHandle.standardError.write(Data("cleared the stored key\n".utf8))
        exit(0)
    }
    FileHandle.standardError.write(Data("stored \(stored.count) characters in the login Keychain\n".utf8))
    exit(stored.isEmpty ? 1 : 0)
}

func describePopup(_ label: String, _ frame: NSRect?) {
    guard let frame else { print("\(label): no panel"); return }
    let padded = label.padding(toLength: 18, withPad: " ", startingAt: 0)
    print("\(padded) x=\(Int(frame.origin.x))  top=\(Int(frame.origin.y + frame.height))  height=\(Int(frame.height))")
}

// Shows the result popup and toggles the original, printing the frame at each step.
// The top edge must not move: clicking Original resizes the panel, it does not reposition it.
//   Flip --popup-demo
if arguments.first == "--popup-demo" {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)


        PopupPanel.shared.showResult(
            source: "We are seeing a spike in failed exports on the desktop client since the 3.2 release, and a few customers have already written in about it.",
            translated: "3.2 릴리스 이후 데스크톱 클라이언트에서 내보내기 실패가 급증하고 있습니다.",
            meta: "demo")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        describePopup("translation only", PopupPanel.shared.currentFrame)

        PopupPanel.shared.toggleOriginalForTesting()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        describePopup("original shown", PopupPanel.shared.currentFrame)

        PopupPanel.shared.toggleOriginalForTesting()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        describePopup("original hidden", PopupPanel.shared.currentFrame)
    }
    exit(0)
}

// Prints every precondition the shortcuts depend on.
//   Flip --doctor
if arguments.first == "--doctor" {
    MainActor.assumeIsolated {
        NSApplication.shared.setActivationPolicy(.accessory)
        Doctor.run()
    }
    exit(0)
}

// Renders every interface surface to PNG without needing a visible screen.
//   Flip --screenshot <directory>
if arguments.first == "--screenshot" {
    let directory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : FileManager.default.currentDirectoryPath)
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        do {
            try ScreenshotRenderer.renderAll(into: directory)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    exit(0)
}

// Headless modes, so the translation path can be checked without the menu bar UI:
//   Flip --prompt [--peek]              print the exact system prompt that will be sent
//   Flip --translate "text" [--peek]    run one translation and print the result
if arguments.first == "--prompt" || arguments.first == "--translate" {
    let mode: Mode = arguments.contains("--peek") ? .peek : .replace
    let settings = Settings.shared

    if arguments.first == "--prompt" {
        print(Translator.systemPrompt(target: settings.resolvedTarget(for: mode),
                                      style: settings.stylePrompt))
        exit(0)
    }

    guard arguments.count > 1 else {
        FileHandle.standardError.write(Data("usage: Flip --translate \"text\" [--peek]\n".utf8))
        exit(2)
    }

    let input = arguments[1]
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0

    Task {
        do {
            let out = try await Translator.translate(text: input, settings: settings, mode: mode)
            print(out.text)
            FileHandle.standardError.write(Data("[\(out.model), \(out.latencyMs) ms, into \(settings.resolvedTarget(for: mode).label)]\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exitCode = 1
        }
        semaphore.signal()
    }

    semaphore.wait()
    exit(exitCode)
}

// One menu bar instance only, otherwise a second copy would fight for the same hotkeys.
if let bundleID = Bundle.main.bundleIdentifier {
    let mine = ProcessInfo.processInfo.processIdentifier
    let others = NSWorkspace.shared.runningApplications.filter {
        $0.bundleIdentifier == bundleID && $0.processIdentifier != mine && !$0.isTerminated
    }
    if !others.isEmpty && !arguments.contains("--relaunched") {
        // Launching again is how you reach Settings when a menu bar manager has
        // collapsed the icon out of sight.
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("video.cutback.flip.openSettings"), object: nil, deliverImmediately: true)
        others.first?.activate()
        exit(0)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    flipDelegate = delegate            // NSApplication.delegate is weak
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
    app.run()
}
