/**
 * TalkieSDK - Client SDK for Talkie Extensions Platform
 *
 * Connect to Talkie's core services: transcription, LLM, diff, and storage.
 *
 * Protocol v2 (current):
 *   - transcribe:start, transcribe:stop, transcribe:result
 *   - llm:complete, llm:revise, llm:result, llm:revision
 *   - diff:compute, diff:result
 *   - storage:clipboard:*, storage:memo:*
 *
 * Protocol v1 (legacy, still supported):
 *   - draft:* messages for backward compatibility
 *
 * @version 2.0.0
 */
class TalkieSDK {
  static VERSION = '2.0'

  constructor(options = {}) {
    this.port = options.port || 7847
    this.host = options.host || 'localhost'
    this.autoReconnect = options.autoReconnect !== false
    this.reconnectInterval = options.reconnectInterval || 2000
    this.name = options.name || 'Talkie Extension'
    this.capabilities = options.capabilities || ['transcribe', 'llm', 'diff']
    this.token = options.token || null

    this.ws = null
    this.listeners = {}
    this.reconnectTimer = null
    this.connected = false
    this.authenticated = false
    this.grantedCapabilities = []
    this.serverVersion = null

    // Request tracking for async responses
    this.pendingRequests = new Map()
    this.requestId = 0

    if (options.autoConnect !== false) {
      this.connect()
    }
  }

  // MARK: - Connection

  connect() {
    const url = `ws://${this.host}:${this.port}`

    try {
      this.ws = new WebSocket(url)

      this.ws.onopen = () => {
        this.connected = true
        this.authenticated = false
        this.clearReconnectTimer()
        this.emit('connected')
      }

      this.ws.onclose = () => {
        this.connected = false
        this.authenticated = false
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
          console.error('TalkieSDK: Failed to parse message', e)
        }
      }
    } catch (e) {
      console.error('TalkieSDK: Connection failed', e)
      if (this.autoReconnect) {
        this.scheduleReconnect()
      }
    }
  }

  disconnect() {
    this.autoReconnect = false
    this.clearReconnectTimer()
    if (this.ws) {
      this.ws.close()
    }
  }

  // MARK: - Message Handling

  handleMessage(message) {
    switch (message.type) {
      // Auth flow
      case 'auth:required':
        this.serverVersion = message.version
        this.handleAuthRequired(message)
        break

      case 'ext:connected':
        this.authenticated = true
        this.grantedCapabilities = message.granted || []
        this.emit('authenticated', { capabilities: this.grantedCapabilities })
        break

      // Transcription
      case 'transcribe:started':
        this.emit('transcribe:started')
        break

      case 'transcribe:result':
        this.emit('transcribe:result', { text: message.text })
        this.resolveRequest('transcribe', { text: message.text })
        break

      // LLM
      case 'llm:result':
        this.emit('llm:result', {
          content: message.content,
          provider: message.provider,
          model: message.model
        })
        this.resolveRequest('llm', message)
        break

      case 'llm:revision':
        this.emit('llm:revision', {
          before: message.before,
          after: message.after,
          diff: message.diff,
          instruction: message.instruction,
          provider: message.provider,
          model: message.model
        })
        this.resolveRequest('llm:revise', message)
        break

      case 'llm:chunk':
        this.emit('llm:chunk', {
          content: message.content,
          done: message.done
        })
        break

      // Diff
      case 'diff:result':
        this.emit('diff:result', { operations: message.operations })
        this.resolveRequest('diff', { operations: message.operations })
        break

      // Storage
      case 'storage:clipboard:content':
        this.emit('storage:clipboard:content', { content: message.content })
        this.resolveRequest('clipboard:read', { content: message.content })
        break

      case 'storage:memo:saved':
        this.emit('storage:memo:saved', { id: message.id })
        this.resolveRequest('memo:save', { id: message.id })
        break

      // Legacy v1 messages (for backward compatibility)
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

      case 'draft:transcription':
        this.emit('transcription', {
          text: message.text,
          append: message.append
        })
        break

      // Errors
      case 'error':
      case 'draft:error':
        const error = new Error(message.error)
        error.code = message.code
        this.emit('error', error)
        this.rejectAllRequests(error)
        break

      default:
        console.warn('TalkieSDK: Unknown message type', message.type)
    }
  }

  handleAuthRequired(message) {
    if (!this.token) {
      console.error('TalkieSDK: No auth token provided. Get token from Talkie app.')
      this.emit('error', new Error('Authentication required but no token provided'))
      return
    }

    this.send({
      type: 'ext:connect',
      name: this.name,
      capabilities: this.capabilities,
      token: this.token,
      version: TalkieSDK.VERSION
    })
  }

  // MARK: - Transcription API

  /**
   * Start voice capture
   * @returns {Promise} Resolves when capture starts
   */
  startTranscription() {
    this.send({ type: 'transcribe:start' })
    return this.createRequest('transcribe:start')
  }

  /**
   * Stop voice capture and get transcription
   * @returns {Promise<{text: string}>} Transcribed text
   */
  stopTranscription() {
    this.send({ type: 'transcribe:stop' })
    return this.createRequest('transcribe')
  }

  // MARK: - LLM API

  /**
   * Send messages to LLM for completion
   * @param {Array<{role: string, content: string}>} messages - Chat messages
   * @param {Object} options - { provider?, model?, stream? }
   * @returns {Promise<{content: string, provider: string, model: string}>}
   */
  complete(messages, options = {}) {
    this.send({
      type: 'llm:complete',
      messages,
      provider: options.provider,
      model: options.model,
      stream: options.stream
    })
    return this.createRequest('llm')
  }

  /**
   * Revise content with instruction
   * @param {string} content - Text to revise
   * @param {string} instruction - What to do
   * @param {Object} options - { maxLength?, style?, format?, provider?, model? }
   * @returns {Promise<{before: string, after: string, diff: Array, provider: string, model: string}>}
   */
  revise(content, instruction, options = {}) {
    this.send({
      type: 'llm:revise',
      content,
      instruction,
      constraints: {
        maxLength: options.maxLength,
        style: options.style,
        format: options.format
      },
      provider: options.provider,
      model: options.model
    })
    return this.createRequest('llm:revise')
  }

  // MARK: - Diff API

  /**
   * Compute diff between two texts
   * @param {string} before - Original text
   * @param {string} after - Modified text
   * @returns {Promise<{operations: Array}>}
   */
  computeDiff(before, after) {
    this.send({
      type: 'diff:compute',
      before,
      after
    })
    return this.createRequest('diff')
  }

  // MARK: - Storage API

  /**
   * Write to clipboard
   * @param {string} content - Text to copy
   */
  writeClipboard(content) {
    this.send({
      type: 'storage:clipboard:write',
      content
    })
  }

  /**
   * Read from clipboard
   * @returns {Promise<{content: string}>}
   */
  readClipboard() {
    this.send({ type: 'storage:clipboard:read' })
    return this.createRequest('clipboard:read')
  }

  /**
   * Save content as memo
   * @param {string} content - Memo content
   * @param {string} title - Optional title
   * @returns {Promise<{id: string}>}
   */
  saveMemo(content, title) {
    this.send({
      type: 'storage:memo:save',
      content,
      title
    })
    return this.createRequest('memo:save')
  }

  // MARK: - Legacy v1 API (backward compatibility)

  /**
   * Update draft content (v1)
   * @deprecated Use revise() instead
   */
  update(content) {
    this.send({ type: 'draft:update', content })
  }

  /**
   * Request LLM revision with constraints (v1)
   * @deprecated Use revise() instead
   */
  refine(instruction, constraints = null) {
    const message = { type: 'draft:refine', instruction }
    if (constraints) {
      message.constraints = constraints
    }
    this.send(message)
  }

  /**
   * Accept current revision (v1)
   * @deprecated
   */
  accept() {
    this.send({ type: 'draft:accept' })
  }

  /**
   * Reject current revision (v1)
   * @deprecated
   */
  reject() {
    this.send({ type: 'draft:reject' })
  }

  /**
   * Save draft (v1)
   * @deprecated Use writeClipboard() or saveMemo() instead
   */
  save(destination) {
    this.send({ type: 'draft:save', destination })
  }

  /**
   * Start voice capture (v1)
   * @deprecated Use startTranscription() instead
   */
  startCapture() {
    this.send({ type: 'draft:capture', action: 'start' })
  }

  /**
   * Stop voice capture (v1)
   * @deprecated Use stopTranscription() instead
   */
  stopCapture() {
    this.send({ type: 'draft:capture', action: 'stop' })
  }

  // MARK: - Event System

  on(event, callback) {
    if (!this.listeners[event]) {
      this.listeners[event] = []
    }
    this.listeners[event].push(callback)
    return this
  }

  off(event, callback) {
    if (this.listeners[event]) {
      this.listeners[event] = this.listeners[event].filter(cb => cb !== callback)
    }
    return this
  }

  emit(event, data) {
    if (this.listeners[event]) {
      this.listeners[event].forEach(cb => cb(data))
    }
  }

  // MARK: - Request Tracking

  createRequest(type, timeout = 30000) {
    return new Promise((resolve, reject) => {
      const id = ++this.requestId
      const timer = setTimeout(() => {
        this.pendingRequests.delete(type)
        reject(new Error(`Request timeout: ${type}`))
      }, timeout)

      this.pendingRequests.set(type, { resolve, reject, timer })
    })
  }

  resolveRequest(type, data) {
    const request = this.pendingRequests.get(type)
    if (request) {
      clearTimeout(request.timer)
      this.pendingRequests.delete(type)
      request.resolve(data)
    }
  }

  rejectAllRequests(error) {
    for (const [type, request] of this.pendingRequests) {
      clearTimeout(request.timer)
      request.reject(error)
    }
    this.pendingRequests.clear()
  }

  // MARK: - Utilities

  send(message) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message))
    }
  }

  scheduleReconnect() {
    this.clearReconnectTimer()
    this.reconnectTimer = setTimeout(() => {
      console.log('TalkieSDK: Attempting to reconnect...')
      this.connect()
    }, this.reconnectInterval)
  }

  clearReconnectTimer() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
  }

  isConnected() {
    return this.connected && this.authenticated
  }

  hasCapability(capability) {
    return this.grantedCapabilities.includes(capability)
  }
}

// Keep TalkieLink as alias for backward compatibility
const TalkieLink = TalkieSDK

// Export for different module systems
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { TalkieSDK, TalkieLink }
}
if (typeof window !== 'undefined') {
  window.TalkieSDK = TalkieSDK
  window.TalkieLink = TalkieLink  // Backward compatibility
}
