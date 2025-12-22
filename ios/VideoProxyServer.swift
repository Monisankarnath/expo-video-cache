import Foundation
import Swifter

internal class VideoProxyServer {
    private var server: HttpServer?
    private let storage: VideoCacheStorage
    private let port: Int
    
    var isRunning: Bool {
        return server?.operating ?? false
    }

    init(port: Int, maxCacheSize: Int) {
        self.port = port
        self.storage = VideoCacheStorage(maxCacheSize: maxCacheSize)
    }

    func start() throws {
        if let current = server, current.operating { return }
        
        let server = HttpServer()
        
        server["/proxy"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            
            guard let urlString = request.queryParams.first(where: { $0.0 == "url" })?.1,
                  let remoteUrl = URL(string: urlString) else {
                return .notFound
            }
            
            // ---------------------------------------------------------
            // 1. FETCH DATA (Cache First, then Network)
            // ---------------------------------------------------------
            var rawData: Data? = self.storage.getCachedData(for: urlString)
            let isCacheHit = (rawData != nil)
            
            if isCacheHit {
                print("🟢 Cache HIT: \(urlString)")
            } else {
                print("🟡 Cache MISS (Downloading): \(urlString)")
                if let downloadedData = try? Data(contentsOf: remoteUrl) {
                    // ✅ CHANGE: Save EVERYTHING to disk, including Manifests
                    self.storage.save(data: downloadedData, for: urlString)
                    rawData = downloadedData
                }
            }
            
            guard let data = rawData else {
                print("❌ Failed to get data: \(urlString)")
                return .notFound
            }

            // ---------------------------------------------------------
            // 2. PROCESS DATA (Rewrite Manifests)
            // ---------------------------------------------------------
            let isManifest = urlString.contains(".m3u8")
            var dataToSend = data
            
            if isManifest {
                // Always rewrite manifest, even if loaded from cache.
                // This ensures links point to the CURRENT port (which might change between app runs).
                if let content = String(data: data, encoding: .utf8) {
                    let rewritten = self.rewriteManifest(content, originalUrl: remoteUrl)
                    if let rewrittenBytes = rewritten.data(using: .utf8) {
                        dataToSend = rewrittenBytes
                    }
                }
            }

            // ---------------------------------------------------------
            // 3. SERVE DATA (With Byte Ranges for fMP4)
            // ---------------------------------------------------------
            let mimeType = self.getMimeType(for: urlString)
            let rangeHeader = request.headers["range"]
            
            // Handle Range Request (206 Partial Content)
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
            
            // Handle Full Request (200 OK)
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
        
        DispatchQueue.global(qos: .background).async {
            self.storage.prune()
        }
        
        print("✅ ExpoVideoCache: Server running on port \(port)")
    }
    
    func stop() {
        server?.stop()
        server = nil
    }
    
    // MARK: - Helper Functions
    
    private func parseRange(_ header: String, fileSize: Int) -> Range<Int>? {
        let components = header.replacingOccurrences(of: "bytes=", with: "").components(separatedBy: "-")
        guard components.count == 2 else { return nil }
        
        let start = Int(components[0]) ?? 0
        var end = Int(components[1]) ?? (fileSize - 1)
        
        if end >= fileSize { end = fileSize - 1 }
        if start > end { return nil }
        
        return start..<(end + 1)
    }
    
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
        var absoluteUrlString = line
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

    private func getMimeType(for urlString: String) -> String {
        if urlString.contains(".m3u8") { return "application/vnd.apple.mpegurl" }
        if urlString.contains(".ts") { return "video/mp2t" }
        if urlString.contains(".mp4") { return "video/mp4" }
        if urlString.contains(".m4s") { return "video/iso.segment" }
        return "application/octet-stream"
    }

    func clearCache() {
        storage.clearAll()
    }
}