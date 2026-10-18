# OpenWhisper

OpenWhisper is an iOS dictation keyboard. You tap the mic in the keyboard, speak, and the text is typed into whatever app you're in. You choose the model:

- **Groq** (cloud, your own API key): Whisper Large V3 Turbo and Whisper Large V3. Any other Whisper model on your Groq account appears after **Check my account for more models**.
- **On-device** (WhisperKit, offline): Whisper Tiny, Base, Small, Large V3 Turbo and Large V3. They download from Hugging Face inside the app.

Optional extras:
- a language picker (auto-detect or one of Whisper's 100 languages)
- a vocabulary hint for names and jargon
- an AI cleanup pass with a Groq chat model that fixes punctuation and removes filler words

Requires iOS 17+ and Xcode 16+. The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open OpenWhisper.xcodeproj
swift test --package-path Packages/DictationCore   # core logic only, fast
python3 scripts/make-icon.py OpenWhisper/Theme/Assets.xcassets/AppIcon.appiconset/AppIcon.png   # regenerate the icon (needs Pillow)
```

## First run on an iPhone
1. In Xcode, set your team on both the **OpenWhisper** and **OpenWhisperKeyboard** targets (Signing & Capabilities). Both targets use the App Group `group.com.jackmatsuzaki.openwhisper`. If you change the bundle prefix, change the group in `project.yml` and `IPC.appGroupID` too.
2. Run the app on a real iPhone. Simulators can't really test a keyboard with Full Access plus a microphone.
3. Follow the checklist on the Dictate tab:
   - **Settings › General › Keyboard › Keyboards › Add New Keyboard › OpenWhisper**, then turn on **Allow Full Access**.
   - Allow the microphone.
   - Paste a Groq key from [console.groq.com/keys](https://console.groq.com/keys) in Settings, or download an on-device model in Models.

## How dictation works
iOS doesn't let keyboard extensions use the microphone, so the app records for the keyboard. This is the same approach Wispr Flow and Superwhisper use.

1. **Start a session.** The first time you tap the keyboard's mic, it opens `openwhisper://session?record=1`. The app starts a session and begins recording right away. It keeps the microphone open in the background (`UIBackgroundModes: audio`), and iOS shows the orange dot while it's on. Swipe back to your app, keep talking, and tap the mic to finish.
2. **Dictate.** While the session is on, the keyboard's mic button sends Darwin notifications (`start`, `stop`, `cancel`) to the app. The app records 16 kHz mono audio and transcribes it with the selected model, then optionally runs the cleanup.
3. **Insert.** The app writes the transcript to the shared App Group container and notifies the keyboard, which types it with `textDocumentProxy.insertText`.
4. **Timeout.** The session ends after the timeout you choose (5 min to never). The next mic tap opens the app again.

The Groq key stays in the app's Keychain. The keyboard makes no network requests. Full Access is only needed so the keyboard can share the App Group container with the app and open it.

## Layout
- **`Packages/DictationCore`**: pure Swift with no UI, shared by the app and the keyboard, and covered by unit tests:
  - the model catalog
  - `DictationSettings`
  - the session status, results and IPC names
  - `SharedStore`, JSON files in the App Group container
  - Groq request building and response and error decoding
  - the WAV encoder
  - the vocabulary prompt and cleanup guardrails
  - the language list
- **`OpenWhisper/Session`**:
  - `DictationSession` runs the background session: heartbeat, timeout, recording and handing results to the keyboard.
  - `AudioCapture` handles the `AVAudioEngine` tap, 16 kHz conversion, levels and interruptions.
- **`OpenWhisper/Engines`**:
  - `GroqClient`
  - `OnDeviceEngine`, a WhisperKit actor. It uses CPU and Neural Engine only, because iOS blocks GPU work in the background.
  - `ModelStore`, which handles downloads.
  - `TranscriptionPipeline`, which runs the chosen engine and then cleanup.
- **`OpenWhisper/Views`**: the Dictate, Models and Settings tabs.
- **`OpenWhisperKeyboard`**:
  - the `UIInputViewController` hosting a SwiftUI keyboard: the mic, the model switcher, space, delete, return, undo and globe
  - `KeyboardModel`
  - `AppOpener`
- **`Shared/DarwinNotifier.swift`**: the cross-process notifications, compiled into both targets.

## Known limits
- **App Review:** keeping the microphone open in the background for dictation is accepted for similar apps on the App Store, but Apple decides each case.
- **Opening the app from the keyboard:** the keyboard reaches the app through the responder chain, because extensions can't call `UIApplication.shared`. If a future iOS blocks this, the keyboard tells you to open OpenWhisper and tap **Start session**.
- **Large models:** Large V3 and Large V3 Turbo on-device need an iPhone 14 Pro or newer and take a minute to optimize the first time. Models WhisperKit flags as unsupported on your device are marked.
- **Groq upload limit:** the free tier accepts 25 MB per request, about 13 minutes of 16 kHz audio. Recordings stop automatically at 10 minutes.

## Manual QA checklist
1. Complete the setup checklist. Each item turns green.
2. In Notes, switch to the OpenWhisper keyboard and tap the mic. The app opens and starts recording. Swipe back, keep talking, and tap the mic. The text appears in Notes.
3. Tap the mic, speak, and tap again. The status shows "Transcribing…", then the text appears in Notes with a leading space when needed. Undo removes it.
4. Switch the model from the keyboard's chip (Groq Turbo ↔ an on-device model) and dictate again.
5. Set a language, add vocabulary (for example, an unusual name), and turn on AI cleanup. Dictate "um so I think we should uh ship it". It comes out cleaned up.
6. Remove the Groq key and dictate with Groq. The keyboard shows "Add your Groq API key in Settings."
7. Set the timeout to 5 minutes and wait. The session ends, and the next mic tap opens the app.
8. Start a phone call or Siri during a recording. The recording is cancelled and the session keeps going.
