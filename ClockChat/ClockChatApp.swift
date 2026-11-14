import SwiftUI

@main
struct ClockChatApp: App {
    @StateObject private var store = ChatStore()
    var body: some Scene {
        WindowGroup { ChatView().environmentObject(store).tint(.teal) }
    }
}
