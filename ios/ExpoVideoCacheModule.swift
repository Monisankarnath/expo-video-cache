import ExpoModulesCore
import Swifter

public class ExpoVideoCacheModule: Module {
  // 1. Declare the Swifter Server instance
  private var server: HttpServer?
  public func definition() -> ModuleDefinition {
    Name("ExpoVideoCache")

    AsyncFunction("startServer") { (port: Int) in
      // 2. Check if running
      if let currentServer = self.server, currentServer.operating {
        print("⚠️ ExpoVideoCache: Server already running on port \(port)")
        return
      }

      // 3. Initialize Swifter
      let server = HttpServer()

      // 4. Add a Test Route (GET /)
      server["/"] = { request in
        return .ok(.htmlBody("<html><body><h1>Hello from Swifter!</h1></body></html>"))
      }
      
      // 5. Add a Video Route (We will expand this in Step 2)
      // This helper function automatically handles byte-range requests (seeking)
      // For now, we just log that it was hit.
      server["/video/:filename"] = { request in
        guard let filename = request.params[":filename"] else {
             return .notFound
        }
        print("Requested video: \(filename)")
        return .notFound // We will link real files in the next step
      }

      // 6. Start the Server
      do {
        // forceIPv4 is often needed for localhost access on simulators
        try server.start(UInt16(port), forceIPv4: true)
        self.server = server
        print("✅ ExpoVideoCache: Swifter server started on http://127.0.0.1:\(port)")
      } catch {
        print("❌ ExpoVideoCache: Failed to start server: \(error)")
      }
    }

    Function("convertUrl") { (url: String, port: Int) -> String in
      // Just returning localhost for now to verify connection
      return "http://127.0.0.1:\(port)/"
    }
  }
}