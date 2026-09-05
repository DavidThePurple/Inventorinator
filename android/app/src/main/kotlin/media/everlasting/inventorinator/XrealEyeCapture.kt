package media.everlasting.inventorinator

import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import android.media.ImageReader
import android.media.MediaCodec
import android.media.MediaFormat
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.HandlerThread
import java.io.ByteArrayOutputStream
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/** Native XREAL Eye TCP/HEVC transport. The Eye is reachable through the
 * glasses' USB Ethernet network rather than Android Camera2/UVC. */
class XrealEyeCapture(private val context: Context) {
    private val running = AtomicBoolean(false)
    @Volatile private var latestFrame: ByteArray? = null
    @Volatile private var packets = 0L
    @Volatile private var error: String? = null
    private var worker: Thread? = null
    private var decoder: MediaCodec? = null
    private var imageReader: ImageReader? = null
    private var imageThread: HandlerThread? = null

    fun start(): Boolean {
        if (running.get()) return true
        error = null
        val network = eyeNetwork() ?: run {
            error = "XREAL Eye USB network was not found."
            return false
        }
        startDecoder()
        running.set(true)
        worker = Thread({ readLoop(network) }, "xreal-eye-reader").also { it.start() }
        return true
    }

    fun stop() {
        running.set(false)
        worker?.interrupt()
        worker = null
        decoder?.stop()
        decoder?.release()
        decoder = null
        imageReader?.close()
        imageReader = null
        imageThread?.quitSafely()
        imageThread = null
    }

    fun status(): Map<String, Any?> = mapOf(
        "streaming" to running.get(), "packets" to packets, "error" to error,
    )

    fun frame(): ByteArray? = latestFrame

    private fun eyeNetwork(): Network? {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        return connectivity.allNetworks.firstOrNull { network ->
            connectivity.getLinkProperties(network)?.linkAddresses?.any {
                it.address.hostAddress?.startsWith("169.254.2.") == true
            } == true
        }
    }

    private fun startDecoder() {
        val readerThread = HandlerThread("xreal-eye-image").also { it.start() }
        imageThread = readerThread
        val reader = ImageReader.newInstance(1280, 720, ImageFormat.YUV_420_888, 3)
        imageReader = reader
        reader.setOnImageAvailableListener({ source ->
            source.acquireLatestImage()?.use { image -> latestFrame = jpeg(image) }
        }, Handler(readerThread.looper))
        decoder = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_HEVC).apply {
            configure(MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_HEVC, 1280, 720), reader.surface, null, 0)
            start()
        }
    }

    private fun readLoop(network: Network) {
        while (running.get()) {
            try {
                network.socketFactory.createSocket("169.254.2.1", 52995).use { video ->
                    network.socketFactory.createSocket("169.254.2.1", 52999).use { control ->
                        if (!activate(control) || !activate(control)) throw IllegalStateException("Eye start rejected")
                        while (running.get()) {
                            val header = readExact(video, 6)
                            val size = ((header[2].toInt() and 0xff) shl 24) or
                                ((header[3].toInt() and 0xff) shl 16) or
                                ((header[4].toInt() and 0xff) shl 8) or (header[5].toInt() and 0xff)
                            val payload = readExact(video, size)
                            if (header[0].toInt() == 0x27 && header[1].toInt() == 0x85) {
                                packets++
                                val start = annexB(payload)
                                if (start >= 0) queueHevc(payload.copyOfRange(start, payload.size))
                            }
                        }
                    }
                }
            } catch (exception: Exception) {
                if (running.get()) {
                    error = exception.message ?: "XREAL Eye stream disconnected."
                    try { Thread.sleep(150) } catch (_: InterruptedException) { }
                }
            }
        }
    }

    private fun activate(control: Socket): Boolean {
        val start = byteArrayOf(0x27, 0x81.toByte(), 0, 0, 0, 6, 0x80.toByte(), 0, 0, 1, 0x1a, 0)
        control.getOutputStream().write(start)
        control.getOutputStream().flush()
        val header = readExact(control, 6)
        val size = ((header[2].toInt() and 0xff) shl 24) or ((header[3].toInt() and 0xff) shl 16) or ((header[4].toInt() and 0xff) shl 8) or (header[5].toInt() and 0xff)
        readExact(control, size)
        return header[0].toInt() == 0x27 && header[1].toInt() == 0x81
    }

    private fun queueHevc(bytes: ByteArray) {
        val codec = decoder ?: return
        val index = codec.dequeueInputBuffer(10_000)
        if (index >= 0) codec.getInputBuffer(index)?.let { buffer ->
            buffer.clear(); buffer.put(bytes)
            codec.queueInputBuffer(index, 0, bytes.size, System.nanoTime() / 1000, 0)
        }
    }

    private fun annexB(payload: ByteArray): Int {
        for (index in 80 until minOf(120, payload.size - 4)) {
            if (payload[index] == 0.toByte() && payload[index + 1] == 0.toByte() && payload[index + 2] == 0.toByte() && payload[index + 3] == 1.toByte()) return index
        }
        return -1
    }

    private fun readExact(socket: Socket, count: Int): ByteArray {
        val result = ByteArray(count); var offset = 0
        while (offset < count) {
            val read = socket.getInputStream().read(result, offset, count - offset)
            if (read <= 0) throw IllegalStateException("XREAL Eye socket closed")
            offset += read
        }
        return result
    }

    private fun jpeg(image: Image): ByteArray {
        val width = image.width; val height = image.height
        val nv21 = ByteArray(width * height * 3 / 2)
        val y = image.planes[0]; val u = image.planes[1]; val v = image.planes[2]
        for (row in 0 until height) for (col in 0 until width) nv21[row * width + col] = y.buffer.get(row * y.rowStride + col * y.pixelStride)
        var output = width * height
        for (row in 0 until height / 2) for (col in 0 until width / 2) {
            nv21[output++] = v.buffer.get(row * v.rowStride + col * v.pixelStride)
            nv21[output++] = u.buffer.get(row * u.rowStride + col * u.pixelStride)
        }
        return ByteArrayOutputStream().use { stream ->
            YuvImage(nv21, ImageFormat.NV21, width, height, null).compressToJpeg(Rect(0, 0, width, height), 88, stream)
            stream.toByteArray()
        }
    }
}
