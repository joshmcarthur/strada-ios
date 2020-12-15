(() => {
  // This represents the adapter that is installed on the webBridge
  // All adapters implement the same interface so the web doesn't need to
  // know anything specific about the client platform
  class NativeBridge {
    constructor() {
      this.supportedComponents = []
      document.addEventListener("web-bridge:ready", () => window.webBridge.setAdapter(this))
    }

    register(component) {
      if (Array.isArray(component)) {
        this.supportedComponents = this.supportedComponents.concat(component)
      } else {
        this.supportedComponents.push(component)
      }

      this.notifyBridgeOfSupportedComponentsUpdate()
    }

    unregister(component) {
      const index = this.supportedComponents.indexOf(component)
      if (index != -1) {
        this.supportedComponents.splice(index, 1)
        this.notifyBridgeOfSupportedComponentsUpdate()
      }
    }

    notifyBridgeOfSupportedComponentsUpdate() {
      if (window.webBridge) {
        window.webBridge.adapterDidUpdateSupportedComponents()
      }
    }

    supportsComponent(component) {
      return this.supportedComponents.includes(component)
    }

    // Send message to web
    send(message) {
      if (window.webBridge) {
        window.webBridge.receive(message)
      }
    }

    // Receive from web
    receive(message) {
      this.postMessage(message)
    }

    get platform() {
      return "ios"
    }

    // Native handler

    postMessage(message) {
      webkit.messageHandlers.strata.postMessage(message)
    }
  }

  window.nativeBridge = new NativeBridge()
  window.nativeBridge.postMessage("ready")
})()