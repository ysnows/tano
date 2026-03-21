import Foundation

// MARK: - TanoDevOverlay

/// Development-only error overlay injected into the WebView that catches
/// and displays runtime errors during development.
///
/// When enabled, the overlay intercepts:
/// - `console.error` calls (server-side errors forwarded from TanoJSC)
/// - Bridge call failures (plugin invoke errors)
/// - Unhandled JS exceptions (`window.onerror`)
/// - Unhandled promise rejections (`window.onunhandledrejection`)
///
/// The overlay is a fixed-position panel at the bottom of the screen with
/// a semi-transparent dark background. It shows the last 5 errors with
/// color-coded type icons and supports tap-to-expand for full stack traces.
///
/// Toggle visibility by double-tapping the top 44px (status bar area).
///
/// Usage:
/// ```swift
/// TanoDevOverlay.enabled = true  // before creating the WebView
/// ```
public enum TanoDevOverlay {

    /// Set to `true` before creating a TanoWebView to inject the dev overlay.
    public static var enabled = false

    /// Self-contained JavaScript that creates and manages the dev overlay.
    /// Injected after bridge.js in dev mode, guarded by `window.__TANO_DEV__`.
    public static let script: String = """
    (function() {
        if (!window.__TANO_DEV__) return;

        var overlay = null;
        var logsList = null;
        var logs = [];
        var isVisible = false;
        var MAX_LOGS = 5;

        function escapeHTML(str) {
            var div = document.createElement('div');
            div.appendChild(document.createTextNode(str));
            return div.innerHTML;
        }

        function createOverlay() {
            if (overlay) return;

            overlay = document.createElement('div');
            overlay.id = '__tano_dev_overlay__';
            overlay.style.cssText = 'position:fixed;bottom:0;left:0;right:0;max-height:50vh;' +
                'background:rgba(20,20,20,0.92);color:#fff;font-family:-apple-system,monospace;' +
                'font-size:12px;z-index:2147483647;overflow-y:auto;display:none;' +
                'border-top:2px solid #ff3b30;box-sizing:border-box;';

            // Header bar
            var header = document.createElement('div');
            header.style.cssText = 'display:flex;justify-content:space-between;align-items:center;' +
                'padding:8px 12px;background:rgba(255,59,48,0.15);border-bottom:1px solid rgba(255,255,255,0.1);';

            var title = document.createElement('span');
            title.style.cssText = 'font-weight:bold;color:#ff6b6b;font-size:13px;';
            title.textContent = 'Tano Dev Overlay';
            header.appendChild(title);

            var closeBtn = document.createElement('span');
            closeBtn.style.cssText = 'cursor:pointer;color:#aaa;font-size:18px;padding:0 4px;' +
                'line-height:1;user-select:none;-webkit-user-select:none;';
            closeBtn.textContent = '\\u00D7';
            closeBtn.addEventListener('click', function(e) {
                e.stopPropagation();
                hideOverlay();
            });
            header.appendChild(closeBtn);

            overlay.appendChild(header);

            logsList = document.createElement('div');
            logsList.style.cssText = 'padding:0;';
            overlay.appendChild(logsList);

            document.body.appendChild(overlay);
        }

        function typeIcon(type) {
            switch (type) {
                case 'error':     return { icon: '\\u25CF', color: '#ff3b30' };
                case 'exception': return { icon: '\\u26A0', color: '#ff3b30' };
                case 'promise':   return { icon: '\\u26A0', color: '#ff9500' };
                case 'bridge':    return { icon: '\\u2192', color: '#ff9500' };
                default:          return { icon: '\\u25CB', color: '#aaa' };
            }
        }

        function renderLogs() {
            if (!logsList) return;
            logsList.innerHTML = '';

            for (var i = 0; i < logs.length; i++) {
                (function(entry) {
                    var row = document.createElement('div');
                    row.style.cssText = 'padding:8px 12px;border-bottom:1px solid rgba(255,255,255,0.06);' +
                        'cursor:pointer;word-break:break-word;';

                    var info = typeIcon(entry.type);

                    var icon = document.createElement('span');
                    icon.style.cssText = 'color:' + info.color + ';margin-right:6px;';
                    icon.textContent = info.icon;
                    row.appendChild(icon);

                    var label = document.createElement('span');
                    label.style.cssText = 'color:rgba(255,255,255,0.5);font-size:10px;margin-right:6px;' +
                        'text-transform:uppercase;';
                    label.textContent = entry.type;
                    row.appendChild(label);

                    var msg = document.createElement('span');
                    msg.style.cssText = 'color:#fff;';
                    msg.textContent = entry.message;
                    row.appendChild(msg);

                    // Stack trace (hidden by default)
                    if (entry.stack) {
                        var stackEl = document.createElement('pre');
                        stackEl.style.cssText = 'display:none;margin:6px 0 0 0;padding:6px;' +
                            'background:rgba(0,0,0,0.3);color:#ccc;font-size:10px;' +
                            'white-space:pre-wrap;word-break:break-all;border-radius:4px;overflow:auto;';
                        stackEl.textContent = entry.stack;

                        row.addEventListener('click', function() {
                            stackEl.style.display = stackEl.style.display === 'none' ? 'block' : 'none';
                        });

                        row.appendChild(stackEl);
                    }

                    logsList.appendChild(row);
                })(logs[i]);
            }
        }

        function showOverlay() {
            if (!overlay) createOverlay();
            overlay.style.display = 'block';
            isVisible = true;
        }

        function hideOverlay() {
            if (overlay) overlay.style.display = 'none';
            isVisible = false;
        }

        function toggleOverlay() {
            if (isVisible) {
                hideOverlay();
            } else {
                if (logs.length > 0) showOverlay();
            }
        }

        function showError(type, message, stack) {
            logs.push({ type: type, message: message || '', stack: stack || null });
            if (logs.length > MAX_LOGS) {
                logs.shift();
            }
            showOverlay();
            renderLogs();
        }

        // -- Intercept console.error --
        var origError = console.error;
        console.error = function() {
            origError.apply(console, arguments);
            var msg = Array.prototype.slice.call(arguments).join(' ');
            showError('error', msg);
        };

        // -- Intercept unhandled errors --
        window.onerror = function(msg, url, line, col, error) {
            var stack = error && error.stack ? error.stack : (url ? url + ':' + line + ':' + col : '');
            showError('exception', String(msg), stack);
            return false;
        };

        // -- Intercept unhandled promise rejections --
        window.addEventListener('unhandledrejection', function(event) {
            var reason = event.reason;
            var msg = reason instanceof Error ? reason.message : String(reason);
            var stack = reason instanceof Error ? reason.stack : null;
            showError('promise', msg, stack);
        });

        // -- Intercept failed Tano.invoke calls --
        var origInvoke = window.Tano && window.Tano.invoke;
        if (origInvoke) {
            window.Tano.invoke = function(plugin, method, params) {
                return origInvoke.call(window.Tano, plugin, method, params).catch(function(err) {
                    showError('bridge', plugin + '.' + method + ': ' + (err.message || String(err)));
                    throw err;
                });
            };
        }

        // -- Double-tap status bar area (top 44px) to toggle --
        var lastTapTime = 0;
        document.addEventListener('touchstart', function(e) {
            if (e.touches.length !== 1) return;
            var touch = e.touches[0];
            if (touch.clientY > 44) return;

            var now = Date.now();
            if (now - lastTapTime < 300) {
                toggleOverlay();
                lastTapTime = 0;
            } else {
                lastTapTime = now;
            }
        }, { passive: true });

        // -- Shake gesture to toggle (iOS) --
        var shakeThreshold = 30;
        var lastShakeTime = 0;
        var lastX = null, lastY = null, lastZ = null;
        window.addEventListener('devicemotion', function(e) {
            var acc = e.accelerationIncludingGravity;
            if (!acc) return;

            if (lastX !== null) {
                var dx = Math.abs(acc.x - lastX);
                var dy = Math.abs(acc.y - lastY);
                var dz = Math.abs(acc.z - lastZ);
                if (dx + dy + dz > shakeThreshold) {
                    var now = Date.now();
                    if (now - lastShakeTime > 1000) {
                        lastShakeTime = now;
                        toggleOverlay();
                    }
                }
            }
            lastX = acc.x; lastY = acc.y; lastZ = acc.z;
        }, { passive: true });

        // Expose for programmatic use
        window.__TanoDevOverlay = {
            show: showOverlay,
            hide: hideOverlay,
            toggle: toggleOverlay,
            addError: showError
        };
    })();
    """
}
