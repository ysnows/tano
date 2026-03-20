import Foundation
import JavaScriptCore

/// Bridges the Web-standard `fetch()` API to `URLSession` on the native side.
///
/// Architecture:
/// 1. A native `_nativeFetch(url, method, headersJSON, body, callback)` is
///    registered on the JSContext.
/// 2. The native function creates a `URLRequest` and fires a
///    `URLSession.shared.dataTask`.
/// 3. The URLSession completion handler runs on a background queue; it uses
///    `jscPerform` to call the JS callback back on the JSC thread.
/// 4. A JS polyfill wraps `_nativeFetch` into the standard `fetch()` → Promise API.
enum TanoFetch {

    static func inject(into context: JSContext, jscPerform: @escaping (@escaping () -> Void) -> Void) {

        // 1. Register the native bridge function
        let nativeFetch: @convention(block) (JSValue, JSValue, JSValue, JSValue, JSValue) -> Void = {
            urlVal, methodVal, headersJSONVal, bodyVal, callbackVal in

            guard let ctx = JSContext.current() else { return }

            let urlString = urlVal.toString() ?? ""
            let method = methodVal.toString() ?? "GET"
            let headersJSON = headersJSONVal.isUndefined || headersJSONVal.isNull ? nil : headersJSONVal.toString()
            let bodyString = bodyVal.isUndefined || bodyVal.isNull ? nil : bodyVal.toString()

            // Prevent GC of the callback while the async operation is in flight
            let managed = JSManagedValue(value: callbackVal)!
            ctx.virtualMachine.addManagedReference(managed, withOwner: TanoFetch.self as AnyObject)

            guard let url = URL(string: urlString) else {
                jscPerform {
                    guard let cb = managed.value, !cb.isUndefined else { return }
                    cb.call(withArguments: ["Invalid URL: \(urlString)", NSNull()])
                    ctx.virtualMachine.removeManagedReference(managed, withOwner: TanoFetch.self as AnyObject)
                }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = method

            // Parse headers JSON
            if let headersJSON = headersJSON,
               let data = headersJSON.data(using: .utf8),
               let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            // Set body
            if let bodyString = bodyString {
                request.httpBody = bodyString.data(using: .utf8)
            }

            // Fire the request
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                jscPerform {
                    defer {
                        ctx.virtualMachine.removeManagedReference(managed, withOwner: TanoFetch.self as AnyObject)
                    }
                    guard let cb = managed.value, !cb.isUndefined else { return }

                    if let error = error {
                        cb.call(withArguments: [error.localizedDescription, NSNull()])
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        cb.call(withArguments: ["No HTTP response", NSNull()])
                        return
                    }

                    let bodyStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

                    // Build headers as JSON object
                    var responseHeaders: [String: String] = [:]
                    for (key, value) in httpResponse.allHeaderFields {
                        responseHeaders[String(describing: key)] = String(describing: value)
                    }
                    let headersJSONStr = (try? JSONSerialization.data(
                        withJSONObject: responseHeaders
                    )).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

                    // Build result object
                    let result = JSValue(newObjectIn: ctx)!
                    result.setObject(NSNumber(value: httpResponse.statusCode), forKeyedSubscript: "status" as NSString)
                    result.setObject(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode) as NSString,
                                     forKeyedSubscript: "statusText" as NSString)
                    result.setObject(headersJSONStr as NSString, forKeyedSubscript: "headers" as NSString)

                    // Use JSValue(object:) for body to avoid template literal issues
                    let jsBody = JSValue(object: bodyStr, in: ctx)!
                    result.setObject(jsBody, forKeyedSubscript: "body" as NSString)

                    cb.call(withArguments: [NSNull(), result])
                }
            }
            task.resume()
        }

        context.setObject(nativeFetch, forKeyedSubscript: "_nativeFetch" as NSString)

        // 2. JS polyfill that wraps _nativeFetch into standard fetch() → Promise
        context.evaluateScript("""
        if (typeof globalThis.fetch === 'undefined') {
          globalThis.fetch = function fetch(input, init) {
            return new Promise(function(resolve, reject) {
              var url, method, headers, body;

              if (typeof input === 'string') {
                url = input;
              } else if (input && input.url) {
                url = input.url;
                if (!init) init = {};
                if (!init.method && input.method) init.method = input.method;
                if (!init.headers && input.headers) init.headers = input.headers;
                if (!init.body && input._body) init.body = input._body;
              } else {
                url = String(input);
              }

              init = init || {};
              method = (init.method || 'GET').toUpperCase();

              // Flatten headers to plain object
              var headerObj = {};
              if (init.headers) {
                if (init.headers instanceof Headers) {
                  init.headers.forEach(function(value, key) {
                    headerObj[key] = value;
                  });
                } else if (typeof init.headers === 'object') {
                  var keys = Object.keys(init.headers);
                  for (var i = 0; i < keys.length; i++) {
                    headerObj[keys[i]] = init.headers[keys[i]];
                  }
                }
              }

              body = init.body !== undefined ? init.body : null;

              _nativeFetch(
                url,
                method,
                JSON.stringify(headerObj),
                body,
                function(err, result) {
                  if (err) {
                    reject(new Error(String(err)));
                    return;
                  }

                  // Parse response headers
                  var respHeaders = {};
                  try { respHeaders = JSON.parse(result.headers); } catch(e) {}

                  var response = new Response(result.body, {
                    status: result.status,
                    statusText: result.statusText,
                    headers: respHeaders
                  });

                  resolve(response);
                }
              );
            });
          };
        }
        """)
    }
}
