import { useVideoPlayer, VideoSource, VideoView } from "expo-video";
import React, { useEffect, useState } from "react";
import { Pressable, StyleSheet, useWindowDimensions } from "react-native";
import NetInfo from "@react-native-community/netinfo";

type Props = {
  source: VideoSource;
  isActive: boolean;
  height: number;
};

export default function VideoItem({ source, isActive, height }: Props) {
  const [isMuted, setIsMuted] = useState(true);
  const { width } = useWindowDimensions();
  const [isOffline, setIsOffline] = useState(false);
  const player = useVideoPlayer(source, (player) => {
    player.loop = true;
    player.muted = isMuted;
  });
  const replacePlayer = () => {
    player.replace(source);
    if (isActive) player.play();
  };
  useEffect(() => {
    player.muted = isMuted;
  }, [isMuted, player]);

  useEffect(() => {
    if (isActive) {
      player.play();
    } else {
      player.pause();
    }
  }, [isActive, player]);

  useEffect(() => {
    const unsubscribe = NetInfo.addEventListener((state) => {
      const isConnected = state.isConnected ?? false;
      if (isOffline && isConnected) {
        console.log("Connection restored, replacing player...");
        replacePlayer();
      }

      setIsOffline(!isConnected);
    });
    return () => unsubscribe();
  }, [isOffline, isActive, player, source]);

  return (
    <Pressable
      onPress={() => setIsMuted((m) => !m)}
      style={[styles.container, { height, width }]}
    >
      <VideoView style={styles.video} player={player} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#000",
  },
  video: {
    flex: 1,
  },
});
