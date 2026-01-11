/**
 * TalkieLink - Client SDK for Talkie Draft Extension API
 *
 * Connect custom renderers to Talkie's Drafts for real-time
 * voice-powered editing with LLM support.
 *
 * Usage:
 *   const talkie = new TalkieLink()
 *   talkie.on('state', draft => console.log(draft.content))
 *   talkie.refine('make it shorter', { maxLength: 280 })
 *
 * @version 1.0.0
 */
class TalkieLink {
  constructor(options = {}) {
    this.port = options.port || 7847
    this.host = options.host || 'localhost'
    this.autoReconnect = options.autoReconnect !== false
    this.reconnectInterval = options.reconnectInterval || 2000
    this.name = options.name || 'Custom Renderer'
    this.capabilities = options.capabilities || []

    this.ws = null
    this.listeners = {}
    this.reconnectTimer = null
    this.connected = false

    this.connect()
  }

  /**
   * Connect to Talkie's Draft Extension API
   */
  connect() {
    const url = `ws://${this.host}:${this.port}/draft`

    try {
      this.ws = new WebSocket(url)

      this.ws.onopen = () => {
        this.connected = true
        this.clearReconnectTimer()

        // Announce ourselves
        this.send({
          type: 'renderer:connect',
          name: this.name,
          capabilities: this.capabilities
        })

        this.emit('connected')
      }

      this.ws.onclose = () => {
        this.connected = false
        this.emit('disconnected')

        if (this.autoReconnect) {
          this.scheduleReconnect()
        }
      }

      this.ws.onerror = (error) => {
        this.emit('error', error)
      }

      this.ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data)
          this.handleMessage(message)
        } catch (e) {
          console.error('TalkieLink: Failed to parse message', e)
        }
      }
    } catch (e) {
      console.error('TalkieLink: Connection failed', e)
      if (this.autoReconnect) {
        this.scheduleReconnect()
      }
    }
  }

  /**
   * Handle incoming messages from Talkie
   */
  handleMessage(message) {
    switch (message.type) {
      case 'draft:state':
        this.emit('state', {
          content: message.content,
          mode: message.mode,
          wordCount: message.wordCount,
          charCount: message.charCount
        })
        break

      case 'draft:revision':
        this.emit('revision', {
          before: message.before,
          after: message.after,
          diff: message.diff,
          instruction: message.instruction,
          provider: message.provider,
          model: message.model
        })
        break

      case 'draft:resolved':
        this.emit('resolved', {
          accepted: message.accepted,
          content: message.content
        })
        break

      case 'draft:error':
        this.emit('error', new Error(message.error))
        break

      case 'draft:transcription':
        this.emit('transcription', {
          text: message.text,
          append: message.append
        })
        break

      default:
        console.warn('TalkieLink: Unknown message type', message.type)
    }
  }

  /**
   * Register an event listener
   * @param {string} event - Event name: 'state', 'revision', 'resolved', 'connected', 'disconnected', 'error'
   * @param {function} callback - Callback function
   */
  on(event, callback) {
    if (!this.listeners[event]) {
      this.listeners[event] = []
    }
    this.listeners[event].push(callback)
    return this // Allow chaining
  }

  /**
   * Remove an event listener
   */
  off(event, callback) {
    if (this.listeners[event]) {
      this.listeners[event] = this.listeners[event].filter(cb => cb !== callback)
    }
    return this
  }

  /**
   * Emit an event to all registered listeners
   */
  emit(event, data) {
    if (this.listeners[event]) {
      this.listeners[event].forEach(cb => cb(data))
    }
  }

  /**
   * Send a message to Talkie
   */
  send(message) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message))
    }
  }

  /**
   * Update the draft content in Talkie
   * @param {string} content - New content
   */
  update(content) {
    this.send({
      type: 'draft:update',
      content
    })
  }

  /**
   * Request an LLM revision with optional constraints
   * @param {string} instruction - What to do (e.g., "make it shorter")
   * @param {object} constraints - Optional constraints { maxLength, style, format }
   */
  refine(instruction, constraints = null) {
    const message = {
      type: 'draft:refine',
      instruction
    }
    if (constraints) {
      message.constraints = constraints
    }
    this.send(message)
  }

  /**
   * Accept the current revision
   */
  accept() {
    this.send({ type: 'draft:accept' })
  }

  /**
   * Reject the current revision
   */
  reject() {
    this.send({ type: 'draft:reject' })
  }

  /**
   * Save the draft to memo or clipboard
   * @param {string} destination - 'memo' or 'clipboard'
   */
  save(destination) {
    this.send({
      type: 'draft:save',
      destination
    })
  }

  /**
   * Copy to clipboard (convenience method)
   */
  copyToClipboard() {
    this.save('clipboard')
  }

  /**
   * Save to memo (convenience method)
   */
  saveToMemo() {
    this.save('memo')
  }

  /**
   * Start voice capture via Talkie's audio pipeline
   * Listen for 'transcription' event for results
   */
  startCapture() {
    this.send({
      type: 'draft:capture',
      action: 'start'
    })
  }

  /**
   * Stop voice capture and trigger transcription
   * Results come via 'transcription' event
   */
  stopCapture() {
    this.send({
      type: 'draft:capture',
      action: 'stop'
    })
  }

  /**
   * Disconnect from Talkie
   */
  disconnect() {
    this.autoReconnect = false
    this.clearReconnectTimer()
    if (this.ws) {
      this.ws.close()
    }
  }

  /**
   * Schedule a reconnection attempt
   */
  scheduleReconnect() {
    this.clearReconnectTimer()
    this.reconnectTimer = setTimeout(() => {
      console.log('TalkieLink: Attempting to reconnect...')
      this.connect()
    }, this.reconnectInterval)
  }

  /**
   * Clear any pending reconnection timer
   */
  clearReconnectTimer() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
  }

  /**
   * Check if connected to Talkie
   */
  isConnected() {
    return this.connected
  }
}

// Export for different module systems
if (typeof module !== 'undefined' && module.exports) {
  module.exports = TalkieLink
}
if (typeof window !== 'undefined') {
  window.TalkieLink = TalkieLink
}
