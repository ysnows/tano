/**
 * Tano configuration for {{APP_NAME}}
 */
export default {
    /** Application name displayed in the native shell */
    name: "{{APP_NAME}}",

    /** Unique bundle identifier for iOS / application ID for Android */
    bundleId: "com.example.{{APP_NAME}}",

    /** Bun server entry point */
    server: {
        entry: "src/server/index.ts",
        port: 3000,
    },

    /** Web UI served inside the WebView */
    web: {
        entry: "src/web/index.html",
    },

    /** Native plugins to include */
    plugins: [
        "@tano/plugin-http",
    ],

    /** iOS-specific configuration */
    ios: {
        minVersion: "15.0",
    },

    /** Android-specific configuration */
    android: {
        minSdk: 24,
    },
};
