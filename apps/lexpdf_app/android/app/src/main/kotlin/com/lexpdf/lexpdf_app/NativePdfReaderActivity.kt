package com.lexpdf.lexpdf_app

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.os.Build
import android.os.Bundle
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
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
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
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.io.RandomAccessFile
import java.util.ArrayDeque
import java.util.concurrent.Executors
import kotlin.math.hypot
import kotlin.math.roundToInt

/**
 * LexPDF Android reader based on Mozilla PDF.js inside the system WebView.
 *
 * The PDF itself is never copied into JavaScript memory by Android code.
 * shouldInterceptRequest streams the local file and honors HTTP byte ranges,
 * allowing PDF.js to request document chunks on demand. AndroidX Ink remains
 * native and independent from the renderer so S Pen input does not depend on
 * any PDF SDK.
 */
class NativePdfReaderActivity : AppCompatActivity(), InProgressStrokesFinishedListener {
    companion object {
        const val EXTRA_PATH = "lexpdf.native_reader.path"
        const val EXTRA_INITIAL_PAGE = "lexpdf.native_reader.initial_page"

        private const val LOCAL_ORIGIN = "https://lexpdf.local"
        private const val VIEWER_URL = "$LOCAL_ORIGIN/viewer.html"
        private const val PDF_URL = "$LOCAL_ORIGIN/document.pdf"
        private const val PDFJS_VERSION = "6.3.289"
        private const val SIDECAR_VERSION = 2
        @Volatile
        private var webViewDirectoryConfigured = false
    }

    private enum class InkKind { PEN, HIGHLIGHTER }

    private data class InkEntry(
        val kind: InkKind,
        val stroke: Stroke,
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
    private lateinit var webView: WebView
    private lateinit var dryInkView: DryInkView
    private lateinit var wetInkView: InProgressStrokesView
    private lateinit var pageLabel: TextView
    private lateinit var statusLabel: TextView
    private lateinit var readerFrame: StylusRouterLayout

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var currentPageIndex = 0
    private var pageCount = 0
    private var pageMetrics: PageMetrics? = null

    private var currentKind = InkKind.PEN
    private val currentEntries = mutableListOf<InkEntry>()
    private val redoEntries = ArrayDeque<InkEntry>()
    private val strokeKinds = mutableMapOf<InProgressStrokeId, InkKind>()

    private val penBrush: Brush by lazy {
        Brush.createWithColorIntArgb(
            StockBrushes.pressurePen(),
            Color.rgb(20, 24, 30),
            3.0f,
            0.1f,
        )
    }

    private val highlighterBrush: Brush by lazy {
        Brush.createWithColorIntArgb(
            StockBrushes.highlighter(),
            Color.argb(92, 255, 224, 64),
            18f,
            0.2f,
        )
    }

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

        val toolbar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(6.dp, 4.dp, 6.dp, 4.dp)
            setBackgroundColor(Color.rgb(242, 244, 247))
        }

        fun button(label: String, onClick: () -> Unit): Button {
            return Button(this).apply {
                text = label
                isAllCaps = false
                minWidth = 0
                setPadding(10.dp, 0, 10.dp, 0)
                setOnClickListener { onClick() }
            }
        }

        toolbar.addView(button("‹") { js("LexPDF.previousPage()") })

        pageLabel = TextView(this).apply {
            gravity = Gravity.CENTER
            textSize = 14f
            setTextColor(Color.rgb(30, 33, 38))
            text = "…"
        }
        toolbar.addView(
            pageLabel,
            LinearLayout.LayoutParams(96.dp, LinearLayout.LayoutParams.WRAP_CONTENT),
        )

        toolbar.addView(button("›") { js("LexPDF.nextPage()") })
        toolbar.addView(button("−") { js("LexPDF.zoomOut()") })
        toolbar.addView(button("+") { js("LexPDF.zoomIn()") })
        toolbar.addView(button("Caneta") { selectInk(InkKind.PEN) })
        toolbar.addView(button("Marca") { selectInk(InkKind.HIGHLIGHTER) })
        toolbar.addView(button("Desfazer") { undoInk() })
        toolbar.addView(button("Refazer") { redoInk() })
        toolbar.addView(button("Fechar") { finish() })

        statusLabel = TextView(this).apply {
            textSize = 12f
            setTextColor(Color.rgb(65, 68, 74))
            setPadding(8.dp, 0, 6.dp, 0)
            text = "PDF.js iniciando…"
        }
        toolbar.addView(
            statusLabel,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )

        root.addView(
            toolbar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                54.dp,
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
                        PDF_URL -> pdfResponse(request)
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

    private fun pdfResponse(request: WebResourceRequest): WebResourceResponse {
        val fileLength = sourceFile.length()
        val range = request.requestHeaders["Range"] ?: request.requestHeaders["range"]

        if (range != null && range.startsWith("bytes=")) {
            val raw = range.removePrefix("bytes=").substringBefore(",")
            val parts = raw.split("-", limit = 2)
            val start = parts.getOrNull(0)?.toLongOrNull()?.coerceIn(0L, fileLength - 1)
                ?: 0L
            val requestedEnd = parts.getOrNull(1)?.toLongOrNull()
            val end =
                (requestedEnd ?: (start + 1024L * 1024L - 1L))
                    .coerceIn(start, fileLength - 1)
            val length = end - start + 1

            PdfCrashDiagnostics.mark(
                this,
                "JSR_RANGE",
                "start=$start end=$end len=$length",
            )

            return WebResourceResponse(
                "application/pdf",
                null,
                206,
                "Partial Content",
                mapOf(
                    "Accept-Ranges" to "bytes",
                    "Content-Range" to "bytes $start-$end/$fileLength",
                    "Content-Length" to length.toString(),
                    "Cache-Control" to "no-store",
                ),
                RangeFileInputStream(sourceFile, start, length),
            )
        }

        PdfCrashDiagnostics.mark(this, "JSR_FULL_STREAM", "len=$fileLength")
        return WebResourceResponse(
            "application/pdf",
            null,
            200,
            "OK",
            mapOf(
                "Accept-Ranges" to "bytes",
                "Content-Length" to fileLength.toString(),
                "Cache-Control" to "no-store",
            ),
            FileInputStream(sourceFile),
        )
    }

    private inner class JsBridge {
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

const PDF_URL = '${PDF_URL}';
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
    pageNumber = target;
    page.cleanup();
    loading.style.display = 'none';
    requestAnimationFrame(() => {
      reportMetrics();
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

stage.addEventListener('scroll', () => requestAnimationFrame(reportMetrics), { passive: true });
window.addEventListener('resize', () => requestAnimationFrame(reportMetrics));

stage.addEventListener('touchstart', e => {
  if (e.touches.length === 2) {
    pinchStartDistance = hypot(e.touches[0], e.touches[1]);
    pinchStartScale = scale;
  }
}, { passive: true });

stage.addEventListener('touchmove', e => {
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
    renderPage(pageNumber, true);
  }
}, { passive: true });

function hypot(a,b) {
  return Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
}

(async () => {
  try {
    const task = pdfjsLib.getDocument({
      url: PDF_URL,
      rangeChunkSize: 131072,
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

    private fun selectInk(kind: InkKind) {
        currentKind = kind
        statusLabel.text =
            when (kind) {
                InkKind.PEN -> "S Pen: caneta • dedo: PDF.js"
                InkKind.HIGHLIGHTER -> "S Pen: marca-texto • dedo: PDF.js"
            }
    }

    private fun currentBrush(): Brush =
        when (currentKind) {
            InkKind.PEN -> penBrush
            InkKind.HIGHLIGHTER -> highlighterBrush
        }

    private fun handleStylusEvent(event: MotionEvent): Boolean {
        val metrics = pageMetrics ?: return false
        if (metrics.pageIndex != currentPageIndex) return false
        val pointerId = event.getPointerId(event.actionIndex.coerceAtLeast(0))

        return when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                readerFrame.requestUnbufferedDispatch(event)
                val strokeId =
                    wetInkView.startStroke(
                        event,
                        pointerId,
                        currentBrush(),
                        viewToPageMatrix(),
                        Matrix(),
                    )
                strokeKinds[strokeId] = currentKind
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
                strokeKinds.clear()
                true
            }

            else -> true
        }
    }

    override fun onStrokesFinished(strokes: Map<InProgressStrokeId, Stroke>) {
        strokes.forEach { (id, stroke) ->
            currentEntries += InkEntry(strokeKinds.remove(id) ?: currentKind, stroke)
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
                        output.writeInt(entry.kind.ordinal)
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
                    require(input.readInt() == SIDECAR_VERSION)
                    val count = input.readInt().coerceIn(0, 50_000)
                    repeat(count) {
                        val kind =
                            InkKind.entries.getOrElse(input.readInt()) { InkKind.PEN }
                        val length = input.readInt().coerceIn(0, 16 * 1024 * 1024)
                        val bytes = ByteArray(length)
                        input.readFully(bytes)
                        val batch =
                            StrokeInputBatch.decode(ByteArrayInputStream(bytes))
                        val brush =
                            if (kind == InkKind.PEN) penBrush else highlighterBrush
                        loaded += InkEntry(kind, Stroke(brush, batch))
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

    private class RangeFileInputStream(
        file: File,
        start: Long,
        private var remaining: Long,
    ) : InputStream() {
        private val raf = RandomAccessFile(file, "r").apply { seek(start) }

        override fun read(): Int {
            if (remaining <= 0) return -1
            val value = raf.read()
            if (value >= 0) remaining--
            return value
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (remaining <= 0) return -1
            val maxRead = minOf(length.toLong(), remaining).toInt()
            val count = raf.read(buffer, offset, maxRead)
            if (count > 0) remaining -= count.toLong()
            return count
        }

        override fun close() {
            raf.close()
        }
    }
}
