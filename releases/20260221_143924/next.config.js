import { withPayload } from '@payloadcms/next/withPayload'

import redirects from './redirects.js'

const allowedImageOrigins = [
  process.env.NEXT_PUBLIC_SERVER_URL,
  process.env.VERCEL_PROJECT_PRODUCTION_URL
    ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`
    : undefined,
  process.env.__NEXT_PRIVATE_ORIGIN,
  'http://localhost:3000',
].filter(Boolean)

/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    remotePatterns: allowedImageOrigins.map((item) => {
      const url = new URL(item)

      return {
        hostname: url.hostname,
        protocol: url.protocol.replace(':', ''),
        ...(url.port ? { port: url.port } : {}),
      }
    }),
  },
  webpack: (webpackConfig) => {
    webpackConfig.resolve.extensionAlias = {
      '.cjs': ['.cts', '.cjs'],
      '.js': ['.ts', '.tsx', '.js', '.jsx'],
      '.mjs': ['.mts', '.mjs'],
    }

    return webpackConfig
  },
  reactStrictMode: true,
  redirects,
}

export default withPayload(nextConfig, { devBundleServerPackages: false })
