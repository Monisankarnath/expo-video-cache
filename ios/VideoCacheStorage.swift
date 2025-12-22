import Foundation
import CryptoKit

/// Handles file system operations: Hashing, saving, loading, and cleaning up cache.
internal class VideoCacheStorage {
    private let fileManager = FileManager.default
    private let maxCacheSize: Int
    
    /// The directory where we store cached files: Library/Caches/ExpoVideoCache
    private lazy var cacheDirectory: URL = {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDir = paths[0].appendingPathComponent("ExpoVideoCache")
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        return cacheDir
    }()

    init(maxCacheSize: Int) {
        self.maxCacheSize = maxCacheSize
    }

    func clearAll() {
        do {
            if fileManager.fileExists(atPath: cacheDirectory.path) {
                try fileManager.removeItem(at: cacheDirectory)
                print("🧹 ExpoVideoCache: All cache cleared and directory deleted.")
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                print("✅ ExpoVideoCache: cache directory recreated.")
            }
        } catch {
            print("⚠️ ExpoVideoCache: Failed to clear cache: \(error)")
        }
    }

    /// Generates a stable filename hash from a URL.
    /// Uses Base64 encoding to ensure the filename is the same across app restarts.
    func getFilePath(for urlString: String) -> URL {
        guard let data = urlString.data(using: .utf8) else {
            return cacheDirectory.appendingPathComponent("unknown.bin")
        }
        
        let hash = SHA256.hash(data: data)
        let safeFilename = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        let extensionName = urlString.hasSuffix(".ts") ? ".ts" : ".bin"
        return cacheDirectory.appendingPathComponent(safeFilename + extensionName)
    }

    /// Checks if a file exists and updates its "Last Access Date" so it doesn't get pruned.
    func getCachedData(for urlString: String) -> Data? {
        let fileUrl = getFilePath(for: urlString)
        
        if fileManager.fileExists(atPath: fileUrl.path) {
            // Touch the file (Update modification date to now)
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileUrl.path)
            return try? Data(contentsOf: fileUrl)
        }
        return nil
    }

    /// Saves data to the cache directory.
    func save(data: Data, for urlString: String) {
        let fileUrl = getFilePath(for: urlString)
        try? data.write(to: fileUrl, options: .atomic)
    }

    /// Runs the LRU (Least Recently Used) cleanup logic.
    /// Deletes the oldest files until the cache is smaller than `maxCacheSize`.
    func prune() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        
        do {
            let fileUrls = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: keys, options: [])
            
            var totalSize = 0
            var files: [(url: URL, size: Int, date: Date)] = []
            
            // 1. Calculate total size
            for url in fileUrls {
                let values = try url.resourceValues(forKeys: Set(keys))
                if let size = values.fileSize, let date = values.contentModificationDate {
                    totalSize += size
                    files.append((url, size, date))
                }
            }
            
            // 2. If under limit, do nothing
            if totalSize < maxCacheSize { return }
            
            print("🧹 ExpoVideoCache: Pruning... Current: \(totalSize/1024/1024)MB, Limit: \(maxCacheSize/1024/1024)MB")
            
            // 3. Sort by oldest date first
            files.sort { $0.date < $1.date }
            
            // 4. Delete files
            for file in files {
                try? fileManager.removeItem(at: file.url)
                totalSize -= file.size
                if totalSize < maxCacheSize { break }
            }
            print("✅ ExpoVideoCache: Pruning Complete.")
            
        } catch {
            print("⚠️ ExpoVideoCache: Prune failed: \(error)")
        }
    }
}