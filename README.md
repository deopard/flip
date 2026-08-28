# Flip

A macOS menu bar app that translates the text you have selected, in any app, with a keyboard shortcut. No Electron, no dependencies, no telemetry: about 1,900 lines of Swift against system frameworks, and your API key stays in your own Keychain.

MIT licensed. Requires macOS 14 or later and the Xcode Command Line Tools.

```
git clone <this repo> && cd flip
./scripts/create-signing-identity.sh   # optional, stops repeated permission prompts
./scripts/build.sh
open build/Flip.app
```

One shortcut, `⌥⌘'` (option command apostrophe). It decides what you meant:

- The selection is inside something you can type into: it **replaces the text in place**. With a cursor in a field and nothing selected, it takes the whole field.
- Anything else: it **shows the translation in a popup** and changes nothing on screen.

Write a Slack message in Korean, select it, press the shortcut, and the box now holds the English. Select a message you are reading, press the same shortcut, and a panel shows the Korean.

You can switch to two separate shortcuts in Settings if you would rather say which one you mean.

### How it decides

Keyboard focus alone is not enough. In Slack, Discord, Notion and most chat apps, focus stays in the composer while you select text in a message you are reading, so deciding on focus would paste a translation of what you were reading into the box you were writing in.

What separates the two is where the selection is:

1. If the focused element reports the selection as its own, that settles it: inside an editable element means replace, otherwise popup. No clipboard is touched.
2. Otherwise Flip copies to find out what is selected, then checks whether the focused element's own contents contain it. If they do, the selection was inside the field after all. If not, the selection is elsewhere and it shows a popup.
3. Where it cannot tell, it shows the popup. Nothing gets overwritten on a guess.

A field the app marks as secure, such as a password box, is refused outright under every shortcut. Flip will neither read it nor paste over it.

Check what it will do in any app with `--probe-focus`, which reports the focused element's role, whether its value can be written, and the decision that follows:

```
/Applications/Flip.app/Contents/MacOS/Flip --probe-focus 5
```

Measured with it: Slack's composer is an `AXTextArea` with a settable value, Notes is the same, a browser reading a page hands back an `AXButton` whose value cannot be written. Browsers also report a selected text range on elements that are plainly not text, which is why a selection range on its own counts for nothing.

## Install

```
./scripts/build.sh
open build/Flip.app
```

The build needs no dependencies and no Xcode project. It uses the Swift compiler that ships with the Xcode Command Line Tools.

To keep it around, and to be able to launch it from Spotlight:

```
./scripts/install.sh
```

That builds it, copies it to `/Applications`, and reopens it. Spotlight does not index apps sitting in a build directory, which is why running it from there works but searching for it does not. The signature does not change, so the Accessibility permission carries over.

## First run: two things to set

**1. Accessibility permission.** macOS will ask on first launch. Open System Settings, go to Privacy & Security, then Accessibility, and turn Flip on. Without it the app cannot read your selection or paste the translation back.

If the build is signed ad hoc, every rebuild produces a different signature, macOS treats it as a different app, and it drops this permission and re-asks for your Keychain password. Run this once to stop that:

```
./scripts/create-signing-identity.sh
./scripts/build.sh
```

It puts a self-signed certificate called "Flip Dev" in your login Keychain and signs every build with it. The signature identity then stays the same across rebuilds, so both prompts stop. To undo it, delete "Flip Dev" in Keychain Access.

**2. API key.** Click the menu bar icon, choose Settings, pick your provider, and paste your key. The key is stored in the macOS login Keychain, not in a file. Press "Test connection" to confirm it works before relying on the shortcuts.

## Settings

- **Provider** — OpenAI (or anything that speaks the OpenAI chat completions format) or Anthropic.
- **Credential** (Anthropic only) — an API key, or the login Anthropic's own CLI already holds. Picking the CLI login means no key is pasted anywhere: Flip asks `ant auth print-credentials --access-token` for a short-lived token and sends it as `Authorization: Bearer` with the `oauth-2025-04-20` beta header. Set it up with `ant auth login`. Whether that draws on a subscription or on API credits depends on the account, not on Flip.

  There is no equivalent for OpenAI. A ChatGPT subscription does not include API access, and there is no supported way for a third-party app to use one. Flip ships no OAuth client id of its own: signing in with another product's first-party client, which is how several tools graft a subscription onto a third-party app, breaks the provider's terms, and in an open repository the client id would be published in the clear.
- **Base URL** — prefilled per provider; change it to point at a compatible gateway.
- **Model** — free text, with presets per provider. Default is `gpt-5.6-luna`.
- **Effort** — how hard the model thinks. Sent as `reasoning_effort` to OpenAI and as `output_config.effort` to Anthropic. Default `medium`. If a model does not accept one, Flip retries without it rather than failing.
- **Replace shortcut translates into** — default English.
- **Peek shortcut translates into** — default Korean.
- **Auto swap** — pick this in either list and the app flips between your two configured languages based on what you selected.
- **Custom style prompt** — free text appended to every request. For example: *Business casual. Short sentences. Never use exclamation marks.*

## History

Menu bar icon, then History. Every translation is recorded: time, mode, source app, the original, the translation, the model, and how long the request took. Searchable, copyable, deletable.

Stored at `~/Library/Application Support/Flip/history.json`, on your machine only.

## When a shortcut does nothing

Run the built-in diagnostic **while Flip is running**:

```
build/Flip.app/Contents/MacOS/Flip --doctor
```

It reports, and tells you how to fix, each of: Accessibility permission, whether each shortcut actually registered or is owned by another app, whether an API key is stored, the provider and model in use, and whether a menu bar manager such as Ice is hiding the status icon.

Accessibility and hotkey lines come from a status file the running app writes, not from a check inside the diagnostic. That is deliberate. Accessibility trust belongs to the process that asks: a command-line tool started from a terminal that already holds the permission inherits it and will report "granted" no matter what the app bundle is actually allowed to do. Only the running app can answer for the running app.

## Storing the key from the terminal

If a menu bar manager has hidden the icon, you do not need it:

```
build/Flip.app/Contents/MacOS/Flip --set-key
```

It prompts, reads one line from standard input so the key never reaches your shell history or the process list, and writes it to the login Keychain. An empty line clears the stored key.

Launching Flip always opens Settings, whether it is running or not. It has no window of its own to return to, so that is the only useful thing a launch can do, and it is the way past a hidden menu bar icon: search for Flip in Spotlight and press return.

## Checking it without the interface

```
build/Flip.app/Contents/MacOS/Flip --prompt
build/Flip.app/Contents/MacOS/Flip --prompt --peek
build/Flip.app/Contents/MacOS/Flip --translate "안녕하세요, 오늘 회의는 3시입니다"
build/Flip.app/Contents/MacOS/Flip --screenshot ./docs
build/Flip.app/Contents/MacOS/Flip --popup-demo
```

The first two print the exact system prompt that will be sent. `--translate` runs one real translation and prints the result, the model, and the latency. `--screenshot` renders every interface surface to PNG without needing a visible screen. `--popup-demo` shows the result panel and toggles the original, printing the frame each time: the top edge must not move, because showing the original resizes the panel rather than repositioning it.

## How it reads and writes text

For the popup shortcut the app first asks macOS Accessibility for the selected text, which does not touch your clipboard. If that returns nothing, it falls back to a synthetic command+C.

For the replace shortcut it always uses the clipboard: it saves whatever you had, copies the selection, pastes the translation, then puts your original clipboard back. If a copy produces nothing, it sends command+A first, which is what makes "translate my whole input box" work.

## Giving it to other people

The self-signed certificate above is for your own machine only. It does not make the app distributable.

A Mac that downloads this app refuses to open it: Gatekeeper reports that Apple cannot verify the developer. Getting past that needs three things, and there is no way around them:

1. An Apple Developer Program membership, 99 US dollars per year.
2. A "Developer ID Application" certificate issued under that membership.
3. Notarization: the signed app is uploaded to Apple, scanned, and the returned ticket is stapled into the bundle.

There is no Developer ID certificate on this machine today (`security find-identity -v -p codesigning` returns nothing), so this is a purchase and setup step, not a code change. Once the certificate exists, the only change here is the identity name in `scripts/build.sh` plus a notarization step after it.

Until then there are two ways to hand it to someone, both awkward for a non-engineer:

- They clone the repository and run `./scripts/build.sh` themselves. A locally built app carries no quarantine flag, so it opens normally. It needs the Xcode Command Line Tools.
- You send them the built app and they right-click it and choose Open the first time, or run `xattr -d com.apple.quarantine /Applications/Flip.app`. Some managed Macs block this outright.

## How it is built

One `swiftc` invocation over `Sources/Flip/*.swift`, linked against AppKit, SwiftUI, Carbon, ApplicationServices and Security. There is no package manifest and no third-party code, so there is nothing to resolve or vendor.

| File | Responsibility |
|---|---|
| `Hotkeys.swift` | System-wide shortcuts through Carbon `RegisterEventHotKey`, and whether each one actually registered |
| `TextAccess.swift` | Reading the selection through Accessibility or a synthetic copy, and pasting the result back |
| `Translator.swift` | The prompt, and the OpenAI and Anthropic request shapes |
| `Settings.swift`, `Keychain.swift` | Configuration, and the API key in the login Keychain |
| `HistoryStore.swift`, `HistoryView.swift` | The record of every translation |
| `PopupPanel.swift` | The floating panel, which must never take focus from the app you are typing in |
| `Doctor.swift` | `--doctor`, which reports every precondition the shortcuts depend on |

## Limits in this version

- macOS only. Windows is planned; the translation, settings, and history layers are platform independent, only text reading, pasting, and hotkeys would need a Windows implementation.
- Shortcuts are fixed. There is no recorder yet.
- 8,000 characters per translation.
- No streaming. The popup shows a spinner until the whole translation arrives.

## Screenshots

Rendered from the app itself with `Flip --screenshot docs/`:

| | |
|---|---|
| ![Settings](docs/settings.png) | ![History](docs/history.png) |
| ![Popup](docs/popup-result.png) | ![Working](docs/popup-working.png) |
