import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'supplier_image_url.dart';

class SupplierImage {
  const SupplierImage(this.bytes, this.thumbnail);
  final Uint8List bytes, thumbnail;
  int get size => bytes.length + thumbnail.length;
}

SupplierImage? _resize(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 16000000) return null;
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) return null;
  img.Image fit(int size) => decoded.width <= size && decoded.height <= size
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? size : null,
          height: decoded.height > decoded.width ? size : null,
        );
  return SupplierImage(img.encodePng(fit(1024)), img.encodePng(fit(256)));
}

/// Bounded, credential-free CDN requests. Successes and failures are cached;
/// concurrent requests for the same image share a single download.
class SupplierImageCache {
  SupplierImageCache({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  static SupplierImageCache shared = SupplierImageCache();
  final http.Client Function() _clientFactory;
  final _cache = <String, (DateTime, SupplierImage?)>{};
  final _pending = <String, Future<SupplierImage?>>{};
  final _queue = Queue<(String, void Function())>();
  int _active = 0, _bytes = 0;
  static const maxDownloadBytes = 6 * 1024 * 1024;
  static const maxCacheBytes = 12 * 1024 * 1024;

  SupplierImage? peek(String url) => _cache[supplierImageUrl(url)]?.$2;

  Future<SupplierImage?> load(String url, {bool priority = false}) {
    final key = supplierImageUrl(url);
    if (key.isEmpty) return Future.value(null);
    final cached = _cache.remove(key);
    if (cached != null) {
      if (DateTime.now().difference(cached.$1) < const Duration(minutes: 10)) {
        _cache[key] = cached;
        return Future.value(cached.$2);
      }
      _bytes -= cached.$2?.size ?? 0;
    }
    if (_pending.containsKey(key)) {
      if (priority) {
        final queued = _queue.where((job) => job.$1 == key).firstOrNull;
        if (queued != null) {
          _queue.remove(queued);
          _queue.addFirst(queued);
        }
      }
      return _pending[key]!;
    }
    // Bound the queue as well as retained image bytes.
    if (_pending.length >= 48) return Future.value(null);
    final result = Completer<SupplierImage?>();
    _pending[key] = result.future;
    void run() async {
      SupplierImage? image;
      try {
        image = await _download(key);
      } catch (_) {
        /* Optional image. */
      }
      _cache[key] = (DateTime.now(), image);
      _bytes += image?.size ?? 0;
      while (_cache.length > 48 || _bytes > maxCacheBytes) {
        _bytes -= _cache.remove(_cache.keys.first)?.$2?.size ?? 0;
      }
      _pending.remove(key);
      result.complete(image);
      _active--;
      _pump();
    }

    if (priority) {
      _queue.addFirst((key, run));
    } else {
      _queue.add((key, run));
    }
    _pump();
    return result.future;
  }

  void _pump() {
    while (_active < 2 && _queue.isNotEmpty) {
      _active++;
      _queue.removeFirst().$2();
    }
  }

  Future<SupplierImage?> _download(String url) async {
    final client = _clientFactory();
    Future<SupplierImage?> read() async {
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = false
        ..headers['Accept'] = 'image/png,image/jpeg,image/webp,image/gif';
      final response = await client.send(request);
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > maxDownloadBytes) {
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxDownloadBytes) return null;
        bytes.add(chunk);
      }
      return compute(_resize, bytes.takeBytes());
    }

    try {
      return await read().timeout(const Duration(seconds: 15));
    } finally {
      client.close();
    }
  }
}

class SupplierImagePreview extends StatefulWidget {
  const SupplierImagePreview({super.key, required this.url});
  final String url;
  @override
  State<SupplierImagePreview> createState() => _SupplierImagePreviewState();
}

class _SupplierImagePreviewState extends State<SupplierImagePreview> {
  ScrollPosition? _position;
  Future<Uint8List?>? _image;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.removeListener(_schedule);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(SupplierImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _image = null;
      _schedule();
    }
  }

  void _schedule() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || widget.url.isEmpty) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final RenderObject? viewport = RenderAbstractViewport.maybeOf(box);
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    final visible = viewport is RenderBox
        ? viewport.localToGlobal(Offset.zero) & viewport.size
        : Offset.zero & MediaQuery.sizeOf(context);
    if (!bounds.overlaps(visible)) {
      if (_image != null) setState(() => _image = null);
      return;
    }
    if (_image == null) {
      setState(() {
        _image = SupplierImageCache.shared
            .load(widget.url)
            .then((image) => image?.bytes);
      });
    }
  });
  @override
  void dispose() {
    _position?.removeListener(_schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.url.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _image == null
                  ? Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    )
                  : FutureBuilder<Uint8List?>(
                      future: _image,
                      builder: (context, snapshot) => snapshot.data == null
                          ? Center(
                              child: Icon(
                                Icons.image_outlined,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            )
                          : InkWell(
                              onTap: () => showDialog<void>(
                                context: context,
                                builder: (context) => Dialog(
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: InteractiveViewer(
                                          minScale: 1,
                                          maxScale: 5,
                                          child: Image.memory(
                                            snapshot.data!,
                                            fit: BoxFit.contain,
                                            width: double.infinity,
                                            height: double.infinity,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: IconButton.filledTonal(
                                          tooltip: 'Close image',
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          icon: const Icon(Icons.close),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              child: Image.memory(
                                snapshot.data!,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                                semanticLabel: 'Product image. Tap to zoom',
                                gaplessPlayback: true,
                              ),
                            ),
                    ),
            ),
          ),
        );
}

/// Finish the optional photo before returning to the editor, so Save cannot
/// race an image download. Failed images never prevent importing the part.
class SupplierUsePartButton extends StatefulWidget {
  const SupplierUsePartButton({
    super.key,
    required this.imageUrl,
    required this.onSelected,
  });
  final String imageUrl;
  final VoidCallback onSelected;
  @override
  State<SupplierUsePartButton> createState() => _SupplierUsePartButtonState();
}

class _SupplierUsePartButtonState extends State<SupplierUsePartButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
    onPressed: _busy
        ? null
        : () async {
            setState(() => _busy = true);
            await SupplierImageCache.shared.load(
              widget.imageUrl,
              priority: true,
            );
            if (mounted) widget.onSelected();
          },
    child: Text(_busy ? 'Loading image…' : 'Use this part'),
  );
}
