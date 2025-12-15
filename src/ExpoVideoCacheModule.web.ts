import { registerWebModule, NativeModule } from 'expo';

import { ExpoVideoCacheModuleEvents } from './ExpoVideoCache.types';

class ExpoVideoCacheModule extends NativeModule<ExpoVideoCacheModuleEvents> {
  PI = Math.PI;
  async setValueAsync(value: string): Promise<void> {
    this.emit('onChange', { value });
  }
  hello() {
    return 'Hello world! 👋';
  }
}

export default registerWebModule(ExpoVideoCacheModule, 'ExpoVideoCacheModule');
