# Three.js subset

Three.js 0.187.0 (MIT), bundled with esbuild 0.28.2: 56,451 bytes before compression. Exports Scene, PerspectiveCamera, MathUtils, CSS3DRenderer and CSS3DObject. No WebGL renderer, canvas, textures, runtime CDN or installation in the website.

Sources: [Three.js r187](https://github.com/mrdoob/three.js/tree/r187), [CSS3DRenderer](https://threejs.org/docs/pages/CSS3DRenderer.html). MIT license in THREE-LICENSE.txt.

Rebuild in a temporary npm prefix using `npm install --no-save --ignore-scripts three@0.187.0 esbuild@0.28.2`.

`three-subset.js`:
```js
export { Scene } from './node_modules/three/src/scenes/Scene.js';
export { PerspectiveCamera } from './node_modules/three/src/cameras/PerspectiveCamera.js';
export * as MathUtils from './node_modules/three/src/math/MathUtils.js';
export { Matrix4 } from './node_modules/three/src/math/Matrix4.js';
export { Object3D } from './node_modules/three/src/core/Object3D.js';
export { Quaternion } from './node_modules/three/src/math/Quaternion.js';
export { Vector3 } from './node_modules/three/src/math/Vector3.js';
```

`entry.js`:
```js
export { Scene, PerspectiveCamera, MathUtils } from './three-subset.js';
export { CSS3DRenderer, CSS3DObject } from './node_modules/three/examples/jsm/renderers/CSS3DRenderer.js';
```

Run `esbuild entry.js --alias:three=/absolute/build/path/three-subset.js --bundle --minify --format=esm --target=es2020 --outfile=pulse-three.js`. Copy the output and original Three.js LICENSE; keep npm dependencies outside the repository.
