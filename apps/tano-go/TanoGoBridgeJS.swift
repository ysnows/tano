/// JavaScript bridge injected into every page loaded in Tano Go.
///
/// Unlike the full TanoBridge (which uses `webkit.messageHandlers` to call
/// native plugins directly), this bridge proxies plugin invocations back to
/// the dev server via HTTP. The dev server can handle these calls, simulate
/// plugin responses, or forward them to any connected native runtime.
enum TanoGoBridgeJS {
    static let script = """
    (function() {
        window.Tano = {
            _callId: 0,
            _pendingCalls: {},
            _eventListeners: {},

            invoke: function(plugin, method, params) {
                // In Tano Go, plugin calls go via HTTP to the dev server.
                // The dev server can proxy to native plugins or simulate them.
                return fetch('/api/tano/invoke', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ plugin: plugin, method: method, params: params || {} })
                }).then(function(res) { return res.json(); });
            },

            on: function(event, callback) {
                if (!this._eventListeners[event]) this._eventListeners[event] = [];
                this._eventListeners[event].push(callback);
                return function() {
                    var listeners = window.Tano._eventListeners[event];
                    if (listeners) {
                        var idx = listeners.indexOf(callback);
                        if (idx >= 0) listeners.splice(idx, 1);
                    }
                };
            },

            send: function(event, data) {
                fetch('/api/tano/event', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ event: event, data: data || {} })
                }).catch(function() {});
            },

            _emit: function(event, data) {
                var listeners = this._eventListeners[event] || [];
                for (var i = 0; i < listeners.length; i++) {
                    try { listeners[i](data); } catch(e) { console.error(e); }
                }
            },

            onDeepLink: function(callback) {
                return this.on('deepLink', callback);
            }
        };

        console.log('[Tano Go] Bridge loaded — plugin calls proxied via HTTP');
    })();
    """;
}
