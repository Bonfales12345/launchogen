import SwiftUI

struct GameDock: View {
    @EnvironmentObject private var library: GameLibraryManager
    @Binding var focusedIndex: Int
    @Binding var mode: DockMode

    private var itemCount: Int { library.games.count + 1 }
    private var addTileIndex: Int { library.games.count }

    private let addTileID = "add-tile"

    @State private var draggingID: GameItem.ID?

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
                                    library.launch(game)
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
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            library.moveGame(id: droppedID, toIndex: index)
                                        }
                                        focusedIndex = index
                                    }
                                )
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
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled(false)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .background(
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
            .overlay(alignment: .top) {
                if let jigglingID = mode.jigglingID,
                   let jigglingGame = library.games.first(where: { $0.id == jigglingID }) {
                    RemoveAppCard(
                        isFocused: mode.isCardFocused,
                        onRemove: {
                            library.removeGame(jigglingGame)
                            focusedIndex = min(focusedIndex, max(0, itemCount - 2))
                            mode = .normal
                        },
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.18)) { mode = .normal }
                        }
                    )
                    .offset(y: 22 - (112 + 16))
                    .zIndex(10)
                    .transition(.identity)
                }
            }
            .onChange(of: focusedIndex) { _, newValue in
                let target: AnyHashable = newValue == addTileIndex ? addTileID : newValue
                withAnimation(.easeInOut(duration: 0.28)) {
                    scrollProxy.scrollTo(target, anchor: .center)
                }
            }
        }
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
