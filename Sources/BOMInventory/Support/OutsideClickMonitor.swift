import AppKit
import SwiftUI

/// Observes mouse events without consuming them, so clicking another control both
/// dismisses autocomplete and performs that control's normal action on the first click.
struct OutsideClickMonitor: NSViewRepresentable {
    var fieldRect: CGRect
    var menuRect: CGRect
    var dismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        context.coordinator.view = view
        context.coordinator.update(self)
        context.coordinator.install()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.update(self) }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator {
        weak var view: NSView?
        private var fieldRect = CGRect.zero
        private var menuRect = CGRect.zero
        private var dismiss: (() -> Void)?
        private var mouseMonitor: Any?
        private var activationObserver: NSObjectProtocol?

        func update(_ input: OutsideClickMonitor) {
            fieldRect = input.fieldRect
            menuRect = input.menuRect
            dismiss = input.dismiss
        }
        func install() {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                self?.observe(event)
                return event
            }
            activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.dismiss?() }
        }
        private func observe(_ event: NSEvent) {
            guard let view, let window = view.window else { return }
            guard event.window === window else { dismiss?(); return }
            let point = view.convert(event.locationInWindow, from: nil)
            if !fieldRect.contains(point) && !menuRect.contains(point) { dismiss?() }
        }
        func stop() {
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
            mouseMonitor = nil
            activationObserver = nil
            dismiss = nil
        }
        deinit { stop() }
    }
    private final class PassthroughView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
