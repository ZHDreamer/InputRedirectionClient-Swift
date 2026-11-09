import AppKit
import Combine
import GameController
import SwiftUI

struct ControllerMenu: NSViewRepresentable {
    @ObservedObject var client: Client

    func makeCoordinator() -> Coordinator { Coordinator(client: client) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectController(_:))
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        guard !context.coordinator.isListening else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = context.coordinator
        if client.controllers.isEmpty {
            menu.addItem(
                withTitle: "Connect a controller via Bluetooth or USB", action: nil,
                keyEquivalent: "")
        } else {
            let hint = NSMenuItem(
                title: "Press a controller button or choose below", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            menu.addItem(.separator())
            for (index, controller) in client.controllers.enumerated() {
                let item = NSMenuItem(
                    title: "\(controller.vendorName ?? "Game Controller") #\(index + 1)",
                    action: nil, keyEquivalent: "")
                item.representedObject = controller
                menu.addItem(item)
            }
        }
        context.coordinator.menu = menu
        button.menu = menu
        button.selectItem(at: client.controllers.isEmpty ? 0 : client.selected + 2)
        button.isEnabled = !client.controllers.isEmpty
        button.toolTip = "Choose a controller or press a button on it while this menu is open"
        button.setAccessibilityLabel("Controller: \(button.titleOfSelectedItem ?? "None")")
    }

    static func dismantleNSView(_ view: NSPopUpButton, coordinator: Coordinator) {
        coordinator.menu?.cancelTracking()
        coordinator.client.cancelControllerSelection()
    }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        let client: Client
        var menu: NSMenu?
        var isListening = false
        private var capture: AnyCancellable?

        init(client: Client) {
            self.client = client
            super.init()
            capture = client.$isSelectingController.sink { [weak self] selecting in
                guard let self, self.isListening, !selecting else { return }
                DispatchQueue.main.async { [weak menu = self.menu] in menu?.cancelTracking() }
            }
        }

        func menuWillOpen(_ menu: NSMenu) {
            client.beginControllerSelection()
            isListening = true
        }

        func menuDidClose(_ menu: NSMenu) {
            isListening = false
            client.cancelControllerSelection()
        }

        @objc func selectController(_ sender: NSPopUpButton) {
            guard let controller = sender.selectedItem?.representedObject as? GCController else {
                return
            }
            client.selectController(controller)
        }
    }
}
