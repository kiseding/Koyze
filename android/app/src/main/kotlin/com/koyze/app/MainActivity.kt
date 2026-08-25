package com.koyze.app

import android.content.ContentUris
import android.content.Intent
import android.database.Cursor
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.URLDecoder

class MainActivity : AudioServiceActivity() {
    private val channelName = "koyze/android_file_access"
    private val prefsName = "koyze_android_file_access"
    private val treeUriKey = "tree_uri"
    private val mediaStoreBitrateColumn = "bitrate"
    private var pendingPicker: MethodChannel.Result? = null
    private var pendingImportedAudio: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "selectDirectory" -> selectDirectory(result)
                    "scanMediaStore" -> respondAsync(result) { scanMediaStore() }
                    "scanSelectedDirectory" -> respondAsync(result) { scanSelectedDirectory() }
                    "externalStorageRoot" -> result.success(
                        Environment.getExternalStorageDirectory().absolutePath,
                    )
                    "isExternalStorageManager" -> result.success(hasAllFilesAccess())
                    "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                    "openBatteryOptimizationSettings" -> {
                        openBatteryOptimizationSettings()
                        result.success(null)
                    }
                    "pendingImportedAudio" -> {
                        result.success(pendingImportedAudio)
                        pendingImportedAudio = null
                    }
                    "writeFileBytes" -> {
                        val path = call.argument<String>("path")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (path == null || bytes == null) {
                            result.error("invalid_args", "Missing path or bytes", null)
                        } else {
                            result.success(writeFileBytes(path, bytes))
                        }
                    }
                    "readFileBytes" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("invalid_args", "Missing path", null)
                        } else {
                            result.success(readFileBytes(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun <T> respondAsync(result: MethodChannel.Result, block: () -> T) {
        Thread {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error(
                        "android_file_access_failed",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }.start()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureImportedAudio(intent)
    }

    override fun onResume() {
        super.onResume()
        captureImportedAudio(intent)
    }

    private fun captureImportedAudio(intent: Intent?) {
        if (intent == null) return
        val uri = intent.data ?: return
        val action = intent.action ?: return
        if (action != Intent.ACTION_VIEW && action != Intent.ACTION_SEND) return
        val mimeType = intent.type.orEmpty()
        val name = displayNameForUri(uri) ?: uri.lastPathSegment?.let { URLDecoder.decode(it, "UTF-8") } ?: "audio"
        if (!isAudioDocument(name, mimeType.takeIf { it.isNotBlank() })) return
        pendingImportedAudio = mapOf(
            "path" to uri.toString(),
            "contentUri" to uri.toString(),
            "fileName" to name,
            "extension" to extensionOf(name),
            "size" to sizeForUri(uri),
            "modifiedAtMillis" to System.currentTimeMillis(),
            "title" to titleFromFileName(name),
            "artist" to "未知歌手",
            "album" to "",
            "durationMillis" to 0L,
            "mimeType" to mimeType,
            "androidSource" to "externalIntent",
        )
    }

    private fun displayNameForUri(uri: Uri): String? {
        contentResolver.query(
            uri,
            arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return null
    }

    private fun sizeForUri(uri: Uri): Long {
        contentResolver.query(
            uri,
            arrayOf(android.provider.OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getLong(0)
        }
        return 0L
    }

    private fun hasAllFilesAccess(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            Environment.isExternalStorageManager()
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }

    private fun openBatteryOptimizationSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        if (intent.resolveActivity(packageManager) != null) {
            startActivity(intent)
        } else {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }

    private fun selectDirectory(result: MethodChannel.Result) {
        if (pendingPicker != null) {
            result.error("already_active", "Directory picker is already open", null)
            return
        }
        pendingPicker = result
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }, 8417)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 8417) return
        val result = pendingPicker ?: return
        pendingPicker = null
        if (resultCode != RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        val uri = data.data!!
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {}
        getSharedPreferences(prefsName, MODE_PRIVATE).edit()
            .putString(treeUriKey, uri.toString()).apply()
        result.success(resolveTreePath(uri) ?: uri.toString())
    }

    private fun resolveTreePath(uri: Uri): String? {
        val id = DocumentsContract.getTreeDocumentId(uri)
        val split = id.split(":", limit = 2)
        return if (split.size == 2 && split[0] == "primary") {
            val suffix = split[1].trim('/')
            val root = Environment.getExternalStorageDirectory().absolutePath
            if (suffix.isEmpty()) root else "$root/$suffix"
        } else null
    }

    private fun scanMediaStore(): List<Map<String, Any?>> {
        val projection = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.MIME_TYPE,
            MediaStore.Audio.Media.DATA,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.Audio.Media.RELATIVE_PATH)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            projection.add(mediaStoreBitrateColumn)
        }
        val tracks = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection.toTypedArray(),
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.DATE_MODIFIED} DESC",
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val contentUri = ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    id,
                )
                val displayName = cursorString(cursor, MediaStore.Audio.Media.DISPLAY_NAME)
                    ?: contentUri.lastPathSegment
                    ?: "audio-$id"
                val dataPath = cursorString(cursor, MediaStore.Audio.Media.DATA)
                val path = dataPath?.takeIf { it.isNotBlank() } ?: contentUri.toString()
                tracks.add(
                    mapOf(
                        "path" to path,
                        "contentUri" to contentUri.toString(),
                        "fileName" to displayName,
                        "extension" to extensionOf(displayName.ifBlank { path }),
                        "size" to cursorLong(cursor, MediaStore.Audio.Media.SIZE),
                        "modifiedAtMillis" to cursorLong(cursor, MediaStore.Audio.Media.DATE_MODIFIED) * 1000L,
                        "title" to cleanMetadataText(cursorString(cursor, MediaStore.Audio.Media.TITLE))
                            .orEmpty().ifBlank { titleFromFileName(displayName) },
                        "artist" to cleanMetadataText(cursorString(cursor, MediaStore.Audio.Media.ARTIST))
                            .orEmpty().ifBlank { "未知歌手" },
                        "album" to cleanMetadataText(cursorString(cursor, MediaStore.Audio.Media.ALBUM)).orEmpty(),
                        "durationMillis" to cursorLong(cursor, MediaStore.Audio.Media.DURATION),
                        "bitrate" to cursorOptionalLong(cursor, mediaStoreBitrateColumn),
                        "mimeType" to cursorString(cursor, MediaStore.Audio.Media.MIME_TYPE),
                        "androidSource" to "mediaStore",
                    ),
                )
            }
        }
        return tracks
    }

    private fun scanSelectedDirectory(): List<Map<String, Any?>> {
        val tree = getSharedPreferences(prefsName, MODE_PRIVATE)
            .getString(treeUriKey, null)?.let(Uri::parse) ?: return emptyList()
        val root = resolveTreePath(tree)
        val tracks = mutableListOf<Map<String, Any?>>()
        scanTreeDocument(
            tree = tree,
            documentId = DocumentsContract.getTreeDocumentId(tree),
            rootPath = root,
            relativeSegments = emptyList(),
            tracks = tracks,
        )
        return tracks
    }

    private fun scanTreeDocument(
        tree: Uri,
        documentId: String,
        rootPath: String?,
        relativeSegments: List<String>,
        tracks: MutableList<Map<String, Any?>>,
    ) {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId)
        contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
            val modifiedCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (cursor.moveToNext()) {
                val childId = cursor.getString(idCol)
                val name = cursor.getString(nameCol) ?: continue
                val mimeType = cursor.getString(mimeCol)
                val nextSegments = relativeSegments + name
                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    scanTreeDocument(tree, childId, rootPath, nextSegments, tracks)
                    continue
                }
                if (!isAudioDocument(name, mimeType)) continue
                val documentUri = DocumentsContract.buildDocumentUriUsingTree(tree, childId)
                val metadata = readDocumentMetadata(documentUri)
                val path = rootPath?.let { root ->
                    val normalizedRoot = root.trimEnd('/')
                    "$normalizedRoot/${nextSegments.joinToString("/")}"
                } ?: documentUri.toString()
                tracks.add(
                    mapOf(
                        "path" to path,
                        "contentUri" to documentUri.toString(),
                        "fileName" to name,
                        "extension" to extensionOf(name),
                        "size" to cursorLong(cursor, sizeCol),
                        "modifiedAtMillis" to cursorLong(cursor, modifiedCol),
                        "title" to metadata.title.ifBlank { titleFromFileName(name) },
                        "artist" to metadata.artist.ifBlank { "未知歌手" },
                        "album" to metadata.album,
                        "durationMillis" to metadata.durationMillis,
                        "bitrate" to metadata.bitrate,
                        "mimeType" to mimeType,
                        "androidSource" to "saf",
                        "safRoot" to rootPath,
                    ),
                )
            }
        }
    }

    private data class AudioMetadata(
        val title: String = "",
        val artist: String = "",
        val album: String = "",
        val durationMillis: Long = 0,
        val bitrate: Long? = null,
    )

    private fun readDocumentMetadata(uri: Uri): AudioMetadata {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, uri)
            AudioMetadata(
                title = cleanMetadataText(
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE),
                ).orEmpty(),
                artist = cleanMetadataText(
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST),
                ).orEmpty(),
                album = cleanMetadataText(
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM),
                ).orEmpty(),
                durationMillis = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_DURATION,
                )?.toLongOrNull() ?: 0,
                bitrate = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_BITRATE,
                )?.toLongOrNull(),
            )
        } catch (_: Throwable) {
            AudioMetadata()
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {}
        }
    }

    private fun cursorString(cursor: Cursor, column: String): String? {
        val index = cursor.getColumnIndex(column)
        if (index < 0 || cursor.isNull(index)) return null
        return cursor.getString(index)
    }

    private fun cursorLong(cursor: Cursor, column: String): Long {
        val index = cursor.getColumnIndex(column)
        return cursorLong(cursor, index)
    }

    private fun cursorLong(cursor: Cursor, index: Int): Long {
        if (index < 0 || cursor.isNull(index)) return 0L
        return cursor.getLong(index)
    }

    private fun cursorOptionalLong(cursor: Cursor, column: String): Long? {
        val index = cursor.getColumnIndex(column)
        if (index < 0 || cursor.isNull(index)) return null
        return cursor.getLong(index)
    }

    private fun cleanMetadataText(value: String?): String? {
        val text = value?.trim().orEmpty()
        if (text.isEmpty() || text == "<unknown>") return null
        return text
    }

    private fun titleFromFileName(name: String): String {
        val base = name.substringBeforeLast('.', name)
        val match = Regex("(.+)-[0-9A-Za-z]{8}-\\d+$").matchEntire(base)
        return match?.groupValues?.getOrNull(1)?.takeIf { it.isNotBlank() } ?: base
    }

    private fun extensionOf(name: String): String {
        val dot = name.lastIndexOf('.')
        return if (dot >= 0 && dot < name.length - 1) {
            name.substring(dot + 1).lowercase()
        } else {
            ""
        }
    }

    private fun isAudioDocument(name: String, mimeType: String?): Boolean {
        if (mimeType?.startsWith("audio/") == true) return true
        return extensionOf(name) in setOf(
            "mp3", "flac", "m4a", "aac", "wav", "ogg", "opus", "wma", "ape", "aiff", "alac",
        )
    }

    private fun writeFileBytes(path: String, bytes: ByteArray): Boolean {
        val tree = getSharedPreferences(prefsName, MODE_PRIVATE)
            .getString(treeUriKey, null)?.let(Uri::parse) ?: return false
        val root = resolveTreePath(tree) ?: return false
        val normalizedRoot = File(root).canonicalPath
        val normalizedPath = File(path).canonicalPath
        if (!normalizedPath.startsWith("$normalizedRoot/")) return false
        val relative = normalizedPath.removePrefix("$normalizedRoot/")
        val segments = relative.split('/').filter { it.isNotEmpty() }
        var current = DocumentsContract.getTreeDocumentId(tree)
        for (segment in segments) {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(
                tree, current,
            )
            contentResolver.query(
                children,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                "${DocumentsContract.Document.COLUMN_DISPLAY_NAME} = ?",
                arrayOf(segment),
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return false
                current = cursor.getString(0)
            } ?: return false
        }
        val document = DocumentsContract.buildDocumentUriUsingTree(tree, current)
        contentResolver.openFileDescriptor(document, "rwt")?.use { descriptor ->
            FileOutputStream(descriptor.fileDescriptor).use { output ->
                output.write(bytes)
                output.flush()
            }
        } ?: return false
        return true
    }

    private fun readFileBytes(path: String): ByteArray? {
        val tree = getSharedPreferences(prefsName, MODE_PRIVATE)
            .getString(treeUriKey, null)?.let(Uri::parse) ?: return null
        val root = resolveTreePath(tree) ?: return null
        val normalizedRoot = File(root).canonicalPath
        val normalizedPath = File(path).canonicalPath
        if (!normalizedPath.startsWith("$normalizedRoot/")) return null
        val relative = normalizedPath.removePrefix("$normalizedRoot/")
        val segments = relative.split('/').filter { it.isNotEmpty() }
        var current = DocumentsContract.getTreeDocumentId(tree)
        for (segment in segments) {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, current)
            contentResolver.query(
                children,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                "${DocumentsContract.Document.COLUMN_DISPLAY_NAME} = ?",
                arrayOf(segment),
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                current = cursor.getString(0)
            } ?: return null
        }
        val document = DocumentsContract.buildDocumentUriUsingTree(tree, current)
        return contentResolver.openInputStream(document)?.use { it.readBytes() }
    }
}
