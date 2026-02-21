import ExpoModulesCore
import Foundation

/// Exposes the native video caching proxy functionality to the JavaScript layer.
public final class ExpoVideoCacheModule: Module {
    
    // MARK: - Properties
    
    private var proxyServer: VideoProxyServer?
    private var activePort: Int = 9000
    
    // MARK: - Definition
    
    public func definition() -> ModuleDefinition {
        Name("ExpoVideoCache")

        // MARK: - API Methods
        
        /// Initializes and starts the TCP proxy server on a background thread.
        ///
        /// - Parameters:
        ///   - port: The local port to listen on. Defaults to `9000`.
        ///   - maxCacheSize: The maximum disk cache size in bytes. Defaults to `1GB`.
        /// - Throws: An error if the server is already running on a different port or if the port bind fails.
        AsyncFunction("startServer") { (port: Int?, maxCacheSize: Int?, headOnlyCache: Bool?) in
            let cacheLimit = maxCacheSize ?? 1_073_741_824 // Default: 1GB
            let targetPort = port ?? 9000
            
            if let currentServer = self.proxyServer, currentServer.isRunning {
                if self.activePort == targetPort { return }
                throw NSError(domain: "ExpoVideoCache", code: 409, userInfo: [NSLocalizedDescriptionKey: "Server active on \(self.activePort). Reload required."])
            }
            
            let newServer = VideoProxyServer(port: targetPort, maxCacheSize: cacheLimit, headOnlyCache: headOnlyCache ?? false)
            
            do {
                try newServer.start()
                self.proxyServer = newServer
                self.activePort = targetPort
            } catch {
                throw NSError(domain: "ExpoVideoCache", code: 500, userInfo: [NSLocalizedDescriptionKey: "Port bind failed: \(error.localizedDescription)"])
            }
        }

        /// Synchronously converts a remote URL into a local proxy URL.
        ///
        /// - Parameters:
        ///   - url: The remote URL string (e.g., `https://cdn.com/video.m3u8`).
        ///   - isCacheable: A boolean flag to bypass caching if needed. Defaults to `true`.
        /// - Returns: A local `http://127.0.0.1...` URL string, or the original URL if encoding fails or caching is disabled.
        Function("convertUrl") { (url: String, isCacheable: Bool?) -> String in
            if isCacheable == false { return url }
            
            guard let server = self.proxyServer, server.isRunning else {
                return url
            }
            
            guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                return url
            }
            
            return "http://127.0.0.1:\(self.activePort)/proxy?url=\(encodedUrl)"
        }

        /// Purges the disk cache directory.
        ///
        /// This method removes all cached video files immediately. It can be called even if the server is not running.
        AsyncFunction("clearCache") {
            if let server = self.proxyServer {
                server.clearCache()
            } else {
                VideoCacheStorage(maxCacheSize: 0).clearAll()
            }
        }
    }
}