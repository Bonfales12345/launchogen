import Foundation
import AppKit
import UniformTypeIdentifiers
enum AppPickerManager {

    @MainActor
    static func pickApplication(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Add Game or App"
        panel.message = "Choose an application to add to your launcher."
        panel.prompt = "Add"

        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false

        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                completion(response == .OK ? panel.url : nil)
            }
        } else {
            let response = panel.runModal()
            completion(response == .OK ? panel.url : nil)
        }
    }
}
