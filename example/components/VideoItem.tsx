import { useVideoPlayer, VideoSource, VideoView } from "expo-video";
import React, { useEffect, useState, useRef } from "react";
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
  const wasOfflineRef = useRef(false);
  const isActiveRef = useRef(isActive);
  useEffect(() => {
    isActiveRef.current = isActive;
    if (isActive) {
      player.play();
    } else {
      player.pause();
    }
  }, [isActive]);

  const player = useVideoPlayer(source, (player) => {
    player.loop = true;
    player.muted = isMuted;
  });

  useEffect(() => {
    player.muted = isMuted;
  }, [isMuted, player]);
  useEffect(() => {
    const unsubscribe = NetInfo.addEventListener((state) => {
      const isConnected = state.isConnected ?? true;
      if (wasOfflineRef.current && isConnected) {
        console.log("🛜 Connection restored, reloading player...");
        player.replace(source);
        if (isActiveRef.current) {
          player.play();
        }
      }
      wasOfflineRef.current = !isConnected;
    });
    return () => unsubscribe();
  }, [player, source]);

  return (
    <Pressable
      onPress={() => setIsMuted((m) => !m)}
      style={[styles.container, { height, width }]}
    >
      <VideoView 
        style={styles.video} 
        player={player} 
        nativeControls={false}
      />
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