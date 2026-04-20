import Foundation

final class SettingsStore {
    private let queue = DispatchQueue(label: "co.brewus.timemanager.SettingsStore")

    func load() -> AppSettings {
        queue.sync {
            let url = FileStoreLocation.settingsFile
            guard FileManager.default.fileExists(atPath: url.path) else {
                return AppSettings.current
            }
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder.timeline.decode(AppSettings.self, from: data)
            } catch {
                NSLog("SettingsStore.load failed: \(error)")
                return AppSettings.current
            }
        }
    }

    func save(_ settings: AppSettings) {
        queue.sync {
            do {
                try FileStoreLocation.ensureDirectoryStructure()
                let data = try JSONEncoder.timelinePretty.encode(settings)
                try AtomicFileWriter.write(data, to: FileStoreLocation.settingsFile)
            } catch {
                NSLog("SettingsStore.save failed: \(error)")
            }
        }
    }
}
