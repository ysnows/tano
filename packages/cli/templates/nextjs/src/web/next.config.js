/** @type {import('next').NextConfig} */
const nextConfig = {
    output: 'export',
    trailingSlash: true,
    async rewrites() {
        return [
            { source: '/api/:path*', destination: 'http://127.0.0.1:18899/api/:path*' }
        ];
    }
}
module.exports = nextConfig
