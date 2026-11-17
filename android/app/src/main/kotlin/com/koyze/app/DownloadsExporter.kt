package com.koyze.app

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * 把应用私有目录里的文件导出到系统「下载/Koyze」。
 *
 * Android 9 及以下没有 `MediaStore.Downloads`，只能拿
 * `Environment.getExternalStoragePublicDirectory(DIRECTORY_DOWNLOADS)` 写真实
 * 路径，并且需要 `WRITE_EXTERNAL_STORAGE`（应用已经声明了
 * `MANAGE_EXTERNAL_STORAGE` 兜底，但那是给「扫描本地音乐」用的，普通手机
 * 不会主动给；所以老系统这条路上写入可能被拒，调用方要能接住异常）。
 *
 * Android 10 起走 `MediaStore`：**不需要任何存储权限**，文件落在
 * `Download/Koyze/`，用户在文件管理器里直接可见，卸载应用也不会带走。
 * 这是唯一既免权限、又能让用户看见的方式。
 */
internal class DownloadsExporter(private val context: Context) {

  /**
   * 复制 [sourcePath] 到公共下载目录。
   *
   * 返回落地后的可读路径（用于界面提示）；同一个文件名已存在时覆盖。
   *
   * MediaStore 的 `DISPLAY_NAME` 是「文件名」，`RELATIVE_PATH` 是相对
   * `Download/` 的子目录，两者拼起来才是用户在文件管理器里看到的位置。
   */
  fun export(sourcePath: String): String {
    val source = File(sourcePath)
    if (!source.isFile) {
      throw IllegalArgumentException("要导出的文件不存在：$sourcePath")
    }
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      exportViaMediaStore(source)
    } else {
      exportViaLegacyDirectory(source)
    }
  }

  private fun exportViaMediaStore(source: File): String {
    val resolver = context.contentResolver
    val collection = MediaStore.Downloads.getContentUri(
      MediaStore.VOLUME_EXTERNAL_PRIMARY
    )
    // RELATIVE_PATH 必须以斜杠结尾：系统存的就是 "Download/Koyze/"，不带
    // 结尾斜杠去查（甚至去插）都匹配不上已有条目。
    val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER_NAME/"
    // 同名旧条目先删掉。复用旧 Uri 再写入的话，`openOutputStream("wt")`
    // 在各家实现上行为不一致（有的不截断，会留下旧文件尾巴），而且旧条目
    // 的 MIME 可能是错的（早期版本没写对扩展名映射）。删了重建最干净。
    deleteExisting(collection, source.name, relativePath)

    val values = ContentValues().apply {
      put(MediaStore.MediaColumns.DISPLAY_NAME, source.name)
      put(MediaStore.MediaColumns.MIME_TYPE, mimeTypeOf(source.name))
      put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
      // 写入期间标记 pending：文件管理器在复制完成前看不到这个半成品。
      put(MediaStore.MediaColumns.IS_PENDING, 1)
    }
    val uri = resolver.insert(collection, values)
      ?: throw IllegalStateException("系统没有给出可写入的下载位置")

    try {
      resolver.openOutputStream(uri, "wt")?.use { output ->
        source.inputStream().use { input -> input.copyTo(output) }
      } ?: throw IllegalStateException("打不开下载位置的写入流")
      val ready = ContentValues().apply {
        put(MediaStore.MediaColumns.IS_PENDING, 0)
      }
      resolver.update(uri, ready, null, null)
    } catch (error: Throwable) {
      // 半成品留在「下载」里比没有更难解释（用户会看到一个 0 字节的歌），
      // 写失败就把这条记录删掉。
      runCatching { resolver.delete(uri, null, null) }
      throw error
    }
    return "${Environment.getExternalStorageDirectory().path}/$relativePath${source.name}"
  }

  /**
   * 删掉「下载/Koyze」里同名的旧条目（如果有）。
   *
   * 同一个 RELATIVE_PATH 下同名文件可能不止一条（用户手动复制过、旧版本
   * 留下的），所以按游标遍历全删，而不是只删第一条。
   */
  private fun deleteExisting(
    collection: Uri,
    displayName: String,
    relativePath: String,
  ) {
    val projection = arrayOf(MediaStore.MediaColumns._ID)
    val selection =
      "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND " +
        "${MediaStore.MediaColumns.RELATIVE_PATH}=?"
    val args = arrayOf(displayName, relativePath)
    val ids = mutableListOf<Long>()
    context.contentResolver.query(collection, projection, selection, args, null)
      ?.use { cursor ->
        while (cursor.moveToNext()) {
          ids.add(cursor.getLong(0))
        }
      }
    for (id in ids) {
      runCatching {
        context.contentResolver.delete(
          ContentUris.withAppendedId(collection, id),
          null,
          null,
        )
      }
    }
  }

  private fun exportViaLegacyDirectory(source: File): String {
    @Suppress("DEPRECATION")
    val downloads = Environment.getExternalStoragePublicDirectory(
      Environment.DIRECTORY_DOWNLOADS
    )
    val target = File(File(downloads, FOLDER_NAME), source.name)
    target.parentFile?.mkdirs()
    // 覆盖式：先删旧文件，否则 copyTo 会追加到末尾把文件写坏。
    if (target.exists()) {
      if (!target.delete()) {
        throw IllegalStateException("无法覆盖已存在的文件：${target.path}")
      }
    }
    source.copyTo(target, overwrite = true)
    return target.path
  }

  /**
   * 按扩展名给 MIME。音频必须给对类型，否则系统「下载」里的条目点开会
   * 被当成二进制文件，其他播放器也不会把它列进音乐库。
   */
  private fun mimeTypeOf(name: String): String =
    when (name.substringAfterLast('.', "").lowercase()) {
      "mp3" -> "audio/mpeg"
      "m4a", "aac" -> "audio/mp4"
      "flac" -> "audio/flac"
      "wav" -> "audio/wav"
      "ogg", "opus" -> "audio/ogg"
      "ape" -> "audio/x-ape"
      "wma" -> "audio/x-ms-wma"
      "jpg", "jpeg" -> "image/jpeg"
      "png" -> "image/png"
      "webp" -> "image/webp"
      "lrc" -> "text/plain"
      else -> "application/octet-stream"
    }

  private companion object {
    /// 公共「下载」下的子目录名，与桌面端保持一致。
    const val FOLDER_NAME = "Koyze"
  }
}
