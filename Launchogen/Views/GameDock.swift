import SwiftUI

/// Reports each visible tile's frame, converted into the shared
/// "launcherScreen" coordinate space that ContentView establishes at the
/// window root. Two features depend on this: the remove card needs to
/// anchor itself to whichever tile is jiggling, and the tvOS-style
/// zoom-launch needs the tapped tile's true on-screen rect as the
/// animation's starting frame. Reading real frames (rather than assuming a
/// tile is centered) is what makes both correct at the edges of the row,
/// where the ScrollView can't fully center a tile because it's already hit
/// its scrollable bounds.
struct TileFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [GameItem.ID: CGRect] = [:]
    static func reduce(value: inout [GameItem.ID: CGRect], nextValue: () -> [GameItem.ID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct GameDock: View {
    @EnvironmentObject private var library: GameLibraryManager
    @Binding var focusedIndex: Int
    @Binding var mode: DockMode

    private var itemCount: Int { library.games.count + 1 }
    private var addTileIndex: Int { library.games.count }

    private let addTileID = "add-tile"
    private let cardGap: CGFloat = 16

    @State private var draggingID: GameItem.ID?
    @State private var tileFrames: [GameItem.ID: CGRect] = [:]

    /// Fired on every activation path — tap and keyboard Return both call
    /// this — with the game and its current on-screen frame in
    /// "launcherScreen" space, so ContentView can run the same
    /// zoom-then-launch sequence no matter how the tile was activated.
    var onActivate: (GameItem, CGRect) -> Void = { _, _ in }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(library.games.enumerated()), id: \.element.id) { index, game in
                        let isJiggling = mode.jigglingID == game.id

                        GameTile(game: game, isFocused: focusedIndex == index)
                            .id(index)
                            .jiggling(isJiggling)
                            .opacity(draggingID == game.id ? 0.35 : 1.0)
                            .onHover { isHovering in
                                if isHovering { focusedIndex = index }
                            }
                            .onTapGesture {
                                if mode != .normal {
                                    withAnimation(.easeOut(duration: 0.18)) { mode = .normal }
                                } else {
                                    focusedIndex = index
                                    onActivate(game, tileFrames[game.id] ?? .zero)
                                }
                            }
                            .contentShape(Rectangle())
                            .background(
                                RightClickCatcher {
                                    focusedIndex = index
                                    enterJiggleMode(for: game.id)
                                }
                            )
                            .modifier(
                                ReorderDragModifier(
                                    isEnabled: isJiggling,
                                    gameID: game.id,
                                    draggingID: $draggingID,
                                    onDrop: { droppedID in
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                            library.moveGame(id: droppedID, toIndex: index)
                                        }
                                        focusedIndex = index
                                    }
                                )
                            )
                            .background(
                                GeometryReader { tileGeometry in
                                    Color.clear.preference(
                                        key: TileFramesPreferenceKey.self,
                                        value: [game.id: tileGeometry.frame(in: .named("launcherScreen"))]
                                    )
                                }
                            )
                    }

                    AddGameTile(isFocused: focusedIndex == addTileIndex)
                        .id(addTileID)
                        .onHover { isHovering in
                            if isHovering { focusedIndex = addTileIndex }
                        }
                        .onTapGesture {
                            focusedIndex = addTileIndex
                            presentPicker()
                        }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .scrollTargetLayout()
            }
            .onPreferenceChange(TileFramesPreferenceKey.self) { frames in
                tileFrames = frames
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled(false)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                // Native "Liquid Glass" effect — system material only, no custom blur.
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
            )
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
            .onChange(of: focusedIndex) { _, newValue in
                let target: AnyHashable = newValue == addTileIndex ? addTileID : newValue
                withAnimation(.easeInOut(duration: 0.28)) {
                    scrollProxy.scrollTo(target, anchor: .center)
                }
            }
        }
        // Drawn as a sibling of the ScrollView — outside its clip shape and
        // outside the horizontally-scrolling content — so the card is never
        // cropped by the panel edge. GeometryReader here gives this
        // overlay's own origin in "launcherScreen" space; subtracting that
        // from the tile's screen-space frame converts it into this overlay's
        // local coordinates. Anchoring with .overlay(alignment: .bottom) at
        // that x-position, then padding up by the tile's remaining height
        // plus the gap, lets SwiftUI measure the card's real height itself —
        // matching the original design's intent — rather than hardcoding a
        // height that would drift out of sync if the card's copy or padding
        // ever changes.
        .overlay {
            GeometryReader { overlayGeometry in
                let overlayOrigin = overlayGeometry.frame(in: .named("launcherScreen")).origin
                if let jigglingID = mode.jigglingID, let screenFrame = tileFrames[jigglingID] {
                    let localMidX = screenFrame.midX - overlayOrigin.x
                    let localTopY = screenFrame.minY - overlayOrigin.y

                    Color.clear
                        .frame(width: 0, height: 0)
                        .overlay(alignment: .bottom) {
                            RemoveAppCard(
                                isFocused: mode.isCardFocused,
                                onRemove: removeJigglingGame,
                                onDismiss: {
                                    withAnimation(.easeOut(duration: 0.18)) { mode = .normal }
                                }
                            )
                            .fixedSize()
                            .offset(y: -cardGap)
                            .zIndex(10)
                        }
                        .position(x: localMidX, y: localTopY)
                        .allowsHitTesting(true)
                }
            }
            .allowsHitTesting(mode.jigglingID != nil)
        }
    }

    private func removeJigglingGame() {
        guard let jigglingID = mode.jigglingID,
              let game = library.games.first(where: { $0.id == jigglingID }) else {
            mode = .normal
            return
        }
        library.removeGame(game)
        focusedIndex = min(focusedIndex, max(0, itemCount - 2))
        mode = .normal
    }

    private func enterJiggleMode(for id: GameItem.ID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            mode = .jiggling(id)
        }
    }

    private func presentPicker() {
        AppPickerManager.pickApplication { url in
            guard let url else { return }
            library.addGame(at: url)
        }
    }
}

private struct ReorderDragModifier: ViewModifier {
    let isEnabled: Bool
    let gameID: GameItem.ID
    @Binding var draggingID: GameItem.ID?
    let onDrop: (GameItem.ID) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .draggable(gameID.uuidString) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .onAppear { draggingID = gameID }
                }
                .dropDestination(for: String.self) { items, _ in
                    defer { draggingID = nil }
                    guard let raw = items.first, let droppedID = UUID(uuidString: raw) else { return false }
                    onDrop(droppedID)
                    return true
                }
        } else {
            content
        }
    }
}

private struct GameTile: View {
    let game: GameItem
    let isFocused: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.85))
            .frame(width: 168, height: 112)
            .overlay(
                Image(nsImage: game.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(isFocused ? 22 : 26)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 1.0 : 0), lineWidth: 3)
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0.2), radius: isFocused ? 22 : 8, y: isFocused ? 12 : 4)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isFocused)
    }
}

private struct AddGameTile: View {
    let isFocused: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial.opacity(0.6))
            .frame(width: 168, height: 112)
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 1.0 : 0.35), lineWidth: isFocused ? 3 : 1)
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: isFocused ? 20 : 0, y: 10)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isFocused)
    }
}

#Preview {
    ZStack {
        Color.black
        GameDock(focusedIndex: .constant(0), mode: .constant(.normal))
            .environmentObject(GameLibraryManager())
    }
    .coordinateSpace(name: "launcherScreen")
}

private struct RightClickCatcher: NSViewRepresentable {
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class CatcherView: NSView {
        var onRightClick: (() -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }
    }
}
