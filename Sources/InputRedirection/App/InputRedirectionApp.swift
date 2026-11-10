import AppKit
import SwiftUI

@main struct InputRedirectionApp: App {
    @StateObject private var client = Client()
    var body: some Scene {
        WindowGroup {
            ContentView(client: client)
                .fixedSize(horizontal: true, vertical: true)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)
    }
}
