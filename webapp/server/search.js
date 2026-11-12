'use strict'

const { safeFetch, log } = require('./util')

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

function cleanText(value) {
  return String(value || '').replace(/<[^>]+>/g, '').trim()
}

async function searchKugou(keyword, page) {
  const url = 'https://songsearch.kugou.com/song_search_v2?' +
    new URLSearchParams({
      keyword: String(keyword),
      page: String(page),
      pagesize: '20',
      showtype: '1',
    }).toString()

  const { response } = await safeFetch(url, {
    headers: { 'User-Agent': UA, Referer: 'https://www.kugou.com/' },
    timeout: 12000,
  })
  if (!response.ok) throw new Error('kugou search returned HTTP ' + response.status)
  const data = await response.json()
  const lists = (data && data.data && data.data.lists) || []

  return lists.map((item) => {
    const hash = String(item.FileHash || item.HQFileHash || '').trim()
    const hq = String(item.HQFileHash || '').trim()
    const sq = String(item.SQFileHash || '').trim()
    return {
      id: hash,
      name: cleanText(item.SongName),
      singer: cleanText(item.SingerName),
      album: cleanText(item.AlbumName),
      interval: Number(item.Duration) || 0,
      payType: Number(item.PayType) || 0,
      privilege: Number(item.Privilege) || 0,
      img: '',
      musicInfo: {
        hash,
        songmid: hash,
        id: hash,
        name: cleanText(item.SongName),
        singer: cleanText(item.SingerName),
        album: cleanText(item.AlbumName),
        interval: Number(item.Duration) || 0,
        img: '',
        meta: {
          HQFileHash: hq,
          SQFileHash: sq,
          '320hash': hq,
          sqhash: sq,
        },
      },
    }
  })
}

const BUILTIN = { kg: searchKugou }

async function search(runtime, payload) {
  const keyword = String(payload.keyword || '').trim()
  if (!keyword) throw new Error('keyword is required')
  if (keyword.length > 120) throw new Error('keyword is too long')

  const page = Math.min(10, Math.max(1, Number(payload.page) || 1))
  const source = String(payload.source || 'kg')

  // 优先把搜索交给音源脚本自己实现（LX 协议允许脚本声明 search action）。
  const declared = runtime.registry[source]
  if (declared && Array.isArray(declared.actions) && declared.actions.includes('search')) {
    const result = await runtime.invoke(source, 'search', { keyword, page })
    if (Array.isArray(result)) return { source, list: result, provider: 'script' }
    if (result && Array.isArray(result.list)) {
      return { source, list: result.list, provider: 'script' }
    }
  }

  const provider = BUILTIN[source]
  if (!provider) {
    // 脚本没实现 search、该平台也没有内置实现时，不要 502。
    // 退回默认内置源（酷狗）搜同一串关键词：用户看到的仍是结果列表，
    // 而不是一个「no search provider」的服务端错误。
    const fallback = BUILTIN[String(payload.fallbackSource || 'kg')]
    if (!fallback) {
      throw new Error('no search provider for "' + source +
        '". Built-in providers: ' + Object.keys(BUILTIN).join(', '))
    }
    const list = await fallback(keyword, page)
    log('search', source, JSON.stringify(keyword), '->', list.length,
      'results (fell back to builtin)', payload.fallbackSource || 'kg')
    return { source, list, provider: 'builtin', fellBackFrom: source }
  }

  const list = await provider(keyword, page)
  log('search', source, JSON.stringify(keyword), '->', list.length, 'results')
  return { source, list, provider: 'builtin' }
}

module.exports = { search, BUILTIN }
