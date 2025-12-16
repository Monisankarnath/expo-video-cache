import { registerWebModule, NativeModule } from "expo";

class ExpoVideoCacheModule extends NativeModule {
  async startServer(port: number): Promise<void> {
    console.warn("ExpoHlsCache: HLS Proxying is not supported on Web.");
  }

  convertUrl(url: string, port: number): string {
    console.warn("ExpoHlsCache: URL conversion is not supported on Web.");
    return url; // Return original URL so web playback doesn't crash
  }
}

export default registerWebModule(ExpoVideoCacheModule, "ExpoVideoCache");
