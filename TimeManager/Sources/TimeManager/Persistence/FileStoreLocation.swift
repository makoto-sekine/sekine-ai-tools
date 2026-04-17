import Foundation

enum FileStoreLocation {
    static let folderName = "TimeManager"

    static var root: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(folderName, isDirectory: true)
    }

    static var daysDirectory: URL { root.appendingPathComponent("days", isDirectory: true) }
    static var trashDirectory: URL { root.appendingPathComponent("trash", isDirectory: true) }
    static var backupsDirectory: URL { root.appendingPathComponent("backups", isDirectory: true) }
    static var tagsFile: URL { root.appendingPathComponent("tags.json") }
    static var settingsFile: URL { root.appendingPathComponent("settings.json") }

    static func dayFile(for date: DayDate) -> URL {
        daysDirectory.appendingPathComponent("\(date.key).json")
    }

    static func ensureDirectoryStructure() throws {
        let fm = FileManager.default
        for url in [root, daysDirectory, trashDirectory, backupsDirectory] {
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }
}
