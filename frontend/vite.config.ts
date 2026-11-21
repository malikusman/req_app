import path from 'node:path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5173,
    allowedHosts: true,
    // Docker on Windows: bind-mounted file changes raise no events inside the
    // container, so without polling Vite keeps serving stale modules.
    // Poll gently and only source folders: aggressive polling contends with Rails
    // on the same bind mount and slowed every API request by ~2 s.
    watch: process.env.VITE_USE_POLLING === 'true'
      ? { usePolling: true, interval: 1000, binaryInterval: 3000,
          ignored: ['**/node_modules/**', '**/.git/**', '**/e2e/**', '**/test-results/**', '**/playwright-report/**', '**/dist/**'] }
      : undefined,
    proxy: {
      '/api': {
        target: process.env.VITE_PROXY_TARGET || 'http://localhost:3000',
        changeOrigin: true,
      },
    },
  },
})
