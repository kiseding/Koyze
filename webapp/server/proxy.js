'use strict'

const { Readable } = require('node:stream')
const { safeFetch, normalizeHeaders, log } = require('./util')

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

const REFERERS = [
  [/(\.|^)kugou\.com$/, 'https://www.kugou.com/'],
  [/(\.|^)kuwo\.cn$/, 'https://www.kuwo.cn/'],
  [/(\.|^)music\.163\.com$/, 'https://music.163.com/'],
  [/(\.|^)126\.net$/, 'https://music.163.com/'],
  [/(\.|^)qq\.com$/, 'https://y.qq.com/'],
  [/(\.|^)gtimg\.cn$/, 'https://y.qq.com/'],
  [/(\.|^)qstatic\.com$/, 'https://y.qq.com/'],
  [/(\.|^)xunhuisi\.store$/, 'https://api.xunhuisi.store/'],
]

function refererFor(hostname, fallback) {
  for (const [pattern, value] of REFERERS) {
    if (pattern.test(hostname)) return value
  }
  return fallback
}

async function stream(req, res, rawUrl) {
  const parsed = new URL(String(rawUrl))
  const origin = parsed.protocol + '//' + parsed.host
  const headers = {
    'User-Agent': UA,
    Referer: refererFor(parsed.hostname, origin + '/'),
    Accept: '*/*',
  }

  // 浏览器拖动进度条会带 Range，必须原样转发才能拿到 206。
  if (req.headers.range) headers.Range = String(req.headers.range)
  if (req.headers['if-range']) headers['If-Range'] = String(req.headers['if-range'])

  const { response, finalUrl } = await safeFetch(String(rawUrl), {
    method: req.method === 'HEAD' ? 'HEAD' : 'GET',
    headers,
    timeout: 20000,
  })

  const out = {
    'Content-Type': response.headers.get('content-type') || 'application/octet-stream',
    'Accept-Ranges': response.headers.get('accept-ranges') || 'bytes',
    'Cache-Control': 'private, max-age=3600',
    'X-Content-Type-Options': 'nosniff',
  }
  for (const key of ['content-length', 'content-range', 'etag', 'last-modified']) {
    const value = response.headers.get(key)
    if (value) out[key] = value
  }

  res.writeHead(response.status, out)
  if (req.method === 'HEAD' || !response.body) {
    res.end()
    return
  }

  const nodeStream = Readable.fromWeb(response.body)
  nodeStream.on('error', (error) => {
    log('stream error', finalUrl, '-', error.message)
    if (!res.headersSent) res.writeHead(502)
    res.end()
  })
  req.on('close', () => nodeStream.destroy())
  nodeStream.pipe(res)
}

async function proxyApi(req, res, rawUrl) {
  const parsed = new URL(String(rawUrl))
  const origin = parsed.protocol + '//' + parsed.host
  const headers = normalizeHeaders(req.headers)
  headers['User-Agent'] = UA
  headers['Referer'] = refererFor(parsed.hostname, origin + '/')
  delete headers.host

  let body
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    body = await new Promise((resolve, reject) => {
      const chunks = []
      req.on('data', (chunk) => chunks.push(chunk))
      req.on('end', () => resolve(Buffer.concat(chunks)))
      req.on('error', reject)
    })
  }

  const { response } = await safeFetch(String(rawUrl), {
    method: req.method,
    headers,
    body: body && body.length ? body : undefined,
    timeout: 20000,
  })

  const buffer = Buffer.from(await response.arrayBuffer())
  const out = {
    'Content-Type': response.headers.get('content-type') || 'application/octet-stream',
    'Cache-Control': 'no-store',
    'X-Koyze-Proxy-Status': String(response.status),
  }
  // Node fetch 已解压，透传原始编码/长度会让浏览器解错。
  for (const key of ['etag', 'last-modified']) {
    const value = response.headers.get(key)
    if (value) out[key] = value
  }
  res.writeHead(200, out)
  res.end(buffer)
}

module.exports = { stream, proxyApi }
