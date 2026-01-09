import { useEffect, useState } from "react";
import { View, ActivityIndicator } from "react-native";
import { startServer } from "./utils/videoCache";
import Stream from "./components/Stream";

export default function App() {
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    const init = async () => {
      try {
        await startServer(); // Wait for native server to confirm start
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
