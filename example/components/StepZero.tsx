import React, { useState } from "react";
import { View, Text, Button, StyleSheet, Platform } from "react-native";
import * as VideoCache from "../../src/index";

let port = 9000;
let testURL =
  "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4";

export default function TestVideoCache() {
  const [status, setStatus] = useState("Waiting to test...");
  const [convertedUrl, setConvertedUrl] = useState("");

  const testModule = async () => {
    try {
      console.log(`JS: Starting Server on ${port}...`);
      await VideoCache.startServer(port);

      // 1. Convert
      const localUrl = VideoCache.convertUrl(testURL, port);
      console.log("JS: Local URL is:", localUrl);
      setConvertedUrl(localUrl);

      // 2. Platform Specific Checks
      if (Platform.OS === "ios") {
        // iOS: Fetch from local server to ensure it is running
        const response = await fetch(localUrl);
        const text = await response.text();
        console.log("JS: Server Response:", text);

        if (text.includes("Hello from Swifter")) {
          // ✅ Fixed string match
          setStatus("✅ SUCCESS: iOS Server responded correctly!");
        } else {
          setStatus("❌ FAILED: Server response mismatch.");
        }
      } else if (Platform.OS === "android") {
        // Android: Just check if the URL was returned unchanged (Pass-through)
        // We do NOT fetch() because we don't want to download the whole video here.
        if (localUrl === testURL) {
          setStatus("✅ SUCCESS: Android returned original URL!");
        } else {
          setStatus("❌ FAILED: Android URL mismatch.");
        }
      } else {
        setStatus("⚠️ Web/Other is not fully supported yet.");
      }
    } catch (e: any) {
      console.error("Test Error:", e);
      setStatus(`Error: ${e.message}`);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.text}>Status: {status}</Text>
      <Text style={styles.text} numberOfLines={2}>
        Converted: {convertedUrl}
      </Text>
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
