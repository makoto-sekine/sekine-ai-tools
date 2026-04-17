import Foundation

final class TagStore {
    private let queue = DispatchQueue(label: "co.brewus.timemanager.TagStore")

    func load() -> TagLibrary {
        queue.sync {
            let url = FileStoreLocation.tagsFile
            guard FileManager.default.fileExists(atPath: url.path) else {
                return TagLibrary.defaultLibrary
            }
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder.timeline.decode(TagLibrary.self, from: data)
            } catch {
                NSLog("TagStore.load failed: \(error)")
                return TagLibrary.defaultLibrary
            }
        }
    }

    func save(_ library: TagLibrary) {
        queue.sync {
            do {
                try FileStoreLocation.ensureDirectoryStructure()
                let data = try JSONEncoder.timelinePretty.encode(library)
                try AtomicFileWriter.write(data, to: FileStoreLocation.tagsFile)
            } catch {
                NSLog("TagStore.save failed: \(error)")
            }
        }
    }

    func ensureSeeded() {
        queue.sync {
            let url = FileStoreLocation.tagsFile
            guard !FileManager.default.fileExists(atPath: url.path) else { return }
            do {
                try FileStoreLocation.ensureDirectoryStructure()
                let data = try JSONEncoder.timelinePretty.encode(TagLibrary.defaultLibrary)
                try AtomicFileWriter.write(data, to: url)
            } catch {
                NSLog("TagStore.ensureSeeded failed: \(error)")
            }
        }
    }
}
