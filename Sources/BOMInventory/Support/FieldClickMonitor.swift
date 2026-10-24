import AppKit
import SwiftUI

/// SwiftUI's focus callback does not fire when an already-focused text field is clicked.
/// Observe that mouse-down without taking over the text field's event handling.
struct FieldClickMonitor: NSViewRepresentable {
    var clicked: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        context.coordinator.view = view
        context.coordinator.clicked = clicked
        context.coordinator.install()
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.clicked = clicked }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }
    final class Coordinator {
        weak var view: NSView?
        var clicked: (() -> Void)?
        private var monitor: Any?
        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                if let self, let view = self.view, let window = view.window,
                   event.window === window, view.bounds.contains(view.convert(event.locationInWindow, from: nil)) {
                    self.clicked?()
                }
                return event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; clicked = nil }
        deinit { stop() }
    }
    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
