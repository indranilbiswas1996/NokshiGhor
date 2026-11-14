import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// NokshiGhor Vite Configuration
export default defineConfig({
  plugins: [react()],
  server: {
    host: 'localhost',
    port: 5173,
    strictPort: true,
  },
})
