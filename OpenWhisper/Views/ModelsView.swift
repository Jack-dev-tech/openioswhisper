import DictationCore
import SwiftUI

/// Choose the engine and model, and manage on-device downloads.
struct ModelsView: View {
    @Environment(AppModel.self) private var model
    @State private var refreshMessage: String?
    @State private var isRefreshing = false

    var body: some View {
        @Bindable var settings = model.settings
        List {
            Section {
                Picker("Engine", selection: $settings.settings.provider) {
                    ForEach(TranscriptionProvider.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(settings.settings.provider == .groq
                     ? "Audio is sent to Groq with your API key. Very fast, and the large models are the most accurate."
                     : "Audio never leaves this iPhone. Works offline; speed depends on the model and your iPhone.")
            }

            switch settings.settings.provider {
            case .groq: groqSection
            case .onDevice: onDeviceSection
            }
        }
        .navigationTitle("Models")
        .task { await model.models.refreshSupport() }
    }

    // MARK: - Groq

    @ViewBuilder
    private var groqSection: some View {
        let settings = model.settings
        Section {
            if !model.hasGroqKey {
                NavigationLink("Add your Groq API key") { SettingsView() }
                    .foregroundStyle(Color.accentColor)
            }
            ForEach(ModelCatalog.models(for: .groq, extraGroqModelIDs: settings.settings.extraGroqModelIDs)) { item in
                ModelRow(model: item, isSelected: settings.settings.isSelected(item)) {
                    settings.settings.select(item)
                }
            }
        } header: {
            Text("Groq models")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let refreshMessage { Text(refreshMessage) }
                Button(isRefreshing ? "Checking…" : "Check my account for more models") {
                    Task {
                        isRefreshing = true
                        refreshMessage = await model.refreshGroqModels()
                        isRefreshing = false
                    }
                }
                .disabled(!model.hasGroqKey || isRefreshing)
                .font(.footnote.weight(.semibold))
            }
        }
    }

    // MARK: - On-device

    @ViewBuilder
    private var onDeviceSection: some View {
        let settings = model.settings
        let store = model.models
        Section {
            ForEach(ModelCatalog.onDevice) { item in
                let state = store.state(of: item.modelID)
                ModelRow(
                    model: item,
                    isSelected: settings.settings.isSelected(item),
                    isEnabled: state == .downloaded,
                    warning: store.isSupported(item.modelID) ? nil : "May be too slow or too big for this iPhone."
                ) {
                    settings.settings.select(item)
                } accessory: {
                    DownloadControl(modelID: item.modelID, sizeMB: item.approximateSizeMB)
                }
            }
        } header: {
            Text("On-device models")
        } footer: {
            Text("Downloads come from Hugging Face (argmaxinc/whisperkit-coreml). After downloading, the model is optimized for this iPhone's Neural Engine, which can take a minute the first time.")
        }
    }
}

private struct ModelRow<Accessory: View>: View {
    var model: TranscriptionModel
    var isSelected: Bool
    var isEnabled = true
    var warning: String?
    var select: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            Button(action: select) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name).font(.body.weight(.medium))
                        Text(model.detail).font(.caption).foregroundStyle(.secondary)
                        if let warning {
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.6)
            accessory()
        }
    }
}

extension ModelRow where Accessory == EmptyView {
    init(model: TranscriptionModel, isSelected: Bool, select: @escaping () -> Void) {
        self.init(model: model, isSelected: isSelected, select: select, accessory: { EmptyView() })
    }
}

private struct DownloadControl: View {
    @Environment(AppModel.self) private var model
    var modelID: String
    var sizeMB: Int?
    @State private var confirmDelete = false

    var body: some View {
        let store = model.models
        switch store.state(of: modelID) {
        case .notDownloaded, .failed:
            VStack(alignment: .trailing, spacing: 2) {
                Button {
                    store.download(modelID)
                } label: {
                    Image(systemName: "arrow.down.circle").font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Download")
                if case .failed(let message) = store.state(of: modelID) {
                    Text(message).font(.caption2).foregroundStyle(.red).lineLimit(2).frame(maxWidth: 120, alignment: .trailing)
                } else if let sizeMB {
                    Text("\(sizeMB) MB").font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .downloading(let fraction):
            HStack(spacing: 6) {
                ProgressView(value: fraction).frame(width: 56)
                Button {
                    store.cancelDownload(modelID)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Cancel download")
            }
        case .preparing:
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView()
                Text("Optimizing").font(.caption2).foregroundStyle(.secondary)
            }
        case .downloaded:
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete download")
            .confirmationDialog("Delete this model?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    Task {
                        await store.delete(modelID)
                        if model.settings.settings.provider == .onDevice, model.settings.settings.onDeviceModelID == modelID {
                            model.settings.settings.onDeviceModelID = model.settings.settings.downloadedOnDeviceModelIDs.first ?? ModelCatalog.defaultOnDeviceModelID
                        }
                    }
                }
            } message: {
                if let bytes = store.sizeOnDisk(modelID) {
                    Text("Frees \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). You can download it again later.")
                }
            }
        }
    }
}
