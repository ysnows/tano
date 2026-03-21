export default {
    app: {
        name: 'NotesApp',
        identifier: 'com.example.notesapp',
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
        '@tano/plugin-clipboard',
        '@tano/plugin-biometrics',
        '@tano/plugin-crypto',
    ],
    ios: { deploymentTarget: '15.0' },
    android: { minSdk: 24 },
}
