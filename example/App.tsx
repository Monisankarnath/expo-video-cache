import { useEffect } from "react";
// import TestVideoCache from "./components/StepZero";
import { clearCache, startServer } from "./utils/videoCache";
import Stream from "./components/Stream";
import { SafeAreaView } from "react-native";
import { clearVideoCacheAsync } from "expo-video";

export default function App() {
  useEffect(() => {
    startServer();
  }, []);
  return <Stream />;
}

const styles = {
  container: {
    flex: 1,
    backgroundColor: "#eee",
  },
};
