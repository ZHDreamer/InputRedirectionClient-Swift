import AppKit
import InputCore
import SwiftUI

// A native menu exposes open/close callbacks so listening has exactly the same lifetime.
struct MappingMenu: NSViewRepresentable {
    @ObservedObject var client: Client
    let target: InputTarget

    func makeCoordinator() -> Coordinator { Coordinator(client: client, target: target) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: "", target: context.coordinator, action: #selector(Coordinator.openMenu(_:)))
        button.bezelStyle = .rounded
        button.alignment = .center
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        let source = client.mapping[target] ?? .none
        let name = client.sourceLabel(source)
        let image = client.sourceImage(
            source, font: button.font ?? .systemFont(ofSize: NSFont.systemFontSize))
        button.title = image == nil ? name : ""
        button.image = image
        button.imagePosition = image == nil ? .noImage : .imageOnly
        button.toolTip =
            "\(target.rawValue): \(name). Open to choose or listen for controller input. Input is paused while mapping."
        button.setAccessibilityLabel("Map \(target.rawValue): \(name)")
    }

    static func dismantleNSView(_ view: NSButton, coordinator: Coordinator) {
        coordinator.menu?.cancelTracking()
        if coordinator.client.mappingTarget == coordinator.target {
            coordinator.client.cancelMapping()
        }
    }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        let client: Client
        let target: InputTarget
        var menu: NSMenu?
        var isListening = false

        init(client: Client, target: InputTarget) {
            self.client = client
            self.target = target
        }

        @objc func openMenu(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            let isStick = target.isStick
            let hint = NSMenuItem(
                title: isStick
                    ? "Move a stick or press the D-Pad" : "Press a button or choose below",
                action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            menu.addItem(.separator())
            let sources = client.availableSources(for: target)
            for source in sources {
                let name = client.sourceLabel(source)
                let item = NSMenuItem(
                    title: name, action: #selector(selectInput(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = source
                item.image = client.sourceImage(source, font: menu.font)
                let selected = client.mapping[target] ?? .none
                item.state = selected == source ? .on : .off
                menu.addItem(item)
            }
            self.menu = menu
            // Close native tracking directly; SwiftUI redraws may wait until the menu closes.
            let capture = client.$mappingTarget.sink { [weak self, weak menu] selected in
                guard let self, self.isListening, selected != self.target else { return }
                DispatchQueue.main.async { menu?.cancelTracking() }
            }
            defer { capture.cancel() }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
            self.menu = nil
        }

        func menuWillOpen(_ menu: NSMenu) {
            client.beginMapping(target)
            isListening = true
        }

        func menuDidClose(_ menu: NSMenu) {
            isListening = false
            if client.mappingTarget == target { client.cancelMapping() }
        }

        @objc func selectInput(_ sender: NSMenuItem) {
            guard let source = sender.representedObject as? InputSource else { return }
            client.cancelMapping()
            client.mapping[target] = source
            client.save()
        }
    }
}
