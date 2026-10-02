package com.lexpdf.lexpdf_app

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextUtils
import android.text.InputType
import android.text.TextWatcher
import android.util.Base64
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.widget.TextViewCompat
import androidx.ink.authoring.InProgressStrokeId
import androidx.ink.authoring.InProgressStrokesFinishedListener
import androidx.ink.authoring.InProgressStrokesView
import androidx.ink.brush.Brush
import androidx.ink.brush.StockBrushes
import androidx.ink.rendering.android.canvas.CanvasStrokeRenderer
import androidx.ink.rendering.android.view.ViewStrokeRenderer
import androidx.ink.storage.decode
import androidx.ink.storage.encode
import androidx.ink.strokes.Stroke
import androidx.ink.strokes.StrokeInputBatch
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.util.ArrayDeque
import java.util.concurrent.Executors
import kotlin.math.hypot
import kotlin.math.roundToInt

/**
 * LexPDF Android reader based on Mozilla PDF.js inside the system WebView.
 *
 * The PDF is read on demand through PDF.js PDFDataRangeTransport. Native
 * reads stay bounded and reuse one RandomAccessFile for the reader session,
 * avoiding full-document copies and repeated file-open overhead. AndroidX Ink
 * remains native and independent from the renderer so S Pen input does not
 * depend on any PDF SDK.
 */
class NativePdfReaderActivity : AppCompatActivity(), InProgressStrokesFinishedListener {
    companion object {
        const val EXTRA_PATH = "lexpdf.native_reader.path"
        const val EXTRA_INITIAL_PAGE = "lexpdf.native_reader.initial_page"
        const val EXTRA_LAST_PAGE = "lexpdf.native_reader.last_page"

        private const val LOCAL_ORIGIN = "https://lexpdf.local"
        private const val VIEWER_URL = "$LOCAL_ORIGIN/viewer.html"
        private const val PDFJS_VERSION = "6.3.289"
        private const val RANGE_CHUNK_SIZE = 512 * 1024
        private const val SIDECAR_VERSION = 3
        private const val INK_PREFS = "native_reader_ink"
        private const val PREF_PEN_COLOR = "pen_color"
        private const val PREF_PEN_SIZE = "pen_size"
        private const val PREF_HIGHLIGHT_COLOR = "highlight_color"
        private const val PREF_HIGHLIGHT_SIZE = "highlight_size"
        private const val ACTION_UNDERLINE = 0x4C5801
        private const val ACTION_STRIKE = 0x4C5802
        private const val ACTION_HIGHLIGHT = 0x4C5803
        private const val ACTION_REMOVE_MARKUP = 0x4C5804
        private const val ACTION_UNDO_MARKUP = 0x4C5805
        private const val ACTION_REDO_MARKUP = 0x4C5806
        @Volatile
        private var webViewDirectoryConfigured = false
    }

    private enum class InkKind { PEN, HIGHLIGHTER }

    private enum class ReaderViewMode { PAGE, CONTINUOUS_VERTICAL, CONTINUOUS_HORIZONTAL }

    private enum class TextMarkupKind { HIGHLIGHT, UNDERLINE, STRIKE }

    private data class TextMarkupRect(
        val x: Float,
        val y: Float,
        val width: Float,
        val height: Float,
    )

    private data class TextMarkup(
        val kind: TextMarkupKind,
        val colorArgb: Int,
        val rects: List<TextMarkupRect>,
    )

    private enum class InkTool { PEN, HIGHLIGHTER, ERASER }

    private sealed interface InkHistoryAction {
        data class Added(val entry: InkEntry) : InkHistoryAction
        data class Removed(val index: Int, val entry: InkEntry) : InkHistoryAction
    }

    private data class InkStyle(
        val kind: InkKind,
        val colorArgb: Int,
        val size: Float,
    )

    private data class InkEntry(
        val style: InkStyle,
        val stroke: Stroke,
    )

    private data class OutlineEntry(
        val title: String,
        val page: Int?,
        val pageLabel: String?,
        val depth: Int,
        val source: String,
    )

    private data class PageMetrics(
        val pageIndex: Int,
        val pageWidth: Float,
        val pageHeight: Float,
        val canvasLeft: Float,
        val canvasTop: Float,
        val canvasWidth: Float,
        val canvasHeight: Float,
    )

    private lateinit var sourceFile: File
    private var rangeReader: RandomAccessFile? = null
    private lateinit var webView: WebView
    private lateinit var highlighterInkView: DryInkView
    private lateinit var penInkView: DryInkView
    private lateinit var wetInkView: InProgressStrokesView
    private lateinit var pageLabel: TextView
    private lateinit var readingPageIndicator: TextView
    private lateinit var toolbarContainer: View
    private lateinit var statusLabel: TextView
    private lateinit var penButton: Button
    private lateinit var highlighterButton: Button
    private lateinit var eraserButton: Button
    private lateinit var readerFrame: StylusRouterLayout
    private lateinit var searchBar: LinearLayout
    private lateinit var searchInput: EditText
    private lateinit var searchCountLabel: TextView
    private val searchHandler = Handler(Looper.getMainLooper())
    private var searchWholeWord = false
    private var searchCaseSensitive = false
    private var pendingSearchRunnable: Runnable? = null
    private val readerChromeHandler = Handler(Looper.getMainLooper())
    private val hideReaderChromeRunnable = Runnable { setReaderChromeVisible(false) }
    private var readerChromeVisible = true
    private var readerViewMode = ReaderViewMode.PAGE

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var currentPageIndex = 0
    private var pageCount = 0
    private var pageMetrics: PageMetrics? = null

    private var currentKind = InkKind.PEN
    private var currentTool = InkTool.PEN
    private var fingerInkEnabled = false
    private var penColor = Color.rgb(20, 24, 30)
    private var penSize = 3.0f
    private var highlighterColor = Color.argb(72, 255, 224, 64)
    private var highlighterSize = 18f
    private val currentEntries = mutableListOf<InkEntry>()
    private val currentTextMarkups = mutableListOf<TextMarkup>()
    private val textMarkupUndoHistory = ArrayDeque<List<TextMarkup>>()
    private val textMarkupRedoHistory = ArrayDeque<List<TextMarkup>>()
    private val undoHistory = ArrayDeque<InkHistoryAction>()
    private val redoHistory = ArrayDeque<InkHistoryAction>()
    private var eraserGestureActive = false
    private val erasedThisGesture = mutableSetOf<InkEntry>()
    private val strokeStyles = mutableMapOf<InProgressStrokeId, InkStyle>()
    private val outlineEntries = mutableListOf<OutlineEntry>()
    private val pageLabels = mutableListOf<String>()
    private var outlineLoaded = false
    private var outlineSource = "none"

    override fun onCreate(savedInstanceState: Bundle?) {
        PdfCrashDiagnostics.installUncaughtExceptionCapture(this)

        // This activity runs in :pdfreader. Android 9+ requires every
        // additional process that uses WebView to have its own data directory.
        // This MUST execute before WebView is initialized in this process.
        configureWebViewProcessStorage()

        super.onCreate(savedInstanceState)
        PdfCrashDiagnostics.mark(this, "JS01_ACTIVITY_CREATED")

        val path = intent.getStringExtra(EXTRA_PATH)
        if (path.isNullOrBlank()) {
            finish()
            return
        }
        sourceFile = File(path)
        if (!sourceFile.isFile || sourceFile.length() <= 0L) {
            Toast.makeText(this, "PDF indisponível.", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        rangeReader = RandomAccessFile(sourceFile, "r")
        loadInkPreferences()

        currentPageIndex =
            (intent.getIntExtra(EXTRA_INITIAL_PAGE, 1) - 1).coerceAtLeast(0)
        publishLastPageResult()

        PdfCrashDiagnostics.mark(
            this,
            "JS02_SOURCE_READY",
            "size=${sourceFile.length()} pathHash=${sourceFile.absolutePath.hashCode()}",
        )

        buildUi()
        configureWebView()
        loadInkForPage(currentPageIndex)
        loadTextMarkupsForPage(currentPageIndex)
        PdfCrashDiagnostics.mark(this, "JS03_BEFORE_LOAD_VIEWER")
        webView.loadUrl(VIEWER_URL)
    }

    private fun configureWebViewProcessStorage() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || webViewDirectoryConfigured) {
            return
        }

        synchronized(NativePdfReaderActivity::class.java) {
            if (!webViewDirectoryConfigured) {
                WebView.setDataDirectorySuffix("pdfreader")
                webViewDirectoryConfigured = true
            }
        }
    }

    private fun buildUi() {
        val darkUi =
            (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
        val toolbarBackground =
            if (darkUi) Color.rgb(27, 29, 34) else Color.rgb(248, 249, 251)
        val toolbarForeground =
            if (darkUi) Color.rgb(244, 246, 249) else Color.rgb(30, 33, 38)
        val toolbarSecondary =
            if (darkUi) Color.rgb(190, 194, 201) else Color.rgb(65, 68, 74)
        val landscape =
            resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val screenWidthDp = resources.configuration.screenWidthDp
        val useOverflowMenu = !landscape && screenWidthDp < 600
        val compactToolbar = landscape || useOverflowMenu

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(20, 22, 26))
        }

        fun toolRow(): LinearLayout =
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(6.dp, 3.dp, 6.dp, 3.dp)
                setBackgroundColor(toolbarBackground)
            }

        fun button(label: String, onClick: () -> Unit): Button =
            Button(this).apply {
                text = label
                isAllCaps = false

                val targetWidthDp =
                    when {
                        label == "⋮" -> 46
                        label.length <= 1 -> if (compactToolbar) 38 else 42
                        label == "Ir" -> if (compactToolbar) 44 else 48
                        label.contains("Página") -> if (compactToolbar) 78 else 86
                        label.length <= 5 -> if (compactToolbar) 58 else 64
                        label.length <= 7 -> if (compactToolbar) 64 else 72
                        else -> if (compactToolbar) 72 else 80
                    }
                minWidth = targetWidthDp.dp
                minimumWidth = targetWidthDp.dp
                setMinWidth(targetWidthDp.dp)

                setSingleLine(true)
                maxLines = 1
                setHorizontallyScrolling(false)
                includeFontPadding = false
                ellipsize = TextUtils.TruncateAt.END
                TextViewCompat.setAutoSizeTextTypeUniformWithConfiguration(
                    this,
                    8,
                    13,
                    1,
                    TypedValue.COMPLEX_UNIT_SP,
                )
                setPadding(8.dp, 0, 8.dp, 0)
                isClickable = true
                isFocusable = true
                setOnTouchListener { view, event ->
                    when (event.actionMasked) {
                        MotionEvent.ACTION_DOWN,
                        MotionEvent.ACTION_MOVE,
                        -> view.parent?.requestDisallowInterceptTouchEvent(true)

                        MotionEvent.ACTION_UP,
                        MotionEvent.ACTION_CANCEL,
                        -> view.parent?.requestDisallowInterceptTouchEvent(false)
                    }
                    false
                }
                setOnClickListener { onClick() }
            }

        fun showOverflowMenu(anchor: View) {
            PopupMenu(this, anchor).apply {
                menu.add("Zoom −")
                menu.add("Zoom +")
                menu.add("Página inteira")
                menu.add("Modo de leitura")
                menu.add("Selecionar texto")
                menu.add("Caneta")
                menu.add("Marca-texto")
                menu.add("Borracha")
                menu.add("Desfazer")
                menu.add("Refazer")
                menu.add("Desfazer marcação")
                menu.add("Refazer marcação")
                menu.add("Fechar")
                setOnMenuItemClickListener { item ->
                    when (item.title.toString()) {
                        "Zoom −" -> js("LexPDF.zoomOut()")
                        "Zoom +" -> js("LexPDF.zoomIn()")
                        "Página inteira" -> js("LexPDF.fitPage()")
                        "Modo de leitura" -> showReaderViewModeDialog()
                        "Selecionar texto" -> selectTextMode()
                        "Caneta" -> selectInk(InkKind.PEN)
                        "Marca-texto" -> selectInk(InkKind.HIGHLIGHTER)
                        "Borracha" -> selectEraser()
                        "Desfazer" -> undoInk()
                        "Refazer" -> redoInk()
                        "Desfazer marcação" -> undoTextMarkup()
                        "Refazer marcação" -> redoTextMarkup()
                        "Fechar" -> finish()
                        else -> return@setOnMenuItemClickListener false
                    }
                    true
                }
                show()
            }
        }

        penButton =
            button("Caneta") {
                selectInk(InkKind.PEN)
            }.apply {
                setOnLongClickListener {
                    showInkSettings(InkKind.PEN)
                    true
                }
            }
        highlighterButton =
            button("Marca") {
                selectInk(InkKind.HIGHLIGHTER)
            }.apply {
                setOnLongClickListener {
                    showInkSettings(InkKind.HIGHLIGHTER)
                    true
                }
            }
        eraserButton =
            button("Borracha") {
                selectEraser()
            }.apply {
                contentDescription = "Apagar traços da caneta e do marca-texto"
            }

        statusLabel = TextView(this).apply {
            textSize = 12f
            gravity = Gravity.CENTER_VERTICAL
            setTextColor(toolbarSecondary)
            setPadding(10.dp, 0, 10.dp, 0)
            setSingleLine(true)
            text = "PDF.js iniciando…"
        }

        val unifiedToolbarRow = toolRow()
        unifiedToolbarRow.addView(button("‹") { js("LexPDF.previousPage()") })

        pageLabel = TextView(this).apply {
            gravity = Gravity.CENTER
            textSize = 14f
            setTextColor(toolbarForeground)
            text = "…"
            isClickable = true
            isFocusable = true
            setOnClickListener { showPageJumpDialog() }
        }
        unifiedToolbarRow.addView(
            pageLabel,
            LinearLayout.LayoutParams(
                if (useOverflowMenu) 76.dp else if (landscape) 96.dp else 110.dp,
                LinearLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        if (!useOverflowMenu) {
            unifiedToolbarRow.addView(button("Ir") { showPageJumpDialog() })
        }
        unifiedToolbarRow.addView(button("›") { js("LexPDF.nextPage()") })
        unifiedToolbarRow.addView(button("Buscar") { showSearchBar() })
        unifiedToolbarRow.addView(button("Índice") { showOutlineDialog() })

        if (useOverflowMenu) {
            val overflowButton = button("⋮") {}
            overflowButton.contentDescription = "Mais opções"
            overflowButton.setOnClickListener { showOverflowMenu(overflowButton) }
            unifiedToolbarRow.addView(overflowButton)
        } else {
            unifiedToolbarRow.addView(button("−") { js("LexPDF.zoomOut()") })
            unifiedToolbarRow.addView(button("+") { js("LexPDF.zoomIn()") })
            unifiedToolbarRow.addView(
                button("⛶ Página") { js("LexPDF.fitPage()") }.apply {
                    contentDescription = "Página inteira"
                },
            )
            unifiedToolbarRow.addView(
                button("Modo") { showReaderViewModeDialog() }.apply {
                    contentDescription = "Modo de leitura"
                },
            )
            unifiedToolbarRow.addView(
                button("Texto") { selectTextMode() }.apply {
                    contentDescription = "Selecionar texto"
                },
            )
            unifiedToolbarRow.addView(penButton)
            unifiedToolbarRow.addView(highlighterButton)
            unifiedToolbarRow.addView(eraserButton)
            unifiedToolbarRow.addView(button("Desfazer") { undoInk() })
            unifiedToolbarRow.addView(button("Refazer") { redoInk() })
            unifiedToolbarRow.addView(
                statusLabel,
                LinearLayout.LayoutParams(
                    if (landscape) 126.dp else 150.dp,
                    LinearLayout.LayoutParams.MATCH_PARENT,
                ),
            )
            unifiedToolbarRow.addView(button("Fechar") { finish() })
        }

        toolbarContainer =
            if (useOverflowMenu) {
                unifiedToolbarRow
            } else {
                HorizontalScrollView(this).apply {
                    isHorizontalScrollBarEnabled = false
                    isHorizontalFadingEdgeEnabled = true
                    setFadingEdgeLength(12.dp)
                    isFillViewport = false
                    overScrollMode = View.OVER_SCROLL_NEVER
                    addView(
                        unifiedToolbarRow,
                        FrameLayout.LayoutParams(
                            FrameLayout.LayoutParams.WRAP_CONTENT,
                            FrameLayout.LayoutParams.MATCH_PARENT,
                        ),
                    )
                }
            }

        root.addView(
            toolbarContainer,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                48.dp,
            ),
        )

        searchBar = buildSearchBar()
        root.addView(
            searchBar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                52.dp,
            ),
        )
        searchBar.visibility = View.GONE

        readerFrame = StylusRouterLayout(this).apply {
            setBackgroundColor(Color.rgb(24, 26, 31))
            onStylusEvent = { event -> handleStylusEvent(event) }
            interceptFingerInput = false
        }

        webView =
            SelectionAwareWebView(
                this,
                ::selectionActionModeCallback,
            ).apply {
                isLongClickable = true
                isHapticFeedbackEnabled = true
            }
        readerFrame.addView(
            webView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        // Highlighter is isolated from pen strokes but uses ordinary transparent
        // compositing. Applying MULTIPLY to the whole Android view can black out
        // the WebView on some Samsung/GPU combinations.
        highlighterInkView =
            DryInkView(
                this,
                { pageToViewMatrix() },
                InkKind.HIGHLIGHTER,
            )
        readerFrame.addView(
            highlighterInkView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        // Pen stays on a normal alpha-composited layer above the highlighter.
        penInkView =
            DryInkView(
                this,
                { pageToViewMatrix() },
                InkKind.PEN,
            )
        readerFrame.addView(
            penInkView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        wetInkView = InProgressStrokesView(this).apply {
            isClickable = false
            isFocusable = false
            addFinishedStrokesListener(this@NativePdfReaderActivity)
            eagerInit()
        }
        readerFrame.addView(
            wetInkView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        readingPageIndicator = TextView(this).apply {
            gravity = Gravity.CENTER
            textSize = 12f
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.argb(168, 24, 26, 31))
            setPadding(12.dp, 5.dp, 12.dp, 5.dp)
            isClickable = false
            isFocusable = false
            visibility = View.GONE
            text = "…"
        }
        readerFrame.addView(
            readingPageIndicator,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
            ).apply {
                bottomMargin = 14.dp
            },
        )

        root.addView(
            readerFrame,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        WindowCompat.setDecorFitsSystemWindows(window, false)
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val safe = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or
                    WindowInsetsCompat.Type.displayCutout(),
            )
            view.setPadding(safe.left, safe.top, safe.right, safe.bottom)
            insets
        }
        setContentView(root)
        ViewCompat.requestApplyInsets(root)
        selectTextMode()
        scheduleReaderChromeAutoHide()
    }

    private fun setReaderChromeVisible(visible: Boolean, autoHide: Boolean = true) {
        if (!::toolbarContainer.isInitialized || !::readingPageIndicator.isInitialized) return
        if (!visible && ::searchBar.isInitialized && searchBar.visibility == View.VISIBLE) return

        readerChromeHandler.removeCallbacks(hideReaderChromeRunnable)
        readerChromeVisible = visible
        toolbarContainer.visibility = if (visible) View.VISIBLE else View.GONE
        readingPageIndicator.visibility = if (visible) View.GONE else View.VISIBLE

        if (visible && autoHide) {
            scheduleReaderChromeAutoHide()
        }
    }

    private fun scheduleReaderChromeAutoHide() {
        readerChromeHandler.removeCallbacks(hideReaderChromeRunnable)
        if (::searchBar.isInitialized && searchBar.visibility == View.VISIBLE) return
        readerChromeHandler.postDelayed(hideReaderChromeRunnable, 3200L)
    }

    private fun toggleReaderChrome() {
        setReaderChromeVisible(!readerChromeVisible)
    }

    private fun showReaderViewModeDialog() {
        val labels =
            arrayOf(
                "Página",
                "Contínuo vertical",
                "Contínuo horizontal",
            )
        val checked =
            when (readerViewMode) {
                ReaderViewMode.PAGE -> 0
                ReaderViewMode.CONTINUOUS_VERTICAL -> 1
                ReaderViewMode.CONTINUOUS_HORIZONTAL -> 2
            }

        AlertDialog.Builder(this)
            .setTitle("Modo de leitura")
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                readerViewMode =
                    when (which) {
                        1 -> ReaderViewMode.CONTINUOUS_VERTICAL
                        2 -> ReaderViewMode.CONTINUOUS_HORIZONTAL
                        else -> ReaderViewMode.PAGE
                    }
                js(
                    "LexPDF.setViewMode(" +
                        JSONObject.quote(readerViewMode.name.lowercase()) +
                        ")",
                )
                dialog.dismiss()
                scheduleReaderChromeAutoHide()
            }
            .setNegativeButton("Cancelar", null)
            .show()
    }

    private fun buildSearchBar(): LinearLayout {
        val darkUi =
            (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
        val searchBackground =
            if (darkUi) Color.rgb(35, 38, 44) else Color.rgb(242, 244, 247)
        val searchForeground =
            if (darkUi) Color.rgb(244, 246, 249) else Color.rgb(30, 33, 38)
        val searchSecondary =
            if (darkUi) Color.rgb(190, 194, 201) else Color.rgb(90, 94, 101)
        val searchAccent =
            if (darkUi) Color.rgb(128, 203, 196) else Color.rgb(0, 121, 107)

        val row =
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(10.dp, 4.dp, 6.dp, 4.dp)
                setBackgroundColor(searchBackground)
            }

        searchInput =
            EditText(this).apply {
                hint = "Localizar palavra ou frase"
                setSingleLine(true)
                textSize = 15f
                setTextColor(searchForeground)
                setHintTextColor(searchSecondary)
                backgroundTintList = ColorStateList.valueOf(searchAccent)
                inputType = InputType.TYPE_CLASS_TEXT
                imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH
                setPadding(8.dp, 0, 8.dp, 0)
                addTextChangedListener(
                    object : TextWatcher {
                        override fun beforeTextChanged(
                            s: CharSequence?,
                            start: Int,
                            count: Int,
                            after: Int,
                        ) = Unit

                        override fun onTextChanged(
                            s: CharSequence?,
                            start: Int,
                            before: Int,
                            count: Int,
                        ) {
                            scheduleNativeSearch()
                        }

                        override fun afterTextChanged(s: Editable?) = Unit
                    },
                )
                setOnEditorActionListener { _, _, _ ->
                    startNativeSearch()
                    true
                }
            }
        row.addView(
            searchInput,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f),
        )

        searchCountLabel =
            TextView(this).apply {
                gravity = Gravity.CENTER
                textSize = 13f
                setTextColor(searchForeground)
                text = "0/0"
            }
        row.addView(
            searchCountLabel,
            LinearLayout.LayoutParams(64.dp, LinearLayout.LayoutParams.MATCH_PARENT),
        )

        fun compactButton(label: String, action: () -> Unit): Button =
            Button(this).apply {
                text = label
                isAllCaps = false
                minWidth = 44.dp
                minimumWidth = 44.dp
                setSingleLine(true)
                setPadding(5.dp, 0, 5.dp, 0)
                setOnClickListener { action() }
            }

        row.addView(compactButton("‹") { js("LexPDF.previousSearchMatch()") })
        row.addView(compactButton("›") { js("LexPDF.nextSearchMatch()") })
        row.addView(compactButton("⋯") { showSearchOptionsDialog() })
        row.addView(compactButton("×") { hideSearchBar() })
        return row
    }

    private fun showSearchBar() {
        setReaderChromeVisible(true, autoHide = false)
        searchBar.visibility = View.VISIBLE
        searchInput.requestFocus()
        searchInput.selectAll()
        searchInput.post {
            val keyboard = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            keyboard?.showSoftInput(searchInput, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun hideSearchBar() {
        pendingSearchRunnable?.let { searchHandler.removeCallbacks(it) }
        pendingSearchRunnable = null
        searchInput.clearFocus()
        val keyboard = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        keyboard?.hideSoftInputFromWindow(searchInput.windowToken, 0)
        searchBar.visibility = View.GONE
        searchCountLabel.text = "0/0"
        js("LexPDF.clearSearch()")
        scheduleReaderChromeAutoHide()
    }

    private fun scheduleNativeSearch() {
        pendingSearchRunnable?.let { searchHandler.removeCallbacks(it) }
        val runnable = Runnable { startNativeSearch() }
        pendingSearchRunnable = runnable
        searchHandler.postDelayed(runnable, 220L)
    }

    private fun startNativeSearch() {
        pendingSearchRunnable?.let { searchHandler.removeCallbacks(it) }
        pendingSearchRunnable = null
        val query = searchInput.text?.toString()?.trim().orEmpty()
        if (query.isBlank()) {
            searchCountLabel.text = "0/0"
            js("LexPDF.clearSearch()")
            return
        }
        val encoded = JSONObject.quote(query)
        js(
            "LexPDF.startSearch(" +
                encoded +
                "," +
                searchCaseSensitive +
                "," +
                searchWholeWord +
                ")",
        )
    }

    private fun showSearchOptionsDialog() {
        val labels =
            arrayOf(
                "Palavra inteira",
                "Diferenciar maiúsculas/minúsculas",
            )
        val values = booleanArrayOf(searchWholeWord, searchCaseSensitive)
        AlertDialog.Builder(this)
            .setTitle("Opções de pesquisa")
            .setMultiChoiceItems(labels, values) { _, which, checked ->
                values[which] = checked
            }
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Aplicar") { _, _ ->
                searchWholeWord = values[0]
                searchCaseSensitive = values[1]
                startNativeSearch()
            }
            .show()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView() {
        webView.setBackgroundColor(Color.rgb(32, 34, 39))
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            cacheMode = WebSettings.LOAD_DEFAULT
            builtInZoomControls = false
            displayZoomControls = false
            setSupportZoom(false)
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }

        WebView.setWebContentsDebuggingEnabled(false)
        webView.addJavascriptInterface(JsBridge(), "LexPdfBridge")
        webView.webViewClient =
            object : WebViewClient() {
                override fun shouldInterceptRequest(
                    view: WebView?,
                    request: WebResourceRequest,
                ): WebResourceResponse? {
                    return when (request.url.toString()) {
                        VIEWER_URL -> htmlResponse()
                        else -> null
                    }
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    if (url == VIEWER_URL) {
                        PdfCrashDiagnostics.mark(
                            this@NativePdfReaderActivity,
                            "JS04_VIEWER_HTML_FINISHED",
                        )
                    }
                }
            }
    }

    private fun htmlResponse(): WebResourceResponse {
        val bytes = viewerHtml().toByteArray(Charsets.UTF_8)
        return WebResourceResponse(
            "text/html",
            "utf-8",
            200,
            "OK",
            mapOf(
                "Content-Length" to bytes.size.toString(),
                "Cache-Control" to "no-store",
            ),
            ByteArrayInputStream(bytes),
        )
    }

    private inner class JsBridge {
        @JavascriptInterface
        fun requestRange(beginText: String, endText: String) {
            val begin = beginText.toLongOrNull() ?: return
            val requestedEnd = endText.toLongOrNull() ?: return
            val fileLength = sourceFile.length()
            if (fileLength <= 0L || begin < 0L || begin >= fileLength) return

            val endExclusive =
                requestedEnd
                    .coerceAtLeast(begin + 1L)
                    .coerceAtMost(fileLength)
            val requestedLength = endExclusive - begin
            if (requestedLength <= 0L || requestedLength > RANGE_CHUNK_SIZE) {
                runOnUiThread {
                    val message =
                        "Faixa inválida solicitada pelo PDF.js: " +
                            "$begin-$endExclusive ($requestedLength bytes)"
                    PdfCrashDiagnostics.mark(
                        this@NativePdfReaderActivity,
                        "JSR_INVALID_RANGE",
                        message,
                    )
                    js("LexPDF.rangeFailure(${JSONObject.quote(message)})")
                }
                return
            }

            ioExecutor.execute {
                try {
                    val bytes = ByteArray(requestedLength.toInt())
                    val file =
                        rangeReader
                            ?: throw IllegalStateException("PDF range reader is closed")
                    file.seek(begin)
                    file.readFully(bytes)
                    val encoded =
                        Base64.encodeToString(bytes, Base64.NO_WRAP)
                    PdfCrashDiagnostics.mark(
                        this@NativePdfReaderActivity,
                        "JSR_NATIVE_RANGE",
                        "start=$begin end=$endExclusive len=${bytes.size}",
                    )
                    runOnUiThread {
                        js(
                            "LexPDF.receiveRange(" +
                                "$begin,${JSONObject.quote(encoded)})",
                        )
                    }
                } catch (error: Throwable) {
                    PdfCrashDiagnostics.recordControlledLaunchFailure(
                        this@NativePdfReaderActivity,
                        error,
                    )
                    val message =
                        "Falha ao ler PDF local em $begin-$endExclusive: " +
                            "${error.javaClass.simpleName}: ${error.message}"
                    runOnUiThread {
                        js("LexPDF.rangeFailure(${JSONObject.quote(message)})")
                    }
                }
            }
        }

        @JavascriptInterface
        fun ready(totalPages: Int) {
            runOnUiThread {
                pageCount = totalPages
                statusLabel.text = "PDF.js • ${sourceFile.length() / (1024 * 1024)} MB"
                updatePageLabel()
                scheduleReaderChromeAutoHide()
                PdfCrashDiagnostics.mark(
                    this@NativePdfReaderActivity,
                    "JS05_DOCUMENT_READY",
                    "pages=$totalPages",
                )
            }
        }

        @JavascriptInterface
        fun pageLabels(json: String) {
            val parsed = mutableListOf<String>()
            try {
                val array = JSONArray(json)
                for (index in 0 until array.length()) {
                    parsed += array.optString(index, (index + 1).toString())
                }
            } catch (_: Throwable) {
                parsed.clear()
            }

            runOnUiThread {
                pageLabels.clear()
                pageLabels += parsed
                updatePageLabel()
            }
        }

        @JavascriptInterface
        fun outline(json: String) {
            val parsed = mutableListOf<OutlineEntry>()
            try {
                val array = JSONArray(json)
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    val title = item.optString("title").trim()
                    if (title.isBlank()) continue
                    val page =
                        if (item.has("page") && !item.isNull("page")) {
                            item.optInt("page").takeIf { it > 0 }
                        } else {
                            null
                        }
                    parsed +=
                        OutlineEntry(
                            title = title,
                            page = page,
                            pageLabel =
                                item
                                    .optString("pageLabel")
                                    .trim()
                                    .takeIf { it.isNotBlank() },
                            depth = item.optInt("depth").coerceIn(0, 8),
                            source = item.optString("source", "outline"),
                        )
                }
            } catch (_: Throwable) {
                parsed.clear()
            }

            runOnUiThread {
                outlineEntries.clear()
                outlineEntries += parsed
                outlineLoaded = true
                outlineSource =
                    parsed.firstOrNull()?.source ?: "none"
                PdfCrashDiagnostics.mark(
                    this@NativePdfReaderActivity,
                    "JS07_OUTLINE_READY",
                    "entries=${parsed.size} source=$outlineSource",
                )
            }
        }

        @JavascriptInterface
        fun searchState(payload: String) {
            runOnUiThread {
                try {
                    val value = JSONObject(payload)
                    val current = value.optInt("current", 0)
                    val total = value.optInt("total", 0)
                    val searching = value.optBoolean("searching", false)
                    searchCountLabel.text =
                        if (searching) {
                            "$current/$total…"
                        } else {
                            "$current/$total"
                        }
                } catch (_: Exception) {
                    searchCountLabel.text = "0/0"
                }
            }
        }

        @JavascriptInterface
        fun readerChromeTap() {
            runOnUiThread {
                toggleReaderChrome()
            }
        }

        @JavascriptInterface
        fun pageChanged(page: Int) {
            runOnUiThread {
                val next = (page - 1).coerceAtLeast(0)
                if (next != currentPageIndex) {
                    persistInkForPage(currentPageIndex)
                    persistTextMarkupsForPage(currentPageIndex)
                    currentPageIndex = next
                    undoHistory.clear()
                    redoHistory.clear()
                    textMarkupUndoHistory.clear()
                    textMarkupRedoHistory.clear()
                    loadInkForPage(next)
                    loadTextMarkupsForPage(next)
                }
                publishLastPageResult()
                updatePageLabel()
            }
        }

        @JavascriptInterface
        fun addTextMarkup(kindText: String, colorArgb: Int, rectsJson: String) {
            val kind =
                when (kindText.lowercase()) {
                    "highlight" -> TextMarkupKind.HIGHLIGHT
                    "underline" -> TextMarkupKind.UNDERLINE
                    "strike" -> TextMarkupKind.STRIKE
                    else -> return
                }

            val rects = mutableListOf<TextMarkupRect>()
            try {
                val array = JSONArray(rectsJson)
                for (index in 0 until array.length()) {
                    val obj = array.optJSONObject(index) ?: continue
                    val width = obj.optDouble("width", 0.0).toFloat()
                    val height = obj.optDouble("height", 0.0).toFloat()
                    if (width <= 0f || height <= 0f) continue
                    rects +=
                        TextMarkupRect(
                            x = obj.optDouble("x", 0.0).toFloat(),
                            y = obj.optDouble("y", 0.0).toFloat(),
                            width = width,
                            height = height,
                        )
                }
            } catch (_: Throwable) {
                return
            }
            if (rects.isEmpty()) return

            runOnUiThread {
                recordTextMarkupHistory()
                currentTextMarkups += TextMarkup(kind, colorArgb, rects)
                persistTextMarkupsForPage(currentPageIndex)
                pushTextMarkupsToViewer()
                js("LexPDF.clearTextSelection()")
            }
        }

        @JavascriptInterface
        fun removeTextMarkupRects(rectsJson: String) {
            val selectionRects = mutableListOf<TextMarkupRect>()
            try {
                val array = JSONArray(rectsJson)
                for (index in 0 until array.length()) {
                    val obj = array.optJSONObject(index) ?: continue
                    val width = obj.optDouble("width", 0.0).toFloat()
                    val height = obj.optDouble("height", 0.0).toFloat()
                    if (width <= 0f || height <= 0f) continue
                    selectionRects +=
                        TextMarkupRect(
                            x = obj.optDouble("x", 0.0).toFloat(),
                            y = obj.optDouble("y", 0.0).toFloat(),
                            width = width,
                            height = height,
                        )
                }
            } catch (_: Throwable) {
                return
            }
            if (selectionRects.isEmpty()) return

            runOnUiThread {
                val updated =
                    currentTextMarkups.mapNotNull { markup ->
                        val remaining =
                            markup.rects.filterNot { rect ->
                                selectionRects.any { selected ->
                                    textMarkupRectsIntersect(rect, selected)
                                }
                            }
                        if (remaining.isEmpty()) null else markup.copy(rects = remaining)
                    }

                if (updated != currentTextMarkups) {
                    recordTextMarkupHistory()
                    currentTextMarkups.clear()
                    currentTextMarkups += updated
                    persistTextMarkupsForPage(currentPageIndex)
                    pushTextMarkupsToViewer()
                }
                js("LexPDF.clearTextSelection()")
            }
        }

        @JavascriptInterface
        fun metrics(json: String) {
            try {
                val obj = JSONObject(json)
                val incoming =
                    PageMetrics(
                        pageIndex = obj.getInt("page") - 1,
                        pageWidth = obj.getDouble("pageWidth").toFloat(),
                        pageHeight = obj.getDouble("pageHeight").toFloat(),
                        canvasLeft = obj.getDouble("left").toFloat(),
                        canvasTop = obj.getDouble("top").toFloat(),
                        canvasWidth = obj.getDouble("width").toFloat(),
                        canvasHeight = obj.getDouble("height").toFloat(),
                    )
                runOnUiThread {
                    if (incoming.pageIndex == currentPageIndex) {
                        pageMetrics = incoming
                        highlighterInkView.invalidate()
                        penInkView.invalidate()
                    }
                }
            } catch (_: Throwable) {
            }
        }

        @JavascriptInterface
        fun error(message: String) {
            runOnUiThread {
                statusLabel.text = "Falha PDF.js"
                Toast.makeText(
                    this@NativePdfReaderActivity,
                    message.take(500),
                    Toast.LENGTH_LONG,
                ).show()
                PdfCrashDiagnostics.mark(
                    this@NativePdfReaderActivity,
                    "JS99_ERROR",
                    message.take(200),
                )
            }
        }

        @JavascriptInterface
        fun rendered(page: Int) {
            runOnUiThread {
                pushTextMarkupsToViewer()
                statusLabel.text =
                    "PDF.js • página $page • S Pen: ${currentEntries.size} traço(s)"
                PdfCrashDiagnostics.mark(
                    this@NativePdfReaderActivity,
                    "JS06_PAGE_VISIBLE",
                    "page=$page",
                )
            }
        }
    }

    private fun viewerHtml(): String {
        return """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
  <style>
    html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#181a1f;color:#fff;font-family:sans-serif}
    #stage{position:absolute;inset:0;overflow:auto;overscroll-behavior:contain}
    #wrap{box-sizing:border-box;width:max-content;min-width:100%;min-height:100%;padding:12px 12px 34px}
    #pageHost{position:relative;display:block;margin:0 auto}
    canvas{display:block;background:white;box-shadow:0 6px 28px #0007}
    #markupLayer{position:absolute;left:0;top:0;overflow:hidden;pointer-events:none}
    #markupLayer .markup{position:absolute;box-sizing:border-box;pointer-events:none}
    #markupLayer .highlight{border-radius:2px}
    #markupLayer .underline::after{content:"";position:absolute;left:0;right:0;bottom:-1px;border-bottom:2px solid currentColor}
    #markupLayer .strike::after{content:"";position:absolute;left:0;right:0;top:50%;border-top:2px solid currentColor}
    #textLayer{position:absolute;left:0;top:0;overflow:hidden;line-height:1;pointer-events:auto;user-select:text;-webkit-user-select:text;touch-action:pan-x pan-y}
    #textLayer span{position:absolute;white-space:pre;color:transparent;cursor:text;transform-origin:0 0;user-select:text;-webkit-user-select:text}
    #textLayer span::selection{background:rgba(37,99,235,.34)}
    #loading{position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);background:#17191dcc;padding:12px 18px;border-radius:18px;font-size:14px}
  </style>
</head>
<body>
<div id="stage"><div id="wrap"><div id="pageHost"><canvas id="pdf"></canvas><div id="markupLayer"></div><div id="textLayer" aria-label="Texto selecionável do PDF"></div></div></div></div>
<div id="loading">Abrindo PDF…</div>
<script type="module">
import * as pdfjsLib from 'https://cdn.jsdelivr.net/npm/pdfjs-dist@${PDFJS_VERSION}/build/pdf.min.mjs';
pdfjsLib.GlobalWorkerOptions.workerSrc =
  'https://cdn.jsdelivr.net/npm/pdfjs-dist@${PDFJS_VERSION}/build/pdf.worker.min.mjs';

const PDF_LENGTH = ${sourceFile.length()};
const RANGE_CHUNK_SIZE = ${RANGE_CHUNK_SIZE};
const canvas = document.getElementById('pdf');
const ctx = canvas.getContext('2d', { alpha: false });
const textLayer = document.getElementById('textLayer');
const markupLayer = document.getElementById('markupLayer');
const pageHost = document.getElementById('pageHost');
const stage = document.getElementById('stage');
const loading = document.getElementById('loading');

let pdf = null;
let pageNumber = ${currentPageIndex + 1};
let scale = 1.15;
let renderToken = 0;
let renderTask = null;
let pageAtScaleOne = { width: 1, height: 1 };
let pinchStartDistance = 0;
let pinchStartScale = scale;
let pinchPreviewScale = scale;
let pinchAnchorPageX = 0;
let pinchAnchorPageY = 0;
let pinchAnchorViewportX = 0;
let pinchAnchorViewportY = 0;
let pinchLastMidpointX = 0;
let pinchLastMidpointY = 0;
let singleTouchStartX = 0;
let singleTouchStartY = 0;
let singleTouchStartScrollTop = 0;
let singleTouchStartedAtTop = false;
let singleTouchStartedAtBottom = false;
let singleTouchStartedAtLeft = false;
let singleTouchStartedAtRight = false;
let singleTouchActive = false;
let readerViewMode = 'page';
let metricsFrame = 0;
let rangeTransport = null;
let rangeFailed = false;
let pdfPageLabels = null;
let inferredPrintedOffset = null;
let printedPaginationReady = false;
const printedToPhysical = new Map();
const physicalToPrinted = new Map();
let numericPaginationSegments = [];

let searchGeneration = 0;
let searchMatches = [];
let searchCurrentIndex = -1;
let searchInProgress = false;
let searchQuery = '';
let searchCaseSensitive = false;
let searchWholeWord = false;

let textLongPressTimer = 0;
let textLongPressStartX = 0;
let textLongPressStartY = 0;
let textLongPressTriggered = false;
let textSelectionAnchorRange = null;
let textSelectionLockScrollTop = 0;
let textSelectionLockScrollLeft = 0;
let capturedSelectionRects = [];
let currentTextMarkups = [];

class NativePdfRangeTransport extends pdfjsLib.PDFDataRangeTransport {
  constructor(length) {
    super(length, new Uint8Array(0), false, 'document.pdf');
  }

  requestDataRange(begin, end) {
    if (rangeFailed) return;

    // PDF.js may request a span larger than rangeChunkSize. Never truncate the
    // request silently: split the entire requested span into bounded native
    // chunks so the original range can be satisfied completely.
    for (let cursor = begin; cursor < end; cursor += RANGE_CHUNK_SIZE) {
      const chunkEnd = Math.min(end, cursor + RANGE_CHUNK_SIZE);
      LexPdfBridge.requestRange(String(cursor), String(chunkEnd));
    }
  }

  abort() {
    rangeFailed = true;
  }
}

function decodeBase64(base64) {
  const raw = atob(base64);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) {
    bytes[i] = raw.charCodeAt(i);
  }
  return bytes;
}

async function loadPageLabels() {
  try {
    const labels = await pdf.getPageLabels();
    if (Array.isArray(labels) && labels.length === pdf.numPages) {
      pdfPageLabels = labels.map((label, index) =>
        String(label ?? (index + 1))
      );
      LexPdfBridge.pageLabels(JSON.stringify(pdfPageLabels));
    } else {
      pdfPageLabels = null;
      LexPdfBridge.pageLabels('[]');
    }
  } catch (_) {
    pdfPageLabels = null;
    LexPdfBridge.pageLabels('[]');
  }
}

function normalizedLabel(value) {
  return String(value ?? '')
    .trim()
    .replace(/^p(?:ágina)?\.?\s*/i, '')
    .toLowerCase();
}

function pageLabelForPhysical(page) {
  if (pdfPageLabels && page >= 1 && page <= pdfPageLabels.length) {
    return String(pdfPageLabels[page - 1]);
  }

  const direct = physicalToPrinted.get(page);
  if (direct) return String(direct);

  for (const segment of numericPaginationSegments) {
    if (page < segment.physicalStart || page > segment.physicalEnd) continue;
    const printed = page - segment.offset;
    if (printed >= segment.printedStart && printed <= segment.printedEnd) {
      return String(printed);
    }
  }

  if (Number.isInteger(inferredPrintedOffset)) {
    const printed = page - inferredPrintedOffset;
    if (printed >= 1) return String(printed);
  }

  return String(page);
}

function segmentPhysicalPageForPrintedNumber(printed) {
  const candidates = numericPaginationSegments
    .filter(segment =>
      printed >= segment.printedStart - 2 &&
      printed <= segment.printedEnd + 2
    )
    .map(segment => ({
      physical: printed + segment.offset,
      distance:
        printed < segment.printedStart
          ? segment.printedStart - printed
          : printed > segment.printedEnd
            ? printed - segment.printedEnd
            : 0,
      confidence: segment.confidence
    }))
    .filter(item => item.physical >= 1 && item.physical <= pdf.numPages)
    .sort((a, b) =>
      a.distance - b.distance ||
      b.confidence - a.confidence ||
      a.physical - b.physical
    );

  return candidates.length ? candidates[0].physical : null;
}

function physicalPageForPrintedLabel(label) {
  const normalized = normalizedLabel(label);
  if (!normalized) return null;

  if (pdfPageLabels) {
    const match = pdfPageLabels.findIndex(
      value => normalizedLabel(value) === normalized
    );
    if (match >= 0) return match + 1;
  }

  // Exact visual-page detections always win over any inferred model.
  const direct = printedToPhysical.get(normalized);
  if (direct) return direct;

  const numeric = Number.parseInt(normalized, 10);
  if (Number.isInteger(numeric)) {
    const segmented = segmentPhysicalPageForPrintedNumber(numeric);
    if (segmented) return segmented;

    if (Number.isInteger(inferredPrintedOffset)) {
      const candidate = numeric + inferredPrintedOffset;
      if (candidate >= 1 && candidate <= pdf.numPages) return candidate;
    }
  }

  // Never assume printed page N == physical PDF page N. That fallback is the
  // source of wrong TOC jumps in PDFs with covers/front matter.
  return null;
}

function publishDerivedPageLabels() {
  if (pdfPageLabels || !printedPaginationReady) return;
  const labels = [];
  for (let physical = 1; physical <= pdf.numPages; physical++) {
    labels.push(pageLabelForPhysical(physical));
  }
  LexPdfBridge.pageLabels(JSON.stringify(labels));
}

function parsePrintedPageLabel(text) {
  const cleaned = String(text ?? '')
    .replace(/\s+/g, ' ')
    .trim();

  let match = cleaned.match(
    /^(?:p(?:ágina)?\.?\s*)?[-–—]?\s*(\d{1,4})\s*[-–—]?$/i
  );
  if (!match) {
    match = cleaned.match(/^(\d{1,4})\s*(?:\/|de)\s*\d{1,4}$/i);
  }
  if (match) return match[1];

  if (/^[ivxlcdm]{1,10}$/i.test(cleaned)) {
    return cleaned.toLowerCase();
  }
  return null;
}

function normalizeSearchText(value) {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function titleSearchKey(title) {
  const words = normalizeSearchText(title)
    .split(' ')
    .filter(word => word.length >= 3)
    .slice(0, 4);
  return words.join(' ');
}

async function resolveOutlineItem(item, depth, output) {
  if (output.length >= 2000) return;

  let page = null;
  try {
    let dest = item.dest;
    if (typeof dest === 'string') {
      dest = await pdf.getDestination(dest);
    }
    if (Array.isArray(dest) && dest.length > 0) {
      page = (await pdf.getPageIndex(dest[0])) + 1;
    }
  } catch (_) {}

  output.push({
    title: String(item.title || 'Sem título'),
    page,
    pageLabel:
      page && pdfPageLabels && page <= pdfPageLabels.length
        ? String(pdfPageLabels[page - 1])
        : (page ? String(page) : null),
    depth,
    source: 'outline'
  });

  for (const child of (item.items || [])) {
    if (output.length >= 2000) break;
    await resolveOutlineItem(child, depth + 1, output);
  }
}

function textLinesFromContent(content) {
  const rows = [];
  for (const item of (content.items || [])) {
    const text = String(item.str || '').trim();
    if (!text || !Array.isArray(item.transform)) continue;
    const x = Number(item.transform[4] || 0);
    const y = Number(item.transform[5] || 0);

    let row = rows.find(candidate => Math.abs(candidate.y - y) <= 2.5);
    if (!row) {
      row = { y, items: [] };
      rows.push(row);
    }
    row.items.push({ x, text });
  }

  return rows
    .sort((a, b) => b.y - a.y)
    .map(row => {
      row.items.sort((a, b) => a.x - b.x);
      return {
        x: row.items.length ? row.items[0].x : 0,
        y: row.y,
        text: row.items
          .map(item => item.text)
          .join(' ')
          .replace(/\s+/g, ' ')
          .trim()
      };
    })
    .filter(row => row.text.length > 0);
}

async function detectPrintedPageLabel(physical) {
  try {
    const page = await pdf.getPage(physical);
    const viewport = page.getViewport({ scale: 1.0 });
    const content = await page.getTextContent();
    const candidates = [];

    for (const row of textLinesFromContent(content)) {
      candidates.push({ text: row.text, y: row.y });
    }
    for (const item of (content.items || [])) {
      if (!Array.isArray(item.transform)) continue;
      const text = String(item.str || '').trim();
      if (!text) continue;
      candidates.push({
        text,
        y: Number(item.transform[5] || 0)
      });
    }

    let best = null;
    let bestScore = Number.POSITIVE_INFINITY;
    for (const candidate of candidates) {
      const nearEdge =
        candidate.y <= viewport.height * 0.18 ||
        candidate.y >= viewport.height * 0.82;
      if (!nearEdge) continue;

      const label = parsePrintedPageLabel(candidate.text);
      if (!label) continue;

      const numeric = Number.parseInt(label, 10);
      if (
        Number.isInteger(numeric) &&
        (numeric < 1 || numeric > Math.max(pdf.numPages, 2000))
      ) {
        continue;
      }

      const edgeDistance = Math.min(
        Math.abs(candidate.y),
        Math.abs(viewport.height - candidate.y)
      );
      let score = edgeDistance;
      if (Number.isInteger(numeric)) {
        const offset = physical - numeric;
        if (Math.abs(offset) <= 250) score -= 40;
      }

      if (score < bestScore) {
        bestScore = score;
        best = label;
      }
    }
    return best;
  } catch (_) {
    return null;
  }
}

function bestOffsetFromVotes(votes) {
  let bestOffset = null;
  let bestVotes = 0;
  for (const [offset, count] of votes.entries()) {
    if (count > bestVotes) {
      bestVotes = count;
      bestOffset = offset;
    }
  }
  return { offset: bestOffset, votes: bestVotes };
}

function buildNumericPaginationSegments(anchors) {
  const byOffset = new Map();
  for (const anchor of anchors) {
    const offset = anchor.physical - anchor.printed;
    if (Math.abs(offset) > 600) continue;
    if (!byOffset.has(offset)) byOffset.set(offset, []);
    byOffset.get(offset).push(anchor);
  }

  const segments = [];
  for (const [offset, raw] of byOffset.entries()) {
    const points = raw
      .slice()
      .sort((a, b) => a.physical - b.physical);

    let group = [];
    const flush = () => {
      if (group.length < 2) {
        group = [];
        return;
      }
      const first = group[0];
      const last = group[group.length - 1];
      segments.push({
        offset,
        physicalStart: first.physical,
        physicalEnd: last.physical,
        printedStart: first.printed,
        printedEnd: last.printed,
        confidence: group.length
      });
      group = [];
    };

    for (const point of points) {
      if (!group.length) {
        group.push(point);
        continue;
      }

      const previous = group[group.length - 1];
      const physicalDelta = point.physical - previous.physical;
      const printedDelta = point.printed - previous.printed;
      const coherent =
        physicalDelta > 0 &&
        physicalDelta <= 48 &&
        printedDelta === physicalDelta;

      if (!coherent) flush();
      group.push(point);
    }
    flush();
  }

  return segments
    .filter(segment => segment.confidence >= 2)
    .sort((a, b) =>
      a.physicalStart - b.physicalStart ||
      b.confidence - a.confidence
    );
}

async function buildPrintedPaginationModel(startPage) {
  if (pdfPageLabels) {
    printedPaginationReady = true;
    return;
  }

  printedToPhysical.clear();
  physicalToPrinted.clear();
  inferredPrintedOffset = null;
  numericPaginationSegments = [];

  const first = Math.max(1, startPage);
  const anchors = [];
  const pagesToInspect = new Set();

  // Read a dense window immediately after the TOC and then sample the whole
  // document. This handles covers, roman front matter, page-number restarts
  // and long books without assuming one global offset.
  const denseEnd = Math.min(pdf.numPages, first + 48);
  for (let physical = first; physical <= denseEnd; physical++) {
    pagesToInspect.add(physical);
  }

  const stride = pdf.numPages > 1800 ? 12 : pdf.numPages > 900 ? 8 : 5;
  for (let physical = first; physical <= pdf.numPages; physical += stride) {
    pagesToInspect.add(physical);
  }
  pagesToInspect.add(pdf.numPages);

  for (const physical of Array.from(pagesToInspect).sort((a, b) => a - b)) {
    const label = await detectPrintedPageLabel(physical);
    if (!label) continue;

    const normalized = normalizedLabel(label);
    if (!normalized) continue;

    if (!printedToPhysical.has(normalized)) {
      printedToPhysical.set(normalized, physical);
    }
    physicalToPrinted.set(physical, label);

    const numeric = Number.parseInt(normalized, 10);
    if (Number.isInteger(numeric) && numeric >= 1) {
      anchors.push({ physical, printed: numeric });
    }
  }

  numericPaginationSegments = buildNumericPaginationSegments(anchors);

  // Global offset remains only as a conservative fallback when the document
  // truly behaves like one continuous numbering sequence.
  const votes = new Map();
  for (const anchor of anchors) {
    const offset = anchor.physical - anchor.printed;
    if (Math.abs(offset) > 600) continue;
    votes.set(offset, (votes.get(offset) || 0) + 1);
  }
  const best = bestOffsetFromVotes(votes);
  const totalNumeric = anchors.length;
  if (
    best.votes >= 4 &&
    totalNumeric > 0 &&
    best.votes / totalNumeric >= 0.7
  ) {
    inferredPrintedOffset = best.offset;
  }

  printedPaginationReady =
    printedToPhysical.size > 0 ||
    numericPaginationSegments.length > 0 ||
    Number.isInteger(inferredPrintedOffset);

  publishDerivedPageLabels();
}

async function findTitleNearPhysicalPage(candidate, predictedPage) {
  if (!Number.isInteger(predictedPage)) return null;
  const key = titleSearchKey(candidate.title);
  if (key.length < 5) return null;

  const first = Math.max(1, predictedPage - 6);
  const last = Math.min(pdf.numPages, predictedPage + 6);
  for (let physical = first; physical <= last; physical++) {
    try {
      const page = await pdf.getPage(physical);
      const content = await page.getTextContent();
      const pageText = normalizeSearchText(
        (content.items || [])
          .map(item => String(item.str || ''))
          .join(' ')
      );
      if (pageText.includes(key)) return physical;
    } catch (_) {}
  }
  return null;
}

async function resolveTocCandidatePage(candidate) {
  const predicted = physicalPageForPrintedLabel(candidate.printedLabel);
  const validated = await findTitleNearPhysicalPage(candidate, predicted);
  return validated || predicted;
}

async function inferOffsetFromTocTitles(candidates, contentStartPage) {
  if (pdfPageLabels || Number.isInteger(inferredPrintedOffset)) return;

  const votes = new Map();
  const anchors = candidates
    .filter(candidate => /^\d{1,4}$/.test(candidate.printedLabel))
    .filter(candidate => titleSearchKey(candidate.title).length >= 5)
    .slice(0, 4);

  for (const candidate of anchors) {
    const printed = Number.parseInt(candidate.printedLabel, 10);
    if (!Number.isInteger(printed)) continue;

    const key = titleSearchKey(candidate.title);
    const first = Math.max(contentStartPage, printed);
    const last = Math.min(pdf.numPages, printed + 180);

    for (let physical = first; physical <= last; physical++) {
      try {
        const page = await pdf.getPage(physical);
        const content = await page.getTextContent();
        const pageText = normalizeSearchText(
          (content.items || [])
            .map(item => String(item.str || ''))
            .join(' ')
        );
        if (!pageText.includes(key)) continue;

        const offset = physical - printed;
        votes.set(offset, (votes.get(offset) || 0) + 1);
        printedToPhysical.set(normalizedLabel(candidate.printedLabel), physical);
        physicalToPrinted.set(physical, candidate.printedLabel);
        break;
      } catch (_) {}
    }
  }

  const best = bestOffsetFromVotes(votes);
  if (best.votes >= 2 && Number.isInteger(best.offset)) {
    inferredPrintedOffset = best.offset;
  }
  printedPaginationReady =
    printedPaginationReady ||
    printedToPhysical.size > 0 ||
    Number.isInteger(inferredPrintedOffset);
  publishDerivedPageLabels();
}

async function buildVisualIndex() {
  const searchLimit = Math.min(pdf.numPages, 80);
  let tocStart = null;
  let tocRows = [];

  for (let physical = 1; physical <= searchLimit; physical++) {
    try {
      const page = await pdf.getPage(physical);
      const content = await page.getTextContent();
      const rows = textLinesFromContent(content);
      const wholeText = rows.map(row => row.text).join(' ');
      if (/\b(sum[aá]rio|índice|conte[uú]do)\b/i.test(wholeText)) {
        tocStart = physical;
        tocRows = rows;
        break;
      }
    } catch (_) {}
  }

  if (tocStart === null) return [];

  const allRows = [...tocRows];
  const tocEnd = Math.min(pdf.numPages, tocStart + 14);
  for (let physical = tocStart + 1; physical <= tocEnd; physical++) {
    try {
      const page = await pdf.getPage(physical);
      const content = await page.getTextContent();
      allRows.push(...textLinesFromContent(content));
    } catch (_) {}
  }

  const candidates = [];
  for (const row of allRows) {
    const line = row.text
      .replace(/[·•]/g, '.')
      .replace(/\.{4,}/g, ' ... ')
      .replace(/\s+/g, ' ')
      .trim();

    if (/^(sum[aá]rio|índice|conte[uú]do)$/i.test(line)) continue;

    const match =
      line.match(/^(.{3,}?)\s+(?:\.\.\.\s*)?([ivxlcdm]+|\d{1,4})$/i);
    if (!match) continue;

    const title = match[1]
      .replace(/\s*\.\.\.\s*$/, '')
      .trim();
    const printedLabel = match[2].trim();
    if (title.length < 3) continue;

    candidates.push({
      title,
      printedLabel,
      x: row.x
    });
  }

  if (candidates.length < 2) return [];

  if (!pdfPageLabels) {
    await buildPrintedPaginationModel(tocEnd + 1);
    if (!Number.isInteger(inferredPrintedOffset)) {
      await inferOffsetFromTocTitles(candidates, tocEnd + 1);
    }
  }

  const minX = Math.min(...candidates.map(item => item.x));
  const output = [];
  const seen = new Set();

  for (const candidate of candidates) {
    const key = candidate.title.toLowerCase() + '|' + candidate.printedLabel;
    if (seen.has(key)) continue;
    seen.add(key);

    const resolvedPage = await resolveTocCandidatePage(candidate);
    if (!resolvedPage) continue;

    output.push({
      title: candidate.title,
      page: resolvedPage,
      pageLabel: candidate.printedLabel,
      depth: Math.max(
        0,
        Math.min(6, Math.round((candidate.x - minX) / 18))
      ),
      source: 'toc'
    });
    if (output.length >= 500) break;
  }
  return output;
}

async function buildOutlineIndex() {
  try {
    if (!pdfPageLabels && !printedPaginationReady) {
      await buildPrintedPaginationModel(1);
    }

    const raw = await pdf.getOutline();
    if (!Array.isArray(raw) || raw.length === 0) return [];

    const output = [];
    for (const item of raw) {
      if (output.length >= 2000) break;
      await resolveOutlineItem(item, 0, output);
    }
    return output;
  } catch (_) {
    return [];
  }
}

async function loadNavigationMetadata() {
  await loadPageLabels();

  // Use the outline/bookmarks embedded in the PDF itself. Destinations are
  // resolved directly by PDF.js to physical PDF pages, matching the behavior
  // that was stable before printed-TOC inference was introduced.
  try {
    const raw = await pdf.getOutline();
    const output = [];
    for (const item of (raw || [])) {
      if (output.length >= 2000) break;
      await resolveOutlineItem(item, 0, output);
    }
    LexPdfBridge.outline(JSON.stringify(output));
  } catch (_) {
    LexPdfBridge.outline('[]');
  }
}

function isSearchWordChar(value) {
  return /[A-Za-zÀ-ÖØ-öø-ÿ0-9_]/.test(String(value || ''));
}

function buildSearchPageText(content) {
  let text = '';
  const spans = [];
  const items = content.items || [];
  for (let itemIndex = 0; itemIndex < items.length; itemIndex++) {
    const item = items[itemIndex];
    const value = String(item.str || '');
    if (!value) continue;
    if (text.length > 0) text += ' ';
    const start = text.length;
    text += value;
    spans.push({ start, end: text.length, itemIndex });
  }
  return { text, spans, items };
}

function findSearchRanges(text, query, caseSensitive, wholeWord) {
  const ranges = [];
  if (!query) return ranges;
  const source = caseSensitive ? text : text.toLocaleLowerCase();
  const needle = caseSensitive ? query : query.toLocaleLowerCase();
  let offset = 0;
  while (offset <= source.length - needle.length) {
    const index = source.indexOf(needle, offset);
    if (index < 0) break;
    const end = index + needle.length;
    const leftOk =
      !wholeWord || index === 0 || !isSearchWordChar(source.charAt(index - 1));
    const rightOk =
      !wholeWord || end >= source.length || !isSearchWordChar(source.charAt(end));
    if (leftOk && rightOk) ranges.push({ start: index, end });
    offset = Math.max(index + 1, end);
  }
  return ranges;
}

function reportSearchState(searching) {
  LexPdfBridge.searchState(JSON.stringify({
    current: searchCurrentIndex >= 0 ? searchCurrentIndex + 1 : 0,
    total: searchMatches.length,
    searching: Boolean(searching)
  }));
}

async function searchPageMatches(physical, query, caseSensitive, wholeWord) {
  const page = await pdf.getPage(physical);
  try {
    const content = await page.getTextContent();
    const built = buildSearchPageText(content);
    return findSearchRanges(
      built.text,
      query,
      caseSensitive,
      wholeWord
    ).map(range => ({
      page: physical,
      start: range.start,
      end: range.end
    }));
  } finally {
    page.cleanup();
  }
}

async function startDocumentSearch(query, caseSensitive, wholeWord) {
  const token = ++searchGeneration;
  searchMatches = [];
  searchCurrentIndex = -1;
  searchQuery = String(query || '').trim();
  searchCaseSensitive = Boolean(caseSensitive);
  searchWholeWord = Boolean(wholeWord);
  searchInProgress = searchQuery.length > 0;
  reportSearchState(searchInProgress);

  if (!pdf || !searchQuery) {
    searchInProgress = false;
    reportSearchState(false);
    if (pdf) renderPage(pageNumber, true);
    return;
  }

  const order = [];
  for (let page = pageNumber; page <= pdf.numPages; page++) order.push(page);
  for (let page = 1; page < pageNumber; page++) order.push(page);

  for (let orderIndex = 0; orderIndex < order.length; orderIndex++) {
    if (token !== searchGeneration) return;
    const physical = order[orderIndex];
    try {
      const found = await searchPageMatches(
        physical,
        searchQuery,
        searchCaseSensitive,
        searchWholeWord
      );
      if (token !== searchGeneration) return;
      if (found.length) {
        searchMatches.push(...found);
        if (searchCurrentIndex < 0) {
          searchCurrentIndex = 0;
          renderPage(searchMatches[0].page, true);
        }
        reportSearchState(true);
      } else if (orderIndex % 12 === 0) {
        reportSearchState(true);
      }
    } catch (_) {
      // A malformed text layer on one page must not cancel the whole search.
    }
  }

  if (token !== searchGeneration) return;
  searchInProgress = false;
  reportSearchState(false);
}

async function goToSearchMatch(index) {
  if (!searchMatches.length) return;
  const total = searchMatches.length;
  searchCurrentIndex = ((index % total) + total) % total;
  const match = searchMatches[searchCurrentIndex];
  await renderPage(match.page, true);
  reportSearchState(searchInProgress);
}

async function paintSearchHighlights(page, viewport, renderScale, target) {
  if (!searchMatches.length || !searchQuery) return;
  const pageMatches = [];
  for (let index = 0; index < searchMatches.length; index++) {
    const match = searchMatches[index];
    if (match.page === target) pageMatches.push({ match, index });
  }
  if (!pageMatches.length) return;

  try {
    const content = await page.getTextContent();
    const built = buildSearchPageText(content);
    for (const entry of pageMatches) {
      const active = entry.index === searchCurrentIndex;
      ctx.save();
      ctx.fillStyle = active
        ? 'rgba(255, 152, 0, 0.58)'
        : 'rgba(255, 235, 59, 0.38)';
      for (const span of built.spans) {
        if (span.end <= entry.match.start || span.start >= entry.match.end) continue;
        const item = built.items[span.itemIndex];
        if (!item || !Array.isArray(item.transform)) continue;
        const tx = pdfjsLib.Util.transform(viewport.transform, item.transform);
        const fontHeight = Math.max(4, Math.hypot(tx[2], tx[3]));
        const width = Math.max(3, Number(item.width || 0) * viewport.scale);
        ctx.fillRect(
          tx[4] * renderScale,
          (tx[5] - fontHeight) * renderScale,
          width * renderScale,
          fontHeight * renderScale
        );
      }
      ctx.restore();
    }
  } catch (_) {}
}

async function renderSelectableTextLayer(page, viewport) {
  textLayer.replaceChildren();
  textLayer.style.width = viewport.width + 'px';
  textLayer.style.height = viewport.height + 'px';
  pageHost.style.width = viewport.width + 'px';
  pageHost.style.height = viewport.height + 'px';

  try {
    const content = await page.getTextContent();
    for (const item of (content.items || [])) {
      const text = String(item.str || '');
      if (!text || !Array.isArray(item.transform)) continue;

      const tx = pdfjsLib.Util.transform(viewport.transform, item.transform);
      const fontHeight = Math.max(1, Math.hypot(tx[2], tx[3]));
      const span = document.createElement('span');
      span.textContent = text;
      span.style.left = tx[4] + 'px';
      span.style.top = (tx[5] - fontHeight) + 'px';
      span.style.fontSize = fontHeight + 'px';
      span.style.fontFamily = 'sans-serif';

      const expectedWidth = Math.max(0, Number(item.width || 0) * viewport.scale);
      if (expectedWidth > 0) {
        span.dataset.expectedWidth = String(expectedWidth);
      }
      textLayer.appendChild(span);
    }

    requestAnimationFrame(() => {
      for (const span of textLayer.querySelectorAll('span[data-expected-width]')) {
        const measured = span.getBoundingClientRect().width;
        const expected = Number(span.dataset.expectedWidth || 0);
        if (measured > 0 && expected > 0) {
          span.style.transform = 'scaleX(' + (expected / measured) + ')';
        }
      }
    });
  } catch (_) {
    textLayer.replaceChildren();
  }
}

function clearTextLongPressTimer() {
  if (textLongPressTimer) {
    clearTimeout(textLongPressTimer);
    textLongPressTimer = 0;
  }
}

function caretRangeAtPoint(x, y) {
  if (document.caretRangeFromPoint) {
    return document.caretRangeFromPoint(x, y);
  }
  if (document.caretPositionFromPoint) {
    const position = document.caretPositionFromPoint(x, y);
    if (!position) return null;
    const range = document.createRange();
    range.setStart(position.offsetNode, position.offset);
    range.collapse(true);
    return range;
  }
  return null;
}

function wordRangeAtPoint(x, y) {
  const caret = caretRangeAtPoint(x, y);
  if (!caret) return null;

  const node = caret.startContainer;
  if (!node || node.nodeType !== Node.TEXT_NODE) return null;
  const parent = node.parentElement;
  if (!parent || !parent.closest('#textLayer')) return null;

  const text = node.textContent || '';
  if (!text.length) return null;

  let offset = Math.max(0, Math.min(text.length, caret.startOffset));
  if (offset === text.length && offset > 0) offset--;
  if (/\s/.test(text[offset] || '') && offset > 0) offset--;

  let start = offset;
  let end = offset;
  while (start > 0 && !/\s/.test(text[start - 1])) start--;
  while (end < text.length && !/\s/.test(text[end])) end++;

  while (start < end && /[.,;:!?()[\]{}"'«»“”‘’]/.test(text[start])) start++;
  while (end > start && /[.,;:!?()[\]{}"'«»“”‘’]/.test(text[end - 1])) end--;
  if (start >= end) return null;

  const range = document.createRange();
  range.setStart(node, start);
  range.setEnd(node, end);
  return range;
}

function applySelectionRange(range) {
  const selection = window.getSelection();
  if (!selection || !range) return false;
  selection.removeAllRanges();
  selection.addRange(range);
  return true;
}

function selectWordAtPoint(x, y) {
  const range = wordRangeAtPoint(x, y);
  if (!range) return false;
  textSelectionAnchorRange = range.cloneRange();
  return applySelectionRange(range);
}

function pointRangeIsBefore(firstRange, secondRange) {
  const first = firstRange.cloneRange();
  first.collapse(true);
  const second = secondRange.cloneRange();
  second.collapse(true);
  return first.compareBoundaryPoints(Range.START_TO_START, second) < 0;
}

function extendSelectionToPoint(x, y) {
  if (!textSelectionAnchorRange) return false;
  const target = wordRangeAtPoint(x, y);
  if (!target) return false;

  const range = document.createRange();
  if (pointRangeIsBefore(target, textSelectionAnchorRange)) {
    range.setStart(target.startContainer, target.startOffset);
    range.setEnd(
      textSelectionAnchorRange.endContainer,
      textSelectionAnchorRange.endOffset
    );
  } else {
    range.setStart(
      textSelectionAnchorRange.startContainer,
      textSelectionAnchorRange.startOffset
    );
    range.setEnd(target.endContainer, target.endOffset);
  }
  return applySelectionRange(range);
}

textLayer.addEventListener('touchstart', e => {
  if (e.touches.length !== 1) {
    clearTextLongPressTimer();
    textLongPressTriggered = false;
    return;
  }

  const touch = e.touches[0];
  textLongPressStartX = touch.clientX;
  textLongPressStartY = touch.clientY;
  textLongPressTriggered = false;
  clearTextLongPressTimer();

  textLongPressTimer = window.setTimeout(() => {
    textLongPressTimer = 0;
    if (selectWordAtPoint(textLongPressStartX, textLongPressStartY)) {
      textLongPressTriggered = true;
      textSelectionLockScrollTop = stage.scrollTop;
      textSelectionLockScrollLeft = stage.scrollLeft;
      singleTouchActive = false;
    }
  }, 480);
}, { passive: true });

textLayer.addEventListener('touchmove', e => {
  if (e.touches.length !== 1) return;
  const touch = e.touches[0];

  if (textLongPressTriggered) {
    // After long-press selection begins, the finger controls only the selection.
    // Keep the PDF fixed in place instead of letting the stage scroll/page.
    e.preventDefault();
    e.stopPropagation();
    stage.scrollTop = textSelectionLockScrollTop;
    stage.scrollLeft = textSelectionLockScrollLeft;
    singleTouchActive = false;
    extendSelectionToPoint(touch.clientX, touch.clientY);
    return;
  }

  if (!textLongPressTimer) return;
  const dx = touch.clientX - textLongPressStartX;
  const dy = touch.clientY - textLongPressStartY;
  if (Math.hypot(dx, dy) > 12) {
    clearTextLongPressTimer();
  }
}, { passive: false });

textLayer.addEventListener('touchend', e => {
  clearTextLongPressTimer();
  if (textLongPressTriggered) {
    e.preventDefault();
    e.stopPropagation();
    stage.scrollTop = textSelectionLockScrollTop;
    stage.scrollLeft = textSelectionLockScrollLeft;
    singleTouchActive = false;
    textLongPressTriggered = false;
  }
}, { passive: false });

textLayer.addEventListener('touchcancel', e => {
  clearTextLongPressTimer();
  if (textLongPressTriggered) {
    e.preventDefault();
    e.stopPropagation();
    stage.scrollTop = textSelectionLockScrollTop;
    stage.scrollLeft = textSelectionLockScrollLeft;
  }
  textLongPressTriggered = false;
}, { passive: false });

function captureSelectionForMarkup() {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
    capturedSelectionRects = [];
    return false;
  }
  const hostRect = pageHost.getBoundingClientRect();
  const rects = [];
  for (let rangeIndex = 0; rangeIndex < selection.rangeCount; rangeIndex++) {
    const range = selection.getRangeAt(rangeIndex);
    for (const rect of range.getClientRects()) {
      if (rect.width <= 0 || rect.height <= 0) continue;
      rects.push({
        x: (rect.left - hostRect.left) / scale,
        y: (rect.top - hostRect.top) / scale,
        width: rect.width / scale,
        height: rect.height / scale
      });
    }
  }
  capturedSelectionRects = rects;
  return rects.length > 0;
}

function commitCapturedMarkup(kind, colorArgb) {
  if (!capturedSelectionRects.length) return false;
  LexPdfBridge.addTextMarkup(
    String(kind),
    Number(colorArgb),
    JSON.stringify(capturedSelectionRects)
  );
  return true;
}

function argbToCss(color) {
  const value = Number(color) >>> 0;
  const a = ((value >>> 24) & 255) / 255;
  const r = (value >>> 16) & 255;
  const g = (value >>> 8) & 255;
  const b = value & 255;
  return 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')';
}

function renderTextMarkups() {
  markupLayer.replaceChildren();
  markupLayer.style.width = (pageAtScaleOne.width * scale) + 'px';
  markupLayer.style.height = (pageAtScaleOne.height * scale) + 'px';

  for (const markup of currentTextMarkups) {
    const color = argbToCss(markup.colorArgb);
    for (const rect of (markup.rects || [])) {
      const node = document.createElement('div');
      node.className = 'markup ' + markup.kind;
      node.style.left = (Number(rect.x) * scale) + 'px';
      node.style.top = (Number(rect.y) * scale) + 'px';
      node.style.width = (Number(rect.width) * scale) + 'px';
      node.style.height = (Number(rect.height) * scale) + 'px';
      if (markup.kind === 'highlight') {
        node.style.background = color;
      } else {
        node.style.color = color;
      }
      markupLayer.appendChild(node);
    }
  }
}

function removeCapturedMarkups() {
  if (!capturedSelectionRects.length) return false;
  LexPdfBridge.removeTextMarkupRects(JSON.stringify(capturedSelectionRects));
  return true;
}

function clearTextSelection() {
  const selection = window.getSelection();
  if (selection) selection.removeAllRanges();
  capturedSelectionRects = [];
}

function reportMetrics() {
  const r = canvas.getBoundingClientRect();
  const density = window.devicePixelRatio || 1;
  LexPdfBridge.metrics(JSON.stringify({
    page: pageNumber,
    pageWidth: pageAtScaleOne.width,
    pageHeight: pageAtScaleOne.height,
    left: r.left * density,
    top: r.top * density,
    width: r.width * density,
    height: r.height * density,
    density
  }));
}

function scheduleMetricsSync() {
  if (metricsFrame) return;
  metricsFrame = requestAnimationFrame(() => {
    metricsFrame = 0;
    reportMetrics();
  });
}

function settleMetrics() {
  scheduleMetricsSync();
  setTimeout(scheduleMetricsSync, 32);
  setTimeout(scheduleMetricsSync, 96);
  setTimeout(scheduleMetricsSync, 220);
}

async function renderPage(target, preserveCenter = false) {
  if (!pdf) return;
  target = Math.max(1, Math.min(pdf.numPages, target));
  const token = ++renderToken;
  loading.style.display = 'block';

  if (renderTask) {
    try { renderTask.cancel(); } catch (_) {}
    renderTask = null;
  }

  try {
    const page = await pdf.getPage(target);
    if (token !== renderToken) return;

    const base = page.getViewport({ scale: 1.0 });
    pageAtScaleOne = { width: base.width, height: base.height };
    const viewport = page.getViewport({ scale });

    const outputScale = Math.min(window.devicePixelRatio || 1, 2);
    const maxPixels = 8000000;
    let pixelWidth = Math.max(1, Math.floor(viewport.width * outputScale));
    let pixelHeight = Math.max(1, Math.floor(viewport.height * outputScale));
    const pixels = pixelWidth * pixelHeight;
    let renderScale = outputScale;
    if (pixels > maxPixels) {
      renderScale *= Math.sqrt(maxPixels / pixels);
      pixelWidth = Math.max(1, Math.floor(viewport.width * renderScale));
      pixelHeight = Math.max(1, Math.floor(viewport.height * renderScale));
    }

    canvas.width = pixelWidth;
    canvas.height = pixelHeight;
    canvas.style.width = viewport.width + 'px';
    canvas.style.height = viewport.height + 'px';

    renderTask = page.render({
      canvasContext: ctx,
      viewport,
      transform: renderScale === 1
        ? null
        : [renderScale, 0, 0, renderScale, 0, 0],
      background: '#ffffff'
    });
    await renderTask.promise;
    renderTask = null;

    if (token !== renderToken) return;
    await renderSelectableTextLayer(page, viewport);
    if (token !== renderToken) return;
    renderTextMarkups();
    await paintSearchHighlights(page, viewport, renderScale, target);
    if (token !== renderToken) return;
    const pageChanged = pageNumber !== target;
    pageNumber = target;
    page.cleanup();
    if (pageChanged && !preserveCenter) {
      stage.scrollTop = 0;
      stage.scrollLeft = 0;
    }
    loading.style.display = 'none';
    requestAnimationFrame(() => {
      settleMetrics();
      LexPdfBridge.pageChanged(pageNumber);
      LexPdfBridge.rendered(pageNumber);
    });
  } catch (e) {
    if (e?.name === 'RenderingCancelledException') return;
    loading.style.display = 'none';
    LexPdfBridge.error(String(e?.stack || e));
  }
}

window.LexPDF = {
  receiveRange(begin, base64) {
    if (!rangeTransport || rangeFailed) return;
    rangeTransport.onDataRange(Number(begin), decodeBase64(base64));
  },
  rangeFailure(message) {
    rangeFailed = true;
    loading.style.display = 'none';
    LexPdfBridge.error(String(message));
  },
  goToPage(page) { renderPage(Number(page)); },
  nextPage() { renderPage(pageNumber + 1); },
  previousPage() { renderPage(pageNumber - 1); },
  startSearch(query, caseSensitive, wholeWord) {
    startDocumentSearch(query, caseSensitive, wholeWord);
  },
  nextSearchMatch() {
    goToSearchMatch(searchCurrentIndex + 1);
  },
  previousSearchMatch() {
    goToSearchMatch(searchCurrentIndex - 1);
  },
  captureSelectionForMarkup,
  commitCapturedMarkup,
  removeCapturedMarkups,
  clearTextSelection,
  setTextMarkups(markups) {
    currentTextMarkups = Array.isArray(markups) ? markups : [];
    renderTextMarkups();
  },
  clearSearch() {
    searchGeneration++;
    searchMatches = [];
    searchCurrentIndex = -1;
    searchQuery = '';
    searchInProgress = false;
    reportSearchState(false);
    renderPage(pageNumber, true);
  },
  zoomIn() {
    scale = Math.min(4.0, scale * 1.2);
    renderPage(pageNumber, true);
  },
  zoomOut() {
    scale = Math.max(0.65, scale / 1.2);
    renderPage(pageNumber, true);
  },
  fitPage() {
    const widthScale =
      Math.max(0.4, (stage.clientWidth - 36) / Math.max(1, pageAtScaleOne.width));
    const heightScale =
      Math.max(0.4, (stage.clientHeight - 36) / Math.max(1, pageAtScaleOne.height));
    scale = Math.max(0.4, Math.min(4.0, widthScale, heightScale));
    renderPage(pageNumber, false);
  },
  setViewMode(mode) {
    const allowed = ['page', 'continuous_vertical', 'continuous_horizontal'];
    readerViewMode = allowed.includes(mode) ? mode : 'page';
    stage.dataset.viewMode = readerViewMode;
  }
};

stage.addEventListener('scroll', () => {
  scheduleMetricsSync();
}, { passive: true });

stage.addEventListener('click', e => {
  const selection = window.getSelection();
  if (selection && !selection.isCollapsed) return;
  const target = e.target;
  if (
    target === stage ||
    target === document.getElementById('wrap') ||
    target === pageHost ||
    target === canvas
  ) {
    LexPdfBridge.readerChromeTap();
  }
});

window.addEventListener('resize', settleMetrics);

stage.addEventListener('touchstart', e => {
  if (e.touches.length === 1) {
    singleTouchActive = true;
    singleTouchStartX = e.touches[0].clientX;
    singleTouchStartY = e.touches[0].clientY;
    singleTouchStartScrollTop = stage.scrollTop;
    singleTouchStartedAtTop = stage.scrollTop <= 3;
    singleTouchStartedAtBottom =
      stage.scrollTop + stage.clientHeight >= stage.scrollHeight - 3;
    singleTouchStartedAtLeft = stage.scrollLeft <= 3;
    singleTouchStartedAtRight =
      stage.scrollLeft + stage.clientWidth >= stage.scrollWidth - 3;
  } else {
    singleTouchActive = false;
  }

  if (e.touches.length === 2) {
    clearTextLongPressTimer();
    textLongPressTriggered = false;
    textSelectionAnchorRange = null;

    pinchStartDistance = hypot(e.touches[0], e.touches[1]);
    pinchStartScale = scale;
    pinchPreviewScale = scale;

    const midpointX = (e.touches[0].clientX + e.touches[1].clientX) / 2;
    const midpointY = (e.touches[0].clientY + e.touches[1].clientY) / 2;
    const hostRect = pageHost.getBoundingClientRect();
    const stageRect = stage.getBoundingClientRect();

    // Store the exact PDF point below the midpoint in unscaled page units.
    pinchAnchorPageX = (midpointX - hostRect.left) / Math.max(0.0001, scale);
    pinchAnchorPageY = (midpointY - hostRect.top) / Math.max(0.0001, scale);
    pinchAnchorViewportX = midpointX - stageRect.left;
    pinchAnchorViewportY = midpointY - stageRect.top;
    pinchLastMidpointX = pinchAnchorViewportX;
    pinchLastMidpointY = pinchAnchorViewportY;
  }
  scheduleMetricsSync();
}, { passive: true });

function clampStageScroll(left, top) {
  const maxLeft = Math.max(0, stage.scrollWidth - stage.clientWidth);
  const maxTop = Math.max(0, stage.scrollHeight - stage.clientHeight);
  stage.scrollLeft = Math.max(0, Math.min(maxLeft, left));
  stage.scrollTop = Math.max(0, Math.min(maxTop, top));
}

function keepPinchAnchorAtViewport(scaleValue, viewportX, viewportY) {
  const hostRect = pageHost.getBoundingClientRect();
  const stageRect = stage.getBoundingClientRect();
  const hostContentLeft =
    hostRect.left - stageRect.left + stage.scrollLeft;
  const hostContentTop =
    hostRect.top - stageRect.top + stage.scrollTop;

  const targetLeft =
    hostContentLeft + pinchAnchorPageX * scaleValue - viewportX;
  const targetTop =
    hostContentTop + pinchAnchorPageY * scaleValue - viewportY;

  clampStageScroll(targetLeft, targetTop);
}

stage.addEventListener('touchmove', e => {
  scheduleMetricsSync();

  if (e.touches.length === 2 && pinchStartDistance > 0) {
    e.preventDefault();

    const d = hypot(e.touches[0], e.touches[1]);
    const next = Math.max(
      0.65,
      Math.min(4.0, pinchStartScale * d / pinchStartDistance)
    );
    pinchPreviewScale = next;

    const midpointX = (e.touches[0].clientX + e.touches[1].clientX) / 2;
    const midpointY = (e.touches[0].clientY + e.touches[1].clientY) / 2;
    const stageRect = stage.getBoundingClientRect();
    pinchLastMidpointX = midpointX - stageRect.left;
    pinchLastMidpointY = midpointY - stageRect.top;

    // Increase the actual scrollable layout size while previewing the zoom.
    // This avoids an unreachable left/right edge on portrait screens.
    pageHost.style.width = (pageAtScaleOne.width * next) + 'px';
    pageHost.style.height = (pageAtScaleOne.height * next) + 'px';

    const ratio = next / pinchStartScale;
    canvas.style.transformOrigin = '0 0';
    markupLayer.style.transformOrigin = '0 0';
    textLayer.style.transformOrigin = '0 0';
    canvas.style.transform = 'scale(' + ratio + ')';
    markupLayer.style.transform = 'scale(' + ratio + ')';
    textLayer.style.transform = 'scale(' + ratio + ')';

    keepPinchAnchorAtViewport(
      next,
      pinchLastMidpointX,
      pinchLastMidpointY
    );
  }
}, { passive: false });

stage.addEventListener('touchend', async e => {
  if (pinchStartDistance > 0 && e.touches.length < 2) {
    const finalScale = pinchPreviewScale;

    canvas.style.transform = '';
    canvas.style.transformOrigin = '';
    markupLayer.style.transform = '';
    markupLayer.style.transformOrigin = '';
    textLayer.style.transform = '';
    textLayer.style.transformOrigin = '';

    pinchStartDistance = 0;
    singleTouchActive = false;
    scale = finalScale;

    await renderPage(pageNumber, true);

    // PDF.js-style center preservation: after scale changes, scroll the
    // container so the same PDF point remains under the gesture center.
    requestAnimationFrame(() => {
      keepPinchAnchorAtViewport(
        scale,
        pinchLastMidpointX,
        pinchLastMidpointY
      );
      settleMetrics();
    });
    return;
  }

  if (singleTouchActive && e.changedTouches.length > 0) {
    const touch = e.changedTouches[0];
    const dx = touch.clientX - singleTouchStartX;
    const dy = touch.clientY - singleTouchStartY;
    const verticalGesture =
      Math.abs(dy) > 72 && Math.abs(dy) > Math.abs(dx) * 1.15;
    const horizontalGesture =
      Math.abs(dx) > 72 && Math.abs(dx) > Math.abs(dy) * 1.15;

    const atTop = stage.scrollTop <= 3;
    const atBottom =
      stage.scrollTop + stage.clientHeight >= stage.scrollHeight - 3;
    const atLeft = stage.scrollLeft <= 3;
    const atRight =
      stage.scrollLeft + stage.clientWidth >= stage.scrollWidth - 3;

    if (readerViewMode === 'continuous_vertical' && verticalGesture) {
      // Continuous vertical mode permits the page turn as soon as the same
      // gesture reaches the document edge, removing the extra boundary swipe.
      if (dy < 0 && atBottom) {
        renderPage(pageNumber + 1);
      } else if (dy > 0 && atTop) {
        renderPage(pageNumber - 1);
      }
    } else if (readerViewMode === 'continuous_horizontal' && horizontalGesture) {
      // Preserve free horizontal pan at zoom: only turn when the gesture reaches
      // the corresponding horizontal boundary.
      if (dx < 0 && atRight) {
        renderPage(pageNumber + 1);
      } else if (dx > 0 && atLeft) {
        renderPage(pageNumber - 1);
      }
    } else if (readerViewMode === 'page' && verticalGesture) {
      // Original fallback: page mode still requires a NEW deliberate swipe
      // that starts and ends at the corresponding vertical boundary.
      if (dy < 0 && singleTouchStartedAtBottom && atBottom) {
        renderPage(pageNumber + 1);
      } else if (dy > 0 && singleTouchStartedAtTop && atTop) {
        renderPage(pageNumber - 1);
      }
    }
  }

  singleTouchActive = false;
  settleMetrics();
}, { passive: true });

function hypot(a,b) {
  return Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
}

(async () => {
  try {
    rangeTransport = new NativePdfRangeTransport(PDF_LENGTH);
    const task = pdfjsLib.getDocument({
      range: rangeTransport,
      rangeChunkSize: RANGE_CHUNK_SIZE,
      disableStream: true,
      disableAutoFetch: true,
      disableRange: false,
      standardFontDataUrl:
        'https://cdn.jsdelivr.net/npm/pdfjs-dist@${PDFJS_VERSION}/standard_fonts/',
      wasmUrl:
        'https://cdn.jsdelivr.net/npm/pdfjs-dist@${PDFJS_VERSION}/wasm/'
    });
    pdf = await task.promise;
    LexPdfBridge.ready(pdf.numPages);
    await renderPage(pageNumber);
    void loadNavigationMetadata();
  } catch (e) {
    loading.style.display = 'none';
    LexPdfBridge.error(String(e?.stack || e));
  }
})();
</script>
</body>
</html>
        """.trimIndent()
    }

    private fun js(script: String) {
        webView.evaluateJavascript(script, null)
    }

    private fun logicalPageLabel(pageIndex: Int): String? =
        pageLabels
            .getOrNull(pageIndex)
            ?.trim()
            ?.takeIf { it.isNotBlank() }

    private fun updatePageLabel() {
        val physical = currentPageIndex + 1
        val logical = logicalPageLabel(currentPageIndex)
        val label =
            when {
                pageCount <= 0 -> "$physical / …"
                logical != null && logical != physical.toString() ->
                    "$logical · $physical / $pageCount"
                else -> "$physical / $pageCount"
            }
        pageLabel.text = label
        if (::readingPageIndicator.isInitialized) {
            readingPageIndicator.text = label
        }
    }

    private fun showPageJumpDialog() {
        if (pageCount <= 0) {
            Toast.makeText(this, "Aguarde o PDF terminar de abrir.", Toast.LENGTH_SHORT).show()
            return
        }

        val currentLogical = logicalPageLabel(currentPageIndex)
        val input =
            EditText(this).apply {
                inputType = InputType.TYPE_CLASS_TEXT
                setText(currentLogical ?: (currentPageIndex + 1).toString())
                selectAll()
                setPadding(24.dp, 12.dp, 24.dp, 12.dp)
            }

        AlertDialog.Builder(this)
            .setTitle("Ir para página")
            .setMessage(
                if (pageLabels.isNotEmpty()) {
                    "Digite a numeração impressa do PDF (ex.: 200, xii) " +
                        "ou o número físico da página."
                } else {
                    "Digite uma página entre 1 e $pageCount."
                },
            )
            .setView(input)
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Ir") { _, _ ->
                val requested = input.text?.toString()?.trim().orEmpty()
                val labelIndex =
                    pageLabels.indexOfFirst {
                        it.equals(requested, ignoreCase = true)
                    }
                val numeric = requested.toIntOrNull()
                val target =
                    when {
                        labelIndex >= 0 -> labelIndex + 1
                        numeric != null && numeric in 1..pageCount -> numeric
                        else -> null
                    }

                if (target == null) {
                    Toast.makeText(
                        this,
                        "Página inválida para este PDF.",
                        Toast.LENGTH_LONG,
                    ).show()
                } else {
                    js("LexPDF.goToPage($target)")
                }
            }
            .show()
    }

    private fun showOutlineDialog() {
        if (!outlineLoaded) {
            Toast.makeText(
                this,
                "O índice ainda está sendo carregado.",
                Toast.LENGTH_SHORT,
            ).show()
            return
        }

        if (outlineEntries.isEmpty()) {
            AlertDialog.Builder(this)
                .setTitle("Índice do PDF")
                .setMessage(
                    "Este PDF não possui índice/bookmarks internos. " +
                        "Use “Ir” para navegar diretamente por número de página.",
                )
                .setPositiveButton("OK", null)
                .show()
            return
        }

        val labels =
            outlineEntries
                .map { entry ->
                    val indent = "    ".repeat(entry.depth.coerceAtMost(6))
                    val displayPage =
                        entry.pageLabel
                            ?: entry.page?.let { logicalPageLabel(it - 1) }
                            ?: entry.page?.toString()
                    val suffix = displayPage?.let { "  ·  p. $it" } ?: ""
                    "$indent${entry.title}$suffix"
                }
                .toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Índice do PDF")
            .setItems(labels) { _, which ->
                val entry = outlineEntries.getOrNull(which) ?: return@setItems
                val page = entry.page
                if (page == null) {
                    Toast.makeText(
                        this,
                        "Este item do índice não aponta para uma página.",
                        Toast.LENGTH_SHORT,
                    ).show()
                } else {
                    js("LexPDF.goToPage($page)")
                }
            }
            .setNegativeButton("Fechar", null)
            .show()
    }

    private fun selectionActionModeCallback(
        nativeCallback: ActionMode.Callback,
    ): ActionMode.Callback =
        object : ActionMode.Callback {
            override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
                if (!nativeCallback.onCreateActionMode(mode, menu)) return false
                addSelectionMarkupActions(menu)
                return true
            }

            override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean {
                val nativeChanged = nativeCallback.onPrepareActionMode(mode, menu)
                addSelectionMarkupActions(menu)
                return nativeChanged
            }

            override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
                return when (item.itemId) {
                    ACTION_UNDERLINE -> {
                        captureSelectionThen(mode) {
                            val color = Color.argb(255, 35, 105, 210)
                            js("LexPDF.commitCapturedMarkup('underline', $color)")
                        }
                        true
                    }

                    ACTION_STRIKE -> {
                        captureSelectionThen(mode) {
                            val color = Color.argb(255, 210, 55, 55)
                            js("LexPDF.commitCapturedMarkup('strike', $color)")
                        }
                        true
                    }

                    ACTION_HIGHLIGHT -> {
                        captureSelectionThen(mode) { showSelectionHighlighterPalette() }
                        true
                    }

                    ACTION_REMOVE_MARKUP -> {
                        captureSelectionThen(mode) {
                            js("LexPDF.removeCapturedMarkups()")
                        }
                        true
                    }

                    ACTION_UNDO_MARKUP -> {
                        undoTextMarkup()
                        mode.finish()
                        true
                    }

                    ACTION_REDO_MARKUP -> {
                        redoTextMarkup()
                        mode.finish()
                        true
                    }

                    else -> nativeCallback.onActionItemClicked(mode, item)
                }
            }

            override fun onDestroyActionMode(mode: ActionMode) {
                nativeCallback.onDestroyActionMode(mode)
            }
        }

    private fun addSelectionMarkupActions(menu: Menu) {
        if (menu.findItem(ACTION_UNDERLINE) == null) {
            menu.add(Menu.NONE, ACTION_UNDERLINE, 90, "Sublinhar")
                .setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
        }
        if (menu.findItem(ACTION_STRIKE) == null) {
            menu.add(Menu.NONE, ACTION_STRIKE, 91, "Tachar")
                .setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
        }
        if (menu.findItem(ACTION_HIGHLIGHT) == null) {
            menu.add(Menu.NONE, ACTION_HIGHLIGHT, 92, "Marca-texto")
                .setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
        }
        if (menu.findItem(ACTION_REMOVE_MARKUP) == null) {
            menu.add(Menu.NONE, ACTION_REMOVE_MARKUP, 93, "Remover marcação")
                .setShowAsAction(MenuItem.SHOW_AS_ACTION_NEVER)
        }
        if (textMarkupUndoHistory.isNotEmpty() && menu.findItem(ACTION_UNDO_MARKUP) == null) {
            menu.add(Menu.NONE, ACTION_UNDO_MARKUP, 94, "Desfazer marcação")
                .setShowAsAction(MenuItem.SHOW_AS_ACTION_NEVER)
        }
        if (textMarkupRedoHistory.isNotEmpty() && menu.findItem(ACTION_REDO_MARKUP) == null) {
            menu.add(Menu.NONE, ACTION_REDO_MARKUP, 95, "Refazer marcação")
                .setShowAsAction(MenuItem.SHOW_AS_ACTION_NEVER)
        }
    }

    private fun captureSelectionThen(mode: ActionMode, action: () -> Unit) {
        webView.evaluateJavascript("LexPDF.captureSelectionForMarkup()") { result ->
            if (result == "true") {
                action()
            } else {
                Toast.makeText(this, "Selecione um trecho de texto.", Toast.LENGTH_SHORT).show()
            }
            mode.finish()
        }
    }

    private fun textMarkupRectsIntersect(
        first: TextMarkupRect,
        second: TextMarkupRect,
    ): Boolean {
        val firstRight = first.x + first.width
        val firstBottom = first.y + first.height
        val secondRight = second.x + second.width
        val secondBottom = second.y + second.height
        return first.x < secondRight &&
            firstRight > second.x &&
            first.y < secondBottom &&
            firstBottom > second.y
    }

    private fun recordTextMarkupHistory() {
        textMarkupUndoHistory.addLast(currentTextMarkups.toList())
        if (textMarkupUndoHistory.size > 100) {
            textMarkupUndoHistory.removeFirst()
        }
        textMarkupRedoHistory.clear()
    }

    private fun applyTextMarkupSnapshot(snapshot: List<TextMarkup>) {
        currentTextMarkups.clear()
        currentTextMarkups += snapshot
        persistTextMarkupsForPage(currentPageIndex)
        pushTextMarkupsToViewer()
    }

    private fun undoTextMarkup() {
        if (textMarkupUndoHistory.isEmpty()) return
        textMarkupRedoHistory.addLast(currentTextMarkups.toList())
        applyTextMarkupSnapshot(textMarkupUndoHistory.removeLast())
    }

    private fun redoTextMarkup() {
        if (textMarkupRedoHistory.isEmpty()) return
        textMarkupUndoHistory.addLast(currentTextMarkups.toList())
        applyTextMarkupSnapshot(textMarkupRedoHistory.removeLast())
    }

    private fun showSelectionHighlighterPalette() {
        val colors =
            intArrayOf(
                Color.argb(88, 255, 224, 64),
                Color.argb(88, 255, 188, 70),
                Color.argb(88, 255, 140, 80),
                Color.argb(88, 115, 225, 120),
                Color.argb(88, 80, 220, 175),
                Color.argb(88, 75, 200, 235),
                Color.argb(88, 105, 150, 245),
                Color.argb(88, 175, 120, 235),
                Color.argb(88, 245, 105, 175),
                Color.argb(88, 240, 105, 105),
            )
        val labels =
            arrayOf(
                "Amarelo",
                "Âmbar",
                "Laranja",
                "Verde",
                "Menta",
                "Azul claro",
                "Azul",
                "Violeta",
                "Rosa",
                "Coral",
            )

        val paletteContainer =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(18.dp, 12.dp, 18.dp, 6.dp)
            }

        for (rowStart in colors.indices step 5) {
            val row =
                LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER
                }
            for (index in rowStart until minOf(rowStart + 5, colors.size)) {
                val color = colors[index]
                val swatch =
                    Button(this).apply {
                        text = ""
                        minWidth = 0
                        minimumWidth = 0
                        setPadding(0, 0, 0, 0)
                        backgroundTintList = ColorStateList.valueOf(color)
                        contentDescription = labels[index]
                    }
                row.addView(
                    swatch,
                    LinearLayout.LayoutParams(48.dp, 44.dp).apply {
                        marginStart = 4.dp
                        marginEnd = 4.dp
                        topMargin = 4.dp
                        bottomMargin = 4.dp
                    },
                )
            }
            paletteContainer.addView(row)
        }

        val dialog =
            AlertDialog.Builder(this)
                .setTitle("Marca-texto da seleção")
                .setView(paletteContainer)
                .setNegativeButton("Cancelar") { _, _ ->
                    js("LexPDF.clearTextSelection()")
                }
                .create()

        for (rowIndex in 0 until paletteContainer.childCount) {
            val row = paletteContainer.getChildAt(rowIndex) as? LinearLayout ?: continue
            for (buttonIndex in 0 until row.childCount) {
                val button = row.getChildAt(buttonIndex) as? Button ?: continue
                button.setOnClickListener {
                    val index = rowIndex * 5 + buttonIndex
                    if (index in colors.indices) {
                        val color = colors[index]
                        js("LexPDF.commitCapturedMarkup('highlight', $color)")
                        dialog.dismiss()
                    }
                }
            }
        }
        dialog.show()
    }

    private fun loadInkPreferences() {
        val prefs = getSharedPreferences(INK_PREFS, Context.MODE_PRIVATE)
        penColor = prefs.getInt(PREF_PEN_COLOR, Color.rgb(20, 24, 30))
        penSize = prefs.getFloat(PREF_PEN_SIZE, 3.0f).coerceIn(1f, 16f)
        highlighterColor =
            prefs.getInt(PREF_HIGHLIGHT_COLOR, Color.argb(72, 255, 224, 64))
        highlighterColor =
            Color.argb(
                72,
                Color.red(highlighterColor),
                Color.green(highlighterColor),
                Color.blue(highlighterColor),
            )
        highlighterSize =
            prefs.getFloat(PREF_HIGHLIGHT_SIZE, 18f).coerceIn(6f, 40f)
    }

    private fun saveInkPreferences() {
        getSharedPreferences(INK_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putInt(PREF_PEN_COLOR, penColor)
            .putFloat(PREF_PEN_SIZE, penSize)
            .putInt(PREF_HIGHLIGHT_COLOR, highlighterColor)
            .putFloat(PREF_HIGHLIGHT_SIZE, highlighterSize)
            .apply()
    }

    private fun showInkSettings(kind: InkKind) {
        currentKind = kind
        val initialStyle = currentInkStyle()
        var selectedColor = initialStyle.colorArgb
        var selectedSize = initialStyle.size

        val container =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(20.dp, 8.dp, 20.dp, 4.dp)
            }

        val colorLabel =
            TextView(this).apply {
                text = "Cor"
                textSize = 15f
                setPadding(0, 4.dp, 0, 8.dp)
            }
        container.addView(colorLabel)

        val palette =
            if (kind == InkKind.PEN) {
                intArrayOf(
                    Color.rgb(20, 24, 30),      // preto
                    Color.rgb(70, 74, 82),      // grafite
                    Color.rgb(25, 92, 190),     // azul
                    Color.rgb(35, 135, 220),    // azul claro
                    Color.rgb(210, 45, 45),     // vermelho
                    Color.rgb(235, 95, 45),     // laranja
                    Color.rgb(25, 135, 75),     // verde
                    Color.rgb(20, 155, 130),    // turquesa
                    Color.rgb(125, 65, 180),    // roxo
                    Color.rgb(210, 65, 145),    // rosa
                    Color.rgb(120, 75, 45),     // marrom
                    Color.rgb(215, 165, 30),    // ocre
                )
            } else {
                intArrayOf(
                    Color.argb(72, 255, 224, 64),   // amarelo
                    Color.argb(72, 255, 188, 70),   // âmbar
                    Color.argb(72, 255, 140, 80),   // laranja
                    Color.argb(72, 115, 225, 120),  // verde
                    Color.argb(72, 80, 220, 175),   // menta
                    Color.argb(72, 75, 200, 235),   // azul
                    Color.argb(72, 105, 150, 245),  // azul royal
                    Color.argb(72, 175, 120, 235),  // violeta
                    Color.argb(72, 245, 105, 175),  // rosa
                    Color.argb(72, 240, 105, 105),  // coral
                )
            }

        val colorRow =
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
        palette.forEachIndexed { index, color ->
            val swatch =
                Button(this).apply {
                    text = if (color == selectedColor) "✓" else ""
                    textSize = 16f
                    minWidth = 0
                    setPadding(0, 0, 0, 0)
                    setBackgroundColor(color)
                    contentDescription = "Cor ${index + 1}"
                    setOnClickListener {
                        selectedColor = color
                        for (childIndex in 0 until colorRow.childCount) {
                            (colorRow.getChildAt(childIndex) as? Button)?.text =
                                if (childIndex == index) "✓" else ""
                        }
                    }
                }
            colorRow.addView(
                swatch,
                LinearLayout.LayoutParams(46.dp, 42.dp).apply {
                    marginEnd = 6.dp
                },
            )
        }
        container.addView(colorRow)

        val minSize = if (kind == InkKind.PEN) 1 else 6
        val maxSize = if (kind == InkKind.PEN) 16 else 40
        val sizeLabel =
            TextView(this).apply {
                text = "Espessura: ${selectedSize.roundToInt()}"
                textSize = 15f
                setPadding(0, 14.dp, 0, 2.dp)
            }
        container.addView(sizeLabel)

        val seek =
            SeekBar(this).apply {
                max = maxSize - minSize
                progress =
                    (selectedSize.roundToInt().coerceIn(minSize, maxSize) - minSize)
            }
        seek.setOnSeekBarChangeListener(
            object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(
                    seekBar: SeekBar?,
                    progress: Int,
                    fromUser: Boolean,
                ) {
                    selectedSize = (minSize + progress).toFloat()
                    sizeLabel.text = "Espessura: ${selectedSize.roundToInt()}"
                }

                override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit
                override fun onStopTrackingTouch(seekBar: SeekBar?) = Unit
            },
        )
        container.addView(seek)

        if (kind == InkKind.HIGHLIGHTER) {
            container.addView(
                TextView(this).apply {
                    text = "O marca-texto usa transparência baixa para preservar a legibilidade do texto sem cobrir a página."
                    textSize = 12f
                    alpha = 0.72f
                    setPadding(0, 8.dp, 0, 0)
                },
            )
        }

        AlertDialog.Builder(this)
            .setTitle(
                if (kind == InkKind.PEN) {
                    "Personalizar caneta"
                } else {
                    "Personalizar marca-texto"
                },
            )
            .setView(container)
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Aplicar") { _, _ ->
                if (kind == InkKind.PEN) {
                    penColor = selectedColor
                    penSize = selectedSize
                } else {
                    // Enforce a readable marker alpha regardless of legacy
                    // preference values or palette migrations.
                    highlighterColor =
                        Color.argb(
                            72,
                            Color.red(selectedColor),
                            Color.green(selectedColor),
                            Color.blue(selectedColor),
                        )
                    highlighterSize = selectedSize
                }
                saveInkPreferences()
                selectInk(kind)
            }
            .show()
    }

    private fun updateWetInkCompositing(kind: InkKind) {
        if (!::wetInkView.isInitialized) return
        // Keep the live stroke on normal hardware composition. Highlighter
        // readability is controlled by its low-alpha color, not by an Xfermode
        // applied to the whole overlay (which can obscure the PDF WebView).
        wetInkView.setLayerType(View.LAYER_TYPE_HARDWARE, null)
    }

    private fun selectTextMode() {
        fingerInkEnabled = false
        currentTool =
            if (currentKind == InkKind.PEN) InkTool.PEN else InkTool.HIGHLIGHTER

        if (::readerFrame.isInitialized) {
            readerFrame.interceptFingerInput = false
        }
        if (::wetInkView.isInitialized) {
            wetInkView.cancelUnfinishedStrokes()
        }
        strokeStyles.clear()

        if (::penButton.isInitialized) {
            penButton.text = "Caneta"
            penButton.alpha = 0.72f
        }
        if (::highlighterButton.isInitialized) {
            highlighterButton.text = "Marca"
            highlighterButton.alpha = 0.72f
        }
        if (::eraserButton.isInitialized) {
            eraserButton.text = "Borracha"
            eraserButton.alpha = 0.72f
        }
        if (::statusLabel.isInitialized) {
            statusLabel.text = "Toque: selecionar texto • S Pen continua disponível"
        }
    }

    private fun selectInk(kind: InkKind) {
        currentKind = kind
        currentTool =
            if (kind == InkKind.PEN) InkTool.PEN else InkTool.HIGHLIGHTER
        fingerInkEnabled = true
        if (::readerFrame.isInitialized) {
            readerFrame.interceptFingerInput = true
        }
        updateWetInkCompositing(kind)
        val style = currentInkStyle()

        if (::penButton.isInitialized) {
            penButton.text = if (kind == InkKind.PEN) "✓ Caneta" else "Caneta"
            penButton.alpha = if (kind == InkKind.PEN) 1.0f else 0.72f
        }
        if (::highlighterButton.isInitialized) {
            highlighterButton.text =
                if (kind == InkKind.HIGHLIGHTER) "✓ Marca" else "Marca"
            highlighterButton.alpha =
                if (kind == InkKind.HIGHLIGHTER) 1.0f else 0.72f
        }

        if (::eraserButton.isInitialized) {
            eraserButton.text = "Borracha"
            eraserButton.alpha = 0.72f
        }

        statusLabel.text =
            when (kind) {
                InkKind.PEN ->
                    "Toque/S Pen: caneta • ${style.size.roundToInt()} • segure para personalizar"
                InkKind.HIGHLIGHTER ->
                    "Toque/S Pen: marca-texto • ${style.size.roundToInt()} • segure para personalizar"
            }
    }

    private fun selectEraser() {
        currentTool = InkTool.ERASER
        fingerInkEnabled = true
        if (::readerFrame.isInitialized) {
            readerFrame.interceptFingerInput = true
        }
        wetInkView.cancelUnfinishedStrokes()
        strokeStyles.clear()
        updateWetInkCompositing(InkKind.PEN)

        if (::penButton.isInitialized) {
            penButton.text = "Caneta"
            penButton.alpha = 0.72f
        }
        if (::highlighterButton.isInitialized) {
            highlighterButton.text = "Marca"
            highlighterButton.alpha = 0.72f
        }
        if (::eraserButton.isInitialized) {
            eraserButton.text = "✓ Borracha"
            eraserButton.alpha = 1.0f
        }
        statusLabel.text =
            "Toque/S Pen: borracha de traço • apaga caneta e marca-texto"
    }

    private fun eventPointInPage(event: MotionEvent): FloatArray {
        val point = floatArrayOf(event.x, event.y)
        viewToPageMatrix().mapPoints(point)
        return point
    }

    private fun eraserRadiusInPage(): Float {
        val metrics = pageMetrics ?: return 14f
        val sx = metrics.canvasWidth / metrics.pageWidth.coerceAtLeast(1f)
        val sy = metrics.canvasHeight / metrics.pageHeight.coerceAtLeast(1f)
        val scale = ((sx + sy) / 2f).coerceAtLeast(0.1f)
        return (18.dp).toFloat() / scale
    }

    private fun squaredDistanceToSegment(
        px: Float,
        py: Float,
        ax: Float,
        ay: Float,
        bx: Float,
        by: Float,
    ): Float {
        val abx = bx - ax
        val aby = by - ay
        val ab2 = abx * abx + aby * aby
        if (ab2 <= 0.0001f) {
            val dx = px - ax
            val dy = py - ay
            return dx * dx + dy * dy
        }
        val apx = px - ax
        val apy = py - ay
        val t = ((apx * abx + apy * aby) / ab2).coerceIn(0f, 1f)
        val cx = ax + t * abx
        val cy = ay + t * aby
        val dx = px - cx
        val dy = py - cy
        return dx * dx + dy * dy
    }

    private fun strokeIntersectsEraser(
        entry: InkEntry,
        pageX: Float,
        pageY: Float,
        radius: Float,
    ): Boolean {
        val inputs = entry.stroke.inputs
        if (inputs.size <= 0) return false

        val effectiveRadius = radius + entry.style.size * 0.55f
        val radiusSquared = effectiveRadius * effectiveRadius

        var previous = inputs[0]
        run {
            val dx = pageX - previous.x
            val dy = pageY - previous.y
            if (dx * dx + dy * dy <= radiusSquared) return true
        }

        for (index in 1 until inputs.size) {
            val point = inputs[index]
            if (
                squaredDistanceToSegment(
                    pageX,
                    pageY,
                    previous.x,
                    previous.y,
                    point.x,
                    point.y,
                ) <= radiusSquared
            ) {
                return true
            }
            previous = point
        }
        return false
    }

    private fun eraseAt(event: MotionEvent): Boolean {
        if (currentEntries.isEmpty()) return false
        val point = eventPointInPage(event)
        val radius = eraserRadiusInPage()

        for (index in currentEntries.indices.reversed()) {
            val entry = currentEntries[index]
            if (entry in erasedThisGesture) continue
            if (!strokeIntersectsEraser(entry, point[0], point[1], radius)) continue

            currentEntries.removeAt(index)
            erasedThisGesture += entry
            undoHistory.addLast(InkHistoryAction.Removed(index, entry))
            redoHistory.clear()
            refreshInkLayers()
            persistInkForPage(currentPageIndex)
            return true
        }
        return false
    }

    private fun currentInkStyle(): InkStyle =
        when (currentKind) {
            InkKind.PEN -> InkStyle(InkKind.PEN, penColor, penSize)
            InkKind.HIGHLIGHTER ->
                InkStyle(InkKind.HIGHLIGHTER, highlighterColor, highlighterSize)
        }

    private fun brushFor(style: InkStyle): Brush =
        Brush.createWithColorIntArgb(
            if (style.kind == InkKind.PEN) {
                StockBrushes.pressurePen()
            } else {
                StockBrushes.highlighter()
            },
            style.colorArgb,
            style.size,
            if (style.kind == InkKind.PEN) 0.1f else 0.2f,
        )

    private fun currentBrush(): Brush = brushFor(currentInkStyle())

    private fun refreshInkLayers() {
        if (::highlighterInkView.isInitialized) {
            highlighterInkView.setEntries(currentEntries)
        }
        if (::penInkView.isInitialized) {
            penInkView.setEntries(currentEntries)
        }
    }

    private fun handleStylusEvent(event: MotionEvent): Boolean {
        val metrics = pageMetrics ?: return false
        if (metrics.pageIndex != currentPageIndex) return false

        val actionIndex = event.actionIndex.coerceAtLeast(0)
        val pointerId = event.getPointerId(actionIndex)
        val toolType = event.getToolType(actionIndex)
        val hardwareEraser = toolType == MotionEvent.TOOL_TYPE_ERASER
        val eraseMode = hardwareEraser || currentTool == InkTool.ERASER

        if (eraseMode) {
            return when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    readerFrame.requestUnbufferedDispatch(event)
                    eraserGestureActive = true
                    erasedThisGesture.clear()
                    eraseAt(event)
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    eraseAt(event)
                    true
                }

                MotionEvent.ACTION_UP,
                MotionEvent.ACTION_POINTER_UP,
                MotionEvent.ACTION_CANCEL -> {
                    eraserGestureActive = false
                    erasedThisGesture.clear()
                    true
                }

                else -> true
            }
        }

        return when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                readerFrame.requestUnbufferedDispatch(event)
                val style = currentInkStyle()
                val strokeId =
                    wetInkView.startStroke(
                        event,
                        pointerId,
                        brushFor(style),
                        viewToPageMatrix(),
                        Matrix(),
                    )
                strokeStyles[strokeId] = style
                true
            }

            MotionEvent.ACTION_MOVE -> {
                for (i in 0 until event.pointerCount) {
                    wetInkView.addToStroke(event, event.getPointerId(i))
                }
                true
            }

            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_POINTER_UP -> {
                wetInkView.finishStroke(event, pointerId)
                true
            }

            MotionEvent.ACTION_CANCEL -> {
                wetInkView.cancelUnfinishedStrokes()
                strokeStyles.clear()
                true
            }

            else -> true
        }
    }

    override fun onStrokesFinished(strokes: Map<InProgressStrokeId, Stroke>) {
        strokes.forEach { (id, stroke) ->
            val style = strokeStyles.remove(id) ?: currentInkStyle()
            val entry = InkEntry(style, stroke)
            currentEntries += entry
            undoHistory.addLast(InkHistoryAction.Added(entry))
        }
        redoHistory.clear()
        refreshInkLayers()
        wetInkView.removeFinishedStrokes(strokes.keys)
        persistInkForPage(currentPageIndex)
    }

    private fun undoInk() {
        if (undoHistory.isEmpty()) return
        val action = undoHistory.removeLast()
        when (action) {
            is InkHistoryAction.Added -> {
                currentEntries.remove(action.entry)
            }
            is InkHistoryAction.Removed -> {
                val targetIndex = action.index.coerceIn(0, currentEntries.size)
                currentEntries.add(targetIndex, action.entry)
            }
        }
        redoHistory.addLast(action)
        refreshInkLayers()
        persistInkForPage(currentPageIndex)
    }

    private fun redoInk() {
        if (redoHistory.isEmpty()) return
        val action = redoHistory.removeLast()
        when (action) {
            is InkHistoryAction.Added -> {
                currentEntries += action.entry
            }
            is InkHistoryAction.Removed -> {
                currentEntries.remove(action.entry)
            }
        }
        undoHistory.addLast(action)
        refreshInkLayers()
        persistInkForPage(currentPageIndex)
    }

    private fun pageToViewMatrix(): Matrix {
        val m = pageMetrics ?: return Matrix()
        val sx = m.canvasWidth / m.pageWidth.coerceAtLeast(1f)
        val sy = m.canvasHeight / m.pageHeight.coerceAtLeast(1f)
        return Matrix().apply {
            postScale(sx, sy)
            postTranslate(m.canvasLeft, m.canvasTop)
        }
    }

    private fun viewToPageMatrix(): Matrix {
        val inverse = Matrix()
        pageToViewMatrix().invert(inverse)
        return inverse
    }

    private fun textMarkupFile(pageIndex: Int): File {
        val documentKey = sourceFile.absolutePath.hashCode().toUInt().toString(16)
        val directory = File(filesDir, "pdfjs_text_markup/$documentKey").apply { mkdirs() }
        return File(directory, "page_${pageIndex + 1}.json")
    }

    private fun textMarkupsJson(values: List<TextMarkup>): JSONArray =
        JSONArray().apply {
            values.forEach { markup ->
                put(
                    JSONObject().apply {
                        put("kind", markup.kind.name.lowercase())
                        put("colorArgb", markup.colorArgb)
                        put(
                            "rects",
                            JSONArray().apply {
                                markup.rects.forEach { rect ->
                                    put(
                                        JSONObject().apply {
                                            put("x", rect.x)
                                            put("y", rect.y)
                                            put("width", rect.width)
                                            put("height", rect.height)
                                        },
                                    )
                                }
                            },
                        )
                    },
                )
            }
        }

    private fun pushTextMarkupsToViewer() {
        val payload = textMarkupsJson(currentTextMarkups).toString()
        js("LexPDF.setTextMarkups($payload)")
    }

    private fun persistTextMarkupsForPage(pageIndex: Int) {
        val snapshot = currentTextMarkups.toList()
        ioExecutor.execute {
            val target = textMarkupFile(pageIndex)
            if (snapshot.isEmpty()) {
                target.delete()
                return@execute
            }
            val temp = File(target.parentFile, "${target.name}.tmp")
            try {
                temp.writeText(textMarkupsJson(snapshot).toString())
                if (!temp.renameTo(target)) {
                    temp.copyTo(target, overwrite = true)
                    temp.delete()
                }
            } catch (_: Throwable) {
                temp.delete()
            }
        }
    }

    private fun loadTextMarkupsForPage(pageIndex: Int) {
        currentTextMarkups.clear()
        textMarkupUndoHistory.clear()
        textMarkupRedoHistory.clear()
        pushTextMarkupsToViewer()
        val source = textMarkupFile(pageIndex)
        if (!source.isFile) return

        ioExecutor.execute {
            val loaded = mutableListOf<TextMarkup>()
            try {
                val array = JSONArray(source.readText())
                for (index in 0 until array.length()) {
                    val obj = array.optJSONObject(index) ?: continue
                    val kind =
                        when (obj.optString("kind")) {
                            "highlight" -> TextMarkupKind.HIGHLIGHT
                            "underline" -> TextMarkupKind.UNDERLINE
                            "strike" -> TextMarkupKind.STRIKE
                            else -> continue
                        }
                    val rectArray = obj.optJSONArray("rects") ?: continue
                    val rects = mutableListOf<TextMarkupRect>()
                    for (rectIndex in 0 until rectArray.length()) {
                        val rect = rectArray.optJSONObject(rectIndex) ?: continue
                        rects +=
                            TextMarkupRect(
                                rect.optDouble("x").toFloat(),
                                rect.optDouble("y").toFloat(),
                                rect.optDouble("width").toFloat(),
                                rect.optDouble("height").toFloat(),
                            )
                    }
                    if (rects.isNotEmpty()) {
                        loaded += TextMarkup(kind, obj.optInt("colorArgb"), rects)
                    }
                }
            } catch (_: Throwable) {
                loaded.clear()
            }

            runOnUiThread {
                if (pageIndex != currentPageIndex || isFinishing) return@runOnUiThread
                currentTextMarkups.clear()
                currentTextMarkups += loaded
                pushTextMarkupsToViewer()
            }
        }
    }

    private fun sidecarFile(pageIndex: Int): File {
        val documentKey = sourceFile.absolutePath.hashCode().toUInt().toString(16)
        val directory = File(filesDir, "pdfjs_ink/$documentKey").apply { mkdirs() }
        return File(directory, "page_${pageIndex + 1}.ink")
    }

    private fun persistInkForPage(pageIndex: Int) {
        val snapshot = currentEntries.toList()
        ioExecutor.execute {
            val target = sidecarFile(pageIndex)
            if (snapshot.isEmpty()) {
                target.delete()
                return@execute
            }
            val temp = File(target.parentFile, "${target.name}.tmp")
            try {
                DataOutputStream(temp.outputStream().buffered()).use { output ->
                    output.writeInt(SIDECAR_VERSION)
                    output.writeInt(snapshot.size)
                    snapshot.forEach { entry ->
                        output.writeInt(entry.style.kind.ordinal)
                        output.writeInt(entry.style.colorArgb)
                        output.writeFloat(entry.style.size)
                        val encoded =
                            ByteArrayOutputStream().use { bytes ->
                                entry.stroke.inputs.encode(bytes)
                                bytes.toByteArray()
                            }
                        output.writeInt(encoded.size)
                        output.write(encoded)
                    }
                }
                if (!temp.renameTo(target)) {
                    temp.copyTo(target, overwrite = true)
                    temp.delete()
                }
            } catch (_: Throwable) {
                temp.delete()
            }
        }
    }

    private fun loadInkForPage(pageIndex: Int) {
        currentEntries.clear()
        undoHistory.clear()
        redoHistory.clear()
        erasedThisGesture.clear()
        refreshInkLayers()
        pageMetrics = null

        val source = sidecarFile(pageIndex)
        if (!source.isFile) return

        ioExecutor.execute {
            val loaded = mutableListOf<InkEntry>()
            try {
                DataInputStream(source.inputStream().buffered()).use { input ->
                    val version = input.readInt()
                    require(version in 2..SIDECAR_VERSION)
                    val count = input.readInt().coerceIn(0, 50_000)
                    repeat(count) {
                        val kind =
                            InkKind.entries.getOrElse(input.readInt()) { InkKind.PEN }
                        val style =
                            if (version >= 3) {
                                run {
                                    val savedColor = input.readInt()
                                    val normalizedColor =
                                        if (kind == InkKind.HIGHLIGHTER) {
                                            Color.argb(
                                                72,
                                                Color.red(savedColor),
                                                Color.green(savedColor),
                                                Color.blue(savedColor),
                                            )
                                        } else {
                                            savedColor
                                        }
                                    InkStyle(
                                        kind = kind,
                                        colorArgb = normalizedColor,
                                        size =
                                            input
                                                .readFloat()
                                                .coerceIn(
                                                    if (kind == InkKind.PEN) 1f else 6f,
                                                    if (kind == InkKind.PEN) 16f else 40f,
                                                ),
                                    )
                                }
                            } else {
                                if (kind == InkKind.PEN) {
                                    InkStyle(
                                        InkKind.PEN,
                                        Color.rgb(20, 24, 30),
                                        3.0f,
                                    )
                                } else {
                                    InkStyle(
                                        InkKind.HIGHLIGHTER,
                                        Color.argb(72, 255, 224, 64),
                                        18f,
                                    )
                                }
                            }
                        val length = input.readInt().coerceIn(0, 16 * 1024 * 1024)
                        val bytes = ByteArray(length)
                        input.readFully(bytes)
                        val batch =
                            StrokeInputBatch.decode(ByteArrayInputStream(bytes))
                        loaded += InkEntry(style, Stroke(brushFor(style), batch))
                    }
                }
            } catch (_: Throwable) {
                loaded.clear()
            }

            runOnUiThread {
                if (pageIndex != currentPageIndex || isFinishing) return@runOnUiThread
                currentEntries.clear()
                currentEntries += loaded
                refreshInkLayers()
            }
        }
    }

    override fun onPause() {
        publishLastPageResult()
        super.onPause()
    }

    private fun publishLastPageResult() {
        setResult(
            RESULT_OK,
            android.content.Intent().apply {
                putExtra(EXTRA_LAST_PAGE, currentPageIndex + 1)
            },
        )
    }

    override fun onDestroy() {
        publishLastPageResult()
        PdfCrashDiagnostics.mark(this, "JSZ_ON_DESTROY")
        try {
            persistInkForPage(currentPageIndex)
            persistTextMarkupsForPage(currentPageIndex)
        } catch (_: Throwable) {
        }
        try {
            wetInkView.clearFinishedStrokesListeners()
        } catch (_: Throwable) {
        }
        pendingSearchRunnable?.let { searchHandler.removeCallbacks(it) }
        pendingSearchRunnable = null
        try {
            rangeReader?.close()
            rangeReader = null
        } catch (_: Throwable) {
        }
        try {
            webView.removeJavascriptInterface("LexPdfBridge")
            webView.stopLoading()
            webView.loadUrl("about:blank")
            webView.clearHistory()
            webView.removeAllViews()
            webView.destroy()
        } catch (_: Throwable) {
        }
        ioExecutor.shutdown()
        super.onDestroy()
    }

    private val Int.dp: Int
        get() = (this * resources.displayMetrics.density).roundToInt()

    private class SelectionAwareWebView(
        context: Context,
        private val callbackDecorator: (ActionMode.Callback) -> ActionMode.Callback,
    ) : WebView(context) {
        override fun startActionMode(callback: ActionMode.Callback): ActionMode? =
            super.startActionMode(callbackDecorator(callback))

        override fun startActionMode(
            callback: ActionMode.Callback,
            type: Int,
        ): ActionMode? =
            super.startActionMode(callbackDecorator(callback), type)
    }

    private class StylusRouterLayout(context: Context) : FrameLayout(context) {
        var onStylusEvent: ((MotionEvent) -> Boolean)? = null
        var interceptFingerInput: Boolean = false

        override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
            if (ev.pointerCount <= 0) return false

            // Keep two-finger gestures available for navigation/zoom even when
            // a finger ink tool is active.
            if (ev.pointerCount > 1) return false

            val type = ev.getToolType(ev.actionIndex.coerceAtLeast(0))
            return when (type) {
                MotionEvent.TOOL_TYPE_STYLUS,
                MotionEvent.TOOL_TYPE_ERASER,
                -> true

                MotionEvent.TOOL_TYPE_FINGER -> interceptFingerInput
                else -> false
            }
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            return onStylusEvent?.invoke(event) ?: false
        }
    }

    private class DryInkView(
        context: Context,
        private val matrixProvider: () -> Matrix,
        private val kind: InkKind,
    ) : View(context) {
        private val entries = mutableListOf<InkEntry>()
        private val renderer =
            ViewStrokeRenderer(
                CanvasStrokeRenderer.create(),
                this,
            )

        init {
            setWillNotDraw(false)
            isClickable = false
            isFocusable = false
            setLayerType(LAYER_TYPE_HARDWARE, null)
        }

        fun setEntries(values: List<InkEntry>) {
            entries.clear()
            entries.addAll(values.filter { it.style.kind == kind })
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val transform = matrixProvider()
            renderer.drawWithStrokes(canvas) { scope ->
                canvas.save()
                canvas.concat(transform)
                entries.forEach { entry ->
                    scope.drawStroke(entry.stroke)
                }
                canvas.restore()
            }
        }
    }
}