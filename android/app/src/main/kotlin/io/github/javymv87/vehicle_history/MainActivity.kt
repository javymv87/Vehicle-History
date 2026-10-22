package io.github.javymv87.vehicle_history

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.DocumentsContract
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executors

/**
 * The app's only activity. Besides hosting Flutter, it implements the
 * `vehicle_history/files` channel (see `lib/data/platform/native_files.dart`):
 *
 * - `saveFile(sourcePath, suggestedName, mimeType)`: the system "save as"
 *   dialog (`ACTION_CREATE_DOCUMENT`), then a streamed copy of the file to the
 *   chosen document in 64 KB chunks, off the main thread. Answers `saved`,
 *   `cancelled` or an error. Used for the backup package and for "Save to…"
 *   of an attachment, which can be far too large to pass through the channel.
 * - `saveFilesToFolder(files)`: the system folder picker
 *   (`ACTION_OPEN_DOCUMENT_TREE`), then a streamed copy of each file into a
 *   new document of the chosen folder, under its name (the provider adds
 *   " (1)" rather than overwrite). Answers the number of files saved, or
 *   `null` when the user cancelled.
 * - `shareFiles(files)`: copies the files, under their names, to
 *   `cache/share/` and offers them to other apps (`ACTION_SEND` /
 *   `ACTION_SEND_MULTIPLE`) through [ShareFileProvider], which grants the
 *   receiving app read access to those copies only. The copies go with the
 *   cache wipe at the next app start.
 * - `freeBytes(path)`: the bytes available to the app on the volume of `path`.
 *
 * A `files` argument is a list of maps with `path`, `name` and `mimeType`.
 */
class MainActivity : FlutterActivity() {
    /** The pending `saveFile` call, answered when the dialog returns. */
    private var pendingSave: PendingSave? = null

    /** The pending `saveFilesToFolder` call, answered when the picker returns. */
    private var pendingFolderSave: PendingFolderSave? = null

    /** Runs the copies, one at a time, off the main thread. */
    private val copier = Executors.newSingleThreadExecutor()

    /** Posts the channel answers back to the main thread. */
    private val mainHandler = Handler(Looper.getMainLooper())

    /** A `saveFile` call waiting for the user to choose a place. */
    private class PendingSave(val sourcePath: String, val result: MethodChannel.Result)

    /** A file named in a `files` argument. */
    private class NativeFile(val path: String, val name: String, val mimeType: String)

    /** A `saveFilesToFolder` call waiting for the user to choose a folder. */
    private class PendingFolderSave(val files: List<NativeFile>, val result: MethodChannel.Result)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveFile" -> startSave(call, result)
                    "saveFilesToFolder" -> startFolderSave(call, result)
                    "shareFiles" -> shareFiles(call, result)
                    "freeBytes" -> freeBytes(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    /** Whether a save dialog or folder picker is waiting for the user. */
    private val saveInProgress get() = pendingSave != null || pendingFolderSave != null

    /** Opens the "save as" dialog for the file of a `saveFile` [call]. */
    private fun startSave(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val suggestedName = call.argument<String>("suggestedName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (sourcePath == null || suggestedName == null) {
            result.error("bad_arguments", "sourcePath and suggestedName are required", null)
            return
        }
        if (saveInProgress) {
            result.error("busy", "Another save is in progress", null)
            return
        }
        if (!File(sourcePath).isFile) {
            result.error("not_found", "No file at $sourcePath", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, suggestedName)
        }
        pendingSave = PendingSave(sourcePath, result)
        try {
            startActivityForResult(intent, SAVE_REQUEST_CODE)
        } catch (error: Exception) {
            pendingSave = null
            result.error("no_picker", error.message, null)
        }
    }

    /** Opens the folder picker for the files of a `saveFilesToFolder` [call]. */
    private fun startFolderSave(call: MethodCall, result: MethodChannel.Result) {
        val files = filesOf(call, result) ?: return
        if (saveInProgress) {
            result.error("busy", "Another save is in progress", null)
            return
        }
        pendingFolderSave = PendingFolderSave(files, result)
        try {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), FOLDER_REQUEST_CODE)
        } catch (error: Exception) {
            pendingFolderSave = null
            result.error("no_picker", error.message, null)
        }
    }

    /** Copies the files of a `shareFiles` [call] and opens the share sheet. */
    private fun shareFiles(call: MethodCall, result: MethodChannel.Result) {
        val files = filesOf(call, result) ?: return
        copier.execute {
            try {
                // Only the latest share is kept: earlier copies are not needed.
                val shareDir = File(cacheDir, SHARE_DIR).apply { deleteRecursively() }
                val uris = ArrayList<Uri>()
                files.forEachIndexed { index, file ->
                    // One directory per file: two files may have the same name.
                    val dir = File(shareDir, index.toString()).apply { mkdirs() }
                    val copy = File(dir, file.name)
                    FileInputStream(file.path).use { input ->
                        copy.outputStream().use { input.copyTo(it, BUFFER_SIZE) }
                    }
                    uris.add(FileProvider.getUriForFile(this, packageName + SHARE_AUTHORITY_SUFFIX, copy))
                }
                mainHandler.post { startShare(files, uris, result) }
            } catch (error: Exception) {
                mainHandler.post { result.error("share_failed", error.message, null) }
            }
        }
    }

    /** Opens the share sheet for [uris], the copies of [files]. */
    private fun startShare(files: List<NativeFile>, uris: ArrayList<Uri>, result: MethodChannel.Result) {
        val types = files.map { it.mimeType }.toSet()
        val families = types.map { it.substringBefore('/') }.toSet()
        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        }
        // One type for all, their common family ("image/*"), or anything.
        intent.type = when {
            types.size == 1 -> types.first()
            families.size == 1 -> families.first() + "/*"
            else -> "*/*"
        }
        // The clip data carries the read grant for every file.
        val clip = ClipData.newRawUri(null, uris[0])
        uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
        intent.clipData = clip
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            startActivity(Intent.createChooser(intent, null))
            result.success(null)
        } catch (error: Exception) {
            result.error("no_app", error.message, null)
        }
    }

    /**
     * The `files` argument of [call], or `null` after answering an error when
     * it is missing, empty or names a file that does not exist.
     */
    private fun filesOf(call: MethodCall, result: MethodChannel.Result): List<NativeFile>? {
        val raw = call.argument<List<Map<String, String>>>("files")
        val files = raw.orEmpty().mapNotNull { map ->
            val path = map["path"]
            val name = map["name"]
            if (path == null || name == null) {
                null
            } else {
                NativeFile(path, name, map["mimeType"] ?: "application/octet-stream")
            }
        }
        if (files.isEmpty() || files.size != raw?.size) {
            result.error("bad_arguments", "files must give the path and name of each file", null)
            return null
        }
        val missing = files.firstOrNull { !File(it.path).isFile }
        if (missing != null) {
            result.error("not_found", "No file at " + missing.path, null)
            return null
        }
        return files
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            SAVE_REQUEST_CODE -> {
                val save = pendingSave ?: return
                pendingSave = null
                val target = data?.data
                if (resultCode != Activity.RESULT_OK || target == null) {
                    save.result.success("cancelled")
                    return
                }
                copier.execute { copy(save, target) }
            }
            FOLDER_REQUEST_CODE -> {
                val save = pendingFolderSave ?: return
                pendingFolderSave = null
                val tree = data?.data
                if (resultCode != Activity.RESULT_OK || tree == null) {
                    save.result.success(null)
                    return
                }
                copier.execute { copyToFolder(save, tree) }
            }
            else -> super.onActivityResult(requestCode, resultCode, data)
        }
    }

    /** Copies the source of [save] to the document [target] in 64 KB chunks. */
    private fun copy(save: PendingSave, target: Uri) {
        try {
            val output = contentResolver.openOutputStream(target, "wt")
                ?: throw IllegalStateException("Cannot write to $target")
            FileInputStream(save.sourcePath).use { input ->
                output.use { input.copyTo(it, BUFFER_SIZE) }
            }
            mainHandler.post { save.result.success("saved") }
        } catch (error: Exception) {
            mainHandler.post { save.result.error("copy_failed", error.message, null) }
        }
    }

    /**
     * Copies each file of [save] into a new document of the folder [tree], in
     * 64 KB chunks. Stops at the first failure, answering an error whose
     * details are the number of files saved before it.
     */
    private fun copyToFolder(save: PendingFolderSave, tree: Uri) {
        var saved = 0
        try {
            val folder = DocumentsContract.buildDocumentUriUsingTree(
                tree,
                DocumentsContract.getTreeDocumentId(tree),
            )
            for (file in save.files) {
                val target = DocumentsContract.createDocument(
                    contentResolver,
                    folder,
                    file.mimeType,
                    file.name,
                ) ?: throw IllegalStateException("Cannot create " + file.name)
                val output = contentResolver.openOutputStream(target, "wt")
                    ?: throw IllegalStateException("Cannot write to $target")
                FileInputStream(file.path).use { input ->
                    output.use { input.copyTo(it, BUFFER_SIZE) }
                }
                saved++
            }
            mainHandler.post { save.result.success(saved) }
        } catch (error: Exception) {
            val savedBefore = saved
            mainHandler.post { save.result.error("copy_failed", error.message, savedBefore) }
        }
    }

    /** Answers the free bytes on the volume of the `path` of a `freeBytes` [call]. */
    private fun freeBytes(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("bad_arguments", "path is required", null)
            return
        }
        try {
            result.success(StatFs(path).availableBytes)
        } catch (error: IllegalArgumentException) {
            result.error("bad_path", error.message, null)
        }
    }

    override fun onDestroy() {
        copier.shutdown()
        super.onDestroy()
    }

    private companion object {
        /** Must match `MethodChannelNativeFiles` in Dart. */
        const val CHANNEL = "vehicle_history/files"

        /** Request code of the "save as" dialog. */
        const val SAVE_REQUEST_CODE = 0x5a7e

        /** Request code of the folder picker. */
        const val FOLDER_REQUEST_CODE = 0x5a7f

        /** Directory of the share copies, under the cache directory. */
        const val SHARE_DIR = "share"

        /** Authority of [ShareFileProvider], after the package name. */
        const val SHARE_AUTHORITY_SUFFIX = ".share"

        /** Size of the copy buffer: 64 KB. */
        const val BUFFER_SIZE = 64 * 1024
    }
}
