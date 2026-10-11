import { defineConfig } from 'vite';
export default defineConfig({ base: './', build: { outDir: '../pulse/Sources/Pulse/Resources/Assistant', emptyOutDir: true, assetsDir: 'assets', sourcemap: false, chunkSizeWarningLimit: 800, rollupOptions: { onwarn(warning, warn) { if (warning.code !== 'MODULE_LEVEL_DIRECTIVE') warn(warning); } } } });
