package io.github.javymv87.vehicle_history

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.StatFs
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
 * - `freeBytes(path)`: the bytes available to the app on the volume of `path`.
 */
class MainActivity : FlutterActivity() {
    /** The pending `saveFile` call, answered when the dialog returns. */
    private var pendingSave: PendingSave? = null

    /** Runs the copies, one at a time, off the main thread. */
    private val copier = Executors.newSingleThreadExecutor()

    /** Posts the channel answers back to the main thread. */
    private val mainHandler = Handler(Looper.getMainLooper())

    /** A `saveFile` call waiting for the user to choose a place. */
    private class PendingSave(val sourcePath: String, val result: MethodChannel.Result)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveFile" -> startSave(call, result)
                    "freeBytes" -> freeBytes(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    /** Opens the "save as" dialog for the file of a `saveFile` [call]. */
    private fun startSave(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val suggestedName = call.argument<String>("suggestedName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (sourcePath == null || suggestedName == null) {
            result.error("bad_arguments", "sourcePath and suggestedName are required", null)
            return
        }
        if (pendingSave != null) {
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

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != SAVE_REQUEST_CODE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val save = pendingSave ?: return
        pendingSave = null
        val target = data?.data
        if (resultCode != Activity.RESULT_OK || target == null) {
            save.result.success("cancelled")
            return
        }
        copier.execute { copy(save, target) }
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

        /** Size of the copy buffer: 64 KB. */
        const val BUFFER_SIZE = 64 * 1024
    }
}
