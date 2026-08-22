import SwiftUI
import AppKit

struct KeyboardNavigationCatcher: NSViewRepresentable {
    var onLeft: () -> Void
    var onRight: () -> Void
    var onUp: () -> Void
    var onDown: () -> Void
    var onActivate: () -> Void
    var onHoldActivate: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onLeft = onLeft
        view.onRight = onRight
        view.onUp = onUp
        view.onDown = onDown
        view.onActivate = onActivate
        view.onHoldActivate = onHoldActivate
        view.onEscape = onEscape
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onLeft = onLeft
        nsView.onRight = onRight
        nsView.onUp = onUp
        nsView.onDown = onDown
        nsView.onActivate = onActivate
        nsView.onHoldActivate = onHoldActivate
        nsView.onEscape = onEscape
        guard let window = nsView.window else { return }
        let responder = window.firstResponder
        if responder == nil || responder === window.contentView || responder === window {
            DispatchQueue.main.async {
                window.makeFirstResponder(nsView)
            }
        }
    }

    final class KeyCatcherView: NSView {
        var onLeft: (() -> Void)?
        var onRight: (() -> Void)?
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onActivate: (() -> Void)?
        var onHoldActivate: (() -> Void)?
        var onEscape: (() -> Void)?

        private let holdThreshold: TimeInterval = 0.45

        private var holdWorkItem: DispatchWorkItem?
        private var holdFired = false
        private var isReturnKeyDown = false

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 123:
                onLeft?()
            case 124:
                onRight?()
            case 125:
                onDown?()
            case 126:
                onUp?()
            case 53:
                onEscape?()
            case 36, 76:
                guard !isReturnKeyDown else { return }
                isReturnKeyDown = true
                holdFired = false

                let workItem = DispatchWorkItem { [weak self] in
                    guard let self, self.isReturnKeyDown else { return }
                    self.holdFired = true
                    self.onHoldActivate?()
                }
                holdWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: workItem)
            default:
                super.keyDown(with: event)
            }
        }

        override func keyUp(with event: NSEvent) {
            switch event.keyCode {
            case 36, 76:
                isReturnKeyDown = false
                holdWorkItem?.cancel()
                holdWorkItem = nil
                if !holdFired {
                    onActivate?()
                }
                holdFired = false
            default:
                super.keyUp(with: event)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
    }
}
