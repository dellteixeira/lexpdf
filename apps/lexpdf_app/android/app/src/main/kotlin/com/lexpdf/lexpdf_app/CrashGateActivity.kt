package com.lexpdf.lexpdf_app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * Native launcher/circuit breaker that lives in the dedicated :crashguard
 * process. The Flutter process may die without taking this Activity down.
 *
 * The guard never blindly relaunches Flutter after a crash. It records every
 * launch attempt, stays behind MainActivity, and surfaces the exit reason when
 * MainActivity disappears abnormally.
 */
class CrashGateActivity : AppCompatActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private var launchedMain = false
    private var mainWasForeground = false
    private var recoveryCheckScheduled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val report = PdfCrashDiagnostics.recentExitReport(this)
        if (report.isNullOrBlank()) {
            launchLexPdf()
        } else {
            showDiagnostic(report)
        }
    }

    override fun onPause() {
        if (launchedMain) {
            mainWasForeground = true
        }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (!launchedMain || !mainWasForeground || recoveryCheckScheduled) return

        recoveryCheckScheduled = true
        handler.postDelayed(
            {
                recoveryCheckScheduled = false
                if (isFinishing || isDestroyed || !launchedMain) return@postDelayed

                val report = PdfCrashDiagnostics.recentExitReport(this)
                if (!report.isNullOrBlank()) {
                    launchedMain = false
                    mainWasForeground = false
                    showDiagnostic(report)
                    return@postDelayed
                }

                // MainActivity returned normally (for example, Back). Do not
                // relaunch it automatically and accidentally create a loop.
                finish()
            },
            1200L,
        )
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun showDiagnostic(report: String) {
        launchedMain = false
        mainWasForeground = false

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24.dp, 24.dp, 24.dp, 24.dp)
        }

        val title = TextView(this).apply {
            text = "LexPDF interrompeu uma falha contínua"
            textSize = 22f
            setPadding(0, 0, 0, 14.dp)
        }
        root.addView(title)

        val explanation = TextView(this).apply {
            text =
                "O processo que falhou foi isolado e não será reiniciado automaticamente. " +
                    "Abaixo está o diagnóstico persistente desta execução. Assim o LexPDF " +
                    "não entra novamente no ciclo abrir → cair → abrir."
            textSize = 14f
            setPadding(0, 0, 0, 14.dp)
        }
        root.addView(explanation)

        val reportView = TextView(this).apply {
            text = report
            textSize = 13f
            setTextIsSelectable(true)
            setPadding(12.dp, 12.dp, 12.dp, 12.dp)
        }
        val scroll = ScrollView(this).apply {
            addView(
                reportView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
        root.addView(
            scroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            setPadding(0, 14.dp, 0, 0)
        }

        val copyButton = Button(this).apply {
            text = "Copiar diagnóstico"
            setOnClickListener {
                val clipboard = getSystemService(ClipboardManager::class.java)
                clipboard.setPrimaryClip(
                    ClipData.newPlainText("LexPDF diagnóstico", report),
                )
            }
        }
        buttons.addView(copyButton)

        val closeButton = Button(this).apply {
            text = "Fechar"
            setOnClickListener { finish() }
        }
        buttons.addView(closeButton)

        val retryButton = Button(this).apply {
            text = "Tentar uma vez"
            setOnClickListener { launchLexPdf() }
        }
        buttons.addView(retryButton)

        root.addView(buttons)
        setContentView(root)
    }

    private fun launchLexPdf() {
        if (launchedMain) return

        try {
            PdfCrashDiagnostics.markAppLaunchAttempt(this)

            val target =
                Intent(this, MainActivity::class.java).apply {
                    action = intent.action
                    data = intent.data
                    type = intent.type
                    clipData = intent.clipData

                    intent.extras?.let { putExtras(it) }
                    intent.categories?.forEach { addCategory(it) }

                    // Do not propagate task-creation flags from the external
                    // launcher/share intent into the internal MainActivity hop.
                    flags = intent.flags and
                        (Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_NEW_DOCUMENT or
                            Intent.FLAG_ACTIVITY_MULTIPLE_TASK).inv()
                }

            launchedMain = true
            mainWasForeground = false
            startActivity(target)
        } catch (error: Throwable) {
            launchedMain = false
            mainWasForeground = false
            PdfCrashDiagnostics.recordControlledLaunchFailure(this, error)
            showDiagnostic(
                buildString {
                    appendLine("LexPDF diagnóstico de inicialização")
                    appendLine("processo: ${packageName}:crashguard")
                    appendLine("motivo: falha controlada ao iniciar MainActivity")
                    appendLine("${error.javaClass.name}: ${error.message ?: "(sem mensagem)"}")
                }.trim(),
            )
        }
    }

    private val Int.dp: Int
        get() = (this * resources.displayMetrics.density).toInt()
}
