import DictationCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var keyDraft = ""
    @State private var keyMessage: String?
    @State private var isTesting = false

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                SecureField(model.hasGroqKey ? "Saved — paste a new key to replace it" : "gsk_…", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                HStack {
                    Button("Save and test") {
                        model.saveGroqKey(keyDraft)
                        keyDraft = ""
                        testKey()
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty || isTesting)
                    Spacer()
                    if model.hasGroqKey {
                        Button("Test", action: testKey).disabled(isTesting)
                        Button("Remove", role: .destructive) {
                            model.saveGroqKey("")
                            keyMessage = nil
                        }
                    }
                }
                .buttonStyle(.borderless)
                if isTesting {
                    ProgressView()
                } else if let keyMessage {
                    Text(keyMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Groq API key")
            } footer: {
                Text("Stored in this iPhone's Keychain and only sent to Groq. Create a key at [console.groq.com/keys](https://console.groq.com/keys).")
            }

            Section {
                Picker("Language", selection: $settings.settings.language) {
                    Text("Auto-detect").tag(String?.none)
                    ForEach(WhisperLanguage.all) { language in
                        Text(language.name).tag(Optional(language.code))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vocabulary")
                    TextField("Names, jargon, spellings — one per line or comma separated", text: $settings.settings.vocabulary, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.callout)
                }
            } header: {
                Text("Recognition")
            } footer: {
                Text("Choosing your language is faster and more accurate than auto-detect. Vocabulary is passed to Whisper as a hint, which helps with names and technical terms.")
            }

            Section {
                Toggle("Clean up with AI", isOn: $settings.settings.cleanupEnabled)
                if settings.settings.cleanupEnabled {
                    Picker("Model", selection: $settings.settings.cleanupModelID) {
                        ForEach(cleanupModelChoices, id: \.self) { Text($0).tag($0) }
                    }
                }
            } header: {
                Text("AI cleanup")
            } footer: {
                Text(model.hasGroqKey
                     ? "Fixes punctuation and removes filler words with a Groq language model before the text is typed. Adds a fraction of a second, and sends the transcript to Groq even with an on-device model."
                     : "Needs a Groq API key.")
            }
            .disabled(!model.hasGroqKey)

            Section {
                Picker("End session after", selection: $settings.settings.sessionTimeout) {
                    ForEach(SessionTimeout.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Session")
            } footer: {
                Text("How long the microphone stays ready after your last dictation. When it ends, the keyboard's mic button opens this app to start a new session.")
            }

            Section("How it works") {
                Text("iOS doesn't let keyboards use the microphone. When you tap the mic in the OpenWhisper keyboard, this app records in the background, transcribes with the model you chose, and the keyboard types the result.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    private var cleanupModelChoices: [String] {
        let fetched = model.settings.settings.groqChatModelIDs
        let current = model.settings.settings.cleanupModelID
        var choices = fetched.isEmpty ? [ModelCatalog.defaultCleanupModelID] : fetched
        if !choices.contains(current) { choices.insert(current, at: 0) }
        return choices
    }

    private func testKey() {
        Task {
            isTesting = true
            keyMessage = await model.refreshGroqModels()
            isTesting = false
        }
    }
}
