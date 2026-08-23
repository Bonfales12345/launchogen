import AppKit
import SwiftUI
import ApplicationServices
import CoreGraphics

enum FullScreenLauncher {

    @MainActor
    static func enterFullScreenWhenReady() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            attempt(retriesLeft: 20)
        }
    }

    @MainActor
    private static func attempt(retriesLeft: Int) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first else {
            guard retriesLeft > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                attempt(retriesLeft: retriesLeft - 1)
            }
            return
        }

        window.collectionBehavior.insert(.fullScreenPrimary)

        guard !window.styleMask.contains(.fullScreen) else { return }

        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }
    @MainActor
    static func forceFullScreen(for app: NSRunningApplication) {
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.requestIfNeeded()
            return
        }
        pollUntilActive(app: app, retriesLeft: 100)
    }

    @MainActor
    private static func pollUntilActive(app: NSRunningApplication, retriesLeft: Int) {
        if app.isTerminated { return }

        if app.isActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                sendFullScreenShortcut()
            }
            return
        }

        guard retriesLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pollUntilActive(app: app, retriesLeft: retriesLeft - 1)
        }
    }

    private static func sendFullScreenShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let keyCode: CGKeyCode = 3 // 'F'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        let flags: CGEventFlags = [.maskControl, .maskCommand]
        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    static func requestIfNeeded() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
