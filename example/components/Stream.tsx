import { clearVideoCacheAsync, VideoSource } from "expo-video";
import React, { useRef, useState, useMemo } from "react";
import {
  FlatList,
  LayoutChangeEvent,
  Platform,
  StyleSheet,
  View,
  ViewToken,
  TouchableOpacity,
  Text,
  SafeAreaView,
} from "react-native";
import VideoItem from "./VideoItem";
import { convertUrl, clearCache } from "../utils/videoCache";

// 1. Raw Data Definition
// We keep this outside to prevent recreation, but we store only plain strings.
// We do NOT call convertUrl() here to avoid the Race Condition.
const rawVideoData = [
  {
    uri: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8",
  },
];

// Helper to safely extract URI string from VideoSource
const getUriFromSource = (source: VideoSource): string | null => {
  if (typeof source === "string") {
    return source;
  }
  if (source && typeof source === "object" && source.uri) {
    return source.uri;
  }
  return null;
};

export default function Stream() {
  const [listHeight, setListHeight] = useState(0);

  // 2. Dynamic Source Generation (The Fix 🛠️)
  // This runs ONLY when the component mounts. By this time, App.tsx
  // has already waited for startServer(), so the Native Module is ready.
  const videoSources = useMemo(() => {
    return rawVideoData.map((item) => ({
      // iOS: Use Proxy | Android: Use Native Cache
      uri: convertUrl(item.uri, Platform.OS === "ios"),
      useCaching: Platform.OS === "android",
    }));
  }, []);

  const [activeViewableItem, setActiveViewableItem] = useState<string | null>(
    getUriFromSource(videoSources[0])
  );

  // Viewability Config for TikTok-style snapping
  const viewabilityConfigCallbackPairs = useRef([
    {
      viewabilityConfig: {
        itemVisiblePercentThreshold: 50,
      },
      onViewableItemsChanged: ({
        viewableItems,
      }: {
        viewableItems: ViewToken[];
      }) => {
        if (viewableItems.length > 0 && viewableItems[0].isViewable) {
          setActiveViewableItem(getUriFromSource(viewableItems[0].item));
        }
      },
    },
  ]);

  const onLayout = (e: LayoutChangeEvent) => {
    const { height } = e.nativeEvent.layout;
    if (height > 0 && height !== listHeight) {
      setListHeight(height);
    }
  };

  const handleClearCache = async () => {
    try {
      // Clear Expo's native cache (Android)
      clearVideoCacheAsync()
        .then(() => console.log("🤖 Expo video cache cleared!"))
        .catch((e) => console.error("Failed to clear expo cache:", e));

      // Clear our custom Proxy cache (iOS)
      clearCache()
        .then(() => console.log("🍎 Native proxy cache cleared!"))
        .catch((e) => console.error("Failed to clear proxy cache:", e));
    } catch (error) {
      console.error("Failed to clear cache:", error);
    }
  };

  return (
    <View style={styles.container} onLayout={onLayout}>
      {listHeight > 0 && (
        <FlatList
          data={videoSources}
          extraData={activeViewableItem}
          style={styles.container}
          renderItem={({ item }) => (
            <VideoItem
              source={item}
              isActive={activeViewableItem === getUriFromSource(item)}
              height={listHeight}
            />
          )}
          keyExtractor={(item) => getUriFromSource(item) ?? ""}
          pagingEnabled
          removeClippedSubviews={Platform.OS === "ios"} // Safer to disable on Android if seeing black screens
          windowSize={5} // Optimization: Keep 5 screens worth of content
          initialNumToRender={1}
          maxToRenderPerBatch={3}
          viewabilityConfigCallbackPairs={
            viewabilityConfigCallbackPairs.current
          }
          // Optimization: Pre-calculate layout to avoid jumps
          getItemLayout={(_data, index) => ({
            length: listHeight,
            offset: listHeight * index,
            index,
          })}
          showsVerticalScrollIndicator={false}
        />
      )}

      {/* Clear Cache Button Overlay */}
      <SafeAreaView style={styles.controls}>
        <TouchableOpacity style={styles.button} onPress={handleClearCache}>
          <Text style={styles.buttonText}>Clear Cache</Text>
        </TouchableOpacity>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#000",
  },
  controls: {
    position: "absolute",
    top: 50,
    right: 20,
    zIndex: 100,
  },
  button: {
    backgroundColor: "rgba(255, 255, 255, 0.8)",
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
  },
  buttonText: {
    color: "#000",
    fontWeight: "bold",
    fontSize: 14,
  },
});
