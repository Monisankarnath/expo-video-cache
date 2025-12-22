import Foundation
import Swifter

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
    private let port: Int
    
    /// Indicates whether the underlying HTTP server is currently accepting connections.
    var isRunning: Bool {
        return server?.operating ?? false
    }

    /// Initializes the proxy server.
    ///
    /// - Parameters:
    ///   - port: The localhost port to listen on.
    ///   - maxCacheSize: The maximum allowable disk usage in bytes.
    init(port: Int, maxCacheSize: Int) {
        self.port = port
        self.storage = VideoCacheStorage(maxCacheSize: maxCacheSize)
    }

    /// Configures routes and starts the HTTP server.
    ///
    /// This method sets up the `/proxy` endpoint which handles the core caching logic.
    /// It also triggers an asynchronous cache prune operation on a background thread.
    ///
    /// - Throws: An error if the socket cannot be bound to the specified port.
    func start() throws {
        // Idempotency check: Do not restart if already running.
        if let current = server, current.operating { return }
        
        let server = HttpServer()
        
        // Define the main proxy handler.
        // Format: http://127.0.0.1:{port}/proxy?url={encoded_remote_url}
        server["/proxy"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            
            // Validate the 'url' query parameter.
            guard let urlString = request.queryParams.first(where: { $0.0 == "url" })?.1,
                  let remoteUrl = URL(string: urlString) else {
                return .notFound
            }
            
            // MARK: Phase 1 - Data Retrieval
            // Attempt to retrieve data from the disk cache. If missing, download synchronously
            // from the remote source and write to disk immediately.
            var rawData: Data? = self.storage.getCachedData(for: urlString)
            let isCacheHit = (rawData != nil)
            
            if isCacheHit {
                print("🟢 Cache HIT: \(urlString)")
            } else {
                print("🟡 Cache MISS (Downloading): \(urlString)")
                // Note: We intentionally block the request thread here to download.
                // Swifter handles requests on concurrent threads, so this does not block the main UI.
                if let downloadedData = try? Data(contentsOf: remoteUrl) {
                    self.storage.save(data: downloadedData, for: urlString)
                    rawData = downloadedData
                }
            }
            
            guard let data = rawData else {
                print("❌ Failed to get data: \(urlString)")
                return .notFound
            }

            // MARK: Phase 2 - HLS Manifest Processing
            // If the content is an HLS playlist (.m3u8), we must rewrite the internal links.
            // Even if the file was cached, we rewrite it dynamically to ensure the links
            // point to the current `self.port`, which may differ between app sessions.
            let isManifest = urlString.contains(".m3u8")
            var dataToSend = data
            
            if isManifest {
                if let content = String(data: data, encoding: .utf8) {
                    let rewritten = self.rewriteManifest(content, originalUrl: remoteUrl)
                    if let rewrittenBytes = rewritten.data(using: .utf8) {
                        dataToSend = rewrittenBytes
                    }
                }
            }

            // MARK: Phase 3 - Content Delivery & Byte Ranges
            // Video players often request partial data (e.g., "bytes=0-1024") for seeking.
            // We must support HTTP 206 Partial Content to function correctly as a video source.
            let mimeType = self.getMimeType(for: urlString)
            let rangeHeader = request.headers["range"]
            
            if let rangeHeader = rangeHeader, let range = self.parseRange(rangeHeader, fileSize: dataToSend.count) {
                let slicedData = dataToSend.subdata(in: range)
                let contentRange = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(dataToSend.count)"
                
                let headers = [
                    "Content-Type": mimeType,
                    "Content-Length": String(slicedData.count),
                    "Content-Range": contentRange,
                    "Accept-Ranges": "bytes",
                    "Access-Control-Allow-Origin": "*"
                ]
                
                return .raw(206, "Partial Content", headers, { writer in
                    try? writer.write(slicedData)
                })
            }
            
            // Standard Full Content Response (200 OK)
            let headers = [
                "Content-Type": mimeType,
                "Content-Length": String(dataToSend.count),
                "Accept-Ranges": "bytes",
                "Access-Control-Allow-Origin": "*"
            ]
            
            return .raw(200, "OK", headers, { writer in
                try? writer.write(dataToSend)
            })
        }

        try server.start(UInt16(port), forceIPv4: true)
        self.server = server
        
        // Perform cleanup (LRU Pruning) in the background to avoid delaying startup.
        DispatchQueue.global(qos: .background).async {
            self.storage.prune()
        }
        
        print("✅ ExpoVideoCache: Server running on port \(port)")
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
    
    // MARK: - Helper Functions
    
    /// Parses the HTTP Range header to determine which bytes to serve.
    ///
    /// - Parameters:
    ///   - header: The raw header string (e.g., "bytes=0-500").
    ///   - fileSize: The total size of the file.
    /// - Returns: A Swift `Range<Int>` representing the requested bytes, or `nil` if invalid.
    private func parseRange(_ header: String, fileSize: Int) -> Range<Int>? {
        let components = header.replacingOccurrences(of: "bytes=", with: "").components(separatedBy: "-")
        guard components.count == 2 else { return nil }
        
        let start = Int(components[0]) ?? 0
        // If the end byte is missing, defaults to the last byte of the file.
        var end = Int(components[1]) ?? (fileSize - 1)
        
        if end >= fileSize { end = fileSize - 1 }
        if start > end { return nil }
        
        return start..<(end + 1)
    }
    
    /// Rewrites URLs inside an M3U8 manifest file.
    ///
    /// This ensures that when the player requests the next segment or playlist variant,
    /// that request is also routed through this proxy.
    ///
    /// - Parameters:
    ///   - content: The raw string content of the manifest.
    ///   - originalUrl: The base URL of the manifest (used to resolve relative paths).
    /// - Returns: The modified manifest string.
    private func rewriteManifest(_ content: String, originalUrl: URL) -> String {
        let lines = content.components(separatedBy: .newlines)
        var rewrittenLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                rewrittenLines.append(line)
                continue
            }
            
            // Handle specific HLS tags that contain URIs (e.g., #EXT-X-KEY:URI="...")
            if trimmed.hasPrefix("#") {
                if trimmed.contains("URI=\"") {
                    rewrittenLines.append(rewriteHlsTag(line: line, originalUrl: originalUrl))
                } else {
                    rewrittenLines.append(line)
                }
                continue
            }
            
            // Handle standard lines (segment URLs or variant playlist URLs)
            rewrittenLines.append(rewriteLine(line: line, originalUrl: originalUrl))
        }
        return rewrittenLines.joined(separator: "\n")
    }

    /// Transforms a single URL line into a proxied URL.
    ///
    /// Resolves relative paths against the original manifest URL before encoding.
    private func rewriteLine(line: String, originalUrl: URL) -> String {
        var absoluteUrlString = line
        
        // If the line is a relative path (e.g., "segment-1.ts"), resolve it to absolute.
        if !line.lowercased().hasPrefix("http") {
             if let resolvedUrl = URL(string: line, relativeTo: originalUrl) {
                 absoluteUrlString = resolvedUrl.absoluteString
             }
        }
        
        guard let encoded = absoluteUrlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return line
        }
        
        return "http://127.0.0.1:\(self.port)/proxy?url=\(encoded)"
    }

    /// rewriting logic for HLS tags containing URIs.
    ///
    /// Example: `#EXT-X-KEY:METHOD=AES-128,URI="key.php"`
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

    /// Determines the MIME type based on file extension.
    ///
    /// Correct MIME types are essential for players (especially AVPlayer) to
    /// recognize the stream format.
    private func getMimeType(for urlString: String) -> String {
        if urlString.contains(".m3u8") { return "application/vnd.apple.mpegurl" }
        if urlString.contains(".ts") { return "video/mp2t" }
        if urlString.contains(".mp4") { return "video/mp4" }
        if urlString.contains(".m4s") { return "video/iso.segment" }
        return "application/octet-stream"
    }
}