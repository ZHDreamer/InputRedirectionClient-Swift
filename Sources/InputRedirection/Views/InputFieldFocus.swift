import AppKit
import SwiftUI

enum InputFieldFocus {
    case address
    case sendRate
}

struct InputFocusDismissal: NSViewRepresentable {
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onDismiss = onDismiss
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    @MainActor final class Coordinator {
        weak var view: NSView?
        var onDismiss: () -> Void
        private var monitor: Any?

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])
            {
                [weak self] event in
                self?.dismissFocus(for: event)
                return event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        func dismissFocus(for event: NSEvent) {
            guard let window = view?.window, event.window === window,
                let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
                let content = window.contentView
            else { return }
            let point =
                content.superview?.convert(event.locationInWindow, from: nil)
                ?? event.locationInWindow
            var hit = content.hitTest(point)
            while let candidate = hit {
                if let field = candidate as? NSTextField, field.isEditable && field.isEnabled {
                    return
                }
                if let text = candidate as? NSTextView, text.isEditable { return }
                hit = candidate.superview
            }
            if window.makeFirstResponder(nil) { onDismiss() }
        }
    }
}
