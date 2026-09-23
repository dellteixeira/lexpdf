package com.lexpdf.lexpdf_app

import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.os.ext.SdkExtensions
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.pdf.ExperimentalPdfApi
import androidx.pdf.PdfDocument
import androidx.pdf.PdfWriteHandle
import androidx.pdf.ink.EditablePdfViewerFragment
import androidx.pdf.viewer.fragment.PdfViewerFragment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * Native AndroidX PDF reader/editor for LexPDF.
 *
 * This Activity deliberately lives outside Flutter and runs in the dedicated
 * :androidxpdf process. The PDF is therefore rendered by Google's AndroidX PDF
 * stack and annotations are authored by AndroidX Ink. No commercial SDK or
 * evaluation watermark participates in this path.
 */
@OptIn(ExperimentalPdfApi::class)
class AndroidxPdfActivity : AppCompatActivity() {
    companion object {
        const val EXTRA_PATH = "lexpdf.androidx_pdf.path"
        const val EXTRA_INITIAL_PAGE = "lexpdf.androidx_pdf.initial_page"

        private const val TAG_VIEWER = "lexpdf_androidx_pdf_viewer"
        private const val MIN_VIEWER_EXTENSION = 13
        private const val MIN_EDIT_EXTENSION = 18
    }

    private lateinit var sourceFile: File
    private lateinit var statusText: TextView
    private lateinit var saveButton: Button
    private lateinit var searchButton: Button
    private var viewerFragment: PdfViewerFragment? = null
    private var extensionS: Int = 0
    private var editable = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val path = intent.getStringExtra(EXTRA_PATH)
        if (path.isNullOrBlank()) {
            finish()
            return
        }
        sourceFile = File(path)
        if (!sourceFile.isFile || sourceFile.length() <= 0L) {
            Toast.makeText(this, "O PDF não está disponível.", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        extensionS =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                SdkExtensions.getExtensionVersion(Build.VERSION_CODES.S)
            } else {
                0
            }
        editable = extensionS >= MIN_EDIT_EXTENSION

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(250, 250, 250))
        }

        val toolbar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(8.dp, 6.dp, 8.dp, 6.dp)
            setBackgroundColor(Color.rgb(245, 247, 250))
        }

        val backButton = Button(this).apply {
            text = "Voltar"
            setOnClickListener { requestClose() }
        }
        toolbar.addView(backButton)

        val title = TextView(this).apply {
            text = sourceFile.name
            textSize = 16f
            setTextColor(Color.rgb(25, 25, 25))
            maxLines = 1
            setPadding(10.dp, 0, 10.dp, 0)
        }
        toolbar.addView(
            title,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )

        statusText = TextView(this).apply {
            textSize = 12f
            setTextColor(Color.rgb(80, 80, 80))
            setPadding(8.dp, 0, 8.dp, 0)
            text = capabilityLabel()
        }
        toolbar.addView(statusText)

        searchButton = Button(this).apply {
            text = "Buscar"
            isEnabled = extensionS >= MIN_VIEWER_EXTENSION
            setOnClickListener {
                viewerFragment?.isTextSearchActive = true
            }
        }
        toolbar.addView(searchButton)

        saveButton = Button(this).apply {
            text = "Salvar"
            visibility = if (editable) View.VISIBLE else View.GONE
            isEnabled = false
            setOnClickListener { saveEdits() }
        }
        toolbar.addView(saveButton)

        root.addView(
            toolbar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        val container = FrameLayout(this).apply {
            id = View.generateViewId()
            setBackgroundColor(Color.DKGRAY)
        }
        root.addView(
            container,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        setContentView(root)

        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    requestClose()
                }
            },
        )

        if (extensionS < MIN_VIEWER_EXTENSION) {
            showUnsupported(container)
            return
        }

        if (savedInstanceState == null) {
            viewerFragment =
                if (editable) {
                    LexPdfEditableFragment.newInstance(sourceFile.absolutePath)
                } else {
                    LexPdfViewerFragment()
                }

            supportFragmentManager
                .beginTransaction()
                .replace(container.id, viewerFragment!!, TAG_VIEWER)
                .commitNow()

            viewerFragment!!.documentUri = Uri.fromFile(sourceFile)
        } else {
            viewerFragment =
                supportFragmentManager.findFragmentByTag(TAG_VIEWER) as? PdfViewerFragment
        }
    }

    private fun capabilityLabel(): String {
        return when {
            extensionS >= MIN_EDIT_EXTENSION ->
                "AndroidX PDF + Ink • S ext $extensionS"
            extensionS >= MIN_VIEWER_EXTENSION ->
                "AndroidX PDF • S ext $extensionS • tinta requer 18"
            else ->
                "SDK Extension S $extensionS • requer 13"
        }
    }

    private fun showUnsupported(container: FrameLayout) {
        val message = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 17f
            gravity = Gravity.CENTER
            setPadding(28.dp, 28.dp, 28.dp, 28.dp)
            text =
                "Este dispositivo possui SDK Extension S $extensionS. " +
                    "O AndroidX PDF requer extensão 13 para leitura e 18 para " +
                    "anotações com AndroidX Ink."
        }
        container.addView(
            message,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    fun onEditModeChanged(enabled: Boolean) {
        saveButton.isEnabled = enabled
        statusText.text =
            if (enabled) {
                "Caneta/Ink ativo • Salve antes de sair"
            } else {
                capabilityLabel()
            }
    }

    fun onSaveStarted() {
        saveButton.isEnabled = false
        statusText.text = "Salvando anotações no PDF…"
    }

    fun onSaveFinished(success: Boolean, error: Throwable? = null) {
        if (success) {
            statusText.text = "Anotações salvas • AndroidX PDF + Ink"
            Toast.makeText(this, "Anotações salvas no PDF.", Toast.LENGTH_SHORT).show()
        } else {
            saveButton.isEnabled = true
            statusText.text = "Falha ao salvar"
            Toast.makeText(
                this,
                "Não foi possível salvar: ${error?.message ?: "erro desconhecido"}",
                Toast.LENGTH_LONG,
            ).show()
        }
    }

    private fun saveEdits() {
        val fragment = viewerFragment as? LexPdfEditableFragment ?: return
        if (fragment.isApplyEditsInProgress) return
        if (!fragment.hasUnsavedChanges) {
            Toast.makeText(this, "Não há alterações pendentes.", Toast.LENGTH_SHORT).show()
            return
        }
        onSaveStarted()
        fragment.applyDraftEdits()
    }

    private fun requestClose() {
        val fragment = viewerFragment as? LexPdfEditableFragment
        if (fragment == null || !fragment.hasUnsavedChanges) {
            finish()
            return
        }

        AlertDialog.Builder(this)
            .setTitle("Salvar anotações?")
            .setMessage("Há escrita ou marcações ainda não salvas neste PDF.")
            .setPositiveButton("Salvar") { _, _ -> saveEdits() }
            .setNegativeButton("Descartar") { _, _ -> finish() }
            .setNeutralButton("Cancelar", null)
            .show()
    }

    private val Int.dp: Int
        get() = (this * resources.displayMetrics.density).toInt()
}

/**
 * Read-only fallback for devices with AndroidX PDF support (ext >= 13) that do
 * not yet expose the extension level required by EditablePdfViewerFragment.
 */
class LexPdfViewerFragment : PdfViewerFragment()

/**
 * AndroidX PDF + AndroidX Ink editor. The fragment enters edit mode as soon as
 * the document is loaded so an S Pen can start authoring without returning to
 * Flutter/PDFium.
 */
@OptIn(ExperimentalPdfApi::class)
class LexPdfEditableFragment : EditablePdfViewerFragment() {
    private lateinit var sourceFile: File

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val path = requireArguments().getString(ARG_PATH)
        require(!path.isNullOrBlank())
        sourceFile = File(path)
    }

    override fun onLoadDocumentSuccess(document: PdfDocument) {
        super.onLoadDocumentSuccess(document)
        isEditModeEnabled = true
        (activity as? AndroidxPdfActivity)?.onEditModeChanged(true)
    }

    override fun onEnterEditMode() {
        super.onEnterEditMode()
        (activity as? AndroidxPdfActivity)?.onEditModeChanged(true)
    }

    override fun onExitEditMode() {
        super.onExitEditMode()
        (activity as? AndroidxPdfActivity)?.onEditModeChanged(false)
    }

    override fun onApplyEditsSuccess(handle: PdfWriteHandle) {
        super.onApplyEditsSuccess(handle)
        val host = activity as? AndroidxPdfActivity
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val parent = sourceFile.parentFile ?: error("Diretório do PDF indisponível.")
                    val temporary = File(parent, ".${sourceFile.name}.lexpdf-save.tmp")
                    if (temporary.exists()) temporary.delete()

                    val descriptor =
                        ParcelFileDescriptor.open(
                            temporary,
                            ParcelFileDescriptor.MODE_CREATE or
                                ParcelFileDescriptor.MODE_TRUNCATE or
                                ParcelFileDescriptor.MODE_READ_WRITE,
                        )
                    try {
                        handle.writeTo(descriptor)
                    } finally {
                        descriptor.close()
                        handle.close()
                    }

                    try {
                        Files.move(
                            temporary.toPath(),
                            sourceFile.toPath(),
                            StandardCopyOption.REPLACE_EXISTING,
                            StandardCopyOption.ATOMIC_MOVE,
                        )
                    } catch (_: Throwable) {
                        temporary.copyTo(sourceFile, overwrite = true)
                        temporary.delete()
                    }
                }
                isEditModeEnabled = false
                host?.onSaveFinished(true)
            } catch (error: Throwable) {
                try {
                    handle.close()
                } catch (_: Throwable) {
                }
                host?.onSaveFinished(false, error)
            }
        }
    }

    override fun onApplyEditsFailed(error: Throwable) {
        super.onApplyEditsFailed(error)
        (activity as? AndroidxPdfActivity)?.onSaveFinished(false, error)
    }

    companion object {
        private const val ARG_PATH = "source_path"

        fun newInstance(path: String): LexPdfEditableFragment {
            return LexPdfEditableFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_PATH, path)
                }
            }
        }
    }
}
