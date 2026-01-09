import Foundation
import Swifter
import Network

/// A local HTTP proxy server designed to intercept and cache video requests.
///
/// The `VideoProxyServer` acts as a middleware between the native video player (e.g., AVPlayer)
/// and the remote video server. Its primary responsibilities are:
/// 1.  **Interception:** Captures requests via a localhost URL.
/// 2.  **Caching:** Serves content from disk if available; otherwise downloads and saves it.
/// 3.  **HLS Rewriting:** Parses `.m3u8` manifests to rewrite segment URLs, ensuring
///     they also pass through the proxy.
/// 4.  **Streaming Support:** Handles HTTP Range requests (206 Partial Content) to support
///     seeking and progressive loading.
internal class VideoProxyServer {
    private var server: HttpServer?
    private let storage: VideoCacheStorage
    
    /// The port on which the server listens.
    internal let port: Int
    
    /// Monitors network connectivity to prevent failed background download attempts.
    private let monitor = NWPathMonitor()
    private var isConnected: Bool = true
    
    /// A circuit breaker flag that trips when a background download fails due to a network error.
    /// This prevents the queue from overwhelming the system with requests during outages.
    private var isOfflineCircuitBreakerOpen: Bool = false
    
    /// Indicates whether the underlying HTTP server is currently accepting connections.
    var isRunning: Bool {
        return server?.operating ?? false
    }

    /// A custom URLSession configured to limit concurrent background downloads.
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 30.0
        return URLSession(configuration: config)
    }()

    /// Initializes the proxy server.
    ///
    /// - Parameters:
    ///   - port: The localhost port to listen on.
    ///   - maxCacheSize: The maximum allowable disk usage in bytes.
    init(port: Int, maxCacheSize: Int) {
        self.port = port
        self.storage = VideoCacheStorage(maxCacheSize: maxCacheSize)
        
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let isSatisfied = (path.status == .satisfied)
            self.isConnected = isSatisfied
            
            if isSatisfied {
                self.isOfflineCircuitBreakerOpen = false
                print("🛜 ExpoVideoCache: Network is ONLINE")
            } else {
                print("🚫 ExpoVideoCache: Network is OFFLINE")
            }
        }
        self.monitor.start(queue: DispatchQueue.global(qos: .background))
    }
    
    deinit {
        monitor.cancel()
    }

    // MARK: - Public API
    
    /// Checks if a specific URL is already cached on disk.
    func isCached(url: String) -> Bool {
        return storage.exists(for: url)
    }

    /// Configures routes and starts the HTTP server.
    ///
    /// This method sets up the `/proxy` endpoint which handles the core caching logic.
    /// It also triggers an asynchronous cache prune operation on a background thread.
    ///
    /// - Throws: An error if the socket cannot be bound to the specified port.
    func start() throws {
        if let current = server, current.operating { return }
        
        let server = HttpServer()
        
        server["/proxy"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            
            guard let urlString = request.queryParams.first(where: { $0.0 == "url" })?.1,
                  let remoteUrl = URL(string: urlString) else {
                return .notFound
            }
            
            let isManifest = urlString.contains(".m3u8")
            
            // Check for cache existence without loading file data into memory.
            let exists = self.storage.exists(for: urlString)
            
            // If the file exists and is a video segment (not a manifest), serve it directly
            // using a file stream. This supports byte-range requests efficiently.
            if exists && !isManifest {
                guard let fileSize = self.storage.getFileSize(for: urlString) else { return .notFound }
                let filePath = self.storage.getFilePath(for: urlString)
                let mimeType = self.getMimeType(for: urlString)
                let rangeHeader = request.headers["range"]
                
                return self.serveFileStream(filePath: filePath, fileSize: fileSize, mimeType: mimeType, rangeHeader: rangeHeader)
            }

            // Fallback to loading data into memory. This path is used for:
            // 1. Manifest files (which need to be rewritten).
            // 2. Cache misses (downloads).
            var rawData: Data? = self.storage.getCachedData(for: urlString)
            
            if rawData == nil {
                // If offline, fail immediately to avoid timeouts.
                if !self.isConnected { return .notFound }
                
                let semaphore = DispatchSemaphore(value: 0)
                var downloadedData: Data?
                
                let session = URLSession(configuration: .default)
                let task = session.dataTask(with: remoteUrl) { data, response, error in
                    if let error = error {
                        print("❌ ExpoVideoCache: Download error: \(error.localizedDescription)")
                    } else if let data = data, !data.isEmpty {
                        downloadedData = data
                    }
                    semaphore.signal()
                }
                
                task.resume()
                
                // Wait up to 10 seconds for the blocking download (usually manifests).
                if semaphore.wait(timeout: .now() + 10.0) == .timedOut {
                    task.cancel()
                    print("❌ ExpoVideoCache: Download timeout for \(urlString)")
                }
                
                if let data = downloadedData {
                    self.storage.save(data: data, for: urlString)
                    rawData = data
                } else if let stale = self.storage.getCachedData(for: urlString) {
                    rawData = stale
                }
            }
            
            guard let data = rawData, !data.isEmpty else { return .notFound }

            // Rewrite HLS manifests to point to the local proxy.
            var dataToSend = data
            if isManifest {
                if let content = String(data: data, encoding: .utf8), !content.isEmpty {
                    let rewritten = self.rewriteManifest(content, originalUrl: remoteUrl)
                    if let rewrittenBytes = rewritten.data(using: .utf8), !rewrittenBytes.isEmpty {
                        return .raw(200, "OK", ["Content-Type": "application/vnd.apple.mpegurl"], { writer in
                            try? writer.write(rewrittenBytes)
                        })
                    }
                }
            }
            
            return .ok(.data(dataToSend))
        }

        try server.start(UInt16(port), forceIPv4: true)
        self.server = server
        
        // Delay cache pruning to avoid disk I/O contention during app startup/playback.
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 10.0) { [weak self] in
            self?.storage.prune()
        }
        
        print("✅ ExpoVideoCache: Server running on port \(port)")
    }
    
    /// Efficiently serves a file or a byte range using FileHandle.
    ///
    /// This method avoids loading the entire file into memory, which is critical for
    /// performance with fragmented MP4 files that make frequent small byte-range requests.
    private func serveFileStream(filePath: URL, fileSize: UInt64, mimeType: String, rangeHeader: String?) -> HttpResponse {
        guard let fileHandle = try? FileHandle(forReadingFrom: filePath) else {
            return .internalServerError
        }
        
        // Handle Byte Range Request (e.g., "bytes=0-100")
        if let rangeHeader = rangeHeader, let range = self.parseRange(rangeHeader, fileSize: Int(fileSize)) {
            let length = range.upperBound - range.lowerBound
            
            try? fileHandle.seek(toOffset: UInt64(range.lowerBound))
            let data = fileHandle.readData(ofLength: length)
            try? fileHandle.close()
            
            let contentRange = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(fileSize)"
            
            let headers = [
                "Content-Type": mimeType,
                "Content-Length": String(data.count),
                "Content-Range": contentRange,
                "Accept-Ranges": "bytes",
                "Access-Control-Allow-Origin": "*"
            ]
            
            return .raw(206, "Partial Content", headers, { writer in
                try? writer.write(data)
            })
        }
        
        // Handle Standard Request (No Range)
        let data = fileHandle.readDataToEndOfFile()
        try? fileHandle.close()
        
        return .raw(200, "OK", [
            "Content-Type": mimeType,
            "Content-Length": String(fileSize),
            "Accept-Ranges": "bytes",
            "Access-Control-Allow-Origin": "*"
        ], { writer in
            try? writer.write(data)
        })
    }
    
    /// Stops the server and releases resources.
    func stop() {
        server?.stop()
        server = nil
    }
    
    /// Clears the entire disk cache.
    func clearCache() {
        storage.clearAll()
    }
    
    // MARK: - Background Processing
    
    /// Initiates a background download for a file that is not yet cached.
    ///
    /// This function implements the "Hybrid Strategy": files not found in the cache
    /// are served directly from the remote URL to the player, while this method
    /// concurrently downloads them for future playback.
    private func downloadInBackground(url: String) {
        if !isConnected || isOfflineCircuitBreakerOpen { return }
        if storage.exists(for: url) { return }
        
        guard let remoteUrl = URL(string: url) else { return }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            if self.storage.exists(for: url) { return }
            if self.isOfflineCircuitBreakerOpen { return }
            
            let task = self.backgroundSession.dataTask(with: remoteUrl) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let error = error as NSError? {
                    // Stop queuing further downloads if the network is confirmed offline.
                    if error.code == -1009 {
                        self.isOfflineCircuitBreakerOpen = true
                        self.isConnected = false
                    }
                    return
                }
                
                guard let data = data, !data.isEmpty else { return }
                self.storage.save(data: data, for: url)
            }
            task.resume()
        }
    }
    
    // MARK: - Rewriting Logic
    
    private func rewriteManifest(_ content: String, originalUrl: URL) -> String {
        let lines = content.components(separatedBy: .newlines)
        var rewrittenLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                rewrittenLines.append(line)
                continue
            }
            
            if trimmed.hasPrefix("#") {
                if trimmed.contains("URI=\"") {
                    rewrittenLines.append(rewriteHlsTag(line: line, originalUrl: originalUrl))
                } else {
                    rewrittenLines.append(line)
                }
                continue
            }
            
            rewrittenLines.append(rewriteLine(line: line, originalUrl: originalUrl))
        }
        return rewrittenLines.joined(separator: "\n")
    }

    private func rewriteLine(line: String, originalUrl: URL) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.isEmpty || trimmed.hasPrefix("#") {
            return line
        }
        
        var absoluteUrlString = trimmed
        if !trimmed.lowercased().hasPrefix("http") {
             if let resolvedUrl = URL(string: trimmed, relativeTo: originalUrl) {
                 absoluteUrlString = resolvedUrl.absoluteString
             } else {
                 return line
             }
        }
        
        if self.storage.exists(for: absoluteUrlString) {
            guard let encoded = absoluteUrlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                return line
            }
            return "http://127.0.0.1:\(self.port)/proxy?url=\(encoded)"
        } else {
            self.downloadInBackground(url: absoluteUrlString)
            return absoluteUrlString
        }
    }

    private func rewriteHlsTag(line: String, originalUrl: URL) -> String {
        let components = line.components(separatedBy: "URI=\"")
        if components.count < 2 { return line }
        
        let prefix = components[0]
        let rest = components[1]
        
        if let quoteIndex = rest.firstIndex(of: "\"") {
            let uriPart = String(rest[..<quoteIndex])
            let suffix = String(rest[rest.index(after: quoteIndex)...])
            
            let newUri = rewriteLine(line: uriPart, originalUrl: originalUrl)
            return "\(prefix)URI=\"\(newUri)\"\(suffix)"
        }
        return line
    }
    
    // MARK: - Utils
    
    private func parseRange(_ header: String, fileSize: Int) -> Range<Int>? {
        let components = header.replacingOccurrences(of: "bytes=", with: "").components(separatedBy: "-")
        guard components.count == 2 else { return nil }
        
        let start = Int(components[0]) ?? 0
        var end = Int(components[1]) ?? (fileSize - 1)
        
        if end >= fileSize { end = fileSize - 1 }
        if start > end { return nil }
        
        return start..<(end + 1)
    }

    private func getMimeType(for urlString: String) -> String {
        if urlString.contains(".m3u8") { return "application/vnd.apple.mpegurl" }
        if urlString.contains(".ts") { return "video/mp2t" }
        if urlString.contains(".mp4") { return "video/mp4" }
        if urlString.contains(".m4s") { return "video/iso.segment" }
        return "application/octet-stream"
    }
}