package com.koyze.app

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File

/**
 * 目标目录里已经有同名文件。
 *
 * 单独定义而不是复用 [java.io.IOException]：调用方需要把「重名」和「没权限」
 * 分开提示，前者用户可以改名重试，后者只能去设置里重新授权。
 */
internal class SafFileConflictException(val path: String) : Exception("目标位置已存在同名文件")

/**
 * 当前没有可用的 SAF 授权树，或路径解析不出来。
 */
internal class SafAccessDeniedException(val path: String) : Exception("没有权限访问该路径")

/**
 * Android SAF 文件操作。
 *
 * 本地音乐目录在 Android 上是一个 `content://` 树（用户通过
 * `ACTION_OPEN_DOCUMENT_TREE` 授权的目录），Dart 侧拿不到真实路径，
 * 所有操作必须经 ContentResolver 转发。
 *
 * 几个绕不开的限制：
 *
 * - **没有 move API**。`DocumentsContract` 只提供 copy/rename/delete，
 *   所以「移动」只能是「复制到目标目录 → 删除源文件」，中途失败会留下
 *   一份副本，调用方要能接受这个中间态。
 * - **rename 只能在同一个父目录内**。跨目录改名要拆成 copy + delete。
 * - **创建文件要先建文档再写入**，不能像 POSIX 那样 open(O_CREAT)。
 */
internal class SafFileAccess(
    private val context: Context,
    private val treeUri: () -> Uri?,
) {
    private val resolver: ContentResolver get() = context.contentResolver

    fun listDirectory(path: String): List<Map<String, Any?>> {
        val tree = treeUri() ?: return emptyList()
        val documentId = resolveDocumentId(tree, path) ?: return emptyList()
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, documentId,
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val entries = mutableListOf<Map<String, Any?>>()
        resolver.query(children, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: continue
                val mime = cursor.getString(2) ?: ""
                entries.add(
                    mapOf(
                        "name" to name,
                        // 目录没有稳定路径，用 documentId 当路径标识；
                        // 上层只需要能把它传回本类做后续操作。
                        "path" to buildPathFor(tree, id, name),
                        "isDirectory" to (mime == DocumentsContract.Document.MIME_TYPE_DIR),
                        "size" to cursor.getLong(3),
                        "modifiedAt" to cursor.getLong(4),
                    ),
                )
            }
        }
        return entries
    }

    fun copyInto(sourcePath: String, targetDirectory: String): String {
        val tree = treeUri() ?: throw SafAccessDeniedException(sourcePath)
        val source = resolveDocumentId(tree, sourcePath)
            ?: throw SafAccessDeniedException(sourcePath)
        val target = resolveDocumentId(tree, targetDirectory)
            ?: throw SafAccessDeniedException(targetDirectory)
        val name = displayName(tree, source)
            ?: throw SafAccessDeniedException(sourcePath)
        // 重名直接拒绝，绝不静默覆盖——用户搬文件最怕同名文件被悄悄换掉。
        if (findChildId(tree, DocumentsContract.getDocumentId(target), name) != null) {
            throw SafFileConflictException("$targetDirectory/$name")
        }
        val created = DocumentsContract.createDocument(
            resolver, target, mimeOf(tree, source), name,
        ) ?: throw SafAccessDeniedException(targetDirectory)
        if (!copyContent(tree, source, created)) {
            runCatching { DocumentsContract.deleteDocument(resolver, created) }
            throw SafAccessDeniedException(sourcePath)
        }
        return buildPathFor(tree, DocumentsContract.getDocumentId(created), name)
    }

    fun moveInto(sourcePath: String, targetDirectory: String): String {
        val tree = treeUri() ?: throw SafAccessDeniedException(sourcePath)
        val source = resolveDocumentId(tree, sourcePath)
            ?: throw SafAccessDeniedException(sourcePath)
        val target = resolveDocumentId(tree, targetDirectory)
            ?: throw SafAccessDeniedException(targetDirectory)
        val name = displayName(tree, source)
            ?: throw SafAccessDeniedException(sourcePath)
        // 先尝试同父目录内的 rename（不产生副本，失败风险最小）。
        val sourceParent = DocumentsContract.getDocumentId(source).substringBeforeLast('/', "")
        val targetId = DocumentsContract.getDocumentId(target)
        if (sourceParent.isNotEmpty() && sourceParent == targetId) {
            // 同目录「移动」等于什么都不做，直接返回原位置。
            return buildPathFor(tree, DocumentsContract.getDocumentId(source), name)
        }
        if (findChildId(tree, targetId, name) != null) {
            throw SafFileConflictException("$targetDirectory/$name")
        }
        // 跨目录：copy + delete。中间态会短暂多出一份副本。
        val created = DocumentsContract.createDocument(
            resolver, target, mimeOf(tree, source), name,
        ) ?: throw SafAccessDeniedException(targetDirectory)
        if (!copyContent(tree, source, created)) {
            runCatching { DocumentsContract.deleteDocument(resolver, created) }
            throw SafAccessDeniedException(sourcePath)
        }
        val removed = runCatching {
            DocumentsContract.deleteDocument(resolver, source)
        }.getOrDefault(false)
        if (!removed) {
            // 源没删掉，副本已经在目标位置：整体算失败，把副本也清掉，
            // 避免用户看到两份而不知道哪份是真的。
            runCatching { DocumentsContract.deleteDocument(resolver, created) }
            throw SafAccessDeniedException(sourcePath)
        }
        return buildPathFor(tree, DocumentsContract.getDocumentId(created), name)
    }

    fun rename(sourcePath: String, newName: String): String {
        val tree = treeUri() ?: throw SafAccessDeniedException(sourcePath)
        val source = resolveDocumentId(tree, sourcePath)
            ?: throw SafAccessDeniedException(sourcePath)
        val renamed = DocumentsContract.renameDocument(resolver, source, newName)
            ?: throw SafAccessDeniedException(sourcePath)
        return buildPathFor(tree, DocumentsContract.getDocumentId(renamed), newName)
    }

    fun deleteFile(path: String): Boolean {
        val tree = treeUri() ?: return false
        val document = resolveDocumentId(tree, path) ?: return false
        return runCatching {
            DocumentsContract.deleteDocument(resolver, document)
        }.getOrDefault(false)
    }

    fun createDirectory(parentPath: String, name: String): String {
        val tree = treeUri() ?: throw SafAccessDeniedException(parentPath)
        val parent = resolveDocumentId(tree, parentPath)
            ?: throw SafAccessDeniedException(parentPath)
        val parentId = DocumentsContract.getDocumentId(parent)
        if (findChildId(tree, parentId, name) != null) {
            throw SafFileConflictException("$parentPath/$name")
        }
        val created = DocumentsContract.createDocument(
            resolver, parent, DocumentsContract.Document.MIME_TYPE_DIR, name,
        ) ?: throw SafAccessDeniedException(parentPath)
        return buildPathFor(tree, DocumentsContract.getDocumentId(created), name)
    }

    fun exists(path: String): Boolean {
        val tree = treeUri() ?: return false
        return resolveDocumentId(tree, path) != null
    }

    /**
     * 跨越「应用私有目录」与「SAF 授权树」搬运文件。
     *
     * 这一路 Dart 侧做不了：`File` 打不开 `content://`，而私有目录又不在
     * 任何 SAF 树里。所以两边各用各的 IO，中间靠流对接。
     *
     * 典型场景：用户把「音乐」目录作为 SAF 树扫进曲库，现在想把某首歌搬到
     * 下载目录去分享——源是 `content://`，目标是普通路径。
     *
     * @param move true 时复制成功后删除源。
     */
    fun transferAcross(
        sourcePath: String,
        targetDirectory: String,
        move: Boolean,
    ): String {
        val sourceIsDocument = isDocumentPath(sourcePath)
        val targetIsDocument = isDocumentPath(targetDirectory)
        if (sourceIsDocument == targetIsDocument) {
            throw IllegalArgumentException("transferAcross 只处理跨源搬运")
        }

        // 文件名必须问 provider 要，不能从路径里切：`content://koyze/<root>/<docId>`
        // 的最后一段是 documentId（形如 `primary:Music/a.mp3`），不是文件名。
        val name = if (sourceIsDocument) {
            val tree = treeUri() ?: throw SafAccessDeniedException(sourcePath)
            val document = resolveDocumentId(tree, sourcePath)
                ?: throw SafAccessDeniedException(sourcePath)
            displayName(tree, document) ?: throw SafAccessDeniedException(sourcePath)
        } else {
            File(sourcePath).name
        }
        if (name.isEmpty()) throw SafAccessDeniedException(sourcePath)

        if (targetIsDocument) {
            val created = createDocumentInTree(targetDirectory, name)
                ?: throw SafAccessDeniedException(targetDirectory)
            if (!pipeInto(sourcePath, sourceIsDocument, created, true)) {
                runCatching { DocumentsContract.deleteDocument(resolver, created) }
                throw SafAccessDeniedException(sourcePath)
            }
            if (move && !deleteSource(sourcePath, sourceIsDocument)) {
                runCatching { DocumentsContract.deleteDocument(resolver, created) }
                throw SafAccessDeniedException(sourcePath)
            }
            return buildPathFor(treeUri()!!, DocumentsContract.getDocumentId(created), name)
        }

        val directory = File(targetDirectory)
        if (!directory.exists() && !directory.mkdirs()) {
            throw SafAccessDeniedException(targetDirectory)
        }
        val target = File(directory, name)
        if (target.exists()) throw SafFileConflictException(target.absolutePath)
        if (!pipeInto(sourcePath, sourceIsDocument, Uri.fromFile(target), false)) {
            runCatching { target.delete() }
            throw SafAccessDeniedException(sourcePath)
        }
        if (move && !deleteSource(sourcePath, sourceIsDocument)) {
            runCatching { target.delete() }
            throw SafAccessDeniedException(sourcePath)
        }
        return target.absolutePath
    }

    /// 把源字节灌进目标。[targetIsDocument] 决定目标用 ContentResolver 还是 File。
    private fun pipeInto(
        sourcePath: String,
        sourceIsDocument: Boolean,
        target: Uri,
        targetIsDocument: Boolean,
    ): Boolean = runCatching {
        val input = if (sourceIsDocument) {
            val tree = treeUri() ?: return@runCatching false
            val document = resolveDocumentId(tree, sourcePath) ?: return@runCatching false
            resolver.openInputStream(document) ?: return@runCatching false
        } else {
            val file = File(sourcePath)
            if (!file.exists()) return@runCatching false
            file.inputStream()
        }
        input.use { from ->
            val output = if (targetIsDocument) {
                resolver.openOutputStream(target, "w")
            } else {
                File(target.path!!).outputStream()
            } ?: return@runCatching false
            output.use { to ->
                from.copyTo(to, DEFAULT_BUFFER_SIZE)
                to.flush()
            }
        }
        true
    }.getOrDefault(false)

    /// 删源。删不掉时调用方负责回滚目标副本。
    private fun deleteSource(path: String, isDocument: Boolean): Boolean = runCatching {
        if (isDocument) {
            val tree = treeUri() ?: return@runCatching false
            val document = resolveDocumentId(tree, path) ?: return@runCatching false
            DocumentsContract.deleteDocument(resolver, document)
        } else {
            File(path).delete()
        }
    }.getOrDefault(false)

    private fun isDocumentPath(path: String): Boolean =
        path.startsWith("content://") || path.startsWith("koyze://")

    private fun createDocumentInTree(targetDirectory: String, name: String): Uri? {
        val tree = treeUri() ?: return null
        val parent = resolveDocumentId(tree, targetDirectory) ?: return null
        val parentId = DocumentsContract.getDocumentId(parent)
        if (findChildId(tree, parentId, name) != null) {
            throw SafFileConflictException("$targetDirectory/$name")
        }
        // 跨源搬运的目标一定是音频，用通用二进制类型即可——SAF 只按 MIME
        // 决定图标和默认打开方式，不影响读写。
        return DocumentsContract.createDocument(
            resolver, parent, "application/octet-stream", name,
        )
    }

    /** 把 `content://` 树里的 documentId 拼成一个可传回本类的字符串。 */
    private fun buildPathFor(tree: Uri, documentId: String, name: String): String {
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        return "content://koyze/$rootId/$documentId"
    }

    /**
     * 把本类生成的路径字符串还原成 document URI。
     *
     * 路径里已经带着完整 documentId，不需要逐级查 children——这比按名字
     * 一层层找快得多，也不会因为同名文件而认错。
     */
    private fun resolveDocumentId(tree: Uri, path: String): Uri? {
        if (path.startsWith("content://koyze/")) {
            val parts = path.removePrefix("content://koyze/").split("/", limit = 2)
            if (parts.size == 2) {
                return DocumentsContract.buildDocumentUriUsingTree(tree, parts[1])
            }
        }
        // 普通文件路径（MediaStore 扫描出来的）：逐级解析到 documentId。
        val root = resolveTreeRoot(tree) ?: return null
        val normalizedRoot = File(root).canonicalPath
        val normalizedPath = runCatching { File(path).canonicalPath }.getOrNull()
            ?: return null
        if (!normalizedPath.startsWith("$normalizedRoot/")) return null
        var current = DocumentsContract.getTreeDocumentId(tree)
        for (segment in normalizedPath.removePrefix("$normalizedRoot/").split('/')) {
            if (segment.isEmpty()) continue
            current = findChildId(tree, current, segment) ?: return null
        }
        return DocumentsContract.buildDocumentUriUsingTree(tree, current)
    }

    private fun findChildId(tree: Uri, parentId: String, name: String): String? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        resolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            ),
            "${DocumentsContract.Document.COLUMN_DISPLAY_NAME} = ?",
            arrayOf(name),
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return null
    }

    private fun displayName(tree: Uri, document: Uri): String? {
        resolver.query(
            document,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return null
    }

    private fun mimeOf(tree: Uri, document: Uri): String {
        resolver.query(
            document,
            arrayOf(DocumentsContract.Document.COLUMN_MIME_TYPE),
            null, null, null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getString(0)
                    ?: "application/octet-stream"
            }
        }
        return "application/octet-stream"
    }

    private fun copyContent(tree: Uri, source: Uri, target: Uri): Boolean {
        return runCatching {
            resolver.openInputStream(source)?.use { input ->
                resolver.openOutputStream(target, "w")?.use { output ->
                    input.copyTo(output, DEFAULT_BUFFER_SIZE)
                    output.flush()
                }
            } != null
        }.getOrDefault(false)
    }

    private fun resolveTreeRoot(uri: Uri): String? {
        val id = DocumentsContract.getTreeDocumentId(uri)
        val split = id.split(":", limit = 2)
        return if (split.size == 2 && split[0] == "primary") {
            val suffix = split[1].trim('/')
            val root = android.os.Environment.getExternalStorageDirectory().absolutePath
            if (suffix.isEmpty()) root else "$root/$suffix"
        } else null
    }
}
