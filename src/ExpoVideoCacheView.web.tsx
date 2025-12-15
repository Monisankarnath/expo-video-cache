import * as React from 'react';

import { ExpoVideoCacheViewProps } from './ExpoVideoCache.types';

export default function ExpoVideoCacheView(props: ExpoVideoCacheViewProps) {
  return (
    <div>
      <iframe
        style={{ flex: 1 }}
        src={props.url}
        onLoad={() => props.onLoad({ nativeEvent: { url: props.url } })}
      />
    </div>
  );
}
