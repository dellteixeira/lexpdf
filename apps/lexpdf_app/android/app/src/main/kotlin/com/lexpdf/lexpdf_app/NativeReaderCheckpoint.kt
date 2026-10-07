package com.lexpdf.lexpdf_app

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.security.MessageDigest

/** Small cross-process recovery record; Flutter remains the reading-progress owner. */
object NativeReaderCheckpoint {
    private fun record(context: Context, source: File): AtomicFile {
        val identity = "${source.absolutePath}|${source.length()}|${source.lastModified()}"
        val key = MessageDigest.getInstance("SHA-256")
            .digest(identity.toByteArray()).joinToString("") { "%02x".format(it) }
        return AtomicFile(File(context.filesDir, "native_reader_checkpoint/$key.txt"))
    }

    fun pendingPage(context: Context, source: File): Int? = try {
        val parts = record(context, source).openRead().bufferedReader().use { it.readText() }.split('|')
        if (parts.getOrNull(1) == "active") parts.firstOrNull()?.toIntOrNull()?.takeIf { it > 0 }
        else null
    } catch (_: Exception) { null }

    fun save(context: Context, source: File, page: Int, active: Boolean = true) {
        if (page < 1) return
        try {
            val file = record(context, source)
            file.baseFile.parentFile?.mkdirs()
            val stream = file.startWrite()
            try {
                stream.write("$page|${if (active) "active" else "closed"}".toByteArray())
                file.finishWrite(stream)
            } catch (error: Exception) {
                file.failWrite(stream)
            }
        } catch (_: Exception) {
            // A storage failure must not interrupt reading or overwrite Flutter progress.
        }
    }
}
