import AppKit
import Combine
import InputCore
import SwiftUI

// A native menu exposes open/close callbacks so listening has exactly the same lifetime.
struct MappingMenu: NSViewRepresentable {
    @ObservedObject var client: Client
    let target: InputTarget

    func makeCoordinator() -> Coordinator { Coordinator(client: client, target: target) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectInput(_:))
        button.bezelStyle = .rounded
        button.alignment = .center
        if let cell = button.cell as? NSPopUpButtonCell {
            cell.arrowPosition = .noArrow
            cell.usesItemFromMenu = false
        }
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        guard !context.coordinator.isListening else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = context.coordinator
        let hint = NSMenuItem(
            title: target.isStick
                ? "Move a stick or press the D-Pad" : "Press a button or choose below",
            action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        let source = client.mapping[target] ?? .none
        var selectedItem: NSMenuItem?
        for availableSource in client.availableSources(for: target) {
            let item = NSMenuItem(
                title: client.sourceLabel(availableSource), action: nil, keyEquivalent: "")
            item.representedObject = availableSource
            item.image = client.sourceImage(availableSource, font: menu.font)
            menu.addItem(item)
            if availableSource == source { selectedItem = item }
        }
        context.coordinator.menu = menu
        button.menu = menu
        button.select(selectedItem)
        let name = client.sourceLabel(source)
        let image = client.sourceImage(
            source, font: button.font ?? .systemFont(ofSize: NSFont.systemFontSize))
        let displayItem = NSMenuItem(
            title: image == nil ? name : "", action: nil, keyEquivalent: "")
        displayItem.image = image
        (button.cell as? NSPopUpButtonCell)?.menuItem = displayItem
        button.imagePosition = image == nil ? .noImage : .imageOnly
        button.toolTip = name
        button.setAccessibilityLabel("Map \(target.rawValue): \(name)")
    }

    static func dismantleNSView(_ view: NSPopUpButton, coordinator: Coordinator) {
        coordinator.capture?.cancel()
        coordinator.menu?.delegate = nil
        coordinator.menu?.cancelTracking()
        view.target = nil
        guard coordinator.isListening else { return }
        coordinator.isListening = false
        DispatchQueue.main.async { [client = coordinator.client, target = coordinator.target] in
            if client.mappingTarget == target { client.cancelMapping() }
        }
    }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        let client: Client
        let target: InputTarget
        var menu: NSMenu?
        var isListening = false
        fileprivate var capture: AnyCancellable?

        init(client: Client, target: InputTarget) {
            self.client = client
            self.target = target
            super.init()
            capture = client.$mappingTarget.sink { [weak self] selected in
                guard let self, self.isListening, selected != self.target else { return }
                DispatchQueue.main.async { [weak menu = self.menu] in menu?.cancelTracking() }
            }
        }

        func menuWillOpen(_ menu: NSMenu) {
            client.beginMapping(target)
            isListening = true
        }

        func menuDidClose(_ menu: NSMenu) {
            isListening = false
            if client.mappingTarget == target { client.cancelMapping() }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isListening else { return }
                self.client.objectWillChange.send()
            }
        }

        @objc func selectInput(_ sender: NSPopUpButton) {
            guard let source = sender.selectedItem?.representedObject as? InputSource else {
                return
            }
            client.cancelMapping()
            client.mapping[target] = source
            client.save()
        }
    }
}
