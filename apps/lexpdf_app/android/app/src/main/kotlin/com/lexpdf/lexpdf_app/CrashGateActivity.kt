package com.lexpdf.lexpdf_app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * Native launcher that runs before Flutter.
 *
 * Its only job is to guarantee that a previous abnormal LexPDF exit is visible
 * to the user even when Flutter itself crashed before MainActivity could draw.
 */
class CrashGateActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val report = PdfCrashDiagnostics.recentExitReport(this)
        if (report.isNullOrBlank()) {
            continueToLexPdf()
            return
        }

        showDiagnostic(report)
    }

    private fun showDiagnostic(report: String) {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24.dp, 24.dp, 24.dp, 24.dp)
        }

        val title = TextView(this).apply {
            text = "Diagnóstico de falha do LexPDF"
            textSize = 22f
            setPadding(0, 0, 0, 14.dp)
        }
        root.addView(title)

        val explanation = TextView(this).apply {
            text =
                "O LexPDF detectou que um processo foi encerrado de forma anormal. " +
                    "Este relatório é exibido antes do Flutter para não desaparecer " +
                    "mesmo quando a falha ocorre durante a inicialização."
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
                ScrollView.LayoutParams(
                    ScrollView.LayoutParams.MATCH_PARENT,
                    ScrollView.LayoutParams.WRAP_CONTENT,
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

        val continueButton = Button(this).apply {
            text = "Continuar para o LexPDF"
            setOnClickListener {
                continueToLexPdf()
            }
        }
        buttons.addView(continueButton)

        root.addView(buttons)
        setContentView(root)
    }

    private fun continueToLexPdf() {
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

        startActivity(target)
        finish()
    }

    private val Int.dp: Int
        get() = (this * resources.displayMetrics.density).toInt()
}
