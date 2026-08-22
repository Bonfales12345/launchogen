//
//  GameLibraryManager.swift
//  Launchogen
//
//  Created by Bonfales on 8/22/26.
//


import Foundation
import AppKit
import Combine

/// Owns the list of launcher entries, persists them to disk as JSON,
/// and handles launching external .app bundles via NSWorkspace.
@MainActor
final class GameLibraryManager: ObservableObject {

    @Published private(set) var games: [GameItem] = []
    @Published var launchError: String?

    private let storeURL: URL

    /// A handful of common, likely-installed apps so the dock isn't empty
    /// on first run. These are only added if they actually exist on disk.
    private let seedCandidates: [(name: String, path: String)] = [
        ("Roblox", "/Applications/Roblox.app"),
        ("Minecraft", "/Applications/Minecraft.app"),
        ("Steam", "/Applications/Steam.app"),
        ("Discord", "/Applications/Discord.app")
    ]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Launchogen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storeURL = dir.appendingPathComponent("library.json")

        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([GameItem].self, from: data) else {
            seedInitialLibrary()
            return
        }
        // Drop entries whose app bundle has since been removed.
        self.games = decoded.filter { FileManager.default.fileExists(atPath: $0.bundlePath) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(games) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func seedInitialLibrary() {
        let found = seedCandidates
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { GameItem(name: $0.name, bundlePath: $0.path) }
        self.games = found
        save()
    }

    // MARK: - Mutation

    func addGame(at url: URL) {
        // Avoid duplicate entries for the same bundle path.
        guard !games.contains(where: { $0.bundlePath == url.path }) else { return }

        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")

        let item = GameItem(name: name, bundlePath: url.path)
        games.append(item)
        save()
    }

    func removeGame(_ item: GameItem) {
        games.removeAll { $0.id == item.id }
        save()
    }

    /// Moves the game with `id` to sit at `destinationIndex` in the list,
    /// used for drag-to-reorder. No-ops if either side can't be resolved.
    func moveGame(id: GameItem.ID, toIndex destinationIndex: Int) {
        guard let sourceIndex = games.firstIndex(where: { $0.id == id }) else { return }
        let clampedDestination = min(max(destinationIndex, 0), games.count - 1)
        guard sourceIndex != clampedDestination else { return }

        let item = games.remove(at: sourceIndex)
        games.insert(item, at: clampedDestination)
        save()
    }

    // MARK: - Launching

    func launch(_ item: GameItem) {
        guard FileManager.default.fileExists(atPath: item.bundlePath) else {
            launchError = "\"\(item.name)\" could not be found. It may have been moved or deleted."
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: item.bundleURL, configuration: configuration) { [weak self] app, error in
            if let error {
                Task { @MainActor in
                    self?.launchError = "Couldn't launch \(item.name): \(error.localizedDescription)"
                }
            } else if let app {
                Task { @MainActor in
                    FullScreenLauncher.forceFullScreen(for: app)
                }
            }
        }
    }
}