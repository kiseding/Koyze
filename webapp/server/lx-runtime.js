'use strict'

const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const { safeFetch, md5, log } = require('./util')

const EVENT_NAMES = {
  request: 'request',
  inited: 'inited',
  updateLog: 'updateLog',
  updateStatus: 'updateStatus',
  updateAlert: 'updateAlert',
}

const SOURCES_DIR = process.env.KOYZE_SOURCES_DIR ||
  path.join(__dirname, '..', 'sources')

// 用户在界面里导入的音源脚本落在这里，容器重启后仍然可用。
// 内置脚本在 sources/（镜像里），用户脚本在 data/user-sources/（挂卷）。
const USER_SOURCES_DIR = process.env.KOYZE_USER_SOURCES_DIR ||
  path.join(__dirname, '..', 'data', 'user-sources')

const HANDLER_TIMEOUT = 30000

class SourceRuntime {
  constructor() {
    // 顺序即优先级：内置在前、用户在后，后者覆盖前者的同名平台。
    this.scripts = []
    this.handlers = new Map()
    this.registry = {}
  }

  load() {
    this.scripts = []
    this.handlers.clear()
    this.registry = {}

    if (fs.existsSync(SOURCES_DIR)) {
      const files = fs.readdirSync(SOURCES_DIR)
        .filter((name) => name.toLowerCase().endsWith('.js'))
        .sort()
      for (const file of files) {
        const full = path.join(SOURCES_DIR, file)
        try {
          this.scripts.push(this._compile(file, fs.readFileSync(full, 'utf8')))
        } catch (error) {
          log('failed to load source', file, '-', error.message)
        }
      }
    } else {
      log('sources dir not found:', SOURCES_DIR)
    }

    this._loadUserSources()
    this._rebuild()
    log('loaded', this.scripts.length, 'source script(s),',
      Object.keys(this.registry).length, 'platform(s)')
    return this.summary()
  }

  /// 编译一份脚本并返回 entry（不注册）。沙箱与 LX 运行时在每次编译时新建，
  /// 脚本之间互不可见。
  _compile(file, code, extra) {
    let requestHandler = null
    let initPayload = null

    const lx = {
      EVENT_NAMES,
      env: 'node',
      version: '5.0.3',
      currentScriptInfo: { name: file, rawScript: code },
      on(event, handler) {
        if (event === EVENT_NAMES.request && typeof handler === 'function') {
          requestHandler = handler
        }
      },
      send(event, payload) {
        if (event === EVENT_NAMES.inited) initPayload = payload
      },
      request(url, options, callback) {
        const done = typeof callback === 'function' ? callback : () => {}
        const opts = options || {}
        let body = opts.body
        const headers = Object.assign({}, opts.headers)

        // Koyze / LX 引擎约定：body 传对象时由引擎按 JSON 编码。
        if (body != null && typeof body === 'object' &&
            !(body instanceof ArrayBuffer) && !ArrayBuffer.isView(body)) {
          body = JSON.stringify(body)
          if (!Object.keys(headers).some((k) => k.toLowerCase() === 'content-type')) {
            headers['Content-Type'] = 'application/json'
          }
        } else if (typeof body === 'string') {
          body = Buffer.from(body, 'utf8')
        }

        safeFetch(String(url), {
          method: String(opts.method || 'GET').toUpperCase(),
          headers,
          body,
          timeout: Number(opts.timeout) > 0 ? Number(opts.timeout) : 15000,
        })
          .then(async ({ response }) => {
            const buffer = await response.arrayBuffer()
            // 沙箱是独立 realm，直接传宿主的 ArrayBuffer 会让脚本里的
            // `body instanceof ArrayBuffer` 判定失败，响应被当成空文本。
            // LX 音源脚本统一按 UTF-8 解析 body，这里直接给字符串最稳妥。
            done(null, {
              statusCode: response.status,
              headers: Object.fromEntries(response.headers.entries()),
              body: Buffer.from(buffer).toString('utf8'),
            })
          })
          .catch((error) => done(error.message || String(error), null))
      },
      utils: {
        crypto: {
          md5,
          sha256: (text) => require('node:crypto')
            .createHash('sha256').update(String(text), 'utf8').digest('hex'),
          randomBytes: (size) => Array.from(
            require('node:crypto').randomBytes(Math.max(1, Math.min(1024, Number(size) || 16)))),
        },
        buffer: {
          from: (text, encoding) => Buffer.from(String(text), encoding || 'utf8'),
        },
      },
    }

    const sandbox = {
      lx,
      console: {
        log: (...args) => log('[' + file + ']', ...args.map(String)),
        warn: (...args) => log('[' + file + '] warn', ...args.map(String)),
        error: (...args) => log('[' + file + '] error', ...args.map(String)),
        info: (...args) => log('[' + file + ']', ...args.map(String)),
      },
      setTimeout,
      clearTimeout,
      setInterval,
      clearInterval,
      TextEncoder,
      TextDecoder,
      URL,
      URLSearchParams,
      btoa: (text) => Buffer.from(String(text), 'binary').toString('base64'),
      atob: (text) => Buffer.from(String(text), 'base64').toString('binary'),
      AbortController,
    }

    vm.createContext(sandbox)
    vm.runInContext(code, sandbox, {
      filename: file,
      timeout: 5000,
      displayErrors: true,
    })

    if (!requestHandler) {
      throw new Error('script did not register an lx request handler')
    }
    if (!initPayload || !initPayload.sources) {
      throw new Error('script did not report lx inited sources')
    }

    const entry = { file, handler: requestHandler, declared: initPayload.sources }
    if (extra) Object.assign(entry, extra)
    log('source ready:', file, '->', Object.keys(initPayload.sources).join(', '))
    return entry
  }

  /// 重算 platform -> entry 映射。后出现的脚本覆盖前者。
  _rebuild() {
    this.handlers.clear()
    this.registry = {}
    for (const entry of this.scripts) {
      for (const [source, info] of Object.entries(entry.declared)) {
        this.registry[source] = info
        this.handlers.set(source, entry)
      }
    }
  }

  /// 注册用户导入的脚本（界面里「导入音源」）。
  /// 同一个 id 重复导入会替换旧脚本，因此改脚本后重新导入即可生效。
  register(id, name, code) {
    const key = String(id || '').trim()
    if (!key) throw new Error('source id is required')
    const script = String(code || '')
    if (!script.trim()) throw new Error('script is empty')

    const entry = this._compile(
      'user:' + key,
      script,
      { userId: key, name: String(name || key) },
    )

    this.scripts = this.scripts.filter((item) => item.userId !== key)
    this.scripts.push(entry)
    this._rebuild()
    this._persistUserSource(key, String(name || key), script)

    const summary = this.summary()
    return {
      ok: true,
      id: key,
      name: String(name || key),
      platforms: Object.keys(entry.declared),
      sources: summary.sources,
      userSources: summary.userSources,
    }
  }

  unregister(id) {
    const key = String(id || '').trim()
    const before = this.scripts.length
    this.scripts = this.scripts.filter((item) => item.userId !== key)
    if (this.scripts.length === before) return { ok: false, error: 'not found' }
    this._rebuild()
    this._writeUserIndex(this._readUserIndex().filter((item) => item.id !== key))
    try {
      fs.unlinkSync(path.join(USER_SOURCES_DIR, this._userFileName(key)))
    } catch (_) { /* 文件不存在时忽略 */ }
    return { ok: true, ...this.summary() }
  }

  _userFileName(id) {
    return String(id).replace(/[^A-Za-z0-9_-]/g, '_') + '.js'
  }

  _indexPath() {
    return path.join(USER_SOURCES_DIR, 'index.json')
  }

  _readUserIndex() {
    try {
      const list = JSON.parse(fs.readFileSync(this._indexPath(), 'utf8'))
      return Array.isArray(list)
        ? list.filter((item) => item && item.id)
        : []
    } catch (_) {
      return []
    }
  }

  _writeUserIndex(list) {
    try {
      fs.mkdirSync(USER_SOURCES_DIR, { recursive: true })
      fs.writeFileSync(this._indexPath(), JSON.stringify(list, null, 2), 'utf8')
    } catch (error) {
      log('failed to persist user source index:', error.message)
    }
  }

  _persistUserSource(id, name, code) {
    try {
      fs.mkdirSync(USER_SOURCES_DIR, { recursive: true })
      fs.writeFileSync(
        path.join(USER_SOURCES_DIR, this._userFileName(id)),
        code,
        'utf8',
      )
      const index = this._readUserIndex().filter((item) => item.id !== id)
      index.push({ id, name })
      this._writeUserIndex(index)
    } catch (error) {
      log('failed to persist user source:', error.message)
    }
  }

  _loadUserSources() {
    for (const item of this._readUserIndex()) {
      const file = path.join(USER_SOURCES_DIR, this._userFileName(item.id))
      if (!fs.existsSync(file)) continue
      try {
        this.scripts.push(this._compile(
          'user:' + item.id,
          fs.readFileSync(file, 'utf8'),
          { userId: item.id, name: item.name || item.id },
        ))
      } catch (error) {
        log('failed to restore user source', item.id, '-', error.message)
      }
    }
  }

  summary() {
    return {
      scripts: this.scripts.map((item) => item.file),
      sources: this.registry,
      userSources: this.scripts
        .filter((item) => item.userId)
        .map((item) => ({
          id: item.userId,
          name: item.name,
          platforms: Object.keys(item.declared),
        })),
    }
  }

  has(source) {
    return this.handlers.has(String(source || ''))
  }

  async invoke(source, action, info) {
    const key = String(source || '')
    const entry = this.handlers.get(key)
    if (!entry) throw new Error('no source script registered for "' + key + '"')

    const result = await Promise.race([
      Promise.resolve().then(() => entry.handler({ action, source: key, info })),
      new Promise((_, reject) => setTimeout(
        () => reject(new Error('source handler timed out')), HANDLER_TIMEOUT)),
    ])
    return result == null ? null : result
  }
}

module.exports = { SourceRuntime }
