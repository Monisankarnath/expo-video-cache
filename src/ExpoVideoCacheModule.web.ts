import { registerWebModule, NativeModule } from "expo";

/**
 * Web implementation of the ExpoVideoCache module.
 *
 * NOTE: The web platform (browsers) operates within a strict security sandbox that prevents
 * the creation of local TCP/HTTP proxy servers. Therefore, the caching strategy used on
 * iOS (local proxy) is technically impossible here.
 *
 * This implementation serves as a "shim" to prevent runtime crashes when the module is
 * imported in a web environment. It ensures that video playback continues using standard
 * browser caching mechanisms.
 */
class ExpoVideoCacheModule extends NativeModule {
  /**
   * Initializes the cache server (No-op on Web).
   *
   * Browser security policies (CORS, Sandbox) prevent binding to local ports.
   *
   * - Parameters:
   * - port: Ignored on Web.
   * - maxCacheSize: Ignored on Web.
   * - headOnlyCache: Ignored on Web.
   */
  async startServer(port?: number, maxCacheSize?: number, headOnlyCache?: boolean): Promise<void> {
    console.warn(
      "ExpoVideoCache: Local proxy server is not supported on Web. Videos will stream directly."
    );
  }

  /**
   * Transforms a remote URL into a locally cacheable URL (Pass-through on Web).
   *
   * Since no proxy server exists, this method simply returns the original URL.
   * Browsers handle media caching internally via the standard HTTP cache headers
   * (Cache-Control, ETag, etc.).
   *
   * - Parameters:
   * - url: The original remote URL.
   * - isCacheable: Ignored on Web.
   * - Returns: The original `url` string.
   */
  convertUrl(url: string, isCacheable?: boolean): string {
    return url;
  }

  /**
   * Clears the video cache (No-op on Web).
   *
   * Browsers do not allow programmatic clearing of specific media caches via
   * JavaScript for security and privacy reasons.
   */
  async clearCache(): Promise<void> {
    console.warn(
      "ExpoVideoCache: programmatic cache clearing is not supported by browser APIs."
    );
  }
}

export default registerWebModule(ExpoVideoCacheModule, "ExpoVideoCache");
