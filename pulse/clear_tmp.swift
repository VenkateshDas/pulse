import Foundation

let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
do {
    let contents = try FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: [.fileSizeKey])
    for file in contents {
        if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = attrs.fileSize {
            if size > 1_000_000_000 {
                print("Deleting giant file: \(file.path) (\(size / 1_000_000) MB)")
                try FileManager.default.removeItem(at: file)
            }
        }
    }
} catch {
    print("Error: \(error)")
}
