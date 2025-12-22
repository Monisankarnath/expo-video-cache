import ExpoVideoCacheModule from "../../src/ExpoVideoCacheModule";

/**
 * Starts the local proxy server.
 * @param port (Optional) The port to listen on. Defaults to 9000 if not provided.
 * @param maxCacheSize (Optional) Max cache size in Bytes. Defaults to 1GB.
 * @throws Error if the port is busy.
 */
export function startServer(port?: number): Promise<void> {
  let maxCacheSize = 1024 * 1024 * 1024;
  return ExpoVideoCacheModule.startServer(port, maxCacheSize);
}

/**
 * Converts a remote URL to a local proxy URL using the active server port.
 * @param url The remote video URL.
 * @param isCacheable (Optional) If false, returns the original URL. Defaults to true.
 */
export function convertUrl(url: string, isCacheable?: boolean): string {
  if (!isCacheable) {
    return url;
  }
  return ExpoVideoCacheModule.convertUrl(url);
}

/**
 * Clears all cached video files from the local storage.
 */
export function clearCache(): Promise<void> {
  return ExpoVideoCacheModule.clearCache();
}
