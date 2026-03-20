import Foundation
import JavaScriptCore

/// Provides `Bun.file()`, `Bun.write()`, `Bun.env`, `Bun.sleep()`, and
/// `Bun.serve()` shims so that Bun-compatible JS can run inside TanoJSC.
public final class TanoBunAPI {

    private let config: TanoConfig
    private let jscPerform: (@escaping () -> Void) -> Void
    var httpServer: TanoHTTPServer?  // will be set in Task 7

    public init(config: TanoConfig, jscPerform: @escaping (@escaping () -> Void) -> Void) {
        self.config = config
        self.jscPerform = jscPerform
    }

    // MARK: - Injection

    public func inject(into context: JSContext) {
        let bun = JSValue(newObjectIn: context)!

        // Pre-create synchronous thenable helpers stored on globalThis to prevent
        // GC from collecting them. Matching the pattern used by the Response/Request
        // polyfills so that .then() resolves immediately (JSC native Promises require
        // microtask flushing which doesn't happen synchronously in native callbacks).
        context.evaluateScript("""
            globalThis.__tanoResolve = function(v) {
                return {
                    then: function(resolve) { if (resolve) resolve(v); return this; },
                    catch: function() { return this; }
                };
            };
            globalThis.__tanoReject = function(e) {
                return {
                    then: function(_, reject) { if (reject) reject(e); return this; },
                    catch: function(reject) { if (reject) reject(e); return this; }
                };
            };
        """)
        let promiseResolverFn = context.evaluateScript("__tanoResolve")!
        let promiseRejecterFn = context.evaluateScript("__tanoReject")!

        // Bun.version
        bun.setObject("1.0.0-tano" as NSString, forKeyedSubscript: "version" as NSString)

        // Bun.main
        bun.setObject(config.serverEntry as NSString, forKeyedSubscript: "main" as NSString)

        // Bun.env — merge config.env with ProcessInfo environment
        let envObj = JSValue(newObjectIn: context)!
        var merged = ProcessInfo.processInfo.environment
        for (key, value) in config.env {
            merged[key] = value
        }
        for (key, value) in merged {
            envObj.setObject(value as NSString, forKeyedSubscript: key as NSString)
        }
        bun.setObject(envObj, forKeyedSubscript: "env" as NSString)

        // Bun.file(path) — returns a BunFile-like object
        let jscPerform = self.jscPerform
        let fileBlock: @convention(block) (JSValue) -> JSValue = { pathVal in
            guard let ctx = JSContext.current() else {
                return JSValue(undefinedIn: JSContext.current())
            }
            let filePath = pathVal.toString() ?? ""
            return TanoBunAPI.createBunFile(path: filePath, context: ctx, jscPerform: jscPerform, resolve: promiseResolverFn, reject: promiseRejecterFn)
        }
        bun.setObject(fileBlock, forKeyedSubscript: "file" as NSString)

        // Bun.write(path, data) — returns a thenable Promise<number>
        let writeWrapperBlock: @convention(block) (JSValue, JSValue) -> JSValue = { pathVal, dataVal in
            let filePath = pathVal.toString() ?? ""
            let data = dataVal.toString() ?? ""

            let dir = (filePath as NSString).deletingLastPathComponent
            if !dir.isEmpty {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }

            let bytes = Data(data.utf8)
            do {
                try bytes.write(to: URL(fileURLWithPath: filePath))
            } catch {
                return promiseRejecterFn.call(withArguments: [JSValue(object: error.localizedDescription, in: context)!])!
            }

            return promiseResolverFn.call(withArguments: [JSValue(int32: Int32(bytes.count), in: context)!])!
        }
        bun.setObject(writeWrapperBlock, forKeyedSubscript: "write" as NSString)

        // Bun.sleep(ms) — returns Promise that resolves after ms milliseconds
        let sleepBlock: @convention(block) (JSValue) -> JSValue = { msVal in
            let ms = msVal.toInt32()
            return TanoBunAPI.bunSleep(ms: ms, context: context, jscPerform: jscPerform)
        }
        bun.setObject(sleepBlock, forKeyedSubscript: "sleep" as NSString)

        // Bun.serve() — will be wired in Task 7
        let serveSelf = self
        let serveBlock: @convention(block) (JSValue) -> JSValue = { options in
            guard let ctx = JSContext.current() else {
                return JSValue(undefinedIn: JSContext.current())
            }
            return serveSelf.startServe(options: options, context: ctx)
        }
        bun.setObject(serveBlock, forKeyedSubscript: "serve" as NSString)

        context.setObject(bun, forKeyedSubscript: "Bun" as NSString)
    }

    // MARK: - Bun.file()

    private static func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "json":            return "application/json"
        case "js", "mjs":      return "application/javascript"
        case "html", "htm":    return "text/html"
        case "css":            return "text/css"
        case "txt":            return "text/plain"
        case "png":            return "image/png"
        case "jpg", "jpeg":    return "image/jpeg"
        case "gif":            return "image/gif"
        case "svg":            return "image/svg+xml"
        case "pdf":            return "application/pdf"
        default:               return "application/octet-stream"
        }
    }

    private static func createBunFile(path: String, context: JSContext, jscPerform: @escaping (@escaping () -> Void) -> Void, resolve: JSValue, reject: JSValue) -> JSValue {
        let fileObj = JSValue(newObjectIn: context)!

        // name
        fileObj.setObject(path as NSString, forKeyedSubscript: "name" as NSString)

        // type (MIME)
        let mime = mimeType(for: path)
        fileObj.setObject(mime as NSString, forKeyedSubscript: "type" as NSString)

        // size
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int {
            fileObj.setObject(size, forKeyedSubscript: "size" as NSString)
        } else {
            fileObj.setObject(0, forKeyedSubscript: "size" as NSString)
        }

        // exists() → Promise<bool>
        let existsBlock: @convention(block) () -> JSValue = {
            let exists = fm.fileExists(atPath: path)
            let jsVal = JSValue(bool: exists, in: context)!
            return resolve.call(withArguments: [jsVal])!
        }
        fileObj.setObject(existsBlock, forKeyedSubscript: "exists" as NSString)

        // text() → Promise<string>
        let textBlock: @convention(block) () -> JSValue = {
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                let jsString = JSValue(object: content, in: context)!
                return resolve.call(withArguments: [jsString])!
            } catch {
                let errMsg = JSValue(object: error.localizedDescription, in: context)!
                return reject.call(withArguments: [errMsg])!
            }
        }
        fileObj.setObject(textBlock, forKeyedSubscript: "text" as NSString)

        // json() → Promise<any>
        let jsonParseFn = context.evaluateScript("JSON.parse")!
        let jsonBlock: @convention(block) () -> JSValue = {
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                let jsString = JSValue(object: content, in: context)!
                let parsed = jsonParseFn.call(withArguments: [jsString])!
                return resolve.call(withArguments: [parsed])!
            } catch {
                let errMsg = JSValue(object: error.localizedDescription, in: context)!
                return reject.call(withArguments: [errMsg])!
            }
        }
        fileObj.setObject(jsonBlock, forKeyedSubscript: "json" as NSString)

        return fileObj
    }

    // MARK: - Bun.sleep()

    private static func bunSleep(ms: Int32, context: JSContext, jscPerform: @escaping (@escaping () -> Void) -> Void) -> JSValue {
        // Use JS-level setTimeout to implement sleep as a proper promise
        let result = context.evaluateScript("""
            (function(ms) {
                return new Promise(function(resolve) {
                    setTimeout(resolve, ms);
                });
            })
        """)!
        return result.call(withArguments: [NSNumber(value: ms)])!
    }

    // MARK: - Bun.serve()

    func startServe(options: JSValue, context: JSContext) -> JSValue {
        let port = options.forProperty("port")?.toUInt32() ?? 3000
        let hostname = options.forProperty("hostname")?.toString() ?? "127.0.0.1"
        let fetchFn = options.forProperty("fetch")

        let server = TanoHTTPServer()
        self.httpServer = server

        let jscPerform = self.jscPerform

        // Store a managed reference to fetchFn so it survives GC
        let managedFetch = JSManagedValue(value: fetchFn)
        if let managedFetch = managedFetch {
            context.virtualMachine.addManagedReference(managedFetch, withOwner: self)
        }

        server.fetchHandler = { method, url, headers, body, respond in
            jscPerform {
                guard let fetchCallback = managedFetch?.value,
                      !fetchCallback.isUndefined else {
                    respond(500, [("content-type", "text/plain")], "No fetch handler")
                    return
                }

                // Build a Request object in JS
                let headersObj = context.evaluateScript("(new Headers())")!
                for (name, value) in headers {
                    headersObj.invokeMethod("set", withArguments: [name, value])
                }

                let reqInit = JSValue(newObjectIn: context)!
                reqInit.setObject(method as NSString, forKeyedSubscript: "method" as NSString)
                reqInit.setObject(headersObj, forKeyedSubscript: "headers" as NSString)
                if method != "GET" && method != "HEAD" && !body.isEmpty {
                    reqInit.setObject(body as NSString, forKeyedSubscript: "body" as NSString)
                }

                let requestConstructor = context.evaluateScript("Request")!
                let request = requestConstructor.construct(withArguments: [url, reqInit])!

                let response = fetchCallback.call(withArguments: [request])

                // Extract response fields
                guard let response = response, !response.isUndefined, !response.isNull else {
                    respond(500, [("content-type", "text/plain")], "Handler returned null")
                    return
                }

                // Handle both sync Response and Promise (with .then)
                let thenProp = response.forProperty("then")
                if let thenProp = thenProp, !thenProp.isUndefined, thenProp.forProperty("length")?.toInt32() ?? 0 > 0 {
                    // It's a thenable/promise — wait for resolution
                    let thenBlock: @convention(block) (JSValue) -> Void = { resolvedResponse in
                        let (status, respHeaders, respBody) = TanoBunAPI.extractResponse(from: resolvedResponse, context: context)
                        respond(status, respHeaders, respBody)
                    }
                    let catchBlock: @convention(block) (JSValue) -> Void = { error in
                        let msg = error.toString() ?? "Unknown error"
                        respond(500, [("content-type", "text/plain")], msg)
                    }
                    let thenResult = response.invokeMethod("then", withArguments: [unsafeBitCast(thenBlock, to: AnyObject.self)])
                    thenResult?.invokeMethod("catch", withArguments: [unsafeBitCast(catchBlock, to: AnyObject.self)])
                } else {
                    // Synchronous Response object
                    let (status, respHeaders, respBody) = TanoBunAPI.extractResponse(from: response, context: context)
                    respond(status, respHeaders, respBody)
                }
            }
        }

        // Start server synchronously — use a semaphore to wait for ready
        let semaphore = DispatchSemaphore(value: 0)
        var actualPort: UInt16 = 0

        DispatchQueue.global().async {
            do {
                try server.start(port: UInt16(port), hostname: hostname) { p in
                    actualPort = p
                    semaphore.signal()
                }
            } catch {
                print("[TanoBunAPI] Failed to start server: \(error)")
                semaphore.signal()
            }
        }

        semaphore.wait()

        // Return a server-like object
        let serverObj = JSValue(newObjectIn: context)!
        serverObj.setObject(NSNumber(value: actualPort), forKeyedSubscript: "port" as NSString)
        serverObj.setObject(hostname as NSString, forKeyedSubscript: "hostname" as NSString)

        let stopBlock: @convention(block) () -> Void = { [weak self] in
            self?.httpServer?.stop()
        }
        serverObj.setObject(stopBlock, forKeyedSubscript: "stop" as NSString)

        return serverObj
    }

    // MARK: - Response extraction helper

    static func extractResponse(from response: JSValue, context: JSContext) -> (Int, [(String, String)], String) {
        let status = response.forProperty("status")?.toInt32() ?? 200

        var respHeaders: [(String, String)] = []
        if let headersVal = response.forProperty("headers") {
            let entriesFn = headersVal.forProperty("entries")
            if let entriesFn = entriesFn, !entriesFn.isUndefined {
                let entries = headersVal.invokeMethod("entries", withArguments: [])
                if let entries = entries, entries.isArray {
                    let len = entries.forProperty("length")?.toInt32() ?? 0
                    for i in 0..<len {
                        if let entry = entries.atIndex(Int(i)),
                           let name = entry.atIndex(0)?.toString(),
                           let value = entry.atIndex(1)?.toString() {
                            respHeaders.append((name, value))
                        }
                    }
                }
            }
        }

        let respBody = response.forProperty("_body")?.toString() ?? ""
        return (Int(status), respHeaders, respBody)
    }
}
