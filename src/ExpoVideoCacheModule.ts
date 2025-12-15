import { NativeModule, requireNativeModule } from 'expo';

import { ExpoVideoCacheModuleEvents } from './ExpoVideoCache.types';

declare class ExpoVideoCacheModule extends NativeModule<ExpoVideoCacheModuleEvents> {
  PI: number;
  hello(): string;
  setValueAsync(value: string): Promise<void>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoVideoCacheModule>('ExpoVideoCache');
