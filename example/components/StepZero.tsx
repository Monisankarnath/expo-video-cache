import React, { useEffect, useState } from "react";
import { View, Text, Button, StyleSheet } from "react-native";
import * as VideoCache from "../../src/index"; // Adjust path to where your index.ts is

export default function TestVideoCache() {
  const [status, setStatus] = useState("Waiting to test...");
  const [convertedUrl, setConvertedUrl] = useState("");

  const testModule = async () => {
    try {
      // 1. Test startServer
      console.log("JS: Calling startServer...");
      await VideoCache.startServer(1234);
      setStatus("startServer called successfully");

      // 2. Test convertUrl
      console.log("JS: Calling convertUrl...");
      const url = VideoCache.convertUrl("http://my-video.mp4", 1234);
      setConvertedUrl(`Result: ${url}`);
    } catch (e: any) {
      console.error("Module Error:", e);
      setStatus(`Error: ${e.message}`);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.text}>Status: {status}</Text>
      <Text style={styles.text}>Converted URL: {convertedUrl}</Text>
      <Button title="Run Step 0 Tests" onPress={testModule} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    padding: 20,
  },
  text: { marginBottom: 20, textAlign: "center" },
});
