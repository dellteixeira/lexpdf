package com.lexpdf.lexpdf_app

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.PointF
import android.os.Build
import android.os.Bundle
import android.text.TextUtils
import android.text.InputType
import android.util.Base64
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
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
import androidx.ink.strokes.MutableStrokeInputBatch
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
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.PI
import kotlin.math.ceil
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
        @Volatile
        private var webViewDirectoryConfigured = false
    }

    private enum class InkKind { PEN, HIGHLIGHTER }

    private enum class InkTool {
        PEN,
        HIGHLIGHTER,
        UNDERLINE,
        SHAPE,
        ERASER,
    }

    private enum class ShapeTool(val label: String) {
        ARROW("Seta"),
        CIRCLE("Círculo"),
        RECTANGLE("Retângulo"),
        LINE("Linha"),
        STAR("Estrela"),
    }

    private enum class EraserMode(val label: String) {
        WHOLE_STROKE("Traço inteiro"),
        PARTIAL("Apagar parte"),
    }

    private sealed interface InkHistoryAction {
        data class Added(val entry: InkEntry) : InkHistoryAction
        data class Removed(val index: Int, val entry: InkEntry) : InkHistoryAction
        data class Replaced(
            val index: Int,
            val original: InkEntry,
            val replacements: List<InkEntry>,
        ) : InkHistoryAction
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
    private lateinit var statusLabel: TextView
    private lateinit var penButton: Button
    private lateinit var highlighterButton: Button
    private lateinit var underlineButton: Button
    private lateinit var shapesButton: Button
    private lateinit var eraserButton: Button
    private lateinit var readerFrame: StylusRouterLayout

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var currentPageIndex = 0
    private var pageCount = 0
    private var pageMetrics: PageMetrics? = null

    private var currentKind = InkKind.PEN
    private var currentTool = InkTool.PEN
    private var currentShape = ShapeTool.LINE
    private var eraserMode = EraserMode.WHOLE_STROKE
    private var penColor = Color.rgb(20, 24, 30)
    private var penSize = 3.0f
    private var highlighterColor = Color.argb(72, 255, 224, 64)
    private var highlighterSize = 18f
    private val currentEntries = mutableListOf<InkEntry>()
    private val undoHistory = ArrayDeque<InkHistoryAction>()
    private val redoHistory = ArrayDeque<InkHistoryAction>()
    private var eraserGestureActive = false
    private val erasedThisGesture = mutableSetOf<InkEntry>()
    private val strokeStyles = mutableMapOf<InProgressStrokeId, InkStyle>()
    private val strokeTools = mutableMapOf<InProgressStrokeId, InkTool>()
    private val strokeShapeTools = mutableMapOf<InProgressStrokeId, ShapeTool>()
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

        PdfCrashDiagnostics.mark(
            this,
            "JS02_SOURCE_READY",
            "size=${sourceFile.length()} pathHash=${sourceFile.absolutePath.hashCode()}",
        )

        buildUi()
        configureWebView()
        loadInkForPage(currentPageIndex)
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
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(18, 20, 24))
        }

        fun toolRow(): LinearLayout =
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(6.dp, 3.dp, 6.dp, 3.dp)
                setBackgroundColor(Color.rgb(242, 244, 247))
            }

        fun button(label: String, onClick: () -> Unit): Button =
            Button(this).apply {
                text = label
                isAllCaps = false

                val targetWidthDp =
                    when {
                        label.length <= 1 -> 42
                        label == "Ir" -> 48
                        label.contains("Página") -> 86
                        label.length <= 5 -> 64
                        label.length <= 7 -> 72
                        else -> 80
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
                setOnClickListener { onClick() }
            }

        val navigationRow = toolRow()
        navigationRow.addView(button("‹") { js("LexPDF.previousPage()") })

        pageLabel = TextView(this).apply {
            gravity = Gravity.CENTER
            textSize = 14f
            setTextColor(Color.rgb(30, 33, 38))
            text = "…"
            isClickable = true
            isFocusable = true
            setOnClickListener { showPageJumpDialog() }
        }
        navigationRow.addView(
            pageLabel,
            LinearLayout.LayoutParams(110.dp, LinearLayout.LayoutParams.MATCH_PARENT),
        )

        navigationRow.addView(button("Ir") { showPageJumpDialog() })
        navigationRow.addView(button("›") { js("LexPDF.nextPage()") })
        navigationRow.addView(button("−") { js("LexPDF.zoomOut()") })
        navigationRow.addView(button("+") { js("LexPDF.zoomIn()") })
        navigationRow.addView(
            button("⛶ Página") { js("LexPDF.fitPage()") }.apply {
                contentDescription = "Página inteira"
            },
        )
        navigationRow.addView(button("Índice") { showOutlineDialog() })
        navigationRow.addView(button("Fechar") { finish() })

        val inkRow = toolRow()
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
        underlineButton =
            button("Sublinhar") {
                selectUnderline()
            }.apply {
                contentDescription = "Sublinhar palavras com uma linha reta"
            }

        shapesButton =
            button("Formas") {
                showShapeToolDialog()
            }.apply {
                contentDescription = "Seta, círculo, retângulo, linha e estrela"
            }

        eraserButton =
            button("Borracha") {
                showEraserModeDialog()
            }.apply {
                contentDescription = "Apagar traço inteiro ou somente parte do desenho"
            }

        inkRow.addView(penButton)
        inkRow.addView(highlighterButton)
        inkRow.addView(underlineButton)
        inkRow.addView(shapesButton)
        inkRow.addView(eraserButton)
        inkRow.addView(button("Desfazer") { undoInk() })
        inkRow.addView(button("Refazer") { redoInk() })

        statusLabel = TextView(this).apply {
            textSize = 12f
            gravity = Gravity.CENTER_VERTICAL
            setTextColor(Color.rgb(65, 68, 74))
            setPadding(10.dp, 0, 6.dp, 0)
            text = "PDF.js iniciando…"
        }
        inkRow.addView(
            statusLabel,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f),
        )

        root.addView(
            navigationRow,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                48.dp,
            ),
        )
        root.addView(
            inkRow,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                48.dp,
            ),
        )

        readerFrame = StylusRouterLayout(this).apply {
            setBackgroundColor(Color.rgb(32, 34, 39))
            onStylusEvent = { event -> handleStylusEvent(event) }
        }

        webView = WebView(this)
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

        root.addView(
            readerFrame,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        setContentView(root)
        selectInk(currentKind)
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
        fun pageChanged(page: Int) {
            runOnUiThread {
                val next = (page - 1).coerceAtLeast(0)
                if (next != currentPageIndex) {
                    persistInkForPage(currentPageIndex)
                    currentPageIndex = next
                    undoHistory.clear()
                    redoHistory.clear()
                    loadInkForPage(next)
                }
                updatePageLabel()
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
    html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#202227;color:#fff;font-family:sans-serif}
    #stage{position:absolute;inset:0;overflow:auto;overscroll-behavior:contain;display:flex;align-items:flex-start;justify-content:center}
    #wrap{padding:18px 18px 36px;min-width:max-content}
    canvas{display:block;background:white;box-shadow:0 3px 18px #0008}
    #loading{position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);background:#17191dcc;padding:12px 18px;border-radius:18px;font-size:14px}
  </style>
</head>
<body>
<div id="stage"><div id="wrap"><canvas id="pdf"></canvas></div></div>
<div id="loading">Abrindo PDF…</div>
<script type="module">
import * as pdfjsLib from 'https://cdn.jsdelivr.net/npm/pdfjs-dist@${PDFJS_VERSION}/build/pdf.min.mjs';
pdfjsLib.GlobalWorkerOptions.workerSrc =
  'https://cdn.jsdelivr.net/npm/pdfjs-dist@${PDFJS_VERSION}/build/pdf.worker.min.mjs';

const PDF_LENGTH = ${sourceFile.length()};
const RANGE_CHUNK_SIZE = ${RANGE_CHUNK_SIZE};
const canvas = document.getElementById('pdf');
const ctx = canvas.getContext('2d', { alpha: false });
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
let singleTouchStartX = 0;
let singleTouchStartY = 0;
let singleTouchStartScrollTop = 0;
let singleTouchActive = false;
let metricsFrame = 0;
let rangeTransport = null;
let rangeFailed = false;
let pdfPageLabels = null;
let inferredPrintedOffset = null;
let printedPaginationReady = false;
const printedToPhysical = new Map();
const physicalToPrinted = new Map();
let numericPaginationSegments = [];

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
  }
};

stage.addEventListener('scroll', () => {
  scheduleMetricsSync();
}, { passive: true });
window.addEventListener('resize', settleMetrics);

stage.addEventListener('touchstart', e => {
  if (e.touches.length === 1) {
    singleTouchActive = true;
    singleTouchStartX = e.touches[0].clientX;
    singleTouchStartY = e.touches[0].clientY;
    singleTouchStartScrollTop = stage.scrollTop;
  } else {
    singleTouchActive = false;
  }

  if (e.touches.length === 2) {
    pinchStartDistance = hypot(e.touches[0], e.touches[1]);
    pinchStartScale = scale;
  }
  scheduleMetricsSync();
}, { passive: true });

stage.addEventListener('touchmove', e => {
  scheduleMetricsSync();

  if (e.touches.length === 2 && pinchStartDistance > 0) {
    const d = hypot(e.touches[0], e.touches[1]);
    const next = Math.max(0.65, Math.min(4.0, pinchStartScale * d / pinchStartDistance));
    canvas.style.transformOrigin = 'center top';
    canvas.style.transform = 'scale(' + (next / scale) + ')';
  }
}, { passive: true });

stage.addEventListener('touchend', e => {
  if (pinchStartDistance > 0 && e.touches.length < 2) {
    const m = canvas.style.transform.match(/scale\(([^)]+)\)/);
    if (m) scale = Math.max(0.65, Math.min(4.0, scale * Number(m[1])));
    canvas.style.transform = '';
    pinchStartDistance = 0;
    singleTouchActive = false;
    renderPage(pageNumber, true);
    settleMetrics();
    return;
  }

  if (singleTouchActive && e.changedTouches.length > 0) {
    const touch = e.changedTouches[0];
    const dx = touch.clientX - singleTouchStartX;
    const dy = touch.clientY - singleTouchStartY;
    const verticalGesture = Math.abs(dy) > 72 && Math.abs(dy) > Math.abs(dx) * 1.15;

    const atTop = stage.scrollTop <= 3;
    const atBottom =
      stage.scrollTop + stage.clientHeight >= stage.scrollHeight - 3;
    const normalReadingScale = scale <= 1.30;
    const barelyScrolled =
      Math.abs(stage.scrollTop - singleTouchStartScrollTop) < 28;

    if (verticalGesture) {
      if (dy < 0 && (normalReadingScale || atBottom || barelyScrolled)) {
        renderPage(pageNumber + 1);
      } else if (dy > 0 && (normalReadingScale || atTop || barelyScrolled)) {
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
        pageLabel.text =
            when {
                pageCount <= 0 -> "$physical / …"
                logical != null && logical != physical.toString() ->
                    "$logical · $physical / $pageCount"
                else -> "$physical / $pageCount"
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

    private fun resetToolButtons() {
        if (::penButton.isInitialized) {
            penButton.text = "Caneta"
            penButton.alpha = 0.72f
        }
        if (::highlighterButton.isInitialized) {
            highlighterButton.text = "Marca"
            highlighterButton.alpha = 0.72f
        }
        if (::underlineButton.isInitialized) {
            underlineButton.text = "Sublinhar"
            underlineButton.alpha = 0.72f
        }
        if (::shapesButton.isInitialized) {
            shapesButton.text = "Formas"
            shapesButton.alpha = 0.72f
        }
        if (::eraserButton.isInitialized) {
            eraserButton.text = "Borracha"
            eraserButton.alpha = 0.72f
        }
    }

    private fun selectInk(kind: InkKind) {
        currentKind = kind
        currentTool =
            if (kind == InkKind.PEN) InkTool.PEN else InkTool.HIGHLIGHTER
        updateWetInkCompositing(kind)
        resetToolButtons()
        val style = currentInkStyle()

        if (kind == InkKind.PEN && ::penButton.isInitialized) {
            penButton.text = "✓ Caneta"
            penButton.alpha = 1.0f
        }
        if (kind == InkKind.HIGHLIGHTER && ::highlighterButton.isInitialized) {
            highlighterButton.text = "✓ Marca"
            highlighterButton.alpha = 1.0f
        }

        statusLabel.text =
            when (kind) {
                InkKind.PEN ->
                    "S Pen: caneta • ${style.size.roundToInt()} • segure para personalizar"
                InkKind.HIGHLIGHTER ->
                    "S Pen: marca-texto • ${style.size.roundToInt()} • segure para personalizar"
            }
    }

    private fun selectUnderline() {
        currentKind = InkKind.PEN
        currentTool = InkTool.UNDERLINE
        updateWetInkCompositing(InkKind.PEN)
        resetToolButtons()
        underlineButton.text = "✓ Sublinhar"
        underlineButton.alpha = 1.0f
        statusLabel.text =
            "S Pen: sublinhado reto • arraste sob a palavra ou trecho"
    }

    private fun selectShape(shape: ShapeTool) {
        currentKind = InkKind.PEN
        currentTool = InkTool.SHAPE
        currentShape = shape
        updateWetInkCompositing(InkKind.PEN)
        resetToolButtons()
        shapesButton.text = "✓ ${shape.label}"
        shapesButton.alpha = 1.0f
        statusLabel.text =
            "S Pen: ${shape.label.lowercase()} • arraste para definir o tamanho"
    }

    private fun showShapeToolDialog() {
        val values = ShapeTool.entries
        AlertDialog.Builder(this)
            .setTitle("Figuras geométricas")
            .setSingleChoiceItems(
                values.map { it.label }.toTypedArray(),
                currentShape.ordinal,
            ) { dialog, which ->
                selectShape(values[which])
                dialog.dismiss()
            }
            .setNegativeButton("Cancelar", null)
            .show()
    }

    private fun showEraserModeDialog() {
        val values = EraserMode.entries
        AlertDialog.Builder(this)
            .setTitle("Borracha")
            .setSingleChoiceItems(
                values.map { it.label }.toTypedArray(),
                eraserMode.ordinal,
            ) { dialog, which ->
                eraserMode = values[which]
                selectEraser()
                dialog.dismiss()
            }
            .setNegativeButton("Cancelar", null)
            .show()
    }

    private fun selectEraser() {
        currentTool = InkTool.ERASER
        wetInkView.cancelUnfinishedStrokes()
        strokeStyles.clear()
        strokeTools.clear()
        strokeShapeTools.clear()
        updateWetInkCompositing(InkKind.PEN)
        resetToolButtons()

        eraserButton.text =
            if (eraserMode == EraserMode.PARTIAL) {
                "✓ Borracha parte"
            } else {
                "✓ Borracha"
            }
        eraserButton.alpha = 1.0f
        statusLabel.text =
            if (eraserMode == EraserMode.PARTIAL) {
                "S Pen: apagar parte • recorta somente a região tocada"
            } else {
                "S Pen: borracha de traço • remove o desenho inteiro"
            }
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

    private fun syntheticStrokeFromPoints(
        template: Stroke,
        points: List<PointF>,
    ): Stroke {
        if (points.size < 2) return template

        val source = template.inputs
        val first = source[0]
        val batch = MutableStrokeInputBatch()
        points.forEachIndexed { index, point ->
            batch.add(
                type = first.toolType,
                x = point.x,
                y = point.y,
                elapsedTimeMillis = index * 6L,
                strokeUnitLengthCm = first.strokeUnitLengthCm,
                pressure = first.pressure,
                tiltRadians = first.tiltRadians,
                orientationRadians = first.orientationRadians,
            )
        }
        return Stroke(template.brush, batch)
    }

    private fun shapePoints(
        tool: InkTool,
        shape: ShapeTool,
        stroke: Stroke,
    ): List<PointF> {
        val inputs = stroke.inputs
        if (inputs.size < 2) return emptyList()

        val start = inputs[0]
        val end = inputs[inputs.size - 1]
        val x0 = start.x
        val y0 = start.y
        val x1 = end.x
        val y1 = end.y
        val dx = x1 - x0
        val dy = y1 - y0
        val distance = sqrt(dx * dx + dy * dy)
        if (distance < 2f) return emptyList()

        if (tool == InkTool.UNDERLINE) {
            val y = (y0 + y1) / 2f
            return listOf(PointF(x0, y), PointF(x1, y))
        }

        return when (shape) {
            ShapeTool.LINE -> listOf(PointF(x0, y0), PointF(x1, y1))

            ShapeTool.RECTANGLE ->
                listOf(
                    PointF(x0, y0),
                    PointF(x1, y0),
                    PointF(x1, y1),
                    PointF(x0, y1),
                    PointF(x0, y0),
                )

            ShapeTool.CIRCLE -> {
                val cx = (x0 + x1) / 2f
                val cy = (y0 + y1) / 2f
                val rx = kotlin.math.abs(x1 - x0) / 2f
                val ry = kotlin.math.abs(y1 - y0) / 2f
                val output = mutableListOf<PointF>()
                val count = 48
                for (i in 0..count) {
                    val angle = 2.0 * PI * i / count
                    output +=
                        PointF(
                            cx + (cos(angle) * rx).toFloat(),
                            cy + (sin(angle) * ry).toFloat(),
                        )
                }
                output
            }

            ShapeTool.STAR -> {
                val cx = (x0 + x1) / 2f
                val cy = (y0 + y1) / 2f
                val rx = kotlin.math.abs(x1 - x0) / 2f
                val ry = kotlin.math.abs(y1 - y0) / 2f
                val output = mutableListOf<PointF>()
                for (i in 0..10) {
                    val vertex = i % 10
                    val outer = vertex % 2 == 0
                    val radiusScale = if (outer) 1f else 0.42f
                    val angle = -PI / 2.0 + vertex * PI / 5.0
                    output +=
                        PointF(
                            cx + (cos(angle) * rx * radiusScale).toFloat(),
                            cy + (sin(angle) * ry * radiusScale).toFloat(),
                        )
                }
                output
            }

            ShapeTool.ARROW -> {
                val ux = dx / distance
                val uy = dy / distance
                val px = -uy
                val py = ux
                val headLength = kotlin.math.min(34f, kotlin.math.max(12f, distance * 0.24f))
                val headWidth = headLength * 0.55f
                val baseX = x1 - ux * headLength
                val baseY = y1 - uy * headLength
                val left = PointF(baseX + px * headWidth, baseY + py * headWidth)
                val right = PointF(baseX - px * headWidth, baseY - py * headWidth)
                listOf(
                    PointF(x0, y0),
                    PointF(x1, y1),
                    left,
                    PointF(x1, y1),
                    right,
                )
            }
        }
    }

    private fun snapFinishedStroke(
        tool: InkTool,
        shape: ShapeTool,
        stroke: Stroke,
    ): Stroke {
        if (tool != InkTool.UNDERLINE && tool != InkTool.SHAPE) return stroke
        val points = shapePoints(tool, shape, stroke)
        return if (points.size >= 2) syntheticStrokeFromPoints(stroke, points) else stroke
    }

    private fun sampledPointsForPartialErase(
        stroke: Stroke,
        sampleStep: Float,
    ): List<PointF> {
        val inputs = stroke.inputs
        if (inputs.size == 0) return emptyList()
        if (inputs.size == 1) return listOf(PointF(inputs[0].x, inputs[0].y))

        val output = mutableListOf<PointF>()
        output += PointF(inputs[0].x, inputs[0].y)

        for (index in 1 until inputs.size) {
            val a = inputs[index - 1]
            val b = inputs[index]
            val dx = b.x - a.x
            val dy = b.y - a.y
            val distance = sqrt(dx * dx + dy * dy)
            val steps = ceil(distance / sampleStep.coerceAtLeast(1f)).toInt().coerceAtLeast(1)
            for (step in 1..steps) {
                val t = step.toFloat() / steps.toFloat()
                output += PointF(a.x + dx * t, a.y + dy * t)
            }
        }
        return output
    }

    private fun partialEraseEntry(
        entry: InkEntry,
        pageX: Float,
        pageY: Float,
        radius: Float,
    ): List<InkEntry> {
        val effectiveRadius = radius + entry.style.size * 0.35f
        val radiusSquared = effectiveRadius * effectiveRadius
        val sampled =
            sampledPointsForPartialErase(
                entry.stroke,
                kotlin.math.max(1.5f, effectiveRadius * 0.28f),
            )
        if (sampled.size < 2) return emptyList()

        val groups = mutableListOf<MutableList<PointF>>()
        var current = mutableListOf<PointF>()

        fun flush() {
            if (current.size >= 2) groups += current
            current = mutableListOf()
        }

        sampled.forEach { point ->
            val dx = point.x - pageX
            val dy = point.y - pageY
            val erased = dx * dx + dy * dy <= radiusSquared
            if (erased) {
                flush()
            } else {
                current += point
            }
        }
        flush()

        return groups.map { points ->
            InkEntry(
                entry.style,
                syntheticStrokeFromPoints(entry.stroke, points),
            )
        }
    }

    private fun eraseAt(event: MotionEvent): Boolean {
        if (currentEntries.isEmpty()) return false
        val point = eventPointInPage(event)
        val radius = eraserRadiusInPage()

        for (index in currentEntries.indices.reversed()) {
            val entry = currentEntries[index]
            if (!strokeIntersectsEraser(entry, point[0], point[1], radius)) continue

            if (eraserMode == EraserMode.WHOLE_STROKE) {
                if (entry in erasedThisGesture) continue
                currentEntries.removeAt(index)
                erasedThisGesture += entry
                undoHistory.addLast(InkHistoryAction.Removed(index, entry))
            } else {
                val replacements =
                    partialEraseEntry(entry, point[0], point[1], radius)
                currentEntries.removeAt(index)
                if (replacements.isNotEmpty()) {
                    currentEntries.addAll(index, replacements)
                }
                undoHistory.addLast(
                    InkHistoryAction.Replaced(
                        index = index,
                        original = entry,
                        replacements = replacements,
                    ),
                )
            }

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
                strokeTools[strokeId] = currentTool
                strokeShapeTools[strokeId] = currentShape
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
                strokeTools.clear()
                strokeShapeTools.clear()
                true
            }

            else -> true
        }
    }

    override fun onStrokesFinished(strokes: Map<InProgressStrokeId, Stroke>) {
        strokes.forEach { (id, rawStroke) ->
            val style = strokeStyles.remove(id) ?: currentInkStyle()
            val tool = strokeTools.remove(id) ?: currentTool
            val shape = strokeShapeTools.remove(id) ?: currentShape
            val stroke = snapFinishedStroke(tool, shape, rawStroke)
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

            is InkHistoryAction.Replaced -> {
                action.replacements.forEach { currentEntries.remove(it) }
                val targetIndex = action.index.coerceIn(0, currentEntries.size)
                currentEntries.add(targetIndex, action.original)
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

            is InkHistoryAction.Replaced -> {
                currentEntries.remove(action.original)
                val targetIndex = action.index.coerceIn(0, currentEntries.size)
                if (action.replacements.isNotEmpty()) {
                    currentEntries.addAll(targetIndex, action.replacements)
                }
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
        strokeStyles.clear()
        strokeTools.clear()
        strokeShapeTools.clear()
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

    override fun onDestroy() {
        PdfCrashDiagnostics.mark(this, "JSZ_ON_DESTROY")
        try {
            persistInkForPage(currentPageIndex)
        } catch (_: Throwable) {
        }
        try {
            wetInkView.clearFinishedStrokesListeners()
        } catch (_: Throwable) {
        }
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

    private class StylusRouterLayout(context: Context) : FrameLayout(context) {
        var onStylusEvent: ((MotionEvent) -> Boolean)? = null

        override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
            if (ev.pointerCount <= 0) return false
            val type = ev.getToolType(ev.actionIndex.coerceAtLeast(0))
            return type == MotionEvent.TOOL_TYPE_STYLUS ||
                type == MotionEvent.TOOL_TYPE_ERASER
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