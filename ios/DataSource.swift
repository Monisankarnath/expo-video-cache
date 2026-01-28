import Foundation
import Network

/// A delegate protocol for receiving data transfer events from the DataSource.
protocol DataSourceDelegate: AnyObject {
    
    /// Called when the source is ready to transmit headers.
    /// - Parameters:
    ///   - headers: A dictionary of HTTP headers (e.g., `Content-Length`, `Content-Type`).
    ///   - status: The HTTP status code (e.g., 200, 206).
    func didReceiveHeaders(headers: [String: String], status: Int)
    
    /// Called when a chunk of data is available for streaming.
    /// - Parameter data: The raw data chunk.
    func didReceiveData(data: Data)
    
    /// Called when the data transfer is complete or has failed.
    /// - Parameter error: An optional error if the transfer failed.
    func didComplete(error: Error?)
}

/// The logic unit responsible for fulfilling a specific data request.
///
/// This class acts as a router that determines whether to serve data from the local disk cache
/// or fetch it from the network via `NetworkDownloader`. It also handles the rewriting of HLS
/// manifests to ensure subsequent segment requests are routed through the local proxy.
internal final class DataSource: NetworkDownloaderDelegate {
    
    // MARK: - Properties
    
    private let storage: VideoCacheStorage
    private let url: URL
    private let range: Range<Int>?
    private let port: Int
    
    weak var delegate: DataSourceDelegate?
    
    private var networkTask: NetworkTask?
    private var fileHandle: FileHandle?
    private var isManifest: Bool
    
    /// Generates a unique key for the file on disk.
    ///
    /// This key appends the byte range to the URL to prevent file collisions in fMP4 streams,
    /// where the same URL is often used for both initialization and media segments.
    private var storageKey: String {
        if let r = range {
            return "\(url.absoluteString)-\(r.lowerBound)-\(r.upperBound)"
        }
        return url.absoluteString
    }
    
    // MARK: - Initialization
    
    /// Initializes a new data source request.
    ///
    /// - Parameters:
    ///   - storage: The cache storage manager.
    ///   - url: The target URL.
    ///   - range: The requested byte range (optional).
    ///   - port: The local proxy port (used for manifest rewriting).
    init(storage: VideoCacheStorage, url: URL, range: Range<Int>?, port: Int) {
        self.storage = storage
        self.url = url
        self.range = range
        self.port = port
        
        let urlString = url.absoluteString.lowercased()
        self.isManifest = url.pathExtension.lowercased().contains("m3u8") || urlString.contains(".m3u8")
    }
    
    // MARK: - Lifecycle
    
    /// Begins the data retrieval process.
    ///
    /// Checks the disk cache first; if the data is missing, initiates a network download.
    func start() {
        if storage.exists(for: storageKey) {
            if isManifest {
                serveManifestFromCache()
            } else {
                serveFileFromDisk()
            }
            return
        }
        
        if isManifest {
            downloadManifest()
        } else {
            startStreamDownload()
        }
    }
    
    /// Cancels any active network tasks or file I/O.
    func cancel() {
        networkTask?.cancel()
        closeFileHandle()
    }
    
    private func closeFileHandle() {
        try? fileHandle?.close()
        fileHandle = nil
    }
    
    // MARK: - Disk Path (Cache Hit)
    
    private func serveFileFromDisk() {
        let path = storage.getFilePath(for: storageKey)
        
        guard let handle = try? FileHandle(forReadingFrom: path) else {
            delegate?.didComplete(error: NSError(domain: "DiskError", code: 500))
            return
        }
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? UInt64) ?? 0
        
        if fileSize == 0 {
            try? handle.close()
            let headers = ["Content-Length": "0", "Content-Type": getMimeType(url: url)]
            delegate?.didReceiveHeaders(headers: headers, status: 200)
            delegate?.didComplete(error: nil)
            return
        }
        
        let headers = [
            "Content-Type": getMimeType(url: url),
            "Content-Length": "\(fileSize)",
            "Accept-Ranges": "bytes"
        ]
        
        delegate?.didReceiveHeaders(headers: headers, status: 200)
        
        while true {
            let data = handle.readData(ofLength: 64 * 1024)
            if data.isEmpty { break }
            delegate?.didReceiveData(data: data)
        }
        
        try? handle.close()
        delegate?.didComplete(error: nil)
    }
    
    // MARK: - Network Path (Cache Miss)
    
    private func startStreamDownload() {
        self.networkTask = NetworkDownloader.shared.download(url: url, range: range, delegate: self)
    }
    
    // MARK: - NetworkDownloaderDelegate
    
    func didReceiveResponse(task: NetworkTask, response: URLResponse) {
        if let httpResponse = response as? HTTPURLResponse {
            if (200...299).contains(httpResponse.statusCode) {
                self.fileHandle = storage.initializeStreamFile(for: storageKey)
            }
            
            var headers = [String:String]()
            for (k, v) in httpResponse.allHeaderFields {
                if let ks = k as? String, let vs = v as? String { headers[ks] = vs }
            }
            
            headers["Content-Type"] = getMimeType(url: url)
            delegate?.didReceiveHeaders(headers: headers, status: httpResponse.statusCode)
        }
    }
    
    func didReceiveData(task: NetworkTask, data: Data) {
        delegate?.didReceiveData(data: data)
        if let handle = fileHandle {
            try? handle.write(contentsOf: data)
        }
    }
    
    func didComplete(task: NetworkTask, error: Error?) {
        closeFileHandle()
        
        if error != nil {
            if storage.exists(for: storageKey) {
                storage.delete(for: storageKey)
            }
        }
        
        delegate?.didComplete(error: error)
    }
    
    // MARK: - Manifest Handling
    
    private func serveManifestFromCache() {
        guard let data = storage.getCachedData(for: storageKey),
              let content = String(data: data, encoding: .utf8) else {
            delegate?.didComplete(error: NSError(domain: "CacheError", code: 404))
            return
        }
        sendRewrittenManifest(content)
    }
    
    private func downloadManifest() {
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, let content = String(data: data, encoding: .utf8) else {
                self?.delegate?.didComplete(error: error ?? NSError(domain: "NetError", code: 500))
                return
            }
            self.storage.save(data: data, for: self.storageKey)
            self.sendRewrittenManifest(content)
        }
        task.resume()
    }
    
    private func sendRewrittenManifest(_ content: String) {
        let rewritten = rewriteManifest(content, originalUrl: url)
        
        let headers = ["Content-Type": "application/vnd.apple.mpegurl"]
        delegate?.didReceiveHeaders(headers: headers, status: 200)
        
        if let data = rewritten.data(using: .utf8) {
            delegate?.didReceiveData(data: data)
        }
        
        delegate?.didComplete(error: nil)
    }
    
    /// Rewrites the HLS manifest content to route segment requests through the local proxy.
    /// - Parameters:
    ///   - content: The raw manifest string.
    ///   - originalUrl: The original URL of the manifest, used for resolving relative paths.
    /// - Returns: A modified manifest string with localhost URLs.
    private func rewriteManifest(_ content: String, originalUrl: URL) -> String {
        let lines = content.components(separatedBy: .newlines)
        var rewritten: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                rewritten.append(line)
                continue
            }
            
            if trimmed.hasPrefix("#") {
                if trimmed.contains("URI=\"") {
                    rewritten.append(rewriteHlsTag(line: line, originalUrl: originalUrl))
                } else {
                    rewritten.append(line)
                }
                continue
            }
            
            rewritten.append(rewriteLine(line: line, originalUrl: originalUrl))
        }
        return rewritten.joined(separator: "\n")
    }
    
    private func rewriteLine(line: String, originalUrl: URL) -> String {
        if line.hasPrefix("#") { return line }
        
        let absolute = URL(string: line, relativeTo: originalUrl)?.absoluteString ?? line
        guard let encoded = absolute.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return line }
        
        return "http://127.0.0.1:\(port)/proxy?url=\(encoded)"
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
    
    private func getMimeType(url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "mp4": return "video/mp4"
        case "m4s": return "video/iso.segment"
        case "m4a": return "audio/mp4"
        case "ts": return "video/mp2t"
        default: return "application/octet-stream"
        }
    }
}