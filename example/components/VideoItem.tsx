import { useVideoPlayer, VideoSource, VideoView } from "expo-video";
import React, { useEffect, useRef, useState } from "react";
import { Pressable, StyleSheet, useWindowDimensions } from "react-native";

type Props = {
  source: VideoSource;
  isActive: boolean;
  height: number;
};

export default function VideoItem({ source, isActive, height }: Props) {
  // 1. Add state to control the mute status. Start muted by default.
  const [isMuted, setIsMuted] = useState(true);
  const player = useVideoPlayer(source, (player) => {
    player.loop = true;
  });

  // 2. A simple effect to sync the player's muted property with our state.
  useEffect(() => {
    player.muted = isMuted;
  }, [isMuted, player]);

  const isMounted = useRef(false);
  useEffect(() => {
    isMounted.current = true;
    return () => {
      isMounted.current = false;
    };
  }, []);

  useEffect(() => {
    if (isActive && isMounted.current) {
      player.play();
    } else {
      player.pause();
    }
  }, [isActive, player]);

  const { width } = useWindowDimensions();

  return (
    // 3. Wrap the video in a Pressable to toggle the mute state on tap.
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
