import ExpoVideoCacheModule from "./ExpoVideoCacheModule";

export function startServer(port: number): Promise<void> {
  return ExpoVideoCacheModule.startServer(port);
}

export function convertUrl(url: string, port: number): string {
  return ExpoVideoCacheModule.convertUrl(url, port);
}
