package com.lexpdf.lexpdf_app

import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
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
        private const val NATIVE_PICKER_CHANNEL = "lexpdf/native_pdf_picker"
        private const val PICK_FILE_REQUEST_CODE = 0x4C50
        private const val PICK_FILES_REQUEST_CODE = 0x4C51
    }

    private var channel: MethodChannel? = null
    private var inputCapabilitiesChannel: MethodChannel? = null
    private var nativeReaderChannel: MethodChannel? = null
    private var nativePickerChannel: MethodChannel? = null
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingPickerExtensions: Set<String> = emptySet()
    private var pendingPickerMultiple = false
    private var pendingPdfPath: String? = null
    private var flutterReady = false
    private var diagnosticDialogVisible = false

    override fun onCreate(savedInstanceState: Bundle?) {
        PdfCrashDiagnostics.installUncaughtExceptionCapture(this)
        super.onCreate(savedInstanceState)
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        PdfCrashDiagnostics.markMainUiReady(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                PDF_CHANNEL,
            ).also { methodChannel ->
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

        inputCapabilitiesChannel =
            MethodChannel(
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

        nativePickerChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                NATIVE_PICKER_CHANNEL,
            ).also { methodChannel ->
                methodChannel.setMethodCallHandler { call, result ->
                    val extensions =
                        call.argument<List<*>>("extensions")
                            ?.mapNotNull { it as? String }
                            ?: emptyList()
                    val mimeType = call.argument<String>("mimeType") ?: "*/*"

                    when (call.method) {
                        "pickPdf" ->
                            launchNativeFilePicker(
                                result = result,
                                mimeType = "application/pdf",
                                extensions = listOf("pdf"),
                                multiple = false,
                            )
                        "pickFile" ->
                            launchNativeFilePicker(
                                result = result,
                                mimeType = mimeType,
                                extensions = extensions,
                                multiple = false,
                            )
                        "pickFiles" ->
                            launchNativeFilePicker(
                                result = result,
                                mimeType = mimeType,
                                extensions = extensions,
                                multiple = true,
                            )
                        else -> result.notImplemented()
                    }
                }
            }

        nativeReaderChannel =
            MethodChannel(
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

                            try {
                                PdfCrashDiagnostics.markReaderLaunchAttempt(
                                    this,
                                    file.absolutePath,
                                )
                                val readerIntent =
                                    Intent(this, NativePdfReaderActivity::class.java).apply {
                                        putExtra(
                                            NativePdfReaderActivity.EXTRA_PATH,
                                            file.absolutePath,
                                        )
                                        putExtra(
                                            NativePdfReaderActivity.EXTRA_INITIAL_PAGE,
                                            initialPage.coerceAtLeast(1),
                                        )
                                    }
                                startActivity(readerIntent)
                                result.success(true)
                            } catch (error: Throwable) {
                                PdfCrashDiagnostics.recordControlledLaunchFailure(
                                    this,
                                    error,
                                )
                                result.error(
                                    "native_reader_launch_failed",
                                    "${error.javaClass.simpleName}: ${error.message}",
                                    null,
                                )
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
            }

        processIntent(intent)
    }

    private fun launchNativeFilePicker(
        result: MethodChannel.Result,
        mimeType: String,
        extensions: List<String>,
        multiple: Boolean,
    ) {
        if (pendingPickerResult != null) {
            result.error("picker_busy", "A file selection is already in progress.", null)
            return
        }

        pendingPickerResult = result
        pendingPickerExtensions =
            extensions
                .map { it.trim().trimStart('.').lowercase() }
                .filter { it.isNotBlank() }
                .toSet()
        pendingPickerMultiple = multiple

        try {
            PdfCrashDiagnostics.mark(
                this,
                "PICKER_OPEN",
                "multiple=$multiple ext=${pendingPickerExtensions.joinToString(",")}",
            )

            val pickerIntent =
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mimeType.ifBlank { "*/*" }
                    if (multiple) {
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    }
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                    )
                }

            startActivityForResult(
                pickerIntent,
                if (multiple) PICK_FILES_REQUEST_CODE else PICK_FILE_REQUEST_CODE,
            )
        } catch (error: Throwable) {
            clearPendingPicker()
            PdfCrashDiagnostics.recordControlledLaunchFailure(this, error)
            result.error(
                "picker_launch_failed",
                "${error.javaClass.simpleName}: ${error.message}",
                null,
            )
        }
    }

    @Deprecated("Deprecated in Android framework; retained for FlutterActivity compatibility.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val isNativePicker =
            requestCode == PICK_FILE_REQUEST_CODE ||
                requestCode == PICK_FILES_REQUEST_CODE
        if (!isNativePicker) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingPickerResult ?: return
        val multiple = pendingPickerMultiple
        val allowedExtensions = pendingPickerExtensions

        if (resultCode != RESULT_OK) {
            clearPendingPicker()
            if (multiple) {
                result.success(emptyList<Map<String, String>>())
            } else {
                result.success(null)
            }
            return
        }

        val uris = mutableListOf<Uri>()
        data?.data?.let { uris.add(it) }
        data?.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                val uri = clip.getItemAt(index).uri
                if (uri != null && !uris.contains(uri)) uris.add(uri)
            }
        }

        if (uris.isEmpty()) {
            clearPendingPicker()
            result.error("picker_missing_uri", "Android returned no file URI.", null)
            return
        }

        uris.forEach { uri ->
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                // The immediate streaming copy below does not depend on persistence.
            }
        }

        PdfCrashDiagnostics.mark(
            this,
            "PICKER_COPY_START",
            "count=${uris.size}",
        )

        Thread(
            {
                try {
                    val files =
                        uris.mapNotNull { uri ->
                            val displayName = queryDisplayName(uri)
                            val path =
                                materializeFile(
                                    uri = uri,
                                    allowedExtensions = allowedExtensions,
                                    fallbackName = displayName,
                                )
                            if (path == null) {
                                null
                            } else {
                                mapOf(
                                    "path" to path,
                                    "name" to displayName,
                                )
                            }
                        }

                    if (files.size != uris.size) {
                        runOnUiThread {
                            clearPendingPicker()
                            result.error(
                                "picker_copy_failed",
                                "Could not stream one or more selected files.",
                                null,
                            )
                        }
                    } else {
                        val totalBytes =
                            files.sumOf { item ->
                                File(item.getValue("path")).length()
                            }
                        PdfCrashDiagnostics.mark(
                            this,
                            "PICKER_COPY_DONE",
                            "count=${files.size} bytes=$totalBytes",
                        )
                        runOnUiThread {
                            clearPendingPicker()
                            if (multiple) {
                                result.success(files)
                            } else {
                                result.success(files.firstOrNull())
                            }
                        }
                    }
                } catch (error: Throwable) {
                    PdfCrashDiagnostics.recordControlledLaunchFailure(this, error)
                    runOnUiThread {
                        clearPendingPicker()
                        result.error(
                            "picker_copy_failed",
                            "${error.javaClass.simpleName}: ${error.message}",
                            null,
                        )
                    }
                }
            },
            "LexPdfPickerCopy",
        ).start()
    }

    private fun clearPendingPicker() {
        pendingPickerResult = null
        pendingPickerExtensions = emptySet()
        pendingPickerMultiple = false
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        processIntent(intent)
    }

    override fun onPostResume() {
        super.onPostResume()
        if (diagnosticDialogVisible || isFinishing || isDestroyed) return

        try {
            val report = PdfCrashDiagnostics.recentExitReport(this)
            if (report.isNullOrBlank()) return

            diagnosticDialogVisible = true
            AlertDialog.Builder(this)
                .setTitle("Diagnóstico de falha do LexPDF")
                .setMessage(report)
                .setPositiveButton("Copiar") { _, _ ->
                    val clipboard = getSystemService(ClipboardManager::class.java)
                    clipboard.setPrimaryClip(
                        ClipData.newPlainText("LexPDF diagnóstico", report),
                    )
                }
                .setNegativeButton("Fechar") { _, _ ->
                    diagnosticDialogVisible = false
                }
                .setOnDismissListener {
                    diagnosticDialogVisible = false
                }
                .show()
        } catch (error: Throwable) {
            diagnosticDialogVisible = false
            PdfCrashDiagnostics.recordControlledLaunchFailure(this, error)
        }
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
        val uri =
            when (sourceIntent?.action) {
                Intent.ACTION_VIEW -> sourceIntent.data
                Intent.ACTION_SEND ->
                    sourceIntent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
                else -> null
            } ?: return

        Thread(
            {
                val path = materializePdf(uri) ?: return@Thread
                runOnUiThread {
                    if (flutterReady) {
                        channel?.invokeMethod("openPdfPath", path)
                    } else {
                        pendingPdfPath = path
                    }
                }
            },
            "LexPdfIntentCopy",
        ).start()
    }

    private fun materializePdf(uri: Uri): String? =
        materializeFile(
            uri = uri,
            allowedExtensions = setOf("pdf"),
            fallbackName = "document.pdf",
        )

    private fun materializeFile(
        uri: Uri,
        allowedExtensions: Set<String>,
        fallbackName: String,
    ): String? {
        if (uri.scheme == "file") {
            val path = uri.path ?: return null
            return path.takeIf {
                allowedExtensions.isEmpty() ||
                    allowedExtensions.contains(
                        File(it).extensionLowercase(),
                    )
            }
        }
        if (uri.scheme != "content") return null

        var displayName = queryDisplayName(uri)
        if (displayName.isBlank()) displayName = fallbackName

        val extension = File(displayName).extensionLowercase()
        if (allowedExtensions.isNotEmpty() && !allowedExtensions.contains(extension)) {
            return null
        }

        val safeName =
            displayName
                .replace(Regex("[^A-Za-z0-9._-]"), "_")
                .ifBlank { fallbackName }
        val uriKey = uri.toString().hashCode().toUInt().toString(16)
        val targetDir =
            File(filesDir, "native_open").apply {
                mkdirs()
                val staleBefore = System.currentTimeMillis() - 30L * 60L * 1000L
                listFiles()
                    ?.filter {
                        it.isFile &&
                            it.name.endsWith(".part") &&
                            it.lastModified() < staleBefore
                    }
                    ?.forEach { it.delete() }
            }
        val target = File(targetDir, "${uriKey}_$safeName")

        if (target.isFile && target.length() > 0L) return target.absolutePath

        val temporary = File.createTempFile("${uriKey}_", ".part", targetDir)
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                temporary.outputStream().use { output ->
                    // Bounded copy: memory remains O(1) regardless of source size.
                    input.copyTo(output, bufferSize = 64 * 1024)
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
        contentResolver
            .query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        return cursor.getString(index) ?: "document.bin"
                    }
                }
            }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "document.bin"
    }

    private fun File.extensionLowercase(): String =
        name
            .substringAfterLast('.', "")
            .lowercase()
}
