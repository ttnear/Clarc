import Foundation
import SwiftUI
import ClarcCore

// MARK: - Notifications

extension Notification.Name {
    public static let chatShortcutsDidChange = Notification.Name("ChatShortcutRegistry.shortcutsDidChange")
}

// MARK: - Chat Shortcut Data

public struct ChatShortcut: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var message: String
    public var isTerminalCommand: Bool

    public init(id: UUID = UUID(), name: String, message: String, isTerminalCommand: Bool = false) {
        self.id = id
        self.name = name
        self.message = message
        self.isTerminalCommand = isTerminalCommand
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        message = try container.decode(String.self, forKey: .message)
        isTerminalCommand = try container.decodeIfPresent(Bool.self, forKey: .isTerminalCommand) ?? false
    }
}

// MARK: - Chat Shortcut Registry (Per-Project)

@MainActor
public enum ChatShortcutRegistry {
    private static var currentProjectPath: String?
    private static var shortcuts: [ChatShortcut] = []

    // MARK: - Project Binding

    public static func bind(to projectPath: String?) {
        guard currentProjectPath != projectPath else { return }
        currentProjectPath = projectPath
        shortcuts = loadShortcuts(for: projectPath)
    }

    public static var currentShortcuts: [ChatShortcut] {
        shortcuts
    }

    // MARK: - CRUD

    public static func add(_ shortcut: ChatShortcut) {
        shortcuts.append(shortcut)
        save()
    }

    public static func update(id: UUID, with updated: ChatShortcut) {
        guard let idx = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        shortcuts[idx] = updated
        save()
    }

    public static func remove(id: UUID) {
        shortcuts.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private static func storeURL(for projectPath: String?) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clarcDir = appSupport.appendingPathComponent("Clarc")

        if let projectPath {
            let safeName = projectPath
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            return clarcDir
                .appendingPathComponent("projects")
                .appendingPathComponent(safeName)
                .appendingPathComponent("shortcuts.json")
        } else {
            return clarcDir.appendingPathComponent("shortcuts_global.json")
        }
    }

    private static func loadShortcuts(for projectPath: String?) -> [ChatShortcut] {
        let url = storeURL(for: projectPath)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ChatShortcut].self, from: data)
        else { return [] }
        return decoded
    }

    private static func save() {
        let url = storeURL(for: currentProjectPath)
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(shortcuts)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save shortcuts: \(error)")
        }
        NotificationCenter.default.post(name: .chatShortcutsDidChange, object: nil)
    }

    // MARK: - Export / Import

    public static func exportShortcuts() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if shortcuts.isEmpty {
            let example = [ChatShortcut(
                id: UUID(),
                name: "Example Shortcut",
                message: "This text will be sent to Claude",
                isTerminalCommand: false
            )]
            return try? encoder.encode(example)
        }
        return try? encoder.encode(shortcuts)
    }

    public static func importShortcuts(from data: Data) -> Bool {
        guard let imported = try? JSONDecoder().decode([ChatShortcut].self, from: data) else {
            return false
        }
        shortcuts = imported
        save()
        return true
    }
}
