import SwiftUI

/// Drives the tvOS/iOS-style launch sequence: the tapped tile's icon
/// scales up from its own frame, expanding to fill the entire window while
/// its corners flatten to a plain black rectangle — then the real app
/// launch fires right as the expansion finishes, so the (unavoidable)
/// NSWorkspace launch latency is masked by the animation instead of
/// showing up as a jump-cut.
@MainActor
private final class LaunchTransition: ObservableObject {
    struct Pending {
        let game: GameItem
        let originFrame: CGRect
    }

    @Published private(set) var pending: Pending?
    @Published private(set) var isExpanded = false

    private var launchWorkItem: DispatchWorkItem?
    private var fallbackResetWorkItem: DispatchWorkItem?
    private var resignObserver: NSObjectProtocol?

    var isActive: Bool { pending != nil }

    func begin(_ game: GameItem, from frame: CGRect, launch: @escaping (GameItem) -> Void) {
        // Ignore re-taps while a launch is already in flight — tvOS debounces
        // this too, and firing NSWorkspace twice would open the app twice.
        guard pending == nil else { return }

        // A zero frame means the tapped tile's on-screen position wasn't
        // available yet (e.g. layout hadn't settled). Rather than animate
        // from a nonsensical origin, fall back to launching immediately
        // with no zoom — still correct, just without the flourish.
        guard frame != .zero else {
            launch(game)
            return
        }

        pending = Pending(game: game, originFrame: frame)

        withAnimation(.timingCurve(0.2, 0.0, 0.0, 1.0, duration: 0.46)) {
            isExpanded = true
        }

        // The real signal that the launched app has taken over is
        // Launchogen itself losing focus — far more reliable than any
        // fixed timer, since app launch time varies a lot (a lightweight
        // utility vs. a large game can differ by seconds). Once Launchogen
        // resigns active, the launched app's own window is what's on
        // screen, so it's safe to drop the overlay.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reset()
        }

        let work = DispatchWorkItem { [weak self] in
            launch(game)
        }
        launchWorkItem = work
        // Fires as the expansion is finishing, not after — the real app's
        // own window takes a beat to appear, and that beat is what covers
        // the tail end of the animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: work)

        // Backstop in case the launch fails silently or the app never
        // takes focus (e.g. it opens as a background/menu-bar-only app) —
        // without this, didResignActiveNotification would never fire and
        // the full-screen overlay would stay up forever.
        let fallback = DispatchWorkItem { [weak self] in
            self?.reset()
        }
        fallbackResetWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: fallback)
    }

    func cancel() {
        launchWorkItem?.cancel()
        launchWorkItem = nil
        reset()
    }

    private func reset() {
        fallbackResetWorkItem?.cancel()
        fallbackResetWorkItem = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
        pending = nil
        isExpanded = false
    }
}

struct ContentView: View {
    @EnvironmentObject private var library: GameLibraryManager
    @StateObject private var wallpaper = WallpaperProvider()
    @StateObject private var launchTransition = LaunchTransition()
    @State private var focusedIndex: Int = 0
    @State private var mode: DockMode = .normal
    // Mirrors the same TileFramesPreferenceKey that GameDock reads
    // internally for its tap handler and remove-card anchoring — this copy
    // lets keyboard activation (which has no tap location of its own) look
    // up the currently-focused tile's live on-screen frame too.
    @State private var tileFrames: [GameItem.ID: CGRect] = [:]

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

                GameDock(focusedIndex: $focusedIndex, mode: $mode, onActivate: launch)
                    .onPreferenceChange(TileFramesPreferenceKey.self) { frames in
                        tileFrames = frames
                    }
            }
            .opacity(launchTransition.isExpanded ? 0 : 1)
            .animation(.easeOut(duration: 0.22), value: launchTransition.isExpanded)

            // Invisible layer that owns keyboard focus for the whole screen.
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

            if let pending = launchTransition.pending {
                LaunchZoomOverlay(game: pending.game, originFrame: pending.originFrame, isExpanded: launchTransition.isExpanded)
                    .allowsHitTesting(false)
                    .zIndex(20)
            }
        }
        .coordinateSpace(name: "launcherScreen")
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
            launch(game, from: tileFrames[game.id] ?? .zero)
        } else {
            AppPickerManager.pickApplication { url in
                guard let url else { return }
                library.addGame(at: url)
            }
        }
    }

    /// Shared entry point for every activation path — the tile's own tap
    /// gesture (which already knows its frame and calls this directly via
    /// GameDock's onActivate) and keyboard Return (above, using
    /// tileFrames captured from the same preference GameDock publishes)
    /// both end up here, so the zoom animation plays identically regardless
    /// of how a tile was activated.
    private func launch(_ game: GameItem, from frame: CGRect) {
        launchTransition.begin(game, from: frame) { game in
            library.launch(game)
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
/// The zoom itself: an icon that starts at the tapped tile's exact frame
/// and rounded-corner radius, then grows to fill the entire window while
/// its corners flatten to a plain rectangle — the same shape language
/// tvOS/iOS use when an icon "becomes" the app it opens.
///
/// The icon glyph fades out well before the shape finishes growing, rather
/// than trying to stay visible at full window size. A generic
/// 128×128-class app icon (all Launchogen has — there's no separate
/// high-res "top shelf" art the way tvOS ships per-app) turns visibly
/// blurry if stretched across an entire ~1100pt+ window, so letting it
/// dissolve into the card's own fill color as it grows means the shape
/// keeps expanding all the way to full-bleed black without ever exposing
/// that blur.
private struct LaunchZoomOverlay: View {
    let game: GameItem
    let originFrame: CGRect
    let isExpanded: Bool

    private let tileCornerRadius: CGFloat = 18

    var body: some View {
        GeometryReader { windowGeometry in
            let windowBounds = windowGeometry.frame(in: .named("launcherScreen"))
            let targetFrame = CGRect(origin: .zero, size: windowBounds.size)
            let frame = isExpanded ? targetFrame : originFrame
            let cornerRadius = isExpanded ? 0 : tileCornerRadius

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isExpanded ? Color.black : Color.white.opacity(0.85))
                .overlay(
                    Image(nsImage: game.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(originFrame.width * 0.15)
                        .opacity(isExpanded ? 0 : 1)
                        // Fades out quickly relative to the ~0.46s grow
                        // (see LaunchTransition.begin), rather than
                        // fading at the same linear rate as the shape's
                        // growth. That keeps the icon legible while
                        // it's still small — so the motion reads as
                        // "this icon is becoming the screen" — and
                        // dissolves it before the shape gets large
                        // enough for a stretched low-res icon to look
                        // blurry.
                        .animation(.easeIn(duration: 0.16), value: isExpanded)
                )
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX - windowBounds.minX, y: frame.midY - windowBounds.minY)
        }
        .ignoresSafeArea()
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
