package expo.modules.videocache
import android.util.Log
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ExpoVideoCacheModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ExpoVideoCache")

    AsyncFunction("startServer") { port: Int ->
      // No-op for Android
      Log.d("ExpoVideoCache", "Android uses native caching, no server needed.")
    }

    Function("convertUrl") { url: String, port: Int ->
      // Return original URL on Android
      return@Function url
    }
  }
}
