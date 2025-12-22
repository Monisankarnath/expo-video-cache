import { useEffect } from "react";
import { startServer } from "./utils/videoCache";
import Stream from "./components/Stream";

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
