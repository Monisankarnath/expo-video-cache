// Reexport the native module. On web, it will be resolved to ExpoVideoCacheModule.web.ts
// and on native platforms to ExpoVideoCacheModule.ts
export { default } from './ExpoVideoCacheModule';
export { default as ExpoVideoCacheView } from './ExpoVideoCacheView';
export * from  './ExpoVideoCache.types';
