import ExpoModulesCore

public class ExpoVideoCacheModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ExpoVideoCache")

    AsyncFunction("startServer") { (port: Int) in
      print("Step 0: Server start requested on port \(port)")
    }

    Function("convertUrl") { (url: String, port: Int) -> String in
      print("Step 0: Convert URL requested")
      return url
    }
  }
}
