import { defineConfig } from '@hey-api/openapi-ts'

export default defineConfig({
  input: './openapi/openapi.json',
  output: { path: './src/api', clean: true },
  plugins: [
    { name: '@hey-api/client-axios', runtimeConfigPath: '#/lib/api-config' },
    '@hey-api/typescript',
    '@hey-api/sdk',
    '@tanstack/react-query',
  ],
})
