import 'dart:async';
import 'dart:io';

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
  final controller = MobileScannerController(
    returnImage: true,
    autoZoom: true,
    cameraResolution: const Size(1920, 1080),
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
                widget.onCode(value, capture.image);
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
        ResolutionPreset.max,
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
              : await compute(decodeAnyBarcodeFrame, frame);
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
      final found = (await availableCameras()).toList()
        ..sort(_compareWindowsCameras);
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
            : await compute(decodeAnyBarcodeFrame, bytes);
      } catch (exception) {
        debugPrint('Windows barcode decoder error: $exception');
      }
      code ??= await compute(_decodeQrFrame, bytes);
      if (code != null && !delivered) {
        delivered = true;
        widget.onCode(code, bytes);
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
    return Column(
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
        Expanded(
          child: xrealEyeMode && xrealEyeImage != null
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
                        fit: BoxFit.contain,
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
                      if (capturing &&
                          widget.captureMode == ScanCaptureMode.ocr)
                        const ColoredBox(
                          color: Color(0x33000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                ),
        ),
        if (compact && cameras.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                key: const Key('cycle-windows-camera'),
                onPressed: initializing ? null : _cycleCamera,
                icon: const Icon(Icons.cameraswitch_rounded),
                label: const Text('Switch camera'),
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
  String? error;

  @override
  void initState() {
    super.initState();
    _findCameras();
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
      unawaited(_refocusCamera());
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
      final bytes = Uint8List.fromList(streamBuffer.sublist(start, end + 2));
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
            : await compute(decodeAnyBarcodeFrame, bytes);
      } catch (exception) {
        debugPrint('Native barcode decoder error: $exception');
      }
      code ??= await compute(_decodeQrFrame, bytes);
      if (code != null && !delivered) {
        delivered = true;
        widget.onCode(code, bytes);
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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

String? _decodeBarcodeFrame(Uint8List bytes, int format) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  return _decodeBarcodeImage(image, format);
}

String? decodeAnyBarcodeFrame(Uint8List bytes) =>
    _decodeBarcodeFrame(bytes, zxing.Format.any);

String? decodeProductBarcodeFrame(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;

  final fullFrame = _decodeBarcodeImage(image, zxing.Format.linearCodes);
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

  final focusedLinear = _decodeBarcodeImage(crop, zxing.Format.linearCodes);
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
  return null;
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
