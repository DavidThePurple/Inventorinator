import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zxing2/qrcode.dart';

enum ScanMode { find, ingest }

enum ScanCaptureMode { barcode, ocr }

String _cameraDisplayName(String name) {
  // Windows camera names may include a device path in angle brackets. Keep
  // the full value for device selection, but show only the friendly name.
  final separator = name.indexOf(' <');
  return separator > 0 ? name.substring(0, separator) : name;
}

int _frameFingerprint(Uint8List bytes) {
  // Native polling returns a fresh byte list even when the decoded frame has
  // not changed. Sample across the JPEG so Flutter only repaints new frames.
  var value = bytes.length;
  final step = (bytes.length / 16).ceil();
  for (var index = 0; index < bytes.length; index += step) {
    value = 0x1fffffff & ((value * 31) ^ bytes[index]);
  }
  return value;
}

typedef ScanResultCallback = void Function(
  String code,
  ScanMode mode,
  Uint8List? imageBytes,
);
typedef LabelCaptureCallback = Future<void> Function(Uint8List imageBytes);

class InventoryQrScanner extends StatefulWidget {
  const InventoryQrScanner({
    super.key,
    required this.onCode,
    this.onLabelCapture,
  });

  final ScanResultCallback onCode;
  final LabelCaptureCallback? onLabelCapture;

  @override
  State<InventoryQrScanner> createState() => _InventoryQrScannerState();
}

class _InventoryQrScannerState extends State<InventoryQrScanner> {
  ScanMode mode = ScanMode.find;
  ScanCaptureMode captureMode = ScanCaptureMode.barcode;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: SegmentedButton<ScanMode>(
            key: const Key('scan-mode'),
            segments: const [
              ButtonSegment(
                value: ScanMode.find,
                icon: Icon(Icons.search_rounded),
                label: Text('Find'),
              ),
              ButtonSegment(
                value: ScanMode.ingest,
                icon: Icon(Icons.add_box_outlined),
                label: Text('Ingest'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (selection) =>
                setState(() => mode = selection.first),
          ),
        ),
        if (mode == ScanMode.ingest)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SegmentedButton<ScanCaptureMode>(
              key: const Key('scan-capture-mode'),
              segments: const [
                ButtonSegment(
                  value: ScanCaptureMode.barcode,
                  icon: Icon(Icons.barcode_reader),
                  label: Text('Barcode'),
                ),
                ButtonSegment(
                  value: ScanCaptureMode.ocr,
                  icon: Icon(Icons.document_scanner_outlined),
                  label: Text('OCR'),
                ),
              ],
              selected: {captureMode},
              onSelectionChanged: (selection) =>
                  setState(() => captureMode = selection.first),
            ),
          ),
        Text(
          mode == ScanMode.find
              ? 'Scan an Inventorinator QR to open an item.'
              : captureMode == ScanCaptureMode.barcode
              ? 'Scan a product UPC, EAN, Code 128, or QR to add an item.'
              : 'Frame the label, then tap/click the camera view to process it.',
          style: const TextStyle(color: Color(0xff929aac)),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Platform.isAndroid
              ? _MobileCameraScanner(
                  mode: mode,
                  captureMode: captureMode,
                  onCode: (code, image) => widget.onCode(code, mode, image),
                  onLabelCapture: widget.onLabelCapture,
                )
              : Platform.isLinux
              ? _LinuxCameraScanner(
                  mode: mode,
                  captureMode: captureMode,
                  onCode: (code, image) => widget.onCode(code, mode, image),
                  onLabelCapture: widget.onLabelCapture,
                )
              : Platform.isWindows
              ? _WindowsCameraScanner(
                  mode: mode,
                  captureMode: captureMode,
                  onCode: (code, image) => widget.onCode(code, mode, image),
                  onLabelCapture: widget.onLabelCapture,
                )
              : _UnsupportedScanner(
                  onCode: (code) => widget.onCode(code, mode, null),
                ),
        ),
      ],
    ),
  );
}

class _MobileCameraScanner extends StatefulWidget {
  const _MobileCameraScanner({
    required this.onCode,
    required this.mode,
    required this.captureMode,
    this.onLabelCapture,
  });
  final void Function(String code, Uint8List? imageBytes) onCode;
  final ScanMode mode;
  final ScanCaptureMode captureMode;
  final LabelCaptureCallback? onLabelCapture;

  @override
  State<_MobileCameraScanner> createState() => _MobileCameraScannerState();
}

class _MobileCameraScannerState extends State<_MobileCameraScanner> {
  static const _xrealEyeChannel = MethodChannel('inventorinator/xreal_eye');
  bool delivered = false;
  bool xrealEyeMode = false;
  Uint8List? xrealEyeFrame;
  Timer? xrealEyeTimer;
  // Normal barcode scanning only needs decoded values. Requesting an image
  // for every preview frame forces large allocations and image conversion on
  // Android, which can stall scrolling and other UI work on high-resolution
  // phones. OCR uses its own still-photo camera below.
  final controller = MobileScannerController(
    returnImage: false,
    autoZoom: false,
    cameraResolution: const Size(1280, 720),
  );

  @override
  void initState() {
    super.initState();
    xrealEyeTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => unawaited(_pollXrealEye()),
    );
  }

  Future<void> _pollXrealEye() async {
    if (!xrealEyeMode) return;
    try {
      final frame = await _xrealEyeChannel.invokeMethod<Uint8List>('frame');
      if (mounted && frame != null && frame.isNotEmpty) {
        setState(() => xrealEyeFrame = frame);
      }
    } catch (_) {}
  }

  Future<void> _toggleXrealEye() async {
    try {
      if (xrealEyeMode) {
        await _xrealEyeChannel.invokeMethod<void>('stop');
        if (mounted) {
          setState(() {
            xrealEyeMode = false;
            xrealEyeFrame = null;
          });
        }
      } else {
        await _xrealEyeChannel.invokeMethod<void>('start');
        if (mounted) {
          setState(() {
            xrealEyeMode = true;
            delivered = false;
          });
        }
      }
    } on PlatformException {
      // The regular Android camera remains available when the Eye is absent.
    }
  }

  @override
  void didUpdateWidget(covariant _MobileCameraScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.captureMode != widget.captureMode) {
      delivered = false;
    }
  }

  @override
  void dispose() {
    xrealEyeTimer?.cancel();
    unawaited(_xrealEyeChannel.invokeMethod<void>('stop'));
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == ScanMode.ingest &&
        widget.captureMode == ScanCaptureMode.ocr &&
        widget.onLabelCapture != null) {
      return _MobileOcrCamera(onLabelCapture: widget.onLabelCapture!);
    }
    return GestureDetector(
      key: const Key('scanner-camera-surface'),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (xrealEyeMode && xrealEyeFrame != null)
            Image.memory(
              xrealEyeFrame!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            )
          else
            MobileScanner(
              controller: controller,
              onDetect: (capture) {
                if (delivered) return;
                final value = capture.barcodes.firstOrNull?.rawValue;
                if (value == null) return;
                if (widget.mode == ScanMode.ingest &&
                    widget.captureMode == ScanCaptureMode.ocr) {
                  final image = capture.image;
                  if (image == null || widget.onLabelCapture == null) return;
                  delivered = true;
                  unawaited(widget.onLabelCapture!(image));
                  return;
                }
                delivered = true;
                widget.onCode(value, null);
              },
            ),
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              children: [
                IconButton.filledTonal(
                  key: const Key('xreal-eye-camera-mobile'),
                  tooltip: 'XREAL Eye',
                  onPressed: _toggleXrealEye,
                  icon: Icon(
                    xrealEyeMode ? Icons.stop_rounded : Icons.videocam_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const Key('cycle-camera'),
                  tooltip: 'Switch camera',
                  onPressed: () => unawaited(controller.switchCamera()),
                  icon: const Icon(Icons.cameraswitch_rounded),
                ),
              ],
            ),
          ),
          _ScanGuide(wide: widget.mode == ScanMode.ingest),
        ],
      ),
    );
  }
}

class _MobileOcrCamera extends StatefulWidget {
  const _MobileOcrCamera({required this.onLabelCapture});
  final LabelCaptureCallback onLabelCapture;

  @override
  State<_MobileOcrCamera> createState() => _MobileOcrCameraState();
}

class _MobileOcrCameraState extends State<_MobileOcrCamera>
    with WidgetsBindingObserver {
  CameraController? camera;
  bool capturing = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final previous = camera;
      camera = null;
      unawaited(previous?.dispose());
    } else if (state == AppLifecycleState.resumed && camera == null) {
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      final description = cameras.firstWhere(
        (value) => value.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final next = CameraController(
        description,
        // OCR captures one still image; requesting the full sensor resolution
        // creates a large capture/decode spike on high-resolution phones.
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await next.initialize();
      try {
        await next.setFocusMode(FocusMode.auto);
      } catch (_) {
        // A few fixed-focus phone cameras do not expose focus controls.
      }
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        camera = next;
        error = null;
      });
    } catch (exception) {
      if (mounted) setState(() => error = 'Camera error: $exception');
    }
  }

  Future<void> _capture() async {
    final active = camera;
    if (active == null || !active.value.isInitialized || capturing) return;
    setState(() => capturing = true);
    try {
      try {
        await active.setFocusPoint(const Offset(.5, .5));
        await active.setFocusMode(FocusMode.auto);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } catch (_) {
        // Capture immediately when the device cannot set a focus point.
      }
      final photo = await active.takePicture();
      await widget.onLabelCapture(await photo.readAsBytes());
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'Could not capture label: $exception');
      }
    } finally {
      if (mounted) setState(() => capturing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(camera?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = camera;
    if (error != null) return Center(child: Text(error!));
    if (active == null || !active.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      key: const Key('scanner-camera-surface'),
      behavior: HitTestBehavior.opaque,
      onTap: _capture,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: active.value.aspectRatio,
              child: CameraPreview(active),
            ),
          ),
          const _ScanGuide(wide: true),
          if (capturing)
            const ColoredBox(
              color: Color(0x55000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

bool _isXrealEyeCamera(CameraDescription camera) {
  final name = camera.name.toLowerCase();
  return name.contains('xreal') ||
      name.contains('x-real') ||
      (name.contains('eye') && name.contains('camera'));
}

int _windowsCameraPriority(CameraDescription camera) {
  final name = camera.name.toLowerCase();
  if (_isXrealEyeCamera(camera)) {
    return -10;
  }
  if (name.contains('ir') || name.contains('depth')) return 100;
  if (name.contains('5m')) return 0;
  if (name.contains('13m')) return 1;
  if (name.contains('webcam')) return 5;
  return 10;
}

int _compareWindowsCameras(CameraDescription a, CameraDescription b) {
  final priority = _windowsCameraPriority(a)
      .compareTo(_windowsCameraPriority(b));
  return priority != 0 ? priority : a.name.compareTo(b.name);
}

class _WindowsCameraScanner extends StatefulWidget {
  const _WindowsCameraScanner({
    required this.onCode,
    required this.mode,
    required this.captureMode,
    this.onLabelCapture,
  });

  final void Function(String code, Uint8List? imageBytes) onCode;
  final ScanMode mode;
  final ScanCaptureMode captureMode;
  final LabelCaptureCallback? onLabelCapture;

  @override
  State<_WindowsCameraScanner> createState() => _WindowsCameraScannerState();
}

class _WindowsCameraScannerState extends State<_WindowsCameraScanner> {
  static const _xrealEyeChannel = MethodChannel('inventorinator/xreal_r1');
  final manual = TextEditingController();
  List<CameraDescription> cameras = const [];
  int selectedCamera = 0;
  CameraController? camera;
  Timer? scanTimer;
  Timer? xrealEyeTimer;
  bool initializing = true;
  bool capturing = false;
  bool decoding = false;
  bool delivered = false;
  String? error;
  bool xrealEyeMode = false;
  bool xrealEyeStreaming = false;
  int xrealEyePackets = 0;
  Uint8List? xrealEyeFrame;
  MemoryImage? xrealEyeImage;
  int? xrealEyeFrameFingerprint;

  @override
  void initState() {
    super.initState();
    unawaited(_findCameras());
    xrealEyeTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => unawaited(_pollXrealEye()),
    );
  }

  Future<void> _pollXrealEye() async {
    if (!xrealEyeMode) return;
    try {
      final frame = await _xrealEyeChannel.invokeMethod<Uint8List>('frame');
      final status = await _xrealEyeChannel.invokeMapMethod<String, dynamic>(
        'status',
      );
      if (!mounted) return;
      final fingerprint = frame == null || frame.isEmpty
          ? null
          : _frameFingerprint(frame);
      setState(() {
        xrealEyeStreaming = status?['streaming'] == true;
        xrealEyePackets = (status?['packets'] as num?)?.toInt() ?? 0;
        if (frame != null &&
            frame.isNotEmpty &&
            fingerprint != xrealEyeFrameFingerprint) {
          xrealEyeFrame = frame;
          xrealEyeImage = MemoryImage(frame);
          xrealEyeFrameFingerprint = fingerprint;
        }
      });
      if (frame != null &&
          frame.isNotEmpty &&
          widget.captureMode == ScanCaptureMode.barcode &&
          !delivered &&
          !decoding) {
        decoding = true;
        try {
          final code = widget.mode == ScanMode.ingest
              ? await compute(decodeProductBarcodeFrame, frame)
              : await compute(decodeInventoryQrFrame, frame);
          if (code != null && !delivered) {
            delivered = true;
            widget.onCode(code, frame);
          }
        } finally {
          decoding = false;
        }
      }
    } catch (_) {
      // The normal Windows camera remains usable if the Eye is unplugged.
    }
  }

  Future<void> _toggleXrealEye() async {
    try {
      if (xrealEyeMode) {
        await _xrealEyeChannel.invokeMethod<void>('stop');
        if (mounted) {
          setState(() {
            xrealEyeMode = false;
            xrealEyeStreaming = false;
            xrealEyePackets = 0;
            xrealEyeFrame = null;
            xrealEyeImage = null;
            xrealEyeFrameFingerprint = null;
          });
        }
      } else {
        await _xrealEyeChannel.invokeMethod<void>('start');
        if (mounted) setState(() => xrealEyeMode = true);
      }
    } on PlatformException catch (exception) {
      if (mounted) {
        setState(() => error = exception.message ?? 'XREAL Eye unavailable.');
      }
    }
  }

  @override
  void didUpdateWidget(covariant _WindowsCameraScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.captureMode != widget.captureMode) {
      delivered = false;
    }
  }

  Future<void> _findCameras() async {
    scanTimer?.cancel();
    if (mounted) {
      setState(() {
        initializing = true;
        error = null;
      });
    }
    try {
      // Bounded so a platform channel that never responds (e.g. no camera
      // plugin handler available) settles into the error state rather than
      // leaving the loading spinner running indefinitely.
      final found = (await availableCameras().timeout(
        const Duration(seconds: 5),
      )).toList()..sort(_compareWindowsCameras);
      if (!mounted) return;
      setState(() {
        cameras = found;
        selectedCamera = selectedCamera
            .clamp(0, found.isEmpty ? 0 : found.length - 1)
            .toInt();
        initializing = false;
        error = found.isEmpty ? 'No Windows camera was found.' : null;
      });
      if (found.isNotEmpty) await _startCamera(selectedCamera);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        initializing = false;
        error = 'Could not list Windows cameras: $exception';
      });
    }
  }

  Future<void> _startCamera(int index) async {
    scanTimer?.cancel();
    final previous = camera;
    camera = null;
    if (mounted) {
      setState(() {
        selectedCamera = index;
        initializing = true;
        error = null;
      });
    }
    await previous?.dispose();
    try {
      Object? lastException;
      for (final preset in const [
        // The ASUS 5M exposes its usable Media Foundation stream above the
        // 720p cap used by ResolutionPreset.high. Try the unrestricted native
        // Windows preset first, then retain the existing fallbacks.
        ResolutionPreset.max,
        ResolutionPreset.high,
        ResolutionPreset.medium,
        ResolutionPreset.low,
      ]) {
        final next = CameraController(
          cameras[index],
          preset,
          enableAudio: false,
        );
        try {
          await next.initialize();
          if (!mounted) {
            await next.dispose();
            return;
          }
          setState(() {
            camera = next;
            initializing = false;
            delivered = false;
          });
          scanTimer = Timer.periodic(
            const Duration(milliseconds: 650),
            (_) => unawaited(_scanCurrentFrame()),
          );
          return;
        } catch (exception) {
          lastException = exception;
          await next.dispose();
        }
      }
      throw lastException ?? StateError('Camera initialization failed.');
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        initializing = false;
        error = 'Could not open ${cameras[index].name}: $exception';
      });
    }
  }

  Future<Uint8List?> _takePicture() async {
    final active = camera;
    if (active == null || !active.value.isInitialized || capturing) return null;
    capturing = true;
    try {
      final picture = await active.takePicture();
      final bytes = await picture.readAsBytes();
      try {
        await File(picture.path).delete();
      } catch (_) {
        // The Windows plugin normally stores captures in a temporary file.
      }
      return bytes;
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'Camera capture failed: $exception');
      }
      return null;
    } finally {
      capturing = false;
    }
  }

  Future<void> _scanCurrentFrame() async {
    if (widget.captureMode != ScanCaptureMode.barcode ||
        delivered ||
        decoding) {
      return;
    }
    final bytes = await _takePicture();
    if (bytes == null) return;
    decoding = true;
    try {
      String? code;
      try {
        code = widget.mode == ScanMode.ingest
            ? await compute(decodeProductBarcodeFrame, bytes)
            : await compute(decodeInventoryQrFrame, bytes);
      } catch (exception) {
        debugPrint('Windows barcode decoder error: $exception');
      }
      code ??= await compute(_decodeQrFrame, bytes);
      if (code != null && !delivered) {
        delivered = true;
        widget.onCode(code, bytes);
        // A matched code closes the scanner. If it is still open, the code
        // was rejected (no matching item), so keep looking after the
        // message has had a moment to show.
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) delivered = false;
          }),
        );
      }
    } finally {
      decoding = false;
    }
  }

  Future<void> _captureLabel() async {
    if (widget.onLabelCapture == null) return;
    final bytes = await _takePicture();
    if (bytes != null) await widget.onLabelCapture!(bytes);
  }

  void _cycleCamera() {
    if (cameras.length < 2 || initializing) return;
    final next = (selectedCamera + 1) % cameras.length;
    unawaited(_startCamera(next));
  }

  Widget _cameraPreview(CameraController? active) =>
      xrealEyeMode && xrealEyeImage != null
      ? GestureDetector(
          key: const Key('xreal-eye-camera-surface'),
          behavior: HitTestBehavior.opaque,
          onTap:
              widget.mode == ScanMode.ingest &&
                  widget.captureMode == ScanCaptureMode.ocr &&
                  widget.onLabelCapture != null
              ? () => unawaited(widget.onLabelCapture!(xrealEyeFrame!))
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(
                image: xrealEyeImage!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
              _ScanGuide(wide: widget.mode == ScanMode.ingest),
            ],
          ),
        )
      : active == null || !active.value.isInitialized
      ? Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (initializing) const CircularProgressIndicator(),
              if (error != null) ...[
                Text(error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _findCameras,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Check cameras again'),
                ),
              ],
            ],
          ),
        )
      : GestureDetector(
          key: const Key('scanner-camera-surface'),
          behavior: HitTestBehavior.opaque,
          onTap:
              widget.mode == ScanMode.ingest &&
                  widget.captureMode == ScanCaptureMode.ocr &&
                  widget.onLabelCapture != null
              ? _captureLabel
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: active.value.aspectRatio,
                  child: CameraPreview(active),
                ),
              ),
              _ScanGuide(wide: widget.mode == ScanMode.ingest),
              if (capturing && widget.captureMode == ScanCaptureMode.ocr)
                const ColoredBox(
                  color: Color(0x33000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        );

  @override
  void dispose() {
    scanTimer?.cancel();
    xrealEyeTimer?.cancel();
    unawaited(_xrealEyeChannel.invokeMethod<void>('stop'));
    manual.dispose();
    unawaited(camera?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = camera;
    final hasXrealEye = cameras.any(_isXrealEyeCamera);
    final compact = MediaQuery.sizeOf(context).width < 520;
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: compact
              ? SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('xreal-eye-camera'),
                    onPressed: _toggleXrealEye,
                    icon: Icon(
                      xrealEyeMode
                          ? Icons.stop_rounded
                          : Icons.videocam_rounded,
                    ),
                    label: Text(
                      xrealEyeMode ? 'Stop XREAL Eye' : 'Start XREAL Eye',
                    ),
                  ),
                )
              : Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'XREAL Eye capture',
                        style: TextStyle(
                          color: Color(0xff929aac),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('xreal-eye-camera'),
                      onPressed: _toggleXrealEye,
                      icon: Icon(
                        xrealEyeMode
                            ? Icons.stop_rounded
                            : Icons.videocam_rounded,
                      ),
                      label: Text(
                        xrealEyeMode ? 'Stop XREAL Eye' : 'Start XREAL Eye',
                      ),
                    ),
                  ],
                ),
        ),
        if (hasXrealEye)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'XREAL Eye camera detected and prioritized.',
              style: TextStyle(color: Color(0xff929aac), fontSize: 12),
            ),
          ),
        if (cameras.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const Key('windows-camera-selector'),
                    initialValue: selectedCamera,
                    decoration: const InputDecoration(
                      labelText: 'Camera',
                      prefixIcon: Icon(Icons.videocam_outlined),
                    ),
                    items: [
                      for (var index = 0; index < cameras.length; index++)
                        DropdownMenuItem(
                          value: index,
                          child: Text(
                            _cameraDisplayName(cameras[index].name),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: initializing
                        ? null
                        : (value) {
                            if (value != null && value != selectedCamera) {
                              unawaited(_startCamera(value));
                            }
                          },
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    key: const Key('cycle-windows-camera'),
                    tooltip: 'Switch camera',
                    onPressed: cameras.length < 2 || initializing
                        ? null
                        : _cycleCamera,
                    icon: const Icon(Icons.cameraswitch_rounded),
                  ),
                ],
              ],
            ),
          ),
        if (compact)
          SizedBox(
            width: double.infinity,
            height:
                MediaQuery.sizeOf(context).width /
                (active?.value.aspectRatio ?? (16 / 9)),
            child: _cameraPreview(active),
          )
        else
          Expanded(child: _cameraPreview(active)),
        if (compact && cameras.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Align(
              alignment: Alignment.center,
              child: FractionallySizedBox(
                widthFactor: .45,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: FilledButton.tonal(
                    key: const Key('cycle-windows-camera'),
                    onPressed: initializing ? null : _cycleCamera,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cameraswitch_rounded, size: 58),
                        SizedBox(height: 12),
                        Text('Switch camera'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (error != null && active != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        _ManualCode(
          controller: manual,
          onCode: (code) => widget.onCode(code, null),
        ),
      ],
    );
    return compact ? SingleChildScrollView(child: content) : content;
  }
}

class _LinuxCameraScanner extends StatefulWidget {
  const _LinuxCameraScanner({
    required this.onCode,
    required this.mode,
    required this.captureMode,
    this.onLabelCapture,
  });
  final void Function(String code, Uint8List? imageBytes) onCode;
  final ScanMode mode;
  final ScanCaptureMode captureMode;
  final LabelCaptureCallback? onLabelCapture;

  @override
  State<_LinuxCameraScanner> createState() => _LinuxCameraScannerState();
}

class _LinuxCameraScannerState extends State<_LinuxCameraScanner> {
  final manual = TextEditingController();
  List<String> devices = const [];
  final Map<String, String> deviceLabels = {};
  String? device;
  Uint8List? frame;
  Process? cameraProcess;
  StreamSubscription<List<int>>? cameraOutput;
  final List<int> streamBuffer = [];
  DateTime lastDecode = DateTime.fromMillisecondsSinceEpoch(0);
  bool decoding = false;
  bool delivered = false;
  Future<void>? focusOperation;
  bool focusing = false;
  bool focusLocked = false;
  bool fixedFocus = false;
  // Device controls changed for scanning, with the values to restore once
  // the scanner releases that camera.
  final Map<String, Map<String, int>> restoreControls = {};
  String? error;

  @override
  void initState() {
    super.initState();
    _findCameras();
  }

  Future<Map<String, ({int minimum, int maximum, int value})>> _readControls(
    String path,
  ) async {
    final output = await Process.run('v4l2-ctl', [
      '--device=$path',
      '--list-ctrls',
    ]);
    return {
      for (final match in RegExp(
        r'^\s*(\w+)\s+0x[0-9a-f]+\s+\((?:int|bool)\)\s*:'
        r'(?:\s*min=(-?\d+)\s+max=(-?\d+))?.*?\svalue=(-?\d+)',
        multiLine: true,
      ).allMatches(output.stdout.toString()))
        match.group(1)!: (
          minimum: int.parse(match.group(2) ?? '0'),
          maximum: int.parse(match.group(3) ?? '1'),
          value: int.parse(match.group(4)!),
        ),
    };
  }

  /// Tunes fixed-focus webcams for reading codes.
  ///
  /// Cameras like the Logitech C270 have no focus motor and ship with very
  /// light in-camera sharpening, and auto exposure may stretch frames to
  /// 66 ms in room light, smearing a handheld code. Sharpening before MJPEG
  /// compression and holding exposure to one frame time keep module edges
  /// crisp enough for ZXing.
  Future<void> _applyFixedFocusScanControls(
    String path,
    Map<String, ({int minimum, int maximum, int value})> controls,
  ) async {
    final changes = <String, int>{};
    final sharpness = controls['sharpness'];
    if (sharpness != null) {
      final target =
          sharpness.minimum +
          ((sharpness.maximum - sharpness.minimum) * .75).round();
      if (sharpness.value < target) changes['sharpness'] = target;
    }
    if (controls['exposure_dynamic_framerate']?.value == 1) {
      changes['exposure_dynamic_framerate'] = 0;
    }
    if (changes.isEmpty) return;
    restoreControls[path] = {
      for (final name in changes.keys) name: controls[name]!.value,
    };
    await _setControls(path, changes);
  }

  Future<void> _setControls(
    String path,
    Map<String, int> values,
  ) => Process.run('v4l2-ctl', [
    '--device=$path',
    '--set-ctrl=${values.entries.map((e) => '${e.key}=${e.value}').join(',')}',
  ]);

  Future<void> _restoreScanControls() async {
    final pending = Map.of(restoreControls);
    restoreControls.clear();
    for (final entry in pending.entries) {
      try {
        await _setControls(entry.key, entry.value);
      } catch (_) {
        // The camera may already be unplugged.
      }
    }
  }

  @override
  void didUpdateWidget(covariant _LinuxCameraScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.captureMode != widget.captureMode) {
      delivered = false;
    }
  }

  Future<void> _findCameras() async {
    try {
      final candidates = await Directory('/dev')
          .list()
          .where((entry) => RegExp(r'/video\d+$').hasMatch(entry.path))
          .map((entry) => entry.path)
          .toList();
      final entries = <String>[];
      for (final path in candidates) {
        final formats = await Process.run('v4l2-ctl', [
          '--device=$path',
          '--list-formats-ext',
        ]);
        // UVC cameras expose a second /dev/video node containing metadata.
        // It looks camera-like but cannot produce frames, so only retain nodes
        // for which V4L2 can enumerate actual pixel formats.
        if (formats.exitCode != 0 ||
            !formats.stdout.toString().contains(RegExp(r"'....'"))) {
          continue;
        }
        final info = await Process.run('v4l2-ctl', [
          '--device=$path',
          '--info',
        ]);
        final card = RegExp(
          r'^\s*Card type\s*:\s*(.+)$',
          multiLine: true,
        ).firstMatch(info.stdout.toString())?.group(1)?.trim();
        deviceLabels[path] = card == null ? path : _cameraDisplayName(card);
        entries.add(path);
      }
      entries.sort((a, b) {
        final aVirtual =
            deviceLabels[a]?.toLowerCase().contains('obs') ?? false;
        final bVirtual =
            deviceLabels[b]?.toLowerCase().contains('obs') ?? false;
        if (aVirtual != bVirtual) return aVirtual ? 1 : -1;
        return a.compareTo(b);
      });
      if (!mounted) return;
      setState(() {
        devices = entries;
        device = entries.firstOrNull;
        error = entries.isEmpty ? 'No Linux webcam was found.' : null;
      });
      if (device != null) {
        await _startCamera();
      }
    } catch (exception) {
      if (mounted) setState(() => error = 'Could not list webcams: $exception');
    }
  }

  Future<void> _startCamera() async {
    await _stopCamera();
    if (delivered || device == null) return;
    streamBuffer.clear();
    focusLocked = false;
    try {
      final process = await Process.start('ffmpeg', [
        '-loglevel',
        'error',
        '-f',
        'v4l2',
        '-input_format',
        'mjpeg',
        '-video_size',
        '1280x720',
        '-framerate',
        '30',
        '-i',
        device!,
        '-an',
        '-f',
        'image2pipe',
        '-c:v',
        'copy',
        '-',
      ]);
      cameraProcess = process;
      cameraOutput = process.stdout.listen(_acceptCameraBytes);
      final path = device!;
      final controls = await _readControls(path);
      final hasFocusMotor = controls.containsKey('focus_absolute');
      if (mounted) setState(() => fixedFocus = !hasFocusMotor);
      if (hasFocusMotor) {
        unawaited(_refocusCamera());
      } else {
        await _applyFixedFocusScanControls(path, controls);
      }
      final errors = StringBuffer();
      process.stderr
          .transform(const SystemEncoding().decoder)
          .listen(errors.write);
      unawaited(
        process.exitCode.then((exitCode) {
          if (!mounted || cameraProcess != process || exitCode == 0) return;
          setState(() {
            error = 'Camera stopped: ${errors.toString().trim()}';
          });
        }),
      );
    } catch (exception) {
      if (mounted) setState(() => error = 'Camera error: $exception');
    }
  }

  void _acceptCameraBytes(List<int> chunk) {
    streamBuffer.addAll(chunk);
    while (true) {
      final start = _markerIndex(streamBuffer, 0xff, 0xd8);
      if (start < 0) {
        if (streamBuffer.length > 1) {
          streamBuffer.removeRange(0, streamBuffer.length - 1);
        }
        return;
      }
      final end = _markerIndex(streamBuffer, 0xff, 0xd9, start + 2);
      if (end < 0) {
        if (start > 0) streamBuffer.removeRange(0, start);
        return;
      }
      final bytes = jpegWithStandardHuffmanTables(
        Uint8List.fromList(streamBuffer.sublist(start, end + 2)),
      );
      streamBuffer.removeRange(0, end + 2);
      if (!mounted) return;
      setState(() {
        frame = bytes;
        error = null;
      });
      final now = DateTime.now();
      if (widget.captureMode == ScanCaptureMode.barcode &&
          !focusing &&
          !decoding &&
          now.difference(lastDecode) >= const Duration(milliseconds: 250)) {
        lastDecode = now;
        decoding = true;
        unawaited(_scanFrame(bytes));
      }
    }
  }

  int _markerIndex(List<int> bytes, int first, int second, [int start = 0]) {
    for (var index = start; index < bytes.length - 1; index++) {
      if (bytes[index] == first && bytes[index + 1] == second) return index;
    }
    return -1;
  }

  Future<void> _scanFrame(Uint8List bytes) async {
    try {
      String? code;
      try {
        code = widget.mode == ScanMode.ingest
            ? await compute(decodeProductBarcodeFrame, bytes)
            : await compute(decodeInventoryQrFrame, bytes);
      } catch (exception) {
        debugPrint('Native barcode decoder error: $exception');
      }
      code ??= await compute(_decodeQrFrame, bytes);
      if (code != null && !delivered) {
        delivered = true;
        widget.onCode(code, bytes);
        // A matched code closes the scanner. If it is still open, the code
        // was rejected (no matching item), so keep looking after the
        // message has had a moment to show.
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) delivered = false;
          }),
        );
      }
    } finally {
      decoding = false;
    }
  }

  Future<void> _stopCamera() async {
    final process = cameraProcess;
    cameraProcess = null;
    process?.kill();
    if (process != null) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
    await cameraOutput?.cancel();
    cameraOutput = null;
    await _restoreScanControls();
  }

  void _cycleCamera() {
    if (devices.length < 2 || device == null) return;
    final next = (devices.indexOf(device!) + 1) % devices.length;
    setState(() {
      device = devices[next];
      frame = null;
      focusLocked = false;
    });
    unawaited(_startCamera());
  }

  @override
  void dispose() {
    cameraOutput?.cancel();
    cameraProcess?.kill();
    unawaited(_restoreScanControls());
    manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.f1): _refocusCamera},
    child: Focus(
      autofocus: true,
      child: Column(
        children: [
          if (devices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: device,
                      decoration: const InputDecoration(labelText: 'Webcam'),
                      items: devices
                          .map(
                            (path) => DropdownMenuItem(
                              value: path,
                              child: Text(deviceLabels[path] ?? path),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          device = value;
                          frame = null;
                          focusLocked = false;
                        });
                        _startCamera();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    key: const Key('cycle-linux-camera'),
                    tooltip: 'Switch camera',
                    onPressed: devices.length < 2 ? null : _cycleCamera,
                    icon: const Icon(Icons.cameraswitch_rounded),
                  ),
                ],
              ),
            ),
          if (devices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  if (fixedFocus)
                    const Tooltip(
                      message:
                          'This webcam cannot refocus. Codes held too close '
                          'blur; a smaller, sharp code still scans.',
                      child: Chip(
                        key: Key('fixed-focus-camera'),
                        avatar: Icon(Icons.center_focus_weak_rounded),
                        label: Text('Fixed focus'),
                      ),
                    )
                  else
                    Tooltip(
                      message: focusLocked
                          ? 'Focus is locked. Press F1 to run another sweep.'
                          : 'Run an autofocus sweep and lock the sharpest point.',
                      child: OutlinedButton.icon(
                        key: const Key('refocus-camera'),
                        onPressed: focusing ? null : _refocusCamera,
                        icon: focusing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.center_focus_strong_rounded),
                        label: Text(focusing ? 'Focusing…' : 'Refocus · F1'),
                      ),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.mode == ScanMode.ingest
                          ? widget.captureMode == ScanCaptureMode.barcode
                                ? 'Fill the wide guide with the bars; leave white space at both ends.'
                                : 'Fill the view with the label, press F1 to refocus, then click the camera.'
                          : fixedFocus
                          ? 'Hold the QR back until its edges look crisp; it can sit inside the guide.'
                          : 'Fill the square guide with the QR code.',
                      style: const TextStyle(
                        color: Color(0xff929aac),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: frame == null
                ? Center(child: Text(error ?? 'Starting webcam…'))
                : GestureDetector(
                    key: const Key('scanner-camera-surface'),
                    behavior: HitTestBehavior.opaque,
                    onTap:
                        widget.mode == ScanMode.ingest &&
                            widget.captureMode == ScanCaptureMode.ocr &&
                            widget.onLabelCapture != null
                        ? _captureFocusedLabel
                        : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          frame!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                        _ScanGuide(wide: widget.mode == ScanMode.ingest),
                      ],
                    ),
                  ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          _ManualCode(
            controller: manual,
            onCode: (code) => widget.onCode(code, null),
          ),
        ],
      ),
    ),
  );

  Future<void> _captureFocusedLabel() async {
    final activeFocus = focusOperation;
    if (activeFocus != null) await activeFocus;
    final path = device;
    if (path == null || widget.onLabelCapture == null) return;
    await Process.run('v4l2-ctl', [
      '--device=$path',
      '--set-ctrl=focus_automatic_continuous=0',
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final focusedFrame = frame;
    if (focusedFrame != null) {
      await widget.onLabelCapture!(focusedFrame);
    }
  }

  Future<void> _refocusCamera() {
    if (fixedFocus) return Future.value();
    final active = focusOperation;
    if (active != null) return active;
    final operation = _runRefocusCamera();
    focusOperation = operation;
    return operation.whenComplete(() => focusOperation = null);
  }

  Future<void> _runRefocusCamera() async {
    final path = device;
    if (path == null) return;
    if (mounted) {
      setState(() {
        focusing = true;
        focusLocked = false;
      });
    }
    try {
      final controls = await Process.run('v4l2-ctl', [
        '--device=$path',
        '--list-ctrls',
      ]);
      final focus = RegExp(
        r'focus_absolute[^:]*:\s*min=(\d+)\s+max=(\d+)\s+step=(\d+).*value=(\d+)',
      ).firstMatch(controls.stdout.toString());
      await Process.run('v4l2-ctl', [
        '--device=$path',
        '--set-ctrl=focus_automatic_continuous=0',
      ]);
      if (focus != null) {
        final minimum = int.parse(focus.group(1)!);
        final maximum = int.parse(focus.group(2)!);
        final step = int.parse(focus.group(3)!);
        final coarseSpacing = ((maximum - minimum) / 8).round();
        final coarse = <int>{
          for (var index = 0; index <= 8; index++)
            _snapFocus(minimum + coarseSpacing * index, minimum, maximum, step),
        };
        final scores = <int, double>{};
        for (final position in coarse) {
          scores[position] = await _measureFocus(path, position);
        }
        var best = scores.entries.reduce(
          (left, right) => left.value >= right.value ? left : right,
        );
        final refineRadius = (coarseSpacing / 2).round();
        final refine = <int>{
          for (final offset in [
            -refineRadius,
            -step * 2,
            0,
            step * 2,
            refineRadius,
          ])
            _snapFocus(best.key + offset, minimum, maximum, step),
        }..removeAll(scores.keys);
        for (final position in refine) {
          scores[position] = await _measureFocus(path, position);
          if (scores[position]! > best.value) {
            best = MapEntry(position, scores[position]!);
          }
        }
        await _setManualFocus(path, best.key);
        await Future<void>.delayed(const Duration(milliseconds: 240));
        focusLocked = true;
      } else {
        await Process.run('v4l2-ctl', [
          '--device=$path',
          '--set-ctrl=focus_automatic_continuous=1',
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 1000));
        await Process.run('v4l2-ctl', [
          '--device=$path',
          '--set-ctrl=focus_automatic_continuous=0',
        ]);
        focusLocked = true;
      }
    } catch (exception) {
      debugPrint('Camera autofocus failed: $exception');
    } finally {
      if (mounted) setState(() => focusing = false);
    }
  }

  int _snapFocus(int value, int minimum, int maximum, int step) {
    final clamped = value.clamp(minimum, maximum);
    return minimum + (((clamped - minimum) / step).round() * step);
  }

  Future<void> _setManualFocus(String path, int position) async {
    await Process.run('v4l2-ctl', [
      '--device=$path',
      '--set-ctrl=focus_absolute=$position',
    ]);
  }

  Future<double> _measureFocus(String path, int position) async {
    await _setManualFocus(path, position);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final sample = frame;
    return sample == null ? 0 : compute(focusSharpnessScore, sample);
  }
}

double focusSharpnessScore(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return 0;
  final scaled = decoded.width > 360
      ? img.copyResize(
          decoded,
          width: 360,
          interpolation: img.Interpolation.linear,
        )
      : decoded;
  final x0 = (scaled.width * .1).round();
  final y0 = (scaled.height * .1).round();
  final x1 = (scaled.width * .9).round();
  final y1 = (scaled.height * .9).round();
  var score = 0.0;
  var samples = 0;
  for (var y = y0 + 1; y < y1 - 1; y += 2) {
    for (var x = x0 + 1; x < x1 - 1; x += 2) {
      final center = scaled.getPixel(x, y).luminanceNormalized;
      final laplacian =
          4 * center -
          scaled.getPixel(x - 1, y).luminanceNormalized -
          scaled.getPixel(x + 1, y).luminanceNormalized -
          scaled.getPixel(x, y - 1).luminanceNormalized -
          scaled.getPixel(x, y + 1).luminanceNormalized;
      score += laplacian * laplacian;
      samples++;
    }
  }
  return samples == 0 ? 0 : score / samples;
}

/// Inserts the standard JPEG Huffman tables into a webcam MJPEG frame.
///
/// UVC webcams such as the Logitech C270 omit the DHT segment and rely on
/// decoders supplying the Annex K defaults. Flutter's preview does, but the
/// `image` package cannot decode such frames, so no barcode was ever read.
@visibleForTesting
Uint8List jpegWithStandardHuffmanTables(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return bytes;
  var index = 2;
  while (index + 4 <= bytes.length && bytes[index] == 0xff) {
    final marker = bytes[index + 1];
    if (marker == 0xc4) return bytes;
    if (marker == 0xda) {
      return Uint8List(bytes.length + _standardHuffmanTables.length)
        ..setRange(0, index, bytes)
        ..setAll(index, _standardHuffmanTables)
        ..setRange(
          index + _standardHuffmanTables.length,
          bytes.length + _standardHuffmanTables.length,
          bytes,
          index,
        );
    }
    index += 2 + (bytes[index + 2] << 8 | bytes[index + 3]);
  }
  return bytes;
}

// ITU T.81 Annex K.3 tables, as one DHT segment.
// dart format off
const _standardHuffmanTables = <int>[
  0xff, 0xc4, 0x01, 0xa2,
  // DC luminance
  0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06,
  0x07, 0x08, 0x09, 0x0a, 0x0b,
  // AC luminance
  0x10, 0x00, 0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04,
  0x04, 0x00, 0x00, 0x01, 0x7d, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05,
  0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14,
  0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1,
  0xf0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19,
  0x1a, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38,
  0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54,
  0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
  0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84,
  0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97,
  0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa,
  0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4,
  0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7,
  0xd8, 0xd9, 0xda, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9,
  0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa,
  // DC chrominance
  0x01, 0x00, 0x03, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06,
  0x07, 0x08, 0x09, 0x0a, 0x0b,
  // AC chrominance
  0x11, 0x00, 0x02, 0x01, 0x02, 0x04, 0x04, 0x03, 0x04, 0x07, 0x05, 0x04,
  0x04, 0x00, 0x01, 0x02, 0x77, 0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05,
  0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32,
  0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52,
  0xf0, 0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1,
  0x17, 0x18, 0x19, 0x1a, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37,
  0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53,
  0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67,
  0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82,
  0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95,
  0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8,
  0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2,
  0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5,
  0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8,
  0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa,
];
// dart format on

String? _decodeBarcodeFrame(Uint8List bytes, int format) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  return _decodeBarcodeImage(image, format) ??
      _decodeSharpenedImage(image, format);
}

String? decodeAnyBarcodeFrame(Uint8List bytes) =>
    _decodeBarcodeFrame(bytes, zxing.Format.any);

/// Reads only QR codes, which is all Find mode can match.
///
/// Noisy webcam frames (the Logitech C270 in room light especially) make
/// ZXing report phantom GS1 DataBar values; one of those ended a desktop scan
/// before the real QR was ever read.
String? decodeInventoryQrFrame(Uint8List bytes) =>
    _decodeBarcodeFrame(bytes, zxing.Format.qrCode);

// GS1 DataBar is for produce and coupons, and webcam noise decodes as it.
const _productLinearCodes =
    zxing.Format.linearCodes &
    ~(zxing.Format.dataBar | zxing.Format.dataBarExpanded);

String? decodeProductBarcodeFrame(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;

  final fullFrame = _decodeBarcodeImage(image, _productLinearCodes);
  if (fullFrame != null) return fullFrame;

  final crop = img.copyCrop(
    image,
    x: (image.width * .03).round(),
    y: (image.height * .23).round(),
    width: (image.width * .94).round(),
    height: (image.height * .54).round(),
  );
  final focusedCode128 = _decodeBarcodeImage(crop, zxing.Format.code128);
  if (focusedCode128 != null) return focusedCode128;

  final focusedLinear = _decodeBarcodeImage(crop, _productLinearCodes);
  if (focusedLinear != null) return focusedLinear;

  final enhanced = img.adjustColor(
    img.Image.from(crop),
    contrast: 1.55,
    saturation: 0,
  );
  final enhancedCode128 = _decodeBarcodeImage(enhanced, zxing.Format.code128);
  if (enhancedCode128 != null) return enhancedCode128;

  for (final angle in const [-8, 8, -14, 14]) {
    final deskewed = img.copyRotate(enhanced, angle: angle);
    final result = _decodeBarcodeImage(deskewed, zxing.Format.code128);
    if (result != null) return result;
  }
  return _decodeSharpenedImage(
    image,
    _productLinearCodes | zxing.Format.qrCode,
  );
}

/// Retries a soft frame after an unsharp mask.
///
/// Fixed-focus webcams such as the Logitech C270 blur codes held close to the
/// lens, and ZXing's binarizer loses module edges once the blur approaches
/// half a module. Restoring edge contrast recovers roughly another blur step
/// without asking the user to hold the code perfectly still at the ideal
/// distance.
String? _decodeSharpenedImage(img.Image image, int format) {
  final normalized = image.convert(numChannels: 3);
  final width = normalized.width;
  final height = normalized.height;
  final rgb = normalized.getBytes(order: img.ChannelOrder.rgb);
  final luminance = Uint8List(width * height);
  for (var index = 0, pixel = 0; index < luminance.length; index++) {
    luminance[index] =
        (rgb[pixel++] * 77 + rgb[pixel++] * 150 + rgb[pixel++] * 29) >> 8;
  }
  for (final (radius, amount) in const [(4, 2.5), (2, 1.5)]) {
    final result = zxing.zx.readBarcode(
      unsharpLuminance(luminance, width, height, radius, amount),
      zxing.DecodeParams(
        imageFormat: zxing.ImageFormat.lum,
        width: width,
        height: height,
        format: format,
        tryHarder: true,
        tryRotate: true,
        tryInverted: true,
        tryDownscale: false,
        maxSize: 2048,
      ),
    );
    final text = result.text?.trim();
    if (result.isValid && text?.isNotEmpty == true) return text;
  }
  return null;
}

/// Sharpens an 8-bit luminance plane with an unsharp mask.
///
/// Two separable box-blur passes approximate a Gaussian of [radius] cheaply
/// enough to run on every scanned webcam frame.
@visibleForTesting
Uint8List unsharpLuminance(
  Uint8List luminance,
  int width,
  int height,
  int radius,
  double amount,
) {
  var blurred = Uint16List.fromList(luminance);
  var scratch = Uint16List(blurred.length);
  for (var pass = 0; pass < 2; pass++) {
    _boxBlur(blurred, scratch, width, height, radius, horizontal: true);
    _boxBlur(scratch, blurred, width, height, radius, horizontal: false);
  }
  final sharpened = Uint8List(luminance.length);
  for (var index = 0; index < luminance.length; index++) {
    final value = luminance[index];
    sharpened[index] = (value + amount * (value - blurred[index]))
        .round()
        .clamp(0, 255);
  }
  return sharpened;
}

void _boxBlur(
  Uint16List source,
  Uint16List target,
  int width,
  int height,
  int radius, {
  required bool horizontal,
}) {
  final lines = horizontal ? height : width;
  final length = horizontal ? width : height;
  final stride = horizontal ? 1 : width;
  final window = radius * 2 + 1;
  for (var line = 0; line < lines; line++) {
    final start = horizontal ? line * width : line;
    int at(int offset) => source[start + offset.clamp(0, length - 1) * stride];
    var sum = 0;
    for (var offset = -radius; offset <= radius; offset++) {
      sum += at(offset);
    }
    for (var offset = 0; offset < length; offset++) {
      target[start + offset * stride] = sum ~/ window;
      sum += at(offset + radius + 1) - at(offset - radius);
    }
  }
}

String? _decodeBarcodeImage(img.Image image, int format) {
  // Some MJPEG cameras produce frames with padded/internal channel layouts.
  // Normalize before handing a tightly packed RGB buffer to native ZXing.
  final normalized = image.convert(numChannels: 3);
  final pixels = normalized.getBytes(order: img.ChannelOrder.rgb);
  final result = zxing.zx.readBarcode(
    pixels,
    zxing.DecodeParams(
      imageFormat: zxing.ImageFormat.rgb,
      width: normalized.width,
      height: normalized.height,
      format: format,
      tryHarder: true,
      tryRotate: true,
      tryInverted: true,
      tryDownscale: false,
      maxSize: 2048,
    ),
  );
  final text = result.text?.trim();
  return result.isValid && text?.isNotEmpty == true ? text : null;
}

String? _decodeQrFrame(Uint8List bytes) {
  try {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final rgba = image
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.rgba);
    final source = RGBLuminanceSource(
      image.width,
      image.height,
      rgba.buffer.asInt32List(rgba.offsetInBytes, rgba.lengthInBytes ~/ 4),
    );
    return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text;
  } catch (_) {
    return null;
  }
}

class _UnsupportedScanner extends StatelessWidget {
  const _UnsupportedScanner({required this.onCode});
  final ValueChanged<String> onCode;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 420,
      child: _ManualCode(controller: TextEditingController(), onCode: onCode),
    ),
  );
}

class _ManualCode extends StatelessWidget {
  const _ManualCode({required this.controller, required this.onCode});
  final TextEditingController controller;
  final ValueChanged<String> onCode;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('manual-qr-code'),
            controller: controller,
            onSubmitted: onCode,
            decoration: const InputDecoration(
              labelText: 'Or enter the item ID / QR text',
              prefixIcon: Icon(Icons.keyboard_alt_outlined),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => onCode(controller.text),
          child: const Text('Open'),
        ),
      ],
    ),
  );
}

class _ScanGuide extends StatelessWidget {
  const _ScanGuide({this.wide = false});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final width = wide
        ? (MediaQuery.sizeOf(context).width * .82).clamp(260.0, 440.0)
        : 260.0;
    return IgnorePointer(
      child: Center(
        child: Container(
          width: width,
          height: wide ? width * .43 : 260,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xff9c83ff), width: 4),
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
    );
  }
}
