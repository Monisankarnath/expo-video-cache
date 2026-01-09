import Foundation
import CryptoKit

/// Manages the disk persistence layer for video caching.
///
/// This class handles all file system interactions, including:
/// - Generating collision-resistant, filesystem-safe filenames from URLs.
/// - Persisting video data to the `Library/Caches` directory.
/// - Retrieving data.
/// - Enforcing storage limits via a Least Recently Used (LRU) pruning algorithm.
internal class VideoCacheStorage {
    private let fileManager = FileManager.default
    
    /// The maximum allowed size of the cache in bytes.
    private let maxCacheSize: Int
    
    /// The directory where cached files are stored.
    ///
    /// Located at `.../Library/Caches/ExpoVideoCache`.
    /// This property lazily initializes the directory, creating it if it does not exist.
    private lazy var cacheDirectory: URL = {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDir = paths[0].appendingPathComponent("ExpoVideoCache")
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        return cacheDir
    }()

    /// Initializes the storage manager with a defined size limit.
    ///
    /// - Parameter maxCacheSize: The limit (in bytes) before pruning is triggered.
    init(maxCacheSize: Int) {
        self.maxCacheSize = maxCacheSize
    }

    /// Wipes the entire cache directory.
    ///
    /// This operation deletes the `ExpoVideoCache` folder and immediately recreates an empty one.
    /// It is intended for user-requested clears or total resets.
    func clearAll() {
        do {
            if fileManager.fileExists(atPath: cacheDirectory.path) {
                try fileManager.removeItem(at: cacheDirectory)
                print("🧹 ExpoVideoCache: All cache cleared and directory deleted.")
                
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                print("✅ ExpoVideoCache: Cache directory recreated.")
            }
        } catch {
            print("⚠️ ExpoVideoCache: Failed to clear cache: \(error)")
        }
    }

    /// Generates a stable, safe filename from a remote URL.
    ///
    /// Remote URLs often contain characters invalid for filesystems (e.g., `?`, `/`, `:`).
    /// We use a SHA256 hash of the URL to ensure:
    /// 1. The filename is unique to the resource.
    /// 2. The filename is safe for the OS.
    /// 3. The filename length is deterministic.
    ///
    /// - Parameter urlString: The remote video URL.
    /// - Returns: A local file URL pointing to the hashed location on disk.
    func getFilePath(for urlString: String) -> URL {
        guard let data = urlString.data(using: .utf8) else {
            return cacheDirectory.appendingPathComponent("unknown.bin")
        }
        
        let hash = SHA256.hash(data: data)
        let safeFilename = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        var extensionName = "bin"
        if let url = URL(string: urlString) {
            let pathExt = url.pathExtension
            if !pathExt.isEmpty {
                extensionName = pathExt.components(separatedBy: "?")[0].components(separatedBy: "/")[0]
            }
        }
        
        return cacheDirectory.appendingPathComponent("\(safeFilename).\(extensionName)")
    }

    /// Checks if a file exists in the cache without loading its content into memory.
    ///
    /// - Parameter urlString: The original remote URL.
    /// - Returns: `true` if the file exists and has content, `false` otherwise.
    func exists(for urlString: String) -> Bool {
        let fileUrl = getFilePath(for: urlString)
        
        guard fileManager.fileExists(atPath: fileUrl.path) else { return false }
        
        if let attr = try? fileManager.attributesOfItem(atPath: fileUrl.path),
           let size = attr[.size] as? Int64, size > 0 {
            return true
        }
        
        return false
    }
    
    /// Retrieves the file size of a cached item without loading it.
    ///
    /// - Parameter urlString: The original remote URL.
    /// - Returns: The file size in bytes, or `nil` if not found.
    func getFileSize(for urlString: String) -> UInt64? {
        let fileUrl = getFilePath(for: urlString)
        if let attr = try? fileManager.attributesOfItem(atPath: fileUrl.path),
           let size = attr[.size] as? UInt64 {
            return size
        }
        return nil
    }

    /// Retrieves cached data.
    ///
    /// - Parameter urlString: The original remote URL of the video.
    /// - Returns: The cached `Data` if it exists and is valid, otherwise `nil`.
    func getCachedData(for urlString: String) -> Data? {
        let fileUrl = getFilePath(for: urlString)
        
        if fileManager.fileExists(atPath: fileUrl.path) {
            if let data = try? Data(contentsOf: fileUrl), !data.isEmpty {
                return data
            } else {
                try? fileManager.removeItem(at: fileUrl)
            }
        }
        return nil
    }

    /// Persists data to the disk.
    ///
    /// Writes are performed atomically to prevent partial file corruption if the app
    /// crashes during a write operation.
    ///
    /// - Parameters:
    ///   - data: The binary data to save.
    ///   - urlString: The original remote URL (used to derive the filename).
    func save(data: Data, for urlString: String) {
        let fileUrl = getFilePath(for: urlString)
        try? data.write(to: fileUrl, options: .atomic)
    }

    /// Enforces the cache size limit using a Least Recently Used (LRU) strategy.
    ///
    /// This method scans the cache directory, calculates the total size, and if the
    /// limit is exceeded, deletes files starting with the oldest `contentModificationDate`.
    func prune() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        
        do {
            let fileUrls = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: keys,
                options: []
            )
            
            var totalSize = 0
            var files: [(url: URL, size: Int, date: Date)] = []
            
            for url in fileUrls {
                let values = try url.resourceValues(forKeys: Set(keys))
                if let size = values.fileSize, let date = values.contentModificationDate {
                    totalSize += size
                    files.append((url, size, date))
                }
            }
            
            if totalSize < maxCacheSize { return }
            
            print("🧹 ExpoVideoCache: Pruning... Current: \(totalSize / 1024 / 1024)MB, Limit: \(maxCacheSize / 1024 / 1024)MB")
            
            files.sort { $0.date < $1.date }
            
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