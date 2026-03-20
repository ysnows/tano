import Foundation

// MARK: - TanoBridgeJS

/// Contains the JavaScript bridge code injected into the WebView at document start.
///
/// This creates the `window.Tano` API that the user's web app uses to communicate
/// with native plugins via `invoke()`, listen for events via `on()`, and send
/// fire-and-forget messages via `send()`.
public enum TanoBridgeJS {

    /// The bridge JavaScript source, injected as a WKUserScript at `.atDocumentStart`.
    ///
    /// Provides:
    /// - `window.Tano.invoke(plugin, method, params)` — call native plugin, returns Promise
    /// - `window.Tano.on(event, callback)` — subscribe to native events, returns unsubscribe fn
    /// - `window.Tano.send(event, data)` — fire-and-forget message to native
    /// - `window.Tano._resolve(callId, result)` — called by native to resolve a pending invoke
    /// - `window.Tano._reject(callId, error)` — called by native to reject a pending invoke
    /// - `window.Tano._emit(event, data)` — called by native to emit an event to listeners
    public static let script: String = """
    (function() {
        'use strict';

        window.Tano = {
            _callId: 0,
            _pendingCalls: {},
            _eventListeners: {},

            invoke: function(plugin, method, params) {
                return new Promise(function(resolve, reject) {
                    var callId = String(++window.Tano._callId);
                    window.Tano._pendingCalls[callId] = { resolve: resolve, reject: reject };
                    window.Tano._pendingCalls[callId].timeout = setTimeout(function() {
                        delete window.Tano._pendingCalls[callId];
                        reject(new Error('Tano.invoke timeout: ' + plugin + '.' + method));
                    }, 30000);

                    window.webkit.messageHandlers.tano.postMessage({
                        type: 'invoke',
                        callId: callId,
                        plugin: plugin,
                        method: method,
                        params: params || {}
                    });
                });
            },

            on: function(event, callback) {
                if (!window.Tano._eventListeners[event]) {
                    window.Tano._eventListeners[event] = [];
                }
                window.Tano._eventListeners[event].push(callback);
                return function() {
                    var listeners = window.Tano._eventListeners[event];
                    if (listeners) {
                        var idx = listeners.indexOf(callback);
                        if (idx >= 0) listeners.splice(idx, 1);
                    }
                };
            },

            send: function(event, data) {
                window.webkit.messageHandlers.tano.postMessage({
                    type: 'event',
                    event: event,
                    data: data || {}
                });
            },

            _resolve: function(callId, result) {
                var pending = window.Tano._pendingCalls[callId];
                if (pending) {
                    clearTimeout(pending.timeout);
                    delete window.Tano._pendingCalls[callId];
                    pending.resolve(result);
                }
            },

            _reject: function(callId, error) {
                var pending = window.Tano._pendingCalls[callId];
                if (pending) {
                    clearTimeout(pending.timeout);
                    delete window.Tano._pendingCalls[callId];
                    pending.reject(new Error(error));
                }
            },

            _emit: function(event, data) {
                var listeners = window.Tano._eventListeners[event] || [];
                for (var i = 0; i < listeners.length; i++) {
                    try { listeners[i](data); } catch(e) { console.error('Tano event handler error:', e); }
                }
            }
        };
    })();
    """
}
