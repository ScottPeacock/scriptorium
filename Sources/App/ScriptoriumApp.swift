import SwiftUI

@main
struct ScriptoriumApp: App {
    @State private var session = SessionModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}
