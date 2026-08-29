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

There is one shortcut and it is rebindable. The menu bar item also offers both actions explicitly, for the rare case where you want to force one.

### How it decides

Keyboard focus alone is not enough. In Slack, Discord, Notion and most chat apps, focus stays in the composer while you select text in a message you are reading, so deciding on focus would paste a translation of what you were reading into the box you were writing in.

What separates the two is where the selection is:

1. Flip copies the selection, saving and restoring your clipboard around it.
2. If the focused element is not something you can type into, it shows the popup.
3. If it is, and it reports the selection as its own, or its contents contain what was copied, the selection was inside the field: replace.
4. Where it cannot tell, it shows the popup. Nothing gets overwritten on a guess.

The text itself always comes from the clipboard, never from Accessibility, even though Accessibility can hand back a selection directly. Chromium, and so every Electron app, flattens its accessibility tree into one line: `AXSelectedText` arrives with every line break gone and U+FFFC where each emoji and mention chip was. A translation of that reads as one run-on paragraph. Accessibility answers where the selection is; the clipboard answers what it says.

A field the app marks as secure, such as a password box, is refused outright under every shortcut. Flip will neither read it nor paste over it.

The popup is placed against the selection, not the pointer: aligned with its left edge and directly below it, flipping above when there is no room. Three ways to find that rectangle, in order:

1. `AXBoundsForRange` on the selected character range. Exact, and what native apps answer.
2. `AXBoundsForTextMarkerRange`. Web content describes positions with text markers rather than character ranges, so this is the one Chromium and every Electron app answers. Slack's focused element is an `AXGroup` that reports a selected range and then refuses to give bounds for it.
3. The last mouse drag, recorded by Flip while it runs. This needs no cooperation from the app at all: the pointer went down at one corner of the text and came up at the other.

The pointer itself is the last resort.

Check what it will do in any app with `--probe-focus`, which reports the focused element's role, whether its value can be written, and the decision that follows:

```
/Applications/Flip.app/Contents/MacOS/Flip --probe-focus 5
```

Measured with it: Slack's composer is an `AXTextArea` with a settable value, Notes is the same, a browser reading a page hands back an `AXButton` whose value cannot be written. Browsers also report a selected text range on elements that are plainly not text, which is why a selection range on its own counts for nothing.

## Install

### Download

1. Get `Flip-<version>-macos-universal.zip` from the [releases page](../../releases). Universal, so it runs on Apple Silicon and Intel.
2. Unzip it and drag `Flip.app` into your **Applications** folder.
3. Open Terminal and run:

   ```
   xattr -dr com.apple.quarantine /Applications/Flip.app
   ```

4. Open Flip normally.

Step 3 is needed because the app is not notarized: this project has no Apple Developer Program membership, which is what notarization requires, so macOS blocks it on first launch.

The `-r` matters. Without it the flag is cleared from the folder but stays on everything inside, macOS still treats the app as freshly downloaded, and the symptom is confusing: it will not hold the Accessibility permission. You grant it, the app still says it needs access, and the request comes back every time you reopen it. `xattr -r /Applications/Flip.app | grep quarantine` should print nothing when it worked.

**Control-clicking and choosing Open does not work.** That was the way to do this until macOS 15, and it is still what most instructions on the internet tell you. Apple removed it: on macOS 15 and later an app that fails notarization has to be allowed from System Settings instead. If you would rather not use Terminal, that route is: double-click Flip and dismiss the warning, then open **System Settings, Privacy & Security**, scroll to the bottom, and click **Open Anyway** next to the line about Flip.

If your Mac is managed by an employer, both routes may be blocked. Building from source is then the only option, and it is the section below: an app you built yourself was never downloaded, so it carries no quarantine flag and opens normally.

### If you would rather not touch the Terminal

Paste this to an AI assistant that can run commands on your Mac. Claude Desktop, ChatGPT's Mac app with terminal access, Claude Code, Cursor and similar tools can all do it.

```
I downloaded a Mac app called Flip from https://github.com/deopard/flip/releases
and I do not use the Terminal. Please set it up for me:

1. Find the Flip zip file in my Downloads folder and unzip it.
2. Move Flip.app into /Applications.
3. Run: xattr -dr com.apple.quarantine /Applications/Flip.app
   The -r is important: without it the flag stays on the files inside
   the app and macOS will refuse to remember the permission in step 5.
   The app is signed but not notarized, so macOS blocks it until that
   download flag is cleared. This step is expected, not a sign that
   anything is wrong with the app.
4. Check it worked: xattr -r /Applications/Flip.app | grep quarantine
   should print nothing.
5. Open Flip.
6. Tell me to turn Flip on in System Settings, Privacy & Security,
   Accessibility. It cannot read my selected text without that.

If any step fails, run
/Applications/Flip.app/Contents/MacOS/Flip --doctor
and tell me in plain language what it says is missing.
```

Ask in whatever language you speak; the assistant will follow it either way. In Korean, for instance:

```
Flip이라는 맥 앱을 https://github.com/deopard/flip/releases 에서 받았는데
터미널을 쓸 줄 몰라요. 대신 설치해 주세요.

1. 다운로드 폴더에서 Flip 압축 파일을 찾아서 풀어주세요.
2. Flip.app을 /Applications 로 옮겨주세요.
3. 이 명령을 실행해 주세요: xattr -dr com.apple.quarantine /Applications/Flip.app
   -r 이 꼭 있어야 합니다. 없으면 앱 안쪽 파일에 표시가 남아서,
   5번에서 권한을 줘도 macOS가 기억하지 않습니다.
   이 앱은 서명은 되어 있지만 공증(notarization)은 안 되어 있어서,
   저 다운로드 표시를 지우기 전까지 macOS가 실행을 막습니다.
   앱에 문제가 있어서가 아니라 원래 필요한 단계입니다.
4. 잘 됐는지 확인해 주세요: xattr -r /Applications/Flip.app | grep quarantine
   아무것도 안 나와야 정상입니다.
5. Flip을 실행해 주세요.
6. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 Flip을 켜라고
   알려주세요. 그게 없으면 제가 선택한 글자를 읽지 못합니다.

중간에 안 되는 게 있으면
/Applications/Flip.app/Contents/MacOS/Flip --doctor
를 실행하고 무엇이 빠졌는지 쉬운 말로 알려주세요.
```

Only paste instructions like this for software you actually mean to install. It runs a command on your machine, and the same shape of prompt would work just as well for something you did not want.


### Or build it

```
./scripts/create-signing-identity.sh   # optional, see below
./scripts/build.sh
open build/Flip.app
```

The build needs no dependencies and no Xcode project. It uses the Swift compiler that ships with the Xcode Command Line Tools.

`create-signing-identity.sh` makes a self-signed certificate in its own keychain and signs every build with it. Without it, builds are signed ad hoc, and because an ad-hoc signature's identity is the binary's own hash, macOS treats each rebuild as a new app: it drops the Accessibility permission and re-asks for your Keychain password every time. It takes no password to set up and `--remove` undoes it.

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

- **Provider** — OpenRouter by default, or OpenAI directly (and anything else speaking the OpenAI chat completions format), or Anthropic. OpenRouter is the way to reach Gemini, DeepSeek, Qwen, GLM and the rest from one key; it speaks the same chat completions format, so all it changes is the base URL and the model presets.
- **Credential** (Anthropic only) — an API key, or the login Anthropic's own CLI already holds. Picking the CLI login means no key is pasted anywhere: Flip asks `ant auth print-credentials --access-token` for a short-lived token and sends it as `Authorization: Bearer` with the `oauth-2025-04-20` beta header. Set it up with `ant auth login`. Whether that draws on a subscription or on API credits depends on the account, not on Flip.

  There is no equivalent for OpenAI. A ChatGPT subscription does not include API access, and there is no supported way for a third-party app to use one. Flip ships no OAuth client id of its own: signing in with another product's first-party client, which is how several tools graft a subscription onto a third-party app, breaks the provider's terms, and in an open repository the client id would be published in the clear.
- **Base URL** — prefilled per provider; change it to point at a compatible gateway.
- **Model** — free text, with presets per provider. Default is `gpt-5.6-luna`.
- **Effort** — how hard the model thinks. Sent as `reasoning_effort` to OpenAI and as `output_config.effort` to Anthropic. Default `medium`. If a model does not accept one, Flip retries without it rather than failing.
- **Replace with** — the language the in-place replacement is written in. Default English.
- **Popup shows** — the language the popup is written in. Default Korean.
- Both are dropdowns you can also type into. The list carries 80 languages; anything you type works too, because the language is passed to the model as a word rather than looked up in a table. "Swiss German" and "Cantonese" both produce what you would expect.
- **Auto swap** — pick this in either row and Flip flips between the two languages above, based on what you selected.
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

This project has no Developer ID certificate, so that is a purchase and setup step rather than a code change. Once one exists, the change here is the identity in `scripts/release.sh` plus a notarization step after it.

Until then, released builds are signed ad hoc and carry the quarantine flag once downloaded, which is why the install instructions above clear it by hand.

Releases are signed with a self-signed certificate rather than ad hoc, which is a different thing from notarization and solves a different problem. macOS identifies a signed app by its designated requirement. Ad hoc makes that the binary's own hash, so every release would be a different app, and the Accessibility permission you granted would not survive an update, while the old entry stayed in the list looking switched on. With a fixed certificate the requirement is `identifier "video.cutback.flip" and certificate leaf = H"..."`, which does not change between versions. The certificate travels inside the signature, so installing a release needs nothing extra.

Versions up to and including 0.1.0 were signed ad hoc. Moving from one of those to 0.1.1 needs the permission granted once more; after that it carries over. Some centrally managed Macs block that outright, in which case building from source is the only route: a locally built app was never downloaded, so it carries no quarantine flag and opens normally.

`scripts/release.sh` produces what the releases page carries: a universal binary for Apple Silicon and Intel, ad-hoc signed, archived with `ditto` so the signature survives.

## Choosing a model

Translation is not a reasoning task, so the expensive models buy little here and the difference between them is worth measuring rather than assuming:

```
/Applications/Flip.app/Contents/MacOS/Flip --bench 3
/Applications/Flip.app/Contents/MacOS/Flip --bench 5 "qwen/qwen3.7-flash,google/gemini-2.5-flash-lite,openai/gpt-5.6-luna"
```

It translates the same message with each model, prints median latency, and then prints every translation so you can judge whether the cheap one is good enough. It costs real money, one request per run.

Here is that measurement for the OpenRouter presets, translating the same Korean announcement into English, three runs each, median round trip. Prices are dollars per million tokens weighted 3 to 1 input against output, from OpenRouter's own model list.

| Model | Median | Range | $/M |
|---|---:|---|---:|
| `z-ai/glm-5.3-flash` | **2337 ms** | 2066-2529 | 0.119 |
| `openai/gpt-5.6-luna` | 2805 ms | 2265-2908 | 0.450 |
| `google/gemini-2.5-flash-lite` | 4604 ms | 3761-4862 | 0.175 |
| `deepseek/deepseek-v4-flash` | 7832 ms | 7417-8443 | 0.107 |
| `qwen/qwen3.7-flash` | 12255 ms | 9959-13004 | 0.055 |
| `openai/gpt-5-nano` | 15212 ms | 15119-17499 | 0.137 |

**Price and speed do not track each other.** The cheapest model in the list was also the slowest, by more than five times, and the third cheapest was the fastest. Latency here includes OpenRouter's own routing, so the same model called directly may differ.

Quality was close enough across all six that speed and price decide it. Every one preserved the line breaks, the mentions, the emoji shortcode and the leading asterisk; only Gemini reflowed the last line into an indented list item. `z-ai/glm-5.3-flash` is the default because it was both faster and 3.8 times cheaper than the alternative.

Effort is the other lever, and often the bigger one: lower effort means fewer reasoning tokens, which is less latency and less money at the same quality for work like this.

## Checking what Flip actually received

Every translation is recorded with its source text exactly as it arrived, which is how to tell a bad translation from a bad read:

```
python3 -c "import json,pathlib;e=json.loads((pathlib.Path.home()/'Library/Application Support/Flip/history.json').read_text())[0];print(repr(e['source'][:300]))"
```

If the source has no line breaks in it, the problem is upstream of the model.

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
- 8,000 characters per translation.
- No streaming. The popup shows a spinner until the whole translation arrives.

## Screenshots

Rendered from the app itself with `Flip --screenshot docs/`:

| | |
|---|---|
| ![Settings](docs/settings.png) | ![History](docs/history.png) |
| ![Popup](docs/popup-result.png) | ![Working](docs/popup-working.png) |
