import ExpoModulesCore

public class ExpoVideoCacheModule: Module {
  private var proxyServer: VideoProxyServer?
  
  // 1. Default to 9000 initially.
  // This ensures convertUrl works (pointing to 9000) even if called before startServer finishes.
  private var activePort: Int = 9000

  public func definition() -> ModuleDefinition {
    Name("ExpoVideoCache")

    // Function: startServer
    // Params: port (Optional), maxCacheSize (Optional)
    AsyncFunction("startServer") { (port: Int?, maxCacheSize: Int?) in
      let safeMaxCacheSize = maxCacheSize ?? 1_073_741_824 // 1GB Default
      
      // LOGIC: Determine Target Port
      // If user passed a port, use it. Otherwise, use 9000 (Default).
      let targetPort = port ?? 9000
      
      // CHECK: Is server already running?
      if let currentServer = self.proxyServer, currentServer.isRunning {
          if self.activePort == targetPort {
              print("✅ ExpoVideoCache: Server already active on port \(targetPort)")
              return // Success (Idempotent)
          } else {
              // User tried to switch ports while running.
              throw NSError(domain: "ExpoVideoCache", code: 409, userInfo: [NSLocalizedDescriptionKey: "Server is already running on port \(self.activePort). You must reload the app to change ports."])
          }
      }
      
      // START: Try to bind to the specific port
      let newServer = VideoProxyServer(port: targetPort, maxCacheSize: safeMaxCacheSize)
      
      do {
          try newServer.start()
          
          // Success! Update our state.
          self.proxyServer = newServer
          self.activePort = targetPort
          print("✅ ExpoVideoCache: Server started on port \(targetPort)")
          
      } catch {
          // STRICT ERROR: Do not retry. Do not increment. Fail loud.
          print("❌ ExpoVideoCache: Port \(targetPort) is busy.")
          throw NSError(domain: "ExpoVideoCache", code: 500, userInfo: [NSLocalizedDescriptionKey: "Port \(targetPort) is already in use. Please choose a different port."])
      }
    }

    // Function: convertUrl
    // Params: url (String), isCacheable (Optional Bool)
    // NO PORT param here. We use self.activePort.
    Function("convertUrl") { (url: String, isCacheable: Bool?) -> String in
        // Default to TRUE (Cache Enabled)
        let shouldCache = isCacheable ?? true
        
        if !shouldCache {
            return url
        }
        
        guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return url
        }
        
        // Use the internal activePort (9000 or whatever user set)
        return "http://127.0.0.1:\(self.activePort)/proxy?url=\(encodedUrl)"
    }

    AsyncFunction("clearCache") {
        if let server = self.proxyServer {
            server.clearCache()
        } else {
            // If server isn't running, we create a temporary storage just to clear the files
            let tempStorage = VideoCacheStorage(maxCacheSize: 0)
            tempStorage.clearAll()
        }
    }
  }
}