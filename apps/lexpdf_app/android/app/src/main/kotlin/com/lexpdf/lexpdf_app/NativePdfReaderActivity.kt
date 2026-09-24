package com.lexpdf.lexpdf_app

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.util.Base64
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
        val depth: Int,
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
    private lateinit var dryInkView: DryInkView
    private lateinit var wetInkView: InProgressStrokesView
    private lateinit var pageLabel: TextView
    private lateinit var statusLabel: TextView
    private lateinit var penButton: Button
    private lateinit var highlighterButton: Button
    private lateinit var readerFrame: StylusRouterLayout

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var currentPageIndex = 0
    private var pageCount = 0
    private var pageMetrics: PageMetrics? = null

    private var currentKind = InkKind.PEN
    private var penColor = Color.rgb(20, 24, 30)
    private var penSize = 3.0f
    private var highlighterColor = Color.argb(92, 255, 224, 64)
    private var highlighterSize = 18f
    private val currentEntries = mutableListOf<InkEntry>()
    private val redoEntries = ArrayDeque<InkEntry>()
    private val strokeStyles = mutableMapOf<InProgressStrokeId, InkStyle>()
    private val outlineEntries = mutableListOf<OutlineEntry>()
    private var outlineLoaded = false

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
                minWidth = 0
                setPadding(10.dp, 0, 10.dp, 0)
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
        inkRow.addView(penButton)
        inkRow.addView(highlighterButton)
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

        dryInkView = DryInkView(this) { pageToViewMatrix() }
        readerFrame.addView(
            dryInkView,
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
                            depth = item.optInt("depth").coerceIn(0, 8),
                        )
                }
            } catch (_: Throwable) {
                parsed.clear()
            }

            runOnUiThread {
                outlineEntries.clear()
                outlineEntries += parsed
                outlineLoaded = true
                PdfCrashDiagnostics.mark(
                    this@NativePdfReaderActivity,
                    "JS07_OUTLINE_READY",
                    "entries=${parsed.size}",
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
                    redoEntries.clear()
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
                        dryInkView.invalidate()
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
    depth
  });

  for (const child of (item.items || [])) {
    if (output.length >= 2000) break;
    await resolveOutlineItem(child, depth + 1, output);
  }
}

async function loadOutline() {
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
  LexPdfBridge.metrics(JSON.stringify({
    page: pageNumber,
    pageWidth: pageAtScaleOne.width,
    pageHeight: pageAtScaleOne.height,
    left: r.left,
    top: r.top,
    width: r.width,
    height: r.height
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
    void loadOutline();
    await renderPage(pageNumber);
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

    private fun updatePageLabel() {
        pageLabel.text =
            if (pageCount > 0) "${currentPageIndex + 1} / $pageCount"
            else "${currentPageIndex + 1} / …"
    }

    private fun showPageJumpDialog() {
        if (pageCount <= 0) {
            Toast.makeText(this, "Aguarde o PDF terminar de abrir.", Toast.LENGTH_SHORT).show()
            return
        }

        val input =
            EditText(this).apply {
                inputType = InputType.TYPE_CLASS_NUMBER
                setText((currentPageIndex + 1).toString())
                selectAll()
                setPadding(24.dp, 12.dp, 24.dp, 12.dp)
            }

        AlertDialog.Builder(this)
            .setTitle("Ir para página")
            .setMessage("Digite uma página entre 1 e $pageCount.")
            .setView(input)
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Ir") { _, _ ->
                val requested = input.text?.toString()?.trim()?.toIntOrNull()
                if (requested == null || requested !in 1..pageCount) {
                    Toast.makeText(
                        this,
                        "Página inválida. Use um número entre 1 e $pageCount.",
                        Toast.LENGTH_LONG,
                    ).show()
                } else {
                    js("LexPDF.goToPage($requested)")
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
                    "Este PDF não possui sumário/bookmarks internos. " +
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
                    val suffix = entry.page?.let { "  ·  p. $it" } ?: ""
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
        penSize = prefs.getFloat(PREF_PEN_SIZE, 3.0f).coerceIn(1f, 12f)
        highlighterColor =
            prefs.getInt(PREF_HIGHLIGHT_COLOR, Color.argb(92, 255, 224, 64))
        highlighterSize =
            prefs.getFloat(PREF_HIGHLIGHT_SIZE, 18f).coerceIn(8f, 32f)
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
                    Color.rgb(20, 24, 30),
                    Color.rgb(25, 92, 190),
                    Color.rgb(210, 45, 45),
                    Color.rgb(25, 135, 75),
                    Color.rgb(125, 65, 180),
                    Color.rgb(120, 75, 45),
                )
            } else {
                intArrayOf(
                    Color.argb(92, 255, 224, 64),
                    Color.argb(92, 115, 225, 120),
                    Color.argb(92, 75, 200, 235),
                    Color.argb(92, 245, 105, 175),
                    Color.argb(92, 255, 155, 70),
                    Color.argb(92, 175, 120, 235),
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

        val minSize = if (kind == InkKind.PEN) 1 else 8
        val maxSize = if (kind == InkKind.PEN) 12 else 32
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
                    highlighterColor = selectedColor
                    highlighterSize = selectedSize
                }
                saveInkPreferences()
                selectInk(kind)
            }
            .show()
    }

    private fun selectInk(kind: InkKind) {
        currentKind = kind
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

        statusLabel.text =
            when (kind) {
                InkKind.PEN ->
                    "S Pen: caneta • ${style.size.roundToInt()} • segure para personalizar"
                InkKind.HIGHLIGHTER ->
                    "S Pen: marca-texto • ${style.size.roundToInt()} • segure para personalizar"
            }
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

    private fun handleStylusEvent(event: MotionEvent): Boolean {
        val metrics = pageMetrics ?: return false
        if (metrics.pageIndex != currentPageIndex) return false
        val pointerId = event.getPointerId(event.actionIndex.coerceAtLeast(0))

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
                        pageToViewMatrix(),
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
            currentEntries += InkEntry(style, stroke)
        }
        redoEntries.clear()
        dryInkView.setEntries(currentEntries)
        wetInkView.removeFinishedStrokes(strokes.keys)
        persistInkForPage(currentPageIndex)
    }

    private fun undoInk() {
        val entry = currentEntries.removeLastOrNull() ?: return
        redoEntries.addLast(entry)
        dryInkView.setEntries(currentEntries)
        persistInkForPage(currentPageIndex)
    }

    private fun redoInk() {
        if (redoEntries.isEmpty()) return
        val entry = redoEntries.removeLast()
        currentEntries += entry
        dryInkView.setEntries(currentEntries)
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
        dryInkView.setEntries(emptyList())
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
                                InkStyle(
                                    kind = kind,
                                    colorArgb = input.readInt(),
                                    size =
                                        input
                                            .readFloat()
                                            .coerceIn(
                                                if (kind == InkKind.PEN) 1f else 8f,
                                                if (kind == InkKind.PEN) 12f else 32f,
                                            ),
                                )
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
                                        Color.argb(92, 255, 224, 64),
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
                dryInkView.setEntries(currentEntries)
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
    ) : View(context) {
        private val entries = mutableListOf<InkEntry>()
        private val renderer =
            ViewStrokeRenderer(
                CanvasStrokeRenderer.create(),
                this,
            )

        init {
            setWillNotDraw(false)
        }

        fun setEntries(values: List<InkEntry>) {
            entries.clear()
            entries.addAll(values)
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