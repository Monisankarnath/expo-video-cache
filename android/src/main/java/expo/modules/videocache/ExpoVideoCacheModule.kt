package expo.modules.videocache

import android.util.Log
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

/**
 * Android implementation of the ExpoVideoCache module.
 *
 * NOTE: Unlike the iOS implementation, which requires a local HTTP proxy server to
 * intercept and cache video requests (due to AVPlayer limitations), Android video players
 * (such as ExoPlayer/Media3) typically support transparent disk caching natively.
 *
 * Therefore, this module serves primarily as a "No-op" (No Operation) shim to ensure
 * API parity with the JavaScript layer. It allows the same JS code to run on both platforms
 * without requiring conditional platform checks.
 */
class ExpoVideoCacheModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ExpoVideoCache")

    /**
     * Initializes the cache server (No-op on Android).
     *
     * This function matches the iOS signature to prevent JavaScript errors when passing
     * configuration objects. On Android, the native player handles caching internally.
     *
     * - Parameters:
     * - port: The port number (Ignored on Android).
     * - maxCacheSize: The maximum cache size in bytes (Ignored on Android).
     * - headOnlyCache: Whether to cache only the first few segments (Ignored on Android).
     */
    AsyncFunction("startServer") { port: Int?, maxCacheSize: Int?, headOnlyCache: Boolean? ->
      Log.d("ExpoVideoCache", "Android uses native caching strategies; arguments ignored.")
    }

    /**
     * Transforms a remote URL into a locally cacheable URL (Pass-through on Android).
     *
     * On Android, this function ignores the `isCacheable` flag and returns the original
     * URL, as caching is handled by the player's internal logic rather than a proxy.
     *
     * - Parameters:
     * - url: The original remote URL.
     * - isCacheable: A boolean flag indicating if the video should be cached (Ignored on Android).
     * - Returns: The original `url` string.
     */
    Function("convertUrl") { url: String, isCacheable: Boolean? ->
      return@Function url
    }
    
    /**
     * Clears the video cache.
     * * Current implementation is a placeholder. If specific ExoPlayer/Media3 cache 
     * clearing is required in the future, it should be implemented here.
     */
    AsyncFunction("clearCache") {
       Log.d("ExpoVideoCache", "Cache clearing is managed by the native player on Android.")
    }
  }
}