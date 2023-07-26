import Foundation
import WebKit

public protocol BridgeDelegate: AnyObject {
    func bridgeDidInitialize()
    func bridgeDidReceiveMessage(_ message: Message)
}

public enum BridgeError: Error {
    case missingWebView
}

/// `Bridge` is the object for configuring a web view and
/// the channel for sending/receiving messages
public final class Bridge {
    public typealias CompletionHandler = (_ result: Any?, _ error: Error?) -> Void
    
    public var webView: WKWebView? {
        didSet {
            guard webView != oldValue else { return }
            loadIntoWebView()
        }
    }
    
    public weak var delegate: BridgeDelegate?

    /// This needs to match whatever the JavaScript file uses
    private let bridgeGlobal = "window.nativeBridge"
    
    /// The webkit.messageHandlers name
    private let scriptHandlerName = "strada"
    
    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: scriptHandlerName)
    }
    
    /// Create a new Bridge object for calling methods on this web view with a delegate
    /// for receiving messages
    public init(webView: WKWebView? = nil, delegate: BridgeDelegate? = nil) {
        self.webView = webView
        self.delegate = delegate
        loadIntoWebView()
    }

    // MARK: - API
    
    /// Register a single component
    /// - Parameter component: Name of a component to register support for
    public func register(component: String) {
        callBridgeFunction("register", arguments: [component])
    }
    
    /// Register multiple components
    /// - Parameter components: Array of component names to register
    public func register(components: [String]) {
        callBridgeFunction("register", arguments: [components])
    }
    
    /// Unregister support for a single component
    /// - Parameter component: Component name
    public func unregister(component: String) {
        callBridgeFunction("unregister", arguments: [component])
    }
    
    /// Send a message through the bridge to the web application
    /// - Parameter message: Message to send
    public func send(_ message: Message) {
        let internalMessage = InternalMessage(from: message)
        callBridgeFunction("send", arguments: [internalMessage.toJSON()])
    }
    
//    /// Convenience method to reply to a previously received message. Data will be replaced,
//    /// while id, component, and event will remain the same
//    /// - Parameter message: Message to reply to
//    /// - Parameter data: Data to send with reply
//    public func reply(to message: Message, with data: MessageData) {
//        let replyMessage = message.replacing(data: data)
//        callBridgeFunction("send", arguments: [replyMessage.toJSON()])
//    }
    
    private func callBridgeFunction(_ function: String, arguments: [Any]) {
        let js = JavaScript(object: bridgeGlobal, functionName: function, arguments: arguments)
        evaluate(javaScript: js)
    }

    // MARK: - Configuration
    
    /// Configure the bridge in the provided web view
    private func loadIntoWebView() {
        guard let configuration = webView?.configuration else { return }

        // Install user script and message handlers in web view
        if let userScript = makeUserScript() {
            configuration.userContentController.addUserScript(userScript)
        }
        
        configuration.userContentController.add(ScriptMessageHandler(delegate: self), name: scriptHandlerName)
    }

    private func makeUserScript() -> WKUserScript? {
        guard
            let path = PathLoader().pathFor(name: "strada", fileType: "js") else {
                return nil
        }
        
        do {
            let source = try String(contentsOfFile: path)
            return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        } catch {
            assertionFailure("Could not open strada.js: \(error)")
            return nil
        }
    }

    // MARK: - JavaScript Evaluation

    /// Evaluates javaScript string directly as passed in sending through the web view
    public func evaluate(javaScript: String, completion: CompletionHandler? = nil) {
        guard let webView = webView else {
            completion?(nil, BridgeError.missingWebView)
            return
        }
        
        webView.evaluateJavaScript(javaScript) { result, error in
            if let error = error {
                debugLog("Error evaluating JavaScript: \(error)")
            }
            
            completion?(result, error)
        }
    }
    
    /// Evaluates a JavaScript function with optional arguments by encoding the arguments
    /// Function should not include the parens
    /// Usage: evaluate(function: "console.log", arguments: ["test"])
    public func evaluate(function: String, arguments: [Any] = [], completion: CompletionHandler? = nil) {
        evaluate(javaScript: JavaScript(functionName: function, arguments: arguments), completion: completion)
    }
    
    private func evaluate(javaScript: JavaScript, completion: CompletionHandler? = nil) {
        do {
            evaluate(javaScript: try javaScript.toString(), completion: completion)
        } catch {
            debugLog("Error evaluating JavaScript: \(javaScript), error: \(error)")
            completion?(nil, error)
        }
    }
}

extension Bridge: ScriptMessageHandlerDelegate {
    func scriptMessageHandlerDidReceiveMessage(_ scriptMessage: WKScriptMessage) {
        if let event = scriptMessage.body as? String, event == "ready" {
            delegate?.bridgeDidInitialize()
        } else if let message = InternalMessage(scriptMessage: scriptMessage) {
            delegate?.bridgeDidReceiveMessage(message.toMessage())
        } else {
            debugLog("Unhandled message received: \(scriptMessage.body)")
        }
    }
}
