import AppKit
import SwiftUI

@main struct InputRedirectionApp: App {
    @StateObject private var client = Client()
    var body: some Scene {
        WindowGroup {
            ContentView(client: client)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 760, height: 650)
    }
}
