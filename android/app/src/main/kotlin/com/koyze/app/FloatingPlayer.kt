package com.koyze.app

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.roundToInt

internal object FloatingPlayer {
    private const val channelName = "koyze/floating_player"

    private var activity: Activity? = null
    private var channel: MethodChannel? = null
    private var windowManager: WindowManager? = null
    private var root: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var artworkView: ImageView? = null
    private var lyricView: TextView? = null
    private var titleView: TextView? = null
    private var progressView: ProgressBar? = null
    private var playView: ImageView? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val loader = Executors.newSingleThreadExecutor()
    private val artworkGeneration = AtomicInteger()
    private var artworkUrl: String? = null

    fun attach(host: Activity, messenger: BinaryMessenger) {
        activity = host
        channel = MethodChannel(messenger, channelName).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "canDrawOverlays" -> result.success(canDrawOverlays())
                    "requestPermission" -> {
                        requestPermission()
                        result.success(null)
                    }
                    "show" -> result.success(show())
                    "hide" -> {
                        hide()
                        result.success(null)
                    }
                    "update" -> {
                        @Suppress("UNCHECKED_CAST")
                        update(call.arguments as? Map<String, Any?>)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun hide() {
        val manager = windowManager
        val view = root
        if (manager != null && view != null) {
            runCatching { manager.removeView(view) }
        }
        root = null
        actions.clear()
        artworkView = null
        lyricView = null
        titleView = null
        progressView = null
        playView = null
        windowManager = null
        artworkUrl = null
    }

    private fun canDrawOverlays(): Boolean {
        val host = activity ?: return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(host)
    }

    private fun requestPermission() {
        val host = activity ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(host)) return
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${host.packageName}"),
        )
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        host.startActivity(intent)
    }

    private fun show(): Boolean {
        if (root != null) return true
        val host = activity ?: return false
        if (!canDrawOverlays()) return false
        val manager = host.getSystemService(WindowManager::class.java) ?: return false
        val view = buildView(host)
        val layoutParams = WindowManager.LayoutParams(
            dp(host, 336),
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            val width = dp(host, 336)
            x = ((host.resources.displayMetrics.widthPixels - width) / 2).coerceAtLeast(0)
            y = dp(host, 48)
        }
        return runCatching {
            manager.addView(view, layoutParams)
            windowManager = manager
            root = view
            params = layoutParams
            true
        }.getOrDefault(false)
    }

    private fun update(payload: Map<String, Any?>?) {
        if (payload == null || root == null) return
        val title = payload["title"]?.toString().orEmpty()
        val lyric = payload["lyric"]?.toString().orEmpty().ifBlank { title }
        val position = (payload["positionMs"] as? Number)?.toInt() ?: 0
        val duration = (payload["durationMs"] as? Number)?.toInt() ?: 0
        val playing = payload["playing"] == true
        val artwork = payload["artwork"]?.toString()
        lyricView?.text = title.ifBlank { lyric }
        titleView?.text = if (title.isBlank()) "" else lyric
        progressView?.apply {
            max = 1000
            progress = if (duration <= 0) 0 else (position.coerceIn(0, duration) * 1000L / duration).toInt()
        }
        playView?.setImageResource(
            if (playing) R.drawable.ic_float_pause else R.drawable.ic_float_play,
        )
        if (artwork != artworkUrl) {
            artworkUrl = artwork
            loadArtwork(artwork)
        }
    }

    private fun buildView(host: Activity): View {
        actions.clear()
        val card = LinearLayout(host).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(host, 12), dp(host, 9), dp(host, 6), dp(host, 9))
            clipChildren = true
            background = GradientDrawable().apply {
                cornerRadius = dp(host, 33).toFloat()
                setColor(Color.parseColor("#F01C1C1E"))
            }
            elevation = dp(host, 8).toFloat()
        }
        val artwork = ImageView(host).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = GradientDrawable().apply {
                cornerRadius = dp(host, 24).toFloat()
                setColor(Color.parseColor("#33FFFFFF"))
            }
            clipToOutline = true
            outlineProvider = android.view.ViewOutlineProvider.BACKGROUND
        }
        artworkView = artwork
        val coverSize = dp(host, 92)
        card.addView(artwork, LinearLayout.LayoutParams(coverSize, coverSize))

        val column = LinearLayout(host).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(host, 12), 0, 0, 0)
        }
        val lyric = TextView(host).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
            includeFontPadding = false
            text = " "
        }
        val title = TextView(host).apply {
            setTextColor(Color.parseColor("#B3FFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            maxLines = 1
            includeFontPadding = false
        }
        val progress = ProgressBar(host, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 1000
            progress = 0
            progressTintList = ColorStateList.valueOf(Color.WHITE)
            progressBackgroundTintList = ColorStateList.valueOf(Color.parseColor("#33FFFFFF"))
        }
        lyricView = lyric
        titleView = title
        progressView = progress
        column.addView(lyric)
        column.addView(title, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(host, 3) })
        column.addView(progress, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(host, 5),
        ).apply { topMargin = dp(host, 6) })
        column.addView(controlRow(host), LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(host, 30),
        ).apply { topMargin = dp(host, 3) })
        card.addView(column, LinearLayout.LayoutParams(0, coverSize, 1f))

        val frame = FrameLayout(host)
        frame.addView(card)
        val close = TextView(host).apply {
            text = "×"
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            setOnClickListener { dispatch("dismiss") }
        }
        frame.addView(close, FrameLayout.LayoutParams(dp(host, 42), dp(host, 42), Gravity.TOP or Gravity.END))
        installDrag(card)
        return frame
    }

    private fun controlRow(host: Activity): View {
        val row = LinearLayout(host).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val buttonWidth = dp(host, 42)
        val buttonHeight = dp(host, 30)
        fun addButton(icon: Int, tint: Int, action: () -> Unit): ImageView {
            val button = controlButton(host, icon, tint, action)
            row.addView(button, LinearLayout.LayoutParams(buttonWidth, buttonHeight))
            return button
        }
        addButton(R.drawable.ic_float_previous, Color.WHITE) { dispatch("previous") }
        playView = addButton(R.drawable.ic_float_play, Color.BLACK) { dispatch("toggle") }.apply {
            layoutParams = LinearLayout.LayoutParams(buttonHeight, buttonHeight)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#1ED760"))
            }
            setPadding(dp(host, 6), dp(host, 6), dp(host, 6), dp(host, 6))
            elevation = dp(host, 3).toFloat()
        }
        addButton(R.drawable.ic_float_next, Color.WHITE) { dispatch("next") }
        return row
    }

    private fun controlButton(
        host: Activity,
        icon: Int,
        tint: Int,
        onClick: () -> Unit,
    ): ImageView {
        return ImageView(host).apply {
            setImageResource(icon)
            setColorFilter(tint)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(dp(host, 8), dp(host, 6), dp(host, 8), dp(host, 6))
            actions[this] = onClick
        }
    }

    private val actions = HashMap<View, () -> Unit>()

    private fun installDrag(view: View) {
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var dragging = false
        val slop = dp(view.context as Activity, 8)
        view.setOnTouchListener { _, event ->
            val layoutParams = params ?: return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    dragging = false
                    downX = event.rawX
                    downY = event.rawY
                    startX = layoutParams.x
                    startY = layoutParams.y
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!dragging && dx * dx + dy * dy > slop * slop) dragging = true
                    if (dragging) {
                        layoutParams.x = startX + dx.roundToInt()
                        layoutParams.y = startY + dy.roundToInt()
                        windowManager?.updateViewLayout(root, layoutParams)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!dragging) {
                        hitAction(view, event.rawX, event.rawY)?.invoke() ?: openApp()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun hitAction(view: View, rawX: Float, rawY: Float): (() -> Unit)? {
        if (view is android.view.ViewGroup) {
            for (index in view.childCount - 1 downTo 0) {
                hitAction(view.getChildAt(index), rawX, rawY)?.let { return it }
            }
        }
        val action = actions[view] ?: return null
        val location = IntArray(2)
        view.getLocationOnScreen(location)
        val inside = rawX >= location[0] &&
            rawX < location[0] + view.width &&
            rawY >= location[1] &&
            rawY < location[1] + view.height
        return if (inside) action else null
    }

    private fun dispatch(action: String) {
        if (action == "open") openApp()
        runCatching { channel?.invokeMethod("action", action) }
    }

    private fun openApp() {
        val host = activity ?: return
        val intent = Intent(host, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
            )
        }
        host.startActivity(intent)
    }

    private fun loadArtwork(url: String?) {
        val generation = artworkGeneration.incrementAndGet()
        if (url.isNullOrBlank()) {
            artworkView?.setImageDrawable(null)
            return
        }
        loader.execute {
            val bitmap = runCatching { decodeArtwork(url) }.getOrNull()
            mainHandler.post {
                if (generation == artworkGeneration.get()) {
                    artworkView?.setImageBitmap(bitmap)
                }
            }
        }
    }

    private fun decodeArtwork(url: String): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        open(url)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        val sample = calculateSample(bounds.outWidth, bounds.outHeight, 256)
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return open(url)?.use { BitmapFactory.decodeStream(it, null, options) }
    }

    private fun open(url: String): java.io.InputStream? {
        if (url.startsWith("content://") || url.startsWith("file://")) {
            val host = activity ?: return null
            return host.contentResolver.openInputStream(Uri.parse(url))
        }
        if (!url.startsWith("https://") && !url.startsWith("http://")) return null
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 8000
        connection.readTimeout = 8000
        connection.instanceFollowRedirects = true
        connection.connect()
        return connection.inputStream
    }

    private fun calculateSample(width: Int, height: Int, target: Int): Int {
        var sample = 1
        while (width / sample > target * 2 || height / sample > target * 2) sample *= 2
        return sample
    }

    private fun dp(host: Activity, value: Int): Int {
        return (value * host.resources.displayMetrics.density).roundToInt()
    }
}
