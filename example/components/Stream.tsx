import { VideoSource } from "expo-video";
import React, { useRef, useState } from "react";
import {
  FlatList,
  LayoutChangeEvent,
  Platform,
  StyleSheet,
  View,
  ViewToken,
  TouchableOpacity,
  Text,
  Alert,
  SafeAreaView,
} from "react-native";
import VideoItem from "./VideoItem";
import { convertUrl, clearCache } from "../utils/videoCache";

const videoSources: VideoSource[] = [
  {
    uri: convertUrl(
      "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8",
      Platform.OS === "ios" ? true : false
    ),
    useCaching: Platform.OS === "android" ? true : false,
  },
  {
    uri: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
    useCaching: true,
  },
];

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
  const [activeViewableItem, setActiveViewableItem] = useState<string | null>(
    getUriFromSource(videoSources[0])
  );

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
      await clearCache();
      Alert.alert("Success", "Cache cleared successfully!");
    } catch (error) {
      console.error("Failed to clear cache:", error);
      Alert.alert("Error", "Failed to clear cache.");
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
          removeClippedSubviews
          windowSize={5}
          initialNumToRender={1}
          maxToRenderPerBatch={3}
          viewabilityConfigCallbackPairs={
            viewabilityConfigCallbackPairs.current
          }
          getItemLayout={(_data, index) => ({
            length: listHeight,
            offset: listHeight * index,
            index,
          })}
          showsVerticalScrollIndicator={false}
        />
      )}
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
