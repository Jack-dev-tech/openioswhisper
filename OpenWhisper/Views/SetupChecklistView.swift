import SwiftUI
import UIKit

/// The steps needed before the keyboard can dictate.
struct SetupChecklistView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            step(
                done: model.keyboardReady,
                title: "Add the keyboard with Full Access",
                detail: "Settings › General › Keyboard › Keyboards › Add New Keyboard › OpenWhisper, then turn on Allow Full Access. Full Access lets the keyboard talk to this app; the keyboard itself never goes online. Then open the keyboard once in any app.",
                action: ("Open Settings", openSettings)
            )
            step(
                done: model.microphoneGranted,
                title: "Allow the microphone",
                detail: "The app records for the keyboard, since iOS keyboards can't use the microphone.",
                action: ("Allow", { Task { await model.requestMicrophone() } })
            )
            step(
                done: model.hasTranscriptionEngine,
                title: "Add a Groq key or download a model",
                detail: "Use Groq's Whisper models with your own API key, or download a model to run on this iPhone.",
                action: ("Choose", { model.selectedTab = .models })
            )
        }
    }

    private func step(done: Bool, title: String, detail: String, action: (String, () -> Void)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                if !done {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                    Button(action.0, action: action.1)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
