import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            NavigationStack { SessionView() }
                .tabItem { Label("Dictate", systemImage: "mic.fill") }
                .tag(AppModel.Tab.dictate)
            NavigationStack { ModelsView() }
                .tabItem { Label("Models", systemImage: "cpu") }
                .tag(AppModel.Tab.models)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppModel.Tab.settings)
        }
    }
}
