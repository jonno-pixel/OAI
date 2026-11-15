import SwiftUI

@main
@MainActor
struct JJSVrijApp: App {
    @StateObject private var workspace = Workspace()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            VrijHome()
                .environmentObject(workspace)
                .onAppear { workspace.scene(phase) }
                .onChange(of: phase) { _, newValue in workspace.scene(newValue) }
                .onChange(of: workspace.isWriting) { _, _ in workspace.scene(phase) }
        }
    }
}
