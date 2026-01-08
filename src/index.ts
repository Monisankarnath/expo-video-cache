import ExpoVideoCacheModule from "./ExpoVideoCacheModule";

/**
 * Initializes the local video proxy server.
 *
 * This function handles the setup of the underlying caching mechanism. It should be called
 * as early as possible in your application's lifecycle (e.g., in `App.tsx` or `_layout.tsx`).
 *
 * - **iOS:** Starts a local HTTP server (localhost) to intercept and cache video requests.
 * - **Android:** No-op. Relies on the native player's built-in caching.
 * - **Web:** No-op. Relies on standard browser caching headers.
 *
 * @param port - (Optional) The local port to bind. Defaults to `9000`.
 * @param maxCacheSize - (Optional) The maximum size of the disk cache in bytes. Defaults to `1GB`.
 * @returns A promise that resolves when the server is ready (or immediately on non-iOS platforms).
 */
export function startServer(
  port?: number,
  maxCacheSize?: number
): Promise<void> {
  return ExpoVideoCacheModule.startServer(port, maxCacheSize);
}

/**
 * Converts a remote video URL into a proxy-compatible URL.
 *
 * You should pass the return value of this function to your `<Video />` component's source.
 *
 * - **iOS:** Returns a localhost URL (e.g., `http://127.0.0.1:9000/proxy?url=...`) if the server is running, otherwise returns the original URL.
 * - **Android/Web:** Returns the original remote URL unchanged.
 *
 * @param url - The remote URL of the video asset (e.g., HLS `.m3u8` or standard `.mp4`).
 * @param isCacheable - (Optional) If set to `false`, the proxy is bypassed and the original URL is returned. Defaults to `true`.
 * @returns A string URL ready for playback.
 */
export function convertUrl(url: string, isCacheable?: boolean): string {
  return ExpoVideoCacheModule.convertUrl(url, isCacheable);
}

/**
 * Clears all cached video files from disk.
 *
 * - **iOS:** Deletes files from the local proxy cache directory.
 * - **Android:** No-op (or implementation specific if expanded).
 *
 * @returns A promise that resolves when the cache has been cleared.
 */
export function clearCache(): Promise<void> {
  return ExpoVideoCacheModule.clearCache();
}
