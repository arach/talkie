import { join } from "node:path";

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  transpilePackages: ["hudsonkit"],
  turbopack: {
    root: join(process.cwd(), "../../.."),
  },
};

export default nextConfig;
