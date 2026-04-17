import Foundation

final class DayFileStore {
    private let queue = DispatchQueue(label: "co.brewus.timemanager.DayFileStore")

    func load(_ date: DayDate) -> DayData {
        queue.sync {
            let url = FileStoreLocation.dayFile(for: date)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return DayData.empty(for: date)
            }
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder.timeline.decode(DayData.self, from: data)
            } catch {
                NSLog("DayFileStore.load(\(date.key)) failed: \(error)")
                return DayData.empty(for: date)
            }
        }
    }

    func save(_ day: DayData) {
        queue.sync {
            do {
                try FileStoreLocation.ensureDirectoryStructure()
                let data = try JSONEncoder.timelinePretty.encode(day)
                try AtomicFileWriter.write(data, to: FileStoreLocation.dayFile(for: day.date))
            } catch {
                NSLog("DayFileStore.save(\(day.date.key)) failed: \(error)")
            }
        }
    }

    func moveToTrash(slot: Slot, from date: DayDate) {
        queue.sync {
            do {
                try FileStoreLocation.ensureDirectoryStructure()
                let filename = "\(date.key)-\(slot.id.uuidString).json"
                let url = FileStoreLocation.trashDirectory.appendingPathComponent(filename)
                var envelope: [String: Any] = [
                    "date": date.key,
                    "deletedAt": ISO8601DateFormatter().string(from: Date())
                ]
                let slotData = try JSONEncoder.timelinePretty.encode(slot)
                if let slotJson = try JSONSerialization.jsonObject(with: slotData) as? [String: Any] {
                    envelope["slot"] = slotJson
                }
                let data = try JSONSerialization.data(
                    withJSONObject: envelope,
                    options: [.prettyPrinted, .sortedKeys]
                )
                try AtomicFileWriter.write(data, to: url)
            } catch {
                NSLog("DayFileStore.moveToTrash failed: \(error)")
            }
        }
    }
}
