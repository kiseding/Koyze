'use strict'

const http = require('node:http')
const fs = require('node:fs')
const path = require('node:path')
const crypto = require('node:crypto')
const { sendJson, readJson, log } = require('./util')
const { SourceRuntime } = require('./lx-runtime')
const { search } = require('./search')
const { stream, proxyApi } = require('./proxy')

const PORT = Number(process.env.PORT) || 8080
const HOST = process.env.HOST || '0.0.0.0'
const TOKEN = String(process.env.KOYZE_TOKEN || '')
const PUBLIC_DIR = path.join(__dirname, '..', 'public')
const SESSION_SECRET = crypto.randomBytes(32).toString('hex')

const runtime = new SourceRuntime()
runtime.load()

function sessionValue() {
  return crypto.createHmac('sha256', SESSION_SECRET).update(TOKEN).digest('hex')
}

function cookieToken(req) {
  const raw = req.headers.cookie || ''
  for (const part of raw.split(';')) {
    const index = part.indexOf('=')
    if (index < 0) continue
    if (part.slice(0, index).trim() === 'koyze_session') {
      return part.slice(index + 1).trim()
    }
  }
  return ''
}

function authorized(req) {
  if (!TOKEN) return true
  const header = String(req.headers['x-koyze-token'] || '')
  if (header && header === TOKEN) return true
  return cookieToken(req) === sessionValue()
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.json': 'application/json; charset=utf-8',
}

const PLACEHOLDER = Buffer.from(`<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>Koyze Web</title><style>body{background:#14161a;color:#e8eaed;font:14px/1.7 sans-serif;
max-width:640px;margin:12vh auto;padding:0 24px}h1{font-size:20px;font-weight:500}
code{background:#242831;padding:2px 6px;border-radius:4px}p{color:#9298a3}</style></head>
<body><h1>服务已启动，但还没有 Web 界面</h1>
<p>后端 API 已可用（<code>/api/health</code>）。界面由现有 Flutter UI 编译而来，
请先在有 Flutter SDK 的机器上执行：</p>
<p><code>./scripts/build-web.sh</code></p>
<p>它会把 <code>build/web</code> 产物复制进 <code>public/</code>，刷新本页即可看到 Koyze 原本的界面。
若用 Docker 部署，先构建再 <code>docker compose up --build</code>。</p></body></html>`, 'utf8')

function sendHtml(res, status, data, cacheControl) {
  res.writeHead(status, {
    'Content-Type': 'text/html; charset=utf-8',
    'Content-Length': data.length,
    'Cache-Control': cacheControl,
  })
  res.end(data)
}

function serveStatic(res, urlPath) {
  const relative = urlPath === '/' ? 'index.html' : urlPath.replace(/^\/+/, '')
  const full = path.resolve(PUBLIC_DIR, relative)
  if (!full.startsWith(path.resolve(PUBLIC_DIR) + path.sep)) {
    return sendJson(res, 403, { error: 'forbidden' })
  }
  fs.readFile(full, (error, data) => {
    if (error) {
      // go_router 的深层路由刷新时回落到 index.html
      const indexPath = path.join(PUBLIC_DIR, 'index.html')
      if (fs.existsSync(indexPath)) {
        return fs.readFile(indexPath, (indexError, indexData) => {
          if (indexError) return sendHtml(res, 200, PLACEHOLDER, 'no-store')
          sendHtml(res, 200, indexData, 'no-cache')
        })
      }
      return sendHtml(res, 200, PLACEHOLDER, 'no-store')
    }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(full).toLowerCase()] || 'application/octet-stream',
      'Content-Length': data.length,
      'Cache-Control': 'no-cache',
    })
    res.end(data)
  })
}

function proxyUrl(raw) {
  if (!raw || typeof raw !== 'string') return null
  return '/api/stream?url=' + encodeURIComponent(raw)
}

function normalizeUrlResult(result) {
  if (!result) return null
  const direct = typeof result === 'string' ? result : result.url
  if (!direct || typeof direct !== 'string') return null
  const type = typeof result === 'object' && result.type ? result.type : null
  return { url: proxyUrl(direct), type }
}

async function handleApi(req, res, url) {
  const route = url.pathname

  if (route === '/api/health') {
    return sendJson(res, 200, {
      ok: true,
      version: '5.0.3',
      tokenRequired: Boolean(TOKEN),
      scripts: runtime.scripts.map((item) => item.file),
      sources: Object.keys(runtime.registry),
    })
  }

  if (route === '/api/login' && req.method === 'POST') {
    const body = await readJson(req)
    if (!TOKEN || String(body.token || '') === TOKEN) {
      const cookie = 'koyze_session=' + (TOKEN ? sessionValue() : '') +
        '; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000'
      res.setHeader('Set-Cookie', cookie)
      return sendJson(res, 200, { ok: true })
    }
    return sendJson(res, 401, { error: 'invalid token' })
  }

  if (!authorized(req)) {
    return sendJson(res, 401, { error: 'token required' })
  }

  if (route === '/api/sources' && req.method === 'GET') {
    return sendJson(res, 200, runtime.summary())
  }

  // 浏览器没有 QuickJS，用户在 Web 界面里导入的脚本必须交给服务端执行。
  // 客户端每次加载某个音源时把脚本体推过来，服务端编译、注册并落盘。
  if (route === '/api/sources' && req.method === 'POST') {
    const body = await readJson(req, 4 * 1024 * 1024)
    try {
      const result = runtime.register(body.id, body.name, body.script)
      return sendJson(res, 200, result)
    } catch (error) {
      return sendJson(res, 400, {
        ok: false,
        error: String(error && error.message ? error.message : error),
      })
    }
  }

  if (route === '/api/sources' && req.method === 'DELETE') {
    const result = runtime.unregister(url.searchParams.get('id'))
    return sendJson(res, result.ok ? 200 : 404, result)
  }

  if (route === '/api/reload' && req.method === 'POST') {
    return sendJson(res, 200, runtime.load())
  }

  if (route === '/api/search' && req.method === 'POST') {
    const body = await readJson(req)
    return sendJson(res, 200, await search(runtime, body))
  }

  if (route === '/api/url' && req.method === 'POST') {
    const body = await readJson(req)
    const source = String(body.source || '')
    const quality = String(body.quality || '128k')
    if (!body.musicInfo || typeof body.musicInfo !== 'object') {
      return sendJson(res, 400, { error: 'musicInfo is required' })
    }
    const result = await runtime.invoke(source, 'musicUrl', {
      type: quality,
      musicInfo: body.musicInfo,
    })
    const normalized = normalizeUrlResult(result)
    if (!normalized) {
      return sendJson(res, 404, {
        error: 'no playable url returned for this quality',
        hint: '该曲目可能受版权或会员限制，或音源脚本未覆盖此平台/档位',
      })
    }
    return sendJson(res, 200, normalized)
  }

  if (route === '/api/songlist' && req.method === 'POST') {
    const body = await readJson(req)
    const source = String(body.source || '')
    const info = { id: String(body.id || ''), page: Number(body.page) || 1 }
    const result = await runtime.invoke(source, 'songListDetail', { source, info })
    if (result == null) return sendJson(res, 200, { list: [] })
    const raw = Array.isArray(result) ? result : (result.list || [])
    return sendJson(res, 200, { list: Array.isArray(raw) ? raw : [] })
  }

  if (route === '/api/lyric' && req.method === 'POST') {
    const body = await readJson(req)
    const result = await runtime.invoke(String(body.source || ''), 'lyric', {
      musicInfo: body.musicInfo || {},
    })
    return sendJson(res, 200, result || { lyric: '', tlyric: '' })
  }

  if (route === '/api/pic' && req.method === 'POST') {
    const body = await readJson(req)
    const result = await runtime.invoke(String(body.source || ''), 'pic', {
      musicInfo: body.musicInfo || {},
    })
    const direct = result && (typeof result === 'string' ? result : result.url)
    return sendJson(res, 200, { url: proxyUrl(direct) })
  }

  // Web 端的内置音源（榜单/搜索/健康检查）直连第三方会被浏览器 CORS 拦，
  // 页面里的 XHR 重写会把跨域请求转到这里，由服务端代发并注入防盗链头。
  if (route === '/api/proxy' && ['GET', 'POST', 'HEAD', 'PUT', 'DELETE'].includes(req.method)) {
    const target = url.searchParams.get('url')
    if (!target) return sendJson(res, 400, { error: 'url is required' })
    return await proxyApi(req, res, target)
  }

  if (route === '/api/stream' && (req.method === 'GET' || req.method === 'HEAD')) {
    const target = url.searchParams.get('url')
    if (!target) return sendJson(res, 400, { error: 'url is required' })
    return await stream(req, res, target)
  }

  return sendJson(res, 404, { error: 'unknown route: ' + route })
}

const server = http.createServer(async (req, res) => {
  let url
  try {
    url = new URL(req.url, 'http://localhost')
  } catch (_) {
    return sendJson(res, 400, { error: 'bad request' })
  }

  if (!url.pathname.startsWith('/api/')) {
    // 口令模式：界面本身没有输入口令的地方（登录页是 Koyze 云账号），
    // 所以允许用一次 ?token= 换成会话 cookie，之后整站（含 <audio> 流）都带 cookie。
    if (TOKEN) {
      const queryToken = url.searchParams.get('token')
      if (queryToken && queryToken === TOKEN) {
        res.writeHead(302, {
          'Set-Cookie': 'koyze_session=' + sessionValue() +
            '; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000',
          Location: '/',
        })
        return res.end()
      }
    }
    return serveStatic(res, url.pathname)
  }

  try {
    await handleApi(req, res, url)
  } catch (error) {
    log('request failed', req.method, url.pathname, '-', error.message)
    if (!res.headersSent) {
      sendJson(res, 502, { error: error.message || 'upstream failed' })
    } else {
      res.end()
    }
  }
})

server.listen(PORT, HOST, () => {
  log('Koyze Web listening on http://' + HOST + ':' + PORT)
  log('token protection:', TOKEN ? 'enabled' : 'disabled (set KOYZE_TOKEN to enable)')
  log('source scripts:', runtime.scripts.length,
    '| platforms:', Object.keys(runtime.registry).join(', ') || 'none')
  if (!runtime.scripts.length) {
    log('WARNING: no source scripts in ./sources - mount your LX script there')
  }
})
