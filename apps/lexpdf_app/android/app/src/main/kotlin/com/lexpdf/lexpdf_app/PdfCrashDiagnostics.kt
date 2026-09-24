package com.lexpdf.lexpdf_app

import android.app.ActivityManager
import android.app.Application
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Process
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object PdfCrashDiagnostics {
    private const val PREFIX = "LPDFDIAG2"
    private const val BREADCRUMB_FILE = "pdfreader_breadcrumb.txt"
    private const val LAUNCH_FILE = "pdfreader_launch.txt"
    private const val MAIN_CRASH_FILE = "uncaught_main.txt"
    private const val READER_CRASH_FILE = "uncaught_pdfreader.txt"
    private const val PREFS = "pdf_crash_diagnostics"
    private const val LAST_SHOWN_EXIT = "last_shown_exit_timestamp"
    private const val LAST_SHOWN_CAPTURE = "last_shown_capture_timestamp"
    private const val LAUNCH_CORRELATION_WINDOW_MS = 60_000L

    fun installUncaughtExceptionCapture(context: Context) {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        if (previous is LexPdfUncaughtExceptionHandler) return

        Thread.setDefaultUncaughtExceptionHandler(
            LexPdfUncaughtExceptionHandler(
                appContext = context.applicationContext,
                previous = previous,
            ),
        )
    }

    fun markReaderLaunchAttempt(context: Context, path: String) {
        val payload =
            "${System.currentTimeMillis()}|pathHash=${path.hashCode()}|size=${File(path).length()}"
        writeDiagnosticFile(context, LAUNCH_FILE, payload)
    }

    fun mark(context: Context, stage: String, detail: String = "") {
        val safeDetail = detail.replace("\n", " ").take(240)
        val payload = "$PREFIX|$stage|$safeDetail"
        writeDiagnosticFile(
            context,
            BREADCRUMB_FILE,
            "${System.currentTimeMillis()}|$payload",
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val am = context.getSystemService(ActivityManager::class.java)
                am.setProcessStateSummary(payload.toByteArray(Charsets.UTF_8))
            } catch (_: Throwable) {
            }
        }
    }

    fun recordControlledLaunchFailure(context: Context, error: Throwable) {
        persistThrowable(
            context = context,
            processName = currentProcessName(context),
            threadName = Thread.currentThread().name,
            error = error,
            controlled = true,
        )
    }

    fun readBreadcrumb(context: Context): String? =
        readDiagnosticFile(context, BREADCRUMB_FILE)

    fun recentExitReport(context: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return recentCapturedCrashReport(context)
        }

        return try {
            val packageName = context.packageName
            val readerProcessName = "$packageName:pdfreader"
            val am = context.getSystemService(ActivityManager::class.java)
            val exits = am.getHistoricalProcessExitReasons(packageName, 0, 24)

            // First preference: an abnormal death of the dedicated PDF reader.
            val readerExit =
                exits.firstOrNull { info ->
                    info.processName == readerProcessName && isAbnormal(info.reason)
                }
            if (readerExit != null && !wasAlreadyShown(context, readerExit.timestamp)) {
                rememberShown(context, readerExit.timestamp)
                return formatExit(
                    context = context,
                    exit = readerExit,
                    captured = readDiagnosticFile(context, READER_CRASH_FILE),
                )
            }

            // Second preference: the main process only when its death happened
            // immediately after an explicit reader launch attempt. This avoids
            // blaming PDF opening for unrelated historical app crashes.
            val launchTimestamp = readLaunchTimestamp(context)
            if (launchTimestamp != null) {
                val mainExit =
                    exits.firstOrNull { info ->
                        info.processName == packageName &&
                            isAbnormal(info.reason) &&
                            info.timestamp >= launchTimestamp &&
                            info.timestamp - launchTimestamp <= LAUNCH_CORRELATION_WINDOW_MS
                    }
                if (mainExit != null && !wasAlreadyShown(context, mainExit.timestamp)) {
                    rememberShown(context, mainExit.timestamp)
                    return formatExit(
                        context = context,
                        exit = mainExit,
                        captured = readDiagnosticFile(context, MAIN_CRASH_FILE),
                    )
                }
            }

            recentCapturedCrashReport(context)
        } catch (error: Throwable) {
            "Falha ao ler ApplicationExitInfo: ${error.javaClass.simpleName}: ${error.message}\n" +
                "captura local: ${recentCapturedCrashReport(context) ?: "(nenhuma)"}"
        }
    }

    private fun formatExit(
        context: Context,
        exit: ApplicationExitInfo,
        captured: String?,
    ): String {
        val summary =
            exit.processStateSummary?.toString(Charsets.UTF_8)
                ?.take(1400)
                ?: "(sem resumo de estado)"
        val description = exit.description ?: "(sem descrição)"
        val timestamp =
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
                .format(Date(exit.timestamp))
        val breadcrumb = readBreadcrumb(context) ?: "(sem breadcrumb em arquivo)"

        return buildString {
            appendLine("LexPDF diagnóstico de encerramento")
            appendLine("processo: ${exit.processName}")
            appendLine("quando: $timestamp")
            appendLine("motivo: ${reasonName(exit.reason)} (${exit.reason})")
            appendLine("status/sinal: ${exit.status}")
            appendLine("PSS: ${exit.pss} kB")
            appendLine("RSS: ${exit.rss} kB")
            appendLine("descrição: $description")
            appendLine("estado salvo: $summary")
            appendLine("último breadcrumb: $breadcrumb")
            if (!captured.isNullOrBlank()) {
                appendLine()
                appendLine("exceção capturada pelo LexPDF:")
                append(captured.take(7000))
            }
        }.trim()
    }

    private fun recentCapturedCrashReport(context: Context): String? {
        val launchTimestamp = readLaunchTimestamp(context)
        val candidates =
            listOfNotNull(
                readDiagnosticFile(context, READER_CRASH_FILE),
                readDiagnosticFile(context, MAIN_CRASH_FILE),
            )
                .mapNotNull { payload ->
                    val timestamp = payload.substringBefore('|').toLongOrNull()
                        ?: return@mapNotNull null
                    timestamp to payload
                }
                .sortedByDescending { it.first }

        val (timestamp, payload) =
            candidates.firstOrNull { (timestamp, payload) ->
                if (wasCapturedAlreadyShown(context, timestamp)) {
                    false
                } else if (payload.contains("processo=${context.packageName}:pdfreader")) {
                    true
                } else {
                    launchTimestamp != null &&
                        timestamp >= launchTimestamp &&
                        timestamp - launchTimestamp <= LAUNCH_CORRELATION_WINDOW_MS
                }
            } ?: return null

        rememberCapturedShown(context, timestamp)
        return buildString {
            appendLine("LexPDF diagnóstico local de exceção")
            append(payload)
        }
    }

    private fun readLaunchTimestamp(context: Context): Long? =
        readDiagnosticFile(context, LAUNCH_FILE)
            ?.substringBefore('|')
            ?.toLongOrNull()

    private fun isAbnormal(reason: Int): Boolean =
        reason == ApplicationExitInfo.REASON_CRASH ||
            reason == ApplicationExitInfo.REASON_CRASH_NATIVE ||
            reason == ApplicationExitInfo.REASON_ANR ||
            reason == ApplicationExitInfo.REASON_LOW_MEMORY ||
            reason == ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE ||
            reason == ApplicationExitInfo.REASON_SIGNALED ||
            reason == ApplicationExitInfo.REASON_INITIALIZATION_FAILURE ||
            reason == ApplicationExitInfo.REASON_DEPENDENCY_DIED

    private fun wasAlreadyShown(context: Context, timestamp: Long): Boolean =
        context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(LAST_SHOWN_EXIT, -1L) == timestamp

    private fun rememberShown(context: Context, timestamp: Long) {
        context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(LAST_SHOWN_EXIT, timestamp)
            .apply()
    }

    private fun wasCapturedAlreadyShown(context: Context, timestamp: Long): Boolean =
        context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(LAST_SHOWN_CAPTURE, -1L) == timestamp

    private fun rememberCapturedShown(context: Context, timestamp: Long) {
        context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(LAST_SHOWN_CAPTURE, timestamp)
            .apply()
    }

    private fun persistThrowable(
        context: Context,
        processName: String,
        threadName: String,
        error: Throwable,
        controlled: Boolean,
    ) {
        try {
            val stack =
                StringWriter().also { writer ->
                    PrintWriter(writer).use { printer ->
                        error.printStackTrace(printer)
                    }
                }.toString()

            val fileName =
                if (processName.endsWith(":pdfreader")) READER_CRASH_FILE
                else MAIN_CRASH_FILE
            val payload =
                buildString {
                    append(System.currentTimeMillis())
                    append('|')
                    appendLine(
                        "processo=$processName pid=${Process.myPid()} thread=$threadName " +
                            "controlled=$controlled",
                    )
                    appendLine(
                        "${error.javaClass.name}: ${error.message ?: "(sem mensagem)"}",
                    )
                    append(stack.take(12_000))
                }
            writeDiagnosticFile(context, fileName, payload)
        } catch (_: Throwable) {
        }
    }

    private fun writeDiagnosticFile(context: Context, name: String, value: String) {
        try {
            val dir = File(context.filesDir, "diagnostics").apply { mkdirs() }
            val target = File(dir, name)
            val temp = File(dir, "$name.tmp")
            temp.writeText(value)
            if (!temp.renameTo(target)) {
                temp.copyTo(target, overwrite = true)
                temp.delete()
            }
        } catch (_: Throwable) {
        }
    }

    private fun readDiagnosticFile(context: Context, name: String): String? =
        try {
            val file = File(File(context.filesDir, "diagnostics"), name)
            file.takeIf { it.isFile }?.readText()?.take(14_000)
        } catch (_: Throwable) {
            null
        }

    private fun currentProcessName(context: Context): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return Application.getProcessName()
        }
        return try {
            val am = context.getSystemService(ActivityManager::class.java)
            am.runningAppProcesses
                ?.firstOrNull { it.pid == Process.myPid() }
                ?.processName
                ?: context.packageName
        } catch (_: Throwable) {
            context.packageName
        }
    }

    private fun reasonName(reason: Int): String =
        when (reason) {
            ApplicationExitInfo.REASON_UNKNOWN -> "UNKNOWN"
            ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
            ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
            ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
            ApplicationExitInfo.REASON_CRASH -> "CRASH_JAVA"
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
            ApplicationExitInfo.REASON_ANR -> "ANR"
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
            ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
            ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
            ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
            ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
            ApplicationExitInfo.REASON_OTHER -> "OTHER"
            else -> "OTHER_$reason"
        }

    private class LexPdfUncaughtExceptionHandler(
        private val appContext: Context,
        private val previous: Thread.UncaughtExceptionHandler?,
    ) : Thread.UncaughtExceptionHandler {
        override fun uncaughtException(thread: Thread, error: Throwable) {
            persistThrowable(
                context = appContext,
                processName = currentProcessName(appContext),
                threadName = thread.name,
                error = error,
                controlled = false,
            )
            previous?.uncaughtException(thread, error)
                ?: Process.killProcess(Process.myPid())
        }
    }
}
