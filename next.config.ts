import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  // Allow CORS for API routes during development so native mobile clients can connect.
  // In production, tighten this to specific origins or implement proper auth.
  async headers() {
    return [
      {
        source: '/api/:path*',
        headers: [
          { key: 'Access-Control-Allow-Origin', value: '*' },
          { key: 'Access-Control-Allow-Methods', value: 'GET,POST,PUT,DELETE,OPTIONS' },
          { key: 'Access-Control-Allow-Headers', value: 'Content-Type, Authorization' },
        ],
      },
    ];
  },
  // Allow cross-origin requests from local network IPs during development
  allowedDevOrigins: ['192.168.1.75', '192.168.1.*'],
};

export default nextConfig;
