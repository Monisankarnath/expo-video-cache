import ExpoModulesCore

/// A module that manages a local proxy server to cache video assets.
///
/// This module acts as a bridge between the React Native JavaScript layer and the
/// native `VideoProxyServer`. It handles the lifecycle of the local server, URL rewriting,
/// and cache management.
public class ExpoVideoCacheModule: Module {
  
  private var proxyServer: VideoProxyServer?
  
  /// The port currently being used by the proxy server.
  ///
  /// Defaults to `9000` to ensure `convertUrl` returns a valid localhost string
  /// even if called before `startServer` has fully completed its asynchronous bootstrap.
  private var activePort: Int = 9000

  public func definition() -> ModuleDefinition {
    Name("ExpoVideoCache")

    /// Initializes and starts the local proxy server.
    ///
    /// If a server is already running on the requested port, this operation is idempotent.
    /// If the requested port differs from the running port, an error is thrown to prevent
    /// state inconsistency requiring a reload.
    ///
    /// - Parameters:
    ///   - port: The specific port to bind to. Defaults to `9000`.
    ///   - maxCacheSize: The maximum disk usage in bytes. Defaults to `1GB`.
    AsyncFunction("startServer") { (port: Int?, maxCacheSize: Int?) in
      let safeMaxCacheSize = maxCacheSize ?? 1_073_741_824 // 1GB Default
      let targetPort = port ?? 9000
      
      if let currentServer = self.proxyServer, currentServer.isRunning {
          if self.activePort == targetPort {
              print("✅ ExpoVideoCache: Server already active on port \(targetPort)")
              return
          } else {
              throw NSError(
                  domain: "ExpoVideoCache",
                  code: 409,
                  userInfo: [NSLocalizedDescriptionKey: "Server is already running on port \(self.activePort). You must reload the app to change ports."]
              )
          }
      }
      
      let newServer = VideoProxyServer(port: targetPort, maxCacheSize: safeMaxCacheSize)
      
      do {
          try newServer.start()
          
          self.proxyServer = newServer
          self.activePort = targetPort
          print("✅ ExpoVideoCache: Server started on port \(targetPort)")
          
      } catch {
          print("❌ ExpoVideoCache: Port \(targetPort) is busy.")
          throw NSError(
              domain: "ExpoVideoCache",
              code: 500,
              userInfo: [NSLocalizedDescriptionKey: "Port \(targetPort) is already in use. Please choose a different port."]
          )
      }
    }

    /// Rewrites a remote URL to point to the local proxy server.
    ///
    /// - Parameters:
    ///   - url: The original remote URL string.
    ///   - isCacheable: Optional flag to bypass the proxy. Defaults to `true`.
    /// - Returns: A `localhost` URL pointing to the proxy, or the original URL if caching is disabled or server is not running.
    Function("convertUrl") { (url: String, isCacheable: Bool?) -> String in
        let shouldCache = isCacheable ?? true
        
        if !shouldCache {
            return url
        }
        
        guard let server = self.proxyServer, server.isRunning else {
            print("⚠️ ExpoVideoCache: Server not running. Returning original URL: \(url)")
            return url
        }
        
        guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return url
        }
        
        return "http://127.0.0.1:\(self.activePort)/proxy?url=\(encodedUrl)"
    }

    /// Clears all cached video files from disk.
    ///
    /// If the server is not currently running, a temporary storage instance is created
    /// to locate and purge the cache directory.
    AsyncFunction("clearCache") {
        if let server = self.proxyServer {
            server.clearCache()
        } else {
            let tempStorage = VideoCacheStorage(maxCacheSize: 0)
            tempStorage.clearAll()
        }
    }
  }
}