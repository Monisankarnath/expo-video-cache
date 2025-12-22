# expo-video-cache

A highly efficient, local proxy server for caching **HLS (HTTP Live Streaming)** video content on iOS.

This module is designed to work as an add-on for [`expo-video`](https://docs.expo.dev/versions/latest/sdk/video/). While `expo-video` (and the underlying AVPlayer/ExoPlayer) handles standard `.mp4` caching and Android caching natively, iOS requires a local proxy to effectively cache HLS streams (`.m3u8`, `.ts`, fMP4) for offline playback.

## ❓ Why use this?

Starting with **Expo SDK 53**, the `expo-video` library introduced a native `useCaching` property.

- ✅ **Native `expo-video` caching works great for:** Standard `.mp4` files and Android (ExoPlayer).
- ❌ **It falls short on:** **HLS (.m3u8) on iOS**. AVPlayer does not natively support simple caching for HLS streams because they consist of hundreds of tiny `.ts` files and manifests.

**This library is specifically engineered to fill that gap.** It creates a local proxy to handle the complex HLS file structure, allowing you to cache streams on iOS just as easily as MP4s.

## 🚀 Features

- **iOS HLS Support:** Caches complex HLS playlists, including standard MPEG-TS and modern Fragmented MP4 (fMP4) streams (Netflix/Disney+ style).
- **Offline Playback:** Automatically rewrites manifests to serve content from the local disk when offline.
- **Smart Pruning:** Automatically manages disk space with a configurable max cache size (LRU strategy).
- **Zero-Config Android:** On Android, this module acts as a pass-through, relying on the native player's built-in caching capabilities.

## 📦 Installation

```bash
npx expo install expo-video-cache
```

Alternative package managers:

```bash
# npm
npm install expo-video-cache

# yarn
yarn add expo-video-cache

# pnpm
pnpm add expo-video-cache
```

## 🛠 Usage

This module works by spinning up a tiny local web server on your device. You must start the server once when your app launches, and then pass your video URLs through a converter function before giving them to the `<VideoView />`.

### 1. Import the module

```typescript
import * as VideoCache from "expo-video-cache";
```

### 2. Start the Server

Call this early in your app's lifecycle (e.g., in `app/_layout.tsx` or your root component).

```typescript
// Start server on port 9000 with a 1GB cache limit
await VideoCache.startServer(9000, 1024 * 1024 * 1024);
```

### 3. Convert URLs

Before passing a URL to your video player, convert it. If the content is cached, it returns a local `http://127.0.0.1...` URL. If not, it proxies the request to download and cache it.

```typescript
const originalUrl = "https://example.com/stream.m3u8";
const sourceUrl = VideoCache.convertUrl(originalUrl);

// Pass 'sourceUrl' to your player
```

### 4. Manage Cache

You can clear the cache manually if needed (e.g., via a settings screen).

```typescript
await VideoCache.clearCache();
```

## 💡 Complete Example

Here is how to integrate it with `expo-video`.

```tsx
import { useEffect, useState } from "react";
import { View, Text, Platform, StyleSheet } from "react-native";
import { VideoView, useVideoPlayer } from "expo-video";
import * as VideoCache from "expo-video-cache";

const STREAM_URL =
  "[https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8](https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8)";

export default function VideoScreen() {
  const [isServerReady, setServerReady] = useState(false);

  // 1. Initialize the Server (Best done in a root component or layout)
  useEffect(() => {
    const bootstrap = async () => {
      try {
        await VideoCache.startServer(9000, 1024 * 1024 * 1024); // Port 9000, 1GB Limit
        setServerReady(true);
      } catch (error) {
        console.error("Failed to start cache server:", error);
      }
    };
    bootstrap();
  }, []);

  // 2. Prepare the Source
  // - iOS: Convert URL to localhost. Disable native caching (Proxy handles it).
  // - Android: Returns original URL. Enable native caching (ExoPlayer handles it).
  const videoSource = {
    uri: isServerReady ? VideoCache.convertUrl(STREAM_URL) : "",
    useCaching: Platform.OS === "android",
  };

  const player = useVideoPlayer(
    isServerReady ? videoSource : null,
    (player) => {
      player.loop = true;
      player.play();
    }
  );

  if (!isServerReady) {
    return (
      <View style={styles.center}>
        <Text>Initializing Cache...</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <VideoView style={styles.video} player={player} allowsFullscreen />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#000", justifyContent: "center" },
  center: { flex: 1, alignItems: "center", justifyContent: "center" },
  video: { width: "100%", height: 300 },
});
```

## 🧩 Advanced Usage: Vertical Video Feed

If you are building a vertical feed (like TikTok/Reels) using `FlatList`, you must be careful not to double-cache on iOS.

**Key Pattern:**

1. **iOS HLS:** Use `convertUrl()` AND set `useCaching: false` (since our proxy handles the cache).
2. **Android:** Use raw URL AND set `useCaching: true` (let ExoPlayer handle it).

```typescript
const videoSource = {
  uri: convertUrl(hlsUrl),
  // ⚠️ Important: Disable native caching on iOS to avoid conflicts with the proxy
  useCaching: Platform.OS === "android",
};
```

## 📱 Platform Compatibility

| Platform    | Supported Formats      | Caching Strategy                                                                                                   |
| :---------- | :--------------------- | :----------------------------------------------------------------------------------------------------------------- |
| **iOS**     | HLS (.m3u8), fMP4, .ts | **Active Proxy.** Uses a local server to intercept, rewrite manifests, and cache segments to disk.                 |
| **Android** | All                    | **Passthrough.** Returns the original URL unaltered. `expo-video` (ExoPlayer) handles caching natively on Android. |
| **Web**     | -                      | **Not Supported.** Returns original URL.                                                                           |

## 🎯 Best Practices & Caveats

### 1. ❌ Do NOT use for large MP4/MOV files

This module is strictly optimized for **HLS Streaming (.m3u8)**.

- **Why?** The proxy downloads a requested file _completely_ to disk before serving it to the player.
- **HLS:** Segments are small (~2MB). The download is instant, and playback is smooth.
- **MP4:** If you try to cache a 500MB movie file, the player will show a black screen until the **entire 500MB** is downloaded.
- **Solution:** For standard MP4 files, use the original URL directly. `expo-video` handles MP4 caching natively.

### 2. 🏁 Start the Server Once

Call `VideoCache.startServer(...)` only once, preferably in your root `_layout.tsx` or `App.tsx`.

- The module prevents multiple instances automatically, but calling it repeatedly is redundant.
- The server keeps running in the background as long as the app is alive.

### 3. 🤖 Android is Passthrough

Remember that `VideoCache.convertUrl(url)` returns the **original** URL on Android.

- Do not write logic that assumes a `127.0.0.1` address on Android.
- This module relies on ExoPlayer's built-in caching on Android (which is excellent by default).

## ⚠️ Limitations

1.  **Large Static Files:** As mentioned above, avoid using this for non-HLS files (MP4, MKV, MOV) larger than a few MBs to avoid blocking playback.
2.  **DRM Protected Content:** Encrypted streams (FairPlay) are **not supported**. Rewriting the manifest URLs usually breaks the digital signature verification required by DRM agents.
3.  **Live Streams:** Caching is technically supported for Live HLS, but it is recommended strictly for **VOD (Video on Demand)**. Live streams can generate infinite segments, filling up the cache limit quickly and triggering aggressive pruning.

## 📄 License

MIT

```

```
