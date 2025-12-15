import { requireNativeView } from 'expo';
import * as React from 'react';

import { ExpoVideoCacheViewProps } from './ExpoVideoCache.types';

const NativeView: React.ComponentType<ExpoVideoCacheViewProps> =
  requireNativeView('ExpoVideoCache');

export default function ExpoVideoCacheView(props: ExpoVideoCacheViewProps) {
  return <NativeView {...props} />;
}
