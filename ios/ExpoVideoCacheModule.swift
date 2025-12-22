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
      
      // Check if the server is already active to handle idempotency or conflict errors.
      if let currentServer = self.proxyServer, currentServer.isRunning {
          if self.activePort == targetPort {
              print("✅ ExpoVideoCache: Server already active on port \(targetPort)")
              return
          } else {
              // Strict Check: Dynamic port switching during runtime is not supported
              // to ensure consistent URL rewriting across the application lifecycle.
              throw NSError(
                  domain: "ExpoVideoCache",
                  code: 409,
                  userInfo: [NSLocalizedDescriptionKey: "Server is already running on port \(self.activePort). You must reload the app to change ports."]
              )
          }
      }
      
      // Attempt to bind the server to the specific port.
      let newServer = VideoProxyServer(port: targetPort, maxCacheSize: safeMaxCacheSize)
      
      do {
          try newServer.start()
          
          self.proxyServer = newServer
          self.activePort = targetPort
          print("✅ ExpoVideoCache: Server started on port \(targetPort)")
          
      } catch {
          // Fail fast: We do not auto-increment ports.
          // This ensures the JS layer always knows exactly which port is being used
          // without needing a callback to update configuration.
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
    /// - Returns: A `localhost` URL pointing to the proxy, or the original URL if caching is disabled.
    Function("convertUrl") { (url: String, isCacheable: Bool?) -> String in
        let shouldCache = isCacheable ?? true
        
        if !shouldCache {
            return url
        }
        
        // Ensure the query parameters are properly encoded to be passed as a query string
        // to the proxy server.
        guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return url
        }
        
        // Relies on `self.activePort`. If the server hasn't started yet, this defaults to 9000.
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
            // Fallback: Access storage directly if the server instance is down.
            let tempStorage = VideoCacheStorage(maxCacheSize: 0)
            tempStorage.clearAll()
        }
    }
  }
}