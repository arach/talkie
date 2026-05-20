import { join } from "node:path";

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  transpilePackages: ["hudsonkit"],
  turbopack: {
    // Was "../../.." (resolved to /Users/art/dev) which made Turbopack
    // walk every sibling project. Narrowed to the talkie monorepo root
    // to contain the watch surface — hudsonkit still resolves through
    // node_modules via its file: link.
    root: join(process.cwd(), "../.."),
  },
};

export default nextConfig;
