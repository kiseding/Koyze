/*!
 * @name 巡回寺 QQ + 网易云 + 酷我 + 酷狗
 * @description 网易云 / 酷狗全部改走官方接口（320k 直出，不依赖任何第三方转发站）；QQ 走巡回寺；酷我走官方 convert_url2（DES）
 * @version 2.0.0
 * @author kiseding
 *
 * ===== 网易云：官方 music.163.com，不需要第三方站 =====
 *   取地址：GET https://music.163.com/api/song/enhance/player/url
 *                ?ids=[id]&br=320000
 *           免 cookie 下大部分歌曲直接给 320k（fee=8 的也放 320k）；
 *           返回 code=-110 是仅会员可听，code=404 是已下架/无版权。
 *           回退：GET /api/song/enhance/player/url/v1?ids=[id]&level=exhigh&encodeType=mp3
 *   歌词：  GET https://music.163.com/api/song/lyric?id={id}&lv=-1&kv=-1&tv=-1
 *   封面：  GET https://music.163.com/api/song/detail?ids=[id]
 *   → 想听会员曲目，把 CONFIG.wyCookie 填成自己的 MUSIC_U 即可。
 *
 * ===== 酷狗：官方 m.kugou.com + trackercdn，不需要第三方站 =====
 *   补 hash：GET https://m.kugou.com/app/i/getSongInfo.php?cmd=playInfo&hash={128hash}
 *            即使上层只给 128k 的 hash，也能从 extra.320hash / extra.sqhash
 *            补出 320k 与无损档位；顺带拿封面 album_img 与时长。
 *   取地址： GET https://trackercdn.kugou.com/i/v2/
 *             ?appid=1005&pid=2&cmd=25&behavior=play&hash={hash}&key=MD5(hash+"kgcloudv2")
 *            status=1 → 成功，bitRate 决定真实档位，无损的 url 是数组；
 *            status=2 → 该曲需要付费 / 会员。
 *   回退：  trackercdnbj.kugou.com（cmd=23&pid=1）
 *   歌词：  krcs.kugou.com/search + lyrics.kugou.com/download（base64 LRC）
 *
 * ===== 酷我：官方 mobi.kuwo.cn convert_url2（DES），保持原样 =====
 *   format=flac | format=mp3&br=320kmp3 | format=mp3
 *   不请求加密 mgg/mflac（沙箱没有 zlib/QMC）
 *
 * body 传对象而不是 JSON.stringify，让 Koyze 引擎按 JSON 编码并写成字节。
 */

// 需要会员曲目时填自己的登录态；留空则只走免登录能拿到的档位
const CONFIG = {
  // 浏览器登录 music.163.com → F12 → Application → Cookies → 复制 MUSIC_U 的值
  // 可写 'MUSIC_U=xxxx' 也可只写 'xxxx'
  wyCookie: '',
  // 酷狗网页登录后的 token / userid，留空即匿名（匿名可播非会员曲目）
  kgToken: '',
  kgUserId: '',
}

const TX_API_URL = 'https://api.xunhuisi.store/API/QQMusic/Song.php'
const KW_MOBI_URL = 'https://mobi.kuwo.cn/mobi.s'
const KW_LYRIC_URL = 'https://www.kuwo.cn/openapi/v1/www/lyric/getlyric'
const KW_PIC_URL = 'https://artistpicserver.kuwo.cn/pic.web'
const KG_UA =
  'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
const KG_PLAYINFO_URL = 'https://m.kugou.com/app/i/getSongInfo.php'
const KG_TRACKER_URL = 'https://trackercdn.kugou.com/i/v2/'
const KG_TRACKER_BACKUP_URL = 'https://trackercdnbj.kugou.com/i/v2/'
const KG_LYRIC_SEARCH_URL = 'https://krcs.kugou.com/search'
const KG_LYRIC_DOWNLOAD_URL = 'https://lyrics.kugou.com/download'
const KG_LYRIC_HEADERS = {
  'KG-RC': '1',
  'KG-THash': 'expand_search_manager.cpp:852736169:451',
  'User-Agent': 'KuGou2012-9020-ExpandSearchManager',
  Referer: 'https://www.kugou.com/',
}
// 请求档位 -> 依次尝试的 hash 档位
const KG_LEVELS = {
  '128k': ['128'],
  '320k': ['320', '128'],
  flac: ['flac', '320', '128'],
  flac24bit: ['flac', '320', '128'],
  hires: ['flac', '320', '128'],
}
const KW_ANTI_URL = 'https://antiserver.kuwo.cn/anti.s'
const KW_HAITANG_URL = 'https://musicapi.haitangw.net/music/kw.php'
const KW_NXINXZ_URL = 'https://music.nxinxz.com/kw.php'
const TX_QUALITY_MAP = {
  '128k': 'standard',
  '320k': 'high',
}

// ===== 网易云（官方接口）=====
const WY_API = 'https://music.163.com'
const WY_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
// 请求档位 -> 依次尝试的码率（接口会按账号权限自动降级）
const WY_BR_CHAIN = {
  '128k': [128000],
  '320k': [320000, 128000],
  flac: [999000, 320000, 128000],
  flac24bit: [1900000, 999000, 320000],
  hires: [1900000, 999000, 320000],
}
const WY_LEVEL_BY_TYPE = {
  '128k': 'standard',
  '320k': 'exhigh',
  flac: 'lossless',
  flac24bit: 'hires',
  hires: 'hires',
}

// lx.request 的 body 可能是 string，也可能是 ArrayBuffer / TypedArray，统一按 UTF-8 解出来
function responseText(body) {
  if (typeof body === 'string') return body
  if (body == null) return ''
  try {
    let view = null
    if (typeof ArrayBuffer !== 'undefined' && body instanceof ArrayBuffer) {
      view = new Uint8Array(body)
    } else if (
      typeof ArrayBuffer !== 'undefined' &&
      body &&
      typeof body === 'object' &&
      body.buffer instanceof ArrayBuffer
    ) {
      view = new Uint8Array(body.buffer, body.byteOffset || 0, body.byteLength || 0)
    }
    if (view) {
      if (typeof TextDecoder === 'function') return new TextDecoder('utf-8').decode(view)
      let out = ''
      for (let i = 0; i < view.length; i++) out += String.fromCharCode(view[i])
      return out
    }
  } catch (_) {}
  return ''
}

function requestJson(url, options) {
  const opts = options || { method: 'GET' }
  return new Promise((resolve) => {
    lx.request(url, opts, (error, response) => {
      if (error || !response || response.statusCode < 200 || response.statusCode >= 300) {
        resolve(null)
        return
      }

      const body = response.body
      const text = responseText(body)
      if (!text) {
        // 少数实现会直接给已解析好的对象
        const isBinary =
          typeof ArrayBuffer !== 'undefined' &&
          (body instanceof ArrayBuffer || (body && typeof body === 'object' && body.buffer instanceof ArrayBuffer))
        resolve(!isBinary && body && typeof body === 'object' ? body : null)
        return
      }

      try {
        resolve(JSON.parse(text))
      } catch (_) {
        resolve(null)
      }
    })
  })
}

function requestText(url, options) {
  const opts = options || { method: 'GET' }
  return new Promise((resolve) => {
    lx.request(url, opts, (error, response) => {
      if (error || !response || response.statusCode < 200 || response.statusCode >= 300) {
        resolve(null)
        return
      }
      resolve(responseText(response.body))
    })
  })
}

function wyCookieValue() {
  const raw = String(CONFIG.wyCookie || '').trim()
  if (!raw) return ''
  if (raw.indexOf('MUSIC_U=') >= 0) return raw
  return 'MUSIC_U=' + raw
}

function wyHeaders() {
  const headers = {
    'User-Agent': WY_UA,
    Referer: WY_API + '/',
  }
  const cookie = wyCookieValue()
  if (cookie) headers.Cookie = cookie + '; os=pc; appver=2.9.7'
  return headers
}

function wyGet(path, query) {
  return requestJson(WY_API + path + (query ? '?' + query : ''), {
    method: 'GET',
    headers: wyHeaders(),
  })
}

// 接口返回的 br 是实际给出的码率，按它反推真实档位
function wyTypeFromBr(br) {
  const value = Number(br) || 0
  if (value >= 1800000) return 'hires'
  if (value >= 900000) return 'flac'
  if (value >= 300000) return '320k'
  return '128k'
}

function wyPickItem(data) {
  if (!data || typeof data !== 'object') return null
  const payload = data.data
  if (Array.isArray(payload)) return payload[0] || null
  if (payload && typeof payload === 'object') return payload
  return data
}

function pickHttpUrl(value) {
  if (typeof value !== 'string') return ''
  const url = value.trim()
  return /^https?:\/\//.test(url) ? url : ''
}

function pickWyUrl(data) {
  if (!data || typeof data !== 'object') return ''
  return (
    pickHttpUrl(data.url) ||
    pickHttpUrl(data.music_url) ||
    (data.data && !Array.isArray(data.data) ? pickHttpUrl(data.data.url) : '') ||
    (data.data && data.data[0] ? pickHttpUrl(data.data[0].url) : '')
  )
}

function pickLyricText(value) {
  if (typeof value === 'string') return value
  if (value && typeof value.lyric === 'string') return value.lyric
  return ''
}

function wyUrlResult(item) {
  if (!item) return null
  const url = pickHttpUrl(item.url) || pickHttpUrl(item.music_url)
  if (!url) return null
  return { url: url, type: wyTypeFromBr(item.br) }
}

function handleTx(action, info) {
  const musicInfo = (info && info.musicInfo) || {}
  const id = musicInfo.songmid || musicInfo.id || musicInfo.hash
  if (!id) return Promise.resolve(null)

  const quality = TX_QUALITY_MAP[info && info.type]
  if (action === 'musicUrl' && !quality) return Promise.resolve(null)
  if (action !== 'musicUrl' && action !== 'lyric') return Promise.resolve(null)

  const query = ['id=' + encodeURIComponent(id)]
  if (quality) query.push('quality=' + quality)

  return requestJson(TX_API_URL + '?' + query.join('&')).then((data) => {
    if (!data || Number(data.code) !== 200) return null
    if (action === 'musicUrl') {
      const url = pickHttpUrl(data.music_url)
      return url ? { url: url } : null
    }
    const lyric = typeof data.lyric === 'string' ? data.lyric : ''
    return lyric ? { lyric: lyric } : null
  })
}

async function handleWy(action, info) {
  const musicInfo = (info && info.musicInfo) || {}
  const id = musicInfo.songmid || musicInfo.id || musicInfo.hash
  if (!id) return null
  if (action !== 'musicUrl' && action !== 'lyric' && action !== 'pic') return null

  const songId = encodeURIComponent(String(id))

  if (action === 'pic') {
    const data = await wyGet('/api/song/detail', 'ids=%5B' + songId + '%5D')
    const songs = (data && data.songs) || []
    const album = songs[0] && songs[0].album
    const url = pickHttpUrl(album && album.picUrl)
    return url ? { url: url } : null
  }

  if (action === 'lyric') {
    const data = await wyGet('/api/song/lyric', 'id=' + songId + '&lv=-1&kv=-1&tv=-1')
    if (!data) return null
    const lyric = pickLyricText(data.lrc) || pickLyricText(data.lyric)
    if (!lyric) return null
    const result = { lyric: lyric }
    const tlyric = pickLyricText(data.tlyric)
    if (tlyric) result.tlyric = tlyric
    return result
  }

  const chain = WY_BR_CHAIN[info && info.type]
  if (!chain) return null

  // 官方接口会按账号权限自动降级，所以按码率从高到低试
  for (let i = 0; i < chain.length; i++) {
    const data = await wyGet(
      '/api/song/enhance/player/url',
      'ids=%5B' + songId + '%5D&br=' + chain[i],
    )
    const item = wyPickItem(data)
    const result = wyUrlResult(item)
    if (result) return result
    // -110 仅会员 / 404 已下架：换码率也没用，直接跳出
    if (item && Number(item.code) !== 200) break
  }

  // 回退 v1 level 端点
  const level = WY_LEVEL_BY_TYPE[info && info.type]
  if (!level) return null
  const data = await wyGet(
    '/api/song/enhance/player/url/v1',
    'ids=%5B' + songId + '%5D&level=' + level + '&encodeType=mp3',
  )
  return wyUrlResult(wyPickItem(data))
}

const KW_LS = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1]
const KW_LSMASK = [0, 0x100001, 0x300003]
const KW_E = [31,0,1,2,3,4,-1,-1,3,4,5,6,7,8,-1,-1,7,8,9,10,11,12,-1,-1,11,12,13,14,15,16,-1,-1,15,16,17,18,19,20,-1,-1,19,20,21,22,23,24,-1,-1,23,24,25,26,27,28,-1,-1,27,28,29,30,31,30,-1,-1]
const KW_IP1 = [39,7,47,15,55,23,63,31,38,6,46,14,54,22,62,30,37,5,45,13,53,21,61,29,36,4,44,12,52,20,60,28,35,3,43,11,51,19,59,27,34,2,42,10,50,18,58,26,33,1,41,9,49,17,57,25,32,0,40,8,48,16,56,24]
const KW_IP2 = [57,49,41,33,25,17,9,1,59,51,43,35,27,19,11,3,61,53,45,37,29,21,13,5,63,55,47,39,31,23,15,7,56,48,40,32,24,16,8,0,58,50,42,34,26,18,10,2,60,52,44,36,28,20,12,4,62,54,46,38,30,22,14,6]
const KW_P = [15,6,19,20,28,11,27,16,0,14,22,25,4,17,30,9,1,7,23,13,31,26,2,8,18,12,29,5,21,10,3,24]
const KW_PC1 = [56,48,40,32,24,16,8,0,57,49,41,33,25,17,9,1,58,50,42,34,26,18,10,2,59,51,43,35,62,54,46,38,30,22,14,6,61,53,45,37,29,21,13,5,60,52,44,36,28,20,12,4,27,19,11,3]
const KW_PC2 = [13,16,10,23,0,4,-1,-1,2,27,14,5,20,9,-1,-1,22,18,11,3,25,7,-1,-1,15,6,26,19,12,1,-1,-1,40,51,30,36,46,54,-1,-1,29,39,50,44,32,47,-1,-1,43,48,38,55,33,52,-1,-1,45,41,49,35,28,31,-1,-1]
const KW_SBOX = [
  [14,4,3,15,2,13,5,3,13,14,6,9,11,2,0,5,4,1,10,12,15,6,9,10,1,8,12,7,8,11,7,0,0,15,10,5,14,4,9,10,7,8,12,3,13,1,3,6,15,12,6,11,2,9,5,0,4,2,11,14,1,7,8,13],
  [15,0,9,5,6,10,12,9,8,7,2,12,3,13,5,2,1,14,7,8,11,4,0,3,14,11,13,6,4,1,10,15,3,13,12,11,15,3,6,0,4,10,1,7,8,4,11,14,13,8,0,6,2,15,9,5,7,1,10,12,14,2,5,9],
  [10,13,1,11,6,8,11,5,9,4,12,2,15,3,2,14,0,6,13,1,3,15,4,10,14,9,7,12,5,0,8,7,13,1,2,4,3,6,12,11,0,13,5,14,6,8,15,2,7,10,8,15,4,9,11,5,9,0,14,3,10,7,1,12],
  [7,10,1,15,0,12,11,5,14,9,8,3,9,7,4,8,13,6,2,1,6,11,12,2,3,0,5,14,10,13,15,4,13,3,4,9,6,10,1,12,11,0,2,5,0,13,14,2,8,15,7,4,15,1,10,7,5,6,12,11,3,8,9,14],
  [2,4,8,15,7,10,13,6,4,1,3,12,11,7,14,0,12,2,5,9,10,13,0,3,1,11,15,5,6,8,9,14,14,11,5,6,4,1,3,10,2,12,15,0,13,2,8,5,11,8,0,15,7,14,9,4,12,7,10,9,1,13,6,3],
  [12,9,0,7,9,2,14,1,10,15,3,4,6,12,5,11,1,14,13,0,2,8,7,13,15,5,4,10,8,3,11,6,10,4,6,11,7,9,0,6,4,2,13,1,9,15,3,8,15,3,1,14,12,5,11,0,2,12,14,7,5,10,8,13],
  [4,1,3,10,15,12,5,0,2,11,9,6,8,7,6,9,11,4,12,15,0,3,10,5,14,13,7,8,13,14,1,2,13,6,14,9,4,1,2,14,11,13,5,0,1,10,8,3,0,11,3,5,9,4,15,2,7,8,12,15,10,7,6,12],
  [13,7,10,0,6,9,5,15,8,4,3,10,11,14,12,5,2,11,9,6,15,12,0,3,4,1,14,13,1,2,7,8,1,2,12,15,10,4,0,3,13,14,6,9,7,8,9,6,15,1,5,12,3,10,14,5,8,7,11,0,4,13,2,11],
]
const KW_KEY_SONG = [121, 108, 122, 115, 120, 107, 119, 109]

function kwBitTest(hi, lo, idx) {
  return idx < 32 ? ((lo >>> idx) & 1) !== 0 : ((hi >>> (idx - 32)) & 1) !== 0
}

function kwBittransform(arr, n, hi, lo) {
  let oHi = 0
  let oLo = 0
  for (let i = 0; i < n; i++) {
    const idx = arr[i]
    if (idx >= 0 && kwBitTest(hi, lo, idx)) {
      if (i < 32) oLo |= 1 << i
      else oHi |= 1 << (i - 32)
    }
  }
  return [oHi >>> 0, oLo >>> 0]
}

function kwShl64(hi, lo, n) {
  if (n <= 0) return [hi, lo]
  if (n >= 64) return [0, 0]
  if (n >= 32) return [(lo << (n - 32)) >>> 0, 0]
  return [((hi << n) | (lo >>> (32 - n))) >>> 0, (lo << n) >>> 0]
}

function kwShr64(hi, lo, n) {
  if (n <= 0) return [hi, lo]
  if (n >= 64) return [0, 0]
  if (n >= 32) return [0, hi >>> (n - 32)]
  return [hi >>> n, ((lo >>> n) | (hi << (32 - n))) >>> 0]
}

function kwBytesTo64(msg, offset, len) {
  let lo = 0
  let hi = 0
  for (let n = 0; n < len; n++) {
    const v = msg[offset + n] & 0xFF
    if (n < 4) lo |= v << (n * 8)
    else hi |= v << ((n - 4) * 8)
  }
  return [hi >>> 0, lo >>> 0]
}

function kwDes64(longs, hi, lo) {
  const ip = kwBittransform(KW_IP2, 64, hi, lo)
  let left = ip[1]
  let right = ip[0]
  for (let i = 0; i < 16; i++) {
    const expanded = kwBittransform(KW_E, 64, 0, right)
    const rHi = (expanded[0] ^ longs[i][0]) >>> 0
    const rLo = (expanded[1] ^ longs[i][1]) >>> 0
    let sOut = 0
    for (let sbi = 7; sbi >= 0; sbi--) {
      const idx = sbi < 4 ? (rLo >>> (sbi * 8)) & 0xFF : (rHi >>> ((sbi - 4) * 8)) & 0xFF
      sOut = ((sOut << 4) | (KW_SBOX[sbi][idx] & 0xF)) >>> 0
    }
    const p = kwBittransform(KW_P, 32, 0, sOut)
    const nextRight = (left ^ p[1]) >>> 0
    left = right
    right = nextRight
  }
  return kwBittransform(KW_IP1, 64, left, right)
}

function kwSubkeys(keyHi, keyLo) {
  let state = kwBittransform(KW_PC1, 56, keyHi, keyLo)
  const longs = new Array(16)
  for (let i = 0; i < 16; i++) {
    const round = KW_LS[i]
    const maskLo = KW_LSMASK[round]
    const left = kwShl64(0, (state[1] & maskLo) >>> 0, 28 - round)
    const right = kwShr64(state[0], (state[1] & (~maskLo >>> 0)) >>> 0, round)
    state = [(left[0] | right[0]) >>> 0, (left[1] | right[1]) >>> 0]
    longs[i] = kwBittransform(KW_PC2, 64, state[0], state[1])
  }
  return longs
}

function kwEncryptQuery(query) {
  const key = kwBytesTo64(KW_KEY_SONG, 0, 8)
  const longs = kwSubkeys(key[0], key[1])
  const msg = []
  for (let i = 0; i < query.length; i++) msg.push(query.charCodeAt(i) & 0xFF)
  const blockCount = Math.floor(msg.length / 8)
  const out = []
  for (let m = 0; m < blockCount; m++) {
    const block = kwBytesTo64(msg, m * 8, 8)
    out.push(kwDes64(longs, block[0], block[1]))
  }
  const rem = msg.length % 8
  const tail = kwBytesTo64(msg, blockCount * 8, rem)
  out.push(kwDes64(longs, tail[0], tail[1]))
  let binary = ''
  for (let i = 0; i < out.length; i++) {
    const hi = out[i][0]
    const lo = out[i][1]
    for (let b = 0; b < 4; b++) binary += String.fromCharCode((lo >>> (b * 8)) & 0xFF)
    for (let b = 0; b < 4; b++) binary += String.fromCharCode((hi >>> (b * 8)) & 0xFF)
  }
  return btoa(binary)
}

function kwRid(musicInfo) {
  let id = String((musicInfo && (musicInfo.songmid || musicInfo.id || musicInfo.hash)) || '')
  if (id.indexOf('MUSIC_') === 0) id = id.slice(6)
  return id
}

function kwPlayableUrl(value) {
  const url = pickHttpUrl(value)
  if (!url) return ''
  const lower = url.toLowerCase()
  if (lower.indexOf('.mflac') >= 0 || lower.indexOf('.mgg') >= 0 || lower.indexOf('.mmp4') >= 0) return ''
  return url
}

function kwGuessType(url) {
  const lower = url.toLowerCase()
  if (
    lower.indexOf('.flac') >= 0 ||
    lower.indexOf('/f000') >= 0 ||
    lower.indexOf('format$flac') >= 0 ||
    lower.indexOf('format=flac') >= 0
  ) {
    return 'flac'
  }
  if (lower.indexOf('m800') >= 0 || lower.indexOf('320k') >= 0 || lower.indexOf('bitrate$320') >= 0) return '320k'
  return '128k'
}

function kwUrlResult(url) {
  const playable = kwPlayableUrl(url)
  if (!playable) return null
  return { url: playable, type: kwGuessType(playable) }
}

function kwPickMobiUrl(text) {
  if (typeof text !== 'string') return ''
  const line = /(?:^|\r?\n)url=([^\r\n]+)/.exec(text)
  if (line) return kwPlayableUrl(line[1])
  const fallback = /https?:\/\/[^\s$"]+/.exec(text)
  return fallback ? kwPlayableUrl(fallback[0]) : ''
}

function kwPad(value, width) {
  let text = String(value)
  while (text.length < width) text = '0' + text
  return text
}

function kwLrclistToLrc(list) {
  if (!Array.isArray(list) || !list.length) return ''
  const lines = []
  for (let i = 0; i < list.length; i++) {
    const item = list[i]
    const text = item && item.lineLyric
    if (typeof text !== 'string' || !text.trim()) continue
    const sec = Number(item.time)
    const ms = Number.isFinite(sec) ? Math.max(0, Math.round(sec * 1000)) : 0
    const mm = kwPad(Math.floor(ms / 60000), 2)
    const ss = kwPad(Math.floor((ms % 60000) / 1000), 2)
    const xx = kwPad(ms % 1000, 3)
    lines.push('[' + mm + ':' + ss + '.' + xx + ']' + text)
  }
  return lines.join('\n')
}

async function kwOfficialUrl(id, format, br) {
  let query =
    'user=0&corp=kuwo&source=kwplayer_ar_5.1.0.0_B_jiakong_vh.apk&p2p=1&type=convert_url2&sig=0&format=' +
    format +
    '&rid=' +
    id
  if (br) query += '&br=' + br
  const text = await requestText(KW_MOBI_URL + '?f=kuwo&q=' + encodeURIComponent(kwEncryptQuery(query)), {
    method: 'GET',
    headers: { 'User-Agent': 'okhttp/3.10.0' },
  })
  const result = kwUrlResult(kwPickMobiUrl(text || ''))
  if (!result) return null
  const bitrate = Number((/(?:^|\r?\n)bitrate=([^\r\n]+)/.exec(text || '') || [])[1])
  if (bitrate === 320) result.type = '320k'
  else if (bitrate === 128) result.type = '128k'
  if (br === '320kmp3' && result.type !== '320k') return null
  return result
}

async function kwThirdPartyUrl(id, level) {
  const urls = [
    KW_HAITANG_URL + '?id=' + encodeURIComponent(id) + '&level=' + level + '&type=json',
    KW_NXINXZ_URL + '?id=' + encodeURIComponent(id) + '&level=' + level + '&type=json',
  ]
  for (let i = 0; i < urls.length; i++) {
    const result = kwUrlResult(pickWyUrl(await requestJson(urls[i])))
    if (result) return result
  }
  return null
}

async function kwAntiUrl(id) {
  const rids = [id, 'MUSIC_' + id]
  for (let i = 0; i < rids.length; i++) {
    const text = await requestText(
      KW_ANTI_URL + '?type=convert_url&rid=' + encodeURIComponent(rids[i]) + '&format=mp3&response=url',
      { method: 'GET', headers: { 'User-Agent': 'okhttp/3.10.0' } },
    )
    const result = kwUrlResult((text || '').trim())
    if (result) return result
  }
  return null
}

async function handleKw(action, info) {
  const id = kwRid((info && info.musicInfo) || {})
  if (!id) return null

  if (action === 'pic') {
    const text = await requestText(
      KW_PIC_URL + '?corp=kuwo&type=rid_pic&pictype=500&size=500&rid=' + encodeURIComponent(id),
      { method: 'GET', headers: { Referer: 'https://www.kuwo.cn/' } },
    )
    const url = kwPlayableUrl((text || '').trim())
    return url ? { url: url } : null
  }

  if (action === 'lyric') {
    const data = await requestJson(KW_LYRIC_URL + '?musicId=' + encodeURIComponent(id), {
      method: 'GET',
      headers: { Referer: 'https://www.kuwo.cn/' },
    })
    const list = data && data.data && data.data.lrclist
    const lyric = kwLrclistToLrc(list)
    return lyric ? { lyric: lyric } : null
  }

  if (action !== 'musicUrl') return null

  const quality = info && info.type
  if (quality === '320k') {
    return (
      (await kwOfficialUrl(id, 'mp3', '320kmp3')) ||
      (await kwThirdPartyUrl(id, 'exhigh')) ||
      (await kwAntiUrl(id))
    )
  }
  if (quality === 'flac' || quality === 'flac24bit' || quality === 'hires') {
    return (await kwOfficialUrl(id, 'flac')) || (await kwThirdPartyUrl(id, 'lossless'))
  }
  if (quality === '128k') {
    return (await kwOfficialUrl(id, 'mp3')) || (await kwThirdPartyUrl(id, 'standard')) || (await kwAntiUrl(id))
  }
  return null
}

function kgMd5(text) {
  const utils = lx && lx.utils && lx.utils.crypto
  if (!utils || typeof utils.md5 !== 'function') return ''
  const value = utils.md5(String(text))
  return typeof value === 'string' ? value : ''
}

function kgRead(musicInfo, meta, keys) {
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i]
    const direct = musicInfo && musicInfo[key]
    if (direct != null && String(direct).trim()) return String(direct).trim()
    const nested = meta && meta[key]
    if (nested != null && String(nested).trim()) return String(nested).trim()
  }
  return ''
}

// playInfo 结果缓存：同一个 128 hash 30 分钟内不重复请求
const kgInfoCache = {}

function kgCacheGet(hash) {
  const item = kgInfoCache[hash]
  if (item && Date.now() - item.at < 30 * 60 * 1000) return item
  return null
}

// 官方 getSongInfo 会把 320 / 无损的 hash 一并给我们（extra 里），
// 所以即便上层只给了 128k 的 hash，也能补出高档位。
async function kgPlayInfo(h128) {
  if (!h128) return null
  const cached = kgCacheGet(h128)
  if (cached) return cached

  const data = await requestJson(
    KG_PLAYINFO_URL + '?cmd=playInfo&hash=' + encodeURIComponent(h128),
    {
      method: 'GET',
      headers: { 'User-Agent': KG_UA, Referer: 'https://m.kugou.com/' },
    },
  )
  if (!data || typeof data !== 'object') return null

  const extra = data.extra && typeof data.extra === 'object' ? data.extra : {}
  const albumPic = pickHttpUrl(data.album_img) || pickHttpUrl(data.imgUrl)
  const record = {
    at: Date.now(),
    h128: h128,
    h320: String(extra['320hash'] || '').trim(),
    hsq: String(extra['sqhash'] || '').trim(),
    direct: pickHttpUrl(data.url),
    pic: albumPic ? albumPic.replace(/\{size\}/g, '480') : '',
    name: String(data.fileName || data.songName || '').trim(),
    singer: String(data.author_name || data.singerName || '').trim(),
    duration: (Number(data.timeLength) || 0) * 1000,
    blocked: String(data.error || '').trim(),
  }

  const keys = Object.keys(kgInfoCache)
  if (keys.length > 200) {
    for (let i = 0; i < keys.length; i++) {
      if (Date.now() - kgInfoCache[keys[i]].at > 30 * 60 * 1000) delete kgInfoCache[keys[i]]
    }
  }

  kgInfoCache[h128] = record
  return record
}

// 某一档位该用哪个 hash；取不到就给空串，让调用方跳过这一档
function kgHashFor(musicInfo, meta, level, playInfo) {
  if (level === 'flac') {
    return (
      kgRead(musicInfo, meta, ['kgHashFlac', 'SQFileHash', 'sqhash']) ||
      (playInfo && playInfo.hsq) ||
      ''
    )
  }
  if (level === '320') {
    return (
      kgRead(musicInfo, meta, ['kgHash320', 'HQFileHash', '320hash', 'hash_high']) ||
      (playInfo && playInfo.h320) ||
      ''
    )
  }
  return kgRead(musicInfo, meta, ['hash', 'kgHash128', 'FileHash', 'songmid', 'id'])
}

// tracker 的 bitRate 是 bps，第三方接口有时给 kbps，先归一再判断。
function kgTypeFromBitrate(bitRate, extName) {
  const ext = String(extName || '').toLowerCase()
  if (ext === 'flac' || ext === 'ape' || ext === 'wav') return 'flac'
  const value = Number(bitRate) || 0
  const kbps = value > 10000 ? Math.round(value / 1000) : value
  if (kbps >= 300) return '320k'
  if (kbps >= 160) return '192k'
  return '128k'
}

function kgPickTrackerUrl(payload) {
  const raw = payload && payload.url
  const first = Array.isArray(raw) ? (raw.length ? raw[0] : '') : raw
  return pickHttpUrl(first)
}

async function kgRequestTracker(base, hash) {
  const key = kgMd5(hash + 'kgcloudv2')
  if (!key) return null
  const isBackup = base.indexOf('trackercdnbj') >= 0
  let query = isBackup ? 'cmd=23&pid=1&behavior=play' : 'appid=1005&pid=2&cmd=25&behavior=play'

  // 填了会员登录态就带上；匿名只能拿到非会员曲目
  const token = String(CONFIG.kgToken || '').trim()
  const userId = String(CONFIG.kgUserId || '').trim()
  if (token) query += '&token=' + encodeURIComponent(token)
  if (userId) query += '&userid=' + encodeURIComponent(userId)

  const data = await requestJson(
    base + '?' + query + '&hash=' + encodeURIComponent(hash) + '&key=' + key,
    {
      method: 'GET',
      headers: { 'User-Agent': KG_UA, Referer: 'https://www.kugou.com/' },
    },
  )
  if (!data || Number(data.status) !== 1) return null
  const url = kgPickTrackerUrl(data)
  if (!url) return null
  return { url: url, type: kgTypeFromBitrate(data.bitRate, data.extName) }
}

async function kgTrackerUrl(hash) {
  return (
    (await kgRequestTracker(KG_TRACKER_URL, hash)) ||
    (await kgRequestTracker(KG_TRACKER_BACKUP_URL, hash))
  )
}

// playInfo 偶尔直接给 url（免费曲目），作为最后兜底
function kgDirectUrl(playInfo) {
  if (!playInfo || !playInfo.direct) return null
  return { url: playInfo.direct, type: kwGuessType(playInfo.direct) }
}

function kgDurationMs(musicInfo) {
  const raw = musicInfo && musicInfo.interval
  if (typeof raw === 'number' && raw > 0) {
    return Math.round(raw > 1000 ? raw : raw * 1000)
  }
  if (typeof raw !== 'string') return 0
  const parts = raw.split(':')
  if (parts.length === 2) return (Number(parts[0]) * 60 + Number(parts[1])) * 1000
  if (parts.length === 3) {
    return (Number(parts[0]) * 3600 + Number(parts[1]) * 60 + Number(parts[2])) * 1000
  }
  return 0
}

function kgBase64Text(value) {
  try {
    const binary = atob(String(value || ''))
    const bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i) & 0xFF
    if (typeof TextDecoder === 'function') return new TextDecoder('utf-8').decode(bytes)
    let out = ''
    for (let i = 0; i < bytes.length; i++) out += String.fromCharCode(bytes[i])
    return out
  } catch (_) {
    return ''
  }
}

async function kgLyric(hash, musicInfo, playInfo) {
  const name = (musicInfo && musicInfo.name) || (playInfo && playInfo.name) || ''
  const singer = (musicInfo && musicInfo.singer) || (playInfo && playInfo.singer) || ''
  const keyword = [name, singer].filter(Boolean).join(' ')
  const duration = kgDurationMs(musicInfo) || (playInfo && playInfo.duration) || 0
  const query = [
    'ver=1',
    'man=yes',
    'client=mobi',
    'keyword=' + encodeURIComponent(keyword || ''),
    'duration=' + (duration || -1),
    'hash=' + encodeURIComponent(hash),
  ]
  const search = await requestJson(KG_LYRIC_SEARCH_URL + '?' + query.join('&'), {
    method: 'GET',
    headers: KG_LYRIC_HEADERS,
  })
  const candidates = search && search.candidates
  if (!Array.isArray(candidates) || !candidates.length) return null

  for (let i = 0; i < candidates.length; i++) {
    const candidate = candidates[i]
    if (!candidate || !candidate.id || !candidate.accesskey) continue
    const download = await requestJson(
      KG_LYRIC_DOWNLOAD_URL +
        '?ver=1&client=pc&fmt=lrc&charset=utf8&id=' +
        encodeURIComponent(candidate.id) +
        '&accesskey=' +
        encodeURIComponent(candidate.accesskey),
      { method: 'GET', headers: KG_LYRIC_HEADERS },
    )
    const lyric = kgBase64Text(download && download.content).replace(/^\uFEFF/, '')
    if (lyric.trim()) return { lyric: lyric }
  }
  return null
}

async function handleKg(action, info) {
  const musicInfo = (info && info.musicInfo) || {}
  const meta =
    musicInfo.meta && typeof musicInfo.meta === 'object' ? musicInfo.meta : {}
  const h128 = kgHashFor(musicInfo, meta, '128', null)
  if (!h128) return null

  // 顺手取一次官方 songinfo，补 320/无损 hash、封面与时长
  const playInfo = await kgPlayInfo(h128)

  if (action === 'pic') {
    const url = pickHttpUrl(musicInfo.img) || (playInfo && playInfo.pic) || ''
    return url ? { url: url } : null
  }

  if (action === 'lyric') return kgLyric(h128, musicInfo, playInfo)
  if (action !== 'musicUrl') return null

  const levels = KG_LEVELS[info && info.type]
  if (!levels) return null

  const tried = []
  for (let i = 0; i < levels.length; i++) {
    const hash = kgHashFor(musicInfo, meta, levels[i], playInfo)
    if (!hash || tried.indexOf(hash) >= 0) continue
    tried.push(hash)
    const result = await kgTrackerUrl(hash)
    if (result) return result
  }

  return kgDirectUrl(playInfo)
}

lx.on(lx.EVENT_NAMES.request, ({ action, source, info }) => {
  if (source === 'tx') return handleTx(action, info)
  if (source === 'wy') return handleWy(action, info)
  if (source === 'kw') return handleKw(action, info)
  if (source === 'kg') return handleKg(action, info)
  return null
})

lx.send(lx.EVENT_NAMES.inited, {
  status: true,
  sources: {
    tx: {
      type: 'music',
      actions: ['musicUrl', 'lyric'],
      qualitys: ['128k', '320k'],
    },
    wy: {
      type: 'music',
      actions: ['musicUrl', 'lyric', 'pic'],
      qualitys: ['128k', '320k', 'flac', 'flac24bit', 'hires'],
    },
    kw: {
      type: 'music',
      actions: ['musicUrl', 'lyric', 'pic'],
      qualitys: ['128k', '320k', 'flac', 'flac24bit', 'hires'],
    },
    kg: {
      type: 'music',
      actions: ['musicUrl', 'lyric', 'pic'],
      qualitys: ['128k', '320k', 'flac', 'flac24bit', 'hires'],
    },
  },
})
