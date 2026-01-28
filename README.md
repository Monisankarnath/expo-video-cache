# expo-video-cache – HLS video caching for Expo & React Native Apps

A high-performance, event-driven local proxy server for caching **HLS (HTTP Live Streaming)** video content on iOS.

This module is a specialized add-on for [`expo-video`](https://docs.expo.dev/versions/latest/sdk/video/). While `expo-video` handles standard MP4 caching natively, it lacks a mechanism to cache complex HLS streams (`.m3u8`, `.ts`, `fMP4`) for offline playback on iOS.

**expo-video-cache** solves this by running a lightweight, non-blocking local server that acts as a middleware between the internet and your video player.

## 🔍 Overview: Expo HLS video caching for iOS & Android

`expo-video-cache` gives you **HLS video caching for Expo + React Native** apps, with a focus on:

- **Expo / React Native iOS HLS caching** for `.m3u8` streams.
- **Offline playback** support for `expo-video` on iOS and React Native apps that stream HLS video.
- **Vertical feeds (TikTok / Reels)** and infinite scroll timelines that aggressively prefetch videos.

If you’re searching for **“how to cache HLS in expo-video on iOS”** or **“Expo HLS offline video caching”**, this library is designed specifically for that use case.

## ❓ Why use expo-video-cache for HLS in Expo/React Native?

- **You stream HLS (`.m3u8`) video in Expo / React Native** and want **offline HLS caching on iOS**, but `expo-video` only caches simple MP4s out of the box.
- **You are building a vertical video feed (Reels / TikTok / Shorts)** in a React Native app and need a cache-aware proxy that throttles concurrent segment downloads to avoid **Socket Error 61** and connection failures.
- **You want a drop-in helper for expo-video**, not a full custom player: keep using `VideoView` / `useVideoPlayer`, but plug in a smarter URL + caching layer.
- **You care about disk usage and stability**: this library includes LRU pruning and file-descriptor–safe download logic tuned specifically for HLS segment storms.

## ⚡️ Architecture & Performance

Unlike basic caching solutions that download files sequentially, this library implements a robust **Event Loop Architecture** designed for high-throughput media streaming:

1.  **Non-Blocking I/O:** Uses an event-driven network layer to handle simultaneous segment downloads without blocking the main thread or UI.
2.  **Traffic Control (Semaphore Pattern):** Implements a strict concurrency limit (default: 32 active downloads) to prevent "Socket Error 61" and connection refusals during rapid seeking.
3.  **Lazy Resource Allocation:** File handles are only opened when data actually arrives. This prevents **File Descriptor Exhaustion** (crashes caused by opening too many files at once) when queuing hundreds of HLS segments.
4.  **Stream-While-Downloading:** The proxy pipes data to the player immediately while saving to disk in the background. If you watch it once, it is cached forever.

## 🚀 Features

- **iOS HLS Support:** Full support for HLS playlists, MPEG-TS chunks, and Fragmented MP4 (fMP4) streams.
- **Offline Playback:** Rewrites manifests on-the-fly. If a segment exists on disk, the player gets the local path. If not, it proxies the network request.
- **Instant Startup:** The server uses a "Wait-for-Ready" signal to ensure the socket is fully bound before returning a URL, eliminating race conditions on app launch.
- **LRU Pruning:** Automatically manages disk usage. When the cache hits the limit (e.g., 1GB), it silently deletes the oldest files to make room for new content.
- **Zero-Config Android:** On Android, this module acts as a pass-through, leveraging the native ExoPlayer's built-in caching engine.

## 📦 Installation

```bash
npx expo install expo-video-cache
```

## 🛠 Quickstart: How to cache HLS video in Expo/React Native

1. **Install the package**: `npx expo install expo-video-cache`.
2. **Start the proxy server once** in your root component (e.g. `App.tsx`).
3. **Convert HLS URLs with `convertUrl`** before passing them to `expo-video` so your HLS streams can be cached offline on iOS.
4. **iOS**: use the converted proxy URL and disable native caching.  
   **Android**: keep the original URL and enable native `useCaching`.

The sections below use the example app to show a real-world vertical feed implementation using the public `expo-video-cache` API.

### 1. Import the module

```typescript
import * as VideoCache from "expo-video-cache";
```

### 2. Start the server (App entry)

Start the server once in your app's root component (e.g., `App.tsx`). The example app exposes this as a helper and waits for the native module to be ready before rendering the feed.

```typescript
// example/App.tsx – start expo-video-cache server for HLS caching
import { useEffect, useState } from "react";
import { View, ActivityIndicator } from "react-native";
import * as VideoCache from "expo-video-cache";
import Stream from "./components/Stream";

export default function App() {
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    const init = async () => {
      try {
        // Start expo-video-cache server (HLS proxy) and wait until it's ready
        await VideoCache.startServer(9000, 1024 * 1024 * 1024);
        setIsReady(true);
      } catch (e) {
        console.error("Failed to start server", e);
        // Even if it fails, we should probably let the app load (without caching)
        setIsReady(true);
      }
    };
    init();
  }, []);

  if (!isReady) {
    return (
      <View style={{ flex: 1, justifyContent: "center", alignItems: "center" }}>
        <ActivityIndicator size="large" color="#000" />
      </View>
    );
  }

  return <Stream />;
}
```

### 3. Build sources with `convertUrl` (vertical feed)

In the example `Stream` component, we keep raw HLS URLs as plain strings and only call `convertUrl` **after** the server has started. iOS uses the proxy URL, Android uses the original URL with native caching.

```typescript
// example/components/Stream.tsx – vertical HLS feed with offline caching in Expo/React Native
import { clearVideoCacheAsync, VideoSource } from "expo-video";
import { FlatList, Platform, StyleSheet, View } from "react-native";
import * as VideoCache from "expo-video-cache";
import VideoItem from "./VideoItem";

const rawVideoData = [
  { uri: "https://.../playlist1.m3u8" },
  { uri: "https://.../playlist2.m3u8" },
  // ...
];

export default function Stream() {
  const videoSources = useMemo(
    () =>
      rawVideoData.map((item) => ({
        // iOS: Use Proxy | Android: Use Native Cache
        uri: VideoCache.convertUrl(item.uri),
        useCaching: Platform.OS === "android",
      })),
    [],
  );

  // ... viewability + layout logic omitted for brevity ...

  return (
    <View style={styles.container} onLayout={onLayout}>
      <FlatList
        data={videoSources}
        renderItem={({ item }) => (
          <VideoItem
            source={item}
            isActive={activeViewableItem === getUriFromSource(item)}
            height={listHeight}
          />
        )}
        pagingEnabled
        // other FlatList optimizations...
      />
      {/* Clear cache button calls clearVideoCacheAsync() + VideoCache.clearCache() */}
    </View>
  );
}
```

### 4. Render each video item with `expo-video`

Each item in the feed uses `useVideoPlayer` + `VideoView`, with simple mute-on-tap behavior and a small network-resilience helper.

```typescript
// example/components/VideoItem.tsx
import { useVideoPlayer, VideoSource, VideoView } from "expo-video";
import React, { useEffect, useState, useRef } from "react";
import { Pressable, StyleSheet, useWindowDimensions } from "react-native";

type Props = {
  source: VideoSource;
  isActive: boolean;
  height: number;
};

export default function VideoItem({ source, isActive, height }: Props) {
  const [isMuted, setIsMuted] = useState(true);
  const { width } = useWindowDimensions();

  const player = useVideoPlayer(source, (player) => {
    player.loop = true;
    player.muted = isMuted;
  });

  useEffect(() => {
    if (isActive) {
      player.play();
    } else {
      player.pause();
    }
  }, [isActive]);

  return (
    <Pressable
      onPress={() => setIsMuted((m) => !m)}
      style={[styles.container, { height, width }]}
    >
      <VideoView style={styles.video} player={player} nativeControls={false} />
    </Pressable>
  );
}
```

This trio (`App.tsx` + `Stream.tsx` + `VideoItem.tsx`) forms a complete, production-style vertical feed that uses **expo-video-cache** on iOS and **native ExoPlayer caching** on Android.

### 📱 Platform Support

| Platform | Cache Engine       | How it works                                                                                  |
| -------- | ------------------ | --------------------------------------------------------------------------------------------- |
| iOS      | expo-video-cache   | Starts a local GCDWebServer-style proxy. Intercepts traffic, rewrites manifests, and serves cached `.ts` chunks. |
| Android  | Native (ExoPlayer) | The URL is passed through unchanged. ExoPlayer has excellent built-in LRU caching that requires no proxy.        |
| Web      | Browser Cache      | Returns original URL. Relies on standard browser HTTP caching headers.                       |

### ⚠️ Caveats & Best Practices

- **HLS only**: This library is strictly optimized for HLS (`.m3u8`).
- **Avoid large MP4s**: Do not use this for large static MP4 files (e.g., 500MB movies). The overhead of the proxy provides no benefit over native caching for single large files.
- **Lifecycle**: The server persists as long as the app is alive. You do not need to stop/start it between screens.
- **DRM**: Encrypted streams (FairPlay) are currently not supported. The manifest rewriting process breaks the signature validation required for DRM.

### 📄 License

MIT
