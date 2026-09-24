package com.lexpdf.lexpdf_app

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object PdfCrashDiagnostics {
    private const val PREFIX = "LPDFDIAG1"
    private const val FILE_NAME = "pdfreader_breadcrumb.txt"

    fun mark(context: Context, stage: String, detail: String = "") {
        val safeDetail = detail.replace("\n", " ").take(240)
        val payload = "$PREFIX|$stage|$safeDetail"
        try {
            val dir = File(context.filesDir, "diagnostics").apply { mkdirs() }
            File(dir, FILE_NAME).writeText(
                "${System.currentTimeMillis()}|$payload",
            )
        } catch (_: Throwable) {
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val am = context.getSystemService(ActivityManager::class.java)
                am.setProcessStateSummary(payload.toByteArray(Charsets.UTF_8))
            } catch (_: Throwable) {
            }
        }
    }

    fun readBreadcrumb(context: Context): String? {
        return try {
            val file = File(File(context.filesDir, "diagnostics"), FILE_NAME)
            file.takeIf { it.isFile }?.readText()?.take(1000)
        } catch (_: Throwable) {
            null
        }
    }

    fun recentExitReport(context: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return readBreadcrumb(context)?.let {
                "Android < 11; último breadcrumb:\n$it"
            }
        }

        return try {
            val am = context.getSystemService(ActivityManager::class.java)
            val exits = am.getHistoricalProcessExitReasons(context.packageName, 0, 12)
            val interesting = exits.firstOrNull { info ->
                val summary =
                    info.processStateSummary?.toString(Charsets.UTF_8).orEmpty()
                info.processName.contains(":pdfreader") ||
                    summary.startsWith(PREFIX) ||
                    info.reason == ApplicationExitInfo.REASON_CRASH ||
                    info.reason == ApplicationExitInfo.REASON_CRASH_NATIVE ||
                    info.reason == ApplicationExitInfo.REASON_ANR ||
                    info.reason == ApplicationExitInfo.REASON_LOW_MEMORY ||
                    info.reason == ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE
            } ?: return readBreadcrumb(context)?.let {
                "Nenhuma saída histórica relevante encontrada.\nÚltimo breadcrumb:\n$it"
            }

            val summary =
                interesting.processStateSummary?.toString(Charsets.UTF_8)
                    ?.take(1000)
                    ?: "(sem resumo de estado)"
            val description = interesting.description ?: "(sem descrição)"
            val timestamp =
                SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
                    .format(Date(interesting.timestamp))
            val reason = reasonName(interesting.reason)
            val breadcrumb = readBreadcrumb(context) ?: "(sem breadcrumb em arquivo)"

            buildString {
                appendLine("LexPDF diagnóstico de encerramento")
                appendLine("processo: ${interesting.processName}")
                appendLine("quando: $timestamp")
                appendLine("motivo: $reason (${interesting.reason})")
                appendLine("status/sinal: ${interesting.status}")
                appendLine("PSS: ${interesting.pss} kB")
                appendLine("RSS: ${interesting.rss} kB")
                appendLine("descrição: $description")
                appendLine("estado salvo: $summary")
                appendLine("último breadcrumb: $breadcrumb")
            }.trim()
        } catch (error: Throwable) {
            "Falha ao ler ApplicationExitInfo: ${error.javaClass.simpleName}: ${error.message}\n" +
                "Último breadcrumb: ${readBreadcrumb(context) ?: "(nenhum)"}"
        }
    }

    private fun reasonName(reason: Int): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return "indisponível"
        return when (reason) {
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
    }
}
