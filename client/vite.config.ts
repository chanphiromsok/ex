import { defineConfig } from 'vite'
import { tanstackStart } from '@tanstack/react-start/plugin/vite'
import viteReact from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// The browser calls the Phoenix API directly; in dev Vite proxies /api so no CORS is needed.
const apiUrl = process.env.API_URL ?? 'http://localhost:4000'

export default defineConfig({
  resolve: { tsconfigPaths: true },
  server: { proxy: { '/api': { target: apiUrl, changeOrigin: true } } },
  plugins: [tailwindcss(), tanstackStart(), viteReact()],
})
