import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: GameLibraryManager
    @StateObject private var wallpaper = WallpaperProvider()
    @State private var focusedIndex: Int = 0
    @State private var mode: DockMode = .normal

    private var focusedGame: GameItem? {
        guard library.games.indices.contains(focusedIndex) else { return nil }
        return library.games[focusedIndex]
    }

    private var itemCount: Int { library.games.count + 1 } // + the Add tile

    var body: some View {
        ZStack {
            WallpaperBackground(image: wallpaper.image)
            if mode != .normal {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { exitJiggleMode() }
            }

            VStack(spacing: 0) {
                Spacer()

                GameTitleLabel(name: focusedGame?.name)
                    .padding(.bottom, 36)

                GameDock(focusedIndex: $focusedIndex, mode: $mode)
            }

            KeyboardNavigationCatcher(
                onLeft: { handleDirection(-1) },
                onRight: { handleDirection(1) },
                onUp: handleUp,
                onDown: handleDown,
                onActivate: handleActivate,
                onHoldActivate: enterJiggleModeForFocusedTile,
                onEscape: exitJiggleMode
            )
            .allowsHitTesting(false)
        }
        .frame(minWidth: 1100, minHeight: 700)
        .alert(
            "Launch Failed",
            isPresented: Binding(
                get: { library.launchError != nil },
                set: { if !$0 { library.launchError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { library.launchError = nil }
        } message: {
            Text(library.launchError ?? "")
        }
    }

    private func handleDirection(_ delta: Int) {
        switch mode {
        case .normal:
            moveFocus(by: delta)
        case .jiggling(let id):
            reposition(id: id, by: delta)
        case .cardFocused:
            break
        }
    }

    private func handleUp() {
        if case .jiggling(let id) = mode {
            withAnimation(.easeOut(duration: 0.15)) {
                mode = .cardFocused(id)
            }
        }
    }

    private func handleDown() {
        if case .cardFocused(let id) = mode {
            withAnimation(.easeOut(duration: 0.15)) {
                mode = .jiggling(id)
            }
        }
    }

    private func handleActivate() {
        switch mode {
        case .normal:
            activateFocusedTile()
        case .jiggling:
            exitJiggleMode()
        case .cardFocused(let id):
            removeGame(id: id)
        }
    }

    private func activateFocusedTile() {
        if let game = focusedGame {
            library.launch(game)
        } else {
            AppPickerManager.pickApplication { url in
                guard let url else { return }
                library.addGame(at: url)
            }
        }
    }

    private func moveFocus(by delta: Int) {
        guard itemCount > 0 else { return }
        let next = focusedIndex + delta
        focusedIndex = min(max(next, 0), itemCount - 1)
    }

    private func reposition(id: GameItem.ID, by delta: Int) {
        guard let currentIndex = library.games.firstIndex(where: { $0.id == id }) else { return }
        let destination = currentIndex + delta
        guard library.games.indices.contains(destination) else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            library.moveGame(id: id, toIndex: destination)
        }
        focusedIndex = destination
    }

    private func enterJiggleModeForFocusedTile() {
        guard let game = focusedGame else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            mode = .jiggling(game.id)
        }
    }

    private func exitJiggleMode() {
        withAnimation(.easeOut(duration: 0.18)) {
            mode = .normal
        }
    }

    private func removeGame(id: GameItem.ID) {
        guard let game = library.games.first(where: { $0.id == id }) else {
            exitJiggleMode()
            return
        }
        library.removeGame(game)
        focusedIndex = min(focusedIndex, max(0, itemCount - 2))
        mode = .normal
    }
}
private struct WallpaperBackground: View {
    let image: NSImage?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.06)
                        .blur(radius: 18)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Color(white: 0.25), Color(white: 0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .overlay(
            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .center,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea()
    }
}

private struct GameTitleLabel: View {
    let name: String?

    var body: some View {
        Text(name ?? " ")
            .font(.system(size: 64, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.18), value: name)
    }
}

#Preview {
    ContentView()
        .environmentObject(GameLibraryManager())
}
