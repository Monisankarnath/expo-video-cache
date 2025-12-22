import ExpoVideoCacheModule from "./ExpoVideoCacheModule";

export function startServer(
  port?: number,
  maxCacheSize?: number
): Promise<void> {
  return ExpoVideoCacheModule.startServer(port, maxCacheSize);
}

export function convertUrl(url: string, isCacheable?: boolean): string {
  return ExpoVideoCacheModule.convertUrl(url, isCacheable);
}
