import Foundation

enum DockMode: Equatable {
    case normal
    case jiggling(GameItem.ID)
    case cardFocused(GameItem.ID)

    var jigglingID: GameItem.ID? {
        switch self {
        case .normal: return nil
        case .jiggling(let id), .cardFocused(let id): return id
        }
    }

    var isCardFocused: Bool {
        if case .cardFocused = self { return true }
        return false
    }
}
