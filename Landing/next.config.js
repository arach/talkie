/** @type {import('next').NextConfig} */
const basePath = process.env.BASE_PATH || ''

const config = {
  output: 'export',
  trailingSlash: true,
  images: { unoptimized: true },
  // For GitHub Pages with a project path, set BASE_PATH env to "/<repo>"
  // For custom domain (e.g., talkie.arach.dev), leave BASE_PATH empty
}

if (basePath) {
  config.basePath = basePath
  config.assetPrefix = `${basePath}/`
}

module.exports = config
