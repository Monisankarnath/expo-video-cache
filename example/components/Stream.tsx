import { VideoSource } from "expo-video";
import React, { useRef, useState } from "react";
import {
  FlatList,
  LayoutChangeEvent,
  Platform,
  StyleSheet,
  View,
  ViewToken,
} from "react-native";
import VideoItem from "./VideoItem";
import { convertUrl } from "../utils/videoCache";

// A list of sample videos to populate our feed.
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

// Helper function to safely extract the URI from a VideoSource
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
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#000",
  },
});
