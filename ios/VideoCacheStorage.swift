import Foundation
import CryptoKit

/// Manages the disk persistence layer for video caching.
///
/// `VideoCacheStorage` is responsible for handling all filesystem-level
/// operations related to video caching, including:
/// - Generating deterministic, filesystem-safe filenames from remote URLs
/// - Reading and writing cached video data
/// - Supporting incremental (streaming) writes
/// - Enforcing a disk size limit using a Least Recently Used (LRU) strategy
///
/// This class is designed to be lightweight, deterministic, and resilient to
/// filesystem errors. All operations are best-effort and never throw, ensuring
/// that cache failures do not impact video playback.
internal final class VideoCacheStorage {
    
    // MARK: - Properties
    
    /// The file manager instance used for all filesystem operations.
    private let fileManager = FileManager.default
    
    /// The maximum allowed size of the cache, in bytes.
    ///
    /// When the total size of cached files exceeds this limit, the cache
    /// is pruned using an LRU (Least Recently Used) strategy.
    private let maxCacheSize: Int
    
    /// The root directory where all cached video files are stored.
    ///
    /// This directory is created inside the system Caches directory and
    /// is guaranteed to exist after initialization.
    private let cacheDirectory: URL
    
    // MARK: - Initialization
    
    /// Initializes a new video cache storage manager.
    ///
    /// During initialization, the cache directory is created if it does not
    /// already exist.
    ///
    /// - Parameter maxCacheSize: The maximum allowed size of the cache in bytes.
    init(maxCacheSize: Int) {
        self.maxCacheSize = maxCacheSize
        
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        self.cacheDirectory = paths[0].appendingPathComponent("ExpoVideoCache")
        
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
        }
    }
    
    // MARK: - Core API
    
    /// Removes all cached files from disk.
    ///
    /// This method deletes the entire cache directory and recreates it,
    /// effectively resetting the cache to an empty state.
    func clearAll() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }
    
    /// Generates a deterministic, filesystem-safe file URL for a given key.
    ///
    /// The provided string is hashed using SHA256 to ensure:
    /// - Collision resistance
    /// - Consistent file paths across launches
    /// - Compatibility with all filesystems
    ///
    /// The original file extension (if present) is preserved.
    ///
    /// - Parameter urlString: The remote URL or unique cache key.
    /// - Returns: A local file URL corresponding to the hashed key.
    func getFilePath(for urlString: String) -> URL {
        guard let data = urlString.data(using: .utf8) else {
            return cacheDirectory.appendingPathComponent("unknown.bin")
        }
        
        let hash = SHA256.hash(data: data)
        let safeFilename = hash.map { String(format: "%02x", $0) }.joined()
        
        var extensionName = "bin"
        if let url = URL(string: urlString) {
            let ext = url.pathExtension
            if !ext.isEmpty {
                extensionName = ext
            }
        }
        
        return cacheDirectory.appendingPathComponent(
            "\(safeFilename).\(extensionName)"
        )
    }
    
    /// Determines whether a valid cached file exists for a given key.
    ///
    /// A file is considered valid only if:
    /// - It exists on disk
    /// - Its size is greater than zero bytes
    ///
    /// - Parameter urlString: The remote URL or unique cache key.
    /// - Returns: `true` if a valid cached file exists, otherwise `false`.
    func exists(for urlString: String) -> Bool {
        let fileUrl = getFilePath(for: urlString)
        
        if let attr = try? fileManager.attributesOfItem(
            atPath: fileUrl.path
        ),
           let size = attr[.size] as? Int64,
           size > 0 {
            return true
        }
        
        return false
    }
    
    // MARK: - Reading & Writing
    
    /// Reads the entire cached file into memory.
    ///
    /// This method is intended for small files such as manifests or metadata.
    ///
    /// - Parameter urlString: The remote URL or unique cache key.
    /// - Returns: The cached file data if it exists, otherwise `nil`.
    func getCachedData(for urlString: String) -> Data? {
        let fileUrl = getFilePath(for: urlString)
        return try? Data(contentsOf: fileUrl)
    }
    
    /// Saves data to disk atomically.
    ///
    /// The write operation replaces any existing file and guarantees that
    /// partially written files are never left on disk.
    ///
    /// - Parameters:
    ///   - data: The data to be written to disk.
    ///   - urlString: The remote URL or unique cache key.
    func save(data: Data, for urlString: String) {
        let fileUrl = getFilePath(for: urlString)
        try? data.write(to: fileUrl, options: .atomic)
    }
    
    /// Deletes the cached file associated with a given key.
    ///
    /// This is typically used when a download fails or cached data becomes invalid.
    ///
    /// - Parameter urlString: The remote URL or unique cache key.
    func delete(for urlString: String) {
        let url = getFilePath(for: urlString)
        try? fileManager.removeItem(at: url)
    }
    
    // MARK: - Streaming API
    
    /// Prepares a file for incremental (streaming) writes.
    ///
    /// Any existing file at the target path is deleted to ensure that
    /// stale or partial data is not mixed with new content.
    ///
    /// - Parameter urlString: The remote URL or unique cache key.
    /// - Returns: A `FileHandle` opened for writing, or `nil` if creation fails.
    func initializeStreamFile(for urlString: String) -> FileHandle? {
        let fileUrl = getFilePath(for: urlString)
        
        if fileManager.fileExists(atPath: fileUrl.path) {
            try? fileManager.removeItem(at: fileUrl)
        }
        
        fileManager.createFile(
            atPath: fileUrl.path,
            contents: nil
        )
        
        return try? FileHandle(forWritingTo: fileUrl)
    }
    
    // MARK: - Maintenance
    
    /// Prunes the cache to enforce the configured size limit.
    ///
    /// This method removes the least recently modified files first until
    /// the total cache size is within the allowed limit.
    ///
    /// All failures are silently ignored to ensure that cache maintenance
    /// never interferes with normal application execution.
    func prune() {
        let keys: [URLResourceKey] = [
            .fileSizeKey,
            .contentModificationDateKey
        ]
        
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
                if let size = values.fileSize,
                   let date = values.contentModificationDate {
                    totalSize += size
                    files.append((url, size, date))
                }
            }
            
            guard totalSize >= maxCacheSize else { return }
            
            files.sort { $0.date < $1.date }
            
            for file in files {
                try? fileManager.removeItem(at: file.url)
                totalSize -= file.size
                if totalSize < maxCacheSize {
                    break
                }
            }
            
        } catch {
            // Intentionally ignored
        }
    }
}