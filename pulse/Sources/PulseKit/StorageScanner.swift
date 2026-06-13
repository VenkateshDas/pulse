import Foundation
import Darwin

public struct StorageNode: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let path: String
    public let sizeBytes: UInt64
    public let isDirectory: Bool
    public let fileCount: Int?
    public let children: [StorageNode]?
    
    public init(id: String, name: String, path: String, sizeBytes: UInt64, isDirectory: Bool, fileCount: Int? = nil, children: [StorageNode]? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
        self.fileCount = fileCount
        self.children = children
    }
}

public struct StorageScanner: Sendable {
    public let rootURL: URL
    
    public init(rootURL: URL = URL(fileURLWithPath: "/")) {
        self.rootURL = rootURL
    }
    
    static let prunedPaths: Set<String> = [
        "/System/Volumes/Data",
        "/System/Volumes/VM",
        "/System/Volumes/Preboot",
        "/System/Volumes/Update",
        "/Network",
        "/net",
        "/home",
        "/.Spotlight-V100",
        "/.Trashes",
        "/.fseventsd",
        "/.DocumentRevisions-V100",
        "/dev"
    ]
    
    public func scan(maxDepth: Int = 4) -> StorageNode {
        var scannedFiles = 0
        let rootPath = rootURL.path
        return rootPath.withCString {
            walk($0, depth: 0, maxDepth: maxDepth, fileCount: &scannedFiles)
        }
    }
    
    public func shallowScan(path: String) -> StorageNode {
        let name = path == "/" ? "Macintosh HD" : (URL(fileURLWithPath: path).lastPathComponent)
        
        if Self.prunedPaths.contains(path) {
            return StorageNode(id: path, name: name, path: path, sizeBytes: 0, isDirectory: true, children: [])
        }
        
        return path.withCString { pathPtr in
            guard let dir = opendir(pathPtr) else {
                return StorageNode(id: path, name: name, path: path, sizeBytes: 0, isDirectory: true, children: [])
            }
            
            var totalBytes: UInt64 = 0
            var childNodes: [StorageNode] = []
            
            while let entry = readdir(dir) {
                let ent = entry.pointee
                var type = Int32(ent.d_type)
                
                let n0 = ent.d_name.0, n1 = ent.d_name.1, n2 = ent.d_name.2
                if n0 == 46 && n1 == 0 { continue }
                if n0 == 46 && n1 == 46 && n2 == 0 { continue }
                
                var childPathBuffer = [CChar](repeating: 0, count: 1024)
                strlcpy(&childPathBuffer, pathPtr, 1024)
                if path != "/" { strlcat(&childPathBuffer, "/", 1024) }
                
                var nameBytes = ent.d_name
                _ = withUnsafePointer(to: &nameBytes) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: 256) { namePtr in
                        strlcat(&childPathBuffer, namePtr, 1024)
                    }
                }
                
                if type == DT_UNKNOWN {
                    var st = stat()
                    if lstat(childPathBuffer, &st) == 0 {
                        let mode = st.st_mode & S_IFMT
                        if mode == S_IFDIR { type = Int32(DT_DIR) }
                        else if mode == S_IFREG { type = Int32(DT_REG) }
                        else if mode == S_IFLNK { type = Int32(DT_LNK) }
                    }
                }
                
                if type == DT_LNK { continue }
                
                let childPathStr = childPathBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                let childNameStr = URL(fileURLWithPath: childPathStr).lastPathComponent
                
                if type == DT_REG {
                    var st = stat()
                    if lstat(childPathBuffer, &st) == 0 {
                        let size = UInt64(st.st_blocks) * 512
                        totalBytes += size
                        childNodes.append(StorageNode(id: childPathStr, name: childNameStr, path: childPathStr, sizeBytes: size, isDirectory: false, children: nil))
                    }
                } else if type == DT_DIR {
                    let childPathStr = childPathBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                    if Self.prunedPaths.contains(childPathStr) { continue }
                    childNodes.append(StorageNode(id: childPathStr, name: childNameStr, path: childPathStr, sizeBytes: 0, isDirectory: true, children: []))
                }
            }
            closedir(dir)
            
            childNodes.sort { $0.sizeBytes > $1.sizeBytes }
            return StorageNode(id: path, name: name, path: path, sizeBytes: totalBytes, isDirectory: true, children: childNodes)
        }
    }
    
    public func scanSizesStream(node: StorageNode) -> AsyncStream<StorageNode> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                let children = node.children ?? []
                var resolvedBytes: UInt64 = 0
                
                await withTaskGroup(of: (Int, UInt64, Int).self) { group in
                    for (index, child) in children.enumerated() {
                        if child.isDirectory {
                            // Directories are summed in the newTotal loop below;
                            // adding them here too would double-count any that
                            // already carry a size (e.g. from a deep scan).
                            if child.sizeBytes == 0 {
                                group.addTask {
                                    let (size, count) = child.path.withCString { pathPtr in
                                        self.fastDirectorySize(pathPtr)
                                    }
                                    return (index, size, count)
                                }
                            }
                        } else {
                            resolvedBytes += child.sizeBytes
                        }
                    }
                    
                    var currentChildren = children
                    for await (index, size, count) in group {
                        if size > 0 || count > 0 {
                            let child = currentChildren[index]
                            currentChildren[index] = StorageNode(id: child.id, name: child.name, path: child.path, sizeBytes: size, isDirectory: child.isDirectory, fileCount: count, children: child.children)
                        }
                        
                        var newTotal: UInt64 = resolvedBytes
                        for c in currentChildren { if c.isDirectory { newTotal += c.sizeBytes } }
                        
                        let sortedChildren = currentChildren.sorted { $0.sizeBytes > $1.sizeBytes }
                        let updatedNode = StorageNode(id: node.id, name: node.name, path: node.path, sizeBytes: newTotal, isDirectory: node.isDirectory, children: sortedChildren)
                        continuation.yield(updatedNode)
                    }
                }
                continuation.finish()
            }
        }
    }
    
    private func walk(_ pathPtr: UnsafePointer<CChar>, depth: Int, maxDepth: Int, fileCount: inout Int) -> StorageNode {
        let path = String(cString: pathPtr)
        let name = path == "/" ? "Macintosh HD" : (URL(fileURLWithPath: path).lastPathComponent)
        
        if Self.prunedPaths.contains(path) {
            return StorageNode(id: path, name: name, path: path, sizeBytes: 0, isDirectory: true, children: [])
        }
        
        guard let dir = opendir(pathPtr) else {
            return StorageNode(id: path, name: name, path: path, sizeBytes: 0, isDirectory: true, children: [])
        }
        
        var totalBytes: UInt64 = 0
        var childNodes: [StorageNode] = []
        var looseFilesBytes: UInt64 = 0
        
        while let entry = readdir(dir) {
            let ent = entry.pointee
            var type = Int32(ent.d_type)
            
            let n0 = ent.d_name.0, n1 = ent.d_name.1, n2 = ent.d_name.2
            if n0 == 46 && n1 == 0 { continue }
            if n0 == 46 && n1 == 46 && n2 == 0 { continue }
            
            var childPathBuffer = [CChar](repeating: 0, count: 1024)
            strlcpy(&childPathBuffer, pathPtr, 1024)
            if path != "/" { strlcat(&childPathBuffer, "/", 1024) }
            
            var nameBytes = ent.d_name
            _ = withUnsafePointer(to: &nameBytes) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 256) { namePtr in
                    strlcat(&childPathBuffer, namePtr, 1024)
                }
            }
            
            if type == DT_UNKNOWN {
                var st = stat()
                if lstat(childPathBuffer, &st) == 0 {
                    let mode = st.st_mode & S_IFMT
                    if mode == S_IFDIR { type = Int32(DT_DIR) }
                    else if mode == S_IFREG { type = Int32(DT_REG) }
                    else if mode == S_IFLNK { type = Int32(DT_LNK) }
                }
            }
            
            if type == DT_LNK { continue }
            
            if type == DT_REG {
                var st = stat()
                if lstat(childPathBuffer, &st) == 0 {
                    let size = UInt64(st.st_blocks) * 512
                    totalBytes += size
                    looseFilesBytes += size
                    fileCount += 1
                    
                    if depth < maxDepth && size > 50_000_000 {
                        let childPathStr = childPathBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                        let childNameStr = URL(fileURLWithPath: childPathStr).lastPathComponent
                        childNodes.append(StorageNode(id: childPathStr, name: childNameStr, path: childPathStr, sizeBytes: size, isDirectory: false, children: nil))
                    }
                }
            } else if type == DT_DIR {
                let childPathStr = childPathBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                if Self.prunedPaths.contains(childPathStr) { continue }
                
                if depth < maxDepth {
                    let childNode = walk(childPathBuffer, depth: depth + 1, maxDepth: maxDepth, fileCount: &fileCount)
                    totalBytes += childNode.sizeBytes
                    if childNode.sizeBytes > 0 {
                        childNodes.append(childNode)
                    }
                } else {
                    let (size, count) = fastDirectorySize(childPathBuffer)
                    totalBytes += size
                    fileCount += count + 1
                    if size > 0 || count > 0 {
                        let childNameStr = URL(fileURLWithPath: childPathStr).lastPathComponent
                        childNodes.append(StorageNode(id: childPathStr, name: childNameStr, path: childPathStr, sizeBytes: size, isDirectory: true, fileCount: count, children: []))
                    }
                }
            }
        }
        closedir(dir)
        
        if depth < maxDepth && looseFilesBytes > 0 {
            let largeFilesSize = childNodes.filter { !$0.isDirectory }.reduce(0) { $0 + $1.sizeBytes }
            let otherFilesSize = looseFilesBytes > largeFilesSize ? looseFilesBytes - largeFilesSize : 0
            if otherFilesSize > 0 {
                childNodes.append(StorageNode(id: "\(path)/_other_files", name: "Other Files", path: path, sizeBytes: otherFilesSize, isDirectory: false, children: nil))
            }
        }
        
        childNodes.sort { $0.sizeBytes > $1.sizeBytes }
        return StorageNode(id: path, name: name, path: path, sizeBytes: totalBytes, isDirectory: true, children: childNodes)
    }
    
    private func fastDirectorySize(_ pathPtr: UnsafePointer<CChar>) -> (UInt64, Int) {
        guard let dir = opendir(pathPtr) else { return (0, 0) }
        var totalSize: UInt64 = 0
        var totalCount: Int = 0
        
        while let entry = readdir(dir) {
            let ent = entry.pointee
            var type = Int32(ent.d_type)
            
            let n0 = ent.d_name.0, n1 = ent.d_name.1, n2 = ent.d_name.2
            if n0 == 46 && n1 == 0 { continue }
            if n0 == 46 && n1 == 46 && n2 == 0 { continue }
            
            totalCount += 1
            
            var childPathBuffer = [CChar](repeating: 0, count: 1024)
            strlcpy(&childPathBuffer, pathPtr, 1024)
            strlcat(&childPathBuffer, "/", 1024)
            
            var nameBytes = ent.d_name
            _ = withUnsafePointer(to: &nameBytes) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 256) { namePtr in
                    strlcat(&childPathBuffer, namePtr, 1024)
                }
            }
            
            if type == DT_UNKNOWN {
                var st = stat()
                if lstat(childPathBuffer, &st) == 0 {
                    let mode = st.st_mode & S_IFMT
                    if mode == S_IFDIR { type = Int32(DT_DIR) }
                    else if mode == S_IFREG { type = Int32(DT_REG) }
                    else if mode == S_IFLNK { type = Int32(DT_LNK) }
                }
            }
            
            if type == DT_LNK { continue }
            
            if type == DT_DIR {
                let (childSize, childCount) = fastDirectorySize(childPathBuffer)
                totalSize += childSize
                totalCount += childCount
            } else if type == DT_REG {
                var st = stat()
                if lstat(childPathBuffer, &st) == 0 {
                    totalSize += UInt64(st.st_blocks) * 512
                }
            }
        }
        closedir(dir)
        return (totalSize, totalCount)
    }
    
    public static func hasFullDiskAccess() -> Bool {
        let testURL = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC")
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: testURL.path)
            return true
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                return false
            }
            return false
        }
    }
}
