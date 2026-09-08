package com.lexpdf.lexpdf_app

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "lexpdf/native_pdf_open"
    }

    private var channel: MethodChannel? = null
    private var pendingPdfPath: String? = null
    private var flutterReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialPdfPath" -> {
                        flutterReady = true
                        result.success(pendingPdfPath)
                        pendingPdfPath = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        processIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        processIntent(intent)
    }

    private fun processIntent(sourceIntent: Intent?) {
        val uri = when (sourceIntent?.action) {
            Intent.ACTION_VIEW -> sourceIntent.data
            Intent.ACTION_SEND -> sourceIntent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            else -> null
        } ?: return

        val path = materializePdf(uri) ?: return
        if (flutterReady) {
            channel?.invokeMethod("openPdfPath", path)
        } else {
            pendingPdfPath = path
        }
    }

    private fun materializePdf(uri: Uri): String? {
        if (uri.scheme == "file") {
            val path = uri.path ?: return null
            return path.takeIf { it.lowercase().endsWith(".pdf") }
        }
        if (uri.scheme != "content") return null

        val displayName = queryDisplayName(uri)
        if (!displayName.lowercase().endsWith(".pdf")) return null

        val safeName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val targetDir = File(cacheDir, "native_open").apply { mkdirs() }
        val target = File(targetDir, "${System.currentTimeMillis()}_$safeName")

        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            target.absolutePath
        } catch (_: Exception) {
            target.delete()
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index) ?: "document.pdf"
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "document.pdf"
    }
}
