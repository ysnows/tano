import Foundation
import JavaScriptCore

/// Injects Web API polyfills (Headers, Response, Request, URLSearchParams)
/// into a JSContext via `evaluateScript`.
///
/// Each polyfill is guarded by a `typeof` check so it won't clobber
/// any native implementation that might already exist.
public enum TanoWebAPIs {

    /// Inject all Web API polyfills into the given context.
    public static func inject(into context: JSContext) {
        context.evaluateScript(polyfillSource)
    }

    // MARK: - Polyfill Source

    // swiftlint:disable:next function_body_length
    static let polyfillSource: String = """
    // ============================================================
    // Headers polyfill
    // ============================================================
    if (typeof globalThis.Headers === 'undefined') {
      globalThis.Headers = (function() {
        function Headers(init) {
          this._map = {};
          if (init) {
            if (init instanceof Headers) {
              var entries = init.entries();
              for (var i = 0; i < entries.length; i++) {
                this.append(entries[i][0], entries[i][1]);
              }
            } else if (Array.isArray(init)) {
              for (var i = 0; i < init.length; i++) {
                this.append(init[i][0], init[i][1]);
              }
            } else if (typeof init === 'object') {
              var keys = Object.keys(init);
              for (var i = 0; i < keys.length; i++) {
                this.append(keys[i], init[keys[i]]);
              }
            }
          }
        }

        Headers.prototype.get = function(name) {
          var key = name.toLowerCase();
          if (this._map.hasOwnProperty(key)) {
            return this._map[key].join(', ');
          }
          return null;
        };

        Headers.prototype.set = function(name, value) {
          this._map[name.toLowerCase()] = [String(value)];
        };

        Headers.prototype.has = function(name) {
          return this._map.hasOwnProperty(name.toLowerCase());
        };

        Headers.prototype.delete = function(name) {
          delete this._map[name.toLowerCase()];
        };

        Headers.prototype.append = function(name, value) {
          var key = name.toLowerCase();
          if (!this._map[key]) {
            this._map[key] = [];
          }
          this._map[key].push(String(value));
        };

        Headers.prototype.forEach = function(callback, thisArg) {
          var keys = Object.keys(this._map);
          for (var i = 0; i < keys.length; i++) {
            callback.call(thisArg, this._map[keys[i]].join(', '), keys[i], this);
          }
        };

        Headers.prototype.entries = function() {
          var result = [];
          var keys = Object.keys(this._map);
          for (var i = 0; i < keys.length; i++) {
            result.push([keys[i], this._map[keys[i]].join(', ')]);
          }
          return result;
        };

        Headers.prototype.keys = function() {
          return Object.keys(this._map);
        };

        Headers.prototype.values = function() {
          var result = [];
          var keys = Object.keys(this._map);
          for (var i = 0; i < keys.length; i++) {
            result.push(this._map[keys[i]].join(', '));
          }
          return result;
        };

        Headers.prototype.toJSON = function() {
          var obj = {};
          var keys = Object.keys(this._map);
          for (var i = 0; i < keys.length; i++) {
            obj[keys[i]] = this._map[keys[i]].join(', ');
          }
          return obj;
        };

        Object.defineProperty(Headers.prototype, 'count', {
          get: function() {
            return Object.keys(this._map).length;
          }
        });

        return Headers;
      })();
    }

    // ============================================================
    // Response polyfill
    // ============================================================
    if (typeof globalThis.Response === 'undefined') {
      globalThis.Response = (function() {
        function Response(body, init) {
          init = init || {};
          this._body = body !== undefined && body !== null ? String(body) : '';
          this.status = init.status !== undefined ? init.status : 200;
          this.statusText = init.statusText || '';
          this.ok = this.status >= 200 && this.status < 300;

          if (init.headers instanceof Headers) {
            this.headers = init.headers;
          } else {
            this.headers = new Headers(init.headers);
          }

          this._bodyUsed = false;
        }

        Object.defineProperty(Response.prototype, 'bodyUsed', {
          get: function() { return this._bodyUsed; }
        });

        Response.prototype.text = function() {
          this._bodyUsed = true;
          var body = this._body;
          return { then: function(resolve) { resolve(body); return this; }, catch: function() { return this; } };
        };

        Response.prototype.json = function() {
          this._bodyUsed = true;
          var body = this._body;
          try {
            var parsed = JSON.parse(body);
            return { then: function(resolve) { resolve(parsed); return this; }, catch: function() { return this; } };
          } catch(e) {
            return { then: function() { return this; }, catch: function(reject) { reject(e); return this; } };
          }
        };

        Response.prototype.arrayBuffer = function() {
          this._bodyUsed = true;
          return { then: function(resolve) { resolve(new ArrayBuffer(0)); return this; }, catch: function() { return this; } };
        };

        Response.prototype.clone = function() {
          return new Response(this._body, {
            status: this.status,
            statusText: this.statusText,
            headers: new Headers(this.headers.toJSON())
          });
        };

        Response.json = function(data, init) {
          init = init || {};
          var headers = new Headers(init.headers);
          if (!headers.has('content-type')) {
            headers.set('content-type', 'application/json');
          }
          return new Response(JSON.stringify(data), {
            status: init.status !== undefined ? init.status : 200,
            statusText: init.statusText || '',
            headers: headers
          });
        };

        Response.redirect = function(url, status) {
          status = status || 302;
          return new Response('', {
            status: status,
            headers: { 'Location': url }
          });
        };

        return Response;
      })();
    }

    // ============================================================
    // Request polyfill
    // ============================================================
    if (typeof globalThis.Request === 'undefined') {
      globalThis.Request = (function() {
        function Request(input, init) {
          init = init || {};
          if (typeof input === 'string') {
            this.url = input;
          } else if (input && input.url) {
            this.url = input.url;
            if (!init.method && input.method) init.method = input.method;
            if (!init.headers && input.headers) init.headers = input.headers;
            if (!init.body && input._body) init.body = input._body;
          } else {
            this.url = '';
          }

          this.method = (init.method || 'GET').toUpperCase();

          if (init.headers instanceof Headers) {
            this.headers = init.headers;
          } else {
            this.headers = new Headers(init.headers);
          }

          this._body = init.body !== undefined && init.body !== null ? String(init.body) : '';
          this._bodyUsed = false;
        }

        Object.defineProperty(Request.prototype, 'bodyUsed', {
          get: function() { return this._bodyUsed; }
        });

        Request.prototype.text = function() {
          this._bodyUsed = true;
          var body = this._body;
          return { then: function(resolve) { resolve(body); return this; }, catch: function() { return this; } };
        };

        Request.prototype.json = function() {
          this._bodyUsed = true;
          var body = this._body;
          try {
            var parsed = JSON.parse(body);
            return { then: function(resolve) { resolve(parsed); return this; }, catch: function() { return this; } };
          } catch(e) {
            return { then: function() { return this; }, catch: function(reject) { reject(e); return this; } };
          }
        };

        Request.prototype.arrayBuffer = function() {
          this._bodyUsed = true;
          return { then: function(resolve) { resolve(new ArrayBuffer(0)); return this; }, catch: function() { return this; } };
        };

        Request.prototype.clone = function() {
          return new Request(this.url, {
            method: this.method,
            headers: new Headers(this.headers.toJSON()),
            body: this._body
          });
        };

        return Request;
      })();
    }

    // ============================================================
    // URLSearchParams polyfill
    // ============================================================
    if (typeof globalThis.URLSearchParams === 'undefined') {
      globalThis.URLSearchParams = (function() {
        function URLSearchParams(init) {
          this._params = [];
          if (typeof init === 'string') {
            if (init.charAt(0) === '?') init = init.substring(1);
            var pairs = init.split('&');
            for (var i = 0; i < pairs.length; i++) {
              if (pairs[i] === '') continue;
              var idx = pairs[i].indexOf('=');
              if (idx === -1) {
                this._params.push([decodeURIComponent(pairs[i]), '']);
              } else {
                this._params.push([
                  decodeURIComponent(pairs[i].substring(0, idx)),
                  decodeURIComponent(pairs[i].substring(idx + 1))
                ]);
              }
            }
          } else if (Array.isArray(init)) {
            for (var i = 0; i < init.length; i++) {
              this._params.push([String(init[i][0]), String(init[i][1])]);
            }
          } else if (init && typeof init === 'object') {
            var keys = Object.keys(init);
            for (var i = 0; i < keys.length; i++) {
              this._params.push([keys[i], String(init[keys[i]])]);
            }
          }
        }

        URLSearchParams.prototype.get = function(name) {
          for (var i = 0; i < this._params.length; i++) {
            if (this._params[i][0] === name) return this._params[i][1];
          }
          return null;
        };

        URLSearchParams.prototype.set = function(name, value) {
          var found = false;
          var newParams = [];
          for (var i = 0; i < this._params.length; i++) {
            if (this._params[i][0] === name) {
              if (!found) {
                newParams.push([name, String(value)]);
                found = true;
              }
            } else {
              newParams.push(this._params[i]);
            }
          }
          if (!found) newParams.push([name, String(value)]);
          this._params = newParams;
        };

        URLSearchParams.prototype.has = function(name) {
          for (var i = 0; i < this._params.length; i++) {
            if (this._params[i][0] === name) return true;
          }
          return false;
        };

        URLSearchParams.prototype.delete = function(name) {
          var newParams = [];
          for (var i = 0; i < this._params.length; i++) {
            if (this._params[i][0] !== name) newParams.push(this._params[i]);
          }
          this._params = newParams;
        };

        URLSearchParams.prototype.append = function(name, value) {
          this._params.push([String(name), String(value)]);
        };

        URLSearchParams.prototype.toString = function() {
          return this._params.map(function(p) {
            return encodeURIComponent(p[0]) + '=' + encodeURIComponent(p[1]);
          }).join('&');
        };

        URLSearchParams.prototype.entries = function() {
          return this._params.slice();
        };

        URLSearchParams.prototype.keys = function() {
          return this._params.map(function(p) { return p[0]; });
        };

        URLSearchParams.prototype.values = function() {
          return this._params.map(function(p) { return p[1]; });
        };

        URLSearchParams.prototype.forEach = function(callback, thisArg) {
          for (var i = 0; i < this._params.length; i++) {
            callback.call(thisArg, this._params[i][1], this._params[i][0], this);
          }
        };

        return URLSearchParams;
      })();
    }

    // ============================================================
    // URL polyfill (minimal — JSC does not always expose URL)
    // ============================================================
    if (typeof globalThis.URL === 'undefined') {
      globalThis.URL = (function() {
        function parseURL(str) {
          // Split protocol
          var rest = str;
          var protocol = '';
          var pi = rest.indexOf('://');
          if (pi !== -1) {
            protocol = rest.substring(0, pi);
            rest = rest.substring(pi + 3);
          }
          // Split hash
          var hash = '';
          var hi = rest.indexOf('#');
          if (hi !== -1) {
            hash = rest.substring(hi);
            rest = rest.substring(0, hi);
          }
          // Split search
          var search = '';
          var qi = rest.indexOf('?');
          if (qi !== -1) {
            search = rest.substring(qi);
            rest = rest.substring(0, qi);
          }
          // Split host and pathname
          var host = '';
          var pathname = '/';
          var si = rest.indexOf('/');
          if (si !== -1) {
            host = rest.substring(0, si);
            pathname = rest.substring(si);
          } else {
            host = rest;
          }
          return { protocol: protocol, host: host, pathname: pathname, search: search, hash: hash };
        }

        function URL(url, base) {
          if (base !== undefined && url.indexOf('://') === -1) {
            // Resolve relative URLs minimally
            var bp = parseURL(base);
            if (url.charAt(0) === '/') {
              url = bp.protocol + '://' + bp.host + url;
            } else {
              var basePath = bp.pathname;
              var idx = basePath.lastIndexOf('/');
              basePath = basePath.substring(0, idx + 1);
              url = bp.protocol + '://' + bp.host + basePath + url;
            }
          }

          var p = parseURL(url);
          this.protocol = p.protocol ? p.protocol + ':' : '';
          this.host = p.host;
          var portIdx = p.host.lastIndexOf(':');
          if (portIdx !== -1 && (p.host.indexOf(']') === -1 || portIdx > p.host.lastIndexOf(']'))) {
            this.hostname = p.host.substring(0, portIdx);
            this.port = p.host.substring(portIdx + 1);
          } else {
            this.hostname = p.host;
            this.port = '';
          }
          this.pathname = p.pathname || '/';
          this.search = p.search;
          this.hash = p.hash;
          this.origin = this.protocol + '//' + this.host;
          this.href = url;
          this.searchParams = new URLSearchParams(this.search);
        }

        URL.prototype.toString = function() {
          return this.href;
        };

        URL.prototype.toJSON = function() {
          return this.href;
        };

        return URL;
      })();
    }
    """
}
