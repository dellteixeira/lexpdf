package com.lexpdf.lexpdf_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.view.Gravity
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
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
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.util.ArrayDeque
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * LexPDF Android reader built only on platform PdfRenderer + stable AndroidX Ink.
 *
 * Design goals:
 * - no Flutter PDF widget and no PDFium initialization on Android;
 * - no commercial SDK, license key or evaluation watermark;
 * - one PdfRenderer.Page opened at a time;
 * - one screen-sized bitmap at a time with a hard pixel budget;
 * - S Pen authors in page coordinates while fingers pan/zoom;
 * - finished strokes persist to a compact per-page LexPDF sidecar.
 */
class NativePdfReaderActivity : AppCompatActivity(), InProgressStrokesFinishedListener {
    companion object {
        const val EXTRA_PATH = "lexpdf.native_reader.path"
        const val EXTRA_INITIAL_PAGE = "lexpdf.native_reader.initial_page"

        private const val MAX_RENDER_PIXELS = 8_000_000L
        private const val SIDECAR_VERSION = 1
    }

    private enum class InkKind { PEN, HIGHLIGHTER }

    private data class InkEntry(
        val kind: InkKind,
        val stroke: Stroke,
    )

    private lateinit var sourceFile: File
    private lateinit var descriptor: ParcelFileDescriptor
    private lateinit var renderer: PdfRenderer

    private lateinit var surface: PdfSurfaceView
    private lateinit var dryInkView: DryInkView
    private lateinit var wetInkView: InProgressStrokesView
    private lateinit var pageLabel: TextView
    private lateinit var statusLabel: TextView

    private val renderExecutor = Executors.newSingleThreadExecutor()
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var currentPageIndex = 0
    private var renderGeneration = 0
    private var currentKind = InkKind.PEN
    private val currentEntries = mutableListOf<InkEntry>()
    private val redoEntries = ArrayDeque<InkEntry>()
    private val strokeKinds = mutableMapOf<InProgressStrokeId, InkKind>()

    private val penBrush: Brush by lazy {
        Brush.createWithColorIntArgb(
            StockBrushes.pressurePen(),
            Color.rgb(20, 24, 30),
            3.2f,
            0.1f,
        )
    }

    private val highlighterBrush: Brush by lazy {
        Brush.createWithColorIntArgb(
            StockBrushes.highlighter(),
            Color.argb(95, 255, 224, 64),
            18f,
            0.2f,
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PdfCrashDiagnostics.mark(this, "A01_ACTIVITY_CREATED")

        val path = intent.getStringExtra(EXTRA_PATH)
        if (path.isNullOrBlank()) {
            finish()
            return
        }
        sourceFile = File(path)
        PdfCrashDiagnostics.mark(
            this,
            "A02_SOURCE_RESOLVED",
            "size=${sourceFile.length()} pathHash=${sourceFile.absolutePath.hashCode()}",
        )
        if (!sourceFile.isFile || sourceFile.length() <= 0L) {
            Toast.makeText(this, "PDF indisponível.", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        try {
            PdfCrashDiagnostics.mark(this, "A03_BEFORE_PFD_OPEN")
            descriptor =
                ParcelFileDescriptor.open(sourceFile, ParcelFileDescriptor.MODE_READ_ONLY)
            PdfCrashDiagnostics.mark(this, "A04_AFTER_PFD_OPEN")
            PdfCrashDiagnostics.mark(this, "A05_BEFORE_PDFRENDERER_CTOR")
            renderer = PdfRenderer(descriptor)
            PdfCrashDiagnostics.mark(
                this,
                "A06_AFTER_PDFRENDERER_CTOR",
                "pages=${renderer.pageCount}",
            )
        } catch (error: Throwable) {
            Toast.makeText(
                this,
                "Não foi possível abrir o PDF: ${error.message}",
                Toast.LENGTH_LONG,
            ).show()
            finish()
            return
        }

        currentPageIndex =
            (intent.getIntExtra(EXTRA_INITIAL_PAGE, 1) - 1)
                .coerceIn(0, max(0, renderer.pageCount - 1))

        PdfCrashDiagnostics.mark(this, "A07_BEFORE_UI_BUILD")
        buildUi()
        PdfCrashDiagnostics.mark(this, "A08_AFTER_UI_BUILD")
        loadInkForPage(currentPageIndex)
        PdfCrashDiagnostics.mark(this, "A09_AFTER_INK_LOAD_REQUEST")
        surface.post {
            PdfCrashDiagnostics.mark(this, "A10_SURFACE_POST_READY")
            renderPage(currentPageIndex)
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

        fun toolbarButton(label: String, onClick: () -> Unit): Button {
            return Button(this).apply {
                text = label
                isAllCaps = false
                minWidth = 0
                setPadding(12.dp, 0, 12.dp, 0)
                setOnClickListener { onClick() }
            }
        }

        toolbar.addView(toolbarButton("‹") { changePage(-1) })

        pageLabel = TextView(this).apply {
            gravity = Gravity.CENTER
            textSize = 14f
            setTextColor(Color.rgb(30, 33, 38))
        }
        toolbar.addView(
            pageLabel,
            LinearLayout.LayoutParams(92.dp, LinearLayout.LayoutParams.WRAP_CONTENT),
        )

        toolbar.addView(toolbarButton("›") { changePage(1) })
        toolbar.addView(toolbarButton("Caneta") { selectInk(InkKind.PEN) })
        toolbar.addView(toolbarButton("Marca") { selectInk(InkKind.HIGHLIGHTER) })
        toolbar.addView(toolbarButton("Desfazer") { undoInk() })
        toolbar.addView(toolbarButton("Refazer") { redoInk() })
        toolbar.addView(toolbarButton("Ajustar") {
            surface.resetTransform()
        })
        toolbar.addView(toolbarButton("Fechar") { finish() })

        statusLabel = TextView(this).apply {
            textSize = 12f
            setTextColor(Color.rgb(60, 65, 72))
            setPadding(10.dp, 0, 8.dp, 0)
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

        val readerFrame = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(32, 34, 39))
        }

        surface = PdfSurfaceView(this).apply {
            onTransformChanged = {
                dryInkView.invalidate()
            }
            onStylusEvent = { event ->
                handleStylusEvent(event)
            }
        }
        readerFrame.addView(
            surface,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        dryInkView = DryInkView(this) { surface.pageToViewMatrix() }
        readerFrame.addView(
            dryInkView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        PdfCrashDiagnostics.mark(this, "UI01_BEFORE_INK_VIEW")
        wetInkView = InProgressStrokesView(this).apply {
            isClickable = false
            isFocusable = false
            addFinishedStrokesListener(this@NativePdfReaderActivity)
            eagerInit()
        }
        PdfCrashDiagnostics.mark(this, "UI02_AFTER_INK_VIEW_EAGER_INIT")
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
        updateToolbarState()
    }

    private fun selectInk(kind: InkKind) {
        currentKind = kind
        statusLabel.text =
            when (kind) {
                InkKind.PEN -> "S Pen: caneta • dedo: mover/zoom"
                InkKind.HIGHLIGHTER -> "S Pen: marca-texto • dedo: mover/zoom"
            }
    }

    private fun currentBrush(): Brush =
        when (currentKind) {
            InkKind.PEN -> penBrush
            InkKind.HIGHLIGHTER -> highlighterBrush
        }

    private fun handleStylusEvent(event: MotionEvent): Boolean {
        if (event.pointerCount <= 0) return false
        val index = event.actionIndex.coerceAtLeast(0)
        val pointerId = event.getPointerId(index)

        return when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                surface.requestUnbufferedDispatch(event)
                val world = surface.viewToPageMatrix()
                val strokeId =
                    wetInkView.startStroke(
                        event,
                        pointerId,
                        currentBrush(),
                        world,
                        Matrix(),
                    )
                strokeKinds[strokeId] = currentKind
                true
            }

            MotionEvent.ACTION_MOVE -> {
                for (pointerIndex in 0 until event.pointerCount) {
                    wetInkView.addToStroke(
                        event,
                        event.getPointerId(pointerIndex),
                    )
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
        updateToolbarState()
    }

    private fun undoInk() {
        val entry = currentEntries.removeLastOrNull() ?: return
        redoEntries.addLast(entry)
        dryInkView.setEntries(currentEntries)
        persistInkForPage(currentPageIndex)
        updateToolbarState()
    }

    private fun redoInk() {
        if (redoEntries.isEmpty()) return
        val entry = redoEntries.removeLast()
        currentEntries += entry
        dryInkView.setEntries(currentEntries)
        persistInkForPage(currentPageIndex)
        updateToolbarState()
    }

    private fun changePage(delta: Int) {
        val next = (currentPageIndex + delta).coerceIn(0, renderer.pageCount - 1)
        if (next == currentPageIndex) return

        wetInkView.cancelUnfinishedStrokes()
        strokeKinds.clear()
        persistInkForPage(currentPageIndex)

        currentPageIndex = next
        redoEntries.clear()
        surface.resetTransform()
        loadInkForPage(next)
        renderPage(next)
        updateToolbarState()
    }

    private fun updateToolbarState() {
        pageLabel.text = "${currentPageIndex + 1} / ${renderer.pageCount}"
        if (statusLabel.text.isNullOrBlank()) {
            statusLabel.text = "PdfRenderer nativo • AndroidX Ink • sem SDK comercial"
        }
    }

    private fun renderPage(pageIndex: Int) {
        PdfCrashDiagnostics.mark(this, "R01_RENDER_REQUEST", "page=${pageIndex + 1}")
        val generation = ++renderGeneration
        statusLabel.text = "Renderizando página ${pageIndex + 1}…"

        val viewportWidth = max(surface.width, resources.displayMetrics.widthPixels)
        val viewportHeight =
            max(
                surface.height,
                resources.displayMetrics.heightPixels - 80.dp,
            )

        renderExecutor.execute {
            var rendered: Bitmap? = null
            var pageWidth = 1
            var pageHeight = 1
            var error: Throwable? = null

            try {
                PdfCrashDiagnostics.mark(
                    this,
                    "R02_BEFORE_OPEN_PAGE",
                    "page=${pageIndex + 1}",
                )
                renderer.openPage(pageIndex).use { page ->
                    PdfCrashDiagnostics.mark(
                        this,
                        "R03_AFTER_OPEN_PAGE",
                        "page=${pageIndex + 1}",
                    )
                    pageWidth = page.width
                    pageHeight = page.height

                    val fit =
                        min(
                            viewportWidth.toFloat() / pageWidth.toFloat(),
                            viewportHeight.toFloat() / pageHeight.toFloat(),
                        ).coerceAtLeast(0.25f)

                    var bitmapWidth = max(1, (pageWidth * fit).roundToInt())
                    var bitmapHeight = max(1, (pageHeight * fit).roundToInt())

                    val pixels = bitmapWidth.toLong() * bitmapHeight.toLong()
                    if (pixels > MAX_RENDER_PIXELS) {
                        val factor =
                            kotlin.math.sqrt(
                                MAX_RENDER_PIXELS.toDouble() / pixels.toDouble(),
                            ).toFloat()
                        bitmapWidth = max(1, (bitmapWidth * factor).roundToInt())
                        bitmapHeight = max(1, (bitmapHeight * factor).roundToInt())
                    }

                    PdfCrashDiagnostics.mark(
                        this,
                        "R04_BEFORE_BITMAP",
                        "page=${pageIndex + 1} w=$bitmapWidth h=$bitmapHeight",
                    )
                    rendered =
                        Bitmap.createBitmap(
                            bitmapWidth,
                            bitmapHeight,
                            Bitmap.Config.ARGB_8888,
                        ).apply {
                            eraseColor(Color.WHITE)
                        }

                    val renderMatrix = Matrix().apply {
                        setScale(
                            bitmapWidth.toFloat() / pageWidth.toFloat(),
                            bitmapHeight.toFloat() / pageHeight.toFloat(),
                        )
                    }

                    PdfCrashDiagnostics.mark(
                        this,
                        "R05_BEFORE_PAGE_RENDER",
                        "page=${pageIndex + 1}",
                    )
                    page.render(
                        rendered!!,
                        null,
                        renderMatrix,
                        PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY,
                    )
                    PdfCrashDiagnostics.mark(
                        this,
                        "R06_AFTER_PAGE_RENDER",
                        "page=${pageIndex + 1}",
                    )
                }
            } catch (t: Throwable) {
                error = t
            }

            mainHandler.post {
                if (generation != renderGeneration || isFinishing) {
                    rendered?.recycle()
                    return@post
                }

                if (error != null || rendered == null) {
                    statusLabel.text = "Falha ao renderizar: ${error?.message ?: "erro"}"
                    Toast.makeText(
                        this,
                        "Falha ao renderizar esta página.",
                        Toast.LENGTH_LONG,
                    ).show()
                    return@post
                }

                PdfCrashDiagnostics.mark(
                    this,
                    "R07_BEFORE_SURFACE_SET",
                    "page=${pageIndex + 1}",
                )
                surface.setPage(rendered!!, pageWidth.toFloat(), pageHeight.toFloat())
                dryInkView.invalidate()
                PdfCrashDiagnostics.mark(
                    this,
                    "R08_PAGE_VISIBLE",
                    "page=${pageIndex + 1}",
                )
                statusLabel.text =
                    "PdfRenderer • ${rendered!!.width}×${rendered!!.height} • " +
                        "S Pen: ${currentEntries.size} traço(s)"
            }
        }
    }

    private fun sidecarFile(pageIndex: Int): File {
        val documentKey = sourceFile.absolutePath.hashCode().toUInt().toString(16)
        val directory =
            File(filesDir, "native_ink/$documentKey").apply {
                mkdirs()
            }
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

            val temporary = File(target.parentFile, "${target.name}.tmp")
            try {
                DataOutputStream(temporary.outputStream().buffered()).use { output ->
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
                if (!temporary.renameTo(target)) {
                    temporary.copyTo(target, overwrite = true)
                    temporary.delete()
                }
            } catch (_: Throwable) {
                temporary.delete()
            }
        }
    }

    private fun loadInkForPage(pageIndex: Int) {
        currentEntries.clear()
        dryInkView.setEntries(emptyList())
        val source = sidecarFile(pageIndex)
        if (!source.isFile) {
            updateToolbarState()
            return
        }

        ioExecutor.execute {
            val loaded = mutableListOf<InkEntry>()
            try {
                DataInputStream(source.inputStream().buffered()).use { input ->
                    val version = input.readInt()
                    require(version == SIDECAR_VERSION)
                    val count = input.readInt().coerceIn(0, 50_000)
                    repeat(count) {
                        val kindOrdinal = input.readInt()
                        val kind = InkKind.entries.getOrElse(kindOrdinal) { InkKind.PEN }
                        val length = input.readInt().coerceIn(0, 16 * 1024 * 1024)
                        val bytes = ByteArray(length)
                        input.readFully(bytes)
                        val batch =
                            StrokeInputBatch.decode(ByteArrayInputStream(bytes))
                        val brush =
                            when (kind) {
                                InkKind.PEN -> penBrush
                                InkKind.HIGHLIGHTER -> highlighterBrush
                            }
                        loaded += InkEntry(kind, Stroke(brush, batch))
                    }
                }
            } catch (_: Throwable) {
                loaded.clear()
            }

            mainHandler.post {
                if (pageIndex != currentPageIndex || isFinishing) return@post
                currentEntries.clear()
                currentEntries += loaded
                dryInkView.setEntries(currentEntries)
                updateToolbarState()
            }
        }
    }

    override fun onDestroy() {
        PdfCrashDiagnostics.mark(this, "Z01_ON_DESTROY")
        ++renderGeneration
        try {
            wetInkView.clearFinishedStrokesListeners()
        } catch (_: Throwable) {
        }
        try {
            surface.releaseBitmap()
        } catch (_: Throwable) {
        }
        try {
            renderer.close()
        } catch (_: Throwable) {
        }
        try {
            descriptor.close()
        } catch (_: Throwable) {
        }
        renderExecutor.shutdownNow()
        ioExecutor.shutdown()
        super.onDestroy()
    }

    private val Int.dp: Int
        get() = (this * resources.displayMetrics.density).roundToInt()

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

    private class PdfSurfaceView(context: Context) : View(context) {
        var onTransformChanged: (() -> Unit)? = null
        var onStylusEvent: ((MotionEvent) -> Boolean)? = null

        private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        private var bitmap: Bitmap? = null
        private var pageWidth = 1f
        private var pageHeight = 1f

        private var zoom = 1f
        private var panX = 0f
        private var panY = 0f
        private var lastX = 0f
        private var lastY = 0f
        private var dragging = false

        private val pageToView = Matrix()
        private val viewToPage = Matrix()

        private val scaleDetector =
            ScaleGestureDetector(
                context,
                object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                    override fun onScale(detector: ScaleGestureDetector): Boolean {
                        zoom = (zoom * detector.scaleFactor).coerceIn(1f, 5f)
                        updateMatrices()
                        invalidate()
                        onTransformChanged?.invoke()
                        return true
                    }
                },
            )

        fun setPage(value: Bitmap, width: Float, height: Float) {
            bitmap?.takeIf { it !== value }?.recycle()
            bitmap = value
            pageWidth = width.coerceAtLeast(1f)
            pageHeight = height.coerceAtLeast(1f)
            resetTransform()
        }

        fun releaseBitmap() {
            bitmap?.recycle()
            bitmap = null
        }

        fun resetTransform() {
            zoom = 1f
            panX = 0f
            panY = 0f
            updateMatrices()
            invalidate()
            onTransformChanged?.invoke()
        }

        fun pageToViewMatrix(): Matrix {
            updateMatrices()
            return Matrix(pageToView)
        }

        fun viewToPageMatrix(): Matrix {
            updateMatrices()
            return Matrix(viewToPage)
        }

        private fun updateMatrices() {
            val availableWidth = width.coerceAtLeast(1).toFloat()
            val availableHeight = height.coerceAtLeast(1).toFloat()
            val base =
                min(
                    availableWidth / pageWidth,
                    availableHeight / pageHeight,
                )

            val scaledWidth = pageWidth * base * zoom
            val scaledHeight = pageHeight * base * zoom
            val left = (availableWidth - scaledWidth) / 2f + panX
            val top = (availableHeight - scaledHeight) / 2f + panY

            pageToView.reset()
            pageToView.postScale(base * zoom, base * zoom)
            pageToView.postTranslate(left, top)
            pageToView.invert(viewToPage)
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            updateMatrices()
            onTransformChanged?.invoke()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            canvas.drawColor(Color.rgb(35, 37, 42))
            val pageBitmap = bitmap ?: return

            updateMatrices()
            canvas.save()
            canvas.concat(pageToView)
            canvas.drawBitmap(
                pageBitmap,
                null,
                RectF(0f, 0f, pageWidth, pageHeight),
                paint,
            )
            canvas.restore()
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            val toolType =
                if (event.pointerCount > 0) {
                    event.getToolType(event.actionIndex.coerceAtLeast(0))
                } else {
                    MotionEvent.TOOL_TYPE_UNKNOWN
                }

            if (
                toolType == MotionEvent.TOOL_TYPE_STYLUS ||
                    toolType == MotionEvent.TOOL_TYPE_ERASER
            ) {
                return onStylusEvent?.invoke(event) ?: true
            }

            scaleDetector.onTouchEvent(event)
            if (scaleDetector.isInProgress) return true

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    dragging = true
                    lastX = event.x
                    lastY = event.y
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (dragging && zoom > 1f) {
                        panX += event.x - lastX
                        panY += event.y - lastY
                        lastX = event.x
                        lastY = event.y
                        updateMatrices()
                        invalidate()
                        onTransformChanged?.invoke()
                    }
                    return true
                }
                MotionEvent.ACTION_UP,
                MotionEvent.ACTION_CANCEL -> {
                    dragging = false
                    return true
                }
            }
            return true
        }
    }
}
