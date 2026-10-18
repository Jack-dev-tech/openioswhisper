import DictationCore
import SwiftUI
import UIKit

/// The home screen: setup checklist, the background session, and a place to try dictation.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    @State private var tryText = ""

    private var session: DictationSession { model.session }

    var body: some View {
        List {
            if !model.isSetupComplete {
                Section("Set up") { SetupChecklistView() }
            }

            Section {
                SessionCard()
            } footer: {
                Text("While a session is on, the microphone stays open in the background so the keyboard can dictate into any app. iOS shows an orange dot while it's on.")
            }

            Section("Try it") {
                HStack(spacing: 12) {
                    RecordButton(isRecording: session.phase == .recording, isBusy: session.phase == .transcribing, size: 44) {
                        if session.phase == .recording {
                            session.stopRecording()
                        } else {
                            session.startRecording(source: .app)
                        }
                    }
                    .disabled(!session.isActive || session.phase == .transcribing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.isActive ? "Tap to record here" : "Start a session to try it")
                            .font(.subheadline.weight(.medium))
                        Text(model.settings.settings.selectedModelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let transcript = session.lastTranscript {
                    Text(transcript)
                        .textSelection(.enabled)
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = transcript }
                }
                TextField("Or switch to the OpenWhisper keyboard here", text: $tryText, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .navigationTitle("OpenWhisper")
    }
}

private struct SessionCard: View {
    @Environment(AppModel.self) private var model
    private var session: DictationSession { model.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(session.isActive ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text(title).font(.headline)
                Spacer()
                if let expiresAt = session.expiresAt, session.isActive {
                    Text("Ends \(expiresAt, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let message = session.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(session.phase == .failed ? Color.red : Color.secondary)
            }

            if session.isActive {
                Text(session.phase == .recording
                     ? "Recording. Swipe back or tap ◀ in the top corner, keep talking, then tap the mic in the keyboard to finish."
                     : "Swipe back or tap ◀ in the top corner to return to your app. The keyboard's mic button now records without coming here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                if session.isActive {
                    session.end()
                } else {
                    Task { await session.start() }
                }
            } label: {
                Text(session.isActive ? "End session" : "Start session")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(session.isActive ? .red : .accentColor)
            .controlSize(.large)
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch session.phase {
        case .inactive: "No session"
        case .ready: "Session on — ready"
        case .recording: "Recording…"
        case .transcribing: "Transcribing…"
        case .failed: "Session on — last dictation failed"
        }
    }
}

/// The round microphone button, shared by the try-it row.
struct RecordButton: View {
    var isRecording: Bool
    var isBusy: Bool
    var size: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(isRecording ? Color.red : Color.accentColor)
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }
}
