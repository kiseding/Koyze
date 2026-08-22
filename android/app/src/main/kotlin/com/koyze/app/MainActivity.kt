package com.koyze.app

import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val channelName = "koyze/android_file_access"
    private val prefsName = "koyze_android_file_access"
    private val treeUriKey = "tree_uri"
    private var pendingPicker: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "selectDirectory" -> selectDirectory(result)
                    "writeFileBytes" -> {
                        val path = call.argument<String>("path")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (path == null || bytes == null) {
                            result.error("invalid_args", "Missing path or bytes", null)
                        } else {
                            result.success(writeFileBytes(path, bytes))
                        }
                    }
                    else -> result.notImplemented()
                }
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
        result.success(resolveTreePath(uri))
    }

    private fun resolveTreePath(uri: Uri): String? {
        val id = DocumentsContract.getTreeDocumentId(uri)
        val split = id.split(":", limit = 2)
        return if (split.size == 2 && split[0] == "primary") {
            "${android.os.Environment.getExternalStorageDirectory()}/${split[1]}"
        } else null
    }

    private fun writeFileBytes(path: String, bytes: ByteArray): Boolean {
        val tree = getSharedPreferences(prefsName, MODE_PRIVATE)
            .getString(treeUriKey, null)?.let(Uri::parse) ?: return false
        val root = resolveTreePath(tree) ?: return false
        val normalizedRoot = java.io.File(root).canonicalPath
        val normalizedPath = java.io.File(path).canonicalPath
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
        contentResolver.openFileDescriptor(document, "w")?.use { descriptor ->
            java.io.FileOutputStream(descriptor.fileDescriptor).use { output ->
                output.write(bytes)
                output.flush()
            }
        } ?: return false
        return true
    }
}
