export default {
    app: {
        name: 'ChatApp',
        identifier: 'com.example.chatapp',
        version: '1.0.0',
    },
    server: {
        entry: './src/server/index.ts',
        port: 18899,
    },
    web: {
        entry: './src/web/index.html',
    },
    env: {
        // Set your Groq API key here or via environment variable
        // GROQ_API_KEY: 'gsk_...',
    },
    plugins: [],
    ios: { deploymentTarget: '15.0' },
    android: { minSdk: 24 },
}
