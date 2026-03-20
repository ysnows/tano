export default {
    app: {
        name: '{{APP_NAME}}',
        identifier: 'com.example.{{APP_NAME_LOWER}}',
        version: '1.0.0',
    },
    server: {
        entry: './src/server/index.ts',
        port: 18899,
    },
    web: {
        entry: './src/web',
        framework: 'vite',
    },
    plugins: [
        '@tano/plugin-sqlite',
        '@tano/plugin-clipboard',
    ],
    ios: { deploymentTarget: '15.0' },
    android: { minSdk: 24 },
}
