'use strict'

const crypto = require('node:crypto')
const dns = require('node:dns').promises
const { URL } = require('node:url')

const ALLOW_PRIVATE = process.env.KOYZE_ALLOW_PRIVATE === '1'

function isPrivateIp(ip) {
  let value = String(ip || '').toLowerCase()
  if (value.startsWith('::ffff:')) value = value.slice(7)
  if (value === '::1' || value === '::' || value.startsWith('fc') ||
      value.startsWith('fd') || value.startsWith('fe80')) return true
  const parts = value.split('.').map(Number)
  if (parts.length !== 4 || parts.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) {
    return false
  }
  const [a, b, c] = parts
  if (a === 0 || a === 10 || a === 127) return true
  if (a === 169 && b === 254) return true
  if (a === 172 && b >= 16 && b <= 31) return true
  if (a === 192 && b === 168) return true
  if (a === 192 && b === 0 && c === 0) return true
  if (a === 100 && b >= 64 && b <= 127) return true
  if (a === 198 && (b === 18 || b === 19)) return true
  return false
}

// 音源脚本可以请求任意 URL，所以每一跳都要重新做 DNS 校验。
// 只放行 http/https、公网地址，避免脚本被拿来探测家庭内网。
async function assertPublicUrl(raw) {
  let parsed
  try {
    parsed = new URL(String(raw))
  } catch (_) {
    throw new Error('invalid url')
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error('unsupported protocol: ' + parsed.protocol)
  }
  if (parsed.username || parsed.password) throw new Error('url credentials are not allowed')
  if (!ALLOW_PRIVATE) {
    let addresses
    try {
      addresses = await dns.lookup(parsed.hostname, { all: true })
    } catch (_) {
      throw new Error('dns lookup failed: ' + parsed.hostname)
    }
    if (!addresses.length || addresses.some((entry) => isPrivateIp(entry.address))) {
      throw new Error('private or loopback target is blocked: ' + parsed.hostname)
    }
  }
  return parsed
}

const FORBIDDEN_HEADERS = new Set([
  'host', 'content-length', 'connection', 'transfer-encoding',
  'accept-encoding', 'upgrade', 'proxy-authorization',
])

function normalizeHeaders(input) {
  const out = {}
  for (const [key, value] of Object.entries(input || {})) {
    const lower = key.toLowerCase()
    if (FORBIDDEN_HEADERS.has(lower)) continue
    if (value === undefined || value === null) continue
    out[key] = String(value)
  }
  return out
}

// 手动跟随重定向，逐跳校验，防止用 302 绕过私网检查。
async function safeFetch(rawUrl, options = {}) {
  const timeout = Number(options.timeout) > 0 ? Number(options.timeout) : 15000
  let current = String(rawUrl)
  for (let hop = 0; hop < 4; hop++) {
    const parsed = await assertPublicUrl(current)
    const init = {
      method: options.method || 'GET',
      headers: normalizeHeaders(options.headers),
      redirect: 'manual',
      signal: AbortSignal.timeout(timeout),
    }
    if (init.method !== 'GET' && init.method !== 'HEAD' && options.body != null) {
      init.body = options.body
    }
    const response = await fetch(current, init)
    if (response.status >= 300 && response.status < 400 && response.headers.get('location')) {
      const next = new URL(response.headers.get('location'), current).toString()
      await response.arrayBuffer().catch(() => {})
      current = next
      continue
    }
    return { response, finalUrl: current }
  }
  throw new Error('too many redirects')
}

function md5(text) {
  return crypto.createHash('md5').update(String(text), 'utf8').digest('hex')
}

function sendJson(res, status, payload) {
  const body = Buffer.from(JSON.stringify(payload), 'utf8')
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': body.length,
    'Cache-Control': 'no-store',
  })
  res.end(body)
}

function readJson(req, limit = 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = []
    let size = 0
    req.on('data', (chunk) => {
      size += chunk.length
      if (size > limit) {
        reject(new Error('request body too large'))
        req.destroy()
        return
      }
      chunks.push(chunk)
    })
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8')
      if (!raw) return resolve({})
      try {
        resolve(JSON.parse(raw))
      } catch (_) {
        reject(new Error('invalid json body'))
      }
    })
    req.on('error', reject)
  })
}

function log(...args) {
  const ts = new Date().toISOString()
  console.log('[' + ts + ']', ...args)
}

module.exports = {
  ALLOW_PRIVATE,
  assertPublicUrl,
  safeFetch,
  normalizeHeaders,
  md5,
  sendJson,
  readJson,
  log,
}
