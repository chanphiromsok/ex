import { defineConfig, loadEnv } from 'vite'
import { tanstackStart } from '@tanstack/react-start/plugin/vite'
import viteReact from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// The browser calls the Phoenix API directly; in dev Vite proxies /api so no CORS is needed.
export default defineConfig(({ mode }) => {
  // API_URL comes from the shell or client/.env (gitignored).
  const env = loadEnv(mode, process.cwd(), '')
  const apiUrl = process.env.API_URL ?? env.API_URL ?? 'http://localhost:4000'

  return {
    resolve: { tsconfigPaths: true },
    server: { proxy: { '/api': { target: apiUrl, changeOrigin: true } } },
    plugins: [tailwindcss(), tanstackStart(), viteReact()],
  }
})
