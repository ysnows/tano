export default {
    app: {
        name: 'TanoAccounting',
        identifier: 'com.example.tano-accounting',
        version: '1.0.0',
    },
    server: {
        entry: './src/server/index.ts',
        port: 18899,
    },
    web: {
        entry: './src/web/index.html',
    },
    plugins: [
        '@tano/plugin-sqlite',
        '@tano/plugin-haptics',
        '@tano/plugin-biometrics',
    ],
    ios: { deploymentTarget: '15.0' },
    android: { minSdk: 24 },
}
