import DictationCore
import SwiftUI
import UIKit

/// A dictation-first keyboard: a big mic button, a model switcher, and the few keys you need around dictation.
struct KeyboardView: View {
    static let height: CGFloat = 240

    @Bindable var model: KeyboardModel

    var body: some View {
        VStack(spacing: 8) {
            topBar
            if model.showingModels {
                ModelPicker(model: model)
            } else {
                micArea
            }
            bottomRow
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        HStack {
            Button {
                model.showingModels.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.settings.provider == .groq ? "bolt.fill" : "iphone")
                    Text(model.settings.selectedModelName)
                        .lineLimit(1)
                    Image(systemName: model.showingModels ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(KeyStyle.specialKey))
            }
            .buttonStyle(.plain)
            .disabled(!model.hasFullAccess)
            .accessibilityLabel("Model: \(model.settings.selectedModelName). Change model")

            Spacer()

            if model.isRecording {
                Button("Cancel") { model.cancelRecording() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var micArea: some View {
        VStack(spacing: 8) {
            MicButton(
                isRecording: model.isRecording,
                isTranscribing: model.isTranscribing,
                isSessionLive: model.isLive,
                level: CGFloat(model.status.level),
                action: model.micTapped
            )
            Text(model.statusLine)
                .font(.footnote)
                .foregroundStyle(model.status.phase == .failed && model.notice == nil ? Color.red : Color.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if model.needsGlobeKey {
                KeyButton(systemImage: "globe", style: .special, action: model.nextKeyboard)
                    .accessibilityLabel("Next keyboard")
            }
            KeyButton(systemImage: "arrow.uturn.backward", style: .special, action: model.undoLastInsertion)
                .disabled(!model.canUndo)
                .opacity(model.canUndo ? 1 : 0.4)
                .accessibilityLabel("Undo dictation")
            KeyButton(title: "space", style: .normal, action: model.insertSpace)
                .frame(maxWidth: .infinity)
            RepeatingKeyButton(systemImage: "delete.left", action: model.deleteBackward)
                .accessibilityLabel("Delete")
            KeyButton(title: model.returnKeyTitle, style: .special, action: model.insertReturn)
                .frame(width: 88)
        }
        .frame(height: 44)
    }
}

// MARK: - Mic

private struct MicButton: View {
    var isRecording: Bool
    var isTranscribing: Bool
    var isSessionLive: Bool
    var level: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.25))
                        .frame(width: 76 + 34 * level, height: 76 + 34 * level)
                        .animation(.easeOut(duration: 0.1), value: level)
                }
                Circle()
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                if isTranscribing {
                    ProgressView().tint(.white).controlSize(.large)
                } else {
                    Image(systemName: isRecording ? "stop.fill" : (isSessionLive ? "mic.fill" : "mic.badge.plus"))
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 110, height: 110)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isTranscribing)
        .accessibilityLabel(isRecording ? "Stop dictation" : "Start dictation")
    }
}

// MARK: - Model picker

private struct ModelPicker: View {
    var model: KeyboardModel

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(model.settings.switchableModels) { item in
                    Button {
                        model.select(item)
                    } label: {
                        HStack {
                            Image(systemName: item.provider == .groq ? "bolt.fill" : "iphone")
                                .frame(width: 20)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.name).font(.subheadline.weight(.medium))
                                Text(item.provider.displayName).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.settings.isSelected(item) {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(KeyStyle.normalKey))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if model.settings.downloadedOnDeviceModelIDs.isEmpty {
                    Text("Download on-device models in the OpenWhisper app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Keys

enum KeyStyle {
    case normal, special

    static let normalKey = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white })
    static let specialKey = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1) })

    var fill: Color { self == .normal ? Self.normalKey : Self.specialKey }
}

private struct KeyFace: View {
    var title: String?
    var systemImage: String?
    var style: KeyStyle
    var isPressed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isPressed ? KeyStyle.specialKey : style.fill)
                .shadow(color: .black.opacity(0.3), radius: 0, y: 1)
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 18))
            } else if let title {
                Text(title).font(.system(size: 16))
            }
        }
        .foregroundStyle(Color.primary)
        .frame(minWidth: 44, maxHeight: .infinity)
    }
}

private struct KeyButton: View {
    var title: String?
    var systemImage: String?
    var style: KeyStyle
    var action: () -> Void

    init(title: String, style: KeyStyle, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    init(systemImage: String, style: KeyStyle, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            KeyFace(title: title, systemImage: systemImage, style: style)
        }
        .buttonStyle(KeyPressStyle())
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Delete: fires once on touch, then repeats while held, like the system keyboard.
private struct RepeatingKeyButton: View {
    var systemImage: String
    var action: () -> Void
    @State private var isPressed = false
    @State private var repeater = Repeater()

    var body: some View {
        KeyFace(systemImage: systemImage, style: .special, isPressed: isPressed)
            .frame(width: 52)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        action()
                        repeater.start(action)
                    }
                    .onEnded { _ in
                        isPressed = false
                        repeater.stop()
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

@MainActor
private final class Repeater {
    private var delay: Timer?
    private var timer: Timer?

    func start(_ action: @escaping () -> Void) {
        stop()
        delay = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                    MainActor.assumeIsolated { action() }
                }
            }
        }
    }

    func stop() {
        delay?.invalidate()
        timer?.invalidate()
        delay = nil
        timer = nil
    }
}
