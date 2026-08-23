import Foundation
import AppKit

struct GameItem: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var bundlePath: String
    var isPlaceholder: Bool

    init(id: UUID = UUID(), name: String, bundlePath: String, isPlaceholder: Bool = false) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.isPlaceholder = isPlaceholder
    }

    var bundleURL: URL {
        URL(fileURLWithPath: bundlePath)
    }

    var icon: NSImage {
        guard !isPlaceholder, FileManager.default.fileExists(atPath: bundlePath) else {
            return NSWorkspace.shared.icon(forFileType: "app")
        }
        return NSWorkspace.shared.icon(forFile: bundlePath)
    }

    static func == (lhs: GameItem, rhs: GameItem) -> Bool {
        lhs.id == rhs.id && lhs.bundlePath == rhs.bundlePath
    }
}
