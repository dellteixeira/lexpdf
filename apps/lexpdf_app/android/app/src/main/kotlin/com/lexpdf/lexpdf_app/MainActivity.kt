package com.lexpdf.lexpdf_app

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.view.InputDevice
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val PDF_CHANNEL = "lexpdf/native_pdf_open"
        private const val INPUT_CAPABILITIES_CHANNEL = "lexpdf/input_capabilities"
        private const val NATIVE_READER_CHANNEL = "lexpdf/native_pdf_reader"
    }

    private var channel: MethodChannel? = null
    private var inputCapabilitiesChannel: MethodChannel? = null
    private var nativeReaderChannel: MethodChannel? = null
    private var pendingPdfPath: String? = null
    private var flutterReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PDF_CHANNEL).also { methodChannel ->
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
        inputCapabilitiesChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INPUT_CAPABILITIES_CHANNEL,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasStylus" -> result.success(hasStylusInputDevice())
                    else -> result.notImplemented()
                }
            }
        }

        nativeReaderChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NATIVE_READER_CHANNEL,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "openDocument" -> {
                        val path = call.argument<String>("path")
                        val initialPage = call.argument<Int>("initialPage") ?: 1
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "PDF path is required.", null)
                            return@setMethodCallHandler
                        }
                        val file = File(path)
                        if (!file.isFile || file.length() <= 0L) {
                            result.error("missing_pdf", "PDF file is unavailable.", null)
                            return@setMethodCallHandler
                        }

                        startActivity(
                            Intent(this, NativePdfReaderActivity::class.java).apply {
                                putExtra(NativePdfReaderActivity.EXTRA_PATH, file.absolutePath)
                                putExtra(
                                    NativePdfReaderActivity.EXTRA_INITIAL_PAGE,
                                    initialPage.coerceAtLeast(1),
                                )
                            },
                        )
                        result.success(true)
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

    private fun hasStylusInputDevice(): Boolean {
        return InputDevice.getDeviceIds().any { deviceId ->
            val device = InputDevice.getDevice(deviceId) ?: return@any false
            val sources = device.sources
            (sources and InputDevice.SOURCE_STYLUS) == InputDevice.SOURCE_STYLUS ||
                (sources and InputDevice.SOURCE_BLUETOOTH_STYLUS) == InputDevice.SOURCE_BLUETOOTH_STYLUS
        }
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
        val uriKey = uri.toString().hashCode().toUInt().toString(16)
        val targetDir = File(filesDir, "native_open").apply { mkdirs() }
        val target = File(targetDir, "${uriKey}_$safeName")

        if (target.isFile && target.length() > 0L) return target.absolutePath

        val temporary = File.createTempFile("${uriKey}_", ".part", targetDir)
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                temporary.outputStream().use { output ->
                    input.copyTo(output)
                    output.flush()
                }
            } ?: run {
                temporary.delete()
                return null
            }

            if (temporary.length() <= 0L) {
                temporary.delete()
                return null
            }

            if (!temporary.renameTo(target)) {
                temporary.delete()
                return null
            }
            target.absolutePath
        } catch (_: Exception) {
            temporary.delete()
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
