import { requireNativeModule } from "expo";

/**
 * Loads the native "ExpoVideoCache" module.
 *
 * This file serves as the direct interface to the native runtime. It uses Expo's
 * `requireNativeModule` to synchronously install the JSI (JavaScript Interface) bindings.
 *
 * This object will contain the functions defined in the native `ModuleDefinition`, such as:
 * - `startServer(port, maxCacheSize)`
 * - `convertUrl(url, isCacheable)`
 * - `clearCache()`
 */
export default requireNativeModule("ExpoVideoCache");
