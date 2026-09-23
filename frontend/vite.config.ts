import { fileURLToPath, URL } from 'node:url'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig, loadEnv } from 'vite'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, '..', '')
  return {
    plugins: [react(), tailwindcss()],
    resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
    server: {
      host: '127.0.0.1', port: 5173, strictPort: true,
      proxy: { '/api': { target: process.env.API_PROXY_TARGET || env.API_PROXY_TARGET || 'http://127.0.0.1:8080', changeOrigin: true } },
    },
  }
})
