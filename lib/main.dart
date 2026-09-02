import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'local_database.dart';
import 'device_name_dialog.dart';
import 'filament_colors.dart';
import 'kit_package.dart';
import 'label_ocr.dart';
import 'qr_scanner.dart';
import 'cloud_sync_dialog.dart';
import 'supabase_sync.dart';
import 'sync_onboarding_dialog.dart';
import 'workshop_delta.dart';

// A single explicit very-dark violet canvas across every platform. Keeping the
// green channel lowest prevents the background from drifting teal/green.
const Color _appCanvasColor = Color(0xff120d1c);

class _ShoppingCartIcon extends StatelessWidget {
  const _ShoppingCartIcon({super.key}) : remove = false;
  const _ShoppingCartIcon.remove({super.key}) : remove = true;

  final bool remove;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 24,
    child: CustomPaint(
      painter: _ShoppingCartPainter(
        color:
            IconTheme.of(context).color ??
            Theme.of(context).colorScheme.onSurface,
        remove: remove,
      ),
    ),
  );
}

class _ShoppingCartPainter extends CustomPainter {
  const _ShoppingCartPainter({required this.color, required this.remove});

  final Color color;
  final bool remove;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..isAntiAlias = true
      ..color = color.withValues(alpha: .9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(2.5, 3.5)
        ..lineTo(5, 3.5)
        ..lineTo(7.5, 15.5)
        ..quadraticBezierTo(7.8, 17, 9.2, 17)
        ..lineTo(19, 17),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(6, 6.5)
        ..lineTo(21, 6.5)
        ..lineTo(19.2, 13.5)
        ..lineTo(7.2, 13.5),
      stroke,
    );
    canvas.drawCircle(const Offset(9, 20.5), 1.5, stroke);
    canvas.drawCircle(const Offset(18, 20.5), 1.5, stroke);
    if (remove) {
      canvas.drawLine(const Offset(16.5, 2.75), const Offset(22, 2.75), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShoppingCartPainter oldDelegate) =>
      color != oldDelegate.color || remove != oldDelegate.remove;
}

class _LocationIcon extends StatelessWidget {
  const _LocationIcon({super.key});

  @override
  Widget build(BuildContext context) =>
      const Icon(Icons.warehouse_outlined, size: 24, semanticLabel: 'Location');
}

Color _themeCanvas(BuildContext context) =>
    Theme.of(context).extension<InventorinatorColors>()?.canvas ??
    _appCanvasColor;

enum AppColorTheme {
  darkPurple,
  darkRed,
  darkBlue,
  darkGreen,
  darkBlack,
  darkBrown,
  custom,
}

enum AppBrightnessMode { dark, light }

extension AppColorThemeLabel on AppColorTheme {
  String get label => switch (this) {
    AppColorTheme.darkPurple => 'Purple',
    AppColorTheme.darkRed => 'Red',
    AppColorTheme.darkBlue => 'Blue',
    AppColorTheme.darkGreen => 'Green',
    AppColorTheme.darkBlack => 'Grey / Black',
    AppColorTheme.darkBrown => 'Orange / Brown',
    AppColorTheme.custom => 'Custom',
  };
}

@immutable
class InventorinatorColors extends ThemeExtension<InventorinatorColors> {
  const InventorinatorColors({
    required this.canvas,
    required this.surface,
    required this.panel,
    required this.input,
    required this.accent,
    required this.base,
    required this.container,
    required this.flash,
    required this.flashDark,
    required this.outline,
    required this.outlineVariant,
    required this.rim,
  });

  final Color canvas;
  final Color surface;
  final Color panel;
  final Color input;
  final Color accent;
  final Color base;
  final Color container;
  final Color flash;
  final Color flashDark;
  final Color outline;
  final Color outlineVariant;
  final Color rim;

  static const palettes = <AppColorTheme, InventorinatorColors>{
    AppColorTheme.darkPurple: InventorinatorColors(
      canvas: Color(0xff120d1c),
      surface: Color(0xff1b1726),
      panel: Color(0xff171220),
      input: Color(0xff15101f),
      accent: Color(0xff9f8aff),
      base: Color(0xff755da5),
      container: Color(0xff493970),
      flash: Color(0xff8359ab),
      flashDark: Color(0xff59407b),
      outline: Color(0xff5d5970),
      outlineVariant: Color(0xff463955),
      rim: Color(0xff8264b4),
    ),
    AppColorTheme.darkRed: InventorinatorColors(
      canvas: Color(0xff1b0c10),
      surface: Color(0xff27171b),
      panel: Color(0xff211115),
      input: Color(0xff1c0e12),
      accent: Color(0xffff879a),
      base: Color(0xffa54e5f),
      container: Color(0xff6e3340),
      flash: Color(0xffc95b73),
      flashDark: Color(0xff81394a),
      outline: Color(0xff74545b),
      outlineVariant: Color(0xff583840),
      rim: Color(0xffb96376),
    ),
    AppColorTheme.darkBlue: InventorinatorColors(
      canvas: Color(0xff090f1d),
      surface: Color(0xff141c2b),
      panel: Color(0xff0f1726),
      input: Color(0xff0c1321),
      accent: Color(0xff7faaff),
      base: Color(0xff4d6fa8),
      container: Color(0xff304a76),
      flash: Color(0xff5c8bce),
      flashDark: Color(0xff3c5d8e),
      outline: Color(0xff52627b),
      outlineVariant: Color(0xff38485f),
      rim: Color(0xff638bc5),
    ),
    AppColorTheme.darkGreen: InventorinatorColors(
      canvas: Color(0xff0b160f),
      surface: Color(0xff15241a),
      panel: Color(0xff101f15),
      input: Color(0xff0d1a12),
      accent: Color(0xff71d998),
      base: Color(0xff3f8b5c),
      container: Color(0xff285c3b),
      flash: Color(0xff4eaa71),
      flashDark: Color(0xff326e49),
      outline: Color(0xff4c6956),
      outlineVariant: Color(0xff344d3c),
      rim: Color(0xff58a875),
    ),
    AppColorTheme.darkBlack: InventorinatorColors(
      canvas: Color(0xff0d0e11),
      surface: Color(0xff191a1f),
      panel: Color(0xff141519),
      input: Color(0xff111216),
      accent: Color(0xffb5bac6),
      base: Color(0xff696e7a),
      container: Color(0xff444750),
      flash: Color(0xff818690),
      flashDark: Color(0xff555963),
      outline: Color(0xff565a65),
      outlineVariant: Color(0xff3c3f47),
      rim: Color(0xff858a95),
    ),
    AppColorTheme.darkBrown: InventorinatorColors(
      canvas: Color(0xff1a1008),
      surface: Color(0xff281b12),
      panel: Color(0xff21150e),
      input: Color(0xff1c110b),
      accent: Color(0xffe0a264),
      base: Color(0xff9a6138),
      container: Color(0xff683f25),
      flash: Color(0xffbd7644),
      flashDark: Color(0xff7d4d2e),
      outline: Color(0xff755b48),
      outlineVariant: Color(0xff584130),
      rim: Color(0xffb4794d),
    ),
  };

  static InventorinatorColors forTheme(
    AppColorTheme theme, {
    Color customColor = const Color(0xff8e75ff),
    AppBrightnessMode brightness = AppBrightnessMode.dark,
  }) {
    final source = theme == AppColorTheme.custom
        ? customColor
        : palettes[theme]!.base;
    if (brightness == AppBrightnessMode.light) {
      return fromLightColor(source);
    }
    return theme == AppColorTheme.custom
        ? fromCustomColor(customColor)
        : palettes[theme]!;
  }

  static InventorinatorColors fromLightColor(Color color) {
    final source = HSVColor.fromColor(color);
    final saturation = source.saturation.clamp(0.0, 1.0);
    Color tone(double saturationScale, double value) => HSVColor.fromAHSV(
      1,
      source.hue,
      (saturation * saturationScale).clamp(0.0, 1.0),
      value,
    ).toColor();

    return InventorinatorColors(
      canvas: tone(.10, .98),
      surface: tone(.035, 1),
      panel: tone(.15, .95),
      input: tone(.05, .99),
      accent: tone(.92, .53),
      base: tone(.74, .62),
      container: tone(.26, .90),
      flash: tone(.96, .68),
      flashDark: tone(.9, .46),
      outline: tone(.18, .52),
      outlineVariant: tone(.13, .78),
      rim: tone(.8, .58),
    );
  }

  static InventorinatorColors fromCustomColor(Color color) {
    final source = HSVColor.fromColor(color);
    final saturation = source.saturation.clamp(0.0, 1.0);
    Color tone(double saturationScale, double value) => HSVColor.fromAHSV(
      1,
      source.hue,
      (saturation * saturationScale).clamp(0.0, 1.0),
      value,
    ).toColor();

    // Preserve the selected hue while deriving consistently dark surfaces and
    // readable interactive colors. The picker color itself remains unchanged
    // and is shown in the Custom tile.
    return InventorinatorColors(
      canvas: tone(.72, .095),
      surface: tone(.52, .155),
      panel: tone(.68, .125),
      input: tone(.74, .105),
      accent: tone(.82, .92),
      base: tone(.72, .62),
      container: tone(.78, .42),
      flash: tone(.9, .72),
      flashDark: tone(.78, .48),
      outline: tone(.34, .44),
      outlineVariant: tone(.48, .32),
      rim: tone(.68, .68),
    );
  }

  @override
  InventorinatorColors copyWith() => this;

  @override
  InventorinatorColors lerp(InventorinatorColors? other, double t) =>
      other ?? this;
}

String _normalizedStockName(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

bool isGenericAndroidDeviceName(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('_', ' ');
  return normalized.isEmpty ||
      normalized == 'unnamed device' ||
      normalized == 'android device' ||
      normalized == 'this device' ||
      normalized == 'localhost' ||
      normalized == 'android' ||
      normalized == 'emulator' ||
      normalized.startsWith('sdk gphone') ||
      normalized.startsWith('generic ') ||
      normalized.startsWith('android sdk built for');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: _appCanvasColor,
      statusBarIconBrightness: Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: _appCanvasColor,
      systemNavigationBarDividerColor: _appCanvasColor,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  late final LocalDatabase database;
  try {
    database = await LocalDatabase.open();
  } on LocalDatabaseAlreadyOpenException {
    await _showAlreadyRunningSystemDialog();
    exit(0);
  }
  runApp(
    InventorinatorApp(
      database: database,
      persistedState: database.loadState(includeFullImages: false),
    ),
  );
}

Future<void> _showAlreadyRunningSystemDialog() async {
  const title = 'Inventorinator';
  const message = 'Cannot launch multiple instances.';
  try {
    if (Platform.isLinux) {
      if (await File('/usr/bin/zenity').exists()) {
        await Process.run('/usr/bin/zenity', [
          '--error',
          '--title=$title',
          '--text=$message',
          '--no-wrap',
        ]);
        return;
      }
      if (await File('/usr/bin/kdialog').exists()) {
        await Process.run('/usr/bin/kdialog', [
          '--error',
          message,
          '--title',
          title,
        ]);
      }
      return;
    }
    if (Platform.isWindows) {
      await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "Add-Type -AssemblyName PresentationFramework; "
            "[System.Windows.MessageBox]::Show('$message', '$title', 'OK', 'Error')",
      ]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('/usr/bin/osascript', [
        '-e',
        'display alert "$title" message "$message" as critical',
      ]);
    }
  } catch (error) {
    debugPrint('$title: $message ($error)');
  }
}

enum InventoryType {
  other,
  fastener,
  filament,
  printedPart,
  resin,
  nozzle,
  heatBreak,
  heatBlock,
  sock,
  custom,
}

extension InventoryTypeContext on InventoryType {
  bool get supportsDrying => this == InventoryType.filament;
  bool get supportsPrinting =>
      this == InventoryType.filament || this == InventoryType.printedPart;
  bool get supportsFilamentLifecycle => this == InventoryType.filament;
}

enum InventorySort { type, quantity, age, cost, dryingTime, moistureRemaining }

enum CatalogViewFilter { kits, builds, machines, printers, tools }

enum FilamentStatus { ready, deployed, drying, queuedForDrying }

enum ArchiveDisposition { archived, depleted, destroyed }

enum ProductSearchProvider { google, bing, duckDuckGo, brave, custom }

enum MoistureTimeUnit { hours, days }

String _searchProviderLabel(ProductSearchProvider provider) =>
    switch (provider) {
      ProductSearchProvider.google => 'Google',
      ProductSearchProvider.bing => 'Bing',
      ProductSearchProvider.duckDuckGo => 'DuckDuckGo',
      ProductSearchProvider.brave => 'Brave Search',
      ProductSearchProvider.custom => 'Custom',
    };

enum ItemAction {
  showCompatibleFilaments,
  resetDryTimer,
  edit,
  duplicate,
  archive,
  delete,
}

enum DebugCardEffect { remoteQuantity, lowStock, moistureThreshold }

class VendorRecord {
  const VendorRecord({
    required this.id,
    required this.name,
    this.isBrand = false,
    this.logoBytes,
  });
  final String id;
  final String name;
  final bool isBrand;
  final Uint8List? logoBytes;
}

class BrandRecord {
  const BrandRecord({
    required this.id,
    required this.name,
    required this.vendorIds,
    required this.categories,
    this.logoBytes,
  });
  final String id;
  final String name;
  final Set<String> vendorIds;
  final Set<InventoryType> categories;
  final Uint8List? logoBytes;
}

class SpoolTypeRecord {
  const SpoolTypeRecord({
    required this.id,
    required this.label,
    required this.weightGrams,
  });
  final String id;
  final String label;
  final int weightGrams;
}

class MaterialRecord {
  const MaterialRecord({
    required this.id,
    required this.name,
    required this.typeKey,
  });

  final String id;
  final String name;
  final String typeKey;
}

class CustomItemTypeRecord {
  const CustomItemTypeRecord({
    required this.id,
    required this.name,
    this.contextualFields = const [],
    this.iconKey = 'tune',
    this.canMarkDepleted = false,
    this.showsStatus = false,
  });
  final String id;
  final String name;
  final List<String> contextualFields;
  final String iconKey;
  final bool canMarkDepleted;
  final bool showsStatus;
}

const _defaultTypeDepletionSettings = <String, bool>{
  'item:filament': true,
  'item:resin': true,
};

bool _typeCanMarkDepleted(String key, Map<String, bool> settings) =>
    settings[key] ?? _defaultTypeDepletionSettings[key] ?? false;

const _defaultTypeStatusSettings = <String, bool>{'item:filament': true};

bool _typeShowsStatus(String key, Map<String, bool> settings) =>
    settings[key] ?? _defaultTypeStatusSettings[key] ?? false;

const typeIconChoices = <String, IconData>{
  'inventory': Icons.inventory_2_outlined,
  'hardware': Icons.hardware_rounded,
  'filament': Icons.donut_large_rounded,
  'printed-part': Icons.view_in_ar_outlined,
  'droplet': Icons.opacity_rounded,
  'nozzle': Icons.change_history_rounded,
  'heat-break': Icons.compress_rounded,
  'shield': Icons.shield_outlined,
  'machine': Icons.precision_manufacturing_outlined,
  'printer': Icons.print_outlined,
  'tool': Icons.handyman_outlined,
  'kit': Icons.account_tree_outlined,
  'build': Icons.construction_rounded,
  'electronics': Icons.memory_rounded,
  'science': Icons.science_outlined,
  'storage': Icons.shelves,
  'package': Icons.inventory_2_rounded,
  'tune': Icons.tune_rounded,
  'lucide:archive': LucideIcons.archive,
  'lucide:armchair': LucideIcons.armchair,
  'lucide:aperture': LucideIcons.aperture,
  'lucide:barcode': LucideIcons.barcode,
  'lucide:battery': LucideIcons.battery,
  'lucide:bike': LucideIcons.bike,
  'lucide:bolt': LucideIcons.bolt,
  'lucide:bot': LucideIcons.bot,
  'lucide:box': LucideIcons.box,
  'lucide:boxes': LucideIcons.boxes,
  'lucide:cable': LucideIcons.cable,
  'lucide:car': LucideIcons.car,
  'lucide:circle-gauge': LucideIcons.circle_gauge,
  'lucide:circuit-board': LucideIcons.circuit_board,
  'lucide:component': LucideIcons.component,
  'lucide:construction': LucideIcons.construction,
  'lucide:cpu': LucideIcons.cpu,
  'lucide:cylinder': LucideIcons.cylinder,
  'lucide:diamond': LucideIcons.diamond,
  'lucide:drill': LucideIcons.drill,
  'lucide:droplet': LucideIcons.droplet,
  'lucide:factory': LucideIcons.factory,
  'lucide:fan': LucideIcons.fan,
  'lucide:flame': LucideIcons.flame,
  'lucide:flask-conical': LucideIcons.flask_conical,
  'lucide:gauge': LucideIcons.gauge,
  'lucide:gem': LucideIcons.gem,
  'lucide:glass-water': LucideIcons.glass_water,
  'lucide:hammer': LucideIcons.hammer,
  'lucide:hard-hat': LucideIcons.hard_hat,
  'lucide:hexagon': LucideIcons.hexagon,
  'lucide:image': LucideIcons.image,
  'lucide:layers': LucideIcons.layers,
  'lucide:leaf': LucideIcons.leaf,
  'lucide:lightbulb': LucideIcons.lightbulb,
  'lucide:nut': LucideIcons.nut,
  'lucide:octagon': LucideIcons.octagon,
  'lucide:package': LucideIcons.package,
  'lucide:paint-bucket': LucideIcons.paint_bucket,
  'lucide:palette': LucideIcons.palette,
  'lucide:plug': LucideIcons.plug,
  'lucide:printer': LucideIcons.printer,
  'lucide:puzzle': LucideIcons.puzzle,
  'lucide:qr-code': LucideIcons.qr_code,
  'lucide:recycle': LucideIcons.recycle,
  'lucide:rocket': LucideIcons.rocket,
  'lucide:ruler': LucideIcons.ruler,
  'lucide:scale': LucideIcons.scale,
  'lucide:scan-line': LucideIcons.scan_line,
  'lucide:shapes': LucideIcons.shapes,
  'lucide:shield': LucideIcons.shield,
  'lucide:shirt': LucideIcons.shirt,
  'lucide:snowflake': LucideIcons.snowflake,
  'lucide:spool': LucideIcons.spool,
  'lucide:star': LucideIcons.star,
  'lucide:tag': LucideIcons.tag,
  'lucide:tags': LucideIcons.tags,
  'lucide:test-tube': LucideIcons.test_tube,
  'lucide:thermometer': LucideIcons.thermometer,
  'lucide:tool-case': LucideIcons.tool_case,
  'lucide:tree-pine': LucideIcons.tree_pine,
  'lucide:triangle': LucideIcons.triangle,
  'lucide:upload': LucideIcons.upload,
  'lucide:warehouse': LucideIcons.warehouse,
  'lucide:weight': LucideIcons.weight,
  'lucide:wrench': LucideIcons.wrench,
  'lucide:zap': LucideIcons.zap,
};

const _customTypeIconPrefix = 'custom-image:';
const _maximumCustomTypeIconBytes = 5 * 1024 * 1024;
final Map<String, Uint8List?> _customTypeIconBytesCache = {};
final Map<Uint8List, Uint8List> _customTypeIconStillCache = Map.identity();

enum CustomIconAnimationMode { interaction, always, off }

CustomIconAnimationMode _customIconAnimationModeFromName(String? value) =>
    CustomIconAnimationMode.values
        .where((mode) => mode.name == value)
        .firstOrNull ??
    CustomIconAnimationMode.interaction;

IconData _iconFromKey(String? key, IconData fallback) =>
    typeIconChoices[key] ?? fallback;

Uint8List? _iconImageBytesFromKey(String? key) {
  if (key == null || !key.startsWith(_customTypeIconPrefix)) return null;
  if (_customTypeIconBytesCache.containsKey(key)) {
    return _customTypeIconBytesCache[key];
  }
  try {
    final bytes = base64Decode(key.substring(_customTypeIconPrefix.length));
    _customTypeIconBytesCache[key] = bytes;
    return bytes;
  } on FormatException {
    _customTypeIconBytesCache[key] = null;
    return null;
  }
}

Uint8List _stillCustomTypeIcon(Uint8List bytes) {
  final cached = _customTypeIconStillCache[bytes];
  if (cached != null) return cached;
  final animatedFormat =
      bytes.length >= 6 &&
          bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 ||
      bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50;
  if (!animatedFormat) return bytes;
  try {
    final firstFrame = img.decodeImage(bytes, frame: 0);
    if (firstFrame == null) return bytes;
    final still = Uint8List.fromList(img.encodePng(firstFrame));
    _customTypeIconStillCache[bytes] = still;
    return still;
  } catch (_) {
    return bytes;
  }
}

class _CustomIconAnimationScope extends InheritedWidget {
  const _CustomIconAnimationScope({required this.mode, required super.child});

  final CustomIconAnimationMode mode;

  static CustomIconAnimationMode of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_CustomIconAnimationScope>()
          ?.mode ??
      CustomIconAnimationMode.interaction;

  @override
  bool updateShouldNotify(_CustomIconAnimationScope oldWidget) =>
      mode != oldWidget.mode;
}

class _CustomTypeImage extends StatefulWidget {
  const _CustomTypeImage({
    required this.bytes,
    required this.fit,
    required this.errorBuilder,
    this.imageKey,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final ImageErrorWidgetBuilder errorBuilder;
  final Key? imageKey;
  final double? width;
  final double? height;

  @override
  State<_CustomTypeImage> createState() => _CustomTypeImageState();
}

class _CustomTypeImageState extends State<_CustomTypeImage> {
  bool interacting = false;
  Timer? interactionTimer;

  void _setInteracting(bool value) {
    interactionTimer?.cancel();
    if (interacting != value) setState(() => interacting = value);
  }

  void _touchInteraction() {
    _setInteracting(true);
    interactionTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _setInteracting(false);
    });
  }

  @override
  void dispose() {
    interactionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = _CustomIconAnimationScope.of(context);
    final animate =
        mode == CustomIconAnimationMode.always ||
        mode == CustomIconAnimationMode.interaction && interacting;
    final bytes = animate ? widget.bytes : _stillCustomTypeIcon(widget.bytes);
    return MouseRegion(
      opaque: false,
      onEnter: (_) => _setInteracting(true),
      onExit: (_) => _setInteracting(false),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _touchInteraction(),
        child: Image.memory(
          bytes,
          key: widget.imageKey,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: widget.errorBuilder,
        ),
      ),
    );
  }
}

Widget _typeIconVisual(
  String? key,
  IconData fallback, {
  double size = 20,
  Color? color,
}) {
  final bytes = _iconImageBytesFromKey(key);
  return bytes == null
      ? Icon(_iconFromKey(key, fallback), size: size, color: color)
      : ClipRRect(
          borderRadius: BorderRadius.circular(size * .22),
          child: _CustomTypeImage(
            bytes: bytes,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Icon(fallback, size: size, color: color),
          ),
        );
}

String _typeIconDisplayName(String key) {
  if (key.startsWith(_customTypeIconPrefix)) return 'Custom image';
  final clean = key.replaceFirst('lucide:', '');
  return clean
      .split('-')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

String _typeIconLibraryName(String key) => key.startsWith('lucide:')
    ? 'Lucide'
    : key.startsWith(_customTypeIconPrefix)
    ? 'Custom'
    : 'Material';

bool _looksLikeRasterImage(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return true;
  }
  if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) return true;
  if (bytes.length >= 6 &&
      ascii.decode(bytes.sublist(0, 3), allowInvalid: true) == 'GIF') {
    return true;
  }
  return bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
}

String _customTypeIconKeyFromBytes(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > _maximumCustomTypeIconBytes) {
    throw const FormatException('Use an image smaller than 5 MB.');
  }
  if (!_looksLikeRasterImage(bytes)) {
    throw const FormatException('Use a PNG, JPEG, WebP, or GIF image.');
  }
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('That image could not be decoded.');
  }
  if (decoded.width > 2048 || decoded.height > 2048) {
    throw const FormatException('Use an image no larger than 2048 × 2048.');
  }
  return '$_customTypeIconPrefix${base64Encode(bytes)}';
}

String _customTypeIconKeyFromBase64(String source) {
  var clean = source.trim();
  if (clean.startsWith('data:')) {
    final comma = clean.indexOf(',');
    if (comma < 0 || !clean.substring(0, comma).contains(';base64')) {
      throw const FormatException('That data URL is not a Base64 image.');
    }
    clean = clean.substring(comma + 1);
  }
  clean = clean.replaceAll(RegExp(r'\s+'), '');
  try {
    return _customTypeIconKeyFromBytes(base64Decode(clean));
  } on FormatException catch (error) {
    if (error.message.toString().startsWith('Use')) rethrow;
    throw const FormatException('Paste valid Base64 image data.');
  }
}

String _iconKeyFor(IconData icon) =>
    typeIconChoices.entries
        .where((entry) => entry.value.codePoint == icon.codePoint)
        .map((entry) => entry.key)
        .firstOrNull ??
    'inventory';

const defaultSpoolTypeId = 'SPOOL-1000G';
const starterSpoolTypes = <SpoolTypeRecord>[
  SpoolTypeRecord(id: 'SPOOL-250G', label: '.250 kg', weightGrams: 250),
  SpoolTypeRecord(id: 'SPOOL-500G', label: '.5 kg', weightGrams: 500),
  SpoolTypeRecord(id: 'SPOOL-750G', label: '.750 kg', weightGrams: 750),
  SpoolTypeRecord(id: defaultSpoolTypeId, label: '1 kg', weightGrams: 1000),
  SpoolTypeRecord(id: 'SPOOL-3000G', label: '3 kg', weightGrams: 3000),
  SpoolTypeRecord(id: 'SPOOL-5000G', label: '5 kg', weightGrams: 5000),
];

const starterMaterials = <MaterialRecord>[
  MaterialRecord(id: 'MAT-FIL-PLA', name: 'PLA', typeKey: 'type:filament'),
  MaterialRecord(id: 'MAT-FIL-HTPLA', name: 'HTPLA', typeKey: 'type:filament'),
  MaterialRecord(id: 'MAT-FIL-PETG', name: 'PETG', typeKey: 'type:filament'),
  MaterialRecord(id: 'MAT-FIL-PCTG', name: 'PCTG', typeKey: 'type:filament'),
  MaterialRecord(id: 'MAT-FIL-NYLON', name: 'Nylon', typeKey: 'type:filament'),
  MaterialRecord(id: 'MAT-FIL-ABS', name: 'ABS', typeKey: 'type:filament'),
  MaterialRecord(id: 'MAT-FIL-ASA', name: 'ASA', typeKey: 'type:filament'),
  MaterialRecord(id: 'MAT-FIL-TPU', name: 'TPU', typeKey: 'type:filament'),
  MaterialRecord(
    id: 'MAT-SPOOL-CARDBOARD',
    name: 'Cardboard',
    typeKey: 'component:spool',
  ),
  MaterialRecord(id: 'MAT-SPOOL-ABS', name: 'ABS', typeKey: 'component:spool'),
  MaterialRecord(
    id: 'MAT-SPOOL-PC',
    name: 'Polycarbonate',
    typeKey: 'component:spool',
  ),
  MaterialRecord(
    id: 'MAT-MASTER-PLA',
    name: 'PLA',
    typeKey: 'component:master-spool',
  ),
  MaterialRecord(
    id: 'MAT-MASTER-PETG',
    name: 'PETG',
    typeKey: 'component:master-spool',
  ),
  MaterialRecord(
    id: 'MAT-MASTER-ABS',
    name: 'ABS',
    typeKey: 'component:master-spool',
  ),
  MaterialRecord(id: 'MAT-NOZ-BRASS', name: 'Brass', typeKey: 'type:nozzle'),
  MaterialRecord(
    id: 'MAT-NOZ-HARDENED',
    name: 'Hardened steel',
    typeKey: 'type:nozzle',
  ),
  MaterialRecord(
    id: 'MAT-NOZ-OBXIDIAN',
    name: 'ObXidian',
    typeKey: 'type:nozzle',
  ),
  MaterialRecord(
    id: 'MAT-NOZ-TUNGSTEN',
    name: 'Tungsten',
    typeKey: 'type:nozzle',
  ),
  MaterialRecord(
    id: 'MAT-NOZ-STAINLESS',
    name: 'Stainless steel',
    typeKey: 'type:nozzle',
  ),
];

class MachineTypeRecord {
  const MachineTypeRecord({
    required this.id,
    required this.name,
    this.parentId,
  });
  final String id;
  final String name;
  final String? parentId;
}

class MachineRecord {
  const MachineRecord({
    required this.id,
    required this.name,
    required this.model,
    required this.address,
    required this.typeId,
    this.kitIds = const {},
    this.sourceUrls = const [],
    this.imageBytes,
  });
  final String id;
  final String name;
  final String model;
  final String address;
  final String typeId;
  final Set<String> kitIds;
  final List<String> sourceUrls;
  final Uint8List? imageBytes;
}

class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.brandId,
    required this.category,
    required this.name,
    this.defaultCost = 0,
    this.dryingMinutes,
    this.printingInstructions = '',
    this.dryingInstructions = '',
    this.storageInstructions = '',
    this.sourceUrls = const [],
    this.imageBytes,
  });
  final String id;
  final String brandId;
  final InventoryType category;
  final String name;
  final double defaultCost;
  final int? dryingMinutes;
  final String printingInstructions;
  final String dryingInstructions;
  final String storageInstructions;
  final List<String> sourceUrls;
  final Uint8List? imageBytes;
}

class KitBomEntry {
  const KitBomEntry({
    this.id = '',
    required this.productId,
    required this.quantity,
    this.name,
    this.section = 'Unassigned',
  });
  final String id;
  final String productId;
  final double quantity;
  final String? name;
  final String section;
}

class KitRecord {
  const KitRecord({
    required this.id,
    required this.name,
    required this.bom,
    this.sections = const [],
    this.sourceUrls = const [],
    this.imageBytes,
  });
  final String id;
  final String name;
  final List<KitBomEntry> bom;
  final List<String> sections;
  final List<String> sourceUrls;
  final Uint8List? imageBytes;
}

class BuildLine {
  const BuildLine({
    required this.id,
    required this.productId,
    required this.name,
    required this.section,
    required this.requiredQuantity,
    this.usedQuantity = 0,
    this.consumedInventoryIds = const [],
  });
  final String id;
  final String productId;
  final String name;
  final String section;
  final double requiredQuantity;
  final double usedQuantity;
  final List<String> consumedInventoryIds;

  BuildLine copyWith({
    double? usedQuantity,
    List<String>? consumedInventoryIds,
  }) => BuildLine(
    id: id,
    productId: productId,
    name: name,
    section: section,
    requiredQuantity: requiredQuantity,
    usedQuantity: usedQuantity ?? this.usedQuantity,
    consumedInventoryIds: consumedInventoryIds ?? this.consumedInventoryIds,
  );
}

class _LineStockStatus {
  const _LineStockStatus({required this.available, required this.missing});

  final double available;
  final double missing;

  bool get isMissing => missing > 0.0001;
}

class _KitBuildability {
  const _KitBuildability({
    required this.buildCount,
    required this.missingLineCount,
    required this.reservedQuantity,
  });

  final int buildCount;
  final int missingLineCount;
  final double reservedQuantity;
  bool get canBuild => buildCount > 0;
}

class BuildRecord {
  BuildRecord({
    required this.id,
    required this.kitId,
    required this.name,
    required this.createdAt,
    required this.createdBy,
    required this.lines,
    this.ownerDeviceId = '',
    this.ownerUserId,
    this.shared = false,
    this.completedAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;
  final String id;
  final String kitId;
  final String name;
  final DateTime createdAt;
  final String createdBy;
  final List<BuildLine> lines;
  final String ownerDeviceId;
  final String? ownerUserId;
  bool shared;
  DateTime? completedAt;
  DateTime updatedAt;
}

class StockLocationRecord {
  const StockLocationRecord({
    required this.id,
    required this.name,
    this.parentId,
  });

  final String id;
  final String name;
  final String? parentId;
}

enum ShoppingListStatus { needed, ordered, received }

class ShoppingListEntry {
  const ShoppingListEntry({
    required this.id,
    required this.name,
    required this.productId,
    required this.quantityNeeded,
    this.quantityOrdered = 0,
    this.quantityReceived = 0,
    this.kitId,
    this.bomLineId,
    this.sourceUrl = '',
    this.status = ShoppingListStatus.needed,
  });

  final String id;
  final String name;
  final String productId;
  final double quantityNeeded;
  final double quantityOrdered;
  final double quantityReceived;
  final String? kitId;
  final String? bomLineId;
  final String sourceUrl;
  final ShoppingListStatus status;

  ShoppingListEntry copyWith({
    double? quantityNeeded,
    double? quantityOrdered,
    double? quantityReceived,
    String? sourceUrl,
    ShoppingListStatus? status,
  }) => ShoppingListEntry(
    id: id,
    name: name,
    productId: productId,
    quantityNeeded: quantityNeeded ?? this.quantityNeeded,
    quantityOrdered: quantityOrdered ?? this.quantityOrdered,
    quantityReceived: quantityReceived ?? this.quantityReceived,
    kitId: kitId,
    bomLineId: bomLineId,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    status: status ?? this.status,
  );
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.timestamp,
    required this.actor,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.changes,
  });
  final String id;
  final DateTime timestamp;
  final String actor;
  final String action;
  final String entityType;
  final String entityId;
  final Map<String, String> changes;
}

class RapidItemDraft {
  const RapidItemDraft({
    required this.name,
    required this.type,
    required this.quantity,
    required this.price,
    this.materialId = '',
    this.materialName = '',
    this.itemColorName = '',
    this.itemColorLabel = '',
  });
  final String name;
  final InventoryType type;
  final double quantity;
  final double price;
  final String materialId;
  final String materialName;
  final String itemColorName;
  final String itemColorLabel;
}

class RapidizerParseResult {
  const RapidizerParseResult({required this.items, required this.errors});
  final List<RapidItemDraft> items;
  final List<String> errors;
  bool get isValid => items.isNotEmpty && errors.isEmpty;
}

class InventoryJsonDraft {
  const InventoryJsonDraft({
    required this.rowNumber,
    required this.name,
    required this.typeName,
    required this.quantity,
    required this.cost,
    this.material = '',
    this.color = '',
    this.colorLabel = '',
    this.brand = '',
    this.vendor = '',
    this.storageLocation = '',
    this.barcode = '',
    this.productUrl = '',
    this.imageUrl = '',
    this.compatibility = const [],
    this.amsCompatible = false,
  });

  final int rowNumber;
  final String name;
  final String typeName;
  final double quantity;
  final double cost;
  final String material;
  final String color;
  final String colorLabel;
  final String brand;
  final String vendor;
  final String storageLocation;
  final String barcode;
  final String productUrl;
  final String imageUrl;
  final List<String> compatibility;
  final bool amsCompatible;
}

class InventoryJsonParseResult {
  const InventoryJsonParseResult({required this.items, required this.errors});

  final List<InventoryJsonDraft> items;
  final List<String> errors;
  bool get isValid => items.isNotEmpty && errors.isEmpty;
}

class _KitPackageImportPlan {
  const _KitPackageImportPlan({
    required this.package,
    required this.existingInventory,
    required this.inventory,
    required this.brands,
    required this.materials,
    required this.products,
    required this.machineTypes,
    required this.machines,
    required this.kits,
    required this.newInventoryItems,
    required this.newProductCount,
    required this.reusedProductCount,
    required this.newMachineCount,
    required this.updatedMachineCount,
    required this.kitWillUpdate,
    required this.matchedInventoryIdsByPartId,
  });

  final InventorinatorKitPackage package;
  final List<InventoryItem> existingInventory;
  final List<InventoryItem> inventory;
  final List<BrandRecord> brands;
  final List<MaterialRecord> materials;
  final List<CatalogProduct> products;
  final List<MachineTypeRecord> machineTypes;
  final List<MachineRecord> machines;
  final List<KitRecord> kits;
  final List<InventoryItem> newInventoryItems;
  final int newProductCount;
  final int reusedProductCount;
  final int newMachineCount;
  final int updatedMachineCount;
  final bool kitWillUpdate;
  final Map<String, String> matchedInventoryIdsByPartId;
}

class _KitPackageImportDecision {
  const _KitPackageImportDecision({required this.inventoryMatchesByPartId});

  final Map<String, String> inventoryMatchesByPartId;
}

const _createNewKitPartChoice = '__inventorinator_create_new__';

double _kitPartInventoryMatchScore(KitPackagePart part, InventoryItem item) {
  final partName = _normalizedStockName(part.name);
  final itemName = _normalizedStockName(item.name);
  if (partName.isEmpty || itemName.isEmpty) return 0;
  var score = partName == itemName ? 1.0 : 0.0;
  if (score == 0 &&
      (partName.contains(itemName) || itemName.contains(partName))) {
    final shorter = math.min(partName.length, itemName.length);
    final longer = math.max(partName.length, itemName.length);
    score = .45 + ((shorter / longer) * .35);
  }
  final partTokens = part.name
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.length > 1)
      .toSet();
  final itemTokens = item.name
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.length > 1)
      .toSet();
  if (partTokens.isNotEmpty && itemTokens.isNotEmpty) {
    final overlap = partTokens.intersection(itemTokens).length;
    final union = partTokens.union(itemTokens).length;
    score = math.max(score, overlap / union);
  }
  if (item.type.name == part.type) score += .12;
  if (part.material.isNotEmpty &&
      _normalizedStockName(item.materialName) ==
          _normalizedStockName(part.material)) {
    score += .08;
  }
  if (part.brand.isNotEmpty &&
      _normalizedStockName(item.brand) == _normalizedStockName(part.brand)) {
    score += .06;
  }
  return score.clamp(0, 1);
}

class _KitPackageImportPreviewDialog extends StatefulWidget {
  const _KitPackageImportPreviewDialog({required this.plan});

  final _KitPackageImportPlan plan;

  @override
  State<_KitPackageImportPreviewDialog> createState() =>
      _KitPackageImportPreviewDialogState();
}

class _KitPackageImportPreviewDialogState
    extends State<_KitPackageImportPreviewDialog> {
  late final Map<String, String> _matchesByPartId = {
    ...widget.plan.matchedInventoryIdsByPartId,
  };

  InventoryItem? _matchedItem(KitPackagePart part) {
    final id = _matchesByPartId[part.id];
    if (id == null || id.isEmpty) return null;
    return widget.plan.existingInventory
        .where((candidate) => candidate.id == id)
        .firstOrNull;
  }

  Future<void> _chooseMatch(KitPackagePart part) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => _KitPartInventoryMatchDialog(
        part: part,
        inventory: widget.plan.existingInventory,
        selectedInventoryId: _matchesByPartId[part.id] ?? '',
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _matchesByPartId[part.id] = selected == _createNewKitPartChoice
          ? ''
          : selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final package = plan.package;
    final matchedCount = package.parts
        .where((part) => _matchedItem(part) != null)
        .length;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.preview_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text('Import ${package.name}?')),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 680,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xffffc15c).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xffffc15c).withValues(alpha: .45),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: Color(0xffffc15c)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Imported parts start at quantity 0. This package does not claim that you own any of them.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${package.sections.length} sections')),
                Chip(label: Text('${package.parts.length} BOM lines')),
                Chip(label: Text('${plan.newProductCount} new products')),
                if (plan.reusedProductCount > 0)
                  Chip(
                    label: Text('${plan.reusedProductCount} reused products'),
                  ),
                Chip(label: Text('$matchedCount matched to inventory')),
                Chip(
                  label: Text(
                    '${package.parts.length - matchedCount} new zero-stock items',
                  ),
                ),
                if (package.machines.isNotEmpty)
                  Chip(label: Text('${package.machines.length} machines')),
                if (package.sources.isNotEmpty)
                  Chip(label: Text('${package.sources.length} kit sources')),
              ],
            ),
            if (package.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                package.description,
                style: const TextStyle(color: Color(0xffaeb5c5)),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final section in package.sections)
                    ExpansionTile(
                      initiallyExpanded: true,
                      title: Text(section.name),
                      subtitle: section.description.isEmpty
                          ? Text(
                              '${package.parts.where((part) => part.sectionId == section.id).length} parts',
                            )
                          : Text(section.description),
                      children: [
                        for (final part in package.parts.where(
                          (part) => part.sectionId == section.id,
                        ))
                          Builder(
                            builder: (context) {
                              final matchedItem = _matchedItem(part);
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  matchedItem == null
                                      ? Icons.add_box_outlined
                                      : Icons.link_rounded,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(child: Text(part.name)),
                                    Text(
                                      '×${_formatBomQuantity(part.quantity)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      [
                                        part.type,
                                        if (part.material.isNotEmpty)
                                          part.material,
                                        if (part.brand.isNotEmpty) part.brand,
                                      ].join(' · '),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      matchedItem == null
                                          ? 'Create new item at quantity 0'
                                          : 'Use ${matchedItem.name} · ${matchedItem.type.name} · qty ${_formatBomQuantity(matchedItem.quantity)}',
                                      key: Key('kit-part-match-${part.id}'),
                                      style: TextStyle(
                                        color: matchedItem == null
                                            ? const Color(0xffffc15c)
                                            : const Color(0xff45d2bd),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: OutlinedButton(
                                  key: Key('choose-kit-part-match-${part.id}'),
                                  onPressed: () => _chooseMatch(part),
                                  child: Text(
                                    matchedItem == null
                                        ? 'Find match'
                                        : 'Change',
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  if (package.machines.isNotEmpty) ...[
                    const Divider(),
                    const ListTile(
                      leading: Icon(Icons.precision_manufacturing_outlined),
                      title: Text(
                        'Machines',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    for (final machine in package.machines)
                      ListTile(
                        dense: true,
                        title: Text(machine.name),
                        subtitle: Text(
                          [
                            machine.type,
                            if (machine.model.isNotEmpty) machine.model,
                            if (machine.sources.isNotEmpty)
                              machine.sources.first.url,
                            if (machine.sources.length > 1)
                              '+${machine.sources.length - 1} more sources',
                          ].join(' · '),
                        ),
                      ),
                  ],
                  if (package.sources.isNotEmpty) ...[
                    const Divider(),
                    const ListTile(
                      leading: Icon(Icons.link_rounded),
                      title: Text(
                        'Kit sources',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    for (final source in package.sources)
                      ListTile(
                        dense: true,
                        title: Text(
                          source.title.isEmpty ? source.url : source.title,
                        ),
                        subtitle: source.title.isEmpty
                            ? null
                            : Text(source.url),
                        trailing: const Icon(Icons.open_in_new_rounded),
                        onTap: () => launchUrl(
                          Uri.parse(source.url),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('confirm-kit-package-import'),
          onPressed: () => Navigator.pop(
            context,
            _KitPackageImportDecision(
              inventoryMatchesByPartId: {..._matchesByPartId},
            ),
          ),
          icon: const Icon(Icons.file_download_done_outlined),
          label: Text(plan.kitWillUpdate ? 'Update kit' : 'Import kit'),
        ),
      ],
    );
  }
}

class _KitPartInventoryMatchDialog extends StatefulWidget {
  const _KitPartInventoryMatchDialog({
    required this.part,
    required this.inventory,
    required this.selectedInventoryId,
  });

  final KitPackagePart part;
  final List<InventoryItem> inventory;
  final String selectedInventoryId;

  @override
  State<_KitPartInventoryMatchDialog> createState() =>
      _KitPartInventoryMatchDialogState();
}

class _KitPartInventoryMatchDialogState
    extends State<_KitPartInventoryMatchDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _normalizedStockName(_query);
    final candidates =
        widget.inventory.where((item) => !item.archived).where((item) {
          if (query.isEmpty) return true;
          return _normalizedStockName(
            '${item.name} ${item.type.name} ${item.materialName} ${item.brand}',
          ).contains(query);
        }).toList()..sort((a, b) {
          final scoreOrder = _kitPartInventoryMatchScore(
            widget.part,
            b,
          ).compareTo(_kitPartInventoryMatchScore(widget.part, a));
          if (scoreOrder != 0) return scoreOrder;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    return AlertDialog(
      title: Text('Match ${widget.part.name}'),
      content: SizedBox(
        width: 620,
        height: 560,
        child: Column(
          children: [
            TextField(
              key: const Key('kit-part-match-search'),
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                labelText: 'Search existing inventory',
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              key: const Key('kit-part-create-new-choice'),
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('Create a new item'),
              subtitle: const Text('Starts at quantity 0'),
              selected: widget.selectedInventoryId.isEmpty,
              onTap: () => Navigator.pop(context, _createNewKitPartChoice),
            ),
            const Divider(height: 1),
            Expanded(
              child: candidates.isEmpty
                  ? const Center(child: Text('No inventory items match'))
                  : ListView.builder(
                      itemCount: candidates.length,
                      itemBuilder: (context, index) {
                        final item = candidates[index];
                        return ListTile(
                          key: Key('kit-part-inventory-choice-${item.id}'),
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(item.name),
                          subtitle: Text(
                            [
                              item.type.name,
                              if (item.materialName.isNotEmpty)
                                item.materialName,
                              'qty ${_formatBomQuantity(item.quantity)}',
                            ].join(' · '),
                          ),
                          selected: widget.selectedInventoryId == item.id,
                          trailing:
                              _kitPartInventoryMatchScore(widget.part, item) >=
                                  .72
                              ? const Chip(label: Text('Likely match'))
                              : null,
                          onTap: () => Navigator.pop(context, item.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class AdditionHistoryEntry {
  const AdditionHistoryEntry({
    required this.id,
    required this.itemId,
    required this.name,
    required this.type,
    required this.addedAt,
    required this.deviceName,
  });
  final String id;
  final String itemId;
  final String name;
  final InventoryType type;
  final DateTime addedAt;
  final String deviceName;

  factory AdditionHistoryEntry.fromItem(
    InventoryItem item, {
    String deviceName = 'Unknown device (predates tracking)',
  }) => AdditionHistoryEntry(
    id: 'ADD-${item.id}',
    itemId: item.id,
    name: item.name,
    type: item.type,
    addedAt: item.added,
    deviceName: deviceName,
  );
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.type,
    required this.compatibility,
    required this.added,
    required this.cost,
    required this.color,
    this.itemColorName = '',
    this.itemColorLabel = '',
    this.quantity = 1,
    this.quantityAlertThreshold,
    this.dryingMinutes,
    this.dryingRemaining,
    this.dryingStartedAt,
    this.moistureLifespanMinutes,
    this.moistureTimeUnit = MoistureTimeUnit.days,
    this.moistureAlertEnabled = false,
    this.moistureAlertThresholdMinutes,
    this.deployed = false,
    this.vendor = '',
    this.printingInstructions = '',
    this.dryingInstructions = '',
    this.storageInstructions = '',
    this.archived = false,
    this.archiveDisposition = ArchiveDisposition.archived,
    this.filamentStatus = FilamentStatus.ready,
    this.brand = '',
    this.storageLocation = '',
    this.storageLocationId = '',
    this.deploymentLocation = '',
    this.lastDriedAt,
    this.imageBytes,
    this.thumbnailBytes,
    this.labelImageBytes,
    this.barcode = '',
    this.productUrl = '',
    this.compatibleMachineIds = const [],
    this.spoolTypeId = defaultSpoolTypeId,
    this.amsCompatible = false,
    this.spoolTareWeightGrams,
    this.spoolOuterDiameterMm,
    this.spoolWidthMm,
    this.spoolHoleDiameterMm,
    this.refill = false,
    this.masterSpool = '',
    this.catalogProductId,
    this.customTypeId = '',
    this.customTypeName = '',
    this.customFieldValues = const {},
    this.materialId = '',
    this.materialName = '',
    this.spoolMaterialId = '',
    this.spoolMaterialName = '',
    this.masterSpoolMaterialId = '',
    this.masterSpoolMaterialName = '',
  });
  final String id;
  final String name;
  final InventoryType type;
  final List<String> compatibility;
  final DateTime added;
  final double cost;
  final Color color;
  final String itemColorName;
  final String itemColorLabel;
  final double quantity;
  final double? quantityAlertThreshold;
  final int? dryingMinutes;
  final int? dryingRemaining;
  final DateTime? dryingStartedAt;
  final int? moistureLifespanMinutes;
  final MoistureTimeUnit moistureTimeUnit;
  final bool moistureAlertEnabled;
  final int? moistureAlertThresholdMinutes;
  final bool deployed;
  final String vendor;
  final String printingInstructions;
  final String dryingInstructions;
  final String storageInstructions;
  final bool archived;
  final ArchiveDisposition archiveDisposition;
  final FilamentStatus filamentStatus;
  final String brand;
  final String storageLocation;
  final String storageLocationId;
  final String deploymentLocation;
  final DateTime? lastDriedAt;
  final Uint8List? imageBytes;
  final Uint8List? thumbnailBytes;
  final Uint8List? labelImageBytes;
  final String barcode;
  final String productUrl;
  final List<String> compatibleMachineIds;
  final String spoolTypeId;
  final bool amsCompatible;
  final double? spoolTareWeightGrams;
  final double? spoolOuterDiameterMm;
  final double? spoolWidthMm;
  final double? spoolHoleDiameterMm;
  final bool refill;
  final String masterSpool;
  final String? catalogProductId;
  final String customTypeId;
  final String customTypeName;
  final Map<String, String> customFieldValues;
  final String materialId;
  final String materialName;
  final String spoolMaterialId;
  final String spoolMaterialName;
  final String masterSpoolMaterialId;
  final String masterSpoolMaterialName;

  InventoryItem copyWith({
    String? id,
    String? name,
    InventoryType? type,
    List<String>? compatibility,
    DateTime? added,
    double? cost,
    Color? color,
    String? itemColorName,
    String? itemColorLabel,
    double? quantity,
    double? quantityAlertThreshold,
    int? dryingMinutes,
    int? dryingRemaining,
    DateTime? dryingStartedAt,
    int? moistureLifespanMinutes,
    MoistureTimeUnit? moistureTimeUnit,
    bool? moistureAlertEnabled,
    int? moistureAlertThresholdMinutes,
    bool? deployed,
    String? vendor,
    String? printingInstructions,
    String? dryingInstructions,
    String? storageInstructions,
    bool? archived,
    ArchiveDisposition? archiveDisposition,
    FilamentStatus? filamentStatus,
    String? brand,
    String? storageLocation,
    String? storageLocationId,
    String? deploymentLocation,
    DateTime? lastDriedAt,
    Uint8List? imageBytes,
    Uint8List? thumbnailBytes,
    Uint8List? labelImageBytes,
    String? barcode,
    String? productUrl,
    List<String>? compatibleMachineIds,
    String? spoolTypeId,
    bool? amsCompatible,
    double? spoolTareWeightGrams,
    double? spoolOuterDiameterMm,
    double? spoolWidthMm,
    double? spoolHoleDiameterMm,
    bool? refill,
    String? masterSpool,
    String? catalogProductId,
    String? customTypeId,
    String? customTypeName,
    Map<String, String>? customFieldValues,
    String? materialId,
    String? materialName,
    String? spoolMaterialId,
    String? spoolMaterialName,
    String? masterSpoolMaterialId,
    String? masterSpoolMaterialName,
    bool clearFilamentData = false,
    bool clearPrintingData = false,
    bool clearCatalogProductId = false,
    bool clearImageBytes = false,
    bool clearLabelImageBytes = false,
  }) => InventoryItem(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    compatibility: compatibility ?? this.compatibility,
    added: added ?? this.added,
    cost: cost ?? this.cost,
    color: color ?? this.color,
    itemColorName: itemColorName ?? this.itemColorName,
    itemColorLabel: itemColorLabel ?? this.itemColorLabel,
    quantity: quantity ?? this.quantity,
    quantityAlertThreshold:
        quantityAlertThreshold ?? this.quantityAlertThreshold,
    dryingMinutes: clearFilamentData
        ? null
        : dryingMinutes ?? this.dryingMinutes,
    dryingRemaining: clearFilamentData
        ? null
        : dryingRemaining ?? this.dryingRemaining,
    dryingStartedAt: clearFilamentData
        ? null
        : dryingStartedAt ?? this.dryingStartedAt,
    moistureLifespanMinutes: clearFilamentData
        ? null
        : moistureLifespanMinutes ?? this.moistureLifespanMinutes,
    moistureTimeUnit: moistureTimeUnit ?? this.moistureTimeUnit,
    moistureAlertEnabled: clearFilamentData
        ? false
        : moistureAlertEnabled ?? this.moistureAlertEnabled,
    moistureAlertThresholdMinutes: clearFilamentData
        ? null
        : moistureAlertThresholdMinutes ?? this.moistureAlertThresholdMinutes,
    deployed: clearFilamentData ? false : deployed ?? this.deployed,
    vendor: vendor ?? this.vendor,
    printingInstructions: clearPrintingData
        ? ''
        : printingInstructions ?? this.printingInstructions,
    dryingInstructions: clearFilamentData
        ? ''
        : dryingInstructions ?? this.dryingInstructions,
    storageInstructions: storageInstructions ?? this.storageInstructions,
    archived: archived ?? this.archived,
    archiveDisposition: archiveDisposition ?? this.archiveDisposition,
    filamentStatus: clearFilamentData
        ? FilamentStatus.ready
        : filamentStatus ?? this.filamentStatus,
    brand: brand ?? this.brand,
    storageLocation: storageLocation ?? this.storageLocation,
    storageLocationId: storageLocationId ?? this.storageLocationId,
    deploymentLocation: deploymentLocation ?? this.deploymentLocation,
    lastDriedAt: clearFilamentData ? null : lastDriedAt ?? this.lastDriedAt,
    imageBytes: clearImageBytes ? null : imageBytes ?? this.imageBytes,
    thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
    labelImageBytes: clearLabelImageBytes
        ? null
        : labelImageBytes ?? this.labelImageBytes,
    barcode: barcode ?? this.barcode,
    productUrl: productUrl ?? this.productUrl,
    compatibleMachineIds: compatibleMachineIds ?? this.compatibleMachineIds,
    spoolTypeId: clearFilamentData
        ? defaultSpoolTypeId
        : spoolTypeId ?? this.spoolTypeId,
    amsCompatible: clearFilamentData
        ? false
        : amsCompatible ?? this.amsCompatible,
    spoolTareWeightGrams: clearFilamentData
        ? null
        : spoolTareWeightGrams ?? this.spoolTareWeightGrams,
    spoolOuterDiameterMm: clearFilamentData
        ? null
        : spoolOuterDiameterMm ?? this.spoolOuterDiameterMm,
    spoolWidthMm: clearFilamentData ? null : spoolWidthMm ?? this.spoolWidthMm,
    spoolHoleDiameterMm: clearFilamentData
        ? null
        : spoolHoleDiameterMm ?? this.spoolHoleDiameterMm,
    refill: clearFilamentData ? false : refill ?? this.refill,
    masterSpool: clearFilamentData ? '' : masterSpool ?? this.masterSpool,
    catalogProductId: clearCatalogProductId
        ? null
        : catalogProductId ?? this.catalogProductId,
    customTypeId: customTypeId ?? this.customTypeId,
    customTypeName: customTypeName ?? this.customTypeName,
    customFieldValues: customFieldValues ?? this.customFieldValues,
    materialId: materialId ?? this.materialId,
    materialName: materialName ?? this.materialName,
    spoolMaterialId: spoolMaterialId ?? this.spoolMaterialId,
    spoolMaterialName: spoolMaterialName ?? this.spoolMaterialName,
    masterSpoolMaterialId: masterSpoolMaterialId ?? this.masterSpoolMaterialId,
    masterSpoolMaterialName:
        masterSpoolMaterialName ?? this.masterSpoolMaterialName,
  );
  String get typeLabel =>
      type == InventoryType.custom && customTypeName.isNotEmpty
      ? customTypeName
      : switch (type) {
          InventoryType.other => 'Other',
          InventoryType.fastener => 'Fastener',
          InventoryType.filament => 'Filament',
          InventoryType.printedPart => 'Printed part',
          InventoryType.resin => 'Resin',
          InventoryType.nozzle => 'Nozzle',
          InventoryType.heatBreak => 'Heat break',
          InventoryType.heatBlock => 'Heat block',
          InventoryType.sock => 'Silicone sock',
          InventoryType.custom => 'Custom',
        };
  IconData get icon => switch (type) {
    InventoryType.other => Icons.inventory_2_outlined,
    InventoryType.fastener => Icons.hardware_rounded,
    InventoryType.filament => Icons.donut_large_rounded,
    InventoryType.printedPart => Icons.view_in_ar_outlined,
    InventoryType.resin => Icons.opacity_rounded,
    InventoryType.nozzle => Icons.change_history_rounded,
    InventoryType.heatBreak => Icons.compress_rounded,
    InventoryType.heatBlock => Icons.view_in_ar_rounded,
    InventoryType.sock => Icons.shield_outlined,
    InventoryType.custom => Icons.tune_rounded,
  };
}

const itemColorPalette = <String, Color>{
  'Black': Color(0xff252832),
  'White': Color(0xfff0f1f5),
  'Gray': Color(0xff8c929f),
  'Red': Color(0xffe64f5f),
  'Orange': Color(0xffff8a3d),
  'Yellow': Color(0xffffcf4d),
  'Green': Color(0xff49c878),
  'Blue': Color(0xff4c93ff),
  'Purple': Color(0xff9a6cff),
  'Pink': Color(0xffff74ad),
  'Brown': Color(0xff9a6847),
  'Clear': Color(0xffbdebf2),
  'Multicolor': Color(0xffc779ff),
};

const _itemCardChromeColor = Color(0xff9da5b7);

String _decodedItemColorName(Map<String, dynamic> item, int schemaVersion) {
  final explicit = _normalizeItemColorValue(
    item['itemColorName'] as String? ?? '',
  );
  if (explicit.isNotEmpty || schemaVersion >= 4) return explicit;
  final name = (item['name'] as String? ?? '').toLowerCase();
  for (final colorName in itemColorPalette.keys) {
    if (RegExp('\\b${RegExp.escape(colorName.toLowerCase())}\\b')
        .hasMatch(name)) {
      return colorName;
    }
  }
  return '';
}

String _decodedItemColorLabel(Map<String, dynamic> item) {
  final explicit = (item['itemColorLabel'] as String? ?? '').trim();
  if (explicit.isNotEmpty) return explicit;
  final legacyValue = (item['itemColorName'] as String? ?? '').trim();
  return legacyValue.isNotEmpty && !legacyValue.startsWith('#')
      ? legacyValue
      : '';
}

Color? _hexColor(String source) {
  var hex = source.trim();
  if (!hex.startsWith('#')) return null;
  hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((value) => '$value$value').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8 || !RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(hex)) {
    return null;
  }
  return Color(int.parse(hex, radix: 16));
}

String _colorHex(Color color) {
  final value = color
      .toARGB32()
      .toRadixString(16)
      .padLeft(8, '0')
      .toUpperCase();
  return value.startsWith('FF') ? '#${value.substring(2)}' : '#$value';
}

String _normalizeItemColorValue(String source) {
  final trimmed = source.trim();
  final parsed = _hexColor(trimmed);
  return parsed == null ? trimmed : _colorHex(parsed);
}

String _itemColorHex(String source) {
  if (source.trim().isEmpty) return '';
  final color = _itemColorSwatch(source);
  return _colorHex(color ?? const Color(0xff8c929f));
}

Color? _itemColorSwatch(String name) {
  final normalized = name.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  final hex = _hexColor(normalized);
  if (hex != null) return hex;
  for (final entry in itemColorPalette.entries) {
    if (normalized.contains(entry.key.toLowerCase())) return entry.value;
  }
  return null;
}

class ItemColorPickerDialog extends StatefulWidget {
  const ItemColorPickerDialog({
    super.key,
    required this.initialValue,
    this.title = 'Choose color',
    this.allowClear = true,
  });

  final String initialValue;
  final String title;
  final bool allowClear;

  @override
  State<ItemColorPickerDialog> createState() => _ItemColorPickerDialogState();
}

class _ItemColorPickerDialogState extends State<ItemColorPickerDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController hexController;
  late HSVColor hsv;

  @override
  void initState() {
    super.initState();
    final initial =
        _itemColorSwatch(widget.initialValue) ?? const Color(0xff8e75ff);
    hsv = HSVColor.fromColor(initial);
    hexController = TextEditingController(text: _colorHex(initial));
  }

  @override
  void dispose() {
    hexController.dispose();
    super.dispose();
  }

  void _setColor(Color color) {
    setState(() {
      hsv = HSVColor.fromColor(color);
      hexController.text = _colorHex(color);
    });
  }

  void _readHex(String value) {
    final color = _hexColor(value);
    if (color != null) setState(() => hsv = HSVColor.fromColor(color));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Icon(Icons.palette_outlined),
        const SizedBox(width: 10),
        Text(widget.title),
      ],
    ),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final dimension = math.min(320.0, constraints.maxWidth);
                  return Center(
                    child: SizedBox.square(
                      dimension: dimension,
                      child: _HsvColorWheel(
                        key: const Key('item-color-picker-wheel'),
                        color: hsv,
                        onChanged: (value) => _setColor(value.toColor()),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    key: const Key('item-color-picker-preview'),
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: hsv.toColor(),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xff687185)),
                      boxShadow: [
                        BoxShadow(
                          color: hsv.toColor().withValues(alpha: .25),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HsvValue(label: 'H', value: '${hsv.hue.round()}°'),
                        _HsvValue(
                          label: 'S',
                          value: '${(hsv.saturation * 100).round()}%',
                        ),
                        _HsvValue(
                          label: 'V',
                          value: '${(hsv.value * 100).round()}%',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('item-color-picker-hex'),
                controller: hexController,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Hex color',
                  hintText: '#8E75FF',
                  helperText: '#RGB, #RRGGBB, or #AARRGGBB',
                ),
                validator: (value) => _hexColor(value ?? '') == null
                    ? 'Enter a valid hex color'
                    : null,
                onChanged: _readHex,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in itemColorPalette.entries)
                    Tooltip(
                      message: entry.key,
                      child: InkWell(
                        key: Key('item-color-preset-${entry.key}'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _setColor(entry.value),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: entry.value,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xff687185)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      if (widget.allowClear)
        TextButton(
          key: const Key('clear-item-color'),
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Clear'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        key: const Key('use-item-color'),
        onPressed: () {
          if (!formKey.currentState!.validate()) return;
          Navigator.pop(context, _normalizeItemColorValue(hexController.text));
        },
        icon: const Icon(Icons.check_rounded),
        label: const Text('Use color'),
      ),
    ],
  );
}

class _HsvValue extends StatelessWidget {
  const _HsvValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xff202633),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xff454e63)),
    ),
    child: Text(
      '$label  $value',
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

enum _ColorDragTarget { hue, saturationValue }

class _HsvColorWheel extends StatefulWidget {
  const _HsvColorWheel({
    super.key,
    required this.color,
    required this.onChanged,
  });

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  @override
  State<_HsvColorWheel> createState() => _HsvColorWheelState();
}

class _HsvColorWheelState extends State<_HsvColorWheel> {
  _ColorDragTarget? dragTarget;

  _ColorDragTarget? _targetFor(Offset position, double side) {
    final squareSize = side * .54;
    final square = Rect.fromCenter(
      center: Offset(side / 2, side / 2),
      width: squareSize,
      height: squareSize,
    );
    if (square.contains(position)) return _ColorDragTarget.saturationValue;
    final distance = (position - Offset(side / 2, side / 2)).distance;
    if (distance >= side * .39 && distance <= side * .5) {
      return _ColorDragTarget.hue;
    }
    return null;
  }

  void _update(Offset position, double side, _ColorDragTarget target) {
    if (target == _ColorDragTarget.hue) {
      final delta = position - Offset(side / 2, side / 2);
      final hue =
          (math.atan2(delta.dy, delta.dx) * 180 / math.pi + 90 + 360) % 360;
      widget.onChanged(widget.color.withHue(hue));
      return;
    }
    final squareSize = side * .54;
    final left = (side - squareSize) / 2;
    final top = (side - squareSize) / 2;
    final saturation = ((position.dx - left) / squareSize).clamp(0.0, 1.0);
    final value = (1 - (position.dy - top) / squareSize).clamp(0.0, 1.0);
    widget.onChanged(widget.color.withSaturation(saturation).withValue(value));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = math.min(constraints.maxWidth, constraints.maxHeight);
      return Semantics(
        label: 'Hue, saturation, and brightness color picker',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final target = _targetFor(details.localPosition, side);
            if (target != null) _update(details.localPosition, side, target);
          },
          onPanStart: (details) {
            dragTarget = _targetFor(details.localPosition, side);
            if (dragTarget != null) {
              _update(details.localPosition, side, dragTarget!);
            }
          },
          onPanUpdate: (details) {
            if (dragTarget != null) {
              _update(details.localPosition, side, dragTarget!);
            }
          },
          onPanEnd: (_) => dragTarget = null,
          onPanCancel: () => dragTarget = null,
          child: CustomPaint(painter: _HsvColorWheelPainter(widget.color)),
        ),
      );
    },
  );
}

class _HsvColorWheelPainter extends CustomPainter {
  const _HsvColorWheelPainter(this.color);

  final HSVColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final ringWidth = side * .085;
    final radius = side / 2 - ringWidth / 2 - 2;
    final ringRect = Rect.fromCircle(center: center, radius: radius);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..shader = const SweepGradient(
        transform: GradientRotation(-math.pi / 2),
        colors: [
          Color(0xffff0000),
          Color(0xffffff00),
          Color(0xff00ff00),
          Color(0xff00ffff),
          Color(0xff0000ff),
          Color(0xffff00ff),
          Color(0xffff0000),
        ],
        stops: [0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 1],
      ).createShader(ringRect);
    canvas.drawCircle(center, radius, ringPaint);

    final squareSize = side * .54;
    final square = Rect.fromCenter(
      center: center,
      width: squareSize,
      height: squareSize,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(8)),
      Paint()..color = HSVColor.fromAHSV(1, color.hue, 1, 1).toColor(),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(8)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xffffffff), Color(0x00ffffff)],
        ).createShader(square),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(8)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xff000000)],
        ).createShader(square),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xffd7dbea),
    );

    final hueAngle = (color.hue - 90) * math.pi / 180;
    final huePoint =
        center + Offset(math.cos(hueAngle), math.sin(hueAngle)) * radius;
    _drawHandle(canvas, huePoint, 10);

    final svPoint = Offset(
      square.left + color.saturation * square.width,
      square.bottom - color.value * square.height,
    );
    _drawHandle(canvas, svPoint, 9);
  }

  void _drawHandle(Canvas canvas, Offset point, double radius) {
    canvas.drawCircle(
      point,
      radius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0x66000000),
    );
    canvas.drawCircle(
      point,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _HsvColorWheelPainter oldDelegate) =>
      oldDelegate.color != color;
}

class FilamentColorsSearchDialog extends StatefulWidget {
  const FilamentColorsSearchDialog({
    super.key,
    required this.client,
    this.initialBrand = '',
    this.initialMaterial = '',
    this.initialQuery = '',
    this.autoSearch = true,
  });

  final FilamentColorsClient client;
  final String initialBrand;
  final String initialMaterial;
  final String initialQuery;
  final bool autoSearch;

  @override
  State<FilamentColorsSearchDialog> createState() =>
      _FilamentColorsSearchDialogState();
}

class _FilamentColorsSearchDialogState
    extends State<FilamentColorsSearchDialog> {
  late final TextEditingController brandController;
  late final TextEditingController materialController;
  late final TextEditingController queryController;
  List<FilamentColorSwatch> results = const [];
  bool loading = false;
  bool hasSearched = false;
  String? error;

  @override
  void initState() {
    super.initState();
    brandController = TextEditingController(text: widget.initialBrand);
    materialController = TextEditingController(text: widget.initialMaterial);
    queryController = TextEditingController(text: widget.initialQuery);
    if (widget.autoSearch &&
        [
          widget.initialBrand,
          widget.initialMaterial,
          widget.initialQuery,
        ].any((value) => value.trim().isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    brandController.dispose();
    materialController.dispose();
    queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (loading) return;
    if ([
      brandController.text,
      materialController.text,
      queryController.text,
    ].every((value) => value.trim().isEmpty)) {
      setState(() {
        hasSearched = false;
        results = const [];
        error = 'Enter a brand, material, or color before searching.';
      });
      return;
    }
    setState(() {
      loading = true;
      hasSearched = true;
      error = null;
    });
    try {
      final next = await widget.client.search(
        brand: brandController.text,
        material: materialController.text,
        query: queryController.text,
      );
      if (!mounted) return;
      setState(() => results = next);
    } on FilamentColorsException catch (exception) {
      if (!mounted) return;
      setState(() {
        results = const [];
        error = exception.message;
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openAttribution() async {
    await launchUrl(
      Uri.parse(filamentColorsAttributionUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    final filters = compact
        ? Column(
            children: [
              TextField(
                key: const Key('filament-colors-brand'),
                controller: brandController,
                decoration: const InputDecoration(labelText: 'Brand'),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('filament-colors-material'),
                controller: materialController,
                decoration: const InputDecoration(labelText: 'Material'),
                onSubmitted: (_) => _search(),
              ),
            ],
          )
        : Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('filament-colors-brand'),
                  controller: brandController,
                  decoration: const InputDecoration(labelText: 'Brand'),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const Key('filament-colors-material'),
                  controller: materialController,
                  decoration: const InputDecoration(labelText: 'Material'),
                  onSubmitted: (_) => _search(),
                ),
              ),
            ],
          );
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.palette_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('FilamentColors.xyz')),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: compact ? 610 : 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            filters,
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('filament-colors-query'),
                    controller: queryController,
                    decoration: const InputDecoration(
                      labelText: 'Color or product name',
                      hintText: 'Galaxy Black',
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  key: const Key('run-filament-colors-search'),
                  onPressed: loading ? null : _search,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        key: Key('filament-colors-loading'),
                      ),
                    )
                  : error != null
                  ? _FilamentColorsError(
                      message: error!,
                      onRetry: _search,
                      onOpenWebsite: _openAttribution,
                    )
                  : !hasSearched
                  ? const Center(
                      child: Text(
                        'Enter a brand, material, or color to search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xff9da5b7)),
                      ),
                    )
                  : results.isEmpty
                  ? const Center(
                      child: Text(
                        'No matching swatches. Try changing a filter.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xff9da5b7)),
                      ),
                    )
                  : ListView.separated(
                      key: const Key('filament-colors-results'),
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final swatch = results[index];
                        return InkWell(
                          key: Key('filament-color-result-${swatch.id}'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(context, swatch),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xff1b202b),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xff41344f),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: _hexColor(swatch.hex),
                                    borderRadius: BorderRadius.circular(13),
                                    border: Border.all(
                                      color: const Color(0xff687185),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        swatch.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        [
                                              swatch.manufacturer,
                                              swatch.filamentType.isNotEmpty
                                                  ? swatch.filamentType
                                                  : swatch.material,
                                            ]
                                            .where((value) => value.isNotEmpty)
                                            .join(' · '),
                                        style: const TextStyle(
                                          color: Color(0xff9da5b7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  swatch.hex,
                                  style: const TextStyle(
                                    color: Color(0xffc9bcff),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('filament-colors-attribution'),
              onPressed: _openAttribution,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text(
                'Color data from FilamentColors.xyz · CC BY 4.0',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _FilamentColorsError extends StatelessWidget {
  const _FilamentColorsError({
    required this.message,
    required this.onRetry,
    required this.onOpenWebsite,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpenWebsite;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.cloud_off_outlined,
          size: 42,
          color: Color(0xffffa552),
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        const Text(
          'Manual hex and color-wheel entry are still available.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xff9da5b7)),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('retry-filament-colors'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
            TextButton.icon(
              onPressed: onOpenWebsite,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open website'),
            ),
          ],
        ),
      ],
    ),
  );
}

bool replaceInventoryItemById(
  List<InventoryItem> inventory,
  String itemId,
  InventoryItem replacement,
) {
  final index = inventory.indexWhere((candidate) => candidate.id == itemId);
  if (index < 0) return false;
  inventory[index] = replacement;
  return true;
}

final sampleInventory = <InventoryItem>[
  InventoryItem(
    id: 'INV-FIL-0001',
    name: 'Galaxy Black PETG',
    type: InventoryType.filament,
    compatibility: const ['1.75 mm', 'E3D V6'],
    added: DateTime(2026, 7, 2),
    cost: 24.99,
    color: const Color(0xff7455ff),
    dryingMinutes: 360,
    dryingRemaining: 82,
    filamentStatus: FilamentStatus.drying,
    brand: 'Polymaker',
    storageLocation: 'Dry box 1',
    lastDriedAt: DateTime(2026, 8, 12),
    vendor: 'Polymaker',
    printingInstructions:
        'Nozzle 230–250°C · Bed 70–80°C. Use moderate cooling.',
    dryingInstructions: 'Dry at 65°C for 6 hours before demanding prints.',
    storageInstructions: 'Store sealed with fresh desiccant below 20% RH.',
  ),
  InventoryItem(
    id: 'INV-NOZ-0001',
    name: 'ObXidian 0.4 mm',
    type: InventoryType.nozzle,
    compatibility: const ['E3D V6', 'Revo'],
    added: DateTime(2026, 4, 18),
    cost: 44.90,
    color: const Color(0xffffb13b),
    deployed: true,
    vendor: 'E3D',
    printingInstructions:
        'Suitable for abrasive polymers. Verify Z offset after installation.',
    storageInstructions:
        'Clean cold and store in the labeled nozzle organizer.',
  ),
  InventoryItem(
    id: 'INV-HBR-0001',
    name: 'Titanium heat break',
    type: InventoryType.heatBreak,
    compatibility: const ['E3D V6'],
    added: DateTime(2025, 11, 9),
    cost: 17.50,
    color: const Color(0xff45d2bd),
    deployed: true,
    vendor: 'E3D',
    printingInstructions:
        'Apply thermal compound only to the cold-side threads.',
    storageInstructions: 'Protect the thin throat from impact and bending.',
  ),
  InventoryItem(
    id: 'INV-HBL-0001',
    name: 'Copper heater block',
    type: InventoryType.heatBlock,
    compatibility: const ['E3D V6', '24 V'],
    added: DateTime(2026, 6, 21),
    cost: 21.00,
    color: const Color(0xffff6b6b),
    vendor: 'E3D',
    printingInstructions:
        'Hot-tighten the nozzle against the heat break, not the block.',
    storageInstructions: 'Keep heater and thermistor bores clean and capped.',
  ),
  InventoryItem(
    id: 'INV-SCK-0001',
    name: 'V6 sock — 3 pack',
    type: InventoryType.sock,
    compatibility: const ['E3D V6'],
    added: DateTime(2026, 8, 4),
    cost: 8.99,
    color: const Color(0xff55a8ff),
    vendor: 'E3D',
    storageInstructions: 'Store flat; discard if torn or contaminated.',
  ),
  InventoryItem(
    id: 'INV-FIL-0002',
    name: 'Bone White PLA',
    type: InventoryType.filament,
    compatibility: const ['1.75 mm'],
    added: DateTime(2026, 8, 11),
    cost: 19.95,
    color: const Color(0xffd5cbb7),
    dryingMinutes: 240,
    dryingRemaining: 0,
    filamentStatus: FilamentStatus.ready,
    brand: 'Overture',
    storageLocation: 'Shelf A · Bin 3',
    lastDriedAt: DateTime(2026, 8, 21),
    vendor: 'Overture',
    printingInstructions: 'Nozzle 190–220°C · Bed 45–60°C.',
    dryingInstructions: 'Dry at 50°C for 4 hours when brittle or stringing.',
    storageInstructions: 'Store sealed with desiccant below 20% RH.',
  ),
  InventoryItem(
    id: 'INV-NOZ-0002',
    name: 'Brass 0.6 mm',
    type: InventoryType.nozzle,
    compatibility: const ['E3D V6'],
    added: DateTime(2024, 9, 14),
    cost: 7.49,
    color: const Color(0xffd59a3a),
    vendor: 'Generic',
    printingInstructions:
        'Use for non-abrasive materials. Hot-tighten after installation.',
    storageInstructions: 'Clean and return to the 0.6 mm compartment.',
  ),
];

final starterVendors = <VendorRecord>[
  const VendorRecord(id: 'VEN-POLYMAKER', name: 'Polymaker', isBrand: true),
  const VendorRecord(
    id: 'VEN-PRINTED-SOLID',
    name: 'Printed Solid',
    isBrand: true,
  ),
  const VendorRecord(
    id: 'VEN-MATTERHACKERS',
    name: 'MatterHackers',
    isBrand: true,
  ),
  const VendorRecord(id: 'VEN-AMAZON', name: 'Amazon'),
  const VendorRecord(id: 'VEN-EBAY', name: 'eBay'),
];

final starterBrands = <BrandRecord>[
  const BrandRecord(
    id: 'BR-POLYMAKER',
    name: 'Polymaker',
    vendorIds: {'VEN-POLYMAKER', 'VEN-PRINTED-SOLID', 'VEN-MATTERHACKERS'},
    categories: {InventoryType.filament},
  ),
  const BrandRecord(
    id: 'BR-PRINTED-SOLID',
    name: 'Printed Solid',
    vendorIds: {'VEN-PRINTED-SOLID'},
    categories: {InventoryType.filament},
  ),
  const BrandRecord(
    id: 'BR-MATTERHACKERS',
    name: 'MatterHackers',
    vendorIds: {'VEN-MATTERHACKERS'},
    categories: {InventoryType.filament, InventoryType.resin},
  ),
  const BrandRecord(
    id: 'BR-E3D',
    name: 'E3D',
    vendorIds: {'VEN-PRINTED-SOLID'},
    categories: {
      InventoryType.nozzle,
      InventoryType.heatBreak,
      InventoryType.heatBlock,
      InventoryType.sock,
    },
  ),
];

final starterProducts = <CatalogProduct>[
  const CatalogProduct(
    id: 'PROD-POLYLITE-PLA',
    brandId: 'BR-POLYMAKER',
    category: InventoryType.filament,
    name: 'PolyLite PLA',
    defaultCost: 24.99,
    dryingMinutes: 360,
    printingInstructions: 'Nozzle 190–230°C · Bed 25–60°C.',
    dryingInstructions: 'Dry at 55°C for 6 hours.',
    storageInstructions: 'Store sealed with desiccant below 20% RH.',
  ),
  const CatalogProduct(
    id: 'PROD-E3D-OBXIDIAN-04',
    brandId: 'BR-E3D',
    category: InventoryType.nozzle,
    name: 'ObXidian 0.4 mm',
    defaultCost: 44.90,
    printingInstructions: 'Suitable for abrasive polymers. Verify Z offset.',
    storageInstructions: 'Clean cold and store in the nozzle organizer.',
  ),
];

int _nextInventoryId = 1;
String _newInventoryId() =>
    'INV-${DateTime.now().microsecondsSinceEpoch}-${_nextInventoryId++}';

typedef WorkshopState = ({
  List<InventoryItem> inventory,
  List<VendorRecord> vendors,
  List<BrandRecord> brands,
  List<SpoolTypeRecord> spoolTypes,
  List<MaterialRecord> materials,
  List<CustomItemTypeRecord> customItemTypes,
  Map<String, String> typeLabelOverrides,
  Map<String, String> typeIconOverrides,
  Map<String, bool> typeDepletionSettings,
  Map<String, bool> typeStatusSettings,
  Set<String> deletedTypeKeys,
  List<CatalogProduct> products,
  List<MachineTypeRecord> machineTypes,
  List<MachineRecord> machines,
  List<KitRecord> kits,
  List<BuildRecord> builds,
  List<StockLocationRecord> locations,
  List<ShoppingListEntry> shoppingList,
  List<AuditEntry> auditLog,
  List<AdditionHistoryEntry> additionHistory,
  int historyLimit,
});

String? _bytesToJson(Uint8List? bytes) =>
    bytes == null ? null : base64Encode(bytes);
Uint8List? _bytesFromJson(Object? value) =>
    value is String && value.isNotEmpty ? base64Decode(value) : null;

Uint8List? _createCardThumbnail(Uint8List? source) {
  if (source == null || source.isEmpty) return null;
  try {
    final decoded = img.decodeImage(source);
    if (decoded == null) return null;
    const maximumEdge = 360;
    final scale = maximumEdge / math.max(decoded.width, decoded.height);
    final thumbnail = scale < 1
        ? img.copyResize(
            decoded,
            width: math.max(1, (decoded.width * scale).round()),
            height: math.max(1, (decoded.height * scale).round()),
            interpolation: img.Interpolation.average,
          )
        : decoded;
    return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 80));
  } catch (_) {
    return null;
  }
}

bool _looksLikeFastener(String name) =>
    !name.toLowerCase().contains('printed part') &&
    RegExp(
      r'\b(screws?|bolts?|nuts?|washers?|spacers?|rivets?|clips?|zip[ -]?ties?|threaded inserts?)\b',
      caseSensitive: false,
    ).hasMatch(name);

InventoryType _migratedInventoryType(String storedType, String name) {
  final type = InventoryType.values.byName(storedType);
  if (type == InventoryType.other &&
      name.toLowerCase().contains('printed part')) {
    return InventoryType.printedPart;
  }
  return type == InventoryType.other && _looksLikeFastener(name)
      ? InventoryType.fastener
      : type;
}

MaterialRecord? _inferStarterMaterial(
  InventoryType type,
  String name,
  List<String> compatibility,
) {
  final typeKey = 'type:${type.name}';
  final source = '$name ${compatibility.join(' ')}'.toLowerCase();
  final candidates =
      starterMaterials.where((material) => material.typeKey == typeKey).toList()
        ..sort((a, b) => b.name.length.compareTo(a.name.length));
  return candidates.where((material) {
    final escaped = RegExp.escape(material.name.toLowerCase());
    return RegExp('(?:^|[^a-z0-9])$escaped(?:[^a-z0-9]|\$)').hasMatch(source);
  }).firstOrNull;
}

Map<String, dynamic> _inventoryItemJson(
  InventoryItem item, {
  bool includeBinary = true,
}) => {
  'id': item.id,
  'name': item.name,
  'type': item.type.name,
  'compatibility': item.compatibility,
  'added': item.added.toIso8601String(),
  'cost': item.cost,
  'color': item.color.toARGB32(),
  'itemColorName': item.itemColorName,
  'itemColorLabel': item.itemColorLabel,
  'quantity': item.quantity,
  'quantityAlertThreshold': item.quantityAlertThreshold,
  'dryingMinutes': item.dryingMinutes,
  'dryingRemaining': item.dryingRemaining,
  'dryingStartedAt': item.dryingStartedAt?.toIso8601String(),
  'moistureLifespanMinutes': item.moistureLifespanMinutes,
  'moistureTimeUnit': item.moistureTimeUnit.name,
  'moistureAlertEnabled': item.moistureAlertEnabled,
  'moistureAlertThresholdMinutes': item.moistureAlertThresholdMinutes,
  'deployed': item.deployed,
  'vendor': item.vendor,
  'printingInstructions': item.printingInstructions,
  'dryingInstructions': item.dryingInstructions,
  'storageInstructions': item.storageInstructions,
  'archived': item.archived,
  'archiveDisposition': item.archiveDisposition.name,
  'filamentStatus': item.filamentStatus.name,
  'brand': item.brand,
  'storageLocation': item.storageLocation,
  'storageLocationId': item.storageLocationId,
  'deploymentLocation': item.deploymentLocation,
  'lastDriedAt': item.lastDriedAt?.toIso8601String(),
  if (includeBinary) 'image': _bytesToJson(item.imageBytes),
  if (includeBinary) 'thumbnail': _bytesToJson(item.thumbnailBytes),
  if (includeBinary) 'labelImage': _bytesToJson(item.labelImageBytes),
  'barcode': item.barcode,
  'productUrl': item.productUrl,
  'compatibleMachineIds': item.compatibleMachineIds,
  'spoolTypeId': item.spoolTypeId,
  'amsCompatible': item.amsCompatible,
  'spoolTareWeightGrams': item.spoolTareWeightGrams,
  'spoolOuterDiameterMm': item.spoolOuterDiameterMm,
  'spoolWidthMm': item.spoolWidthMm,
  'spoolHoleDiameterMm': item.spoolHoleDiameterMm,
  'refill': item.refill,
  'masterSpool': item.masterSpool,
  'catalogProductId': item.catalogProductId,
  'customTypeId': item.customTypeId,
  'customTypeName': item.customTypeName,
  'customFieldValues': item.customFieldValues,
  'materialId': item.materialId,
  'materialName': item.materialName,
  'spoolMaterialId': item.spoolMaterialId,
  'spoolMaterialName': item.spoolMaterialName,
  'masterSpoolMaterialId': item.masterSpoolMaterialId,
  'masterSpoolMaterialName': item.masterSpoolMaterialName,
};

String encodeWorkshopState({
  required List<InventoryItem> inventory,
  required List<VendorRecord> vendors,
  required List<BrandRecord> brands,
  List<SpoolTypeRecord> spoolTypes = starterSpoolTypes,
  List<MaterialRecord> materials = starterMaterials,
  List<CustomItemTypeRecord> customItemTypes = const [],
  Map<String, String> typeLabelOverrides = const {},
  Map<String, String> typeIconOverrides = const {},
  Map<String, bool> typeDepletionSettings = const {},
  Map<String, bool> typeStatusSettings = const {},
  Set<String> deletedTypeKeys = const {},
  required List<CatalogProduct> products,
  List<MachineTypeRecord> machineTypes = const [],
  List<MachineRecord> machines = const [],
  List<KitRecord> kits = const [],
  List<BuildRecord> builds = const [],
  List<StockLocationRecord> locations = const [],
  List<ShoppingListEntry> shoppingList = const [],
  List<AuditEntry> auditLog = const [],
  List<AdditionHistoryEntry> additionHistory = const [],
  int historyLimit = 100,
}) => jsonEncode({
  'schemaVersion': 8,
  'inventory': inventory.map(_inventoryItemJson).toList(),
  'customItemTypes': customItemTypes
      .map(
        (type) => {
          'id': type.id,
          'name': type.name,
          'contextualFields': type.contextualFields,
          'iconKey': type.iconKey,
          'canMarkDepleted': type.canMarkDepleted,
          'showsStatus': type.showsStatus,
        },
      )
      .toList(),
  'typeLabelOverrides': typeLabelOverrides,
  'typeIconOverrides': typeIconOverrides,
  'typeDepletionSettings': typeDepletionSettings,
  'typeStatusSettings': typeStatusSettings,
  'deletedTypeKeys': deletedTypeKeys.toList(),
  'machineTypes': machineTypes
      .map(
        (type) => {'id': type.id, 'name': type.name, 'parentId': type.parentId},
      )
      .toList(),
  'machines': machines
      .map(
        (machine) => {
          'id': machine.id,
          'name': machine.name,
          'model': machine.model,
          'address': machine.address,
          'typeId': machine.typeId,
          'kitIds': machine.kitIds.toList(),
          'sourceUrls': machine.sourceUrls,
          'image': _bytesToJson(machine.imageBytes),
        },
      )
      .toList(),
  'kits': kits
      .map(
        (kit) => {
          'id': kit.id,
          'name': kit.name,
          'sections': kit.sections,
          'sourceUrls': kit.sourceUrls,
          'image': _bytesToJson(kit.imageBytes),
          'bom': kit.bom
              .map(
                (entry) => {
                  'id': entry.id,
                  'productId': entry.productId,
                  'quantity': entry.quantity,
                  if (entry.name != null) 'name': entry.name,
                  'section': entry.section,
                },
              )
              .toList(),
        },
      )
      .toList(),
  'builds': builds
      .map(
        (build) => {
          'id': build.id,
          'kitId': build.kitId,
          'name': build.name,
          'createdAt': build.createdAt.toIso8601String(),
          'createdBy': build.createdBy,
          'ownerDeviceId': build.ownerDeviceId,
          if (build.ownerUserId != null) 'ownerUserId': build.ownerUserId,
          'shared': build.shared,
          if (build.completedAt != null)
            'completedAt': build.completedAt!.toIso8601String(),
          'updatedAt': build.updatedAt.toIso8601String(),
          'lines': build.lines
              .map(
                (line) => {
                  'id': line.id,
                  'productId': line.productId,
                  'name': line.name,
                  'section': line.section,
                  'requiredQuantity': line.requiredQuantity,
                  'usedQuantity': line.usedQuantity,
                  'consumedInventoryIds': line.consumedInventoryIds,
                },
              )
              .toList(),
        },
      )
      .toList(),
  'locations': locations
      .map(
        (location) => {
          'id': location.id,
          'name': location.name,
          if (location.parentId != null) 'parentId': location.parentId,
        },
      )
      .toList(),
  'shoppingList': shoppingList
      .map(
        (entry) => {
          'id': entry.id,
          'name': entry.name,
          'productId': entry.productId,
          'quantityNeeded': entry.quantityNeeded,
          'quantityOrdered': entry.quantityOrdered,
          'quantityReceived': entry.quantityReceived,
          if (entry.kitId != null) 'kitId': entry.kitId,
          if (entry.bomLineId != null) 'bomLineId': entry.bomLineId,
          'sourceUrl': entry.sourceUrl,
          'status': entry.status.name,
        },
      )
      .toList(),
  'auditLog': auditLog
      .map(
        (entry) => {
          'id': entry.id,
          'timestamp': entry.timestamp.toIso8601String(),
          'actor': entry.actor,
          'action': entry.action,
          'entityType': entry.entityType,
          'entityId': entry.entityId,
          'changes': entry.changes,
        },
      )
      .toList(),
  'vendors': vendors
      .map(
        (vendor) => {
          'id': vendor.id,
          'name': vendor.name,
          'isBrand': vendor.isBrand,
          'logo': _bytesToJson(vendor.logoBytes),
        },
      )
      .toList(),
  'brands': brands
      .map(
        (brand) => {
          'id': brand.id,
          'name': brand.name,
          'vendorIds': brand.vendorIds.toList(),
          'categories': brand.categories.map((type) => type.name).toList(),
          'logo': _bytesToJson(brand.logoBytes),
        },
      )
      .toList(),
  'spoolTypes': spoolTypes
      .map(
        (spool) => {
          'id': spool.id,
          'label': spool.label,
          'weightGrams': spool.weightGrams,
        },
      )
      .toList(),
  'materials': materials
      .map(
        (material) => {
          'id': material.id,
          'name': material.name,
          'typeKey': material.typeKey,
        },
      )
      .toList(),
  'products': products
      .map(
        (product) => {
          'id': product.id,
          'brandId': product.brandId,
          'category': product.category.name,
          'name': product.name,
          'defaultCost': product.defaultCost,
          'dryingMinutes': product.dryingMinutes,
          'printingInstructions': product.printingInstructions,
          'dryingInstructions': product.dryingInstructions,
          'storageInstructions': product.storageInstructions,
          'sourceUrls': product.sourceUrls,
          'image': _bytesToJson(product.imageBytes),
        },
      )
      .toList(),
  'additionHistory': additionHistory
      .map(
        (entry) => {
          'id': entry.id,
          'itemId': entry.itemId,
          'name': entry.name,
          'type': entry.type.name,
          'addedAt': entry.addedAt.toIso8601String(),
          'deviceName': entry.deviceName,
        },
      )
      .toList(),
  'historyLimit': historyLimit,
});

Map<String, dynamic> encodeWorkshopEntityPayload(
  String entityType,
  Object record,
) {
  final root = jsonDecode(
    encodeWorkshopState(
      inventory: entityType == 'inventory'
          ? [record as InventoryItem]
          : const [],
      vendors: entityType == 'vendors' ? [record as VendorRecord] : const [],
      brands: entityType == 'brands' ? [record as BrandRecord] : const [],
      spoolTypes: entityType == 'spoolTypes'
          ? [record as SpoolTypeRecord]
          : const [],
      materials: entityType == 'materials'
          ? [record as MaterialRecord]
          : const [],
      customItemTypes: entityType == 'customItemTypes'
          ? [record as CustomItemTypeRecord]
          : const [],
      products: entityType == 'products'
          ? [record as CatalogProduct]
          : const [],
      machineTypes: entityType == 'machineTypes'
          ? [record as MachineTypeRecord]
          : const [],
      machines: entityType == 'machines' ? [record as MachineRecord] : const [],
      kits: entityType == 'kits' ? [record as KitRecord] : const [],
      builds: entityType == 'builds' ? [record as BuildRecord] : const [],
      locations: entityType == 'locations'
          ? [record as StockLocationRecord]
          : const [],
      shoppingList: entityType == 'shoppingList'
          ? [record as ShoppingListEntry]
          : const [],
      auditLog: entityType == 'auditLog' ? [record as AuditEntry] : const [],
      additionHistory: entityType == 'additionHistory'
          ? [record as AdditionHistoryEntry]
          : const [],
    ),
  ) as Map<String, dynamic>;
  return Map<String, dynamic>.from(
    (root[entityType] as List<dynamic>).single as Map,
  );
}

WorkshopState? decodeWorkshopState(String? source) {
  if (source == null || source.isEmpty) return null;
  try {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final schemaVersion = root['schemaVersion'] as int? ?? 1;
    final inventory = (root['inventory'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (item) => InventoryItem(
            id: item['id'] as String,
            name: item['name'] as String,
            type: _migratedInventoryType(
              item['type'] as String,
              item['name'] as String,
            ),
            compatibility: (item['compatibility'] as List).cast<String>(),
            added: DateTime.parse(item['added'] as String),
            cost: (item['cost'] as num).toDouble(),
            color: Color(item['color'] as int),
            itemColorName: _decodedItemColorName(item, schemaVersion),
            itemColorLabel: _decodedItemColorLabel(item),
            quantity: (item['quantity'] as num?)?.toDouble() ?? 1,
            quantityAlertThreshold: (item['quantityAlertThreshold'] as num?)
                ?.toDouble(),
            dryingMinutes: item['dryingMinutes'] as int?,
            dryingRemaining: item['dryingRemaining'] as int?,
            dryingStartedAt: item['dryingStartedAt'] == null
                ? null
                : DateTime.parse(item['dryingStartedAt'] as String),
            moistureLifespanMinutes:
                item['moistureLifespanMinutes'] as int? ??
                ((item['moistureLifespanDays'] as int?) == null
                    ? null
                    : (item['moistureLifespanDays'] as int) * 1440),
            moistureTimeUnit: MoistureTimeUnit.values.byName(
              item['moistureTimeUnit'] as String? ?? 'days',
            ),
            moistureAlertEnabled:
                item['moistureAlertEnabled'] as bool? ?? false,
            moistureAlertThresholdMinutes:
                item['moistureAlertThresholdMinutes'] as int? ??
                ((item['moistureAlertThresholdDays'] as int?) == null
                    ? null
                    : (item['moistureAlertThresholdDays'] as int) * 1440),
            deployed: item['deployed'] as bool? ?? false,
            vendor: item['vendor'] as String? ?? '',
            printingInstructions: item['printingInstructions'] as String? ?? '',
            dryingInstructions: item['dryingInstructions'] as String? ?? '',
            storageInstructions: item['storageInstructions'] as String? ?? '',
            archived: item['archived'] as bool? ?? false,
            archiveDisposition: ArchiveDisposition.values.byName(
              item['archiveDisposition'] as String? ?? 'archived',
            ),
            filamentStatus: FilamentStatus.values.byName(
              item['filamentStatus'] as String? ?? 'ready',
            ),
            brand: item['brand'] as String? ?? '',
            storageLocation: item['storageLocation'] as String? ?? '',
            storageLocationId: item['storageLocationId'] as String? ?? '',
            deploymentLocation: item['deploymentLocation'] as String? ?? '',
            lastDriedAt: item['lastDriedAt'] == null
                ? null
                : DateTime.parse(item['lastDriedAt'] as String),
            imageBytes: _bytesFromJson(item['image']),
            thumbnailBytes: _bytesFromJson(item['thumbnail']),
            labelImageBytes: _bytesFromJson(item['labelImage']),
            barcode: item['barcode'] as String? ?? '',
            productUrl: item['productUrl'] as String? ?? '',
            compatibleMachineIds:
                (item['compatibleMachineIds'] as List<dynamic>? ?? const [])
                    .cast<String>(),
            spoolTypeId: item['spoolTypeId'] as String? ?? defaultSpoolTypeId,
            amsCompatible: item['amsCompatible'] as bool? ?? false,
            spoolTareWeightGrams: (item['spoolTareWeightGrams'] as num?)
                ?.toDouble(),
            spoolOuterDiameterMm: (item['spoolOuterDiameterMm'] as num?)
                ?.toDouble(),
            spoolWidthMm: (item['spoolWidthMm'] as num?)?.toDouble(),
            spoolHoleDiameterMm: (item['spoolHoleDiameterMm'] as num?)
                ?.toDouble(),
            refill: item['refill'] as bool? ?? false,
            masterSpool: item['masterSpool'] as String? ?? '',
            catalogProductId: item['catalogProductId'] as String?,
            customTypeId: item['customTypeId'] as String? ?? '',
            customTypeName: item['customTypeName'] as String? ?? '',
            customFieldValues:
                (item['customFieldValues'] as Map<String, dynamic>? ?? const {})
                    .map((key, value) => MapEntry(key, value.toString())),
            materialId:
                item['materialId'] as String? ??
                _inferStarterMaterial(
                  _migratedInventoryType(
                    item['type'] as String,
                    item['name'] as String,
                  ),
                  item['name'] as String,
                  (item['compatibility'] as List).cast<String>(),
                )?.id ??
                '',
            materialName:
                item['materialName'] as String? ??
                _inferStarterMaterial(
                  _migratedInventoryType(
                    item['type'] as String,
                    item['name'] as String,
                  ),
                  item['name'] as String,
                  (item['compatibility'] as List).cast<String>(),
                )?.name ??
                '',
            spoolMaterialId: item['spoolMaterialId'] as String? ?? '',
            spoolMaterialName: item['spoolMaterialName'] as String? ?? '',
            masterSpoolMaterialId:
                item['masterSpoolMaterialId'] as String? ?? '',
            masterSpoolMaterialName:
                item['masterSpoolMaterialName'] as String? ?? '',
          ),
        )
        .toList();
    final customItemTypes =
        (root['customItemTypes'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(
              (type) => CustomItemTypeRecord(
                id: type['id'] as String,
                name: type['name'] as String,
                contextualFields:
                    (type['contextualFields'] as List<dynamic>? ?? const [])
                        .cast<String>(),
                iconKey: type['iconKey'] as String? ?? 'tune',
                canMarkDepleted: type['canMarkDepleted'] as bool? ?? false,
                showsStatus: type['showsStatus'] as bool? ?? false,
              ),
            )
            .toList();
    final typeLabelOverrides =
        (root['typeLabelOverrides'] as Map<String, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(key, value.toString()),
        );
    final typeIconOverrides =
        (root['typeIconOverrides'] as Map<String, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(key, value.toString()),
        );
    final typeDepletionSettings =
        (root['typeDepletionSettings'] as Map<String, dynamic>? ?? const {})
            .map((key, value) => MapEntry(key, value == true));
    final typeStatusSettings =
        (root['typeStatusSettings'] as Map<String, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(key, value == true),
        );
    final deletedTypeKeys =
        (root['deletedTypeKeys'] as List<dynamic>? ?? const [])
            .cast<String>()
            .toSet();
    final vendors = (root['vendors'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (vendor) => VendorRecord(
            id: vendor['id'] as String,
            name: vendor['name'] as String,
            isBrand: vendor['isBrand'] as bool? ?? false,
            logoBytes: _bytesFromJson(vendor['logo']),
          ),
        )
        .toList();
    final brands = (root['brands'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (brand) => BrandRecord(
            id: brand['id'] as String,
            name: brand['name'] as String,
            vendorIds: (brand['vendorIds'] as List).cast<String>().toSet(),
            categories: (brand['categories'] as List)
                .cast<String>()
                .map(InventoryType.values.byName)
                .toSet(),
            logoBytes: _bytesFromJson(brand['logo']),
          ),
        )
        .toList();
    final products = (root['products'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (product) => CatalogProduct(
            id: product['id'] as String,
            brandId: product['brandId'] as String,
            category: _migratedInventoryType(
              product['category'] as String,
              product['name'] as String,
            ),
            name: product['name'] as String,
            defaultCost: (product['defaultCost'] as num).toDouble(),
            dryingMinutes: product['dryingMinutes'] as int?,
            printingInstructions:
                product['printingInstructions'] as String? ?? '',
            dryingInstructions: product['dryingInstructions'] as String? ?? '',
            storageInstructions:
                product['storageInstructions'] as String? ?? '',
            sourceUrls: (product['sourceUrls'] as List<dynamic>? ?? const [])
                .cast<String>(),
            imageBytes: _bytesFromJson(product['image']),
          ),
        )
        .toList();
    final spoolTypes =
        (root['spoolTypes'] as List<dynamic>? ??
                starterSpoolTypes
                    .map(
                      (spool) => {
                        'id': spool.id,
                        'label': spool.label,
                        'weightGrams': spool.weightGrams,
                      },
                    )
                    .toList())
            .cast<Map<String, dynamic>>()
            .map(
              (spool) => SpoolTypeRecord(
                id: spool['id'] as String,
                label: spool['label'] as String,
                weightGrams: spool['weightGrams'] as int,
              ),
            )
            .toList();
    final materials =
        (root['materials'] as List<dynamic>? ??
                starterMaterials
                    .map(
                      (material) => {
                        'id': material.id,
                        'name': material.name,
                        'typeKey': material.typeKey,
                      },
                    )
                    .toList())
            .cast<Map<String, dynamic>>()
            .map(
              (material) => MaterialRecord(
                id: material['id'] as String,
                name: material['name'] as String,
                typeKey: material['typeKey'] as String,
              ),
            )
            .toList();
    for (var index = 0; index < brands.length; index++) {
      final brand = brands[index];
      final sellsFasteners = products.any(
        (product) =>
            product.brandId == brand.id &&
            product.category == InventoryType.fastener,
      );
      if (sellsFasteners &&
          !brand.categories.contains(InventoryType.fastener)) {
        brands[index] = BrandRecord(
          id: brand.id,
          name: brand.name,
          vendorIds: brand.vendorIds,
          categories: {...brand.categories, InventoryType.fastener},
          logoBytes: brand.logoBytes,
        );
      }
    }
    final machineTypes = (root['machineTypes'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (type) => MachineTypeRecord(
            id: type['id'] as String,
            name: type['name'] as String,
            parentId: type['parentId'] as String?,
          ),
        )
        .toList();
    final machines = (root['machines'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (machine) => MachineRecord(
            id: machine['id'] as String,
            name: machine['name'] as String,
            model: machine['model'] as String? ?? '',
            address: machine['address'] as String? ?? '',
            typeId: machine['typeId'] as String,
            kitIds: (machine['kitIds'] as List<dynamic>? ?? const [])
                .cast<String>()
                .toSet(),
            sourceUrls: (machine['sourceUrls'] as List<dynamic>? ?? const [])
                .cast<String>(),
            imageBytes: _bytesFromJson(machine['image']),
          ),
        )
        .toList();
    final kits = (root['kits'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (kit) => KitRecord(
            id: kit['id'] as String,
            name: kit['name'] as String,
            sections: (kit['sections'] as List<dynamic>? ?? const [])
                .cast<String>(),
            sourceUrls: (kit['sourceUrls'] as List<dynamic>? ?? const [])
                .cast<String>(),
            imageBytes: _bytesFromJson(kit['image']),
            bom: [
              for (final (index, entry)
                  in (kit['bom'] as List<dynamic>? ?? const [])
                      .cast<Map<String, dynamic>>()
                      .indexed)
                KitBomEntry(
                  id: entry['id'] as String? ?? '${kit['id']}-LINE-$index',
                  productId: entry['productId'] as String,
                  quantity: (entry['quantity'] as num).toDouble(),
                  name: entry['name'] as String?,
                  section: entry['section'] as String? ?? 'Unassigned',
                ),
            ],
          ),
        )
        .toList();
    final builds = (root['builds'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (build) => BuildRecord(
            id: build['id'] as String,
            kitId: build['kitId'] as String,
            name: build['name'] as String,
            createdAt: DateTime.parse(build['createdAt'] as String),
            createdBy: build['createdBy'] as String? ?? 'Unknown device',
            ownerDeviceId: build['ownerDeviceId'] as String? ?? '',
            ownerUserId: build['ownerUserId'] as String?,
            shared: build['shared'] as bool? ?? true,
            completedAt: build['completedAt'] == null
                ? null
                : DateTime.parse(build['completedAt'] as String),
            updatedAt: build['updatedAt'] == null
                ? null
                : DateTime.parse(build['updatedAt'] as String),
            lines: (build['lines'] as List<dynamic>? ?? const [])
                .cast<Map<String, dynamic>>()
                .map(
                  (line) => BuildLine(
                    id: line['id'] as String,
                    productId: line['productId'] as String,
                    name: line['name'] as String,
                    section: line['section'] as String? ?? 'Unassigned',
                    requiredQuantity: (line['requiredQuantity'] as num)
                        .toDouble(),
                    usedQuantity:
                        (line['usedQuantity'] as num?)?.toDouble() ?? 0,
                    consumedInventoryIds:
                        (line['consumedInventoryIds'] as List<dynamic>? ??
                                const [])
                            .cast<String>(),
                  ),
                )
                .toList(),
          ),
        )
        .toList();
    final locations = (root['locations'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (location) => StockLocationRecord(
            id: location['id'] as String,
            name: location['name'] as String,
            parentId: location['parentId'] as String?,
          ),
        )
        .toList();
    final shoppingList = (root['shoppingList'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (entry) => ShoppingListEntry(
            id: entry['id'] as String,
            name: entry['name'] as String,
            productId: entry['productId'] as String? ?? '',
            quantityNeeded: (entry['quantityNeeded'] as num?)?.toDouble() ?? 0,
            quantityOrdered:
                (entry['quantityOrdered'] as num?)?.toDouble() ?? 0,
            quantityReceived:
                (entry['quantityReceived'] as num?)?.toDouble() ?? 0,
            kitId: entry['kitId'] as String?,
            bomLineId: entry['bomLineId'] as String?,
            sourceUrl: entry['sourceUrl'] as String? ?? '',
            status: ShoppingListStatus.values.byName(
              entry['status'] as String? ?? 'needed',
            ),
          ),
        )
        .toList();
    final auditLog = (root['auditLog'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (entry) => AuditEntry(
            id: entry['id'] as String,
            timestamp: DateTime.parse(entry['timestamp'] as String),
            actor: entry['actor'] as String? ?? 'Unknown device',
            action: entry['action'] as String,
            entityType: entry['entityType'] as String,
            entityId: entry['entityId'] as String? ?? '',
            changes: (entry['changes'] as Map<String, dynamic>? ?? const {})
                .map((key, value) => MapEntry(key, value.toString())),
          ),
        )
        .toList();
    final additionHistory = root['additionHistory'] == null
        ? inventory.map(AdditionHistoryEntry.fromItem).toList()
        : (root['additionHistory'] as List)
              .cast<Map<String, dynamic>>()
              .map(
                (entry) => AdditionHistoryEntry(
                  id: entry['id'] as String,
                  itemId: entry['itemId'] as String,
                  name: entry['name'] as String,
                  type: InventoryType.values.byName(entry['type'] as String),
                  addedAt: DateTime.parse(entry['addedAt'] as String),
                  deviceName: switch (entry['deviceName'] as String?) {
                    null ||
                    'Earlier inventory' => 'Unknown device (predates tracking)',
                    final value => value,
                  },
                ),
              )
              .toList();
    return (
      inventory: inventory,
      vendors: vendors,
      brands: brands,
      spoolTypes: spoolTypes,
      materials: materials,
      customItemTypes: customItemTypes,
      typeLabelOverrides: typeLabelOverrides,
      typeIconOverrides: typeIconOverrides,
      typeDepletionSettings: typeDepletionSettings,
      typeStatusSettings: typeStatusSettings,
      deletedTypeKeys: deletedTypeKeys,
      products: products,
      machineTypes: machineTypes,
      machines: machines,
      kits: kits,
      builds: builds,
      locations: locations,
      shoppingList: shoppingList,
      auditLog: auditLog,
      additionHistory: additionHistory,
      historyLimit: root['historyLimit'] as int? ?? 100,
    );
  } catch (exception) {
    debugPrint('Could not restore Inventorinator database: $exception');
    return null;
  }
}

class _GlassButtonSurface extends StatefulWidget {
  const _GlassButtonSurface({
    required this.states,
    required this.child,
    this.joined = false,
  });

  final Set<WidgetState> states;
  final Widget? child;
  final bool joined;

  @override
  State<_GlassButtonSurface> createState() => _GlassButtonSurfaceState();
}

class _GlassButtonSurfaceState extends State<_GlassButtonSurface> {
  Timer? _hoverRiseTimer;
  Timer? _hoverSettleTimer;
  _GlassHoverPhase _hoverPhase = _GlassHoverPhase.rest;
  late bool _wasHovered;

  bool get _hovered => widget.states.contains(WidgetState.hovered);

  @override
  void initState() {
    super.initState();
    _wasHovered = _hovered;
  }

  @override
  void didUpdateWidget(covariant _GlassButtonSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_wasHovered && _hovered) {
      _cancelHoverTimers();
      _hoverPhase = _GlassHoverPhase.rest;
      _hoverRiseTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted && _hovered) {
          setState(() => _hoverPhase = _GlassHoverPhase.magenta);
        }
      });
      _hoverSettleTimer = Timer(const Duration(milliseconds: 220), () {
        if (mounted && _hovered) {
          setState(() => _hoverPhase = _GlassHoverPhase.purple);
        }
      });
    } else if (_wasHovered && !_hovered) {
      _cancelHoverTimers();
      _hoverPhase = _GlassHoverPhase.rest;
    }
    _wasHovered = _hovered;
  }

  void _cancelHoverTimers() {
    _hoverRiseTimer?.cancel();
    _hoverSettleTimer?.cancel();
  }

  @override
  void dispose() {
    _cancelHoverTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette =
        Theme.of(context).extension<InventorinatorColors>() ??
        InventorinatorColors.palettes[AppColorTheme.darkPurple]!;
    final light = Theme.of(context).brightness == Brightness.light;
    final disabled = widget.states.contains(WidgetState.disabled);
    final pressed = widget.states.contains(WidgetState.pressed);
    final selected = widget.states.contains(WidgetState.selected);
    final activeHover = _hovered && _hoverPhase != _GlassHoverPhase.rest;
    // This is the Flutter counterpart of #inventorinator-window-button in the
    // Linux runner. Keep its stops, rim, inset, shadow, and radius identical.
    final mobileTouchSurface =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final colors = disabled
        ? light
              ? [
                  Colors.white.withValues(alpha: .5),
                  palette.container.withValues(alpha: .18),
                ]
              : [
                  const Color(0x121d1f29),
                  palette.container.withValues(alpha: .07),
                ]
        : pressed
        ? [
            palette.container.withValues(alpha: .78),
            palette.base.withValues(alpha: .48),
          ]
        : _hovered && _hoverPhase == _GlassHoverPhase.magenta
        ? [palette.flash, palette.flashDark]
        : _hovered && _hoverPhase == _GlassHoverPhase.purple || selected
        ? [palette.base, palette.container]
        : light
        ? [
            Colors.white.withValues(alpha: .86),
            palette.container.withValues(alpha: .3),
          ]
        : [const Color(0x29ffffff), palette.base.withValues(alpha: .12)];
    final rim = disabled
        ? light
              ? palette.outlineVariant.withValues(alpha: .58)
              : const Color(0x1febe6ff)
        : activeHover || selected
        ? palette.rim
        : light
        ? palette.outlineVariant
        : const Color(0x38ebe6ff);
    final inset = disabled
        ? light
              ? Colors.white.withValues(alpha: .28)
              : const Color(0x0fffffff)
        : pressed
        ? const Color(0x57000000)
        : activeHover || selected
        ? palette.rim.withValues(alpha: .42)
        : light
        ? Colors.white.withValues(alpha: .92)
        : const Color(0x29ffffff);
    final radius = widget.joined
        ? BorderRadius.zero
        : BorderRadius.circular(10);
    return AnimatedContainer(
      duration: Duration(
        milliseconds: switch (_hoverPhase) {
          _GlassHoverPhase.rest => 180,
          _GlassHoverPhase.magenta => 120,
          _GlassHoverPhase.purple => 130,
        },
      ),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: radius,
        border: widget.joined ? null : Border.all(color: rim),
        boxShadow: disabled || widget.joined || mobileTouchSurface
            ? const []
            : [
                BoxShadow(
                  color: activeHover || selected
                      ? palette.container.withValues(alpha: .48)
                      : light
                      ? palette.outlineVariant.withValues(alpha: .42)
                      : const Color(0x52000000),
                  blurRadius: activeHover || selected ? 12 : 9,
                  offset: Offset(0, activeHover || selected ? 4 : 3),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child ?? const SizedBox.shrink(),
            Positioned(
              top: 0,
              left: widget.joined ? 0 : 1,
              right: widget.joined ? 0 : 1,
              height: 1,
              child: IgnorePointer(child: ColoredBox(color: inset)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassFilterChip extends StatefulWidget {
  const _GlassFilterChip({
    super.key,
    required this.selected,
    required this.child,
  });

  final bool selected;
  final Widget child;

  @override
  State<_GlassFilterChip> createState() => _GlassFilterChipState();
}

class _GlassFilterChipState extends State<_GlassFilterChip> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: _GlassButtonSurface(
      states: {
        if (hovered) WidgetState.hovered,
        if (widget.selected) WidgetState.selected,
      },
      child: widget.child,
    ),
  );
}

class _GlassSliderThumbShape extends SliderComponentShape {
  _GlassSliderThumbShape();

  static const bodySize = 30.0;
  static const preferredWidth = 92.0;
  double? _lastValue;
  double _motionBias = 0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(preferredWidth, 32);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final pressed = activationAnimation.value;
    final enabled = enableAnimation.value;
    final accent = sliderTheme.activeTrackColor ?? const Color(0xff9f8aff);
    final base = sliderTheme.thumbColor ?? const Color(0xff755da5);
    final container = Color.lerp(base, Colors.black, .35)!;
    if (pressed > .01 && _lastValue != null) {
      final delta = value - _lastValue!;
      if (delta.abs() > .00001) {
        final target = delta > 0 ? 1.0 : -1.0;
        _motionBias = ui.lerpDouble(_motionBias, target, .55)!;
      }
    } else if (pressed <= .01) {
      _motionBias = 0;
    }
    _lastValue = value;

    final stretching = math.max(0.0, _motionBias);
    final tapering = math.max(0.0, -_motionBias);
    final currentBodySize = ui.lerpDouble(bodySize, 32, pressed)!;
    final rect = Rect.fromCenter(
      center: center,
      width: currentBodySize,
      height: currentBodySize,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    final bodyPath = Path()..addRRect(rrect);
    final direction = textDirection == TextDirection.ltr ? -1.0 : 1.0;
    final tailLength = 26 + stretching * 18 - tapering * 14;
    final tailHalfHeight = 8 + stretching * 4 - tapering * 4;
    final tip = Offset(center.dx + direction * tailLength, center.dy);
    final joinX = center.dx + direction * (currentBodySize / 2 - 6);
    final tailPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..cubicTo(
        tip.dx - direction * 12,
        tip.dy - 1,
        joinX + direction * 10,
        center.dy - tailHalfHeight,
        joinX,
        center.dy - tailHalfHeight,
      )
      ..lineTo(joinX, center.dy + tailHalfHeight)
      ..cubicTo(
        joinX + direction * 10,
        center.dy + tailHalfHeight,
        tip.dx - direction * 12,
        tip.dy + 1,
        tip.dx,
        tip.dy,
      )
      ..close();

    canvas.drawPath(
      tailPath,
      Paint()
        ..color = base.withValues(
          alpha: ui.lerpDouble(.1, .3 + stretching * .12, pressed)!,
        )
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          ui.lerpDouble(3, 8 + stretching * 3, pressed)!,
        ),
    );
    canvas.drawPath(
      tailPath,
      Paint()..shader = ui.Gradient.linear(tip, center, [accent, base]),
    );

    canvas.drawShadow(
      bodyPath,
      Colors.black.withValues(alpha: .32 * enabled),
      3 + pressed,
      false,
    );
    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = base.withValues(alpha: ui.lerpDouble(.08, .24, pressed)!)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          ui.lerpDouble(3, 7, pressed)!,
        ),
    );
    // A button has an opaque surface beneath its translucent glass. Without
    // this layer, the slider track shows through and the thumb looks hollow.
    canvas.drawPath(bodyPath, Paint()..color = container);
    final top = Color.lerp(
      const Color(0x29ffffff),
      container.withValues(alpha: .78),
      pressed,
    )!;
    final bottom = Color.lerp(
      base.withValues(alpha: .12),
      base.withValues(alpha: .48),
      pressed,
    )!;
    canvas.drawPath(
      bodyPath,
      Paint()
        ..shader = ui.Gradient.linear(
          bodyPath.getBounds().topLeft,
          bodyPath.getBounds().bottomRight,
          [top, bottom],
        ),
    );
    canvas.drawPath(
      bodyPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.lerp(
          const Color(0x38ebe6ff),
          Color.lerp(base, Colors.white, .16)!,
          pressed,
        )!,
    );
    canvas.drawLine(
      Offset(rect.left + 7, rect.top + 1.5),
      Offset(rect.right - 7, rect.top + 1.5),
      Paint()
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(
          const Color(0x29ffffff),
          const Color(0x57000000),
          pressed,
        )!,
    );
  }
}

enum _GlassHoverPhase { rest, magenta, purple }

class InventorinatorApp extends StatefulWidget {
  const InventorinatorApp({
    super.key,
    this.database,
    this.persistedState,
    this.filamentColorsClient,
  });
  final LocalDatabase? database;
  final String? persistedState;
  final FilamentColorsClient? filamentColorsClient;

  @override
  State<InventorinatorApp> createState() => _InventorinatorAppState();
}

class _InventorinatorAppState extends State<InventorinatorApp> {
  static const _nativeThemeChannel = MethodChannel(
    'media.everlasting.inventorinator/theme',
  );
  late AppColorTheme colorTheme;
  late AppBrightnessMode brightnessMode;
  late Color customThemeColor;

  @override
  void initState() {
    super.initState();
    final saved = widget.database?.loadStringPreference(
      'app_color_theme',
      fallback: AppColorTheme.darkPurple.name,
    );
    final savedBrightness = widget.database?.loadStringPreference(
      'app_brightness_mode',
      fallback: saved == 'light'
          ? AppBrightnessMode.light.name
          : AppBrightnessMode.dark.name,
    );
    colorTheme =
        AppColorTheme.values
            .where((value) => value.name == saved)
            .firstOrNull ??
        AppColorTheme.darkPurple;
    brightnessMode =
        AppBrightnessMode.values
            .where((value) => value.name == savedBrightness)
            .firstOrNull ??
        AppBrightnessMode.dark;
    customThemeColor =
        _hexColor(
          widget.database?.loadStringPreference(
                'app_custom_theme_color',
                fallback: '#8E75FF',
              ) ??
              '#8E75FF',
        ) ??
        const Color(0xff8e75ff);
    _applySystemColors();
  }

  void _applySystemColors() {
    final palette = InventorinatorColors.forTheme(
      colorTheme,
      customColor: customThemeColor,
      brightness: brightnessMode,
    );
    final canvas = palette.canvas;
    final iconBrightness = brightnessMode == AppBrightnessMode.light
        ? Brightness.dark
        : Brightness.light;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: canvas,
        statusBarIconBrightness: iconBrightness,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: canvas,
        systemNavigationBarDividerColor: canvas,
        systemNavigationBarIconBrightness: iconBrightness,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    if (!kIsWeb && Platform.isLinux) {
      unawaited(
        _nativeThemeChannel
            .invokeMethod<void>('setTheme', {
              'theme': colorTheme.name,
              'canvas': _colorHex(palette.canvas),
              'surface': _colorHex(palette.surface),
              'base': _colorHex(palette.base),
              'container': _colorHex(palette.container),
              'flash': _colorHex(palette.flash),
              'flashDark': _colorHex(palette.flashDark),
              'outlineVariant': _colorHex(palette.outlineVariant),
              'rim': _colorHex(palette.rim),
              'accent': _colorHex(palette.accent),
              'foreground': brightnessMode == AppBrightnessMode.light
                  ? '#211A2D'
                  : '#EEEAFF',
            })
            .catchError((_) {}),
      );
    }
  }

  void _setColorTheme(AppColorTheme value) {
    if (value == colorTheme) return;
    setState(() => colorTheme = value);
    widget.database?.saveStringPreference('app_color_theme', value.name);
    _applySystemColors();
  }

  void _setBrightnessMode(AppBrightnessMode value) {
    if (value == brightnessMode) return;
    setState(() => brightnessMode = value);
    widget.database?.saveStringPreference('app_brightness_mode', value.name);
    _applySystemColors();
  }

  void _setCustomThemeColor(Color value) {
    setState(() {
      customThemeColor = value;
      colorTheme = AppColorTheme.custom;
    });
    widget.database?.saveStringPreference(
      'app_custom_theme_color',
      _colorHex(value),
    );
    widget.database?.saveStringPreference(
      'app_color_theme',
      AppColorTheme.custom.name,
    );
    _applySystemColors();
  }

  @override
  Widget build(BuildContext context) {
    final palette = InventorinatorColors.forTheme(
      colorTheme,
      customColor: customThemeColor,
      brightness: brightnessMode,
    );
    final light = brightnessMode == AppBrightnessMode.light;
    final brightness = light ? Brightness.light : Brightness.dark;
    final foreground = light
        ? const Color(0xff211a2d)
        : const Color(0xffeeeaff);
    final mutedForeground = light
        ? const Color(0xff625b6d)
        : const Color(0xff929aac);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: palette.base,
          brightness: brightness,
          surface: palette.surface,
        ).copyWith(
          primary: palette.accent,
          onPrimary: light ? Colors.white : palette.canvas,
          primaryContainer: palette.container,
          onPrimaryContainer: foreground,
          secondary: light ? const Color(0xff08766c) : const Color(0xff45d2bd),
          onSecondary: light ? Colors.white : palette.canvas,
          secondaryContainer: light
              ? const Color(0xffc3eee8)
              : const Color(0xff173d3b),
          onSecondaryContainer: light
              ? const Color(0xff073e39)
              : const Color(0xffd8fff8),
          error: light ? const Color(0xffb42336) : const Color(0xffff6b7a),
          onError: light ? Colors.white : const Color(0xff240006),
          surface: palette.surface,
          surfaceContainerLowest: palette.canvas,
          surfaceContainerLow: palette.panel,
          surfaceContainer: palette.surface,
          surfaceContainerHigh: Color.lerp(
            palette.surface,
            light ? palette.container : Colors.white,
            light ? .28 : .035,
          ),
          onSurface: foreground,
          onSurfaceVariant: mutedForeground,
          outline: palette.outline,
          outlineVariant: palette.outlineVariant,
        );
    final glassForeground = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return light ? const Color(0xff938b9e) : const Color(0xff6f7180);
      }
      if (light &&
          !states.contains(WidgetState.hovered) &&
          !states.contains(WidgetState.pressed) &&
          !states.contains(WidgetState.selected)) {
        return foreground;
      }
      return const Color(0xffeeeaff);
    });
    Widget glassButtonLayer(
      BuildContext context,
      Set<WidgetState> states,
      Widget? child,
    ) => _GlassButtonSurface(states: states, child: child);

    final glassButtonStyle = ButtonStyle(
      animationDuration: const Duration(milliseconds: 180),
      foregroundColor: glassForeground,
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      side: const WidgetStatePropertyAll(BorderSide.none),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      backgroundBuilder: glassButtonLayer,
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Inventorinator',
      theme: ThemeData(
        brightness: brightness,
        colorScheme: scheme,
        extensions: [palette],
        scaffoldBackgroundColor: palette.canvas,
        useMaterial3: true,
        outlinedButtonTheme: OutlinedButtonThemeData(style: glassButtonStyle),
        filledButtonTheme: FilledButtonThemeData(style: glassButtonStyle),
        elevatedButtonTheme: ElevatedButtonThemeData(style: glassButtonStyle),
        textButtonTheme: TextButtonThemeData(style: glassButtonStyle),
        iconButtonTheme: IconButtonThemeData(
          style: glassButtonStyle.copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: glassButtonStyle.copyWith(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: palette.surface,
          foregroundColor: foreground,
          hoverColor: palette.base,
          focusColor: palette.container,
          elevation: 4,
          hoverElevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            side: BorderSide(color: palette.outline),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: palette.surface,
          selectedColor: palette.container,
          disabledColor: light
              ? const Color(0xffe3dee9)
              : const Color(0xff1a1c25),
          side: BorderSide(color: palette.outline),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          labelStyle: TextStyle(color: foreground),
          secondaryLabelStyle: TextStyle(color: foreground),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: palette.input,
          labelStyle: TextStyle(
            color: mutedForeground,
            fontWeight: FontWeight.w600,
          ),
          floatingLabelStyle: TextStyle(
            color: palette.accent,
            fontWeight: FontWeight.w700,
          ),
          hintStyle: TextStyle(
            color: light ? const Color(0xff777080) : const Color(0xff687185),
          ),
          helperStyle: TextStyle(color: mutedForeground),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: palette.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: palette.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: palette.accent, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xffff6b7a)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xffff6b7a), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
        ),
        cardTheme: CardThemeData(
          color: palette.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: palette.outlineVariant),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: palette.surface,
          elevation: 20,
          shadowColor: palette.accent.withValues(alpha: .28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: palette.accent.withValues(alpha: .28)),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: palette.panel,
          surfaceTintColor: Colors.transparent,
          elevation: 18,
          shadowColor: palette.accent.withValues(alpha: .32),
          menuPadding: const EdgeInsets.symmetric(vertical: 8),
          textStyle: TextStyle(
            color: foreground,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: palette.outlineVariant),
          ),
        ),
        menuTheme: MenuThemeData(
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(palette.panel),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
        ),
        dropdownMenuTheme: DropdownMenuThemeData(
          textStyle: TextStyle(color: foreground),
          menuStyle: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(palette.panel),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
        ),
        hoverColor: palette.base.withValues(alpha: .35),
        splashColor: palette.container.withValues(alpha: .55),
      ),
      home: InventoryHome(
        database: widget.database,
        persistedState: widget.persistedState,
        filamentColorsClient: widget.filamentColorsClient,
        colorTheme: colorTheme,
        brightnessMode: brightnessMode,
        customThemeColor: customThemeColor,
        onColorThemeChanged: _setColorTheme,
        onBrightnessModeChanged: _setBrightnessMode,
        onCustomThemeColorChanged: _setCustomThemeColor,
      ),
    );
  }
}

class _CenteredSquareGridDelegate extends SliverGridDelegate {
  const _CenteredSquareGridDelegate({
    required this.cardExtent,
    required this.spacing,
  });

  final double cardExtent;
  final double spacing;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final extent = math.min(cardExtent, constraints.crossAxisExtent);
    final count = math.max(
      1,
      ((constraints.crossAxisExtent + spacing) / (extent + spacing)).floor(),
    );
    final occupied = (count * extent) + ((count - 1) * spacing);
    return _CenteredSquareGridLayout(
      crossAxisCount: count,
      cardExtent: extent,
      spacing: spacing,
      leadingSpace: math.max(0, (constraints.crossAxisExtent - occupied) / 2),
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
      crossAxisExtent: constraints.crossAxisExtent,
    );
  }

  @override
  bool shouldRelayout(covariant _CenteredSquareGridDelegate oldDelegate) =>
      cardExtent != oldDelegate.cardExtent || spacing != oldDelegate.spacing;
}

class _CenteredSquareGridLayout extends SliverGridLayout {
  const _CenteredSquareGridLayout({
    required this.crossAxisCount,
    required this.cardExtent,
    required this.spacing,
    required this.leadingSpace,
    required this.reverseCrossAxis,
    required this.crossAxisExtent,
  });

  final int crossAxisCount;
  final double cardExtent;
  final double spacing;
  final double leadingSpace;
  final bool reverseCrossAxis;
  final double crossAxisExtent;

  double get stride => cardExtent + spacing;

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) =>
      crossAxisCount * (scrollOffset ~/ stride);

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) =>
      math.max(0, crossAxisCount * (scrollOffset / stride).ceil() - 1);

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final row = index ~/ crossAxisCount;
    final column = index % crossAxisCount;
    final naturalOffset = leadingSpace + (column * stride);
    return SliverGridGeometry(
      scrollOffset: row * stride,
      crossAxisOffset: reverseCrossAxis
          ? crossAxisExtent - naturalOffset - cardExtent
          : naturalOffset,
      mainAxisExtent: cardExtent,
      crossAxisExtent: cardExtent,
    );
  }

  @override
  double computeMaxScrollOffset(int childCount) {
    if (childCount == 0) return 0;
    final rowCount = ((childCount - 1) ~/ crossAxisCount) + 1;
    return (rowCount * cardExtent) + ((rowCount - 1) * spacing);
  }
}

class _SmoothWheelScrollController extends ScrollController {
  _SmoothWheelScrollController({required this.enabled});

  final bool enabled;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SmoothWheelScrollPosition(
    smoothWheelEnabled: enabled,
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

class _SmoothWheelScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothWheelScrollPosition({
    required this.smoothWheelEnabled,
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  final bool smoothWheelEnabled;
  late final Ticker _wheelTicker = context.vsync.createTicker(_tickWheel);
  static const double _wheelDecaySeconds = .075;
  static const double _maximumWheelVelocity = 7200;
  double _wheelVelocity = 0;
  Duration? _lastWheelTick;
  bool _wheelScrollActive = false;

  @override
  void pointerScroll(double delta) {
    if (!smoothWheelEnabled) {
      super.pointerScroll(delta);
      return;
    }
    if (delta == 0) {
      if (_wheelTicker.isActive) {
        _finishWheelScroll();
      } else {
        goBallistic(0);
      }
      return;
    }
    final target = (pixels + delta)
        .clamp(minScrollExtent, maxScrollExtent)
        .toDouble();
    if (target == pixels && _wheelVelocity.sign == delta.sign) {
      if (_wheelTicker.isActive) {
        _finishWheelScroll();
      } else {
        goBallistic(0);
      }
      return;
    }
    _wheelVelocity = (_wheelVelocity + (delta / _wheelDecaySeconds)).clamp(
      -_maximumWheelVelocity,
      _maximumWheelVelocity,
    );
    updateUserScrollDirection(
      delta < 0 ? ScrollDirection.forward : ScrollDirection.reverse,
    );
    if (_wheelTicker.isActive) return;
    goIdle();
    isScrollingNotifier.value = true;
    didStartScroll();
    _wheelScrollActive = true;
    _lastWheelTick = null;
    _wheelTicker.start();
  }

  void _tickWheel(Duration elapsed) {
    final previousTick = _lastWheelTick;
    _lastWheelTick = elapsed;
    if (previousTick == null) return;
    final elapsedSeconds = (elapsed - previousTick).inMicroseconds / 1000000;
    if (elapsedSeconds <= 0) return;
    // A delayed desktop frame should extend the glide, not turn all of the
    // missed time into one large, visible jump when scheduling resumes.
    final seconds = math.min(elapsedSeconds, 1 / 30);
    final decay = math.exp(-seconds / _wheelDecaySeconds);
    final oldPixels = pixels;
    final distance = _wheelVelocity * _wheelDecaySeconds * (1 - decay);
    final next = (oldPixels + distance)
        .clamp(minScrollExtent, maxScrollExtent)
        .toDouble();
    forcePixels(next);
    didUpdateScrollPositionBy(pixels - oldPixels);
    _wheelVelocity *= decay;
    if (next == oldPixels || _wheelVelocity.abs() < 4) {
      _finishWheelScroll();
    }
  }

  void _finishWheelScroll() {
    _wheelTicker.stop();
    _lastWheelTick = null;
    _wheelVelocity = 0;
    if (_wheelScrollActive) {
      _wheelScrollActive = false;
      didEndScroll();
    }
    goBallistic(0);
  }

  @override
  void dispose() {
    _wheelTicker.dispose();
    super.dispose();
  }
}

class InventoryHome extends StatefulWidget {
  const InventoryHome({
    super.key,
    this.database,
    this.persistedState,
    this.filamentColorsClient,
    this.colorTheme = AppColorTheme.darkPurple,
    this.brightnessMode = AppBrightnessMode.dark,
    this.customThemeColor = const Color(0xff8e75ff),
    this.onColorThemeChanged,
    this.onBrightnessModeChanged,
    this.onCustomThemeColorChanged,
  });
  final LocalDatabase? database;
  final String? persistedState;
  final FilamentColorsClient? filamentColorsClient;
  final AppColorTheme colorTheme;
  final AppBrightnessMode brightnessMode;
  final Color customThemeColor;
  final ValueChanged<AppColorTheme>? onColorThemeChanged;
  final ValueChanged<AppBrightnessMode>? onBrightnessModeChanged;
  final ValueChanged<Color>? onCustomThemeColorChanged;
  @override
  State<InventoryHome> createState() => _InventoryHomeState();
}

class _InventoryHomeState extends State<InventoryHome> {
  late final FilamentColorsClient _filamentColorsClient;
  late final bool _ownsFilamentColorsClient;
  late final List<InventoryItem> inventory;
  late final List<VendorRecord> vendors;
  late final List<BrandRecord> brands;
  late final List<SpoolTypeRecord> spoolTypes;
  late final List<MaterialRecord> materials;
  late final List<CustomItemTypeRecord> customItemTypes;
  late final Map<String, String> typeLabelOverrides;
  late final Map<String, String> typeIconOverrides;
  late final Map<String, bool> typeDepletionSettings;
  late final Map<String, bool> typeStatusSettings;
  late final Set<String> deletedTypeKeys;
  late final List<CatalogProduct> products;
  late final List<MachineTypeRecord> machineTypes;
  late final List<MachineRecord> machines;
  late final List<KitRecord> kits;
  late final List<BuildRecord> builds;
  late final List<StockLocationRecord> locations;
  late final List<ShoppingListEntry> shoppingList;
  late final List<AuditEntry> auditLog;
  late final List<AdditionHistoryEntry> additionHistory;
  late int historyLimit;
  late bool syncChimeEnabled;
  late bool dryingCompleteChimeEnabled;
  late bool moistureAlertChimeEnabled;
  late int animationDurationPercent;
  late int animationRecurrenceSeconds;
  late bool photoCardsEnabled;
  late CustomIconAnimationMode customIconAnimationMode;
  late final Set<String> _moistureAlertChimedCycles;
  late final Set<String> _readInventoryAlertKeys;
  late String deviceName;
  late String deviceId;
  String? currentUserId;
  bool gridView = true;
  bool hideZeroQuantityItems = false;
  bool archivedOnly = false;
  CatalogViewFilter? catalogFilter;
  String query = '';
  InventoryType? type;
  String? customTypeFilterId;
  String? itemColorFilter;
  final TextEditingController inventorySearchController =
      TextEditingController();
  final FocusNode inventorySearchFocusNode = FocusNode(
    debugLabel: 'Inventory search',
  );
  final Set<String> selectedInventoryIds = {};
  final Set<String> selectedBuildIds = {};
  final Set<String> selectedKitIds = {};
  final Set<String> selectedMachineIds = {};
  InventorySort sort = InventorySort.type;
  static const _pageSizes = [12, 25, 100, 250, 1000];
  static const _minimumCardSizePercent = 75.0;
  static const _maximumCardSizePercent = 150.0;
  final _pageSizeThumbShape = _GlassSliderThumbShape();
  final _cardSizeThumbShape = _GlassSliderThumbShape();
  final ValueNotifier<double> _pageSizeSliderValue = ValueNotifier(0);
  final ValueNotifier<double> _cardSizeSliderValue = ValueNotifier(100);
  Timer? _pageSizeCommitTimer;
  Timer? _cardSizeCommitTimer;
  int pageSizeIndex = 0;
  double cardSizePercent = 100;
  int currentPage = 0;
  final ScrollController inventoryScrollController =
      _SmoothWheelScrollController(
        enabled: Platform.isLinux || Platform.isWindows,
      );
  final ValueNotifier<bool> _inventoryIsScrolling = ValueNotifier(false);
  Timer? _inventoryOverlayRestore;
  final ExpansibleController typeFilterExpansionController =
      ExpansibleController();
  final ExpansibleController colorFilterExpansionController =
      ExpansibleController();
  bool typePanelExpanded = false;
  bool colorPanelExpanded = false;
  Timer? _syncDebounce;
  Timer? _deferredAutoSync;
  Timer? _syncPoll;
  final Map<String, Timer> _quantityCommitTimers = {};
  final Map<String, InventoryItem> _quantityCommitOriginals = {};
  int _localStateRevision = 0;
  int _lastSyncedLocalRevision = 0;
  bool _syncRequestedWhileBusy = false;
  bool _thumbnailBackfillRunning = false;
  Timer? _clockTick;
  bool _syncing = false;
  bool _autoSyncPausedForAuthentication = false;
  bool _applyingCloudState = false;
  final List<Map<String, Object?>> _pendingAuditEvents = [];
  WorkspaceRole currentRole = WorkspaceRole.admin;
  bool workspaceOwner = true;
  final Map<String, int> _remoteQuantityAnimationVersions = {};
  final Map<String, int> _lowStockAnimationVersions = {};
  final Map<String, int> _moistureAnimationVersions = {};
  final Set<String> _moistureAnimationCycles = {};
  static final RegExp _searchNormalizationPattern = RegExp(r'[^a-z0-9]');
  int _searchDataRevision = 0;
  final Map<String, (InventoryItem, String)> _inventorySearchTextCache = {};
  final Map<String, ValueNotifier<InventoryItem>> _inventoryItemNotifiers = {};
  final Map<String, Map<String, Object>> _persistedEntityReferences = {};
  Map<String, dynamic> _persistedMetadata = const {};
  bool _incrementalPersistenceReady = false;
  final Map<Object, String> _catalogSearchTextCache = Map.identity();
  Object? _visibleItemsCacheKey;
  List<InventoryItem>? _visibleItemsCache;
  Object? _visibleCatalogRecordsCacheKey;
  List<Object>? _visibleCatalogRecordsCache;
  Object? _visibleEverythingCatalogRecordsCacheKey;
  List<Object>? _visibleEverythingCatalogRecordsCache;
  Object? _availableItemColorFiltersCacheKey;
  List<({String value, String label, String hex})>?
  _availableItemColorFiltersCache;
  double itemDetailsPanelWidth = 520;
  static const _audioChannel = MethodChannel('inventorinator/audio');
  static const _deviceChannel = MethodChannel('inventorinator/device');

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleInventoryShortcut);
    _ownsFilamentColorsClient = widget.filamentColorsClient == null;
    _filamentColorsClient =
        widget.filamentColorsClient ??
        FilamentColorsClient(
          cacheRead: widget.database?.loadApiCache,
          cacheWrite: widget.database?.saveApiCache,
        );
    final syncConfigSource = widget.database?.loadSyncConfig();
    if (syncConfigSource != null) {
      try {
        final config = SupabaseConfig.fromJson(
          jsonDecode(syncConfigSource) as Map<String, dynamic>,
        );
        if (config.syncMode == 'supabase') {
          currentRole = WorkspaceRole.fromServer(config.workspaceRole);
          final hasOwnerRecovery =
              config.workspaceId != null &&
              widget.database?.loadWorkspaceRecoveryKey(config.workspaceId!) !=
                  null;
          workspaceOwner = config.workspaceRole == 'owner' || hasOwnerRecovery;
          if (hasOwnerRecovery) currentRole = WorkspaceRole.admin;
          currentUserId = config.userId;
        }
      } catch (_) {
        // A malformed sync preference must not prevent local inventory access.
      }
    }
    final restored = decodeWorkshopState(widget.persistedState);
    final firstLaunch =
        widget.database != null && widget.persistedState == null;
    inventory =
        restored?.inventory ??
        (firstLaunch ? <InventoryItem>[] : [...sampleInventory]);
    final initializedDryingTimers = _initializeDryingTimers();
    vendors = restored?.vendors ?? [...starterVendors];
    brands = restored?.brands ?? [...starterBrands];
    spoolTypes = restored?.spoolTypes ?? [...starterSpoolTypes];
    materials = restored?.materials ?? [...starterMaterials];
    var initializedMaterials = false;
    for (var index = 0; index < inventory.length; index++) {
      final item = inventory[index];
      if (item.materialName.isNotEmpty) continue;
      final inferred = _inferStarterMaterial(
        item.type,
        item.name,
        item.compatibility,
      );
      if (inferred != null) {
        inventory[index] = item.copyWith(
          materialId: inferred.id,
          materialName: inferred.name,
        );
        initializedMaterials = true;
      }
    }
    customItemTypes = restored?.customItemTypes ?? [];
    typeLabelOverrides = {...?restored?.typeLabelOverrides};
    typeIconOverrides = {...?restored?.typeIconOverrides};
    typeDepletionSettings = {...?restored?.typeDepletionSettings};
    typeStatusSettings = {...?restored?.typeStatusSettings};
    deletedTypeKeys = {...?restored?.deletedTypeKeys};
    products = restored?.products ?? [...starterProducts];
    machineTypes = restored?.machineTypes ?? [];
    machines = restored?.machines ?? [];
    kits = restored?.kits ?? [];
    builds = restored?.builds ?? [];
    locations = restored?.locations ?? [];
    shoppingList = restored?.shoppingList ?? [];
    final initializedLocations = _initializeLegacyLocations();
    for (final item in inventory) {
      _inventoryItemNotifiers[item.id] = ValueNotifier(item);
    }
    auditLog = restored?.auditLog ?? [];
    additionHistory =
        restored?.additionHistory ??
        (firstLaunch
            ? <AdditionHistoryEntry>[]
            : inventory.map(AdditionHistoryEntry.fromItem).toList());
    historyLimit = restored?.historyLimit ?? 100;
    final initializedKitSections = _initializeKitSections();
    syncChimeEnabled =
        widget.database?.loadBoolPreference(
          'sync_chime_enabled',
          fallback: true,
        ) ??
        true;
    dryingCompleteChimeEnabled =
        widget.database?.loadBoolPreference(
          'drying_complete_chime_enabled',
          fallback: true,
        ) ??
        true;
    moistureAlertChimeEnabled =
        widget.database?.loadBoolPreference(
          'moisture_alert_chime_enabled',
          fallback: true,
        ) ??
        true;
    cardSizePercent =
        (double.tryParse(
                  widget.database?.loadStringPreference(
                        'inventory_card_size_percent',
                        fallback: '100',
                      ) ??
                      '100',
                ) ??
                100)
            .clamp(_minimumCardSizePercent, _maximumCardSizePercent);
    _pageSizeSliderValue.value = pageSizeIndex.toDouble();
    _cardSizeSliderValue.value = cardSizePercent;
    animationDurationPercent =
        (int.tryParse(
                  widget.database?.loadStringPreference(
                        'animation_duration_percent',
                        fallback: '100',
                      ) ??
                      '100',
                ) ??
                100)
            .clamp(25, 200);
    final savedRecurrenceSeconds =
        int.tryParse(
          widget.database?.loadStringPreference(
                'animation_recurrence_seconds',
                fallback: '5',
              ) ??
              '5',
        ) ??
        5;
    animationRecurrenceSeconds =
        const {0, 3, 5, 10, 30}.contains(savedRecurrenceSeconds)
        ? savedRecurrenceSeconds
        : 5;
    photoCardsEnabled =
        widget.database?.loadBoolPreference(
          'photo_cards_enabled',
          fallback: false,
        ) ??
        false;
    hideZeroQuantityItems =
        widget.database?.loadBoolPreference(
          'hide_zero_quantity_items',
          fallback: false,
        ) ??
        false;
    customIconAnimationMode = _customIconAnimationModeFromName(
      widget.database?.loadStringPreference(
        'custom_icon_animation_mode',
        fallback: CustomIconAnimationMode.interaction.name,
      ),
    );
    try {
      _moistureAlertChimedCycles = {
        ...((jsonDecode(
          widget.database?.loadStringPreference(
                'moisture_alert_chimed_cycles',
                fallback: '[]',
              ) ??
              '[]',
        ) as List).cast<String>()),
      };
    } catch (_) {
      _moistureAlertChimedCycles = <String>{};
    }
    try {
      _readInventoryAlertKeys = {
        ...((jsonDecode(
          widget.database?.loadStringPreference(
                'read_inventory_alert_keys',
                fallback: '[]',
              ) ??
              '[]',
        ) as List).cast<String>()),
      };
    } catch (_) {
      _readInventoryAlertKeys = <String>{};
    }
    _reconcileReadInventoryAlerts();
    final hostName = Platform.localHostname.trim();
    final defaultDeviceName = Platform.isAndroid
        ? 'Android device'
        : hostName.isNotEmpty && hostName != 'localhost'
        ? hostName
        : 'This device';
    deviceName =
        widget.database?.loadStringPreference(
          'device_name',
          fallback: defaultDeviceName,
        ) ??
        defaultDeviceName;
    deviceId =
        widget.database?.loadStringPreference('device_id', fallback: '') ?? '';
    if (deviceId.isEmpty) {
      deviceId = 'DEVICE-${DateTime.now().microsecondsSinceEpoch}';
      widget.database?.saveStringPreference('device_id', deviceId);
    }
    if (Platform.isAndroid
        ? isGenericAndroidDeviceName(deviceName)
        : const {'Unnamed device', 'This device'}.contains(deviceName)) {
      deviceName = defaultDeviceName;
    }
    widget.database?.saveStringPreference('device_name', deviceName);
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadAndroidDeviceName(),
      );
    }
    _trimAdditionHistory();
    _clockTick = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _advanceDryingTimers(),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_backfillInventoryThumbnails()),
    );
    if (initializedDryingTimers ||
        initializedKitSections ||
        initializedMaterials ||
        initializedLocations) {
      _persist();
    }
    if (!firstLaunch) {
      _capturePersistedEntityReferences();
      _incrementalPersistenceReady = true;
    }
    if (firstLaunch) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _completeFirstLaunch(),
      );
    } else if (_needsSyncOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openSyncOnboarding(),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoSync());
    }
  }

  Future<void> _completeFirstLaunch() async {
    final loadDemoItems = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start your inventory'),
        content: const SizedBox(
          width: 500,
          child: Text(
            'Begin with an empty inventory, or load a few demo items to explore Inventorinator. Demo items can be deleted later.',
          ),
        ),
        actions: [
          OutlinedButton(
            key: const Key('load-demo-inventory'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Load demo items'),
          ),
          FilledButton(
            key: const Key('start-empty-inventory'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Start empty'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (loadDemoItems == true) {
      setState(() {
        inventory.addAll(sampleInventory);
        _initializeDryingTimers();
        additionHistory.addAll(
          inventory.map(
            (item) => AdditionHistoryEntry.fromItem(
              item,
              deviceName: 'Demo inventory',
            ),
          ),
        );
      });
    }
    _persist();
    _capturePersistedEntityReferences();
    _incrementalPersistenceReady = true;
    if (_needsSyncOnboarding) {
      await _openSyncOnboarding();
    } else {
      _startAutoSync();
    }
  }

  Future<void> _loadAndroidDeviceName() async {
    if (isGenericAndroidDeviceName(deviceName)) {
      try {
        final resolved = (await _deviceChannel.invokeMethod<String>(
          'getDeviceName',
        ))?.trim();
        if (resolved != null && resolved.isNotEmpty && mounted) {
          setState(() => deviceName = resolved);
          widget.database?.saveStringPreference('device_name', resolved);
        }
      } catch (error) {
        debugPrint('Could not read Android device name: $error');
      }
    }
    if (!mounted || widget.database == null) return;
    final confirmed = widget.database!.loadBoolPreference(
      'device_name_confirmed',
      fallback: false,
    );
    if (confirmed) return;
    final savedSync = widget.database!.loadSyncConfig();
    if (savedSync == null) return;
    try {
      final config = SupabaseConfig.fromJson(
        jsonDecode(savedSync) as Map<String, dynamic>,
      );
      if (!config.hasSession || config.workspaceId == null) return;
    } catch (_) {
      return;
    }
    if (await _renameThisDevice()) unawaited(_syncAutomatically());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleInventoryShortcut);
    _syncDebounce?.cancel();
    _deferredAutoSync?.cancel();
    _syncPoll?.cancel();
    _clockTick?.cancel();
    _pageSizeCommitTimer?.cancel();
    _cardSizeCommitTimer?.cancel();
    pageSizeIndex = _pageSizeSliderValue.value.round();
    cardSizePercent = _cardSizeSliderValue.value;
    widget.database?.saveStringPreference(
      'inventory_card_size_percent',
      cardSizePercent.toStringAsFixed(1),
    );
    _pageSizeSliderValue.dispose();
    _cardSizeSliderValue.dispose();
    for (final timer in _quantityCommitTimers.values) {
      timer.cancel();
    }
    if (_quantityCommitOriginals.isNotEmpty) {
      for (final entry in _quantityCommitOriginals.entries) {
        if (!_recordPendingQuantityAudit(entry.key, entry.value)) continue;
        final current = inventory
            .where((item) => item.id == entry.key)
            .firstOrNull;
        if (current != null && widget.database != null) {
          _saveInventoryEntity(
            widget.database!,
            current,
            previous: entry.value,
          );
        }
      }
    }
    _inventoryOverlayRestore?.cancel();
    _inventoryIsScrolling.dispose();
    for (final notifier in _inventoryItemNotifiers.values) {
      notifier.dispose();
    }
    if (_ownsFilamentColorsClient) _filamentColorsClient.close();
    inventorySearchController.dispose();
    inventorySearchFocusNode.dispose();
    inventoryScrollController.dispose();
    super.dispose();
  }

  bool _handleInventoryShortcut(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyF ||
        !HardwareKeyboard.instance.isControlPressed ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    inventorySearchFocusNode.requestFocus();
    inventorySearchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: inventorySearchController.text.length,
    );
    return true;
  }

  bool _initializeDryingTimers() {
    var changed = false;
    final now = DateTime.now();
    for (var index = 0; index < inventory.length; index++) {
      final item = inventory[index];
      if (item.type == InventoryType.filament &&
          item.filamentStatus == FilamentStatus.drying &&
          item.dryingStartedAt == null) {
        inventory[index] = item.copyWith(dryingStartedAt: now);
        changed = true;
      }
    }
    return changed;
  }

  bool _initializeKitSections() {
    final kitIndex = kits.indexWhere(
      (kit) =>
          kit.id == 'KIT-ORIGINAL-PRUSA-I3-MK3S-PLUS' &&
          kit.bom.isNotEmpty &&
          kit.bom.every((line) => line.section == 'Unassigned'),
    );
    if (kitIndex < 0) return false;

    final kit = kits[kitIndex];
    const allocations = <String, List<(String, double)>>{
      'PROD-MK3S-LM8UU-LINEAR-BEARING': [
        ('Y-axis & Frame', 3),
        ('X-axis', 4),
        ('Extruder', 3),
      ],
      'PROD-MK3S-GT2-16-TOOTH-PULLEY': [('Y-axis & Frame', 1), ('X-axis', 1)],
      'PROD-MK3S-623H-IDLER-BEARING': [('Y-axis & Frame', 1), ('X-axis', 1)],
      'PROD-MK3S-M3X10-SCREW': [
        ('Y-axis & Frame', 22),
        ('Z-axis', 18),
        ('Extruder', 11),
        ('LCD', 6),
        ('Heatbed & PSU', 7),
        ('Electronics', 14),
      ],
      'PROD-MK3S-M3X18-SCREW': [
        ('Y-axis & Frame', 1),
        ('X-axis', 4),
        ('Z-axis', 4),
        ('Extruder', 1),
      ],
      'PROD-MK3S-M3X30-SCREW': [('Y-axis & Frame', 1), ('X-axis', 1)],
      'PROD-MK3S-M3X40-SCREW': [('Extruder', 6), ('Electronics', 1)],
      'PROD-MK3S-M3-SQUARE-NUT': [
        ('Y-axis & Frame', 12),
        ('X-axis', 1),
        ('Extruder', 8),
        ('LCD', 4),
        ('Electronics', 5),
      ],
      'PROD-MK3S-M3-HEX-NUT': [
        ('Y-axis & Frame', 6),
        ('Z-axis', 4),
        ('Extruder', 8),
        ('Heatbed & PSU', 2),
        ('Electronics', 4),
      ],
      'PROD-MK3S-M3-NYLOC-NUT': [
        ('Y-axis & Frame', 2),
        ('X-axis', 1),
        ('Heatbed & PSU', 3),
      ],
      'PROD-MK3S-TEXTILE-SLEEVE-5X300-MM': [
        ('Heatbed & PSU', 1),
        ('Electronics', 1),
      ],
      'PROD-MK3S-ZIP-TIE': [('Extruder', 7), ('Electronics', 1)],
    };
    const sectionOrder = [
      'Y-axis & Frame',
      'X-axis',
      'Z-axis',
      'Extruder',
      'LCD',
      'Heatbed & PSU',
      'Electronics',
      'Accessories',
      'Unassigned',
    ];
    final segmented = <KitBomEntry>[];
    for (final source in kit.bom) {
      final split = allocations[source.productId];
      if (split != null) {
        for (final (section, quantity) in split) {
          segmented.add(
            KitBomEntry(
              id: '${kit.id}-${source.productId}-$section',
              productId: source.productId,
              quantity: quantity,
              name: source.name,
              section: section,
            ),
          );
        }
        continue;
      }
      segmented.add(
        KitBomEntry(
          id: source.id.isEmpty ? '${kit.id}-${source.productId}' : source.id,
          productId: source.productId,
          quantity: source.quantity,
          name: source.name,
          section: _prusaMk3sSection(source.productId),
        ),
      );
    }
    segmented.sort(
      (left, right) => sectionOrder
          .indexOf(left.section)
          .compareTo(sectionOrder.indexOf(right.section)),
    );
    kits[kitIndex] = KitRecord(
      id: kit.id,
      name: kit.name,
      bom: segmented,
      imageBytes: kit.imageBytes,
      sourceUrls: kit.sourceUrls,
      sections: sectionOrder
          .where((section) => segmented.any((line) => line.section == section))
          .toList(),
    );
    return true;
  }

  String _prusaMk3sSection(String id) {
    if (id.contains('DOUBLE-SPOOL-HOLDER')) return 'Accessories';
    if (id.contains('EINSY') ||
        id.contains('EXTRUDER-CABLE-CLIP') ||
        id.contains('PSU-COVER')) {
      return 'Electronics';
    }
    if (id.contains('LCD') || id.endsWith('-SD-CARD')) return 'LCD';
    if (id.contains('HEATBED') ||
        id.contains('POWER-SUPPLY') ||
        id.contains('PSU-POWER') ||
        id.contains('POWER-PANIC') ||
        id.contains('REMOVABLE-SPRING')) {
      return 'Heatbed & PSU';
    }
    if (id.contains('EXTRUDER') ||
        id.contains('X-CARRIAGE') ||
        id.contains('ADAPTER-PRINTER') ||
        id.contains('-FS-') ||
        id.contains('FAN-SHROUD') ||
        id.contains('HOTEND') ||
        id.contains('NOZZLE') ||
        id.contains('BONDTECH') ||
        id.contains('FILAMENT-SENSOR') ||
        id.contains('MAGNET-') ||
        id.contains('IR-FILAMENT') ||
        id.contains('SUPERPINDA') ||
        id.contains('PRINT-FAN') ||
        id.contains('CABLE-HOLDER') ||
        id.contains('NYLON-FILAMENT') ||
        id.contains('M2X8') ||
        id.contains('M3X14') ||
        id.contains('M3X20') ||
        id.contains('TEXTILE-SLEEVE-13')) {
      return 'Extruder';
    }
    if (id.contains('Z-AXIS') ||
        id.contains('Z-SCREW') ||
        id.contains('TRAPEZOIDAL') ||
        id.contains('SMOOTH-ROD-320')) {
      return 'Z-axis';
    }
    if (id.contains('X-END') ||
        id.contains('X-AXIS') ||
        id.contains('SMOOTH-ROD-370')) {
      return 'X-axis';
    }
    if (id.contains('ALUMINUM') ||
        id.contains('Y-') ||
        id.contains('ANTIVIBRATION') ||
        id.contains('SMOOTH-ROD-330') ||
        id.contains('M3X6') ||
        id.contains('M5X16') ||
        id.contains('M3-ELASTIC')) {
      return 'Y-axis & Frame';
    }
    if (id.contains('M3X12') ||
        id.contains('M4X10') ||
        id.contains('M3-WASHER') ||
        id.contains('HEATBED-SPACER')) {
      return 'Heatbed & PSU';
    }
    return 'Unassigned';
  }

  void _advanceDryingTimers() {
    if (!mounted) return;
    final now = DateTime.now();
    final completedItems = <int, InventoryItem>{};
    for (var index = 0; index < inventory.length; index++) {
      final item = inventory[index];
      if (item.filamentStatus != FilamentStatus.drying ||
          _dryingTimeRemaining(item, now: now) > Duration.zero) {
        continue;
      }
      completedItems[index] = item.copyWith(
        filamentStatus: FilamentStatus.ready,
        dryingRemaining: 0,
        lastDriedAt: now,
        deployed: false,
      );
    }
    if (completedItems.isNotEmpty) {
      setState(() {
        for (final entry in completedItems.entries) {
          _publishInventoryItem(entry.value);
        }
      });
      _persist();
      unawaited(_playDryingCompleteChime());
    }
    _checkMoistureThresholdAnimations();
    _checkMoistureAlertChimes();
  }

  void _checkMoistureThresholdAnimations() {
    final triggeredIds = <String>[];
    for (final item in _moistureAlerts) {
      final cycle =
          '${item.id}:${item.lastDriedAt?.toIso8601String()}:${item.moistureAlertThresholdMinutes}';
      if (_moistureAnimationCycles.add(cycle)) triggeredIds.add(item.id);
    }
    if (triggeredIds.isEmpty || !mounted) return;
    setState(() {
      for (final id in triggeredIds) {
        _moistureAnimationVersions[id] =
            (_moistureAnimationVersions[id] ?? 0) + 1;
      }
    });
    if (_moistureAnimationCycles.length > 200) {
      final currentCycles = inventory
          .where((item) => item.type == InventoryType.filament)
          .map(
            (item) =>
                '${item.id}:${item.lastDriedAt?.toIso8601String()}:${item.moistureAlertThresholdMinutes}',
          )
          .toSet();
      _moistureAnimationCycles.retainAll(currentCycles);
    }
  }

  void _checkMoistureAlertChimes() {
    if (!moistureAlertChimeEnabled) return;
    var changed = false;
    for (final item in _moistureAlerts) {
      final cycle =
          '${item.id}:${item.lastDriedAt?.toIso8601String()}:${item.moistureAlertThresholdMinutes}';
      if (_moistureAlertChimedCycles.add(cycle)) changed = true;
    }
    if (!changed) return;
    if (_moistureAlertChimedCycles.length > 200) {
      final current = inventory
          .where((item) => item.type == InventoryType.filament)
          .map(
            (item) =>
                '${item.id}:${item.lastDriedAt?.toIso8601String()}:${item.moistureAlertThresholdMinutes}',
          )
          .toSet();
      _moistureAlertChimedCycles.retainAll(current);
    }
    widget.database?.saveStringPreference(
      'moisture_alert_chimed_cycles',
      jsonEncode(_moistureAlertChimedCycles.toList()),
    );
    unawaited(_playMoistureAlertChime());
  }

  void _startAutoSync() {
    _syncPoll?.cancel();
    _autoSyncPausedForAuthentication = false;
    _syncAutomatically();
    _syncPoll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _syncAutomatically(),
    );
  }

  bool get _needsSyncOnboarding {
    final source = widget.database?.loadSyncConfig();
    if (source == null) return widget.database != null;
    try {
      return (jsonDecode(source) as Map<String, dynamic>)['syncMode'] == null ||
          (jsonDecode(source) as Map<String, dynamic>)['syncMode'] == '';
    } catch (_) {
      return true;
    }
  }

  String _normalized(String value) =>
      value.toLowerCase().replaceAll(_searchNormalizationPattern, '');

  void _invalidateSearchCaches() {
    _searchDataRevision++;
    _inventorySearchTextCache.clear();
    _catalogSearchTextCache.clear();
    _visibleItemsCacheKey = null;
    _visibleItemsCache = null;
    _visibleCatalogRecordsCacheKey = null;
    _visibleCatalogRecordsCache = null;
    _visibleEverythingCatalogRecordsCacheKey = null;
    _visibleEverythingCatalogRecordsCache = null;
    _availableItemColorFiltersCacheKey = null;
    _availableItemColorFiltersCache = null;
  }

  String _machineTypePath(String typeId, [Set<String>? visited]) {
    final seen = visited ?? <String>{};
    if (!seen.add(typeId)) return '';
    final type = machineTypes.where((value) => value.id == typeId).firstOrNull;
    if (type == null) return '';
    if (type.parentId == null) return type.name;
    final parent = _machineTypePath(type.parentId!, seen);
    return parent.isEmpty ? type.name : '$parent ${type.name}';
  }

  bool _isPrinter(MachineRecord machine) =>
      _normalized(_machineTypePath(machine.typeId)).contains('printer') ||
      const {'fdm', 'sla', 'uv', 'uvdtf', 'paperprinter'}.any(
        (word) => _normalized(_machineTypePath(machine.typeId)).contains(word),
      );

  List<Object> get visibleCatalogRecords {
    final selected = catalogFilter;
    if (selected == null) return const [];
    final cacheKey = (
      _searchDataRevision,
      selected,
      query,
      currentRole,
      currentUserId,
    );
    if (_visibleCatalogRecordsCacheKey == cacheKey) {
      return _visibleCatalogRecordsCache!;
    }
    final needle = _normalized(query);
    late final List<Object> records;
    if (selected == CatalogViewFilter.kits) {
      final result = kits
          .where((kit) {
            return needle.isEmpty ||
                _catalogSearchTextCache
                    .putIfAbsent(
                      kit,
                      () => _normalized(
                        '${kit.name} ${kit.bom.map(_kitLineName).join(' ')}',
                      ),
                    )
                    .contains(needle);
          })
          .cast<Object>()
          .toList();
      result.sort(
        (a, b) => (a as KitRecord).name.compareTo((b as KitRecord).name),
      );
      records = result;
    } else if (selected == CatalogViewFilter.builds) {
      final result = builds
          .where(
            (build) =>
                _canViewBuild(build) &&
                (needle.isEmpty ||
                    _catalogSearchTextCache
                        .putIfAbsent(
                          build,
                          () => _normalized(
                            '${build.name} ${build.lines.map((line) => '${line.name} ${line.section}').join(' ')}',
                          ),
                        )
                        .contains(needle)),
          )
          .cast<Object>()
          .toList();
      result.sort(
        (a, b) => (b as BuildRecord).createdAt.compareTo(
          (a as BuildRecord).createdAt,
        ),
      );
      records = result;
    } else {
      final result = machines
          .where((machine) {
            final printer = _isPrinter(machine);
            if (selected == CatalogViewFilter.printers && !printer) {
              return false;
            }
            if (selected == CatalogViewFilter.tools && printer) return false;
            if (needle.isEmpty) return true;
            return _catalogSearchTextCache
                .putIfAbsent(machine, () {
                  final kitNames = kits
                      .where((kit) => machine.kitIds.contains(kit.id))
                      .map((kit) => kit.name)
                      .join(' ');
                  return _normalized(
                    '${machine.name} ${machine.model} ${machine.address} '
                    '${_machineTypePath(machine.typeId)} $kitNames',
                  );
                })
                .contains(needle);
          })
          .cast<Object>()
          .toList();
      result.sort(
        (a, b) =>
            (a as MachineRecord).name.compareTo((b as MachineRecord).name),
      );
      records = result;
    }
    _visibleCatalogRecordsCacheKey = cacheKey;
    return _visibleCatalogRecordsCache = records;
  }

  List<Object> get visibleEverythingCatalogRecords {
    final cacheKey = (_searchDataRevision, query, currentRole, currentUserId);
    if (_visibleEverythingCatalogRecordsCacheKey == cacheKey) {
      return _visibleEverythingCatalogRecordsCache!;
    }
    final needle = _normalized(query);
    final result = <Object>[];
    result.addAll(
      kits.where((kit) {
        return needle.isEmpty ||
            _catalogSearchTextCache
                .putIfAbsent(
                  kit,
                  () => _normalized(
                    '${kit.name} ${kit.bom.map(_kitLineName).join(' ')}',
                  ),
                )
                .contains(needle);
      }),
    );
    result.addAll(
      builds.where(
        (build) =>
            _canViewBuild(build) &&
            (needle.isEmpty ||
                _catalogSearchTextCache
                    .putIfAbsent(
                      build,
                      () => _normalized(
                        '${build.name} ${build.lines.map((line) => '${line.name} ${line.section}').join(' ')}',
                      ),
                    )
                    .contains(needle)),
      ),
    );
    result.addAll(
      machines.where((machine) {
        return needle.isEmpty ||
            _catalogSearchTextCache
                .putIfAbsent(
                  machine,
                  () => _normalized(
                    '${machine.name} ${machine.model} ${machine.address} ${_machineTypePath(machine.typeId)}',
                  ),
                )
                .contains(needle);
      }),
    );
    _visibleEverythingCatalogRecordsCacheKey = cacheKey;
    return _visibleEverythingCatalogRecordsCache = result;
  }

  String _spoolSizeLabel(InventoryItem item) =>
      item.type != InventoryType.filament
      ? ''
      : spoolTypes
                .where((spool) => spool.id == item.spoolTypeId)
                .firstOrNull
                ?.label ??
            '1 kg';

  String _inventoryTypeDisplayLabel(InventoryType value) =>
      typeLabelOverrides[_inventoryTypeDefinitionKey(value)] ??
      _typeLabel(value);

  String _catalogViewDisplayLabel(CatalogViewFilter value) =>
      typeLabelOverrides[_catalogViewDefinitionKey(value)] ??
      _defaultCatalogViewLabel(value);

  IconData _inventoryTypeIcon(InventoryType value) => _iconFromKey(
    typeIconOverrides[_inventoryTypeDefinitionKey(value)],
    _typeIcon(value),
  );

  IconData _catalogViewIcon(CatalogViewFilter value) => _iconFromKey(
    typeIconOverrides[_catalogViewDefinitionKey(value)],
    switch (value) {
      CatalogViewFilter.kits => Icons.inventory_2_outlined,
      CatalogViewFilter.builds => Icons.construction_rounded,
      CatalogViewFilter.machines => Icons.precision_manufacturing_outlined,
      CatalogViewFilter.printers => Icons.print_outlined,
      CatalogViewFilter.tools => Icons.handyman_outlined,
    },
  );

  IconData _itemTypeIcon(InventoryItem item) {
    if (item.type != InventoryType.custom) return _inventoryTypeIcon(item.type);
    final customType = customItemTypes
        .where((candidate) => candidate.id == item.customTypeId)
        .firstOrNull;
    return _iconFromKey(customType?.iconKey, Icons.tune_rounded);
  }

  String? _itemTypeIconKey(InventoryItem item) {
    if (item.type != InventoryType.custom) {
      return typeIconOverrides[_inventoryTypeDefinitionKey(item.type)];
    }
    return customItemTypes
        .where((candidate) => candidate.id == item.customTypeId)
        .firstOrNull
        ?.iconKey;
  }

  bool _itemCanMarkDepleted(InventoryItem item) {
    if (item.type == InventoryType.custom) {
      return customItemTypes
              .where((candidate) => candidate.id == item.customTypeId)
              .firstOrNull
              ?.canMarkDepleted ??
          false;
    }
    return _typeCanMarkDepleted(
      _inventoryTypeDefinitionKey(item.type),
      typeDepletionSettings,
    );
  }

  bool _itemShowsStatus(InventoryItem item) {
    if (item.type == InventoryType.custom) {
      return customItemTypes
              .where((candidate) => candidate.id == item.customTypeId)
              .firstOrNull
              ?.showsStatus ??
          false;
    }
    return _typeShowsStatus(
      _inventoryTypeDefinitionKey(item.type),
      typeStatusSettings,
    );
  }

  String _itemTypeDisplayLabel(InventoryItem item) =>
      item.type == InventoryType.custom && item.customTypeName.isNotEmpty
      ? item.customTypeName
      : _inventoryTypeDisplayLabel(item.type);

  List<({String value, String label, String hex})>
  get availableItemColorFilters {
    if (catalogFilter != null) return const [];
    final cacheKey = (
      _searchDataRevision,
      archivedOnly,
      type,
      customTypeFilterId,
    );
    if (_availableItemColorFiltersCacheKey == cacheKey) {
      return _availableItemColorFiltersCache!;
    }
    final colors = <String, ({String value, String label, String hex})>{};
    for (final item in inventory.where(
      (item) =>
          item.archived == archivedOnly &&
          (type == null || item.type == type) &&
          (customTypeFilterId == null ||
              item.customTypeId == customTypeFilterId) &&
          item.itemColorName.isNotEmpty,
    )) {
      final value = item.itemColorName;
      colors.putIfAbsent(
        value,
        () => (
          value: value,
          label: item.itemColorLabel.trim().isNotEmpty
              ? item.itemColorLabel.trim()
              : value.startsWith('#')
              ? 'Unnamed color'
              : value,
          hex: _itemColorHex(value),
        ),
      );
    }
    final result = colors.values.toList()
      ..sort((a, b) {
        final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
        return byLabel != 0 ? byLabel : a.hex.compareTo(b.hex);
      });
    _availableItemColorFiltersCacheKey = cacheKey;
    return _availableItemColorFiltersCache = result;
  }

  List<InventoryItem> get visibleItems {
    final cacheKey = (
      _searchDataRevision,
      query,
      archivedOnly,
      hideZeroQuantityItems,
      type,
      customTypeFilterId,
      itemColorFilter,
      sort,
    );
    if (_visibleItemsCacheKey == cacheKey) return _visibleItemsCache!;
    final needle = _normalized(query);
    final now = DateTime.now();
    final result = inventory.where((item) {
      if (item.archived != archivedOnly ||
          hideZeroQuantityItems && item.quantity <= 0 ||
          type != null && item.type != type ||
          customTypeFilterId != null &&
              item.customTypeId != customTypeFilterId ||
          itemColorFilter != null && item.itemColorName != itemColorFilter) {
        return false;
      }
      if (needle.isEmpty) return true;
      final cached = _inventorySearchTextCache[item.id];
      final searchable = cached != null && identical(cached.$1, item)
          ? cached.$2
          : _normalized(
              '${item.name} ${_itemTypeDisplayLabel(item)} ${item.compatibility.join(' ')} ${item.barcode} '
              '${item.brand} ${item.vendor} ${item.materialName} ${item.storageLocation} ${item.productUrl} '
              '${item.spoolMaterialName} ${item.masterSpoolMaterialName} '
              '${item.customFieldValues.entries.map((entry) => '${entry.key} ${entry.value}').join(' ')} '
              '${item.itemColorLabel} ${item.itemColorName} '
              '${_spoolSizeLabel(item)} ${item.amsCompatible ? 'AMS compatible' : ''} '
              '${item.refill ? 'refill reload master spool ${item.masterSpool}' : 'factory spool'} '
              '${item.spoolOuterDiameterMm ?? ''} ${item.spoolWidthMm ?? ''} ${item.spoolHoleDiameterMm ?? ''} '
              '${machines.where((machine) => item.compatibleMachineIds.contains(machine.id)).map((machine) => '${machine.name} ${machine.model} ${_machineTypePath(machine.typeId)}').join(' ')}',
            );
      if (cached == null || !identical(cached.$1, item)) {
        _inventorySearchTextCache[item.id] = (item, searchable);
      }
      return searchable.contains(needle);
    }).toList();
    result.sort(
      (a, b) => switch (sort) {
        InventorySort.type => a.typeLabel.compareTo(b.typeLabel),
        InventorySort.quantity => b.quantity.compareTo(a.quantity),
        InventorySort.age => a.added.compareTo(b.added),
        InventorySort.cost => b.cost.compareTo(a.cost),
        InventorySort.dryingTime => (b.dryingMinutes ?? -1).compareTo(
          a.dryingMinutes ?? -1,
        ),
        InventorySort.moistureRemaining => compareMoistureRemaining(
          a,
          b,
          now: now,
        ),
      },
    );
    _visibleItemsCacheKey = cacheKey;
    return _visibleItemsCache = result;
  }

  @override
  Widget build(BuildContext context) {
    final showingCatalog = catalogFilter != null;
    final allItems = showingCatalog ? const <InventoryItem>[] : visibleItems;
    final allCatalogRecords = showingCatalog
        ? visibleCatalogRecords
        : const <Object>[];
    final showingEverything =
        !showingCatalog &&
        !archivedOnly &&
        type == null &&
        customTypeFilterId == null &&
        itemColorFilter == null;
    final allRecords = showingCatalog
        ? allCatalogRecords
        : showingEverything
        ? <Object>[...visibleEverythingCatalogRecords, ...allItems]
        : allItems.cast<Object>();
    final resultCount = allRecords.length;
    final pageSize = _pageSizes[pageSizeIndex];
    final pageCount = resultCount == 0 ? 1 : (resultCount / pageSize).ceil();
    final page = currentPage.clamp(0, pageCount - 1);
    final start = page * pageSize;
    final records = allRecords.skip(start).take(pageSize).toList();
    return _CustomIconAnimationScope(
      mode: customIconAnimationMode,
      child: TickerMode(
        enabled: true,
        child: Scaffold(
          extendBody: true,
          body: Stack(
            children: [
              Positioned.fill(
                child: SafeArea(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleInventoryScrollNotification,
                    child: CustomScrollView(
                      key: const Key('inventory-scroll-view'),
                      controller: inventoryScrollController,
                      scrollCacheExtent:
                          Platform.isAndroid ||
                              Platform.isLinux ||
                              Platform.isWindows
                          ? const ScrollCacheExtent.viewport(.75)
                          : null,
                      slivers: [
                        SliverToBoxAdapter(child: _titleHeader()),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _PinnedActionBarDelegate(
                            height: 80,
                            child: _floatingHeaderActionBar(),
                          ),
                        ),
                        SliverToBoxAdapter(child: _header()),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                          sliver: resultCount == 0
                              ? const SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: Text(
                                      'Nothing matches those filters.',
                                    ),
                                  ),
                                )
                              : gridView
                              ? ValueListenableBuilder<double>(
                                  valueListenable: _cardSizeSliderValue,
                                  builder: (context, liveCardSizePercent, _) =>
                                      SliverLayoutBuilder(
                                        builder: (context, constraints) {
                                          const spacing = 14.0;
                                          return SliverGrid.builder(
                                            itemCount: records.length,
                                            gridDelegate:
                                                _CenteredSquareGridDelegate(
                                                  cardExtent:
                                                      274.0 *
                                                      (liveCardSizePercent /
                                                          100),
                                                  spacing: spacing,
                                                ),
                                            itemBuilder: (_, index) =>
                                                _recordWidget(records[index]),
                                          );
                                        },
                                      ),
                                )
                              : SliverList.separated(
                                  itemCount: records.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (_, index) =>
                                      _recordWidget(records[index], list: true),
                                ),
                        ),
                        if (resultCount > 0)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                8,
                                20,
                                110,
                              ),
                              child: _pageNavigation(
                                page,
                                pageCount,
                                resultCount,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!_hasCatalogSelection && selectedInventoryIds.isEmpty)
                Positioned(
                  key: const Key('bottom-action-overlay'),
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _bottomActionBar(),
                ),
            ],
          ),
          bottomNavigationBar: selectedInventoryIds.isNotEmpty
              ? _bulkEditToolbar()
              : selectedBuildIds.isNotEmpty &&
                    selectedKitIds.isEmpty &&
                    selectedMachineIds.isEmpty
              ? _bulkBuildToolbar()
              : _hasCatalogSelection
              ? _bulkCatalogToolbar()
              : null,
        ),
      ),
    );
  }

  bool _handleInventoryScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle)) {
      _inventoryOverlayRestore?.cancel();
      _inventoryOverlayRestore = Timer(const Duration(milliseconds: 500), () {
        if (!mounted || !_inventoryIsScrolling.value) return;
        _inventoryIsScrolling.value = false;
      });
    } else if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _inventoryOverlayRestore?.cancel();
      if (!_inventoryIsScrolling.value) {
        _inventoryIsScrolling.value = true;
      }
    } else {
      return false;
    }
    return false;
  }

  Widget _recordWidget(Object record, {bool list = false}) {
    if (record is! InventoryItem) {
      return _catalogRecordCard(record, list: list);
    }
    final notifier = _inventoryItemNotifiers.putIfAbsent(
      record.id,
      () => ValueNotifier(record),
    );
    return ValueListenableBuilder<InventoryItem>(
      key: ValueKey('inventory-cell-${record.id}'),
      valueListenable: notifier,
      builder: (_, item, _) => _inventoryItemWidget(item, list: list),
    );
  }

  Widget _inventoryItemWidget(InventoryItem record, {required bool list}) {
    final common = (
      selected: selectedInventoryIds.contains(record.id),
      typeLabel: _itemTypeDisplayLabel(record),
      spoolSizeLabel: _spoolSizeLabel(record),
      quantitySyncVersion: _remoteQuantityAnimationVersions[record.id] ?? 0,
      lowStockAnimationVersion: _lowStockAnimationVersions[record.id] ?? 0,
      moistureAnimationVersion: _moistureAnimationVersions[record.id] ?? 0,
      showStatus: _itemShowsStatus(record),
    );
    final Widget card;
    if (list) {
      card = InventoryRow(
        item: record,
        typeIcon: _itemTypeIcon(record),
        typeIconImageBytes: _iconImageBytesFromKey(_itemTypeIconKey(record)),
        selected: common.selected,
        typeLabel: common.typeLabel,
        spoolSizeLabel: common.spoolSizeLabel,
        quantitySyncVersion: common.quantitySyncVersion,
        lowStockAnimationVersion: common.lowStockAnimationVersion,
        moistureAnimationVersion: common.moistureAnimationVersion,
        showStatus: common.showStatus,
        animationDurationPercent: animationDurationPercent,
        animationRecurrenceSeconds: animationRecurrenceSeconds,
        scrollingListenable: _inventoryIsScrolling,
        canEdit: currentRole.canEditInventory,
        canCreate: currentRole.canCreateInventory,
        canArchive: currentRole.canArchiveInventory,
        canDelete: currentRole.canHardDeleteItems,
        onOpen: () => _handleInventoryTap(record),
        onSelect: () => _selectInventoryItem(record),
        onAction: (action) => _handleAction(record, action),
        onQuantityChanged: (delta) => _adjustItemQuantity(record, delta),
      );
    } else {
      card = InventoryCard(
        item: record,
        photoCard: photoCardsEnabled,
        typeIcon: _itemTypeIcon(record),
        typeIconImageBytes: _iconImageBytesFromKey(_itemTypeIconKey(record)),
        selected: common.selected,
        typeLabel: common.typeLabel,
        spoolSizeLabel: common.spoolSizeLabel,
        quantitySyncVersion: common.quantitySyncVersion,
        lowStockAnimationVersion: common.lowStockAnimationVersion,
        moistureAnimationVersion: common.moistureAnimationVersion,
        showStatus: common.showStatus,
        animationDurationPercent: animationDurationPercent,
        animationRecurrenceSeconds: animationRecurrenceSeconds,
        scrollingListenable: _inventoryIsScrolling,
        canEdit: currentRole.canEditInventory,
        canCreate: currentRole.canCreateInventory,
        canArchive: currentRole.canArchiveInventory,
        canDelete: currentRole.canHardDeleteItems,
        onOpen: () => _handleInventoryTap(record),
        onSelect: () => _selectInventoryItem(record),
        onAction: (action) => _handleAction(record, action),
        onQuantityChanged: (delta) => _adjustItemQuantity(record, delta),
      );
    }
    return card;
  }

  void _publishInventoryItem(InventoryItem item) {
    final index = inventory.indexWhere((candidate) => candidate.id == item.id);
    if (index < 0) return;
    inventory[index] = item;
    final notifier = _inventoryItemNotifiers.putIfAbsent(
      item.id,
      () => ValueNotifier(item),
    );
    if (!identical(notifier.value, item)) notifier.value = item;
  }

  void _addInventoryItem(InventoryItem item) {
    inventory.add(item);
    _inventoryItemNotifiers.remove(item.id)?.dispose();
    _inventoryItemNotifiers[item.id] = ValueNotifier(item);
  }

  void _removeInventoryItem(String itemId) {
    inventory.removeWhere((item) => item.id == itemId);
    _inventoryItemNotifiers.remove(itemId)?.dispose();
  }

  void _synchronizeInventoryNotifiers() {
    final activeIds = inventory.map((item) => item.id).toSet();
    for (final staleId
        in _inventoryItemNotifiers.keys
            .where((id) => !activeIds.contains(id))
            .toList()) {
      _inventoryItemNotifiers.remove(staleId)?.dispose();
    }
    for (final item in inventory) {
      final notifier = _inventoryItemNotifiers.putIfAbsent(
        item.id,
        () => ValueNotifier(item),
      );
      if (!identical(notifier.value, item)) notifier.value = item;
    }
  }

  List<InventoryItem> get _selectedInventoryItems => inventory
      .where((item) => selectedInventoryIds.contains(item.id))
      .toList();

  bool get _hasCatalogSelection =>
      selectedBuildIds.isNotEmpty ||
      selectedKitIds.isNotEmpty ||
      selectedMachineIds.isNotEmpty;

  int get _catalogSelectionCount =>
      selectedBuildIds.length +
      selectedKitIds.length +
      selectedMachineIds.length;

  void _clearCatalogSelection() {
    selectedBuildIds.clear();
    selectedKitIds.clear();
    selectedMachineIds.clear();
  }

  void _handleInventoryTap(InventoryItem item) {
    if (HardwareKeyboard.instance.isShiftPressed ||
        selectedInventoryIds.isNotEmpty ||
        _hasCatalogSelection) {
      setState(() {
        _clearCatalogSelection();
        selectedInventoryIds.contains(item.id)
            ? selectedInventoryIds.remove(item.id)
            : selectedInventoryIds.add(item.id);
      });
      return;
    }
    _openDetails(item);
  }

  void _selectInventoryItem(InventoryItem item) {
    setState(() {
      _clearCatalogSelection();
      selectedInventoryIds.contains(item.id)
          ? selectedInventoryIds.remove(item.id)
          : selectedInventoryIds.add(item.id);
    });
  }

  void _handleCatalogRecordTap(Object record) {
    if (HardwareKeyboard.instance.isShiftPressed || _hasCatalogSelection) {
      _selectCatalogRecord(record);
      return;
    }
    switch (record) {
      case KitRecord value:
        unawaited(_openKitDetails(value));
      case BuildRecord value:
        unawaited(_openBuildQueue(value, _kitForBuild(value)));
      case MachineRecord value:
        unawaited(_openMachineDetails(value));
    }
  }

  void _selectCatalogRecord(Object record) {
    setState(() {
      selectedInventoryIds.clear();
      switch (record) {
        case KitRecord value:
          selectedKitIds.contains(value.id)
              ? selectedKitIds.remove(value.id)
              : selectedKitIds.add(value.id);
        case BuildRecord value:
          selectedBuildIds.contains(value.id)
              ? selectedBuildIds.remove(value.id)
              : selectedBuildIds.add(value.id);
        case MachineRecord value:
          selectedMachineIds.contains(value.id)
              ? selectedMachineIds.remove(value.id)
              : selectedMachineIds.add(value.id);
      }
    });
  }

  Widget _bulkBuildToolbar() {
    final selected = builds
        .where((build) => selectedBuildIds.contains(build.id))
        .toList();
    return Material(
      key: const Key('bulk-build-toolbar'),
      color: Theme.of(context).colorScheme.surface,
      elevation: 20,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(
                key: const Key('clear-build-selection'),
                tooltip: 'Clear selection',
                onPressed: () => setState(selectedBuildIds.clear),
                icon: const Icon(Icons.close_rounded),
              ),
              const SizedBox(width: 4),
              Text(
                '${selected.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              OutlinedButton.icon(
                key: const Key('bulk-delete-builds'),
                onPressed: currentRole.canHardDeleteItems
                    ? _bulkDeleteBuilds
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xffff7777),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _bulkDeleteBuilds() async {
    final count = selectedBuildIds.length;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $count ${count == 1 ? 'build' : 'builds'}?'),
        content: const Text(
          'This permanently deletes the selected build records. Inventory already used by them is not returned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-bulk-delete-builds'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      for (final build in builds.where(
        (candidate) => selectedBuildIds.contains(candidate.id),
      )) {
        _recordAudit('delete', 'build', build.id, {'name': build.name});
      }
      builds.removeWhere((build) => selectedBuildIds.contains(build.id));
      selectedBuildIds.clear();
    });
    _persist();
  }

  Widget _bulkCatalogToolbar() => Material(
    key: const Key('bulk-catalog-toolbar'),
    color: Theme.of(context).colorScheme.surface,
    elevation: 20,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconButton(
              key: const Key('clear-catalog-selection'),
              tooltip: 'Clear selection',
              onPressed: () => setState(_clearCatalogSelection),
              icon: const Icon(Icons.close_rounded),
            ),
            const SizedBox(width: 4),
            Text(
              '$_catalogSelectionCount selected',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            OutlinedButton.icon(
              key: const Key('bulk-delete-catalog-records'),
              onPressed: currentRole.canHardDeleteItems
                  ? _bulkDeleteCatalogRecords
                  : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xffff7777),
              ),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _bulkDeleteCatalogRecords() async {
    final count = _catalogSelectionCount;
    if (count == 0) return;
    final unfinishedBuilds = builds
        .where(
          (build) =>
              selectedKitIds.contains(build.kitId) &&
              build.completedAt == null &&
              !selectedBuildIds.contains(build.id),
        )
        .length;
    final summary = <String>[
      if (selectedKitIds.isNotEmpty)
        '${selectedKitIds.length} ${selectedKitIds.length == 1 ? 'kit' : 'kits'}',
      if (selectedMachineIds.isNotEmpty)
        '${selectedMachineIds.length} ${selectedMachineIds.length == 1 ? 'machine' : 'machines'}',
      if (selectedBuildIds.isNotEmpty)
        '${selectedBuildIds.length} ${selectedBuildIds.length == 1 ? 'build' : 'builds'}',
    ].join(', ');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $count selected records?'),
        content: Text(
          unfinishedBuilds == 0
              ? 'This permanently deletes $summary.'
              : 'This permanently deletes $summary. $unfinishedBuilds unfinished ${unfinishedBuilds == 1 ? 'build references' : 'builds reference'} the selected kits and will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-bulk-delete-catalog-records'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      for (final kit in kits.where(
        (candidate) => selectedKitIds.contains(candidate.id),
      )) {
        _recordAudit('delete', 'kit', kit.id, {
          'name': kit.name,
          'bulk': 'true',
        });
      }
      for (final machine in machines.where(
        (candidate) => selectedMachineIds.contains(candidate.id),
      )) {
        _recordAudit('delete', 'machine', machine.id, {
          'name': machine.name,
          'bulk': 'true',
        });
      }
      for (final build in builds.where(
        (candidate) => selectedBuildIds.contains(candidate.id),
      )) {
        _recordAudit('delete', 'build', build.id, {
          'name': build.name,
          'bulk': 'true',
        });
      }

      builds.removeWhere((build) => selectedBuildIds.contains(build.id));
      kits.removeWhere((kit) => selectedKitIds.contains(kit.id));
      machines.removeWhere(
        (machine) => selectedMachineIds.contains(machine.id),
      );
      for (final machine in machines) {
        machine.kitIds.removeWhere(selectedKitIds.contains);
      }
      for (var index = 0; index < inventory.length; index++) {
        final item = inventory[index];
        if (!item.compatibleMachineIds.any(selectedMachineIds.contains)) {
          continue;
        }
        _publishInventoryItem(
          item.copyWith(
            compatibleMachineIds: item.compatibleMachineIds
                .where((id) => !selectedMachineIds.contains(id))
                .toList(),
          ),
        );
      }
      _clearCatalogSelection();
    });
    _persist();
  }

  Widget _bulkEditToolbar() {
    final selected = _selectedInventoryItems;
    final restore =
        selected.isNotEmpty && selected.every((item) => item.archived);
    final actions =
        <
          ({
            Key key,
            IconData icon,
            String label,
            VoidCallback? onPressed,
            bool destructive,
          })
        >[
          (
            key: const Key('bulk-create-kit'),
            icon: Icons.inventory_2_outlined,
            label: 'Create Kit',
            onPressed: currentRole.canManageCatalog ? _bulkCreateKit : null,
            destructive: false,
          ),
          (
            key: const Key('bulk-archive'),
            icon: restore ? Icons.unarchive_outlined : Icons.archive_outlined,
            label: restore ? 'Restore' : 'Archive',
            onPressed: currentRole.canArchiveInventory
                ? _bulkArchiveOrRestore
                : null,
            destructive: false,
          ),
          (
            key: const Key('bulk-delete'),
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            onPressed: currentRole.canHardDeleteItems ? _bulkDelete : null,
            destructive: true,
          ),
          (
            key: const Key('bulk-change-type'),
            icon: Icons.swap_horiz_rounded,
            label: 'Change Type',
            onPressed: currentRole.canEditInventory ? _bulkChangeType : null,
            destructive: false,
          ),
        ];
    final noActionsAvailable = actions.every(
      (action) => action.onPressed == null,
    );
    return Material(
      key: const Key('bulk-edit-toolbar'),
      color: Theme.of(context).colorScheme.surface,
      elevation: 20,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final selectionHeader = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('clear-bulk-selection'),
                  tooltip: 'Clear selection',
                  onPressed: () => setState(selectedInventoryIds.clear),
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 4),
                Text(
                  '${selected.length} selected',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            );
            if (constraints.maxWidth < 650) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: selectionHeader,
                    ),
                    if (noActionsAvailable)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline_rounded, size: 16),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Builder role: ask the inventory owner to promote this device for bulk editing.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        for (final action in actions)
                          Expanded(
                            child: _bulkMobileToolbarButton(
                              key: action.key,
                              icon: action.icon,
                              label: action.label,
                              onPressed: action.onPressed,
                              destructive: action.destructive,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  selectionHeader,
                  const SizedBox(width: 18),
                  for (final action in actions)
                    _bulkToolbarButton(
                      key: action.key,
                      icon: action.icon,
                      label: action.label,
                      onPressed: action.onPressed,
                      destructive: action.destructive,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _bulkMobileToolbarButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool destructive = false,
  }) => TextButton(
    key: key,
    onPressed: onPressed,
    style: destructive
        ? TextButton.styleFrom(foregroundColor: const Color(0xffff7777))
        : null,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon),
        const SizedBox(height: 3),
        FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
      ],
    ),
  );

  Widget _bulkToolbarButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool destructive = false,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: OutlinedButton.icon(
      key: key,
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: destructive
          ? OutlinedButton.styleFrom(foregroundColor: const Color(0xffff7777))
          : null,
    ),
  );

  Future<void> _bulkCreateKit() async {
    final selected = _selectedInventoryItems;
    if (selected.isEmpty) return;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    setState(() {
      selectedInventoryIds.clear();
    });
    await _openCatalog(
      initialKitBom: [
        for (final (index, item) in selected.indexed)
          KitBomEntry(
            id: 'KIT-DRAFT-$stamp-LINE-$index',
            productId: item.catalogProductId ?? item.id,
            quantity: 1,
            name: item.name,
            section: 'Main component',
          ),
      ],
    );
  }

  void _bulkArchiveOrRestore() {
    final selected = _selectedInventoryItems;
    if (selected.isEmpty) return;
    final restore = selected.every((item) => item.archived);
    setState(() {
      for (var index = 0; index < inventory.length; index++) {
        final item = inventory[index];
        if (!selectedInventoryIds.contains(item.id)) continue;
        _publishInventoryItem(
          item.copyWith(
            archived: !restore,
            archiveDisposition: ArchiveDisposition.archived,
          ),
        );
        _recordAudit(restore ? 'restore' : 'archive', 'inventory', item.id, {
          'name': item.name,
          'bulk': 'true',
        });
      }
      selectedInventoryIds.clear();
    });
    _persist();
  }

  Future<void> _bulkDelete() async {
    final selected = _selectedInventoryItems;
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${selected.length} items?'),
        content: const Text(
          'This permanently deletes every selected inventory item.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('confirm-bulk-delete'),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      for (final item in selected) {
        _recordAudit('delete', 'inventory', item.id, {
          'name': item.name,
          'bulk': 'true',
        });
      }
      for (final id in selectedInventoryIds.toList()) {
        _removeInventoryItem(id);
      }
      selectedInventoryIds.clear();
    });
    _persist();
  }

  Future<void> _bulkChangeType() async {
    final selected = _selectedInventoryItems;
    if (selected.isEmpty) return;
    final choice =
        await showDialog<
          ({InventoryType type, CustomItemTypeRecord? customType})
        >(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: Text('Change type for ${selected.length} items'),
            children: [
              for (final value in InventoryType.values.where(
                (value) => value != InventoryType.custom,
              ))
                SimpleDialogOption(
                  key: Key('bulk-type-${value.name}'),
                  onPressed: () => Navigator.pop(dialogContext, (
                    type: value,
                    customType: null,
                  )),
                  child: ListTile(
                    leading: _typeIconVisual(
                      typeIconOverrides[_inventoryTypeDefinitionKey(value)],
                      _typeIcon(value),
                    ),
                    title: Text(_inventoryTypeDisplayLabel(value)),
                  ),
                ),
              for (final customType in customItemTypes)
                SimpleDialogOption(
                  key: Key('bulk-custom-type-${customType.id}'),
                  onPressed: () => Navigator.pop(dialogContext, (
                    type: InventoryType.custom,
                    customType: customType,
                  )),
                  child: ListTile(
                    leading: _typeIconVisual(
                      customType.iconKey,
                      Icons.tune_rounded,
                    ),
                    title: Text(customType.name),
                  ),
                ),
            ],
          ),
        );
    if (choice == null || !mounted) return;
    final targetLabel =
        choice.customType?.name ?? _inventoryTypeDisplayLabel(choice.type);
    setState(() {
      for (var index = 0; index < inventory.length; index++) {
        final item = inventory[index];
        if (!selectedInventoryIds.contains(item.id)) continue;
        _publishInventoryItem(
          item.copyWith(
            type: choice.type,
            customTypeId: choice.customType?.id ?? '',
            customTypeName: choice.customType?.name ?? '',
            customFieldValues: const {},
            materialId: '',
            materialName: '',
            clearFilamentData:
                item.type == InventoryType.filament &&
                choice.type != InventoryType.filament,
            clearPrintingData: !choice.type.supportsPrinting,
            clearCatalogProductId: true,
          ),
        );
        _recordAudit('change type', 'inventory', item.id, {
          'type': '${_itemTypeDisplayLabel(item)} → $targetLabel',
          'bulk': 'true',
        });
      }
      selectedInventoryIds.clear();
    });
    _persist();
  }

  Future<void> _addItem({
    String initialBarcode = '',
    InventoryItem? productTemplate,
    LabelOcrDraft? labelDraft,
    FilamentColorSwatch? initialFilamentColor,
  }) async {
    if (!currentRole.canCreateInventory) {
      _showPermissionDenied('Your role cannot add inventory items.');
      return;
    }
    final item = await showDialog<InventoryItem>(
      context: context,
      builder: (_) => AddItemDialog(
        vendors: vendors,
        brands: brands,
        products: products,
        initialBarcode: initialBarcode,
        productTemplate: productTemplate,
        labelDraft: labelDraft,
        initialFilamentColor: initialFilamentColor,
        machineTypes: machineTypes,
        machines: machines,
        locations: locations,
        spoolTypes: spoolTypes,
        materials: materials,
        customItemTypes: customItemTypes,
        typeLabelOverrides: typeLabelOverrides,
        typeIconOverrides: typeIconOverrides,
        database: widget.database,
        filamentColorsClient: _filamentColorsClient,
      ),
    );
    if (item != null && mounted) {
      setState(() {
        _addInventoryItem(item);
        _recordAddition(item);
        _recordAudit('create', 'inventory', item.id, {'name': item.name});
      });
      _persist();
      _discardLoadedFullImages([item]);
    }
  }

  Future<void> _openRapidizer() async {
    if (!currentRole.canCreateInventory) {
      _showPermissionDenied('Your role cannot add inventory items.');
      return;
    }
    final drafts = await showDialog<List<RapidItemDraft>>(
      context: context,
      builder: (_) => RapidizerDialog(
        typeAliases: {
          for (final type in InventoryType.values)
            type: _inventoryTypeDisplayLabel(type),
        },
        materials: materials,
      ),
    );
    if (drafts == null || drafts.isEmpty || !mounted) return;
    final now = DateTime.now();
    final items = drafts
        .map(
          (draft) => InventoryItem(
            id: _newInventoryId(),
            name: draft.name,
            type: draft.type,
            compatibility: const [],
            added: now,
            cost: draft.price,
            quantity: draft.quantity,
            color: _typeColor(draft.type),
            itemColorName: draft.itemColorName,
            itemColorLabel: draft.itemColorLabel,
            materialId: draft.materialId,
            materialName: draft.materialName,
          ),
        )
        .toList();
    setState(() {
      inventory.addAll(items);
      for (final item in items) {
        _recordAddition(item);
      }
    });
    _persist();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${items.length} items RAPIDIZED!')));
  }

  Future<void> _openFilamentColors() async {
    if (!currentRole.canCreateInventory) {
      _showPermissionDenied('Your role cannot add inventory items.');
      return;
    }
    final selected = await showDialog<FilamentColorSwatch>(
      context: context,
      builder: (_) => FilamentColorsSearchDialog(
        client: _filamentColorsClient,
        autoSearch: false,
      ),
    );
    if (!mounted || selected == null) return;
    await _addItem(initialFilamentColor: selected);
  }

  Future<bool> _importInventoryJson() async {
    if (!currentRole.canCreateInventory) {
      _showPermissionDenied('Your role cannot add inventory items.');
      return false;
    }
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Import inventory items from JSON',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null || !mounted) return false;
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('Inventory JSON must be 10 MB or smaller.');
      }
      final parsed = parseInventoryJson(utf8.decode(bytes));
      if (!parsed.isValid) {
        await _showInventoryJsonErrors(parsed.errors);
        return false;
      }
      final prepared = prepareInventoryJsonImport(parsed.items);
      if (prepared.errors.isNotEmpty) {
        await _showInventoryJsonErrors(prepared.errors);
        return false;
      }
      if (!mounted) return false;
      final duplicateCount = prepared.items
          .where(
            (item) => inventory.any(
              (existing) =>
                  existing.type == item.type &&
                  _normalized(existing.name) == _normalized(item.name),
            ),
          )
          .length;
      final imageCount = parsed.items
          .where((draft) => draft.imageUrl.isNotEmpty)
          .length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.data_object_rounded),
              const SizedBox(width: 10),
              Expanded(child: Text('Import ${prepared.items.length} items?')),
            ],
          ),
          content: SizedBox(
            width: 720,
            height: 600,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('${prepared.items.length} new items')),
                    if (prepared.newMaterials.isNotEmpty)
                      Chip(
                        label: Text(
                          '${prepared.newMaterials.length} new materials',
                        ),
                      ),
                    if (prepared.newVendors.isNotEmpty)
                      Chip(
                        label: Text(
                          '${prepared.newVendors.length} new vendors',
                        ),
                      ),
                    if (prepared.newBrands.isNotEmpty)
                      Chip(
                        label: Text('${prepared.newBrands.length} new brands'),
                      ),
                    if (prepared.updatedBrands.isNotEmpty ||
                        prepared.updatedVendors.isNotEmpty)
                      Chip(
                        label: Text(
                          '${prepared.updatedBrands.length + prepared.updatedVendors.length} catalog links updated',
                        ),
                      ),
                    if (imageCount > 0)
                      Chip(label: Text('$imageCount product images')),
                    if (duplicateCount > 0)
                      Chip(
                        avatar: const Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                        ),
                        label: Text('$duplicateCount possible duplicates'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Every row creates a new inventory item. Review possible duplicates before importing.',
                  style: TextStyle(color: Color(0xffaeb5c5)),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: prepared.items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = prepared.items[index];
                      final duplicate = inventory.any(
                        (existing) =>
                            existing.type == item.type &&
                            _normalized(existing.name) ==
                                _normalized(item.name),
                      );
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          duplicate
                              ? Icons.warning_amber_rounded
                              : _typeIcon(item.type),
                          color: duplicate ? const Color(0xffffc15c) : null,
                        ),
                        title: Text(item.name),
                        subtitle: Text(
                          [
                            _itemTypeDisplayLabel(item),
                            if (item.materialName.isNotEmpty) item.materialName,
                            'qty ${_formatBomQuantity(item.quantity)}',
                            '\$${item.cost.toStringAsFixed(2)}',
                            if (duplicate) 'Possible duplicate',
                          ].join(' · '),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              key: const Key('confirm-inventory-json-import'),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.file_download_done_outlined),
              label: const Text('Import items'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return false;
      var importedItems = prepared.items;
      var importedImageCount = 0;
      var failedImageCount = 0;
      if (imageCount > 0) {
        final imageProgress = ValueNotifier<int>(0);
        final progressDialog = showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Importing product images'),
              content: SizedBox(
                width: 420,
                child: ValueListenableBuilder<int>(
                  valueListenable: imageProgress,
                  builder: (_, completed, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(
                        value: imageCount == 0 ? null : completed / imageCount,
                      ),
                      const SizedBox(height: 12),
                      Text('$completed of $imageCount images'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await WidgetsBinding.instance.endOfFrame;
        final imageResult = await downloadInventoryJsonImages(
          prepared.items,
          parsed.items,
          onProgress: (completed, _) => imageProgress.value = completed,
        );
        importedItems = imageResult.items;
        importedImageCount = imageResult.imported;
        failedImageCount = imageResult.failed;
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          await progressDialog;
        }
        imageProgress.dispose();
      }
      if (!mounted) return false;
      setState(() {
        materials.addAll(prepared.newMaterials);
        for (final replacement in prepared.updatedVendors.values) {
          final index = vendors.indexWhere(
            (vendor) => vendor.id == replacement.id,
          );
          if (index >= 0) vendors[index] = replacement;
        }
        for (final replacement in prepared.updatedBrands.values) {
          final index = brands.indexWhere(
            (brand) => brand.id == replacement.id,
          );
          if (index >= 0) brands[index] = replacement;
        }
        vendors.addAll(prepared.newVendors);
        brands.addAll(prepared.newBrands);
        for (final item in importedItems) {
          _addInventoryItem(item);
          _recordAddition(item);
          _recordAudit('import', 'inventory', item.id, {
            'name': item.name,
            'source': 'JSON',
          });
        }
        currentPage = 0;
      });
      _persist();
      _discardLoadedFullImages(importedItems);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            [
              '${prepared.items.length} inventory items imported.',
              if (importedImageCount > 0) '$importedImageCount images added.',
              if (failedImageCount > 0)
                '$failedImageCount images could not be downloaded.',
            ].join(' '),
          ),
        ),
      );
      return true;
    } on FormatException catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('JSON import failed: ${error.message}')),
      );
      return false;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('JSON import failed: $error')));
      return false;
    }
  }

  ({
    List<InventoryItem> items,
    List<MaterialRecord> newMaterials,
    List<VendorRecord> newVendors,
    List<BrandRecord> newBrands,
    Map<String, VendorRecord> updatedVendors,
    Map<String, BrandRecord> updatedBrands,
    List<String> errors,
  })
  prepareInventoryJsonImport(List<InventoryJsonDraft> drafts) {
    final preparedItems = <InventoryItem>[];
    final availableMaterials = [...materials];
    final newMaterials = <MaterialRecord>[];
    final availableVendors = [...vendors];
    final availableBrands = [...brands];
    final newVendors = <VendorRecord>[];
    final newBrands = <BrandRecord>[];
    final updatedVendors = <String, VendorRecord>{};
    final updatedBrands = <String, BrandRecord>{};
    final errors = <String>[];
    final now = DateTime.now();
    for (final draft in drafts) {
      final customType = customItemTypes
          .where(
            (candidate) =>
                _normalized(candidate.name) == _normalized(draft.typeName),
          )
          .firstOrNull;
      final type = draft.typeName.trim().isEmpty
          ? InventoryType.other
          : customType != null
          ? InventoryType.custom
          : smartMatchInventoryType(
              draft.typeName,
              typeAliases: {
                for (final type in InventoryType.values)
                  type: _inventoryTypeDisplayLabel(type),
              },
            );
      if (type == null) {
        errors.add(
          'Row ${draft.rowNumber}: unknown Type “${draft.typeName}”. Add it in Catalog or correct the JSON.',
        );
        continue;
      }
      final typeKey = customType == null
          ? 'type:${type.name}'
          : 'custom:${customType.id}';
      VendorRecord? vendor;
      if (draft.vendor.isNotEmpty) {
        vendor = availableVendors
            .where(
              (candidate) =>
                  _normalized(candidate.name) == _normalized(draft.vendor),
            )
            .firstOrNull;
        final vendorIsBrand =
            draft.brand.isNotEmpty &&
            _normalized(draft.brand) == _normalized(draft.vendor);
        if (vendor == null) {
          vendor = VendorRecord(
            id: _newCatalogId('VEN'),
            name: draft.vendor,
            isBrand: vendorIsBrand,
          );
          availableVendors.add(vendor);
          newVendors.add(vendor);
        } else if (vendorIsBrand && !vendor.isBrand) {
          final replacement = VendorRecord(
            id: vendor.id,
            name: vendor.name,
            isBrand: true,
            logoBytes: vendor.logoBytes,
          );
          final availableIndex = availableVendors.indexWhere(
            (candidate) => candidate.id == vendor!.id,
          );
          availableVendors[availableIndex] = replacement;
          final newIndex = newVendors.indexWhere(
            (candidate) => candidate.id == vendor!.id,
          );
          if (newIndex >= 0) {
            newVendors[newIndex] = replacement;
          } else {
            updatedVendors[replacement.id] = replacement;
          }
          vendor = replacement;
        }
      }
      if (draft.brand.isNotEmpty) {
        final existingBrand = availableBrands
            .where(
              (candidate) =>
                  _normalized(candidate.name) == _normalized(draft.brand),
            )
            .firstOrNull;
        final vendorIds = {
          ...?existingBrand?.vendorIds,
          if (vendor != null) vendor.id,
        };
        final categories = {...?existingBrand?.categories, type};
        final replacement = BrandRecord(
          id: existingBrand?.id ?? _newCatalogId('BRAND'),
          name: existingBrand?.name ?? draft.brand,
          vendorIds: vendorIds,
          categories: categories,
          logoBytes: existingBrand?.logoBytes,
        );
        if (existingBrand == null) {
          availableBrands.add(replacement);
          newBrands.add(replacement);
        } else if (vendorIds.length != existingBrand.vendorIds.length ||
            categories.length != existingBrand.categories.length) {
          final availableIndex = availableBrands.indexWhere(
            (candidate) => candidate.id == existingBrand.id,
          );
          availableBrands[availableIndex] = replacement;
          final newIndex = newBrands.indexWhere(
            (candidate) => candidate.id == existingBrand.id,
          );
          if (newIndex >= 0) {
            newBrands[newIndex] = replacement;
          } else {
            updatedBrands[replacement.id] = replacement;
          }
        }
      }
      MaterialRecord? material;
      if (draft.material.isNotEmpty) {
        material = availableMaterials
            .where(
              (candidate) =>
                  candidate.typeKey == typeKey &&
                  _normalized(candidate.name) == _normalized(draft.material),
            )
            .firstOrNull;
        if (material == null) {
          material = MaterialRecord(
            id: _newCatalogId('MAT'),
            name: draft.material,
            typeKey: typeKey,
          );
          availableMaterials.add(material);
          newMaterials.add(material);
        }
      }
      final namedColor = _itemColorSwatch(draft.color);
      final labelColor = _itemColorSwatch(draft.colorLabel);
      final itemColorName = namedColor != null
          ? _colorHex(namedColor)
          : labelColor != null
          ? _colorHex(labelColor)
          : _normalizeItemColorValue(draft.color);
      final itemColorLabel = draft.colorLabel.isNotEmpty
          ? draft.colorLabel
          : draft.color.startsWith('#')
          ? ''
          : draft.color;
      preparedItems.add(
        InventoryItem(
          id: _newInventoryId(),
          name: draft.name,
          type: type,
          customTypeId: customType?.id ?? '',
          customTypeName: customType?.name ?? '',
          compatibility: draft.compatibility,
          added: now,
          cost: draft.cost,
          quantity: draft.quantity,
          color: _typeColor(type),
          itemColorName: itemColorName,
          itemColorLabel: itemColorLabel,
          materialId: material?.id ?? '',
          materialName: material?.name ?? '',
          brand: draft.brand,
          vendor: draft.vendor,
          storageLocation: draft.storageLocation,
          barcode: draft.barcode,
          productUrl: draft.productUrl,
          amsCompatible: type == InventoryType.filament && draft.amsCompatible,
        ),
      );
    }
    return (
      items: preparedItems,
      newMaterials: newMaterials,
      newVendors: newVendors,
      newBrands: newBrands,
      updatedVendors: updatedVendors,
      updatedBrands: updatedBrands,
      errors: errors,
    );
  }

  Future<void> _showInventoryJsonErrors(List<String> errors) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Inventory JSON needs attention'),
          content: SizedBox(
            width: 620,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: errors.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xffff6b7a),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(errors[index])),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  StockLocationRecord? _itemStorageLocation(InventoryItem item) {
    if (item.storageLocationId.isNotEmpty) {
      final byId = locations
          .where((location) => location.id == item.storageLocationId)
          .firstOrNull;
      if (byId != null) return byId;
    }
    final storedPath = _normalized(item.storageLocation);
    if (storedPath.isEmpty) return null;
    return locations
        .where(
          (location) =>
              _normalized(_locationPath(location.id)) == storedPath ||
              _normalized(location.name) == storedPath,
        )
        .firstOrNull;
  }

  InventoryItem _withFullInventoryImages(InventoryItem item) {
    final images = widget.database?.loadInventoryImages(item.id);
    if (images == null) return item;
    return item.copyWith(
      imageBytes: images.imageBytes,
      labelImageBytes: images.labelImageBytes,
    );
  }

  InventoryItem _withoutFullInventoryImages(InventoryItem item) =>
      item.copyWith(clearImageBytes: true, clearLabelImageBytes: true);

  void _discardLoadedFullImages(Iterable<InventoryItem> items) {
    for (final item in items) {
      if (item.imageBytes == null && item.labelImageBytes == null) continue;
      final lightweight = _withoutFullInventoryImages(item);
      _publishInventoryItem(lightweight);
      _persistedEntityReferences.putIfAbsent(
        'inventory',
        () => {},
      )[lightweight.id] = lightweight;
    }
  }

  Future<void> _openDetails(InventoryItem item) async {
    final detailedItem = _withFullInventoryImages(item);
    final storageLocation = _itemStorageLocation(item);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close item details',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => Align(
        alignment: Alignment.centerRight,
        child: ItemDetailsPanel(
          item: detailedItem,
          typeLabel: _itemTypeDisplayLabel(detailedItem),
          typeIcon: _itemTypeIcon(detailedItem),
          typeIconImageBytes: _iconImageBytesFromKey(
            _itemTypeIconKey(detailedItem),
          ),
          initialWidth: itemDetailsPanelWidth,
          onWidthChanged: (width) => itemDetailsPanelWidth = width,
          machines: machines,
          machineTypes: machineTypes,
          spoolTypes: spoolTypes,
          onChanged: (updated) =>
              _updateItemById(_withoutFullInventoryImages(updated)),
          onEdit: currentRole.canEditInventory
              ? (item) => _handleAction(item, ItemAction.edit)
              : null,
          onSplitOne:
              currentRole.canEditInventory && currentRole.canCreateInventory
              ? _splitOneIntoNewStack
              : null,
          canEdit: currentRole.canEditInventory,
          canArchive: currentRole.canArchiveInventory,
          canMarkDepleted: _itemCanMarkDepleted(item),
          showStatus: _itemShowsStatus(item),
          onStorageLocationTap: storageLocation == null
              ? null
              : () => _openLocation(storageLocation),
        ),
      ),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(.12, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _splitOneIntoNewStack(InventoryItem source) async {
    if (!currentRole.canEditInventory || !currentRole.canCreateInventory) {
      _showPermissionDenied(
        'Your role cannot split inventory into a new stack.',
      );
      return;
    }
    final index = inventory.indexWhere((item) => item.id == source.id);
    if (index < 0) return;
    final current = inventory[index];
    if (current.quantity <= 1) {
      _showPermissionDenied('This stack needs more than one item to split.');
      return;
    }

    final detailedSource = _withFullInventoryImages(current);
    final splitItem = detailedSource.copyWith(
      id: _newInventoryId(),
      quantity: 1,
    );
    setState(() {
      _publishInventoryItem(current.copyWith(quantity: current.quantity - 1));
      _addInventoryItem(splitItem);
      _recordAudit('split', 'inventory', splitItem.id, {
        'source': current.id,
        'name': splitItem.name,
        'quantity': '1',
      });
    });
    _persist();
    _discardLoadedFullImages([splitItem]);
    final lightweightSplit = inventory
        .where((item) => item.id == splitItem.id)
        .first;
    if (mounted) await _openDetails(lightweightSplit);
  }

  Future<void> _handleAction(InventoryItem item, ItemAction action) async {
    final allowed = switch (action) {
      ItemAction.showCompatibleFilaments => true,
      ItemAction.delete => currentRole.canHardDeleteItems,
      ItemAction.duplicate => currentRole.canCreateInventory,
      ItemAction.archive => currentRole.canArchiveInventory,
      ItemAction.edit ||
      ItemAction.resetDryTimer => currentRole.canEditInventory,
    };
    if (!allowed) {
      _showPermissionDenied('Your role cannot perform that action.');
      return;
    }
    switch (action) {
      case ItemAction.showCompatibleFilaments:
        await showDialog<void>(
          context: context,
          builder: (_) => _CompatibleFilamentsDialog(
            printedPart: item,
            filaments: _compatibleFilamentsFor(item),
            spoolSizeLabel: _spoolSizeLabel,
          ),
        );
      case ItemAction.resetDryTimer:
        if (item.dryingMinutes == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This item has no drying timer.')),
          );
          return;
        }
        _replaceItem(
          item,
          item.copyWith(
            dryingRemaining: item.dryingMinutes,
            dryingStartedAt: DateTime.now(),
            filamentStatus: FilamentStatus.drying,
            deployed: false,
          ),
        );
      case ItemAction.edit:
        final edited = await showDialog<InventoryItem>(
          context: context,
          builder: (_) => AddItemDialog(
            initialItem: item,
            vendors: vendors,
            brands: brands,
            spoolTypes: spoolTypes,
            materials: materials,
            customItemTypes: customItemTypes,
            typeLabelOverrides: typeLabelOverrides,
            typeIconOverrides: typeIconOverrides,
            products: products,
            machineTypes: machineTypes,
            machines: machines,
            locations: locations,
            database: widget.database,
          ),
        );
        if (edited != null) _replaceItem(item, edited);
      case ItemAction.duplicate:
        final duplicate = _withFullInventoryImages(item).copyWith(
          id: _newInventoryId(),
          name: '${item.name} copy',
          added: DateTime.now(),
          archived: false,
        );
        setState(() {
          _addInventoryItem(duplicate);
          _recordAddition(duplicate);
          _recordAudit('duplicate', 'inventory', duplicate.id, {
            'source': item.id,
            'name': duplicate.name,
          });
        });
        _persist();
        _discardLoadedFullImages([duplicate]);
      case ItemAction.archive:
        _replaceItem(
          item,
          item.copyWith(
            archived: !item.archived,
            archiveDisposition: ArchiveDisposition.archived,
          ),
        );
      case ItemAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete item?'),
            content: Text('Permanently delete “${item.name}”?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          setState(() {
            _removeInventoryItem(item.id);
            selectedInventoryIds.remove(item.id);
            _recordAudit('delete', 'inventory', item.id, {'name': item.name});
          });
          _persist();
        }
    }
  }

  List<InventoryItem> _compatibleFilamentsFor(InventoryItem printedPart) {
    final stockedFilaments = inventory
        .where(
          (candidate) =>
              candidate.type == InventoryType.filament &&
              !candidate.archived &&
              candidate.quantity > 0,
        )
        .toList();
    final partTags = printedPart.compatibility
        .map(_normalized)
        .where((tag) => tag.isNotEmpty)
        .toSet();
    final partMachines = printedPart.compatibleMachineIds.toSet();
    if (partTags.isEmpty && partMachines.isEmpty) return stockedFilaments;

    return stockedFilaments.where((filament) {
      final sharedMachine = filament.compatibleMachineIds.any(
        partMachines.contains,
      );
      final filamentText = _normalized(
        '${filament.name} ${filament.brand} ${filament.materialName} ${filament.compatibility.join(' ')}',
      );
      final sharedTag = partTags.any(filamentText.contains);
      return sharedMachine || sharedTag;
    }).toList();
  }

  void _showPermissionDenied(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _replaceItem(InventoryItem oldItem, InventoryItem newItem) {
    if (!mounted) return;
    final enteredLowStock = !_isLowStock(oldItem) && _isLowStock(newItem);
    setState(() {
      // A cloud poll can rebuild the inventory with fresh object instances
      // while an Edit dialog is open. Match the stable ID so Save still
      // updates the current in-memory item instead of silently doing nothing.
      _publishInventoryItem(newItem);
      final changes = <String, String>{};
      if (oldItem.name != newItem.name) {
        changes['name'] = '${oldItem.name} → ${newItem.name}';
      }
      if (oldItem.quantity != newItem.quantity) {
        changes['quantity'] =
            '${_formatBomQuantity(oldItem.quantity)} → ${_formatBomQuantity(newItem.quantity)}';
      }
      if (oldItem.archived != newItem.archived ||
          oldItem.archiveDisposition != newItem.archiveDisposition) {
        changes['status'] = newItem.archived
            ? newItem.archiveDisposition.name
            : 'active';
      }
      if (changes.isNotEmpty) {
        _recordAudit('edit', 'inventory', newItem.id, changes);
      }
      if (enteredLowStock) {
        _lowStockAnimationVersions[newItem.id] =
            (_lowStockAnimationVersions[newItem.id] ?? 0) + 1;
      }
    });
    _persist();
    _discardLoadedFullImages([newItem]);
    _checkMoistureThresholdAnimations();
  }

  void _updateItemById(InventoryItem item) {
    if (!mounted) return;
    if (!currentRole.canEditInventory) {
      _showPermissionDenied('Your role is view/build only.');
      return;
    }
    final previous = inventory
        .where((candidate) => candidate.id == item.id)
        .firstOrNull;
    final enteredLowStock =
        previous != null && !_isLowStock(previous) && _isLowStock(item);
    setState(() {
      _publishInventoryItem(item);
      if (previous != null) {
        final changes = <String, String>{};
        if (previous.name != item.name) {
          changes['name'] = '${previous.name} → ${item.name}';
        }
        if (previous.quantity != item.quantity) {
          changes['quantity'] =
              '${_formatBomQuantity(previous.quantity)} → ${_formatBomQuantity(item.quantity)}';
        }
        if (previous.filamentStatus != item.filamentStatus) {
          changes['status'] =
              '${previous.filamentStatus.name} → ${item.filamentStatus.name}';
        }
        if (changes.isNotEmpty) {
          _recordAudit('edit', 'inventory', item.id, changes);
        }
      }
      if (enteredLowStock) {
        _lowStockAnimationVersions[item.id] =
            (_lowStockAnimationVersions[item.id] ?? 0) + 1;
      }
    });
    _persist();
    _checkMoistureThresholdAnimations();
  }

  void _adjustItemQuantity(InventoryItem item, double delta) {
    if (!currentRole.canEditInventory) {
      _showPermissionDenied('Your role is view/build only.');
      return;
    }
    final current = inventory
        .where((candidate) => candidate.id == item.id)
        .firstOrNull;
    if (current == null) return;
    final quantity = math.max(0, current.quantity + delta).toDouble();
    if (quantity == current.quantity) return;
    _quantityCommitOriginals.putIfAbsent(item.id, () => current);
    _publishInventoryItem(current.copyWith(quantity: quantity));
    _invalidateSearchCaches();
    _quantityCommitTimers.remove(item.id)?.cancel();
    _quantityCommitTimers[item.id] = Timer(
      const Duration(seconds: 1),
      () => _commitPendingQuantityChange(item.id),
    );
  }

  void _commitPendingQuantityChange(String itemId) {
    _quantityCommitTimers.remove(itemId)?.cancel();
    final original = _quantityCommitOriginals.remove(itemId);
    if (original == null || !mounted) return;
    final changed = _recordPendingQuantityAudit(itemId, original);
    if (!changed) return;
    final current = inventory
        .where((candidate) => candidate.id == itemId)
        .firstOrNull;
    if (current != null) _publishInventoryItem(current.copyWith());
    if (current != null) _persistInventoryItem(current);
    _checkMoistureThresholdAnimations();
  }

  bool _recordPendingQuantityAudit(String itemId, InventoryItem original) {
    final current = inventory
        .where((candidate) => candidate.id == itemId)
        .firstOrNull;
    if (current == null || current.quantity == original.quantity) return false;
    _recordAudit('edit', 'inventory', itemId, {
      'quantity':
          '${_formatBomQuantity(original.quantity)} → ${_formatBomQuantity(current.quantity)}',
    });
    if (!_isLowStock(original) && _isLowStock(current)) {
      _lowStockAnimationVersions[itemId] =
          (_lowStockAnimationVersions[itemId] ?? 0) + 1;
    }
    return true;
  }

  Future<void> _openCatalog({
    String? initialKitId,
    List<KitBomEntry>? initialKitBom,
  }) => showDialog<void>(
    context: context,
    builder: (_) => CatalogManagerDialog(
      vendors: vendors,
      brands: brands,
      spoolTypes: spoolTypes,
      materials: materials,
      customItemTypes: customItemTypes,
      typeLabelOverrides: typeLabelOverrides,
      typeIconOverrides: typeIconOverrides,
      typeDepletionSettings: typeDepletionSettings,
      typeStatusSettings: typeStatusSettings,
      deletedTypeKeys: deletedTypeKeys,
      customTypeUsageCounts: {
        for (final customType in customItemTypes)
          customType.id: inventory
              .where((item) => item.customTypeId == customType.id)
              .length,
      },
      products: products,
      inventoryItems: inventory,
      machineTypes: machineTypes,
      machines: machines,
      kits: kits,
      initialKitId: initialKitId,
      initialKitBom: initialKitBom,
      onImportKitPackage: _importKitPackage,
      onVendorAdded: (vendor) {
        setState(() => vendors.add(vendor));
        _persist();
      },
      onBrandAdded: (brand) {
        setState(() => brands.add(brand));
        _persist();
      },
      onSpoolTypeAdded: (spoolType) {
        setState(() => spoolTypes.add(spoolType));
        _persist();
      },
      onMaterialAdded: (material) {
        setState(() => materials.add(material));
        _persist();
      },
      onMaterialUpdated: (material) {
        setState(() {
          final index = materials.indexWhere(
            (candidate) => candidate.id == material.id,
          );
          final previous = index >= 0 ? materials[index] : null;
          if (index >= 0) materials[index] = material;
          for (var index = 0; index < inventory.length; index++) {
            if (inventory[index].materialId == material.id) {
              inventory[index] = previous?.typeKey == material.typeKey
                  ? inventory[index].copyWith(materialName: material.name)
                  : inventory[index].copyWith(materialId: '', materialName: '');
            }
            if (inventory[index].spoolMaterialId == material.id) {
              inventory[index] = previous?.typeKey == material.typeKey
                  ? inventory[index].copyWith(spoolMaterialName: material.name)
                  : inventory[index].copyWith(
                      spoolMaterialId: '',
                      spoolMaterialName: '',
                    );
            }
            if (inventory[index].masterSpoolMaterialId == material.id) {
              inventory[index] = previous?.typeKey == material.typeKey
                  ? inventory[index].copyWith(
                      masterSpoolMaterialName: material.name,
                    )
                  : inventory[index].copyWith(
                      masterSpoolMaterialId: '',
                      masterSpoolMaterialName: '',
                    );
            }
          }
        });
        _persist();
      },
      onMaterialDeleted: (material) {
        setState(() {
          materials.removeWhere((candidate) => candidate.id == material.id);
          for (var index = 0; index < inventory.length; index++) {
            if (inventory[index].materialId == material.id) {
              inventory[index] = inventory[index].copyWith(
                materialId: '',
                materialName: '',
              );
            }
            if (inventory[index].spoolMaterialId == material.id) {
              inventory[index] = inventory[index].copyWith(
                spoolMaterialId: '',
                spoolMaterialName: '',
              );
            }
            if (inventory[index].masterSpoolMaterialId == material.id) {
              inventory[index] = inventory[index].copyWith(
                masterSpoolMaterialId: '',
                masterSpoolMaterialName: '',
              );
            }
          }
        });
        _persist();
      },
      onCustomItemTypeAdded: (customType) {
        setState(() => customItemTypes.add(customType));
        _persist();
      },
      onCustomItemTypeUpdated: (customType) {
        setState(() {
          final index = customItemTypes.indexWhere(
            (candidate) => candidate.id == customType.id,
          );
          if (index >= 0) customItemTypes[index] = customType;
          for (var index = 0; index < inventory.length; index++) {
            final item = inventory[index];
            if (item.customTypeId == customType.id) {
              inventory[index] = item.copyWith(customTypeName: customType.name);
            }
          }
        });
        _persist();
      },
      onCustomItemTypeDeleted: (customType) {
        setState(() {
          customItemTypes.removeWhere(
            (candidate) => candidate.id == customType.id,
          );
          for (var index = 0; index < inventory.length; index++) {
            final item = inventory[index];
            if (item.customTypeId == customType.id) {
              inventory[index] = item.copyWith(
                type: InventoryType.other,
                customTypeId: '',
                customTypeName: '',
                customFieldValues: const {},
                materialId: '',
                materialName: '',
              );
            }
          }
          if (customTypeFilterId == customType.id) {
            customTypeFilterId = null;
            type = null;
          }
        });
        _persist();
      },
      onBuiltInTypeRenamed: (entry) {
        setState(() => typeLabelOverrides[entry.key] = entry.value);
        _persist();
      },
      onBuiltInTypeIconChanged: (entry) {
        setState(() => typeIconOverrides[entry.key] = entry.value);
        _persist();
      },
      onBuiltInTypeDepletionChanged: (entry) {
        setState(() => typeDepletionSettings[entry.key] = entry.value);
        _persist();
      },
      onBuiltInTypeStatusChanged: (entry) {
        setState(() => typeStatusSettings[entry.key] = entry.value);
        _persist();
      },
      onBuiltInTypeDeleted: _deleteBuiltInType,
      onBuiltInTypeRestored: (key) {
        setState(() => deletedTypeKeys.remove(key));
        _persist();
      },
      canDeleteCustomItemTypes: workspaceOwner,
      onProductAdded: (product) {
        setState(() => products.add(product));
        _persist();
      },
      onMachineTypeAdded: (machineType) {
        setState(() => machineTypes.add(machineType));
        _persist();
      },
      onMachineAdded: (machine) {
        setState(() => machines.add(machine));
        _persist();
      },
      onMachineUpdated: (machine) {
        setState(() {
          final index = machines.indexWhere(
            (candidate) => candidate.id == machine.id,
          );
          if (index >= 0) machines[index] = machine;
        });
        _persist();
      },
      onKitAdded: (kit) {
        setState(() => kits.add(kit));
        _persist();
      },
      onKitUpdated: (kit) {
        setState(() {
          final index = kits.indexWhere((candidate) => candidate.id == kit.id);
          if (index >= 0) kits[index] = kit;
        });
        _persist();
      },
    ),
  );

  Future<bool> _importKitPackage() async {
    if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      _showPermissionDenied('Kit package import is available on desktop.');
      return false;
    }
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Import Inventorinator kit package',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null || !mounted) return false;
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('Kit packages must be 10 MB or smaller.');
      }
      final parsed = parseInventorinatorKitPackage(utf8.decode(bytes));
      if (!mounted) return false;
      if (!parsed.isValid) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Kit package needs attention'),
            content: SizedBox(
              width: 620,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: parsed.errors.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xffff6b7a),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(parsed.errors[index])),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return false;
      }
      final previewPlan = createKitPackageImportPlan(parsed.package!);
      if (!mounted) return false;
      final decision = await showDialog<_KitPackageImportDecision>(
        context: context,
        builder: (_) => _KitPackageImportPreviewDialog(plan: previewPlan),
      );
      if (decision == null || !mounted) return false;
      final plan = createKitPackageImportPlan(
        parsed.package!,
        inventoryMatchesByPartId: decision.inventoryMatchesByPartId,
      );
      setState(() {
        inventory
          ..clear()
          ..addAll(plan.inventory);
        brands
          ..clear()
          ..addAll(plan.brands);
        materials
          ..clear()
          ..addAll(plan.materials);
        products
          ..clear()
          ..addAll(plan.products);
        machineTypes
          ..clear()
          ..addAll(plan.machineTypes);
        machines
          ..clear()
          ..addAll(plan.machines);
        kits
          ..clear()
          ..addAll(plan.kits);
        for (final item in plan.newInventoryItems) {
          _recordAddition(item);
        }
        _recordAudit(
          'import',
          'kit',
          _kitPackageStableId('KIT', plan.package.id),
          {
            'name': plan.package.name,
            'parts': plan.package.parts.length.toString(),
            'machines': plan.package.machines.length.toString(),
          },
        );
        currentPage = 0;
      });
      _persist();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${plan.package.name} imported · ${plan.package.parts.length} BOM lines · ${plan.newInventoryItems.length} zero-quantity items added',
          ),
        ),
      );
      return true;
    } on FormatException catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kit package import failed: ${error.message}')),
      );
      return false;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kit package import failed: $error')),
      );
      return false;
    }
  }

  _KitPackageImportPlan createKitPackageImportPlan(
    InventorinatorKitPackage package, {
    Map<String, String> inventoryMatchesByPartId = const {},
  }) {
    final existingInventory = [...inventory];
    final nextInventory = [...inventory];
    final nextBrands = [...brands];
    final nextMaterials = [...materials];
    final nextProducts = [...products];
    final nextMachineTypes = [...machineTypes];
    final nextMachines = [...machines];
    final nextKits = [...kits];
    final newInventoryItems = <InventoryItem>[];
    var newProductCount = 0;
    var reusedProductCount = 0;
    var newMachineCount = 0;
    var updatedMachineCount = 0;
    final matchedInventoryIdsByPartId = <String, String>{};
    final kitId = _kitPackageStableId('KIT', package.id);

    final importedMachineIds = <String>[];
    for (final packageMachine in package.machines) {
      var machineTypeIndex = nextMachineTypes.indexWhere(
        (candidate) =>
            _normalized(candidate.name) == _normalized(packageMachine.type),
      );
      if (machineTypeIndex < 0) {
        nextMachineTypes.add(
          MachineTypeRecord(
            id: _kitPackageStableId('MT', package.id, packageMachine.type),
            name: packageMachine.type,
          ),
        );
        machineTypeIndex = nextMachineTypes.length - 1;
      }
      final stableMachineId = _kitPackageStableId(
        'MCH',
        package.id,
        packageMachine.id,
      );
      var machineIndex = nextMachines.indexWhere(
        (candidate) => candidate.id == stableMachineId,
      );
      machineIndex = machineIndex >= 0
          ? machineIndex
          : nextMachines.indexWhere(
              (candidate) =>
                  _normalized(candidate.name) ==
                  _normalized(packageMachine.name),
            );
      final sourceUrls = packageMachine.sources
          .map((source) => source.url)
          .toSet()
          .toList();
      if (machineIndex >= 0) {
        final existing = nextMachines[machineIndex];
        nextMachines[machineIndex] = MachineRecord(
          id: existing.id,
          name: packageMachine.name,
          model: packageMachine.model,
          address: packageMachine.address,
          typeId: nextMachineTypes[machineTypeIndex].id,
          kitIds: {...existing.kitIds, kitId},
          sourceUrls: {...existing.sourceUrls, ...sourceUrls}.toList(),
          imageBytes: existing.imageBytes,
        );
        importedMachineIds.add(existing.id);
        updatedMachineCount++;
      } else {
        final machine = MachineRecord(
          id: stableMachineId,
          name: packageMachine.name,
          model: packageMachine.model,
          address: packageMachine.address,
          typeId: nextMachineTypes[machineTypeIndex].id,
          kitIds: {kitId},
          sourceUrls: sourceUrls,
        );
        nextMachines.add(machine);
        importedMachineIds.add(machine.id);
        newMachineCount++;
      }
    }

    final sectionNames = {
      for (final section in package.sections) section.id: section.name,
    };
    final bom = <KitBomEntry>[];
    for (final part in package.parts) {
      final packageType = InventoryType.values.byName(part.type);
      final hasMatchOverride = inventoryMatchesByPartId.containsKey(part.id);
      final requestedInventoryId = inventoryMatchesByPartId[part.id] ?? '';
      var matchedInventoryIndex = requestedInventoryId.isEmpty
          ? -1
          : nextInventory.indexWhere(
              (candidate) => candidate.id == requestedInventoryId,
            );
      if (!hasMatchOverride) {
        matchedInventoryIndex = nextInventory.indexWhere(
          (candidate) =>
              !candidate.archived &&
              candidate.type == packageType &&
              _normalized(candidate.name) == _normalized(part.name),
        );
        if (matchedInventoryIndex < 0) {
          final rankedCandidates =
              nextInventory
                  .asMap()
                  .entries
                  .where((entry) => !entry.value.archived)
                  .map(
                    (entry) => (
                      index: entry.key,
                      score: _kitPartInventoryMatchScore(part, entry.value),
                    ),
                  )
                  .toList()
                ..sort((a, b) => b.score.compareTo(a.score));
          if (rankedCandidates.isNotEmpty &&
              rankedCandidates.first.score >= .84) {
            matchedInventoryIndex = rankedCandidates.first.index;
          }
        }
      }
      final matchedInventory = matchedInventoryIndex >= 0
          ? nextInventory[matchedInventoryIndex]
          : null;
      final type = matchedInventory?.type ?? packageType;
      if (matchedInventory != null) {
        matchedInventoryIdsByPartId[part.id] = matchedInventory.id;
      }
      String brandId = '';
      if (part.brand.isNotEmpty) {
        var brandIndex = nextBrands.indexWhere(
          (candidate) => _normalized(candidate.name) == _normalized(part.brand),
        );
        if (brandIndex < 0) {
          nextBrands.add(
            BrandRecord(
              id: _kitPackageStableId('BR', package.id, part.brand),
              name: part.brand,
              vendorIds: const {},
              categories: {type},
            ),
          );
          brandIndex = nextBrands.length - 1;
        } else if (!nextBrands[brandIndex].categories.contains(type)) {
          final existing = nextBrands[brandIndex];
          nextBrands[brandIndex] = BrandRecord(
            id: existing.id,
            name: existing.name,
            vendorIds: existing.vendorIds,
            categories: {...existing.categories, type},
            logoBytes: existing.logoBytes,
          );
        }
        brandId = nextBrands[brandIndex].id;
      }

      MaterialRecord? material;
      if (part.material.isNotEmpty) {
        final typeKey = 'type:${type.name}';
        material = nextMaterials
            .where(
              (candidate) =>
                  candidate.typeKey == typeKey &&
                  _normalized(candidate.name) == _normalized(part.material),
            )
            .firstOrNull;
        if (material == null) {
          material = MaterialRecord(
            id: _kitPackageStableId(
              'MAT',
              package.id,
              '${type.name}-${part.material}',
            ),
            name: part.material,
            typeKey: typeKey,
          );
          nextMaterials.add(material);
        }
      }

      final stableProductId = _kitPackageStableId('PROD', package.id, part.id);
      var productIndex = matchedInventory?.catalogProductId == null
          ? -1
          : nextProducts.indexWhere(
              (candidate) => candidate.id == matchedInventory!.catalogProductId,
            );
      productIndex = productIndex >= 0
          ? productIndex
          : nextProducts.indexWhere(
              (candidate) => candidate.id == stableProductId,
            );
      productIndex = productIndex >= 0
          ? productIndex
          : nextProducts.indexWhere(
              (candidate) =>
                  candidate.category == type &&
                  _normalized(candidate.name) ==
                      _normalized(matchedInventory?.name ?? part.name),
            );
      final partSourceUrls = part.sources
          .map((source) => source.url)
          .toSet()
          .toList();
      late CatalogProduct product;
      if (productIndex >= 0) {
        final existing = nextProducts[productIndex];
        product = CatalogProduct(
          id: existing.id,
          brandId: brandId.isEmpty ? existing.brandId : brandId,
          category: existing.category,
          name: existing.name,
          defaultCost: part.unitCost,
          dryingMinutes: existing.dryingMinutes,
          printingInstructions: existing.printingInstructions,
          dryingInstructions: existing.dryingInstructions,
          storageInstructions: existing.storageInstructions,
          sourceUrls: {...existing.sourceUrls, ...partSourceUrls}.toList(),
          imageBytes: existing.imageBytes,
        );
        nextProducts[productIndex] = product;
        reusedProductCount++;
      } else {
        product = CatalogProduct(
          id: stableProductId,
          brandId: brandId,
          category: type,
          name: matchedInventory?.name ?? part.name,
          defaultCost: matchedInventory?.cost ?? part.unitCost,
          sourceUrls: partSourceUrls,
        );
        nextProducts.add(product);
        newProductCount++;
      }

      if (matchedInventoryIndex >= 0 &&
          nextInventory[matchedInventoryIndex].catalogProductId != product.id) {
        nextInventory[matchedInventoryIndex] =
            nextInventory[matchedInventoryIndex].copyWith(
              catalogProductId: product.id,
            );
      }
      final forceNewInventoryItem =
          hasMatchOverride && requestedInventoryId.isEmpty;
      final inventoryExists =
          matchedInventoryIndex >= 0 ||
          (!forceNewInventoryItem &&
              nextInventory.any(
                (candidate) =>
                    candidate.catalogProductId == product.id ||
                    (candidate.type == packageType &&
                        _normalized(candidate.name) == _normalized(part.name)),
              ));
      if (!inventoryExists) {
        final item = InventoryItem(
          id: _kitPackageStableId('INV', package.id, part.id),
          name: part.name,
          type: type,
          compatibility: part.compatibility,
          added: DateTime.now(),
          cost: part.unitCost,
          color: _typeColor(type),
          quantity: 0,
          brand: part.brand,
          productUrl:
              partSourceUrls.firstOrNull ??
              package.sources.firstOrNull?.url ??
              '',
          compatibleMachineIds: importedMachineIds,
          catalogProductId: product.id,
          materialId: material?.id ?? '',
          materialName: material?.name ?? '',
        );
        nextInventory.add(item);
        newInventoryItems.add(item);
      }
      bom.add(
        KitBomEntry(
          id: _kitPackageStableId('LINE', package.id, part.id),
          productId: product.id,
          quantity: part.quantity,
          name: part.name,
          section: sectionNames[part.sectionId]!,
        ),
      );
    }

    final kitIndex = nextKits.indexWhere((candidate) => candidate.id == kitId);
    final kit = KitRecord(
      id: kitId,
      name: package.name,
      bom: bom,
      sections: package.sections.map((section) => section.name).toList(),
      sourceUrls: package.sources.map((source) => source.url).toList(),
      imageBytes: kitIndex >= 0 ? nextKits[kitIndex].imageBytes : null,
    );
    if (kitIndex >= 0) {
      nextKits[kitIndex] = kit;
    } else {
      nextKits.add(kit);
    }

    return _KitPackageImportPlan(
      package: package,
      existingInventory: existingInventory,
      inventory: nextInventory,
      brands: nextBrands,
      materials: nextMaterials,
      products: nextProducts,
      machineTypes: nextMachineTypes,
      machines: nextMachines,
      kits: nextKits,
      newInventoryItems: newInventoryItems,
      newProductCount: newProductCount,
      reusedProductCount: reusedProductCount,
      newMachineCount: newMachineCount,
      updatedMachineCount: updatedMachineCount,
      kitWillUpdate: kitIndex >= 0,
      matchedInventoryIdsByPartId: matchedInventoryIdsByPartId,
    );
  }

  void _deleteBuiltInType(String key) {
    setState(() {
      deletedTypeKeys.add(key);
      typeLabelOverrides.remove(key);
      typeIconOverrides.remove(key);

      if (key.startsWith('item:')) {
        final typeName = key.substring('item:'.length);
        final deletedType = InventoryType.values
            .where((candidate) => candidate.name == typeName)
            .firstOrNull;
        if (deletedType != null && deletedType != InventoryType.other) {
          for (var index = 0; index < inventory.length; index++) {
            final item = inventory[index];
            if (item.type == deletedType) {
              inventory[index] = item.copyWith(type: InventoryType.other);
            }
          }
          for (var index = 0; index < products.length; index++) {
            final product = products[index];
            if (product.category != deletedType) continue;
            products[index] = CatalogProduct(
              id: product.id,
              brandId: product.brandId,
              category: InventoryType.other,
              name: product.name,
              defaultCost: product.defaultCost,
              dryingMinutes: product.dryingMinutes,
              printingInstructions: product.printingInstructions,
              dryingInstructions: product.dryingInstructions,
              storageInstructions: product.storageInstructions,
              sourceUrls: product.sourceUrls,
              imageBytes: product.imageBytes,
            );
          }
          if (type == deletedType) type = null;
        }
      } else if (key.startsWith('catalog:')) {
        final filterName = key.substring('catalog:'.length);
        if (catalogFilter?.name == filterName) catalogFilter = null;
      }
      currentPage = 0;
    });
    _persist();
  }

  Future<void> _openKitDetails(KitRecord kit) {
    final availableQuantity = _inventoryAvailabilitySnapshot();
    return showDialog<void>(
      context: context,
      builder: (_) => KitDetailsDialog(
        kit: kit,
        kits: kits,
        products: products,
        inventory: inventory,
        availableQuantity: availableQuantity,
        onMatchInventory: _matchKitBomLineToInventory,
        canMatchInventory: currentRole.canManageCatalog,
        onAddShortage: _addKitShortageToShoppingList,
        onBuild: _createBuild,
        canBuild: currentRole.canCreateBuilds,
        canDelete: currentRole.canHardDeleteItems,
        onDelete: _confirmDeleteKit,
        buildDisabledReason: currentRole.canCreateBuilds
            ? null
            : _buildDisabledReason,
      ),
    );
  }

  Future<void> _openMachineDetails(MachineRecord machine) => showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final linkedKits = kits
          .where((kit) => machine.kitIds.contains(kit.id))
          .toList();
      final typeName = _machineTypePath(machine.typeId).trim();
      return AlertDialog(
        key: Key('machine-details-${machine.id}'),
        title: Row(
          children: [
            _catalogRecordVisual(
              machine.imageBytes,
              _isPrinter(machine)
                  ? Icons.print_outlined
                  : Icons.precision_manufacturing_outlined,
              _isPrinter(machine)
                  ? const Color(0xff42d8c7)
                  : const Color(0xffffb34d),
              48,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(machine.name)),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (typeName.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('Type'),
                    subtitle: Text(typeName),
                  ),
                if (machine.model.trim().isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Model'),
                    subtitle: Text(machine.model),
                  ),
                if (machine.address.trim().isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lan_outlined),
                    title: const Text('Address'),
                    subtitle: SelectableText(
                      machine.address,
                      key: Key('machine-address-${machine.id}'),
                    ),
                  ),
                if (linkedKits.isNotEmpty) ...[
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      'Associated kits',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  for (final kit in linkedKits)
                    ListTile(
                      key: Key('machine-kit-details-${kit.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(kit.name),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        unawaited(_openKitDetails(kit));
                      },
                    ),
                ],
                if (machine.sourceUrls.isNotEmpty) ...[
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      'Sources',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  for (final source in machine.sourceUrls)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.link_rounded),
                      title: Text(
                        source,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.open_in_new_rounded),
                      onTap: () {
                        final uri = Uri.tryParse(source);
                        if (uri != null) {
                          unawaited(
                            launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            ),
                          );
                        }
                      },
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  String get _buildDisabledReason {
    final source = widget.database?.loadSyncConfig();
    if (source != null) {
      try {
        final config = SupabaseConfig.fromJson(
          jsonDecode(source) as Map<String, dynamic>,
        );
        if (config.syncMode == 'supabase' && config.workspaceRole == null) {
          return 'Build unavailable: the remote role has not loaded. Update the server role migration, then sync again.';
        }
      } catch (_) {
        // Fall through to the normal role explanation.
      }
    }
    return 'Your workspace role can use shared builds, but cannot create one.';
  }

  Future<void> _openKitEditor(KitRecord kit) =>
      _openCatalog(initialKitId: kit.id);

  String _kitLineName(KitBomEntry line) =>
      line.name ??
      products
          .where((product) => product.id == line.productId)
          .firstOrNull
          ?.name ??
      kits.where((kit) => kit.id == line.productId).firstOrNull?.name ??
      'Missing item';

  double _availableInventoryQuantity(String productId, String name) => inventory
      .where(
        (item) =>
            !item.archived &&
            item.quantity > 0 &&
            (item.id == productId ||
                item.catalogProductId == productId ||
                _normalized(item.name) == _normalized(name)),
      )
      .fold(0, (total, item) => total + item.quantity);

  String _stockKey(String productId, String name) {
    final normalizedName = _normalized(name);
    final match =
        inventory
            .where(
              (item) =>
                  item.id == productId || item.catalogProductId == productId,
            )
            .firstOrNull ??
        inventory
            .where((item) => _normalized(item.name) == normalizedName)
            .firstOrNull;
    if (match != null) {
      return match.catalogProductId?.isNotEmpty == true
          ? 'product:${match.catalogProductId}'
          : 'inventory:${match.id}';
    }
    return productId.isEmpty ? 'name:$normalizedName' : 'product:$productId';
  }

  double _reservedInventoryQuantity(String productId, String name) {
    final key = _stockKey(productId, name);
    return builds
        .where((build) => build.completedAt == null)
        .expand((build) => build.lines)
        .where((line) => _stockKey(line.productId, line.name) == key)
        .fold<double>(
          0,
          (total, line) =>
              total +
              (line.requiredQuantity - line.usedQuantity).clamp(
                0,
                line.requiredQuantity,
              ),
        );
  }

  double Function(String productId, String name)
  _inventoryAvailabilitySnapshot() {
    final byId = <String, InventoryItem>{};
    final byCatalogId = <String, InventoryItem>{};
    final byName = <String, InventoryItem>{};
    for (final item in inventory) {
      byId.putIfAbsent(item.id, () => item);
      final catalogId = item.catalogProductId;
      if (catalogId != null && catalogId.isNotEmpty) {
        byCatalogId.putIfAbsent(catalogId, () => item);
      }
      byName.putIfAbsent(_normalized(item.name), () => item);
    }

    String stockKey(String productId, String name) {
      final normalizedName = _normalized(name);
      final match =
          byId[productId] ?? byCatalogId[productId] ?? byName[normalizedName];
      if (match != null) {
        return match.catalogProductId?.isNotEmpty == true
            ? 'product:${match.catalogProductId}'
            : 'inventory:${match.id}';
      }
      return productId.isEmpty ? 'name:$normalizedName' : 'product:$productId';
    }

    final reservedByKey = <String, double>{};
    for (final build in builds.where((build) => build.completedAt == null)) {
      for (final line in build.lines) {
        final remaining = (line.requiredQuantity - line.usedQuantity).clamp(
          0,
          line.requiredQuantity,
        );
        final key = stockKey(line.productId, line.name);
        reservedByKey[key] = (reservedByKey[key] ?? 0) + remaining;
      }
    }

    return (productId, name) {
      final normalizedName = _normalized(name);
      final available = inventory
          .where(
            (item) =>
                !item.archived &&
                item.quantity > 0 &&
                (item.id == productId ||
                    item.catalogProductId == productId ||
                    _normalized(item.name) == normalizedName),
          )
          .fold<double>(0, (total, item) => total + item.quantity);
      return math.max(
        0,
        available - (reservedByKey[stockKey(productId, name)] ?? 0),
      );
    };
  }

  Map<String, ({String productId, String name, double quantity})>
  _flattenKitRequirements(KitRecord kit) {
    final result =
        <String, ({String productId, String name, double quantity})>{};
    void expand(KitRecord source, double multiplier, Set<String> path) {
      if (!path.add(source.id)) return;
      for (final line in source.bom) {
        final nested = kits
            .where((candidate) => candidate.id == line.productId)
            .firstOrNull;
        if (nested != null) {
          expand(nested, multiplier * line.quantity, {...path});
          continue;
        }
        final name = _kitLineName(line);
        final key = _stockKey(line.productId, name);
        final existing = result[key];
        result[key] = (
          productId: line.productId,
          name: name,
          quantity: (existing?.quantity ?? 0) + line.quantity * multiplier,
        );
      }
    }

    expand(kit, 1, <String>{});
    return result;
  }

  _KitBuildability _kitBuildability(KitRecord kit) {
    final requirements = _flattenKitRequirements(kit).values;
    if (requirements.isEmpty) {
      return const _KitBuildability(
        buildCount: 0,
        missingLineCount: 0,
        reservedQuantity: 0,
      );
    }
    var count = 1 << 30;
    var missing = 0;
    var reserved = 0.0;
    for (final requirement in requirements) {
      final raw = _availableInventoryQuantity(
        requirement.productId,
        requirement.name,
      );
      final held = _reservedInventoryQuantity(
        requirement.productId,
        requirement.name,
      );
      final available = math.max(0, raw - held);
      reserved += math.min(raw, held);
      if (available + .0001 < requirement.quantity) missing++;
      count = math.min(count, (available / requirement.quantity).floor());
    }
    return _KitBuildability(
      buildCount: count == 1 << 30 ? 0 : count,
      missingLineCount: missing,
      reservedQuantity: reserved,
    );
  }

  Future<void> _openBuildability() => showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final rows =
          [for (final kit in kits) (kit: kit, status: _kitBuildability(kit))]
            ..sort((left, right) {
              final byReady = right.status.buildCount.compareTo(
                left.status.buildCount,
              );
              return byReady != 0
                  ? byReady
                  : left.kit.name.compareTo(right.kit.name);
            });
      return AlertDialog(
        key: const Key('buildability-dialog'),
        title: const Row(
          children: [
            Icon(Icons.inventory_outlined),
            SizedBox(width: 10),
            Expanded(child: Text('What can I build?')),
          ],
        ),
        content: SizedBox(
          width: 680,
          height: math.min(620, 108.0 * rows.length + 40),
          child: rows.isEmpty
              ? const Center(
                  child: Text('Add a kit to calculate buildability.'),
                )
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final status = row.status;
                    return ListTile(
                      key: Key('buildability-${row.kit.id}'),
                      leading: CircleAvatar(
                        child: status.canBuild
                            ? const Icon(Icons.check_rounded)
                            : const _ShoppingCartIcon(),
                      ),
                      title: Text(row.kit.name),
                      subtitle: Text(
                        status.canBuild
                            ? 'Buildable ×${status.buildCount}${status.reservedQuantity > 0 ? ' · ${_formatBomQuantity(status.reservedQuantity)} reserved by active builds' : ''}'
                            : '${status.missingLineCount} shortage${status.missingLineCount == 1 ? '' : 's'}${status.reservedQuantity > 0 ? ' · ${_formatBomQuantity(status.reservedQuantity)} reserved' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        unawaited(_openKitDetails(row.kit));
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );

  KitRecord _matchKitBomLineToInventory(
    KitRecord source,
    int lineIndex,
    InventoryItem item,
  ) {
    if (!currentRole.canManageCatalog || lineIndex >= source.bom.length) {
      return source;
    }
    final previous = source.bom[lineIndex];
    final updatedLines = [...source.bom];
    updatedLines[lineIndex] = KitBomEntry(
      id: previous.id,
      productId: item.catalogProductId ?? item.id,
      quantity: previous.quantity,
      name: item.name,
      section: previous.section,
    );
    final updated = KitRecord(
      id: source.id,
      name: source.name,
      bom: List.unmodifiable(updatedLines),
      sections: source.sections,
      sourceUrls: source.sourceUrls,
      imageBytes: source.imageBytes,
    );
    setState(() {
      final index = kits.indexWhere((candidate) => candidate.id == source.id);
      if (index >= 0) kits[index] = updated;
      _recordAudit('edit', 'kit', source.id, {
        'name': source.name,
        'bomLine': previous.name ?? previous.productId,
        'matchedInventory': item.name,
        'matchedInventoryId': item.id,
      });
    });
    _persist();
    return updated;
  }

  void _addKitShortageToShoppingList(
    KitRecord kit,
    KitBomEntry line,
    double missing,
  ) {
    if (missing <= 0) return;
    final existingIndex = shoppingList.indexWhere(
      (entry) =>
          entry.kitId == kit.id &&
          entry.bomLineId == line.id &&
          entry.status != ShoppingListStatus.received,
    );
    final name = _kitLineName(line);
    setState(() {
      if (existingIndex >= 0) {
        final existing = shoppingList[existingIndex];
        shoppingList[existingIndex] = existing.copyWith(
          quantityNeeded: math.max(existing.quantityNeeded, missing),
        );
      } else {
        shoppingList.add(
          ShoppingListEntry(
            id: 'SHOP-${DateTime.now().microsecondsSinceEpoch}',
            name: name,
            productId: line.productId,
            quantityNeeded: missing,
            kitId: kit.id,
            bomLineId: line.id,
            sourceUrl: kit.sourceUrls.firstOrNull ?? '',
          ),
        );
      }
      _recordAudit('add', 'shopping', line.id, {
        'kit': kit.name,
        'item': name,
        'quantity': missing.toString(),
      });
    });
    _persist();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name added to the shopping list.')),
    );
  }

  void _createBuild(KitRecord kit) {
    if (!currentRole.canCreateBuilds) {
      _showPermissionDenied(
        'Your role can use shared builds but cannot create them.',
      );
      return;
    }
    final lines = <BuildLine>[];
    void expand(
      KitRecord source,
      String sectionPrefix,
      double multiplier,
      Set<String> path,
    ) {
      if (!path.add(source.id)) return;
      for (final line in source.bom) {
        final section = [sectionPrefix, line.section]
            .where((value) => value.isNotEmpty && value != 'Unassigned')
            .join(' / ');
        final nested = kits
            .where((candidate) => candidate.id == line.productId)
            .firstOrNull;
        if (nested != null) {
          expand(
            nested,
            section.isEmpty ? nested.name : section,
            multiplier * line.quantity,
            {...path},
          );
        } else {
          lines.add(
            BuildLine(
              id: 'BLDLINE-${DateTime.now().microsecondsSinceEpoch}-${lines.length}',
              productId: line.productId,
              name: _kitLineName(line),
              section: section.isEmpty ? 'Unassigned' : section,
              requiredQuantity: line.quantity * multiplier,
            ),
          );
        }
      }
    }

    expand(kit, '', 1, <String>{});
    final build = BuildRecord(
      id: 'BUILD-${DateTime.now().microsecondsSinceEpoch}',
      kitId: kit.id,
      name: '${kit.name} build',
      createdAt: DateTime.now(),
      createdBy: deviceName,
      ownerDeviceId: deviceId,
      ownerUserId: currentUserId,
      lines: lines,
    );
    setState(() {
      builds.insert(0, build);
      _recordAudit('create', 'build', build.id, {
        'kit': kit.name,
        'lines': lines.length.toString(),
      });
    });
    _persist();
    Navigator.of(context).pop();
    unawaited(_openBuildQueue(build, kit));
  }

  Future<void> _openBuildQueue(BuildRecord build, KitRecord kit) =>
      showDialog<void>(
        context: context,
        builder: (_) => BuildQueueDialog(
          build: build,
          kit: kit,
          kits: kits,
          products: products,
          availableQuantity: _availableInventoryQuantity,
          onAdjust: (lineId, use) => _adjustBuildInventory(build, lineId, use),
          canUse: currentRole.canOperateBuilds && _canOperateBuild(build),
          canShare:
              currentRole.canShareBuilds &&
              (_ownsBuild(build) || currentRole == WorkspaceRole.admin),
          onSharedChanged: (shared) => _setBuildShared(build, shared),
          onCompletedChanged: (completed) =>
              _setBuildCompleted(build, completed),
        ),
      );

  KitRecord _kitForBuild(BuildRecord build) =>
      kits.where((candidate) => candidate.id == build.kitId).firstOrNull ??
      KitRecord(
        id: build.kitId,
        name: build.name.replaceFirst(
          RegExp(r'\s+build$', caseSensitive: false),
          '',
        ),
        sections: build.lines.map((line) => line.section).toSet().toList(),
        bom: [
          for (final line in build.lines)
            KitBomEntry(
              id: line.id,
              productId: line.productId,
              quantity: line.requiredQuantity,
              name: line.name,
              section: line.section,
            ),
        ],
      );

  bool _ownsBuild(BuildRecord build) =>
      build.ownerDeviceId.isEmpty || build.ownerDeviceId == deviceId;

  bool _canViewBuild(BuildRecord build) =>
      build.shared || _ownsBuild(build) || currentRole == WorkspaceRole.admin;

  bool _canOperateBuild(BuildRecord build) =>
      build.shared || _ownsBuild(build) || currentRole == WorkspaceRole.admin;

  Future<bool> _setBuildShared(BuildRecord build, bool shared) async {
    if (!currentRole.canShareBuilds ||
        (!_ownsBuild(build) && currentRole != WorkspaceRole.admin)) {
      _showPermissionDenied('Only this build’s owner can change sharing.');
      return false;
    }
    setState(() {
      build.shared = shared;
      build.updatedAt = DateTime.now();
      _recordAudit(shared ? 'share' : 'unshare', 'build', build.id, {
        'shared': shared.toString(),
      });
    });
    _persist();
    return true;
  }

  Future<bool> _setBuildCompleted(BuildRecord build, bool completed) async {
    if (!currentRole.canOperateBuilds || !_canOperateBuild(build)) {
      _showPermissionDenied('This private build belongs to another device.');
      return false;
    }
    final allUsed = build.lines.every(
      (line) => line.usedQuantity >= line.requiredQuantity,
    );
    if (completed && !allUsed) {
      _showPermissionDenied(
        'Complete every component before closing the build.',
      );
      return false;
    }
    setState(() {
      build.completedAt = completed ? DateTime.now() : null;
      build.updatedAt = DateTime.now();
      _recordAudit(completed ? 'complete' : 'reopen', 'build', build.id, {});
    });
    _persist();
    return true;
  }

  Future<bool> _adjustBuildInventory(
    BuildRecord build,
    String lineId,
    bool use,
  ) async {
    if (!currentRole.canOperateBuilds || !_canOperateBuild(build)) {
      _showPermissionDenied('This private build belongs to another device.');
      return false;
    }
    if (build.completedAt != null) return false;
    final lineIndex = build.lines.indexWhere((line) => line.id == lineId);
    if (lineIndex < 0) return false;
    final line = build.lines[lineIndex];
    if (use && line.usedQuantity >= line.requiredQuantity) return false;
    if (!use && line.usedQuantity <= 0) return false;

    InventoryItem? item;
    if (use) {
      item = inventory
          .where(
            (candidate) =>
                !candidate.archived &&
                candidate.quantity > 0 &&
                (candidate.id == line.productId ||
                    candidate.catalogProductId == line.productId ||
                    _normalized(candidate.name) == _normalized(line.name)),
          )
          .firstOrNull;
      if (item == null) {
        _showPermissionDenied('No available inventory for ${line.name}.');
        return false;
      }
    } else {
      final consumedId = line.consumedInventoryIds.lastOrNull;
      item = inventory
          .where((candidate) => candidate.id == consumedId)
          .firstOrNull;
      if (item == null) return false;
    }

    final amount = use
        ? (line.requiredQuantity - line.usedQuantity).clamp(0, 1).toDouble()
        : line.usedQuantity.clamp(0, 1).toDouble();
    final consumed = [...line.consumedInventoryIds];
    if (use) {
      consumed.add(item.id);
    } else if (consumed.isNotEmpty) {
      consumed.removeLast();
    }
    setState(() {
      replaceInventoryItemById(
        inventory,
        item!.id,
        item.copyWith(quantity: item.quantity + (use ? -amount : amount)),
      );
      build.lines[lineIndex] = line.copyWith(
        usedQuantity: line.usedQuantity + (use ? amount : -amount),
        consumedInventoryIds: consumed,
      );
      build.updatedAt = DateTime.now();
      _recordAudit(use ? 'use' : 'unuse', 'build', build.id, {
        'line': line.name,
        'inventoryId': item.id,
        'quantity': amount.toString(),
      });
    });
    _persist();
    return true;
  }

  Future<void> _showKitContextMenu(KitRecord kit, Offset position) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      items: [
        const PopupMenuItem(
          value: 'edit',
          height: 52,
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: _PopupActionRow(
            actionKey: 'edit-kit',
            icon: Icons.edit_outlined,
            label: 'Edit kit / BOM',
          ),
        ),
        if (currentRole.canHardDeleteItems)
          const PopupMenuItem(
            value: 'delete',
            height: 52,
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: _PopupActionRow(
              actionKey: 'delete-kit',
              icon: Icons.delete_outline_rounded,
              label: 'Delete kit',
              destructive: true,
            ),
          ),
      ],
    );
    if (action == 'edit' && mounted) await _openKitEditor(kit);
    if (action == 'delete' && mounted) await _confirmDeleteKit(kit);
  }

  Future<bool> _confirmDeleteKit(KitRecord kit) async {
    final unfinishedBuilds = builds
        .where((build) => build.kitId == kit.id && build.completedAt == null)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${kit.name}?'),
        content: Text(
          unfinishedBuilds > 0
              ? 'You have $unfinishedBuilds ${unfinishedBuilds == 1 ? 'build' : 'builds'} in progress.'
              : 'This permanently deletes the kit and its BOM.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete-kit'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete Kit (permanent)'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    setState(() {
      kits.removeWhere((candidate) => candidate.id == kit.id);
      for (final machine in machines) {
        machine.kitIds.remove(kit.id);
      }
      _recordAudit('delete', 'kit', kit.id, {
        'name': kit.name,
        'unfinishedBuilds': unfinishedBuilds.toString(),
      });
    });
    _persist();
    return true;
  }

  Future<void> _openScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryQrScanner(
          onCode: (code, mode, imageBytes) =>
              unawaited(_handleScannedCode(code, mode, imageBytes)),
          onLabelCapture: _ingestCapturedLabel,
        ),
      ),
    );
  }

  List<InventoryItem> get _moistureAlerts =>
      inventory.where((item) {
        if (item.archived ||
            item.type != InventoryType.filament ||
            !item.moistureAlertEnabled ||
            item.moistureAlertThresholdMinutes == null) {
          return false;
        }
        final remaining = _moistureRemaining(item);
        return remaining != null &&
            remaining <= Duration(minutes: item.moistureAlertThresholdMinutes!);
      }).toList()..sort((a, b) {
        final left = _moistureRemaining(a) ?? Duration.zero;
        final right = _moistureRemaining(b) ?? Duration.zero;
        return left.compareTo(right);
      });

  List<InventoryItem> get _quantityAlerts =>
      inventory
          .where(
            (item) =>
                !item.archived &&
                item.quantityAlertThreshold != null &&
                item.quantity <= item.quantityAlertThreshold!,
          )
          .toList()
        ..sort((a, b) => a.quantity.compareTo(b.quantity));

  String _quantityAlertKey(InventoryItem item) =>
      'quantity:${item.id}:${item.quantityAlertThreshold}';

  String _moistureAlertKey(InventoryItem item) =>
      'moisture:${item.id}:${item.lastDriedAt?.toIso8601String()}:${item.moistureAlertThresholdMinutes}';

  List<InventoryItem> get _unreadQuantityAlerts => _quantityAlerts
      .where(
        (item) => !_readInventoryAlertKeys.contains(_quantityAlertKey(item)),
      )
      .toList();

  List<InventoryItem> get _unreadMoistureAlerts => _moistureAlerts
      .where(
        (item) => !_readInventoryAlertKeys.contains(_moistureAlertKey(item)),
      )
      .toList();

  Set<String> get _activeInventoryAlertKeys => {
    ..._quantityAlerts.map(_quantityAlertKey),
    ..._moistureAlerts.map(_moistureAlertKey),
  };

  void _saveReadInventoryAlerts() {
    widget.database?.saveStringPreference(
      'read_inventory_alert_keys',
      jsonEncode(_readInventoryAlertKeys.toList()),
    );
  }

  void _reconcileReadInventoryAlerts() {
    final activeKeys = _activeInventoryAlertKeys;
    final previousLength = _readInventoryAlertKeys.length;
    _readInventoryAlertKeys.removeWhere((key) => !activeKeys.contains(key));
    if (_readInventoryAlertKeys.length != previousLength) {
      _saveReadInventoryAlerts();
    }
  }

  void _markInventoryAlertRead(String key) {
    if (!_readInventoryAlertKeys.add(key)) return;
    setState(() {});
    _saveReadInventoryAlerts();
  }

  void _markAllInventoryAlertsRead() {
    final keys = _activeInventoryAlertKeys;
    if (keys.every(_readInventoryAlertKeys.contains)) return;
    setState(() => _readInventoryAlertKeys.addAll(keys));
    _saveReadInventoryAlerts();
  }

  int get _inventoryAlertCount => {
    ..._unreadMoistureAlerts.map((item) => item.id),
    ..._unreadQuantityAlerts.map((item) => item.id),
  }.length;

  Future<void> _openDebugPanel() async {
    final result = await showDialog<({String itemId, DebugCardEffect effect})>(
      context: context,
      builder: (_) => DebugPanelDialog(items: visibleItems),
    );
    if (result == null || !mounted) return;
    setState(() {
      final versions = switch (result.effect) {
        DebugCardEffect.remoteQuantity => _remoteQuantityAnimationVersions,
        DebugCardEffect.lowStock => _lowStockAnimationVersions,
        DebugCardEffect.moistureThreshold => _moistureAnimationVersions,
      };
      versions[result.itemId] = (versions[result.itemId] ?? 0) + 1;
    });
  }

  Future<void> _openAnimationControls() => showDialog<void>(
    context: context,
    builder: (_) => PersonalizationSettingsDialog(
      animationDurationPercent: animationDurationPercent,
      animationRecurrenceSeconds: animationRecurrenceSeconds,
      photoCardsEnabled: photoCardsEnabled,
      customIconAnimationMode: customIconAnimationMode,
      colorTheme: widget.colorTheme,
      brightnessMode: widget.brightnessMode,
      customThemeColor: widget.customThemeColor,
      onSettingsChanged: _updateAnimationSettings,
      onColorThemeChanged: widget.onColorThemeChanged ?? (_) {},
      onBrightnessModeChanged: widget.onBrightnessModeChanged ?? (_) {},
      onCustomThemeColorChanged: widget.onCustomThemeColorChanged ?? (_) {},
      onPhotoCardsChanged: (value) {
        setState(() => photoCardsEnabled = value);
        widget.database?.saveBoolPreference('photo_cards_enabled', value);
      },
      onCustomIconAnimationModeChanged: (value) {
        setState(() => customIconAnimationMode = value);
        widget.database?.saveStringPreference(
          'custom_icon_animation_mode',
          value.name,
        );
      },
    ),
  );

  void _updateAnimationSettings(int durationPercent, int recurrenceSeconds) {
    setState(() {
      animationDurationPercent = durationPercent;
      animationRecurrenceSeconds = recurrenceSeconds;
    });
    widget.database?.saveStringPreference(
      'animation_duration_percent',
      '$durationPercent',
    );
    widget.database?.saveStringPreference(
      'animation_recurrence_seconds',
      '$recurrenceSeconds',
    );
  }

  Future<void> _openMoistureAlerts() => showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final moistureAlerts = _unreadMoistureAlerts;
        final quantityAlerts = _unreadQuantityAlerts;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.notifications_outlined),
              SizedBox(width: 10),
              Text('Inventory alerts'),
            ],
          ),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(
              children: [
                SwitchListTile(
                  key: const Key('drying-complete-chime-toggle'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Drying-complete chime'),
                  subtitle: const Text(
                    'This setting applies only to this device.',
                  ),
                  value: dryingCompleteChimeEnabled,
                  onChanged: (value) {
                    setState(() => dryingCompleteChimeEnabled = value);
                    setDialogState(() {});
                    widget.database?.saveBoolPreference(
                      'drying_complete_chime_enabled',
                      value,
                    );
                  },
                ),
                SwitchListTile(
                  key: const Key('moisture-alert-chime-toggle'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Moisture-threshold chime'),
                  subtitle: const Text(
                    'Plays once per filament and drying cycle.',
                  ),
                  value: moistureAlertChimeEnabled,
                  onChanged: (value) {
                    setState(() => moistureAlertChimeEnabled = value);
                    setDialogState(() {});
                    widget.database?.saveBoolPreference(
                      'moisture_alert_chime_enabled',
                      value,
                    );
                  },
                ),
                const Divider(),
                Expanded(
                  child: moistureAlerts.isEmpty && quantityAlerts.isEmpty
                      ? const Center(child: Text('No unread inventory alerts.'))
                      : ListView(
                          children: [
                            if (quantityAlerts.isNotEmpty) ...[
                              const ListTile(
                                dense: true,
                                title: Text(
                                  'LOW STOCK',
                                  style: TextStyle(
                                    color: Color(0xffffa552),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              ...quantityAlerts.map(
                                (item) => ListTile(
                                  key: Key('quantity-alert-${item.id}'),
                                  leading: const Icon(
                                    Icons.inventory_2_outlined,
                                    color: Color(0xffffa552),
                                  ),
                                  title: Text(item.name),
                                  subtitle: Text(
                                    '${_formatBomQuantity(item.quantity)} remaining · alert at ${_formatBomQuantity(item.quantityAlertThreshold!)}',
                                  ),
                                  onTap: () {
                                    _markInventoryAlertRead(
                                      _quantityAlertKey(item),
                                    );
                                    Navigator.pop(dialogContext);
                                    _openDetails(item);
                                  },
                                ),
                              ),
                            ],
                            if (moistureAlerts.isNotEmpty) ...[
                              const ListTile(
                                dense: true,
                                title: Text(
                                  'MOISTURE',
                                  style: TextStyle(
                                    color: Color(0xff9c83ff),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              ...moistureAlerts.map((item) {
                                final remaining = _moistureRemaining(item)!;
                                return ListTile(
                                  key: Key('moisture-alert-${item.id}'),
                                  leading: Icon(
                                    Icons.water_drop_rounded,
                                    color: remaining <= Duration.zero
                                        ? const Color(0xffff6b6b)
                                        : const Color(0xffffa552),
                                  ),
                                  title: Text(item.name),
                                  subtitle: Text(_moistureRemainingLabel(item)),
                                  onTap: () {
                                    _markInventoryAlertRead(
                                      _moistureAlertKey(item),
                                    );
                                    Navigator.pop(dialogContext);
                                    _openDetails(item);
                                  },
                                );
                              }),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              key: const Key('mark-all-alerts-read'),
              onPressed: moistureAlerts.isEmpty && quantityAlerts.isEmpty
                  ? null
                  : () {
                      _markAllInventoryAlertsRead();
                      setDialogState(() {});
                    },
              icon: const Icon(Icons.done_all_rounded),
              label: const Text('Mark all as read'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _openAdditionHistory() => showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.new_releases_outlined),
            SizedBox(width: 10),
            Text('New items'),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 520,
          child: Column(
            children: [
              Row(
                children: [
                  Text('${additionHistory.length} additions preserved'),
                  const Spacer(),
                  const Text('Keep'),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    key: const Key('history-limit'),
                    value: historyLimit,
                    items: const [20, 50, 100, 500, 2000]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        historyLimit = value;
                        _trimAdditionHistory();
                      });
                      setDialogState(() {});
                      _persist();
                    },
                  ),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.devices_outlined),
                title: const Text('This device'),
                subtitle: Text(deviceName),
                trailing: IconButton(
                  key: const Key('rename-device'),
                  tooltip: 'Rename this device',
                  onPressed: () async {
                    if (await _renameThisDevice()) setDialogState(() {});
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
              SwitchListTile(
                key: const Key('sync-chime-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Chime for remotely added items'),
                subtitle: const Text(
                  'This setting applies only to this device.',
                ),
                value: syncChimeEnabled,
                onChanged: (value) {
                  setState(() => syncChimeEnabled = value);
                  setDialogState(() {});
                  widget.database?.saveBoolPreference(
                    'sync_chime_enabled',
                    value,
                  );
                },
              ),
              const Divider(),
              Expanded(
                child: additionHistory.isEmpty
                    ? const Center(child: Text('No additions recorded yet.'))
                    : ListView.separated(
                        itemCount: additionHistory.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = additionHistory[index];
                          final local = entry.addedAt.toLocal();
                          final when =
                              '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
                              '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
                          return ListTile(
                            leading: const Icon(Icons.add_circle_outline),
                            title: Text(entry.name),
                            subtitle: Text(
                              '${_inventoryTypeDisplayLabel(entry.type)} · ${entry.deviceName} · $when',
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );

  Future<bool> _renameThisDevice() async {
    final name = await showDeviceNameDialog(
      context,
      initialName: deviceName,
      explainAndroidRestriction: Platform.isAndroid,
    );
    final cleaned = name?.trim();
    if (cleaned == null || cleaned.isEmpty || !mounted) return false;
    setState(() => deviceName = cleaned);
    widget.database?.saveStringPreference('device_name', cleaned);
    widget.database?.saveBoolPreference('device_name_confirmed', true);
    return true;
  }

  void _persist() {
    _reconcileReadInventoryAlerts();
    _invalidateSearchCaches();
    _synchronizeInventoryNotifiers();
    final database = widget.database;
    if (database != null) {
      if (_incrementalPersistenceReady) {
        _persistChangedEntities(database);
      } else {
        final previous = database.loadState();
        final current = _currentStateJson();
        database.saveStateAndQueueChanges(
          current,
          diffWorkshopStates(previous, current),
        );
      }
    }
    if (!_applyingCloudState) {
      _localStateRevision++;
      _scheduleAutomaticSync();
    }
  }

  Map<String, List<Object>> _entityCollections() => {
    'inventory': inventory,
    'customItemTypes': customItemTypes,
    'machineTypes': machineTypes,
    'machines': machines,
    'kits': kits,
    'builds': builds,
    'locations': locations,
    'shoppingList': shoppingList,
    'auditLog': auditLog,
    'vendors': vendors,
    'brands': brands,
    'spoolTypes': spoolTypes,
    'materials': materials,
    'products': products,
    'additionHistory': additionHistory,
  };

  String _entityId(Object record) => switch (record) {
    InventoryItem value => value.id,
    CustomItemTypeRecord value => value.id,
    MachineTypeRecord value => value.id,
    MachineRecord value => value.id,
    KitRecord value => value.id,
    BuildRecord value => value.id,
    StockLocationRecord value => value.id,
    ShoppingListEntry value => value.id,
    AuditEntry value => value.id,
    VendorRecord value => value.id,
    BrandRecord value => value.id,
    SpoolTypeRecord value => value.id,
    MaterialRecord value => value.id,
    CatalogProduct value => value.id,
    AdditionHistoryEntry value => value.id,
    _ => throw ArgumentError.value(record, 'record', 'Unknown entity type'),
  };

  Map<String, dynamic> _workshopMetadata() => {
    'schemaVersion': 8,
    'typeLabelOverrides': typeLabelOverrides,
    'typeIconOverrides': typeIconOverrides,
    'typeDepletionSettings': typeDepletionSettings,
    'typeStatusSettings': typeStatusSettings,
    'deletedTypeKeys': deletedTypeKeys.toList(),
    'historyLimit': historyLimit,
  };

  void _capturePersistedEntityReferences() {
    _persistedEntityReferences
      ..clear()
      ..addEntries(
        _entityCollections().entries.map(
          (entry) => MapEntry(entry.key, {
            for (final record in entry.value) _entityId(record): record,
          }),
        ),
      );
    _persistedMetadata = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(_workshopMetadata())) as Map,
    );
  }

  void _persistChangedEntities(LocalDatabase database) {
    for (final collection in _entityCollections().entries) {
      final previous = _persistedEntityReferences[collection.key] ?? const {};
      final current = <String, Object>{
        for (final record in collection.value) _entityId(record): record,
      };
      for (final entry in current.entries) {
        if (identical(previous[entry.key], entry.value)) continue;
        if (collection.key == 'inventory') {
          _saveInventoryEntity(
            database,
            entry.value as InventoryItem,
            previous: previous[entry.key] as InventoryItem?,
          );
        } else {
          database.saveEntityPayloadAndQueue(
            collection.key,
            entry.key,
            encodeWorkshopEntityPayload(collection.key, entry.value),
          );
        }
      }
      for (final removedId in previous.keys.where(
        (id) => !current.containsKey(id),
      )) {
        database.deleteEntityAndQueue(collection.key, removedId);
      }
      _persistedEntityReferences[collection.key] = current;
    }
    final metadata = _workshopMetadata();
    if (jsonEncode(metadata) != jsonEncode(_persistedMetadata)) {
      database.saveEntityPayloadAndQueue(
        workshopMetadataEntityType,
        workshopMetadataEntityId,
        metadata,
      );
      _persistedMetadata = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(metadata)) as Map,
      );
    }
  }

  Map<String, dynamic> _changedInventoryFields(
    InventoryItem? previous,
    InventoryItem current,
  ) {
    if (previous == null) return _inventoryItemJson(current);
    final fields = changedWorkshopEntityFields(
      _inventoryItemJson(previous, includeBinary: false),
      _inventoryItemJson(current, includeBinary: false),
    );
    if (!listEquals(previous.imageBytes, current.imageBytes)) {
      fields['image'] = _bytesToJson(current.imageBytes);
    }
    if (!listEquals(previous.thumbnailBytes, current.thumbnailBytes)) {
      fields['thumbnail'] = _bytesToJson(current.thumbnailBytes);
    }
    if (!listEquals(previous.labelImageBytes, current.labelImageBytes)) {
      fields['labelImage'] = _bytesToJson(current.labelImageBytes);
    }
    return fields;
  }

  void _saveInventoryEntity(
    LocalDatabase database,
    InventoryItem item, {
    InventoryItem? previous,
  }) {
    final fields = _changedInventoryFields(previous, item);
    if (fields.isEmpty) return;
    database.applyAndQueueWorkshopChanges([
      WorkshopEntityChange(
        entityType: 'inventory',
        entityId: item.id,
        fields: fields,
      ),
    ]);
  }

  void _persistInventoryItem(InventoryItem item) {
    _reconcileReadInventoryAlerts();
    _invalidateSearchCaches();
    final database = widget.database;
    if (database != null) {
      _saveInventoryEntity(
        database,
        item,
        previous:
            _persistedEntityReferences['inventory']?[item.id] as InventoryItem?,
      );
    }
    _persistedEntityReferences.putIfAbsent('inventory', () => {})[item.id] =
        item;
    if (!_applyingCloudState) {
      _localStateRevision++;
      _scheduleAutomaticSync();
    }
  }

  Future<void> _backfillInventoryThumbnails() async {
    if (_thumbnailBackfillRunning || widget.database == null) return;
    _thumbnailBackfillRunning = true;
    var changed = false;
    try {
      final idsWithImages = widget.database!.inventoryIdsWithFullImages();
      final candidates = inventory
          .where(
            (item) =>
                item.thumbnailBytes == null && idsWithImages.contains(item.id),
          )
          .map((item) => item.id)
          .toList();
      for (final id in candidates) {
        if (!mounted) return;
        final current = inventory.where((item) => item.id == id).firstOrNull;
        final source =
            current?.imageBytes ??
            widget.database!.loadInventoryImages(id).imageBytes;
        if (current == null ||
            source == null ||
            current.thumbnailBytes != null) {
          continue;
        }
        final thumbnail = await compute(_createCardThumbnail, source);
        if (thumbnail == null || !mounted) continue;
        while (mounted && _inventoryIsScrolling.value) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (!mounted) return;
        final latest = inventory.where((item) => item.id == id).firstOrNull;
        final latestSource =
            latest?.imageBytes ??
            widget.database!.loadInventoryImages(id).imageBytes;
        if (latest == null || !listEquals(latestSource, source)) continue;
        final updated = latest.copyWith(thumbnailBytes: thumbnail);
        _publishInventoryItem(updated);
        _saveInventoryEntity(widget.database!, updated, previous: latest);
        _persistedEntityReferences.putIfAbsent(
          'inventory',
          () => {},
        )[updated.id] = updated;
        changed = true;
      }
    } finally {
      _thumbnailBackfillRunning = false;
    }
    if (changed && mounted) {
      _localStateRevision++;
      _scheduleAutomaticSync();
    }
  }

  void _scheduleAutomaticSync({
    Duration delay = const Duration(milliseconds: 700),
  }) {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(delay, _syncAutomatically);
  }

  List<Map<String, Object?>> _pendingAuditBatch() => [..._pendingAuditEvents];

  void _acknowledgeAuditBatch(List<Map<String, Object?>> sent) {
    var acknowledged = 0;
    while (acknowledged < sent.length &&
        acknowledged < _pendingAuditEvents.length &&
        identical(_pendingAuditEvents[acknowledged], sent[acknowledged])) {
      acknowledged++;
    }
    if (acknowledged > 0) {
      _pendingAuditEvents.removeRange(0, acknowledged);
    }
  }

  String _currentStateJson() => encodeWorkshopState(
    inventory: inventory,
    vendors: vendors,
    brands: brands,
    spoolTypes: spoolTypes,
    materials: materials,
    customItemTypes: customItemTypes,
    typeLabelOverrides: typeLabelOverrides,
    typeIconOverrides: typeIconOverrides,
    typeDepletionSettings: typeDepletionSettings,
    typeStatusSettings: typeStatusSettings,
    deletedTypeKeys: deletedTypeKeys,
    products: products,
    machineTypes: machineTypes,
    machines: machines,
    kits: kits,
    builds: builds,
    locations: locations,
    shoppingList: shoppingList,
    auditLog: auditLog,
    additionHistory: additionHistory,
    historyLimit: historyLimit,
  );

  bool _initializeLegacyLocations() {
    var changed = false;
    final byName = <String, StockLocationRecord>{
      for (final location in locations)
        location.name.trim().toLowerCase(): location,
    };
    for (var index = 0; index < inventory.length; index++) {
      final item = inventory[index];
      final name = item.storageLocation.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      final location = byName.putIfAbsent(key, () {
        final created = StockLocationRecord(
          id: 'LOC-${base64UrlEncode(utf8.encode(key)).replaceAll('=', '')}',
          name: name,
        );
        locations.add(created);
        changed = true;
        return created;
      });
      if (item.storageLocationId.isEmpty) {
        inventory[index] = item.copyWith(storageLocationId: location.id);
        changed = true;
      }
    }
    return changed;
  }

  void _recordAddition(InventoryItem item) {
    additionHistory.removeWhere((entry) => entry.itemId == item.id);
    additionHistory.add(
      AdditionHistoryEntry.fromItem(item, deviceName: deviceName),
    );
    _trimAdditionHistory();
  }

  void _recordAudit(
    String action,
    String entityType,
    String entityId,
    Map<String, String> changes,
  ) {
    final entry = AuditEntry(
      id: 'AUD-${DateTime.now().microsecondsSinceEpoch}',
      timestamp: DateTime.now(),
      actor: deviceName,
      action: action,
      entityType: entityType,
      entityId: entityId,
      changes: changes,
    );
    auditLog.insert(0, entry);
    if (auditLog.length > 2000) auditLog.removeRange(2000, auditLog.length);
    widget.database?.saveEntityPayloadAndQueue('auditLog', entry.id, {
      'id': entry.id,
      'timestamp': entry.timestamp.toIso8601String(),
      'actor': entry.actor,
      'action': entry.action,
      'entityType': entry.entityType,
      'entityId': entry.entityId,
      'changes': entry.changes,
    });
    _pendingAuditEvents.add({
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'changes': changes,
    });
  }

  void _trimAdditionHistory() {
    additionHistory.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    if (additionHistory.length > historyLimit) {
      additionHistory.removeRange(historyLimit, additionHistory.length);
    }
  }

  void _applyCloudState(String source) {
    final restored = decodeWorkshopState(source);
    if (restored == null) {
      throw const FormatException('The remote inventory could not be read.');
    }
    _applyingCloudState = true;
    var initializedKitSections = false;
    setState(() {
      inventory
        ..clear()
        ..addAll(restored.inventory);
      selectedInventoryIds.retainAll(inventory.map((item) => item.id).toSet());
      _initializeDryingTimers();
      vendors
        ..clear()
        ..addAll(restored.vendors);
      brands
        ..clear()
        ..addAll(restored.brands);
      spoolTypes
        ..clear()
        ..addAll(restored.spoolTypes);
      materials
        ..clear()
        ..addAll(restored.materials);
      customItemTypes
        ..clear()
        ..addAll(restored.customItemTypes);
      typeLabelOverrides
        ..clear()
        ..addAll(restored.typeLabelOverrides);
      typeIconOverrides
        ..clear()
        ..addAll(restored.typeIconOverrides);
      typeDepletionSettings
        ..clear()
        ..addAll(restored.typeDepletionSettings);
      typeStatusSettings
        ..clear()
        ..addAll(restored.typeStatusSettings);
      deletedTypeKeys
        ..clear()
        ..addAll(restored.deletedTypeKeys);
      products
        ..clear()
        ..addAll(restored.products);
      machineTypes
        ..clear()
        ..addAll(restored.machineTypes);
      machines
        ..clear()
        ..addAll(restored.machines);
      selectedMachineIds.retainAll(
        machines.map((machine) => machine.id).toSet(),
      );
      kits
        ..clear()
        ..addAll(restored.kits);
      selectedKitIds.retainAll(kits.map((kit) => kit.id).toSet());
      initializedKitSections = _initializeKitSections();
      builds
        ..clear()
        ..addAll(restored.builds);
      locations
        ..clear()
        ..addAll(restored.locations);
      shoppingList
        ..clear()
        ..addAll(restored.shoppingList);
      _initializeLegacyLocations();
      selectedBuildIds.retainAll(builds.map((build) => build.id).toSet());
      auditLog
        ..clear()
        ..addAll(restored.auditLog);
      additionHistory
        ..clear()
        ..addAll(restored.additionHistory);
      historyLimit = restored.historyLimit;
      _trimAdditionHistory();
    });
    _persist();
    _applyingCloudState = false;
    if (initializedKitSections) unawaited(_syncAutomatically());
  }

  void _applyRemoteCloudState(String source) {
    final before = jsonDecode(_currentStateJson()) as Map<String, dynamic>;
    final after = jsonDecode(source) as Map<String, dynamic>;
    final incoming = decodeWorkshopState(source);
    final quantityChanges = incoming == null
        ? const <String>{}
        : remoteQuantityChangedItemIds(inventory, incoming.inventory);
    final lowStockEntries = incoming == null
        ? const <String>{}
        : lowStockEnteredItemIds(inventory, incoming.inventory);
    final inventoryChanged = !_sameJson(
      before['inventory'],
      after['inventory'],
    );
    _applyCloudState(source);
    if ((quantityChanges.isNotEmpty || lowStockEntries.isNotEmpty) && mounted) {
      setState(() {
        for (final id in quantityChanges) {
          _remoteQuantityAnimationVersions[id] =
              (_remoteQuantityAnimationVersions[id] ?? 0) + 1;
        }
        for (final id in lowStockEntries) {
          _lowStockAnimationVersions[id] =
              (_lowStockAnimationVersions[id] ?? 0) + 1;
        }
      });
    }
    _checkMoistureThresholdAnimations();
    if (inventoryChanged) unawaited(_playSyncChime());
  }

  void _applyRemoteEntityChanges(List<WorkshopEntityChange> changes) {
    var rebuildRoot = false;
    var inventoryChanged = false;

    T? decodedEntity<T>(
      WorkshopEntityChange change,
      T? Function(WorkshopState) pick,
    ) {
      if (change.deleted) return null;
      final root = <String, dynamic>{
        'schemaVersion': 8,
        'historyLimit': historyLimit,
        for (final type in workshopEntityCollections) type: <Object?>[],
      };
      root[change.entityType] = [
        {'id': change.entityId, ...change.fields},
      ];
      final decoded = decodeWorkshopState(jsonEncode(root));
      return decoded == null ? null : pick(decoded);
    }

    void replaceById<T>(
      List<T> target,
      String id,
      T value,
      String Function(T) idOf,
    ) {
      final index = target.indexWhere((entry) => idOf(entry) == id);
      if (index < 0) {
        target.add(value);
      } else {
        target[index] = value;
      }
    }

    void rememberAppliedChange(WorkshopEntityChange change) {
      if (change.entityType == workshopMetadataEntityType) {
        _persistedMetadata = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(_workshopMetadata())) as Map,
        );
        return;
      }
      final references = _persistedEntityReferences.putIfAbsent(
        change.entityType,
        () => {},
      );
      if (change.deleted) {
        references.remove(change.entityId);
        return;
      }
      final record = _entityCollections()[change.entityType]
          ?.where((entry) => _entityId(entry) == change.entityId)
          .firstOrNull;
      if (record != null) references[change.entityId] = record;
    }

    for (final change in changes) {
      if (change.entityType == workshopMetadataEntityType) {
        final fields = change.fields;
        if (fields['historyLimit'] is num) {
          historyLimit = (fields['historyLimit'] as num).toInt();
        }
        if (fields['typeLabelOverrides'] is Map) {
          typeLabelOverrides
            ..clear()
            ..addAll(
              Map<String, dynamic>.from(fields['typeLabelOverrides'] as Map)
                  .map((key, value) => MapEntry(key, value.toString())),
            );
        }
        if (fields['typeIconOverrides'] is Map) {
          typeIconOverrides
            ..clear()
            ..addAll(
              Map<String, dynamic>.from(fields['typeIconOverrides'] as Map)
                  .map((key, value) => MapEntry(key, value.toString())),
            );
        }
        if (fields['typeDepletionSettings'] is Map) {
          typeDepletionSettings
            ..clear()
            ..addAll(
              Map<String, dynamic>.from(fields['typeDepletionSettings'] as Map)
                  .map((key, value) => MapEntry(key, value == true)),
            );
        }
        if (fields['typeStatusSettings'] is Map) {
          typeStatusSettings
            ..clear()
            ..addAll(
              Map<String, dynamic>.from(fields['typeStatusSettings'] as Map)
                  .map((key, value) => MapEntry(key, value == true)),
            );
        }
        if (fields['deletedTypeKeys'] is List) {
          deletedTypeKeys
            ..clear()
            ..addAll((fields['deletedTypeKeys'] as List).cast<String>());
        }
        rebuildRoot = true;
        rememberAppliedChange(change);
        continue;
      }

      if (change.entityType == 'inventory') {
        inventoryChanged = true;
        final index = inventory.indexWhere(
          (item) => item.id == change.entityId,
        );
        if (change.deleted) {
          if (index >= 0) inventory.removeAt(index);
          _inventoryItemNotifiers.remove(change.entityId)?.dispose();
          rebuildRoot = true;
          rememberAppliedChange(change);
          continue;
        }
        final item = decodedEntity<InventoryItem>(
          change,
          (state) => state.inventory.singleOrNull,
        );
        if (item == null) continue;
        final lightweightItem = _withoutFullInventoryImages(item);
        if (index < 0) {
          _addInventoryItem(lightweightItem);
          rebuildRoot = true;
        } else {
          final previous = inventory[index];
          _publishInventoryItem(lightweightItem);
          if (previous.name != lightweightItem.name ||
              previous.type != lightweightItem.type ||
              previous.archived != lightweightItem.archived ||
              previous.itemColorName != lightweightItem.itemColorName ||
              sort == InventorySort.quantity &&
                  previous.quantity != lightweightItem.quantity ||
              hideZeroQuantityItems &&
                  (previous.quantity == 0) != (lightweightItem.quantity == 0)) {
            rebuildRoot = true;
          }
        }
        rememberAppliedChange(change);
        continue;
      }

      rebuildRoot = true;
      switch (change.entityType) {
        case 'vendors':
          if (change.deleted) {
            vendors.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<VendorRecord>(
              change,
              (s) => s.vendors.singleOrNull,
            );
            if (value != null) {
              replaceById(vendors, change.entityId, value, (e) => e.id);
            }
          }
        case 'brands':
          if (change.deleted) {
            brands.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<BrandRecord>(
              change,
              (s) => s.brands.singleOrNull,
            );
            if (value != null) {
              replaceById(brands, change.entityId, value, (e) => e.id);
            }
          }
        case 'spoolTypes':
          if (change.deleted) {
            spoolTypes.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<SpoolTypeRecord>(
              change,
              (s) => s.spoolTypes
                  .where((e) => e.id == change.entityId)
                  .firstOrNull,
            );
            if (value != null) {
              replaceById(spoolTypes, change.entityId, value, (e) => e.id);
            }
          }
        case 'materials':
          if (change.deleted) {
            materials.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<MaterialRecord>(
              change,
              (s) =>
                  s.materials.where((e) => e.id == change.entityId).firstOrNull,
            );
            if (value != null) {
              replaceById(materials, change.entityId, value, (e) => e.id);
            }
          }
        case 'customItemTypes':
          if (change.deleted) {
            customItemTypes.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<CustomItemTypeRecord>(
              change,
              (s) => s.customItemTypes.singleOrNull,
            );
            if (value != null) {
              replaceById(customItemTypes, change.entityId, value, (e) => e.id);
            }
          }
        case 'products':
          if (change.deleted) {
            products.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<CatalogProduct>(
              change,
              (s) => s.products.singleOrNull,
            );
            if (value != null) {
              replaceById(products, change.entityId, value, (e) => e.id);
            }
          }
        case 'machineTypes':
          if (change.deleted) {
            machineTypes.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<MachineTypeRecord>(
              change,
              (s) => s.machineTypes.singleOrNull,
            );
            if (value != null) {
              replaceById(machineTypes, change.entityId, value, (e) => e.id);
            }
          }
        case 'machines':
          if (change.deleted) {
            machines.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<MachineRecord>(
              change,
              (s) => s.machines.singleOrNull,
            );
            if (value != null) {
              replaceById(machines, change.entityId, value, (e) => e.id);
            }
          }
        case 'kits':
          if (change.deleted) {
            kits.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<KitRecord>(
              change,
              (s) => s.kits.singleOrNull,
            );
            if (value != null) {
              replaceById(kits, change.entityId, value, (e) => e.id);
            }
          }
        case 'builds':
          if (change.deleted) {
            builds.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<BuildRecord>(
              change,
              (s) => s.builds.singleOrNull,
            );
            if (value != null) {
              replaceById(builds, change.entityId, value, (e) => e.id);
            }
          }
        case 'locations':
          if (change.deleted) {
            locations.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<StockLocationRecord>(
              change,
              (s) => s.locations.singleOrNull,
            );
            if (value != null) {
              replaceById(locations, change.entityId, value, (e) => e.id);
            }
          }
        case 'shoppingList':
          if (change.deleted) {
            shoppingList.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<ShoppingListEntry>(
              change,
              (s) => s.shoppingList.singleOrNull,
            );
            if (value != null) {
              replaceById(shoppingList, change.entityId, value, (e) => e.id);
            }
          }
        case 'auditLog':
          if (change.deleted) {
            auditLog.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<AuditEntry>(
              change,
              (s) => s.auditLog.singleOrNull,
            );
            if (value != null) {
              replaceById(auditLog, change.entityId, value, (e) => e.id);
            }
          }
        case 'additionHistory':
          if (change.deleted) {
            additionHistory.removeWhere((entry) => entry.id == change.entityId);
          } else {
            final value = decodedEntity<AdditionHistoryEntry>(
              change,
              (s) => s.additionHistory.singleOrNull,
            );
            if (value != null) {
              replaceById(additionHistory, change.entityId, value, (e) => e.id);
            }
          }
      }
      rememberAppliedChange(change);
    }

    _invalidateSearchCaches();
    if (rebuildRoot && mounted) setState(() {});
    if (inventoryChanged) unawaited(_playSyncChime());
  }

  Future<void> _playSyncChime() async {
    if (!syncChimeEnabled) return;
    try {
      if (Platform.isAndroid || Platform.isWindows) {
        await _audioChannel.invokeMethod<void>('playSyncChime');
        return;
      }
      if (Platform.isLinux) {
        final executableDirectory = File(Platform.resolvedExecutable)
            .parent
            .path;
        final sound =
            '$executableDirectory/data/flutter_assets/assets/audio/transhuman_sync.wav';
        final result = await Process.run('/usr/bin/paplay', [sound]);
        if (result.exitCode == 0) return;
      }
      await SystemSound.play(SystemSoundType.alert);
    } catch (error) {
      debugPrint('Could not play sync chime: $error');
    }
  }

  Future<void> _playDryingCompleteChime() async {
    if (!dryingCompleteChimeEnabled) return;
    try {
      if (Platform.isAndroid || Platform.isWindows) {
        await _audioChannel.invokeMethod<void>('playDryingCompleteChime');
        return;
      }
      if (Platform.isLinux) {
        final executableDirectory = File(Platform.resolvedExecutable)
            .parent
            .path;
        final sound =
            '$executableDirectory/data/flutter_assets/assets/audio/drying_complete.wav';
        final result = await Process.run('/usr/bin/paplay', [sound]);
        if (result.exitCode == 0) return;
      }
      await SystemSound.play(SystemSoundType.alert);
    } catch (error) {
      debugPrint('Could not play drying-complete chime: $error');
    }
  }

  Future<void> _playMoistureAlertChime() async {
    if (!moistureAlertChimeEnabled) return;
    try {
      if (Platform.isAndroid || Platform.isWindows) {
        await _audioChannel.invokeMethod<void>('playMoistureAlertChime');
        return;
      }
      if (Platform.isLinux) {
        final executableDirectory = File(Platform.resolvedExecutable)
            .parent
            .path;
        final sound =
            '$executableDirectory/data/flutter_assets/assets/audio/moisture_alert.wav';
        final result = await Process.run('/usr/bin/paplay', [sound]);
        if (result.exitCode == 0) return;
      }
      await SystemSound.play(SystemSoundType.alert);
    } catch (error) {
      debugPrint('Could not play moisture-alert chime: $error');
    }
  }

  Object? _sortedJson(Object? value) {
    if (value is List) return value.map(_sortedJson).toList();
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _sortedJson(value[key])};
    }
    return value;
  }

  bool _sameJson(Object? a, Object? b) =>
      jsonEncode(_sortedJson(a)) == jsonEncode(_sortedJson(b));

  Future<bool> _recoverExpiredOwnerSession(
    LocalDatabase database,
    SupabaseConfig failedConfig,
  ) async {
    final workspaceId = failedConfig.workspaceId;
    if (failedConfig.workspaceRole != 'owner' || workspaceId == null) {
      return false;
    }
    final recoveryKey = database.loadWorkspaceRecoveryKey(workspaceId);
    if (recoveryKey == null) return false;
    try {
      return await database.withSyncSessionLock(() async {
        final source = database.loadSyncConfig();
        final latest = source == null
            ? failedConfig
            : SupabaseConfig.fromJson(
                jsonDecode(source) as Map<String, dynamic>,
              );
        final service = SupabaseSyncService(latest);
        final session = await service.signInAnonymously();
        await service.requireCurrentSchema(session);
        final replacement = await service.recoverWorkspace(
          session,
          workspaceId: workspaceId,
          recoveryKey: recoveryKey,
          deviceName: deviceName,
        );
        final recovered = latest.copyWith(
          userId: session.userId,
          workspaceId: replacement.workspaceId,
          workspaceRole: 'owner',
          accessToken: session.accessToken,
          accessTokenExpiresAt: session.expiresAt,
          refreshToken: session.refreshToken,
        );
        database.saveWorkspaceRecoveryKey(
          replacement.workspaceId,
          replacement.key,
        );
        database.saveSyncConfig(jsonEncode(recovered.toJson()));
        if (mounted) {
          setState(() {
            currentRole = WorkspaceRole.admin;
            workspaceOwner = true;
            currentUserId = session.userId;
          });
        }
        return true;
      });
    } catch (error) {
      debugPrint('Automatic owner-session recovery failed: $error');
      return false;
    }
  }

  Future<void> _syncAutomatically() async {
    final database = widget.database;
    if (database == null || _autoSyncPausedForAuthentication) {
      return;
    }
    if (_syncing) {
      // A save that lands during an upload must get another turn. Previously
      // its debounce fired into this guard and the newer state could wait for
      // a later poll while an older remote snapshot was treated as current.
      _syncRequestedWhileBusy = true;
      return;
    }
    if (_quantityCommitTimers.isNotEmpty) return;
    if (_inventoryIsScrolling.value) {
      _deferredAutoSync?.cancel();
      _deferredAutoSync = Timer(
        const Duration(milliseconds: 750),
        () => unawaited(_syncAutomatically()),
      );
      return;
    }
    _deferredAutoSync?.cancel();
    _deferredAutoSync = null;
    final saved = database.loadSyncConfig();
    if (saved == null) return;
    late SupabaseConfig config;
    try {
      config = SupabaseConfig.fromJson(
        jsonDecode(saved) as Map<String, dynamic>,
      );
    } catch (_) {
      return;
    }
    if (config.syncMode != 'supabase' ||
        !config.isConfigured ||
        !config.hasSession ||
        config.workspaceId == null) {
      return;
    }
    var retryAfterRecovery = false;
    var syncSucceeded = false;
    _syncing = true;
    _syncRequestedWhileBusy = false;
    try {
      final refreshed = await database.withSyncSessionLock(() async {
        final latestSource = database.loadSyncConfig();
        final latest = latestSource == null
            ? config
            : SupabaseConfig.fromJson(
                jsonDecode(latestSource) as Map<String, dynamic>,
              );
        final cachedSession = latest.cachedSession;
        if (cachedSession != null) {
          return (config: latest, session: cachedSession);
        }
        final nextSession = await SupabaseSyncService(latest).refresh();
        final nextConfig = latest.copyWith(
          userId: nextSession.userId,
          accessToken: nextSession.accessToken,
          accessTokenExpiresAt: nextSession.expiresAt,
          refreshToken: nextSession.refreshToken,
        );
        // Refresh tokens rotate. Persist the replacement while the per-database
        // session lock is held; normal sync polls reuse the access token until
        // shortly before it expires instead of rotating on every poll.
        database.saveSyncConfig(jsonEncode(nextConfig.toJson()));
        return (config: nextConfig, session: nextSession);
      });
      config = refreshed.config;
      final session = refreshed.session;
      var service = SupabaseSyncService(config);
      await service.requireCurrentSchema(session);
      try {
        final role = await service.currentRole(session);
        final roleChanged = config.workspaceRole != role;
        config = config.copyWith(workspaceRole: role);
        if (roleChanged) {
          database.saveSyncConfig(jsonEncode(config.toJson()));
        }
        if (role == 'owner') {
          final recoveryKey = await service.ensureRecoveryKey(session);
          if (recoveryKey != null &&
              config.workspaceId != null &&
              database.loadWorkspaceRecoveryKey(config.workspaceId!) !=
                  recoveryKey) {
            database.saveWorkspaceRecoveryKey(config.workspaceId!, recoveryKey);
          }
        }
        final nextRole = WorkspaceRole.fromServer(role);
        final nextOwner = role == 'owner';
        if (mounted &&
            (currentRole != nextRole ||
                workspaceOwner != nextOwner ||
                currentUserId != session.userId)) {
          setState(() {
            currentRole = nextRole;
            workspaceOwner = nextOwner;
            currentUserId = session.userId;
          });
        }
        service = SupabaseSyncService(config);
      } catch (error) {
        debugPrint('Could not refresh workspace role: $error');
      }
      // Device registration only updates the friendly name and last-seen
      // metadata. It must never prevent the actual inventory from syncing if
      // an older server is missing the device-roles RPC or PostgREST has a
      // temporarily stale schema cache.
      try {
        await service.registerDevice(session, deviceName);
      } catch (error) {
        debugPrint('Device registration failed; continuing sync: $error');
      }

      var cursor = database.loadSyncCursor(config.workspaceId!);
      final incoming = await service.downloadChanges(
        session,
        afterRevision: cursor,
      );
      if (_quantityCommitTimers.isNotEmpty) {
        _syncRequestedWhileBusy = true;
        return;
      }
      var pending = database.loadPendingWorkshopChanges();
      var pendingByKey = {
        for (final entry in pending)
          '${entry.change.entityType}\u0000${entry.change.entityId}':
              entry.change,
      };
      if (incoming.changes.isNotEmpty && mounted) {
        await _waitForInventoryScrollIdle();
        if (!mounted) return;
        final mergedIncoming = incoming.changes.map((change) {
          final local =
              pendingByKey['${change.entityType}\u0000${change.entityId}'];
          if (local == null) return change;
          if (local.deleted) return local;
          return WorkshopEntityChange(
            entityType: change.entityType,
            entityId: change.entityId,
            fields: {...change.fields, ...local.fields},
            revision: change.revision,
          );
        }).toList();
        database.applyRemoteWorkshopChanges(mergedIncoming);
        _applyRemoteEntityChanges(mergedIncoming);
      }
      cursor = incoming.revision;
      database.saveSyncCursor(config.workspaceId!, cursor);

      final syncingRevision = _localStateRevision;
      final auditBatch = _pendingAuditBatch();
      if (pending.isNotEmpty) {
        await service.uploadChanges(
          session,
          pending.map((entry) => entry.change),
          deviceId: deviceId,
          auditEvents: auditBatch,
        );
        database.acknowledgePendingWorkshopChanges(pending);
        _acknowledgeAuditBatch(auditBatch);
      }

      // Pull again from the previous cursor. This includes our confirmed rows
      // and any concurrent device writes; advancing directly to the RPC's
      // revision could otherwise skip an interleaved change.
      final confirmed = await service.downloadChanges(
        session,
        afterRevision: cursor,
      );
      if (confirmed.changes.isNotEmpty && mounted) {
        await _waitForInventoryScrollIdle();
        if (!mounted) return;
        if (_quantityCommitTimers.isNotEmpty) {
          _syncRequestedWhileBusy = true;
          return;
        }
        pending = database.loadPendingWorkshopChanges();
        pendingByKey = {
          for (final entry in pending)
            '${entry.change.entityType}\u0000${entry.change.entityId}':
                entry.change,
        };
        final mergedConfirmed = confirmed.changes.map((change) {
          final local =
              pendingByKey['${change.entityType}\u0000${change.entityId}'];
          if (local == null) return change;
          if (local.deleted) return local;
          return WorkshopEntityChange(
            entityType: change.entityType,
            entityId: change.entityId,
            fields: {...change.fields, ...local.fields},
            revision: change.revision,
          );
        }).toList();
        database.applyRemoteWorkshopChanges(mergedConfirmed);
        _applyRemoteEntityChanges(mergedConfirmed);
      }
      database.saveSyncCursor(config.workspaceId!, confirmed.revision);
      config = config.copyWith(
        lastSyncedAt: DateTime.now().toUtc(),
        clearLastSyncedStateJson: true,
      );
      database.saveSyncConfig(jsonEncode(config.toJson()));
      _lastSyncedLocalRevision = syncingRevision;
      syncSucceeded = true;
    } on SupabaseSyncException catch (error) {
      if (error.isInvalidRefreshToken) {
        retryAfterRecovery = await _recoverExpiredOwnerSession(
          database,
          config,
        );
        if (!retryAfterRecovery) {
          _autoSyncPausedForAuthentication = true;
          _syncPoll?.cancel();
          debugPrint(
            'Automatic sync paused until Remote Sync is reopened: $error',
          );
          if (mounted && canManageWorkspaceDevices(config.workspaceRole)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Remote session expired. Open Remote Sync to reconnect.',
                ),
                duration: Duration(seconds: 8),
              ),
            );
          }
        }
      } else {
        debugPrint('Automatic sync failed: $error');
      }
    } catch (error) {
      debugPrint('Automatic sync failed: $error');
    } finally {
      _syncing = false;
      final newerStateNeedsSync =
          syncSucceeded && _localStateRevision != _lastSyncedLocalRevision;
      final runAgain = _syncRequestedWhileBusy || newerStateNeedsSync;
      _syncRequestedWhileBusy = false;
      if (runAgain &&
          mounted &&
          !_autoSyncPausedForAuthentication &&
          !retryAfterRecovery) {
        _scheduleAutomaticSync(delay: Duration.zero);
      }
    }
    if (retryAfterRecovery && mounted) {
      _autoSyncPausedForAuthentication = false;
      unawaited(_syncAutomatically());
    }
  }

  Future<void> _waitForInventoryScrollIdle() async {
    while (mounted && _inventoryIsScrolling.value) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // Let the first settled frame render before applying incoming records.
    if (mounted) await SchedulerBinding.instance.endOfFrame;
  }

  Future<void> _openCloudSync({String? initialPairingCode}) async {
    final database = widget.database;
    if (database == null) return;
    final source = database.loadSyncConfig();
    if (source == null ||
        SupabaseConfig.fromJson(jsonDecode(source) as Map<String, dynamic>)
                .syncMode !=
            'supabase') {
      await _openSyncOnboarding();
      return;
    }
    _syncDebounce?.cancel();
    _syncPoll?.cancel();
    await showDialog<void>(
      context: context,
      builder: (_) => CloudSyncDialog(
        database: database,
        localStateJson: _currentStateJson(),
        onCloudState: _applyRemoteCloudState,
        onCloudChanges: _applyRemoteEntityChanges,
        initialPairingCode: initialPairingCode,
      ),
    );
    _startAutoSync();
  }

  Future<void> _openSyncOnboarding() async {
    final database = widget.database;
    if (database == null || !mounted) return;
    final choice = await showDialog<SyncOnboardingChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SyncOnboardingDialog(),
    );
    if (choice == null) return;
    final config = choice.config;
    if (config == null) {
      database.saveSyncConfig(
        jsonEncode(
          const SupabaseConfig(
            syncMode: 'local',
            url: '',
            publishableKey: '',
          ).toJson(),
        ),
      );
      return;
    }
    database.saveSyncConfig(jsonEncode(config.toJson()));
    if (mounted) {
      await _openCloudSync(initialPairingCode: choice.pairingPayload);
      _startAutoSync();
    }
  }

  Future<void> _openDatabaseSettings() async {
    final database = widget.database;
    if (database == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        Widget tile(IconData icon, String label) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        );

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.storage_rounded),
              const SizedBox(width: 10),
              const Expanded(child: Text('Local database')),
              IconButton(
                key: const Key('close-local-database'),
                tooltip: 'Close',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Inventorinator saves every inventory and catalog change automatically.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    database.path,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  const Divider(height: 28),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 10.0;
                      final useColumns = constraints.maxWidth >= 220;
                      final tileWidth = useColumns
                          ? (constraints.maxWidth - gap) / 2
                          : constraints.maxWidth;

                      Widget action(Widget child) =>
                          SizedBox(width: tileWidth, height: 104, child: child);

                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          action(
                            OutlinedButton(
                              key: const Key('import-database'),
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                _importDatabase();
                              },
                              child: tile(Icons.file_upload_outlined, 'Import'),
                            ),
                          ),
                          action(
                            OutlinedButton(
                              key: const Key('export-database'),
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                _exportDatabase();
                              },
                              child: tile(
                                Icons.file_download_outlined,
                                'Export',
                              ),
                            ),
                          ),
                          action(
                            FilledButton(
                              key: const Key('delete-database'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              onPressed: currentRole.canDeleteDatabase
                                  ? () async {
                                      Navigator.pop(dialogContext);
                                      await _confirmDeleteDatabase();
                                    }
                                  : null,
                              child: tile(
                                Icons.delete_forever_outlined,
                                'Delete database',
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportDatabase() async {
    final database = widget.database;
    if (database == null) return;
    try {
      final bytes = await database.exportPortableDatabase();
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final destination = await FilePicker.saveFile(
        dialogTitle: 'Export Inventorinator database',
        fileName: 'inventorinator-$date.sqlite3',
        bytes: bytes,
        mimeType: 'application/vnd.sqlite3',
      );
      if (destination != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SQLite database exported.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Database export failed: $error')));
    }
  }

  Future<void> _importDatabase() async {
    final database = widget.database;
    if (database == null) return;
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Import Inventorinator database',
      type: FileType.custom,
      allowedExtensions: const ['sqlite3', 'sqlite', 'db'],
    );
    if (picked == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import this database?'),
        content: const Text(
          'This replaces the inventory on this device. Its Supabase connection stays intact, so imported items may synchronize to paired devices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-import-database'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Import and replace'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final bytes = await picked.readAsBytes();
      final state = await database.importPortableDatabase(bytes);
      _applyCloudState(state);
      _syncDebounce?.cancel();
      _syncDebounce = Timer(
        const Duration(milliseconds: 700),
        _syncAutomatically,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SQLite database imported.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Database import failed: $error')));
    }
  }

  Future<void> _confirmDeleteDatabase() async {
    if (!currentRole.canDeleteDatabase) {
      _showPermissionDenied('Only an Admin can delete the database.');
      return;
    }
    final firstConfirmation = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete the entire database?'),
        content: const Text(
          'This permanently removes inventory, archives, brands, vendors, products, images, barcodes, and instructions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('continue-delete-database'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('I understand, continue'),
          ),
        ],
      ),
    );
    if (firstConfirmation != true || !mounted) return;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Final confirmation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Type delete to permanently erase the database.'),
              const SizedBox(height: 14),
              TextField(
                key: const Key('delete-database-confirmation'),
                controller: controller,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-delete-database'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: controller.text == 'delete'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Delete everything'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;
    await widget.database!.deleteAndRecreate();
    if (!mounted) return;
    setState(() {
      inventory.clear();
      vendors.clear();
      brands.clear();
      products.clear();
      machineTypes.clear();
      machines.clear();
      kits.clear();
      typeIconOverrides.clear();
      additionHistory.clear();
      archivedOnly = false;
      type = null;
      customTypeFilterId = null;
      itemColorFilter = null;
    });
    _persist();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Local database permanently deleted.')),
    );
  }

  Future<void> _handleScannedCode(
    String rawCode,
    ScanMode mode,
    Uint8List? imageBytes,
  ) async {
    final value = rawCode.trim();
    const locationPrefix = 'inventorinator:location:';
    if (value.startsWith(locationPrefix)) {
      final locationId = value.substring(locationPrefix.length);
      final location = locations
          .where(
            (candidate) =>
                candidate.id.toLowerCase() == locationId.toLowerCase(),
          )
          .firstOrNull;
      if (location == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No location matches “$locationId”.')),
        );
        return;
      }
      Navigator.of(context).pop();
      await _openLocation(location);
      return;
    }
    if (mode == ScanMode.ingest) {
      if (imageBytes != null) {
        final knownProduct = inventory
            .where((item) => item.barcode == value)
            .firstOrNull;
        Navigator.of(context).pop();
        await _addItem(
          initialBarcode: value,
          productTemplate: knownProduct,
          labelDraft: LabelOcrDraft(imageBytes: imageBytes),
        );
      } else {
        final knownProduct = inventory
            .where((item) => item.barcode == value)
            .firstOrNull;
        Navigator.of(context).pop();
        await _addItem(initialBarcode: value, productTemplate: knownProduct);
      }
      return;
    }
    final id = value.startsWith('inventorinator:item:')
        ? value.substring('inventorinator:item:'.length)
        : value;
    InventoryItem? match;
    for (final candidate in inventory) {
      if (candidate.id.toLowerCase() == id.toLowerCase()) {
        match = candidate;
        break;
      }
    }
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No inventory item matches “$id”.')),
      );
      return;
    }
    Navigator.of(context).pop();
    _openDetails(match);
  }

  Future<void> _ingestCapturedLabel(
    Uint8List imageBytes, {
    String barcode = '',
  }) async {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    LabelOcrDraft draft;
    try {
      draft = await recognizeProductLabel(imageBytes);
    } on LabelOcrUnavailable catch (error) {
      draft = LabelOcrDraft(imageBytes: imageBytes);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      draft = LabelOcrDraft(imageBytes: imageBytes);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Label OCR failed: $error')));
      }
    }
    if (!mounted) return;
    final knownProduct = inventory
        .where((item) => barcode.isNotEmpty && item.barcode == barcode)
        .firstOrNull;
    await _addItem(
      initialBarcode: barcode,
      productTemplate: knownProduct,
      labelDraft: draft,
    );
  }

  Widget _header() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 920;
      final narrow = constraints.maxWidth < 600;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 20,
          12,
          compact ? 12 : 20,
          14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('inventory-search'),
              controller: inventorySearchController,
              focusNode: inventorySearchFocusNode,
              onChanged: (value) => setState(() {
                query = value;
                currentPage = 0;
              }),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: compact
                    ? 'Search inventory…'
                    : 'Search items, types, compatibility…  Try “E3DV6”',
              ),
            ),
            const SizedBox(height: 14),
            if (catalogFilter == null &&
                availableItemColorFilters.isNotEmpty) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _typeFilterPanel(compact: narrow)),
                  const SizedBox(width: 8),
                  Expanded(child: _colorFilterPanel(compact: narrow)),
                ],
              ),
              const SizedBox(height: 8),
              if (narrow) ...[
                Row(
                  children: [
                    _resultCount(),
                    const Spacer(),
                    _sortControl(compact: true),
                    const SizedBox(width: 8),
                    _viewOptions(),
                  ],
                ),
                const SizedBox(height: 10),
                _mobileSizeControls(),
              ] else
                Row(
                  children: [
                    _resultCount(),
                    const SizedBox(width: 12),
                    _sortControl(showLabel: !compact),
                    const SizedBox(width: 12),
                    Expanded(child: _sizeControls(expandSliders: true)),
                    const SizedBox(width: 12),
                    _viewOptions(),
                  ],
                ),
            ] else if (compact) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _typeFilterPanel(compact: narrow)),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 13),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (catalogFilter == null)
                          _sortControl(compact: narrow),
                        const SizedBox(width: 8),
                        _viewOptions(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _resultCount(),
                  const SizedBox(width: 12),
                  Expanded(child: _sizeControls(expandSliders: true)),
                ],
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 320, child: _typeFilterPanel()),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 13),
                      child: Row(
                        children: [
                          _resultCount(),
                          const SizedBox(width: 12),
                          if (catalogFilter == null) ...[
                            _sortControl(showLabel: true),
                            const SizedBox(width: 12),
                          ],
                          Expanded(child: _sizeControls(expandSliders: true)),
                          const SizedBox(width: 12),
                          _viewOptions(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    },
  );

  Widget _titleHeader() => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 600;
      return Padding(
        padding: EdgeInsets.fromLTRB(narrow ? 12 : 20, 16, narrow ? 12 : 20, 4),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _headerIdentity(compactLogo: narrow),
          ),
        ),
      );
    },
  );

  Widget _floatingHeaderActionBar() => ValueListenableBuilder<bool>(
    valueListenable: _inventoryIsScrolling,
    child: AnimatedContainer(
      key: const Key('floating-header-actions'),
      duration: Duration.zero,
      decoration: _floatingActionBarDecoration(reduceEffects: false),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 920;
          if (compact) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: _compactHeaderActionStrip(
                showOverflowHint: constraints.maxWidth < 600,
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                ..._centerHeaderActions(),
                const Spacer(),
                ..._databaseHeaderActions(),
              ],
            ),
          );
        },
      ),
    ),
    builder: (context, scrolling, child) => Padding(
      key: const Key('floating-header-shell'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: IgnorePointer(
        ignoring: scrolling,
        child: AnimatedOpacity(
          key: const Key('floating-header-visibility'),
          duration: Duration.zero,
          opacity: scrolling ? 0 : 1,
          child: child,
        ),
      ),
    ),
  );

  BoxDecoration _floatingActionBarDecoration({bool reduceEffects = false}) =>
      BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .55),
        ),
        boxShadow: reduceEffects
            ? const []
            : [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .18),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: .46),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
      );

  Widget _resultCount() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        catalogFilter == null
            ? archivedOnly
                  ? '${visibleItems.length} archived'
                  : type == null &&
                        customTypeFilterId == null &&
                        itemColorFilter == null
                  ? '${visibleItems.length + visibleEverythingCatalogRecords.length} records'
                  : '${visibleItems.length} items'
            : '${visibleCatalogRecords.length} ${_catalogViewDisplayLabel(catalogFilter!).toLowerCase()}',
        style: const TextStyle(
          color: Color(0xff9da5b7),
          fontWeight: FontWeight.w600,
        ),
      ),
      if (catalogFilter == CatalogViewFilter.kits) ...[
        const SizedBox(width: 10),
        Tooltip(
          message: 'What can I build?',
          child: IconButton.outlined(
            key: const Key('open-buildability'),
            onPressed: _openBuildability,
            icon: const Icon(Icons.inventory_outlined, size: 18),
          ),
        ),
      ],
    ],
  );

  Widget _sortControl({bool showLabel = false, bool compact = false}) {
    String label(InventorySort value) => switch (value) {
      InventorySort.type => 'Type',
      InventorySort.quantity => 'Quantity',
      InventorySort.age => 'Age',
      InventorySort.cost => 'Cost',
      InventorySort.dryingTime => 'Drying time',
      InventorySort.moistureRemaining => 'Moisture remaining',
    };
    IconData icon(InventorySort value) => switch (value) {
      InventorySort.type => Icons.category_outlined,
      InventorySort.quantity => Icons.numbers_rounded,
      InventorySort.age => Icons.schedule_rounded,
      InventorySort.cost => Icons.attach_money_rounded,
      InventorySort.dryingTime => Icons.local_fire_department_outlined,
      InventorySort.moistureRemaining => Icons.water_drop_outlined,
    };
    final dropdown = PopupMenuButton<InventorySort>(
      key: const Key('sort-menu'),
      tooltip: 'Sort items',
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      initialValue: sort,
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 280),
      onSelected: (value) => setState(() {
        sort = value;
        currentPage = 0;
      }),
      itemBuilder: (context) => [
        for (final value in InventorySort.values)
          PopupMenuItem(
            value: value,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _PopupActionRow(
              actionKey: 'sort-${value.name}',
              icon: icon(value),
              label: label(value),
              selected: sort == value,
            ),
          ),
      ],
      child: _GlassFilterChip(
        key: const Key('sort-glass-surface'),
        selected: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 9, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon(sort),
                size: 17,
                color: Theme.of(context).colorScheme.primary,
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label(sort),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          const Text(
            'Sort',
            style: TextStyle(color: Color(0xff7f8798), fontSize: 12),
          ),
          const SizedBox(width: 8),
          dropdown,
        ] else
          SizedBox(width: compact ? 64 : 180, child: dropdown),
      ],
    );
  }

  Widget _pageSizeControl({
    bool expandSlider = false,
    bool compactLabel = false,
  }) => ValueListenableBuilder<double>(
    valueListenable: _pageSizeSliderValue,
    builder: (context, previewValue, _) {
      final palette =
          Theme.of(context).extension<InventorinatorColors>() ??
          InventorinatorColors.palettes[AppColorTheme.darkPurple]!;
      final previewIndex = previewValue.round().clamp(0, _pageSizes.length - 1);
      final slider = SliderTheme(
        data: SliderTheme.of(context).copyWith(
          thumbShape: _pageSizeThumbShape,
          thumbColor: palette.base,
          activeTrackColor: palette.accent,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          overlayColor: palette.base.withValues(alpha: .16),
        ),
        child: Slider(
          key: const Key('page-size-slider'),
          value: previewValue,
          min: 0,
          max: (_pageSizes.length - 1).toDouble(),
          divisions: _pageSizes.length - 1,
          label: '${_pageSizes[previewIndex]}',
          onChanged: _previewPageSize,
        ),
      );
      return Row(
        mainAxisSize: expandSlider ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Text(
            compactLabel ? 'Page' : 'Page size',
            style: const TextStyle(color: Color(0xff7f8798), fontSize: 12),
          ),
          if (expandSlider)
            Expanded(child: slider)
          else
            SizedBox(width: 190, child: slider),
          SizedBox(
            width: compactLabel ? 28 : 38,
            child: Text(
              '${_pageSizes[previewIndex]}',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
    },
  );

  void _previewPageSize(double value) {
    _pageSizeSliderValue.value = value.roundToDouble();
    _pageSizeCommitTimer?.cancel();
    _pageSizeCommitTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      final nextIndex = _pageSizeSliderValue.value.round();
      if (nextIndex == pageSizeIndex) return;
      setState(() {
        pageSizeIndex = nextIndex;
        currentPage = 0;
      });
    });
  }

  Widget _sizeControls({bool expandSliders = false}) {
    if (!gridView) return _pageSizeControl(expandSlider: expandSliders);
    return Row(
      mainAxisSize: expandSliders ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (expandSliders)
          Expanded(
            child: _pageSizeControl(expandSlider: true, compactLabel: true),
          )
        else
          _pageSizeControl(),
        const SizedBox(width: 14),
        if (expandSliders)
          Expanded(
            child: _cardSizeControl(expandSlider: true, compactLabel: true),
          )
        else
          _cardSizeControl(),
      ],
    );
  }

  Widget _mobileSizeControls() => Container(
    key: const Key('mobile-size-controls'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      ),
      child: Column(
        children: [
          _pageSizeControl(expandSlider: true),
          if (gridView) ...[
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            _cardSizeControl(expandSlider: true),
          ],
        ],
      ),
    ),
  );

  Widget _cardSizeControl({
    bool expandSlider = false,
    bool compactLabel = false,
  }) => ValueListenableBuilder<double>(
    valueListenable: _cardSizeSliderValue,
    builder: (context, previewValue, _) {
      final palette =
          Theme.of(context).extension<InventorinatorColors>() ??
          InventorinatorColors.palettes[AppColorTheme.darkPurple]!;
      final slider = SliderTheme(
        data: SliderTheme.of(context).copyWith(
          thumbShape: _cardSizeThumbShape,
          thumbColor: palette.base,
          activeTrackColor: palette.accent,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          overlayColor: palette.base.withValues(alpha: .16),
        ),
        child: Slider(
          key: const Key('card-size-slider'),
          value: previewValue,
          min: _minimumCardSizePercent,
          max: _maximumCardSizePercent,
          label: '${previewValue.round()}%',
          onChanged: _previewCardSize,
        ),
      );
      return Row(
        mainAxisSize: expandSlider ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Text(
            compactLabel ? 'Card' : 'Card size',
            style: const TextStyle(color: Color(0xff7f8798), fontSize: 12),
          ),
          if (expandSlider)
            Expanded(child: slider)
          else
            SizedBox(width: 120, child: slider),
          SizedBox(
            width: compactLabel ? 38 : 42,
            child: Text(
              '${previewValue.round()}%',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
    },
  );

  void _previewCardSize(double value) {
    _cardSizeSliderValue.value = value;
    _cardSizeCommitTimer?.cancel();
    _cardSizeCommitTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      final nextValue = _cardSizeSliderValue.value;
      if (nextValue == cardSizePercent) return;
      cardSizePercent = nextValue;
      widget.database?.saveStringPreference(
        'inventory_card_size_percent',
        nextValue.toStringAsFixed(1),
      );
    });
  }

  Widget _headerIdentity({bool showText = true, bool compactLogo = false}) =>
      Row(
        key: const Key('app-title-block'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: compactLogo ? 58 : 75,
            height: compactLogo ? 50 : 62,
            child: Image.asset(
              'assets/images/inventorinator-raygun-v2.png',
              key: const Key('inventorinator-logo'),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          if (showText) ...[
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INVENTORINATOR',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    fontSize: 17,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Take over '),
                      TextSpan(
                        text: 'the world',
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      TextSpan(text: ' the shop!'),
                    ],
                  ),
                  style: TextStyle(color: Color(0xff8f96a7), fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      );

  Widget _compactHeaderActionStrip({required bool showOverflowHint}) => Stack(
    alignment: Alignment.centerRight,
    children: [
      SingleChildScrollView(
        key: const Key('compact-header-actions'),
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(right: showOverflowHint ? 36 : 0),
        child: Row(
          children: [
            ..._centerHeaderActions(),
            const SizedBox(width: 8),
            ..._databaseHeaderActions(),
          ],
        ),
      ),
      if (showOverflowHint)
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              key: const Key('header-more-indicator'),
              width: 42,
              alignment: Alignment.centerRight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).scaffoldBackgroundColor
                        .withValues(alpha: 0),
                    Theme.of(context).scaffoldBackgroundColor,
                  ],
                ),
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
            ),
          ),
        ),
    ],
  );

  Widget _glassQuickAction({
    required Key key,
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    bool iconOnly = false,
    Offset iconOffset = Offset.zero,
    double iconOnlyWidth = 48,
  }) {
    final iconWidget = Transform.translate(
      offset: iconOffset,
      child: Icon(icon, size: 24),
    );
    if (iconOnly) {
      return Tooltip(
        message: label,
        child: OutlinedButton(
          key: key,
          onPressed: onPressed,
          style: _quickActionStyle.copyWith(
            minimumSize: WidgetStatePropertyAll(Size(iconOnlyWidth, 44)),
            maximumSize: WidgetStatePropertyAll(Size(iconOnlyWidth, 44)),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            alignment: Alignment.center,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Center(child: iconWidget),
        ),
      );
    }
    return OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: _quickActionStyle,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [iconWidget, const SizedBox(width: 10), Text(label)],
      ),
    );
  }

  Widget _scanButton({bool iconOnly = false, double iconOnlyWidth = 48}) =>
      _glassQuickAction(
        key: const Key('open-scanner'),
        onPressed: _openScanner,
        icon: Icons.qr_code_scanner_rounded,
        label: 'Scan',
        iconOnly: iconOnly,
        iconOnlyWidth: iconOnlyWidth,
      );

  Widget _rapidizerButton({bool iconOnly = false, double iconOnlyWidth = 48}) =>
      _glassQuickAction(
        key: const Key('open-rapidizer'),
        onPressed: _openRapidizer,
        icon: Icons.bolt_rounded,
        label: 'Rapidizer',
        iconOnly: iconOnly,
        iconOnlyWidth: iconOnlyWidth,
      );

  Widget _filamentColorsButton({
    bool iconOnly = false,
    double iconOnlyWidth = 48,
  }) => Tooltip(
    message: 'Search FilamentColors.xyz',
    child: _glassQuickAction(
      key: const Key('open-filament-colors'),
      onPressed: _openFilamentColors,
      icon: Icons.palette_outlined,
      label: 'FilamentColors.xyz',
      iconOnly: iconOnly,
      iconOnlyWidth: iconOnlyWidth,
    ),
  );

  Widget _inventoryJsonButton({
    bool iconOnly = false,
    double iconOnlyWidth = 48,
  }) => Tooltip(
    message: 'Import inventory items from JSON',
    child: _glassQuickAction(
      key: const Key('open-inventory-json-import'),
      onPressed: currentRole.canCreateInventory ? _importInventoryJson : null,
      icon: Icons.data_object_rounded,
      label: 'JSON',
      iconOnly: iconOnly,
      iconOnlyWidth: iconOnlyWidth,
    ),
  );

  String _locationPath(String id, [Set<String>? visited]) {
    final seen = visited ?? <String>{};
    if (!seen.add(id)) return '';
    final location = locations.where((value) => value.id == id).firstOrNull;
    if (location == null) return '';
    if (location.parentId == null) return location.name;
    final parent = _locationPath(location.parentId!, seen);
    return parent.isEmpty ? location.name : '$parent / ${location.name}';
  }

  bool _locationIsWithin(String candidateId, String ancestorId) {
    var currentId = candidateId;
    final visited = <String>{};
    while (visited.add(currentId)) {
      if (currentId == ancestorId) return true;
      final current = locations
          .where((location) => location.id == currentId)
          .firstOrNull;
      final parentId = current?.parentId;
      if (parentId == null) return false;
      currentId = parentId;
    }
    return false;
  }

  Future<void> _openLocation(
    StockLocationRecord location, {
    StateSetter? stockroomRefresh,
  }) async {
    final path = _locationPath(location.id);
    final items =
        inventory
            .where(
              (item) =>
                  item.storageLocationId.isNotEmpty &&
                  _locationIsWithin(item.storageLocationId, location.id),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final totalUnits = items.fold<double>(
      0,
      (total, item) => total + item.quantity,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final compact = MediaQuery.sizeOf(dialogContext).width < 600;
        final availableHeight = MediaQuery.sizeOf(dialogContext).height - 150;
        final qrCode = Container(
          key: Key('location-qr-${location.id}'),
          width: 168,
          height: 168,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: QrImageView(
            key: Key('location-qr-image-${location.id}'),
            data: 'inventorinator:location:${location.id}',
          ),
        );
        final locationInfo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${items.length} item${items.length == 1 ? '' : 's'} · ${_formatBomQuantity(totalUnits)} units',
              key: Key('location-summary-${location.id}'),
              style: Theme.of(dialogContext).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Includes inventory in this location and its child locations.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: Key('download-location-qr-${location.id}'),
                  onPressed: () =>
                      _downloadLocationQr(dialogContext, location, path),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download QR'),
                ),
                FilledButton.icon(
                  key: Key('move-items-from-location-${location.id}'),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    final refresh =
                        stockroomRefresh ??
                        (VoidCallback callback) {
                          if (mounted) setState(callback);
                        };
                    unawaited(_moveItemsToLocation(location, refresh));
                  },
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('Move items here'),
                ),
              ],
            ),
          ],
        );
        return AlertDialog(
          key: Key('location-details-${location.id}'),
          title: Row(
            children: [
              const _LocationIcon(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                key: const Key('close-location-details'),
                tooltip: 'Close location',
                style: _destructiveIconButtonStyle(dialogContext),
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          content: SizedBox(
            width: 680,
            height: availableHeight.clamp(360.0, 650.0),
            child: Column(
              children: [
                if (compact)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(alignment: Alignment.center, child: qrCode),
                      const SizedBox(height: 16),
                      locationInfo,
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      qrCode,
                      const SizedBox(width: 16),
                      Expanded(child: locationInfo),
                    ],
                  ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? const Center(
                          child: Text(
                            'No inventory is assigned to this area yet.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return ListTile(
                              key: Key('location-item-${item.id}'),
                              leading: _ItemVisual(
                                item: item,
                                size: 42,
                                typeIcon: _itemTypeIcon(item),
                                typeIconImageBytes: _iconImageBytesFromKey(
                                  _itemTypeIconKey(item),
                                ),
                              ),
                              title: Text(item.name),
                              subtitle: Text(
                                '${_locationPath(item.storageLocationId)} · ${_itemTypeDisplayLabel(item)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                '×${_formatBomQuantity(item.quantity)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(dialogContext);
                                _openDetails(item);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addLocation(StateSetter refresh) async {
    final controller = TextEditingController();
    String? parentId;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add location'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('new-location-name'),
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Location name'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: const Key('new-location-parent'),
                  initialValue: parentId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Inside (optional)',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Top level'),
                    ),
                    for (final location in locations)
                      DropdownMenuItem(
                        value: location.id,
                        child: Text(_locationPath(location.id)),
                      ),
                  ],
                  onChanged: (value) => parentId = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-add-location'),
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Add location'),
            ),
          ],
        ),
      ),
    );
    final name = controller.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (accepted != true || name.isEmpty || !mounted) return;
    locations.add(
      StockLocationRecord(
        id: 'LOC-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        parentId: parentId,
      ),
    );
    _recordAudit('create', 'location', locations.last.id, {'name': name});
    _persist();
    refresh(() {});
    if (mounted) setState(() {});
  }

  void _refreshStructuredLocationPaths() {
    final validIds = locations.map((location) => location.id).toSet();
    for (var index = 0; index < inventory.length; index++) {
      final item = inventory[index];
      if (item.storageLocationId.isEmpty) continue;
      if (!validIds.contains(item.storageLocationId)) {
        _publishInventoryItem(
          item.copyWith(storageLocationId: '', storageLocation: ''),
        );
        continue;
      }
      _publishInventoryItem(
        item.copyWith(storageLocation: _locationPath(item.storageLocationId)),
      );
    }
  }

  Future<void> _renameLocation(
    StockLocationRecord location,
    StateSetter refresh,
  ) async {
    final controller = TextEditingController(text: location.name);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rename location'),
          content: TextField(
            key: const Key('rename-location-name'),
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Location name'),
            onChanged: (_) => setDialogState(() {}),
            onSubmitted: (_) {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, true);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              key: const Key('confirm-rename-location'),
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Rename'),
            ),
          ],
        ),
      ),
    );
    final nextName = controller.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (accepted != true || nextName.isEmpty || !mounted) return;
    final oldPath = _locationPath(location.id);
    final index = locations.indexWhere((entry) => entry.id == location.id);
    if (index < 0) return;
    locations[index] = StockLocationRecord(
      id: location.id,
      name: nextName,
      parentId: location.parentId,
    );
    _refreshStructuredLocationPaths();
    _recordAudit('rename', 'location', location.id, {
      'name': '$oldPath → ${_locationPath(location.id)}',
    });
    _persist();
    refresh(() {});
    if (mounted) setState(() {});
  }

  Future<void> _deleteLocation(
    StockLocationRecord location,
    StateSetter refresh,
  ) async {
    final directItemCount = inventory
        .where((item) => item.storageLocationId == location.id)
        .length;
    final childCount = locations
        .where((entry) => entry.parentId == location.id)
        .length;
    final parent = location.parentId == null
        ? null
        : locations.where((entry) => entry.id == location.parentId).firstOrNull;
    final destination = parent == null
        ? 'No location'
        : _locationPath(parent.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${_locationPath(location.id)}?'),
        content: Text(
          [
            'This permanently removes the location.',
            if (directItemCount > 0)
              '$directItemCount directly stored item${directItemCount == 1 ? '' : 's'} will move to $destination.',
            if (childCount > 0)
              '$childCount child location${childCount == 1 ? '' : 's'} will move up one level.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('confirm-delete-location'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete location'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final oldPath = _locationPath(location.id);
    for (var index = 0; index < locations.length; index++) {
      final child = locations[index];
      if (child.parentId != location.id) continue;
      locations[index] = StockLocationRecord(
        id: child.id,
        name: child.name,
        parentId: location.parentId,
      );
    }
    for (var index = 0; index < inventory.length; index++) {
      final item = inventory[index];
      if (item.storageLocationId != location.id) continue;
      _publishInventoryItem(
        item.copyWith(
          storageLocationId: parent?.id ?? '',
          storageLocation: parent == null ? '' : _locationPath(parent.id),
        ),
      );
    }
    locations.removeWhere((entry) => entry.id == location.id);
    _refreshStructuredLocationPaths();
    _recordAudit('delete', 'location', location.id, {
      'name': oldPath,
      'items moved': directItemCount.toString(),
      'children moved': childCount.toString(),
    });
    _persist();
    refresh(() {});
    if (mounted) setState(() {});
  }

  void _moveInventoryItem(InventoryItem item, StockLocationRecord location) {
    setState(() {
      _publishInventoryItem(
        item.copyWith(
          storageLocationId: location.id,
          storageLocation: _locationPath(location.id),
        ),
      );
      _recordAudit('move', 'inventory', item.id, {
        'name': item.name,
        'location': _locationPath(location.id),
      });
    });
    _persist();
  }

  Future<void> _moveItemsToLocation(
    StockLocationRecord location,
    StateSetter refresh,
  ) async {
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final needle = _normalized(query);
          final matches = inventory
              .where(
                (item) =>
                    !item.archived &&
                    (needle.isEmpty ||
                        _normalized(
                          '${item.name} ${item.brand} ${item.barcode} ${item.id}',
                        ).contains(needle)),
              )
              .toList();
          return AlertDialog(
            key: const Key('move-items-to-location-dialog'),
            title: Text('Move to ${_locationPath(location.id)}'),
            content: SizedBox(
              width: 580,
              height: 520,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('move-location-search'),
                          autofocus: true,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded),
                            hintText: 'Search items, brands, IDs, or barcodes',
                          ),
                          onChanged: (value) =>
                              setDialogState(() => query = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        key: const Key('scan-item-to-location'),
                        tooltip: 'Scan item into this location',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => InventoryQrScanner(
                              onCode: (code, mode, image) {
                                final value = code.trim();
                                final id =
                                    value.startsWith('inventorinator:item:')
                                    ? value.substring(
                                        'inventorinator:item:'.length,
                                      )
                                    : value;
                                final match = inventory
                                    .where(
                                      (item) =>
                                          item.id.toLowerCase() ==
                                              id.toLowerCase() ||
                                          item.barcode == value,
                                    )
                                    .firstOrNull;
                                if (match != null) {
                                  _moveInventoryItem(match, location);
                                }
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      match == null
                                          ? 'No inventory item matches that code.'
                                          : '${match.name} moved to ${_locationPath(location.id)}.',
                                    ),
                                  ),
                                );
                                refresh(() {});
                                setDialogState(() {});
                              },
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final item = matches[index];
                        final here = item.storageLocationId == location.id;
                        return ListTile(
                          key: Key('move-item-${item.id}'),
                          leading: Icon(item.icon),
                          title: Text(item.name),
                          subtitle: Text(
                            item.storageLocation.isEmpty
                                ? 'No location'
                                : item.storageLocation,
                          ),
                          trailing: here
                              ? const Icon(Icons.check_rounded)
                              : const Icon(Icons.arrow_forward_rounded),
                          onTap: here
                              ? null
                              : () {
                                  _moveInventoryItem(item, location);
                                  refresh(() {});
                                  setDialogState(() {});
                                },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _receiveShoppingEntry(
    ShoppingListEntry entry,
    StateSetter refresh,
  ) async {
    final remaining = math
        .max(0, entry.quantityNeeded - entry.quantityReceived)
        .toDouble();
    final matched = inventory
        .where(
          (item) =>
              item.id == entry.productId ||
              item.catalogProductId == entry.productId ||
              _normalized(item.name) == _normalized(entry.name),
        )
        .firstOrNull;
    if (matched == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Match ${entry.name} to an inventory item first.'),
        ),
      );
      return;
    }
    final controller = TextEditingController(
      text: _formatBomQuantity(remaining),
    );
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Receive ${entry.name}'),
        content: TextField(
          key: const Key('receive-shopping-quantity'),
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Quantity received'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-receive-shopping'),
            onPressed: () => Navigator.pop(
              dialogContext,
              double.tryParse(controller.text.trim()),
            ),
            child: const Text('Receive'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (amount == null || amount <= 0 || !mounted) return;
    setState(() {
      _publishInventoryItem(
        matched.copyWith(quantity: matched.quantity + amount),
      );
      final index = shoppingList.indexWhere((value) => value.id == entry.id);
      if (index >= 0) {
        final received = entry.quantityReceived + amount;
        shoppingList[index] = entry.copyWith(
          quantityReceived: received,
          status: received + .0001 >= entry.quantityNeeded
              ? ShoppingListStatus.received
              : ShoppingListStatus.ordered,
        );
      }
      _recordAudit('receive', 'shopping', entry.id, {
        'item': entry.name,
        'quantity': amount.toString(),
        'inventoryId': matched.id,
      });
    });
    _persist();
    refresh(() {});
  }

  ButtonStyle _destructiveIconButtonStyle(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    Widget dangerLayer(
      BuildContext context,
      Set<WidgetState> states,
      Widget? child,
    ) {
      final active =
          states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused) ||
          states.contains(WidgetState.pressed);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: danger.withValues(alpha: active ? .2 : .11),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: danger.withValues(alpha: active ? .72 : .42),
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: danger.withValues(alpha: .2),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: child ?? const SizedBox.shrink(),
        ),
      );
    }

    return ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(danger),
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
      minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      backgroundBuilder: dangerLayer,
    );
  }

  Future<void> _openStockroom() => showDialog<void>(
    context: context,
    builder: (dialogContext) => DefaultTabController(
      length: 2,
      child: StatefulBuilder(
        builder: (context, refresh) {
          final compact = MediaQuery.sizeOf(context).width < 600;
          final sortedLocations = [
            ...locations,
          ]..sort((a, b) => _locationPath(a.id).compareTo(_locationPath(b.id)));
          return AlertDialog(
            key: const Key('stockroom-dialog'),
            title: Row(
              children: [
                const Icon(Icons.warehouse_outlined),
                const SizedBox(width: 10),
                const Expanded(child: Text('Stockroom')),
                IconButton(
                  key: const Key('close-stockroom'),
                  tooltip: 'Close Stockroom',
                  onPressed: () => Navigator.pop(dialogContext),
                  style: _destructiveIconButtonStyle(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            content: SizedBox(
              width: 760,
              height: 650,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(
                        icon: Icon(Icons.account_tree_outlined),
                        text: 'Locations',
                      ),
                      Tab(icon: _ShoppingCartIcon(), text: 'Shopping'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        Column(
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: FilledButton.icon(
                                  key: const Key('add-location'),
                                  onPressed: () => _addLocation(refresh),
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Add location'),
                                ),
                              ),
                            ),
                            Expanded(
                              child: sortedLocations.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Add a shelf, cabinet, bin, or room.',
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: sortedLocations.length,
                                      itemBuilder: (context, index) {
                                        final location = sortedLocations[index];
                                        final count = inventory
                                            .where(
                                              (item) =>
                                                  item.storageLocationId ==
                                                  location.id,
                                            )
                                            .length;
                                        Widget locationActions() => Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton.filledTonal(
                                              key: Key(
                                                'move-items-location-${location.id}',
                                              ),
                                              tooltip: 'Move items',
                                              onPressed: () =>
                                                  _moveItemsToLocation(
                                                    location,
                                                    refresh,
                                                  ),
                                              icon: const Icon(
                                                Icons.drive_file_move_outline,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              key: Key(
                                                'rename-location-${location.id}',
                                              ),
                                              tooltip:
                                                  'Rename ${_locationPath(location.id)}',
                                              onPressed: () => _renameLocation(
                                                location,
                                                refresh,
                                              ),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                              ),
                                            ),
                                            IconButton(
                                              key: Key(
                                                'delete-location-${location.id}',
                                              ),
                                              tooltip:
                                                  'Delete ${_locationPath(location.id)}',
                                              style:
                                                  _destructiveIconButtonStyle(
                                                    context,
                                                  ),
                                              onPressed: () => _deleteLocation(
                                                location,
                                                refresh,
                                              ),
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                              ),
                                            ),
                                          ],
                                        );
                                        if (compact) {
                                          return Card(
                                            clipBehavior: Clip.antiAlias,
                                            child: InkWell(
                                              key: Key(
                                                'location-${location.id}',
                                              ),
                                              onTap: () => _openLocation(
                                                location,
                                                stockroomRefresh: refresh,
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      14,
                                                      12,
                                                      8,
                                                      8,
                                                    ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 2,
                                                              ),
                                                          child: _LocationIcon(
                                                            key: Key(
                                                              'location-pin-${location.id}',
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 12,
                                                        ),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                _locationPath(
                                                                  location.id,
                                                                ),
                                                              ),
                                                              Text(
                                                                '$count item${count == 1 ? '' : 's'}',
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: locationActions(),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                        return Card(
                                          child: ListTile(
                                            key: Key('location-${location.id}'),
                                            onTap: () => _openLocation(
                                              location,
                                              stockroomRefresh: refresh,
                                            ),
                                            leading: _LocationIcon(
                                              key: Key(
                                                'location-pin-${location.id}',
                                              ),
                                            ),
                                            title: Text(
                                              _locationPath(location.id),
                                            ),
                                            subtitle: Text(
                                              '$count item${count == 1 ? '' : 's'}',
                                            ),
                                            trailing: locationActions(),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                        shoppingList.isEmpty
                            ? const Center(
                                child: Text(
                                  'Add shortages from a kit BOM to shop and receive them here.',
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(top: 10),
                                itemCount: shoppingList.length,
                                itemBuilder: (context, index) {
                                  final entry = shoppingList[index];
                                  final remaining = math.max(
                                    0,
                                    entry.quantityNeeded -
                                        entry.quantityReceived,
                                  );
                                  return Card(
                                    key: Key('shopping-${entry.id}'),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        12,
                                        8,
                                        8,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              entry.status ==
                                                      ShoppingListStatus
                                                          .received
                                                  ? const Icon(
                                                      Icons
                                                          .check_circle_rounded,
                                                    )
                                                  : const _ShoppingCartIcon(),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  entry.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Need ${_formatBomQuantity(entry.quantityNeeded)} · Received ${_formatBomQuantity(entry.quantityReceived)}${entry.quantityOrdered > 0 ? ' · Ordered ${_formatBomQuantity(entry.quantityOrdered)}' : ''}',
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            alignment: WrapAlignment.end,
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              if (entry.status ==
                                                  ShoppingListStatus.needed)
                                                OutlinedButton(
                                                  onPressed: () {
                                                    setState(() {
                                                      shoppingList[index] =
                                                          entry.copyWith(
                                                            quantityOrdered: entry
                                                                .quantityNeeded,
                                                            status:
                                                                ShoppingListStatus
                                                                    .ordered,
                                                          );
                                                    });
                                                    _persist();
                                                    refresh(() {});
                                                  },
                                                  child: const Text('Ordered'),
                                                ),
                                              FilledButton(
                                                onPressed: remaining <= 0
                                                    ? null
                                                    : () =>
                                                          _receiveShoppingEntry(
                                                            entry,
                                                            refresh,
                                                          ),
                                                child: const Text('Receive'),
                                              ),
                                              IconButton(
                                                key: Key(
                                                  'remove-shopping-${entry.id}',
                                                ),
                                                tooltip:
                                                    'Remove from shopping list',
                                                style:
                                                    _destructiveIconButtonStyle(
                                                      context,
                                                    ),
                                                onPressed: () {
                                                  setState(
                                                    () => shoppingList.removeAt(
                                                      index,
                                                    ),
                                                  );
                                                  _persist();
                                                  refresh(() {});
                                                },
                                                icon:
                                                    const _ShoppingCartIcon.remove(
                                                      key: Key(
                                                        'remove-shopping-cart-glyph',
                                                      ),
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _stockroomButton({bool iconOnly = false, double iconOnlyWidth = 48}) =>
      Tooltip(
        message: 'Locations, shopping, and receiving',
        child: _glassQuickAction(
          key: const Key('open-stockroom'),
          onPressed: _openStockroom,
          icon: Icons.warehouse_outlined,
          label: 'Stockroom',
          iconOnly: iconOnly,
          iconOffset: const Offset(-2, 0),
          iconOnlyWidth: iconOnlyWidth,
        ),
      );

  Widget _bottomActionBar() {
    return ValueListenableBuilder<bool>(
      valueListenable: _inventoryIsScrolling,
      child: AnimatedContainer(
        key: const Key('bottom-action-surface'),
        duration: Duration.zero,
        decoration: _floatingActionBarDecoration(reduceEffects: false),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Collapse before the longest labels can crowd or clip. The
            // compact rail is intentionally used through medium desktop
            // widths, not only at phone sizes.
            final iconOnly = constraints.maxWidth < 1180;
            final taper = ((constraints.maxWidth - 760) / (1180 - 760)).clamp(
              0.0,
              1.0,
            );
            final iconOnlyWidth = ui.lerpDouble(48, 88, taper)!;
            final addItem = _glassQuickAction(
              key: const Key('add-item'),
              onPressed: currentRole.canCreateInventory ? _addItem : null,
              icon: Icons.add_rounded,
              label: 'Add item',
              iconOnly: iconOnly,
              iconOnlyWidth: iconOnlyWidth,
            );
            final rightActions = <Widget>[
              _scanButton(iconOnly: iconOnly, iconOnlyWidth: iconOnlyWidth),
              const SizedBox(width: 12),
              addItem,
              const SizedBox(width: 12),
              _rapidizerButton(
                iconOnly: iconOnly,
                iconOnlyWidth: iconOnlyWidth,
              ),
              const SizedBox(width: 12),
              _filamentColorsButton(
                iconOnly: iconOnly,
                iconOnlyWidth: iconOnlyWidth,
              ),
              const SizedBox(width: 12),
              _inventoryJsonButton(
                iconOnly: iconOnly,
                iconOnlyWidth: iconOnlyWidth,
              ),
            ];
            if (iconOnly) {
              final fittedIconWidth = math.min(
                iconOnlyWidth,
                // Reserve the same 14 px outer inset used by the expanded
                // bar, plus the compact gaps between its seven actions.
                math.max(36.0, (constraints.maxWidth - 48) / 7),
              );
              final compactAddItem = _glassQuickAction(
                key: const Key('add-item'),
                onPressed: currentRole.canCreateInventory ? _addItem : null,
                icon: Icons.add_rounded,
                label: 'Add item',
                iconOnly: true,
                iconOnlyWidth: fittedIconWidth,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    key: const Key('compact-bottom-action-group'),
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _catalogButton(
                            iconOnly: true,
                            iconOnlyWidth: fittedIconWidth,
                          ),
                          const SizedBox(width: 4),
                          _stockroomButton(
                            iconOnly: true,
                            iconOnlyWidth: fittedIconWidth,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _scanButton(
                            iconOnly: true,
                            iconOnlyWidth: fittedIconWidth,
                          ),
                          const SizedBox(width: 4),
                          compactAddItem,
                          const SizedBox(width: 4),
                          _rapidizerButton(
                            iconOnly: true,
                            iconOnlyWidth: fittedIconWidth,
                          ),
                          const SizedBox(width: 4),
                          _filamentColorsButton(
                            iconOnly: true,
                            iconOnlyWidth: fittedIconWidth,
                          ),
                          const SizedBox(width: 4),
                          _inventoryJsonButton(
                            iconOnly: true,
                            iconOnlyWidth: fittedIconWidth,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  _catalogButton(),
                  const SizedBox(width: 12),
                  _stockroomButton(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: false,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: rightActions,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      builder: (context, scrolling, child) => SafeArea(
        key: const Key('bottom-quick-actions'),
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: IgnorePointer(
          ignoring: scrolling,
          child: AnimatedOpacity(
            key: const Key('bottom-action-visibility'),
            duration: Duration.zero,
            opacity: scrolling ? 0 : 1,
            child: child,
          ),
        ),
      ),
    );
  }

  ButtonStyle get _quickActionStyle => ButtonStyle(
    foregroundColor: WidgetStatePropertyAll(
      Theme.of(context).colorScheme.onSurface,
    ),
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    side: const WidgetStatePropertyAll(BorderSide.none),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    iconSize: const WidgetStatePropertyAll(24),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  );

  List<Widget> _centerHeaderActions() => [
    SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        key: const Key('moisture-alerts'),
        onPressed: _openMoistureAlerts,
        icon: Badge.count(
          count: _inventoryAlertCount,
          isLabelVisible: _inventoryAlertCount > 0,
          child: const Icon(Icons.notifications_outlined),
        ),
        label: const Text('Alerts'),
      ),
    ),
    const SizedBox(width: 8),
    SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        key: const Key('addition-history'),
        onPressed: _openAdditionHistory,
        icon: const Icon(Icons.new_releases_outlined),
        label: const Text('New items'),
      ),
    ),
  ];

  List<Widget> _databaseHeaderActions() => [
    SizedBox(
      height: 48,
      child: Material(
        key: const Key('config-action-group'),
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _configBlockButton(
              key: const Key('database-settings'),
              tooltip: 'Local database',
              onPressed: widget.database == null ? null : _openDatabaseSettings,
              icon: Icons.storage_rounded,
            ),
            _configBlockDivider(),
            _configBlockButton(
              key: const Key('cloud-sync'),
              tooltip: 'Remote Sync',
              onPressed: widget.database == null ? null : _openCloudSync,
              icon: Icons.cloud_sync_outlined,
            ),
            _configBlockDivider(),
            _configBlockButton(
              key: const Key('personalization-settings'),
              tooltip: 'Personalization settings',
              onPressed: _openAnimationControls,
              icon: Icons.palette_outlined,
            ),
            _configBlockDivider(),
            _configBlockButton(
              key: const Key('debug-panel'),
              tooltip: 'Debug effects',
              onPressed: _openDebugPanel,
              icon: Icons.bug_report_outlined,
            ),
            _configBlockDivider(),
            _configBlockButton(
              key: const Key('audit-log'),
              tooltip: 'Change log',
              onPressed: _openAuditLog,
              icon: Icons.history_rounded,
            ),
          ],
        ),
      ),
    ),
  ];

  Widget _configBlockButton({
    required Key key,
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
  }) {
    Widget joinedGlassLayer(
      BuildContext context,
      Set<WidgetState> states,
      Widget? child,
    ) => _GlassButtonSurface(states: states, joined: true, child: child);

    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      style: IconButton.styleFrom(
        shape: const RoundedRectangleBorder(),
        backgroundColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ).copyWith(backgroundBuilder: joinedGlassLayer),
      icon: Icon(icon),
    );
  }

  Widget _configBlockDivider() => SizedBox(
    width: 1,
    height: 48,
    child: ColoredBox(color: Theme.of(context).colorScheme.outlineVariant),
  );

  Future<void> _openAuditLog() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Change log'),
      content: SizedBox(
        width: 680,
        height: 560,
        child: auditLog.isEmpty
            ? const Center(child: Text('No recorded changes yet.'))
            : ListView.separated(
                itemCount: auditLog.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = auditLog[index];
                  return ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(
                      '${entry.action.toUpperCase()} · ${entry.entityType}',
                    ),
                    subtitle: Text(
                      '${entry.actor} · ${entry.timestamp.toLocal()}\n${entry.changes.entries.map((change) => '${change.key}: ${change.value}').join(' · ')}',
                    ),
                    isThreeLine: true,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _catalogButton({bool iconOnly = false, double iconOnlyWidth = 48}) =>
      _glassQuickAction(
        key: const Key('open-catalog'),
        onPressed: currentRole.canManageCatalog ? _openCatalog : null,
        icon: Icons.category_outlined,
        label: 'Catalog',
        iconOnly: iconOnly,
        iconOnlyWidth: iconOnlyWidth,
      );

  Widget _viewToggle() => SegmentedButton<bool>(
    key: const Key('inventory-view-toggle'),
    style: ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(
        Theme.of(context).colorScheme.surface,
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? const Color(0xff6f7180)
            : states.contains(WidgetState.selected)
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface,
      ),
      side: WidgetStatePropertyAll(
        BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    ),
    segments: const [
      ButtonSegment(
        value: false,
        icon: Icon(Icons.view_agenda_outlined),
        tooltip: 'List view',
      ),
      ButtonSegment(
        value: true,
        icon: Icon(Icons.grid_view_rounded),
        tooltip: 'Grid view',
      ),
    ],
    selected: {gridView},
    showSelectedIcon: false,
    onSelectionChanged: (value) => setState(() => gridView = value.first),
  );

  Widget _viewOptions() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _viewToggle(),
      const SizedBox(width: 8),
      Tooltip(
        message: hideZeroQuantityItems
            ? 'Show zero-quantity items'
            : 'Hide zero-quantity items',
        child: IconButton(
          key: const Key('hide-zero-quantity-items'),
          isSelected: hideZeroQuantityItems,
          onPressed: catalogFilter != null
              ? null
              : () {
                  setState(() {
                    hideZeroQuantityItems = !hideZeroQuantityItems;
                    currentPage = 0;
                  });
                  widget.database?.saveBoolPreference(
                    'hide_zero_quantity_items',
                    hideZeroQuantityItems,
                  );
                },
          icon: const Icon(Icons.visibility_outlined),
          selectedIcon: const Icon(Icons.visibility_off_outlined),
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
            backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? const Color(0xff6f7180)
                  : Theme.of(context).colorScheme.onSurface,
            ),
            side: const WidgetStatePropertyAll(BorderSide.none),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    ],
  );

  String get _activeTypeFilterLabel {
    if (archivedOnly) return 'Archived';
    if (catalogFilter case final filter?) {
      return _catalogViewDisplayLabel(filter);
    }
    if (customTypeFilterId case final id?) {
      return customItemTypes
              .where((candidate) => candidate.id == id)
              .firstOrNull
              ?.name ??
          'Custom type';
    }
    if (type case final selected?) {
      return _inventoryTypeDisplayLabel(selected);
    }
    return 'Everything';
  }

  Widget _activeTypeFilterVisual() {
    if (archivedOnly) return const Icon(Icons.archive_outlined, size: 20);
    if (catalogFilter case final selected?) {
      return _typeIconVisual(
        typeIconOverrides[_catalogViewDefinitionKey(selected)],
        _catalogViewIcon(selected),
        size: 20,
      );
    }
    if (customTypeFilterId case final id?) {
      final custom = customItemTypes
          .where((candidate) => candidate.id == id)
          .firstOrNull;
      return _typeIconVisual(custom?.iconKey, Icons.tune_rounded, size: 20);
    }
    if (type case final selected?) {
      return _typeIconVisual(
        typeIconOverrides[_inventoryTypeDefinitionKey(selected)],
        _typeIcon(selected),
        size: 20,
      );
    }
    return const Icon(Icons.category_outlined, size: 20);
  }

  Widget _typeFilterPanel({bool compact = false}) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('type-filter-panel'),
        controller: typeFilterExpansionController,
        initiallyExpanded: typePanelExpanded,
        onExpansionChanged: (expanded) =>
            setState(() => typePanelExpanded = expanded),
        tilePadding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
        minTileHeight: compact ? 62 : null,
        dense: compact,
        visualDensity: compact
            ? const VisualDensity(horizontal: -3, vertical: -3)
            : null,
        leading: _activeTypeFilterVisual(),
        title: Text(
          'Types',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: compact ? 15 : null,
          ),
        ),
        subtitle: Text(
          _activeTypeFilterLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xff9da5b7),
            fontSize: compact ? 11 : null,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              key: const Key('type-filter-options-scroll'),
              primary: false,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  runSpacing: 8,
                  children: [
                    _typeChip(null, 'Everything'),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _GlassFilterChip(
                        selected: archivedOnly,
                        child: FilterChip(
                          key: const Key('archived-view'),
                          avatar: const Icon(Icons.archive_outlined, size: 18),
                          label: const Text('Archived'),
                          selected: archivedOnly,
                          onSelected: (selected) {
                            _collapseTypePanel();
                            setState(() {
                              archivedOnly = selected;
                              catalogFilter = null;
                              itemColorFilter = null;
                              if (selected) {
                                type = null;
                                customTypeFilterId = null;
                              }
                              currentPage = 0;
                            });
                            _scrollToFilteredResults();
                          },
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          backgroundColor: Colors.transparent,
                          selectedColor: Colors.transparent,
                          side: BorderSide.none,
                        ),
                      ),
                    ),
                    for (final filter in CatalogViewFilter.values)
                      if (!deletedTypeKeys.contains(
                        _catalogViewDefinitionKey(filter),
                      ))
                        _catalogFilterChip(
                          filter,
                          _catalogViewDisplayLabel(filter),
                          _catalogViewIcon(filter),
                        ),
                    ...InventoryType.values
                        .where(
                          (value) =>
                              value != InventoryType.custom &&
                              !deletedTypeKeys.contains(
                                _inventoryTypeDefinitionKey(value),
                              ),
                        )
                        .map(
                          (value) => _typeChip(
                            value,
                            _inventoryTypeDisplayLabel(value),
                          ),
                        ),
                    ...customItemTypes.map(_customTypeChip),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _collapseTypePanel() {
    if (typePanelExpanded) typeFilterExpansionController.collapse();
  }

  void _collapseColorPanel() {
    if (colorPanelExpanded) colorFilterExpansionController.collapse();
  }

  void _scrollToFilteredResults() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !inventoryScrollController.hasClients) return;
      inventoryScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _typeChip(InventoryType? value, String label) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: _GlassFilterChip(
      selected:
          catalogFilter == null &&
          type == value &&
          customTypeFilterId == null &&
          (value != null || !archivedOnly),
      child: FilterChip(
        key: Key('type-filter-${value?.name ?? 'everything'}'),
        avatar: value == null
            ? null
            : _typeIconVisual(
                typeIconOverrides[_inventoryTypeDefinitionKey(value)],
                _typeIcon(value),
                size: 18,
              ),
        label: Text(label),
        selected:
            catalogFilter == null &&
            type == value &&
            customTypeFilterId == null &&
            (value != null || !archivedOnly),
        onSelected: (_) {
          _collapseTypePanel();
          setState(() {
            type = value;
            customTypeFilterId = null;
            catalogFilter = null;
            itemColorFilter = null;
            archivedOnly = false;
            currentPage = 0;
          });
          _scrollToFilteredResults();
        },
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        backgroundColor: Colors.transparent,
        selectedColor: Colors.transparent,
        side: BorderSide.none,
      ),
    ),
  );

  Widget _customTypeChip(CustomItemTypeRecord customType) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: _GlassFilterChip(
      selected:
          catalogFilter == null &&
          type == InventoryType.custom &&
          customTypeFilterId == customType.id,
      child: FilterChip(
        key: Key('custom-type-filter-${customType.id}'),
        avatar: _typeIconVisual(
          customType.iconKey,
          Icons.tune_rounded,
          size: 18,
        ),
        label: Text(customType.name),
        selected:
            catalogFilter == null &&
            type == InventoryType.custom &&
            customTypeFilterId == customType.id,
        onSelected: (_) {
          _collapseTypePanel();
          setState(() {
            type = InventoryType.custom;
            customTypeFilterId = customType.id;
            catalogFilter = null;
            itemColorFilter = null;
            archivedOnly = false;
            currentPage = 0;
          });
          _scrollToFilteredResults();
        },
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        backgroundColor: Colors.transparent,
        selectedColor: Colors.transparent,
        side: BorderSide.none,
      ),
    ),
  );

  Widget _catalogFilterChip(
    CatalogViewFilter value,
    String label,
    IconData icon,
  ) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: _GlassFilterChip(
      selected: catalogFilter == value,
      child: FilterChip(
        key: Key('catalog-filter-${value.name}'),
        avatar: _typeIconVisual(
          typeIconOverrides[_catalogViewDefinitionKey(value)],
          icon,
          size: 18,
        ),
        label: Text(label),
        selected: catalogFilter == value,
        onSelected: (_) {
          _collapseTypePanel();
          setState(() {
            catalogFilter = value;
            type = null;
            customTypeFilterId = null;
            itemColorFilter = null;
            archivedOnly = false;
            currentPage = 0;
          });
          _scrollToFilteredResults();
        },
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        backgroundColor: Colors.transparent,
        selectedColor: Colors.transparent,
        side: BorderSide.none,
      ),
    ),
  );

  Widget _colorFilterPanel({bool compact = false}) {
    final selected = availableItemColorFilters
        .where((color) => color.value == itemColorFilter)
        .firstOrNull;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('color-filter-panel'),
          controller: colorFilterExpansionController,
          initiallyExpanded: colorPanelExpanded,
          onExpansionChanged: (expanded) =>
              setState(() => colorPanelExpanded = expanded),
          tilePadding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
          minTileHeight: compact ? 62 : null,
          dense: compact,
          visualDensity: compact
              ? const VisualDensity(horizontal: -3, vertical: -3)
              : null,
          leading: selected == null
              ? const Icon(Icons.palette_outlined, size: 20)
              : Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color:
                        _itemColorSwatch(selected.value) ??
                        const Color(0xff8c929f),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xff687185)),
                  ),
                ),
          title: Text(
            'Colors',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: compact ? 15 : null,
            ),
          ),
          subtitle: Text(
            selected == null
                ? 'All colors'
                : '${selected.label} · ${selected.hex}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xff9da5b7),
              fontSize: compact ? 11 : null,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                key: const Key('color-filter-scroll'),
                primary: false,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _GlassFilterChip(
                        selected: itemColorFilter == null,
                        child: FilterChip(
                          key: const Key('color-filter-all'),
                          label: const Text('All colors'),
                          selected: itemColorFilter == null,
                          onSelected: (_) {
                            _collapseColorPanel();
                            setState(() {
                              itemColorFilter = null;
                              currentPage = 0;
                            });
                            _scrollToFilteredResults();
                          },
                          backgroundColor: Colors.transparent,
                          selectedColor: Colors.transparent,
                          side: BorderSide.none,
                        ),
                      ),
                      for (final color in availableItemColorFilters)
                        _GlassFilterChip(
                          selected: itemColorFilter == color.value,
                          child: FilterChip(
                            key: Key('color-filter-${color.value}'),
                            avatar: CircleAvatar(
                              backgroundColor:
                                  _itemColorSwatch(color.value) ??
                                  const Color(0xff8c929f),
                            ),
                            label: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  color.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  color.hex,
                                  style: const TextStyle(
                                    color: Color(0xff9da5b7),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                            selected: itemColorFilter == color.value,
                            onSelected: (_) {
                              _collapseColorPanel();
                              setState(() {
                                itemColorFilter = color.value;
                                currentPage = 0;
                              });
                              _scrollToFilteredResults();
                            },
                            backgroundColor: Colors.transparent,
                            selectedColor: Colors.transparent,
                            side: BorderSide.none,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogRecordCard(Object record, {bool list = false}) {
    late final IconData icon;
    late final Color accent;
    late final String category;
    late final String title;
    late final String subtitle;
    late final String detail;
    Uint8List? recordImage;
    if (record is KitRecord) {
      final totalUnits = record.bom.fold<double>(
        0,
        (total, entry) => total + entry.quantity,
      );
      final totalLabel = totalUnits == totalUnits.roundToDouble()
          ? totalUnits.toInt().toString()
          : totalUnits.toStringAsFixed(2);
      final machineCount = machines
          .where((machine) => machine.kitIds.contains(record.id))
          .length;
      icon = Icons.inventory_2_outlined;
      accent = const Color(0xffa987ff);
      category = _catalogViewDisplayLabel(CatalogViewFilter.kits).toUpperCase();
      title = record.name;
      subtitle = '${record.bom.length} BOM lines · $totalLabel units';
      detail = machineCount == 0
          ? 'Not assigned to a machine'
          : '$machineCount compatible ${machineCount == 1 ? 'machine' : 'machines'}';
      recordImage = record.imageBytes;
    } else if (record is BuildRecord) {
      final used = record.lines.fold<double>(
        0,
        (total, line) => total + line.usedQuantity,
      );
      final required = record.lines.fold<double>(
        0,
        (total, line) => total + line.requiredQuantity,
      );
      icon = Icons.construction_rounded;
      accent = const Color(0xffffb34d);
      category = _catalogViewDisplayLabel(CatalogViewFilter.builds)
          .toUpperCase();
      title = record.name;
      subtitle =
          '${record.lines.length} lines · ${_formatBomQuantity(used)} / ${_formatBomQuantity(required)} used';
      detail = [
        record.completedAt == null ? 'Active' : 'Completed',
        record.shared ? 'Shared' : 'Unshared',
        'Created by ${record.createdBy}',
      ].join(' · ');
      recordImage = kits
          .where((kit) => kit.id == record.kitId)
          .firstOrNull
          ?.imageBytes;
    } else {
      final machine = record as MachineRecord;
      final printer = _isPrinter(machine);
      icon = printer ? Icons.print_outlined : Icons.handyman_outlined;
      accent = printer ? const Color(0xff42d8c7) : const Color(0xffffb34d);
      category = _catalogViewDisplayLabel(
        printer ? CatalogViewFilter.printers : CatalogViewFilter.tools,
      ).toUpperCase();
      title = machine.name;
      subtitle = [
        machine.model,
        _machineTypePath(machine.typeId),
      ].where((value) => value.trim().isNotEmpty).join(' · ');
      detail = machine.address.trim().isEmpty
          ? machine.kitIds.isEmpty
                ? 'No address or kit assigned'
                : '${machine.kitIds.length} associated ${machine.kitIds.length == 1 ? 'kit' : 'kits'}'
          : machine.address;
      recordImage = machine.imageBytes;
    }
    final content = list
        ? ListTile(
            leading: _catalogRecordVisual(recordImage, icon, accent, 42),
            title: Text(title),
            subtitle: Text('$category · $subtitle\n$detail'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right_rounded),
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 450;
              return Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _catalogRecordVisual(recordImage, icon, accent, 42),
                    if (compact) const SizedBox(height: 16) else const Spacer(),
                    Text(
                      category,
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xffa4abba)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff7f8798),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
    final selected = switch (record) {
      KitRecord value => selectedKitIds.contains(value.id),
      BuildRecord value => selectedBuildIds.contains(value.id),
      MachineRecord value => selectedMachineIds.contains(value.id),
      _ => false,
    };
    return Card(
      key: Key(
        'catalog-record-${switch (record) {
          KitRecord value => value.id,
          BuildRecord value => value.id,
          MachineRecord value => value.id,
          _ => record.hashCode,
        }}',
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _handleCatalogRecordTap(record),
        onSecondaryTapDown: record is KitRecord
            ? (details) => _showKitContextMenu(record, details.globalPosition)
            : record is BuildRecord
            ? (_) => _openBuildQueue(record, _kitForBuild(record))
            : null,
        onLongPress: () => _selectCatalogRecord(record),
        child: content,
      ),
    );
  }

  Widget _catalogRecordVisual(
    Uint8List? imageBytes,
    IconData fallbackIcon,
    Color accent,
    double size,
  ) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .25),
    child: SizedBox.square(
      dimension: size,
      child: imageBytes == null
          ? ColoredBox(
              color: accent.withValues(alpha: .14),
              child: Icon(fallbackIcon, color: accent, size: size * .65),
            )
          : Image.memory(imageBytes, fit: BoxFit.cover),
    ),
  );

  Widget _pageNavigation(int page, int pageCount, int totalItems) {
    final first = (page - 2).clamp(0, (pageCount - 5).clamp(0, pageCount));
    final last = (first + 5).clamp(0, pageCount);
    return Column(
      children: [
        Text(
          'Page ${page + 1} of $pageCount · $totalItems results',
          style: const TextStyle(color: Color(0xff929aac), fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          children: [
            IconButton.outlined(
              key: const Key('previous-page'),
              onPressed: page == 0 ? null : () => _changePage(page - 1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            for (var index = first; index < last; index++)
              index == page
                  ? IconButton.filled(
                      key: Key('page-${index + 1}'),
                      onPressed: null,
                      icon: Text('${index + 1}'),
                    )
                  : IconButton.outlined(
                      key: Key('page-${index + 1}'),
                      onPressed: () => _changePage(index),
                      icon: Text('${index + 1}'),
                    ),
            IconButton.outlined(
              key: const Key('next-page'),
              onPressed: page >= pageCount - 1
                  ? null
                  : () => _changePage(page + 1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    );
  }

  void _changePage(int nextPage) {
    if (nextPage == currentPage) return;
    setState(() {
      currentPage = nextPage;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!inventoryScrollController.hasClients) return;
      inventoryScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }
}

class KitDetailsDialog extends StatefulWidget {
  const KitDetailsDialog({
    super.key,
    required this.kit,
    required this.kits,
    required this.products,
    this.inventory = const [],
    required this.availableQuantity,
    this.onMatchInventory,
    this.canMatchInventory = false,
    this.onAddShortage,
    required this.onBuild,
    this.canBuild = true,
    this.canDelete = false,
    this.onDelete,
    this.buildDisabledReason,
  });

  final KitRecord kit;
  final List<KitRecord> kits;
  final List<CatalogProduct> products;
  final List<InventoryItem> inventory;
  final double Function(String productId, String name) availableQuantity;
  final KitRecord Function(KitRecord kit, int lineIndex, InventoryItem item)?
  onMatchInventory;
  final bool canMatchInventory;
  final void Function(KitRecord kit, KitBomEntry line, double missing)?
  onAddShortage;
  final ValueChanged<KitRecord> onBuild;
  final bool canBuild;
  final bool canDelete;
  final Future<bool> Function(KitRecord kit)? onDelete;
  final String? buildDisabledReason;

  @override
  State<KitDetailsDialog> createState() => _KitDetailsDialogState();
}

class _KitDetailsDialogState extends State<KitDetailsDialog> {
  late KitRecord kit = widget.kit;
  List<KitRecord> get kits => widget.kits;
  List<CatalogProduct> get products => widget.products;
  List<InventoryItem> get inventory => widget.inventory;
  double Function(String productId, String name) get availableQuantity =>
      widget.availableQuantity;
  ValueChanged<KitRecord> get onBuild => widget.onBuild;
  bool get canBuild => widget.canBuild;
  bool get canDelete => widget.canDelete;
  Future<bool> Function(KitRecord kit)? get onDelete => widget.onDelete;
  String? get buildDisabledReason => widget.buildDisabledReason;

  String _lineName(KitBomEntry line) =>
      line.name ??
      products
          .where((product) => product.id == line.productId)
          .firstOrNull
          ?.name ??
      kits.where((kit) => kit.id == line.productId).firstOrNull?.name ??
      'Missing item';

  Map<int, _LineStockStatus> _stockStatus() {
    final reserved = <String, double>{};
    final result = <int, _LineStockStatus>{};
    for (var index = 0; index < kit.bom.length; index++) {
      final line = kit.bom[index];
      if (kits.any((candidate) => candidate.id == line.productId)) continue;
      final name = _lineName(line);
      final key = line.productId.isEmpty
          ? 'name:${_normalizedStockName(name)}'
          : 'product:${line.productId}';
      final totalAvailable = availableQuantity(line.productId, name);
      final remaining = (totalAvailable - (reserved[key] ?? 0)).clamp(
        0,
        line.quantity,
      );
      reserved[key] = (reserved[key] ?? 0) + line.quantity;
      result[index] = _LineStockStatus(
        available: remaining.toDouble(),
        missing: (line.quantity - remaining).clamp(0, line.quantity).toDouble(),
      );
    }
    return result;
  }

  Future<void> _showSources(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Kit sources'),
      content: SizedBox(
        width: 580,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: kit.sourceUrls.length,
          itemBuilder: (_, index) => ListTile(
            leading: const Icon(Icons.link_rounded),
            title: Text(
              kit.sourceUrls[index],
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => launchUrl(
              Uri.parse(kit.sourceUrls[index]),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  int _inventoryMatchScore(InventoryItem item, String targetName) {
    final target = _normalizedStockName(targetName);
    final candidate = _normalizedStockName(item.name);
    if (candidate == target) return 10000;
    var score = 0;
    if (candidate.contains(target) || target.contains(candidate)) score += 4000;
    final targetTokens = targetName
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length > 1)
        .toSet();
    final candidateText = [
      item.name,
      item.typeLabel,
      item.materialName,
      item.brand,
      item.vendor,
    ].join(' ').toLowerCase();
    score += targetTokens.where(candidateText.contains).length * 300;
    return score;
  }

  Future<void> _matchBomLine(BuildContext context, int lineIndex) async {
    final line = kit.bom[lineIndex];
    final targetName = _lineName(line);
    var query = '';
    final selected = await showDialog<InventoryItem>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final needle = _normalizedStockName(query);
          final matches =
              inventory.where((item) {
                if (item.archived) return false;
                if (needle.isEmpty) return true;
                return _normalizedStockName(
                  '${item.name} ${item.typeLabel} ${item.materialName} ${item.brand} ${item.vendor}',
                ).contains(needle);
              }).toList()..sort((left, right) {
                final byScore = _inventoryMatchScore(
                  right,
                  targetName,
                ).compareTo(_inventoryMatchScore(left, targetName));
                return byScore != 0 ? byScore : left.name.compareTo(right.name);
              });
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.link_rounded),
                SizedBox(width: 10),
                Expanded(child: Text('Match BOM item')),
              ],
            ),
            content: SizedBox(
              width: 560,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    targetName,
                    key: const Key('bom-match-source-name'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Required ${_formatBomQuantity(line.quantity)} · ${line.section}',
                    style: const TextStyle(color: Color(0xff929aac)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('bom-match-search'),
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      labelText: 'Search existing inventory',
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    query.trim().isEmpty ? 'SUGGESTED MATCHES' : 'MATCHES',
                    style: const TextStyle(
                      color: Color(0xff929aac),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: matches.isEmpty
                        ? const Center(
                            child: Text(
                              'No inventory items match this search.',
                            ),
                          )
                        : ListView.builder(
                            key: const Key('bom-match-results'),
                            itemCount: matches.length,
                            itemBuilder: (context, index) {
                              final item = matches[index];
                              final directlyLinked =
                                  item.id == line.productId ||
                                  item.catalogProductId == line.productId;
                              return ListTile(
                                key: Key('bom-match-item-${item.id}'),
                                leading: Icon(item.icon),
                                title: Text(item.name),
                                subtitle: Text(
                                  '${item.typeLabel}${item.materialName.isEmpty ? '' : ' · ${item.materialName}'} · ${_formatBomQuantity(item.quantity)} available',
                                ),
                                trailing: directlyLinked
                                    ? const Icon(Icons.link_rounded)
                                    : const Icon(Icons.chevron_right_rounded),
                                onTap: () =>
                                    Navigator.of(dialogContext).pop(item),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      kit = widget.onMatchInventory!(kit, lineIndex, selected);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stock = _stockStatus();
    final compact = MediaQuery.sizeOf(context).width < 600;

    Widget identity() => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.square(
            dimension: 44,
            child: kit.imageBytes == null
                ? ColoredBox(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: .13),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : Image.memory(kit.imageBytes!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kit.name,
                key: const Key('kit-details-title'),
                style: TextStyle(
                  fontSize: compact ? 20 : 24,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${kit.bom.length} BOM items',
                style: const TextStyle(color: Color(0xff929aac)),
              ),
            ],
          ),
        ),
      ],
    );

    Widget buildButton({bool expand = false}) {
      final button = Tooltip(
        message: canBuild
            ? 'Create a new build'
            : buildDisabledReason ?? 'You cannot create builds.',
        child: FilledButton.icon(
          key: const Key('build-kit'),
          onPressed: canBuild ? () => onBuild(kit) : null,
          icon: const Icon(Icons.construction_rounded),
          label: const Text('Build'),
        ),
      );
      return expand ? Expanded(child: button) : button;
    }

    Widget sourceButton() => IconButton(
      key: const Key('kit-sources'),
      tooltip: 'Kit sources',
      onPressed: () => _showSources(context),
      icon: const Icon(Icons.link_rounded),
    );

    Widget deleteButton() => IconButton(
      key: const Key('delete-kit'),
      tooltip: 'Delete kit',
      onPressed: () async {
        final deleted = await onDelete!(kit);
        if (deleted && context.mounted) Navigator.of(context).pop();
      },
      icon: const Icon(Icons.delete_outline_rounded),
    );

    Widget closeButton() => IconButton(
      tooltip: 'Close kit',
      onPressed: () => Navigator.of(context).pop(),
      icon: const Icon(Icons.close_rounded),
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 860),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 24,
                compact ? 14 : 20,
                compact ? 8 : 14,
                14,
              ),
              child: compact
                  ? Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: identity()),
                            closeButton(),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            buildButton(expand: true),
                            if (kit.sourceUrls.isNotEmpty) sourceButton(),
                            if (canDelete && onDelete != null) deleteButton(),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: identity()),
                        buildButton(),
                        const SizedBox(width: 8),
                        if (kit.sourceUrls.isNotEmpty) ...[
                          sourceButton(),
                          const SizedBox(width: 4),
                        ],
                        if (canDelete && onDelete != null) ...[
                          deleteButton(),
                          const SizedBox(width: 4),
                        ],
                        closeButton(),
                      ],
                    ),
            ),
            if (!canBuild)
              Container(
                key: const Key('build-disabled-reason'),
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xff332817),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xffa8782a)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: Color(0xffffc15c),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        buildDisabledReason ?? 'You cannot create builds.',
                        style: const TextStyle(color: Color(0xffffd79a)),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            if (kit.bom.isEmpty)
              const Expanded(
                child: Center(child: Text('This kit has no BOM items.')),
              )
            else
              Expanded(
                child: ListView.separated(
                  key: const Key('kit-details-list'),
                  padding: const EdgeInsets.all(10),
                  itemCount: kit.bom.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final line = kit.bom[index];
                    final lineStock = stock[index];
                    final missing = lineStock?.isMissing ?? false;
                    final nestedKit = kits
                        .where((candidate) => candidate.id == line.productId)
                        .firstOrNull;
                    final matchedInventory = inventory
                        .where(
                          (candidate) =>
                              candidate.id == line.productId ||
                              candidate.catalogProductId == line.productId,
                        )
                        .firstOrNull;
                    final duplicate =
                        kit.bom
                            .where(
                              (candidate) =>
                                  candidate.productId == line.productId,
                            )
                            .length >
                        1;
                    final leading = Icon(
                      missing
                          ? Icons.error_outline_rounded
                          : nestedKit == null
                          ? Icons.inventory_2_outlined
                          : Icons.account_tree_outlined,
                      color: missing
                          ? const Color(0xffff7b8e)
                          : nestedKit == null
                          ? const Color(0xff929aac)
                          : Theme.of(context).colorScheme.primary,
                    );
                    final title = Text(
                      _lineName(line),
                      key: Key('kit-line-title-$index'),
                    );
                    final subtitle = nestedKit == null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (line.section != 'Unassigned')
                                Text(line.section),
                              if (matchedInventory != null)
                                Text(
                                  'Matched to ${matchedInventory.name}',
                                  key: Key('kit-match-label-$index'),
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              Text(
                                'Required ${_formatBomQuantity(line.quantity)} · Available ${_formatBomQuantity(lineStock?.available ?? 0)}${missing ? ' · Missing ${_formatBomQuantity(lineStock!.missing)}' : ''}',
                                key: Key('kit-stock-$index'),
                                style: TextStyle(
                                  color: missing
                                      ? const Color(0xffff9cab)
                                      : const Color(0xff929aac),
                                  fontWeight: missing
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          )
                        : Text('Kit · Open BOM · ${line.section}');
                    final trailing = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '× ${_formatBomQuantity(line.quantity)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (nestedKit == null &&
                            missing &&
                            widget.onAddShortage != null) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            key: Key('shop-kit-line-$index'),
                            tooltip: 'Add shortage to shopping list',
                            onPressed: () => widget.onAddShortage!(
                              kit,
                              line,
                              lineStock!.missing,
                            ),
                            icon: const _ShoppingCartIcon(
                              key: Key('bom-shopping-cart-glyph'),
                            ),
                          ),
                        ],
                        if (nestedKit == null &&
                            missing &&
                            widget.canMatchInventory &&
                            widget.onMatchInventory != null) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            key: Key('match-kit-line-$index'),
                            tooltip: matchedInventory == null
                                ? 'Match to existing inventory'
                                : 'Change inventory match',
                            onPressed: () => _matchBomLine(context, index),
                            icon: const Icon(Icons.link_rounded),
                          ),
                        ],
                        if (nestedKit != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ],
                    );
                    final VoidCallback? openNested = nestedKit == null
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) => KitDetailsDialog(
                              kit: nestedKit,
                              kits: kits,
                              products: products,
                              inventory: inventory,
                              availableQuantity: availableQuantity,
                              onMatchInventory: widget.onMatchInventory,
                              canMatchInventory: widget.canMatchInventory,
                              onAddShortage: widget.onAddShortage,
                              onBuild: onBuild,
                              canBuild: canBuild,
                              buildDisabledReason: buildDisabledReason,
                            ),
                          );
                    return Card(
                      key: Key(
                        duplicate
                            ? 'kit-detail-line-${line.productId}-$index'
                            : 'kit-detail-line-${line.productId}',
                      ),
                      color: missing ? const Color(0xff351a22) : null,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: missing
                              ? const Color(0xffe45f72)
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: compact
                          ? InkWell(
                              onTap: openNested,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  8,
                                  8,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: leading,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [title, subtitle],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: trailing,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListTile(
                              leading: leading,
                              title: title,
                              subtitle: subtitle,
                              trailing: trailing,
                              onTap: openNested,
                            ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BuildQueueDialog extends StatefulWidget {
  const BuildQueueDialog({
    super.key,
    required this.build,
    required this.kit,
    required this.kits,
    required this.products,
    required this.availableQuantity,
    required this.onAdjust,
    required this.canUse,
    required this.canShare,
    required this.onSharedChanged,
    required this.onCompletedChanged,
  });
  final BuildRecord build;
  final KitRecord kit;
  final List<KitRecord> kits;
  final List<CatalogProduct> products;
  final double Function(String productId, String name) availableQuantity;
  final Future<bool> Function(String lineId, bool use) onAdjust;
  final bool canUse;
  final bool canShare;
  final Future<bool> Function(bool shared) onSharedChanged;
  final Future<bool> Function(bool completed) onCompletedChanged;

  @override
  State<BuildQueueDialog> createState() => _BuildQueueDialogState();
}

class _BuildQueueDialogState extends State<BuildQueueDialog>
    with SingleTickerProviderStateMixin {
  bool showKit = false;
  late final AnimationController completionCelebration = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void dispose() {
    completionCelebration.dispose();
    super.dispose();
  }

  String _kitLineName(KitBomEntry line) =>
      line.name ??
      widget.products
          .where((product) => product.id == line.productId)
          .firstOrNull
          ?.name ??
      widget.kits.where((kit) => kit.id == line.productId).firstOrNull?.name ??
      'Missing item';

  Map<String, _LineStockStatus> _stockStatus() {
    final reserved = <String, double>{};
    final result = <String, _LineStockStatus>{};
    for (final line in widget.build.lines) {
      final needed = (line.requiredQuantity - line.usedQuantity).clamp(
        0,
        line.requiredQuantity,
      );
      final key = line.productId.isEmpty
          ? 'name:${_normalizedStockName(line.name)}'
          : 'product:${line.productId}';
      final totalAvailable = widget.availableQuantity(
        line.productId,
        line.name,
      );
      final available = (totalAvailable - (reserved[key] ?? 0)).clamp(
        0,
        needed,
      );
      reserved[key] = (reserved[key] ?? 0) + needed;
      result[line.id] = _LineStockStatus(
        available: available.toDouble(),
        missing: (needed - available).clamp(0, needed).toDouble(),
      );
    }
    return result;
  }

  Map<int, _LineStockStatus> _kitStockStatus() {
    final reserved = <String, double>{};
    final result = <int, _LineStockStatus>{};
    for (var index = 0; index < widget.kit.bom.length; index++) {
      final line = widget.kit.bom[index];
      final name = _kitLineName(line);
      final key = line.productId.isEmpty
          ? 'name:${_normalizedStockName(name)}'
          : 'product:${line.productId}';
      final totalAvailable = widget.availableQuantity(line.productId, name);
      final available = (totalAvailable - (reserved[key] ?? 0)).clamp(
        0,
        line.quantity,
      );
      reserved[key] = (reserved[key] ?? 0) + line.quantity;
      result[index] = _LineStockStatus(
        available: available.toDouble(),
        missing: (line.quantity - available).clamp(0, line.quantity).toDouble(),
      );
    }
    return result;
  }

  bool get _allBuildLinesUsed => widget.build.lines.every(
    (line) => line.usedQuantity >= line.requiredQuantity,
  );

  void _celebrateCompletion() {
    completionCelebration.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<BuildLine>>{};
    for (final line in widget.build.lines) {
      grouped.putIfAbsent(line.section, () => []).add(line);
    }
    final allLinesUsed = _allBuildLinesUsed;
    final completed = widget.build.completedAt != null;
    final stock = _stockStatus();
    final kitStock = _kitStockStatus();
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final mobileHeight = math.min(
      MediaQuery.sizeOf(context).height * .88,
      math.max(
        430.0,
        250.0 + (widget.build.lines.length * 112) + (grouped.length * 58),
      ),
    );
    final queuePanel = Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(narrow ? 16 : 22, 16, 12, 12),
          child: _buildHeader(allLinesUsed, completed),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(narrow ? 12 : 16),
            children: [
              ...grouped.entries.map(
                (section) => _buildSection(section, stock),
              ),
            ],
          ),
        ),
      ],
    );
    final kitPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              if (narrow) ...[
                IconButton(
                  key: const Key('return-to-build-queue'),
                  onPressed: () => setState(() => showKit = false),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  widget.kit.name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: widget.kit.bom.length,
            itemBuilder: (context, index) {
              final line = widget.kit.bom[index];
              final name = _kitLineName(line);
              final lineStock = kitStock[index]!;
              final available = lineStock.available;
              final missing = lineStock.missing;
              return Card(
                color: missing > 0.0001 ? const Color(0xff351a22) : null,
                child: ListTile(
                  dense: true,
                  leading: missing > 0.0001
                      ? const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xffff7b8e),
                        )
                      : null,
                  title: Text(name),
                  subtitle: Text(
                    '${line.section}\nRequired ${_formatBomQuantity(line.quantity)} · Available ${_formatBomQuantity(available.clamp(0, line.quantity))}${missing > 0.0001 ? ' · Missing ${_formatBomQuantity(missing)}' : ''}',
                  ),
                  trailing: Text('× ${_formatBomQuantity(line.quantity)}'),
                ),
              );
            },
          ),
        ),
      ],
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 900),
            child: SizedBox(
              height: narrow ? mobileHeight : null,
              child: Row(
                children: [
                  if (!narrow || !showKit) Expanded(child: queuePanel),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: showKit
                        ? narrow
                              ? MediaQuery.sizeOf(context).width - 32
                              : 360
                        : 0,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      border: Border(
                        left: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: showKit ? kitPanel : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: completionCelebration,
                builder: (context, _) =>
                    completionCelebration.value == 0 ||
                        completionCelebration.isCompleted
                    ? const SizedBox.shrink()
                    : CustomPaint(
                        key: const Key('build-completion-confetti'),
                        painter: _BuildCompletionConfettiPainter(
                          completionCelebration.value,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool allLinesUsed, bool completed) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.build.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          Text(
            'Build queue · ${widget.build.createdBy}',
            style: const TextStyle(color: Color(0xff929aac)),
          ),
        ],
      );
      final actions = <Widget>[
        FilterChip(
          key: const Key('share-build'),
          selected: widget.build.shared,
          onSelected: widget.canShare
              ? (value) async {
                  if (await widget.onSharedChanged(value) && mounted) {
                    setState(() {});
                  }
                }
              : null,
          avatar: Icon(
            widget.build.shared
                ? Icons.groups_rounded
                : Icons.lock_outline_rounded,
            size: 18,
          ),
          label: Text(widget.build.shared ? 'Shared' : 'Unshared'),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          key: const Key('complete-build'),
          onPressed: widget.canUse && (completed || allLinesUsed)
              ? () async {
                  final completing = !completed;
                  if (await widget.onCompletedChanged(completing) && mounted) {
                    setState(() {});
                    if (completing) _celebrateCompletion();
                  }
                }
              : null,
          icon: Icon(completed ? Icons.replay_rounded : Icons.task_alt_rounded),
          label: Text(completed ? 'Reopen' : 'Complete'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: const Key('toggle-build-kit-panel'),
          onPressed: () => setState(() => showKit = !showKit),
          icon: Icon(
            showKit
                ? Icons.close_fullscreen_rounded
                : Icons.view_sidebar_outlined,
          ),
          label: Text(showKit ? 'Hide kit' : 'Full kit'),
        ),
      ];
      final close = IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close_rounded),
      );
      if (constraints.maxWidth < 720) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.construction_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(child: title),
                close,
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: actions.where((widget) => widget is! SizedBox).toList(),
            ),
          ],
        );
      }
      return Row(
        children: [
          Icon(
            Icons.construction_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(child: title),
          ...actions,
          const SizedBox(width: 8),
          close,
        ],
      );
    },
  );

  Widget _buildSection(
    MapEntry<String, List<BuildLine>> section,
    Map<String, _LineStockStatus> stock,
  ) {
    final used = section.value.fold<double>(
      0,
      (total, line) => total + line.usedQuantity,
    );
    final required = section.value.fold<double>(
      0,
      (total, line) => total + line.requiredQuantity,
    );
    final complete = used >= required;
    return Container(
      key: Key('build-section-${section.key}'),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xff131824),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: complete
              ? const Color(0xff42d8c7).withValues(alpha: .72)
              : const Color(0xff5f527f),
          width: 1.3,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
            child: Row(
              children: [
                Icon(
                  complete
                      ? Icons.check_circle_rounded
                      : Icons.account_tree_outlined,
                  color: complete
                      ? const Color(0xff42d8c7)
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.key.toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                Text(
                  '${_formatBomQuantity(used)} / ${_formatBomQuantity(required)}',
                  style: const TextStyle(
                    color: Color(0xff929aac),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: section.value
                  .map((line) => _buildLine(line, stock[line.id]!))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(BuildLine line, _LineStockStatus stock) {
    final complete = line.usedQuantity >= line.requiredQuantity;
    final multiple = line.requiredQuantity > 1;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: complete ? .42 : 1,
      child: Card(
        key: Key('build-stock-${line.id}'),
        color: stock.isMissing ? const Color(0xff351a22) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: stock.isMissing
                ? const Color(0xffe45f72)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 560;
            final statusIcon = Icon(
              complete
                  ? Icons.check_circle_rounded
                  : stock.isMissing
                  ? Icons.error_outline_rounded
                  : Icons.radio_button_unchecked,
              color: complete
                  ? const Color(0xff42d8c7)
                  : stock.isMissing
                  ? const Color(0xffff7b8e)
                  : null,
            );
            final details = Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        '${_formatBomQuantity(line.usedQuantity)} / ${_formatBomQuantity(line.requiredQuantity)} used · ${_formatBomQuantity(stock.available)} available',
                  ),
                  if (stock.isMissing)
                    TextSpan(
                      text: ' · ${_formatBomQuantity(stock.missing)} missing',
                      style: const TextStyle(
                        color: Color(0xffff9cab),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            );
            final actions = Wrap(
              spacing: 6,
              children: [
                OutlinedButton(
                  onPressed:
                      !widget.canUse ||
                          widget.build.completedAt != null ||
                          line.usedQuantity <= 0
                      ? null
                      : () async {
                          if (await widget.onAdjust(line.id, false) &&
                              mounted) {
                            setState(() {});
                          }
                        },
                  child: const Text('Unuse'),
                ),
                FilledButton(
                  onPressed:
                      !widget.canUse ||
                          widget.build.completedAt != null ||
                          complete ||
                          stock.available <= 0
                      ? null
                      : () async {
                          final wasFullyUsed = _allBuildLinesUsed;
                          if (await widget.onAdjust(line.id, true) && mounted) {
                            setState(() {});
                            if (!wasFullyUsed && _allBuildLinesUsed) {
                              _celebrateCompletion();
                            }
                          }
                        },
                  child: Text(multiple ? 'Use 1' : 'Use'),
                ),
              ],
            );
            if (narrow) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        statusIcon,
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              details,
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                ),
              );
            }
            return ListTile(
              leading: statusIcon,
              title: Text(line.name),
              subtitle: details,
              trailing: actions,
            );
          },
        ),
      ),
    );
  }
}

class _BuildCompletionConfettiPainter extends CustomPainter {
  const _BuildCompletionConfettiPainter(this.progress);

  final double progress;

  static const colors = [
    Color(0xffa987ff),
    Color(0xff45d2bd),
    Color(0xffffc857),
    Color(0xffff6f91),
    Color(0xff58a6ff),
    Colors.white,
  ];

  double _noise(int seed) {
    final value = math.sin(seed * 12.9898) * 43758.5453;
    return value - value.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final time = Curves.easeOut.transform(progress);
    final fade = progress < .72 ? 1.0 : (1 - progress) / .28;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var index = 0; index < 96; index++) {
      final fromLeft = index.isEven;
      final horizontal = _noise(index * 5 + 1);
      final vertical = _noise(index * 5 + 2);
      final flutter = _noise(index * 5 + 3);
      final pieceWidth = 5.0 + (_noise(index * 5 + 4) * 8);
      final pieceHeight = 3.0 + (_noise(index * 5 + 5) * 7);
      final direction = fromLeft ? 1.0 : -1.0;
      final origin = Offset(fromLeft ? 12 : size.width - 12, size.height - 8);
      final velocityX = size.width * (.12 + horizontal * .82) * direction;
      final velocityY = size.height * (.72 + vertical * .62);
      final gravity = size.height * 1.18;
      final position = Offset(
        origin.dx + velocityX * time,
        origin.dy - velocityY * time + gravity * time * time,
      );
      if (position.dx < -20 || position.dx > size.width + 20) continue;

      paint.color = colors[index % colors.length].withValues(
        alpha: fade.clamp(0, 1),
      );
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate((time * (5 + flutter * 12)) * direction);
      if (index % 4 == 0) {
        canvas.drawCircle(Offset.zero, pieceWidth * .48, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: pieceWidth,
              height: pieceHeight,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BuildCompletionConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class CatalogManagerDialog extends StatefulWidget {
  const CatalogManagerDialog({
    super.key,
    required this.vendors,
    required this.brands,
    required this.spoolTypes,
    this.materials = starterMaterials,
    required this.customItemTypes,
    required this.typeLabelOverrides,
    required this.typeIconOverrides,
    required this.typeDepletionSettings,
    required this.typeStatusSettings,
    required this.deletedTypeKeys,
    required this.customTypeUsageCounts,
    required this.products,
    required this.inventoryItems,
    required this.machineTypes,
    required this.machines,
    required this.kits,
    required this.onVendorAdded,
    required this.onBrandAdded,
    required this.onSpoolTypeAdded,
    this.onMaterialAdded,
    this.onMaterialUpdated,
    this.onMaterialDeleted,
    required this.onCustomItemTypeAdded,
    required this.onCustomItemTypeUpdated,
    required this.onCustomItemTypeDeleted,
    required this.onBuiltInTypeRenamed,
    required this.onBuiltInTypeIconChanged,
    required this.onBuiltInTypeDepletionChanged,
    required this.onBuiltInTypeStatusChanged,
    required this.onBuiltInTypeDeleted,
    required this.onBuiltInTypeRestored,
    required this.canDeleteCustomItemTypes,
    required this.onProductAdded,
    required this.onMachineTypeAdded,
    required this.onMachineAdded,
    required this.onMachineUpdated,
    required this.onKitAdded,
    required this.onKitUpdated,
    this.onImportKitPackage,
    this.initialKitId,
    this.initialKitBom,
  });
  final List<VendorRecord> vendors;
  final List<BrandRecord> brands;
  final List<SpoolTypeRecord> spoolTypes;
  final List<MaterialRecord> materials;
  final List<CustomItemTypeRecord> customItemTypes;
  final Map<String, String> typeLabelOverrides;
  final Map<String, String> typeIconOverrides;
  final Map<String, bool> typeDepletionSettings;
  final Map<String, bool> typeStatusSettings;
  final Set<String> deletedTypeKeys;
  final Map<String, int> customTypeUsageCounts;
  final List<CatalogProduct> products;
  final List<InventoryItem> inventoryItems;
  final List<MachineTypeRecord> machineTypes;
  final List<MachineRecord> machines;
  final List<KitRecord> kits;
  final ValueChanged<VendorRecord> onVendorAdded;
  final ValueChanged<BrandRecord> onBrandAdded;
  final ValueChanged<SpoolTypeRecord> onSpoolTypeAdded;
  final ValueChanged<MaterialRecord>? onMaterialAdded;
  final ValueChanged<MaterialRecord>? onMaterialUpdated;
  final ValueChanged<MaterialRecord>? onMaterialDeleted;
  final ValueChanged<CustomItemTypeRecord> onCustomItemTypeAdded;
  final ValueChanged<CustomItemTypeRecord> onCustomItemTypeUpdated;
  final ValueChanged<CustomItemTypeRecord> onCustomItemTypeDeleted;
  final ValueChanged<MapEntry<String, String>> onBuiltInTypeRenamed;
  final ValueChanged<MapEntry<String, String>> onBuiltInTypeIconChanged;
  final ValueChanged<MapEntry<String, bool>> onBuiltInTypeDepletionChanged;
  final ValueChanged<MapEntry<String, bool>> onBuiltInTypeStatusChanged;
  final ValueChanged<String> onBuiltInTypeDeleted;
  final ValueChanged<String> onBuiltInTypeRestored;
  final bool canDeleteCustomItemTypes;
  final ValueChanged<CatalogProduct> onProductAdded;
  final ValueChanged<MachineTypeRecord> onMachineTypeAdded;
  final ValueChanged<MachineRecord> onMachineAdded;
  final ValueChanged<MachineRecord> onMachineUpdated;
  final ValueChanged<KitRecord> onKitAdded;
  final ValueChanged<KitRecord> onKitUpdated;
  final Future<bool> Function()? onImportKitPackage;
  final String? initialKitId;
  final List<KitBomEntry>? initialKitBom;

  @override
  State<CatalogManagerDialog> createState() => _CatalogManagerDialogState();
}

class _CatalogManagerDialogState extends State<CatalogManagerDialog> {
  final vendorName = TextEditingController();
  final brandName = TextEditingController();
  final spoolLabel = TextEditingController();
  final spoolWeightGrams = TextEditingController();
  final materialName = TextEditingController();
  final customTypeName = TextEditingController();
  final customTypeFields = TextEditingController();
  final productName = TextEditingController();
  final productCost = TextEditingController();
  final productDrying = TextEditingController();
  final printing = TextEditingController();
  final drying = TextEditingController();
  final storage = TextEditingController();
  final machineTypeName = TextEditingController();
  final machineName = TextEditingController();
  final machineModel = TextEditingController();
  final machineAddress = TextEditingController();
  final kitName = TextEditingController();
  String? kitNameError;
  late final List<VendorRecord> vendors = [...widget.vendors];
  late final List<BrandRecord> brands = [...widget.brands];
  late final List<SpoolTypeRecord> spoolTypes = [...widget.spoolTypes];
  late final List<MaterialRecord> materials = [...widget.materials];
  late final List<CustomItemTypeRecord> customItemTypes = [
    ...widget.customItemTypes,
  ];
  late final Map<String, String> typeLabelOverrides = {
    ...widget.typeLabelOverrides,
  };
  late final Map<String, String> typeIconOverrides = {
    ...widget.typeIconOverrides,
  };
  late final Map<String, bool> typeDepletionSettings = {
    ...widget.typeDepletionSettings,
  };
  late final Map<String, bool> typeStatusSettings = {
    ...widget.typeStatusSettings,
  };
  late final Set<String> deletedTypeKeys = {...widget.deletedTypeKeys};
  late final List<CatalogProduct> products = [...widget.products];
  late final List<MachineTypeRecord> machineTypes = [...widget.machineTypes];
  late final List<MachineRecord> machines = [...widget.machines];
  late final List<KitRecord> kits = [...widget.kits];
  final List<KitBomEntry> draftBom = [];
  final List<String> draftSections = [];
  String? editingKitId;
  String? machineTypeParentId;
  String? selectedMachineTypeId;
  final Set<String> selectedMachineKitIds = {};
  String? editingMachineId;
  String? brandVendorId;
  String? productBrandId;
  final Set<InventoryType> brandCategories = {};
  final Set<InventoryType> vendorBrandCategories = {};
  InventoryType? productCategory;
  bool vendorAlsoBrand = false;
  bool kitSectionExpanded = false;
  bool loadingInitialKit = false;
  Uint8List? vendorLogo;
  Uint8List? brandLogo;
  Uint8List? productImage;
  Uint8List? machineImage;
  Uint8List? kitImage;
  String customTypeIconKey = 'tune';
  bool customTypeCanMarkDepleted = false;
  bool customTypeShowsStatus = false;
  String customTypeLinkKey = '';
  String materialTypeKey = 'type:filament';

  bool get kitOnly =>
      widget.initialKitId != null || widget.initialKitBom != null;

  List<({String key, String defaultLabel, IconData icon})>
  get _allBuiltInCatalogTypes => [
    for (final type in CatalogViewFilter.values)
      (
        key: _catalogViewDefinitionKey(type),
        defaultLabel: _defaultCatalogViewLabel(type),
        icon: switch (type) {
          CatalogViewFilter.kits => Icons.inventory_2_outlined,
          CatalogViewFilter.builds => Icons.construction_rounded,
          CatalogViewFilter.machines => Icons.precision_manufacturing_outlined,
          CatalogViewFilter.printers => Icons.print_outlined,
          CatalogViewFilter.tools => Icons.handyman_outlined,
        },
      ),
    for (final type in InventoryType.values.where(
      (type) => type != InventoryType.custom,
    ))
      (
        key: _inventoryTypeDefinitionKey(type),
        defaultLabel: _typeLabel(type),
        icon: _typeIcon(type),
      ),
  ];

  List<({String key, String defaultLabel, IconData icon})>
  get _builtInCatalogTypes => _allBuiltInCatalogTypes
      .where((type) => !deletedTypeKeys.contains(type.key))
      .toList();

  List<({String key, String defaultLabel, IconData icon})>
  get _deletedCatalogTypes => _allBuiltInCatalogTypes
      .where(
        (type) =>
            type.key.startsWith('catalog:') &&
            deletedTypeKeys.contains(type.key),
      )
      .toList();

  String _builtInTypeLabel(
    ({String key, String defaultLabel, IconData icon}) type,
  ) => typeLabelOverrides[type.key] ?? type.defaultLabel;

  String _builtInTypeIconKey(
    ({String key, String defaultLabel, IconData icon}) type,
  ) => typeIconOverrides[type.key] ?? _iconKeyFor(type.icon);

  String _catalogInventoryTypeLabel(InventoryType type) =>
      typeLabelOverrides[_inventoryTypeDefinitionKey(type)] ?? _typeLabel(type);

  IconData _catalogInventoryItemIcon(InventoryItem item) {
    if (item.type != InventoryType.custom) {
      return _iconFromKey(
        typeIconOverrides[_inventoryTypeDefinitionKey(item.type)],
        _typeIcon(item.type),
      );
    }
    final customType = customItemTypes
        .where((candidate) => candidate.id == item.customTypeId)
        .firstOrNull;
    return _iconFromKey(customType?.iconKey, Icons.tune_rounded);
  }

  @override
  void initState() {
    super.initState();
    if (!kitOnly) draftSections.add('Main component');
    if (kitOnly) {
      kitSectionExpanded = true;
      if (widget.initialKitBom != null) {
        draftBom.addAll(
          widget.initialKitBom!.map(
            (line) => KitBomEntry(
              id: line.id,
              productId: line.productId,
              quantity: line.quantity,
              name: line.name,
              section:
                  line.section.trim().isEmpty || line.section == 'Unassigned'
                  ? 'Main component'
                  : line.section,
            ),
          ),
        );
        draftSections.addAll(
          widget.initialKitBom!
              .map((line) => line.section.trim())
              .where((section) => section.isNotEmpty)
              .toSet(),
        );
        if (draftSections.isEmpty) draftSections.add('Main component');
        return;
      }
      loadingInitialKit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (!mounted) return;
        final initialKit = widget.kits
            .where((kit) => kit.id == widget.initialKitId)
            .firstOrNull;
        setState(() {
          if (initialKit != null) {
            editingKitId = initialKit.id;
            kitName.text = initialKit.name;
            draftBom.addAll(initialKit.bom.map(_withDefaultKitSection));
            draftSections.addAll(_sectionsForKit(initialKit));
          }
          loadingInitialKit = false;
        });
      });
    }
  }

  @override
  void dispose() {
    vendorName.dispose();
    brandName.dispose();
    spoolLabel.dispose();
    spoolWeightGrams.dispose();
    materialName.dispose();
    customTypeName.dispose();
    customTypeFields.dispose();
    productName.dispose();
    productCost.dispose();
    productDrying.dispose();
    printing.dispose();
    drying.dispose();
    storage.dispose();
    machineTypeName.dispose();
    machineName.dispose();
    machineModel.dispose();
    machineAddress.dispose();
    kitName.dispose();
    super.dispose();
  }

  Widget _catalogFormCard({
    required String title,
    required String description,
    required IconData icon,
    required List<Widget> children,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xff929aac),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );

  Widget _catalogRecordCard({
    required Uint8List? logo,
    required IconData fallbackIcon,
    required String name,
    required String details,
    Widget? badge,
  }) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xff171c27),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xff0d1119),
            borderRadius: BorderRadius.circular(11),
          ),
          child: logo == null
              ? Icon(fallbackIcon, color: Theme.of(context).colorScheme.primary)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.memory(logo, fit: BoxFit.contain),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                details,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xff929aac), fontSize: 12),
              ),
            ],
          ),
        ),
        if (badge != null) ...[const SizedBox(width: 10), badge],
      ],
    ),
  );

  Widget _vendorCatalogSection() => ExpansionTile(
    key: const Key('catalog-vendors-section'),
    leading: const Icon(Icons.storefront_outlined),
    title: Text('Vendors (${vendors.length})'),
    subtitle: const Text('Stores and suppliers you purchase from'),
    childrenPadding: const EdgeInsets.fromLTRB(0, 8, 0, 18),
    children: [
      _catalogFormCard(
        title: 'Add vendor',
        description: 'Create a store or supplier used when sourcing products.',
        icon: Icons.add_business_outlined,
        children: [
          TextField(
            key: const Key('new-vendor-name'),
            controller: vendorName,
            decoration: const InputDecoration(
              labelText: 'Vendor name',
              hintText: 'Printed Solid',
            ),
          ),
          const SizedBox(height: 12),
          _ImagePickerButton(
            key: const Key('vendor-logo-picker'),
            label: 'Vendor logo',
            bytes: vendorLogo,
            fallbackIcon: Icons.storefront_outlined,
            onChanged: (bytes) => setState(() => vendorLogo = bytes),
          ),
          const SizedBox(height: 6),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const Key('vendor-is-brand'),
              contentPadding: EdgeInsets.zero,
              title: const Text('This vendor also makes products'),
              subtitle: const Text(
                'Create a matching brand with the same name and logo.',
              ),
              value: vendorAlsoBrand,
              onChanged: (value) => setState(() {
                vendorAlsoBrand = value;
                if (!value) vendorBrandCategories.clear();
              }),
            ),
          ),
          if (vendorAlsoBrand) ...[
            const Text(
              'PRODUCT TYPES · SELECT AT LEAST ONE',
              style: TextStyle(
                color: Color(0xff929aac),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .9,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: InventoryType.values
                  .where((type) => type != InventoryType.custom)
                  .map(
                    (category) => FilterChip(
                      key: Key('vendor-brand-category-${category.name}'),
                      label: Text(_catalogInventoryTypeLabel(category)),
                      selected: vendorBrandCategories.contains(category),
                      onSelected: (selected) => setState(() {
                        selected
                            ? vendorBrandCategories.add(category)
                            : vendorBrandCategories.remove(category);
                      }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('add-vendor'),
              onPressed: _addVendor,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add vendor'),
            ),
          ),
        ],
      ),
      const Divider(height: 28),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'EXISTING VENDORS',
          style: TextStyle(
            color: const Color(0xff929aac),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (vendors.isEmpty)
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'No vendors yet.',
            style: TextStyle(color: Color(0xff929aac)),
          ),
        )
      else
        ...vendors.map(
          (vendor) => Padding(
            key: Key('vendor-summary-${vendor.id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: _catalogRecordCard(
              logo: vendor.logoBytes,
              fallbackIcon: Icons.storefront_outlined,
              name: vendor.name,
              details: vendor.isBrand
                  ? 'Purchase source · also a product brand'
                  : 'Purchase source',
              badge: vendor.isBrand
                  ? const Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('Also a brand'),
                    )
                  : null,
            ),
          ),
        ),
    ],
  );

  Widget _brandCatalogSection() => ExpansionTile(
    key: const Key('catalog-brands-section'),
    leading: const Icon(Icons.sell_outlined),
    title: Text('Brands (${brands.length})'),
    subtitle: const Text('Product makers and the types they manufacture'),
    childrenPadding: const EdgeInsets.fromLTRB(0, 8, 0, 18),
    children: [
      _catalogFormCard(
        title: 'Add brand',
        description:
            'Create a maker, then connect it to a vendor and product types.',
        icon: Icons.new_label_outlined,
        children: [
          TextField(
            key: const Key('new-brand-name'),
            controller: brandName,
            decoration: const InputDecoration(labelText: 'Brand name'),
          ),
          const SizedBox(height: 12),
          _ImagePickerButton(
            key: const Key('brand-logo-picker'),
            label: 'Brand logo',
            bytes: brandLogo,
            fallbackIcon: Icons.sell_outlined,
            onChanged: (bytes) => setState(() => brandLogo = bytes),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('brand-vendor'),
            initialValue: brandVendorId,
            decoration: const InputDecoration(
              labelText: 'Purchased from',
              helperText: 'Choose the vendor that sells this brand.',
            ),
            items: vendors
                .map(
                  (vendor) => DropdownMenuItem(
                    value: vendor.id,
                    child: Text(vendor.name),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => brandVendorId = value),
          ),
          const SizedBox(height: 14),
          const Text(
            'PRODUCT TYPES · SELECT AT LEAST ONE',
            style: TextStyle(
              color: Color(0xff929aac),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: .9,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: InventoryType.values
                .where((type) => type != InventoryType.custom)
                .map(
                  (category) => FilterChip(
                    key: Key('brand-category-${category.name}'),
                    label: Text(_catalogInventoryTypeLabel(category)),
                    selected: brandCategories.contains(category),
                    onSelected: (selected) => setState(() {
                      selected
                          ? brandCategories.add(category)
                          : brandCategories.remove(category);
                    }),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('add-brand'),
              onPressed: _addBrand,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add brand'),
            ),
          ),
        ],
      ),
      const Divider(height: 28),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'EXISTING BRANDS',
          style: TextStyle(
            color: const Color(0xff929aac),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (brands.isEmpty)
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'No brands yet.',
            style: TextStyle(color: Color(0xff929aac)),
          ),
        )
      else
        ...brands.map((brand) {
          final linkedVendors = vendors
              .where((vendor) => brand.vendorIds.contains(vendor.id))
              .map((vendor) => vendor.name)
              .join(', ');
          final categoryLabels = brand.categories
              .map(_catalogInventoryTypeLabel)
              .join(', ');
          return Padding(
            key: Key('brand-summary-${brand.id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: _catalogRecordCard(
              logo: brand.logoBytes,
              fallbackIcon: Icons.sell_outlined,
              name: brand.name,
              details: [
                if (linkedVendors.isNotEmpty) 'Sold by $linkedVendors',
                if (categoryLabels.isNotEmpty) 'Makes $categoryLabels',
              ].join(' · '),
            ),
          );
        }),
    ],
  );

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 860),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kitOnly ? 'Kit / BOM' : 'Product catalog',
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        kitOnly
                            ? editingKitId == null
                                  ? 'Create a kit and define its bill of materials'
                                  : 'Edit this kit and its bill of materials'
                            : 'Sources, makers, and reusable product definitions',
                        style: const TextStyle(color: Color(0xff929aac)),
                      ),
                    ],
                  ),
                ),
                if (!kitOnly &&
                    (Platform.isLinux ||
                        Platform.isWindows ||
                        Platform.isMacOS)) ...[
                  OutlinedButton.icon(
                    key: const Key('import-kit-package'),
                    onPressed: widget.onImportKitPackage == null
                        ? null
                        : () async {
                            final imported = await widget.onImportKitPackage!();
                            if (imported && context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Import kit'),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: kitOnly
                ? loadingInitialKit
                      ? const _KitBomLoadingState()
                      : _kitOnlyBomList()
                : ListView(
                    key: const Key('catalog-list'),
                    padding: const EdgeInsets.all(18),
                    children: () {
                      final sections = <String, Widget>{
                        'types': _itemTypesSection(),
                        'vendors': _vendorCatalogSection(),
                        'brands': _brandCatalogSection(),
                        'spools': ExpansionTile(
                          key: const Key('catalog-spool-types-section'),
                          leading: const Icon(Icons.donut_large_rounded),
                          title: Text('Spool sizes (${spoolTypes.length})'),
                          subtitle: const Text(
                            'Reusable filament package weights',
                          ),
                          children: [
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: const Key('new-spool-label'),
                                    controller: spoolLabel,
                                    decoration: const InputDecoration(
                                      labelText: 'Button label',
                                      hintText: '2.5 kg',
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 200,
                                  child: TextField(
                                    key: const Key('new-spool-weight'),
                                    controller: spoolWeightGrams,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Filament weight',
                                      suffixText: 'g',
                                    ),
                                  ),
                                ),
                                FilledButton(
                                  key: const Key('add-spool-type'),
                                  onPressed: _addSpoolType,
                                  child: const Text('Add'),
                                ),
                              ],
                            ),
                            const Divider(height: 28),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'EXISTING SPOOL SIZES',
                                style: TextStyle(
                                  color: Color(0xff929aac),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: spoolTypes
                                  .map(
                                    (spool) => Chip(
                                      key: Key('spool-summary-${spool.id}'),
                                      avatar: const Icon(
                                        Icons.scale_outlined,
                                        size: 18,
                                      ),
                                      label: Text(spool.label),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                        'machines': ExpansionTile(
                          key: const Key('catalog-machines-section'),
                          leading: const Icon(
                            Icons.precision_manufacturing_outlined,
                          ),
                          title: Text('Machines (${machines.length})'),
                          subtitle: const Text(
                            'Equipment and compatible machine types',
                          ),
                          children: [
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('new-machine-type-name'),
                              controller: machineTypeName,
                              decoration: const InputDecoration(
                                labelText: 'New machine type',
                                hintText: 'Printer, FDM, Heat Insert Press…',
                              ),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String?>(
                              key: const Key('machine-type-parent'),
                              initialValue: machineTypeParentId,
                              decoration: const InputDecoration(
                                labelText: 'Parent type (optional)',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('No parent'),
                                ),
                                ...machineTypes.map(
                                  (type) => DropdownMenuItem<String?>(
                                    value: type.id,
                                    child: Text(type.name),
                                  ),
                                ),
                              ],
                              onChanged: (value) =>
                                  setState(() => machineTypeParentId = value),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton(
                                key: const Key('add-machine-type'),
                                onPressed: _addMachineType,
                                child: const Text('Add type'),
                              ),
                            ),
                            const Divider(),
                            DropdownButtonFormField<String>(
                              key: const Key('machine-type'),
                              initialValue: selectedMachineTypeId,
                              decoration: const InputDecoration(
                                labelText: 'Machine type',
                              ),
                              items: machineTypes
                                  .map(
                                    (type) => DropdownMenuItem(
                                      value: type.id,
                                      child: Text(type.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => selectedMachineTypeId = value),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              key: const Key('new-machine-name'),
                              controller: machineName,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: machineModel,
                              decoration: const InputDecoration(
                                labelText: 'Model',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: machineAddress,
                              decoration: const InputDecoration(
                                labelText: 'Hostname / IP',
                              ),
                            ),
                            const SizedBox(height: 10),
                            _ImagePickerButton(
                              key: const Key('machine-image-picker'),
                              label: 'Machine image',
                              bytes: machineImage,
                              fallbackIcon:
                                  Icons.precision_manufacturing_outlined,
                              onChanged: (bytes) =>
                                  setState(() => machineImage = bytes),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Associated kits',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (kits.isEmpty)
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Define a kit below before associating it.',
                                  style: TextStyle(color: Color(0xff929aac)),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: kits
                                    .map(
                                      (kit) => FilterChip(
                                        key: Key('machine-kit-${kit.id}'),
                                        label: Text(kit.name),
                                        selected: selectedMachineKitIds
                                            .contains(kit.id),
                                        onSelected: (selected) => setState(() {
                                          selected
                                              ? selectedMachineKitIds.add(
                                                  kit.id,
                                                )
                                              : selectedMachineKitIds.remove(
                                                  kit.id,
                                                );
                                        }),
                                      ),
                                    )
                                    .toList(),
                              ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  if (editingMachineId != null)
                                    TextButton(
                                      key: const Key('cancel-machine-edit'),
                                      onPressed: _clearMachineEditor,
                                      child: const Text('Cancel'),
                                    ),
                                  FilledButton.icon(
                                    key: const Key('add-machine'),
                                    onPressed: _addMachine,
                                    icon: Icon(
                                      editingMachineId == null
                                          ? Icons.add_rounded
                                          : Icons.save_outlined,
                                    ),
                                    label: Text(
                                      editingMachineId == null
                                          ? 'Add machine'
                                          : 'Update machine',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 28),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'EXISTING MACHINES',
                                style: TextStyle(
                                  color: Color(0xff929aac),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Column(
                              children: machines.map((machine) {
                                final type = machineTypes
                                    .where(
                                      (value) => value.id == machine.typeId,
                                    )
                                    .firstOrNull;
                                final kitNames = kits
                                    .where(
                                      (kit) => machine.kitIds.contains(kit.id),
                                    )
                                    .map((kit) => kit.name)
                                    .join(', ');
                                return ListTile(
                                  key: Key('machine-summary-${machine.id}'),
                                  leading: _LogoAvatar(
                                    bytes: machine.imageBytes,
                                    fallbackIcon: Icons.memory_rounded,
                                  ),
                                  title: Text(machine.name),
                                  subtitle: Text(
                                    '${type?.name ?? 'Unknown type'}${kitNames.isEmpty ? '' : ' · $kitNames'}',
                                  ),
                                  trailing: IconButton(
                                    key: Key('edit-machine-${machine.id}'),
                                    tooltip: 'Edit machine',
                                    onPressed: () =>
                                        _startEditingMachine(machine),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                        'products': ExpansionTile(
                          key: const Key('catalog-products-section'),
                          leading: const Icon(Icons.category_outlined),
                          title: Text('Product templates (${products.length})'),
                          subtitle: const Text(
                            'Named products and reusable defaults; these are not filters',
                          ),
                          children: [
                            DropdownButtonFormField<String>(
                              key: const Key('product-brand'),
                              initialValue: productBrandId,
                              decoration: const InputDecoration(
                                labelText: 'Brand',
                              ),
                              items: brands
                                  .map(
                                    (brand) => DropdownMenuItem(
                                      value: brand.id,
                                      child: Text(brand.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(() {
                                productBrandId = value;
                                productCategory = null;
                              }),
                            ),
                            if (_productBrand != null) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                children: _productBrand!.categories
                                    .map(
                                      (category) => ChoiceChip(
                                        key: Key(
                                          'product-category-${category.name}',
                                        ),
                                        label: Text(
                                          _catalogInventoryTypeLabel(category),
                                        ),
                                        selected: productCategory == category,
                                        onSelected: (_) => setState(
                                          () => productCategory = category,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('new-product-name'),
                              controller: productName,
                              decoration: const InputDecoration(
                                labelText: 'Product name',
                                hintText: 'PolyLite PLA Pro',
                              ),
                            ),
                            const SizedBox(height: 10),
                            _ImagePickerButton(
                              key: const Key('product-image-picker'),
                              label: 'Product icon / image',
                              bytes: productImage,
                              fallbackIcon: Icons.inventory_2_outlined,
                              onChanged: (bytes) =>
                                  setState(() => productImage = bytes),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: productCost,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Default cost',
                                      prefixText: r'$ ',
                                    ),
                                  ),
                                ),
                                if (productCategory?.supportsDrying ==
                                    true) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: productDrying,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Drying duration',
                                        suffixText: 'min',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (productCategory?.supportsPrinting == true) ...[
                              const SizedBox(height: 10),
                              TextField(
                                controller: printing,
                                decoration: const InputDecoration(
                                  labelText: 'Printing instructions',
                                ),
                              ),
                            ],
                            if (productCategory?.supportsDrying == true) ...[
                              const SizedBox(height: 10),
                              TextField(
                                controller: drying,
                                decoration: const InputDecoration(
                                  labelText: 'Drying instructions',
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            TextField(
                              controller: storage,
                              decoration: const InputDecoration(
                                labelText: 'Storage instructions',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                key: const Key('add-product'),
                                onPressed: _addProduct,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add product'),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                        'kits': ExpansionTile(
                          key: const Key('catalog-kits-section'),
                          onExpansionChanged: (expanded) =>
                              setState(() => kitSectionExpanded = expanded),
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text('Kits (${kits.length})'),
                          subtitle: const Text('Reusable bills of materials'),
                          children: _kitEditorWidgets(includeKitList: true),
                        ),
                        'materials': _materialsSection(),
                      };
                      const order = [
                        'types',
                        'materials',
                        'machines',
                        'kits',
                        'spools',
                        'vendors',
                        'brands',
                        'products',
                      ];
                      return order.map((key) => sections[key]!).toList();
                    }(),
                  ),
          ),
          if (kitSectionExpanded && !loadingInitialKit)
            Container(
              key: const Key('kit-editor-footer'),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      editingKitId == null
                          ? 'New kit · ${draftSections.length} sections · ${draftBom.length} BOM items'
                          : 'Editing kit · ${draftSections.length} sections · ${draftBom.length} BOM items',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (editingKitId != null) ...[
                    TextButton(
                      key: const Key('cancel-kit-edit'),
                      onPressed: _clearKitEditor,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.icon(
                    key: const Key('save-kit'),
                    onPressed: _saveKit,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      editingKitId == null && kitOnly
                          ? 'Create Kit'
                          : editingKitId == null
                          ? 'Save kit'
                          : 'Update kit',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _kitOnlyBomList() => ListView(
    key: const Key('kit-bom-list'),
    padding: const EdgeInsets.all(18),
    children: [
      TextField(
        key: const Key('new-kit-name'),
        controller: kitName,
        decoration: InputDecoration(
          labelText: 'Kit name',
          errorText: kitNameError,
        ),
        onChanged: (_) {
          if (kitNameError != null) setState(() => kitNameError = null);
        },
      ),
      const SizedBox(height: 12),
      _kitImagePicker(),
      const SizedBox(height: 18),
      _kitSectionsEditor(),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('add-kit-section'),
          onPressed: _addKitSection,
          icon: const Icon(Icons.dashboard_customize_outlined),
          label: const Text('Add component section'),
        ),
      ),
      const SizedBox(height: 18),
    ],
  );

  Widget _itemTypesSection() => ExpansionTile(
    key: const Key('catalog-item-types-section'),
    leading: const Icon(Icons.tune_rounded),
    title: Text(
      'Item types (${_builtInCatalogTypes.length + customItemTypes.length})',
    ),
    subtitle: const Text('Editable inventory and catalog types'),
    children: [
      _newCustomTypeForm(),
      const Divider(height: 28),
      for (final type in _builtInCatalogTypes)
        ListTile(
          key: Key('built-in-type-row-${type.key}'),
          contentPadding: EdgeInsets.zero,
          leading: _typeIconVisual(
            _builtInTypeIconKey(type),
            type.icon,
            size: 24,
          ),
          title: Text(_builtInTypeLabel(type)),
          subtitle: Text(
            [
              'Item type',
              if (_typeShowsStatus(type.key, typeStatusSettings))
                'Shows status',
              if (type.key.startsWith('item:') &&
                  _typeCanMarkDepleted(type.key, typeDepletionSettings))
                'Can be marked depleted',
            ].join(' · '),
          ),
          trailing: Wrap(
            spacing: 2,
            children: [
              IconButton(
                key: Key('edit-built-in-type-${type.key}'),
                tooltip: 'Rename ${_builtInTypeLabel(type)}',
                onPressed: () => _editBuiltInType(type),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: Key('delete-built-in-type-${type.key}'),
                tooltip: widget.canDeleteCustomItemTypes
                    ? 'Delete ${_builtInTypeLabel(type)}'
                    : 'Only the database owner can delete types',
                onPressed: widget.canDeleteCustomItemTypes
                    ? () => _deleteBuiltInType(type)
                    : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      for (final type in customItemTypes)
        ListTile(
          key: Key('custom-type-row-${type.id}'),
          contentPadding: EdgeInsets.zero,
          leading: _typeIconVisual(type.iconKey, Icons.tune_rounded, size: 24),
          title: Text(type.name),
          subtitle: Text(
            [
              'Item type',
              if (type.contextualFields.isNotEmpty)
                type.contextualFields.join(', '),
              if (type.canMarkDepleted) 'Can be marked depleted',
              if (type.showsStatus) 'Shows status',
              '${widget.customTypeUsageCounts[type.id] ?? 0} inventory items',
            ].join(' · '),
          ),
          trailing: Wrap(
            spacing: 2,
            children: [
              IconButton(
                key: Key('edit-custom-type-${type.id}'),
                tooltip: 'Edit ${type.name}',
                onPressed: () => _editCustomItemType(type),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: Key('delete-custom-type-${type.id}'),
                tooltip: widget.canDeleteCustomItemTypes
                    ? 'Delete ${type.name}'
                    : 'Only the database owner can delete types',
                onPressed: widget.canDeleteCustomItemTypes
                    ? () => _deleteCustomItemType(type)
                    : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      const SizedBox(height: 16),
    ],
  );

  List<({String key, String label})> get _materialTypeChoices => [
    (key: 'component:spool', label: 'Filament spool'),
    (key: 'component:master-spool', label: 'Master spool'),
    for (final type in InventoryType.values.where(
      (type) =>
          type != InventoryType.custom &&
          !deletedTypeKeys.contains(_inventoryTypeDefinitionKey(type)),
    ))
      (key: 'type:${type.name}', label: _catalogInventoryTypeLabel(type)),
    for (final type in customItemTypes)
      (key: 'custom:${type.id}', label: type.name),
  ];

  String _materialTypeLabel(String key) =>
      _materialTypeChoices
          .where((choice) => choice.key == key)
          .map((choice) => choice.label)
          .firstOrNull ??
      'Unavailable type';

  Widget _materialsSection() => ExpansionTile(
    key: const Key('catalog-materials-section'),
    leading: const Icon(Icons.layers_outlined),
    title: Text('Materials (${materials.length})'),
    subtitle: const Text('Type-specific item subtypes'),
    children: [
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: const Key('new-material-type'),
        initialValue: materialTypeKey,
        decoration: const InputDecoration(labelText: 'Item type'),
        items: _materialTypeChoices
            .map(
              (choice) => DropdownMenuItem(
                value: choice.key,
                child: Text(choice.label),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) setState(() => materialTypeKey = value);
        },
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('new-material-name'),
              controller: materialName,
              decoration: const InputDecoration(
                labelText: 'New material',
                hintText: 'PLA, Brass, Cardboard…',
              ),
              onSubmitted: (_) => _addMaterial(),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            key: const Key('add-material'),
            onPressed: _addMaterial,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      for (final material
          in ([...materials]..sort((a, b) {
            final typeOrder = _materialTypeLabel(a.typeKey)
                .compareTo(_materialTypeLabel(b.typeKey));
            return typeOrder != 0 ? typeOrder : a.name.compareTo(b.name);
          })))
        ListTile(
          key: Key('material-row-${material.id}'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.layers_outlined),
          title: Text(material.name),
          subtitle: Text(
            '${_materialTypeLabel(material.typeKey)} · ${_materialUsageCount(material)} items',
          ),
          trailing: Wrap(
            spacing: 2,
            children: [
              IconButton(
                key: Key('edit-material-${material.id}'),
                tooltip: 'Edit ${material.name}',
                onPressed: () => _editMaterial(material),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: Key('delete-material-${material.id}'),
                tooltip: widget.canDeleteCustomItemTypes
                    ? 'Delete ${material.name}'
                    : 'Only the database owner can delete materials',
                onPressed: widget.canDeleteCustomItemTypes
                    ? () => _deleteMaterial(material)
                    : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      const SizedBox(height: 16),
    ],
  );

  int _materialUsageCount(MaterialRecord material) => widget.inventoryItems
      .where(
        (item) =>
            item.materialId == material.id ||
            item.spoolMaterialId == material.id ||
            item.masterSpoolMaterialId == material.id,
      )
      .length;

  Widget _newCustomTypeForm() => Column(
    children: [
      const SizedBox(height: 12),
      if (_deletedCatalogTypes.isNotEmpty) ...[
        DropdownButtonFormField<String>(
          key: const Key('new-type-record-link'),
          initialValue: customTypeLinkKey,
          decoration: const InputDecoration(
            labelText: 'Existing records',
            helperText: 'Link this type to an existing catalog record family, or create an independent item type.',
          ),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('New independent item type'),
            ),
            for (final type in _deletedCatalogTypes)
              DropdownMenuItem(
                value: type.key,
                child: Text('Reconnect ${type.defaultLabel}'),
              ),
          ],
          onChanged: (value) {
            final next = value ?? '';
            setState(() {
              customTypeLinkKey = next;
              if (next.isNotEmpty) {
                final linked = _deletedCatalogTypes.firstWhere(
                  (type) => type.key == next,
                );
                customTypeName.text = linked.defaultLabel;
                customTypeIconKey = _iconKeyFor(linked.icon);
              }
            });
          },
        ),
        const SizedBox(height: 10),
      ],
      TextField(
        key: const Key('new-custom-type-name'),
        controller: customTypeName,
        decoration: InputDecoration(
          labelText: customTypeLinkKey.isEmpty
              ? 'New item type'
              : 'Recreated type name',
          hintText: customTypeLinkKey.isEmpty ? 'Soap batch' : null,
        ),
      ),
      if (customTypeLinkKey.isEmpty) ...[
        const SizedBox(height: 10),
        TextField(
          key: const Key('new-custom-type-fields'),
          controller: customTypeFields,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Contextual fields',
            hintText: 'Cure time, Mold, Fragrance',
            helperText: 'Separate field names with commas or new lines',
          ),
        ),
      ],
      const SizedBox(height: 10),
      _TypeIconSelector(
        key: const Key('new-custom-type-icon'),
        value: customTypeIconKey,
        onChanged: (value) => setState(() => customTypeIconKey = value),
      ),
      const SizedBox(height: 10),
      if (customTypeLinkKey.isEmpty) ...[
        SwitchListTile.adaptive(
          key: const Key('new-custom-type-can-mark-depleted'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow “Mark depleted”'),
          subtitle: const Text(
            'Use for consumable item types that are exhausted rather than destroyed.',
          ),
          value: customTypeCanMarkDepleted,
          onChanged: (value) =>
              setState(() => customTypeCanMarkDepleted = value),
        ),
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          key: const Key('new-custom-type-shows-status'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Show item status'),
          subtitle: const Text(
            'Show Ready or Deployed status for items of this type.',
          ),
          value: customTypeShowsStatus,
          onChanged: (value) => setState(() => customTypeShowsStatus = value),
        ),
        const SizedBox(height: 10),
      ],
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          key: const Key('add-custom-type'),
          onPressed: _addCustomItemType,
          icon: Icon(
            customTypeLinkKey.isEmpty ? Icons.add_rounded : Icons.link_rounded,
          ),
          label: Text(
            customTypeLinkKey.isEmpty
                ? 'Add item type'
                : 'Create and reconnect',
          ),
        ),
      ),
    ],
  );

  Widget _kitSectionsEditor() {
    if (draftSections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Text(
          'No component sections yet. Add one, then fill it with BOM items.',
          style: TextStyle(color: Color(0xff929aac)),
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < draftSections.length; index++)
          _kitSectionCard(index),
      ],
    );
  }

  Widget _kitSectionCard(int sectionIndex) {
    final section = draftSections[sectionIndex];
    final lines = draftBom
        .where((line) => line.section == section)
        .toList(growable: false);
    return Padding(
      key: ValueKey('kit-section-$section'),
      padding: const EdgeInsets.only(bottom: 18),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: section,
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${lines.length} ${lines.length == 1 ? 'item' : 'items'}',
                    style: const TextStyle(
                      color: Color(0xff929aac),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  key: Key('rename-kit-section-$sectionIndex'),
                  tooltip: 'Rename section',
                  onPressed: () => _renameKitSection(sectionIndex),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  key: Key('delete-kit-section-$sectionIndex'),
                  tooltip: lines.isEmpty
                      ? 'Delete section'
                      : 'Remove its items before deleting this section',
                  onPressed: lines.isEmpty
                      ? () =>
                            setState(() => draftSections.removeAt(sectionIndex))
                      : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            if (lines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'This section is empty.',
                  style: TextStyle(color: Color(0xff687185)),
                ),
              )
            else
              ReorderableListView.builder(
                key: Key('kit-section-list-$sectionIndex'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: lines.length,
                onReorderItem: (oldIndex, newIndex) =>
                    _reorderSectionBom(section, oldIndex, newIndex),
                itemBuilder: (context, localIndex) {
                  final line = lines[localIndex];
                  final globalIndex = draftBom.indexWhere(
                    (candidate) => candidate.id == line.id,
                  );
                  return _kitBomRow(globalIndex, localIndex);
                },
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: sectionIndex == 0
                    ? const Key('add-kit-bom-line')
                    : Key('add-kit-bom-line-$sectionIndex'),
                onPressed: () => _chooseKitProduct(section: section),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add item to this section'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kitBomRow(int index, int localIndex) {
    final line = draftBom[index];
    final duplicate =
        draftBom
            .where((candidate) => candidate.productId == line.productId)
            .length >
        1;
    final rowKey = duplicate ? line.id : line.productId;
    return Padding(
      key: ValueKey('kit-bom-row-$rowKey'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: localIndex,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.drag_indicator_rounded),
            ),
          ),
          Expanded(
            child: TextFormField(
              key: Key('kit-bom-name-$rowKey'),
              initialValue: _bomEntryName(line),
              decoration: const InputDecoration(labelText: 'Item name'),
              onChanged: (value) => _renameDraftBomLine(index, value),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextFormField(
              key: Key('kit-bom-quantity-$rowKey'),
              initialValue: _formatBomQuantity(line.quantity),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Qty'),
              onChanged: (value) => _setDraftBomQuantity(index, value),
            ),
          ),
          if (draftSections.length > 1)
            PopupMenuButton<String>(
              key: Key('move-kit-bom-$rowKey'),
              tooltip: 'Move to another section',
              icon: const Icon(Icons.drive_file_move_outline),
              itemBuilder: (_) => draftSections
                  .where((candidate) => candidate != line.section)
                  .map(
                    (candidate) =>
                        PopupMenuItem(value: candidate, child: Text(candidate)),
                  )
                  .toList(),
              onSelected: (section) => _moveDraftBomLine(index, section),
            ),
          IconButton(
            key: Key('delete-kit-bom-$rowKey'),
            tooltip: 'Remove from kit',
            onPressed: () => setState(() => draftBom.removeAt(index)),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  List<Widget> _kitEditorWidgets({required bool includeKitList}) => [
    TextField(
      key: const Key('new-kit-name'),
      controller: kitName,
      decoration: InputDecoration(
        labelText: editingKitId == null ? 'Kit name' : 'Editing kit name',
        errorText: kitNameError,
      ),
      onChanged: (_) {
        if (kitNameError != null) setState(() => kitNameError = null);
      },
    ),
    const SizedBox(height: 12),
    _kitImagePicker(),
    const SizedBox(height: 12),
    _kitSectionsEditor(),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const Key('add-kit-section'),
        onPressed: _addKitSection,
        icon: const Icon(Icons.dashboard_customize_outlined),
        label: const Text('Add component section'),
      ),
    ),
    const SizedBox(height: 16),
    if (includeKitList) ...[
      const Divider(height: 24),
      const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'EXISTING KITS',
          style: TextStyle(
            color: Color(0xff929aac),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
      const SizedBox(height: 8),
      ...kits.map(
        (kit) => ListTile(
          key: Key('kit-summary-${kit.id}'),
          leading: _LogoAvatar(
            bytes: kit.imageBytes,
            fallbackIcon: Icons.inventory_2_outlined,
          ),
          title: Text(kit.name),
          subtitle: Text('${kit.bom.length} BOM lines'),
          trailing: IconButton(
            key: Key('edit-kit-${kit.id}'),
            tooltip: 'Edit kit',
            onPressed: () => _startEditingKit(kit),
            icon: const Icon(Icons.edit_outlined),
          ),
        ),
      ),
      const SizedBox(height: 16),
    ],
  ];

  Widget _kitImagePicker() => _ImagePickerButton(
    key: const Key('kit-image-picker'),
    label: 'Kit image',
    bytes: kitImage,
    fallbackIcon: Icons.inventory_2_outlined,
    onChanged: (bytes) => setState(() => kitImage = bytes),
  );

  BrandRecord? get _productBrand =>
      brands.where((brand) => brand.id == productBrandId).firstOrNull;

  void _addVendor() {
    final name = vendorName.text.trim();
    if (name.isEmpty) return;
    if (vendorAlsoBrand && vendorBrandCategories.isEmpty) return;
    final vendor = VendorRecord(
      id: _newCatalogId('VEN'),
      name: name,
      isBrand: vendorAlsoBrand,
      logoBytes: vendorLogo,
    );
    final linkedBrand = vendorAlsoBrand
        ? BrandRecord(
            id: _newCatalogId('BR'),
            name: name,
            vendorIds: {vendor.id},
            categories: {...vendorBrandCategories},
            logoBytes: vendorLogo,
          )
        : null;
    setState(() {
      vendors.add(vendor);
      if (linkedBrand != null) brands.add(linkedBrand);
      vendorName.clear();
      vendorLogo = null;
      vendorAlsoBrand = false;
      vendorBrandCategories.clear();
    });
    widget.onVendorAdded(vendor);
    if (linkedBrand != null) widget.onBrandAdded(linkedBrand);
  }

  void _addBrand() {
    final name = brandName.text.trim();
    if (name.isEmpty || brandVendorId == null || brandCategories.isEmpty) {
      return;
    }
    final brand = BrandRecord(
      id: _newCatalogId('BR'),
      name: name,
      vendorIds: {brandVendorId!},
      categories: {...brandCategories},
      logoBytes: brandLogo,
    );
    setState(() {
      brands.add(brand);
      brandName.clear();
      brandLogo = null;
      brandCategories.clear();
    });
    widget.onBrandAdded(brand);
  }

  void _addSpoolType() {
    final label = spoolLabel.text.trim();
    final grams = int.tryParse(spoolWeightGrams.text.trim());
    if (label.isEmpty || grams == null || grams <= 0) return;
    final spool = SpoolTypeRecord(
      id: _newCatalogId('SPOOL'),
      label: label,
      weightGrams: grams,
    );
    setState(() {
      spoolTypes.add(spool);
      spoolTypes.sort((a, b) => a.weightGrams.compareTo(b.weightGrams));
      spoolLabel.clear();
      spoolWeightGrams.clear();
    });
    widget.onSpoolTypeAdded(spool);
  }

  void _addMaterial() {
    final name = materialName.text.trim();
    if (name.isEmpty ||
        materials.any(
          (material) =>
              material.typeKey == materialTypeKey &&
              material.name.toLowerCase() == name.toLowerCase(),
        )) {
      return;
    }
    final material = MaterialRecord(
      id: _newCatalogId('MAT'),
      name: name,
      typeKey: materialTypeKey,
    );
    setState(() {
      materials.add(material);
      materialName.clear();
    });
    widget.onMaterialAdded?.call(material);
  }

  Future<void> _editMaterial(MaterialRecord material) async {
    final name = TextEditingController(text: material.name);
    var typeKey = material.typeKey;
    final updated = await showDialog<MaterialRecord>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit material'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('edit-material-type'),
                initialValue: typeKey,
                decoration: const InputDecoration(labelText: 'Item type'),
                items: _materialTypeChoices
                    .map(
                      (choice) => DropdownMenuItem(
                        value: choice.key,
                        child: Text(choice.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => typeKey = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('edit-material-name'),
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Material name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('save-material'),
              onPressed: () {
                final cleanName = name.text.trim();
                if (cleanName.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  MaterialRecord(
                    id: material.id,
                    name: cleanName,
                    typeKey: typeKey,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (updated == null || !mounted) return;
    setState(() {
      final index = materials.indexWhere(
        (candidate) => candidate.id == updated.id,
      );
      if (index >= 0) materials[index] = updated;
    });
    widget.onMaterialUpdated?.call(updated);
  }

  Future<void> _deleteMaterial(MaterialRecord material) async {
    final usageCount = _materialUsageCount(material);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${material.name}?'),
        content: Text(
          usageCount == 0
              ? 'This removes the material from the Catalog.'
              : '$usageCount inventory ${usageCount == 1 ? 'item uses' : 'items use'} this material. The material will be cleared from ${usageCount == 1 ? 'that item' : 'those items'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('confirm-delete-material'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete material'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(
      () => materials.removeWhere((candidate) => candidate.id == material.id),
    );
    widget.onMaterialDeleted?.call(material);
  }

  Future<void> _editCustomItemType(CustomItemTypeRecord type) async {
    final updated = await showDialog<CustomItemTypeRecord>(
      context: context,
      builder: (_) => _CustomItemTypeEditorDialog(
        type: type,
        existingNames: customItemTypes
            .where((candidate) => candidate.id != type.id)
            .map((candidate) => candidate.name)
            .toSet(),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      final index = customItemTypes.indexWhere(
        (candidate) => candidate.id == updated.id,
      );
      if (index >= 0) customItemTypes[index] = updated;
      customItemTypes.sort((a, b) => a.name.compareTo(b.name));
    });
    widget.onCustomItemTypeUpdated(updated);
  }

  Future<void> _editBuiltInType(
    ({String key, String defaultLabel, IconData icon}) type,
  ) async {
    final currentLabel = _builtInTypeLabel(type);
    final existingNames = <String>{
      for (final candidate in _builtInCatalogTypes)
        if (candidate.key != type.key) _builtInTypeLabel(candidate),
      ...customItemTypes.map((candidate) => candidate.name),
    };
    final updated =
        await showDialog<
          ({
            String name,
            String iconKey,
            bool canMarkDepleted,
            bool showsStatus,
          })
        >(
          context: context,
          builder: (_) => _TypeNameEditorDialog(
            initialName: currentLabel,
            initialIconKey: _builtInTypeIconKey(type),
            initialCanMarkDepleted: _typeCanMarkDepleted(
              type.key,
              typeDepletionSettings,
            ),
            initialShowsStatus: _typeShowsStatus(type.key, typeStatusSettings),
            showDepletionSetting: type.key.startsWith('item:'),
            showStatusSetting: type.key.startsWith('item:'),
            existingNames: existingNames,
          ),
        );
    if (updated == null || !mounted) return;
    setState(() {
      typeLabelOverrides[type.key] = updated.name;
      typeIconOverrides[type.key] = updated.iconKey;
      if (type.key.startsWith('item:')) {
        typeDepletionSettings[type.key] = updated.canMarkDepleted;
        typeStatusSettings[type.key] = updated.showsStatus;
      }
    });
    widget.onBuiltInTypeRenamed(MapEntry(type.key, updated.name));
    widget.onBuiltInTypeIconChanged(MapEntry(type.key, updated.iconKey));
    if (type.key.startsWith('item:')) {
      widget.onBuiltInTypeDepletionChanged(
        MapEntry(type.key, updated.canMarkDepleted),
      );
      widget.onBuiltInTypeStatusChanged(
        MapEntry(type.key, updated.showsStatus),
      );
    }
  }

  Future<void> _deleteBuiltInType(
    ({String key, String defaultLabel, IconData icon}) type,
  ) async {
    final label = _builtInTypeLabel(type);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $label?'),
        content: Text(
          type.key.startsWith('catalog:')
              ? 'This removes the type and its filter, but keeps every existing record under Everything. You can recreate and reconnect the type later from the New Type form.'
              : 'This removes the item type and its filter. Existing inventory remains visible under Everything and is moved to Other when needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('confirm-delete-built-in-type'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete type'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      deletedTypeKeys.add(type.key);
      typeLabelOverrides.remove(type.key);
      typeIconOverrides.remove(type.key);
    });
    widget.onBuiltInTypeDeleted(type.key);
  }

  Future<void> _deleteCustomItemType(CustomItemTypeRecord type) async {
    final usageCount = widget.customTypeUsageCounts[type.id] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${type.name}?'),
        content: Text(
          usageCount == 0
              ? 'This removes the item type from the Catalog.'
              : '$usageCount inventory ${usageCount == 1 ? 'item uses' : 'items use'} this type. ${usageCount == 1 ? 'It' : 'They'} will be changed to Other and the custom field values will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('confirm-delete-custom-type'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete type'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(
      () => customItemTypes.removeWhere((candidate) => candidate.id == type.id),
    );
    widget.onCustomItemTypeDeleted(type);
  }

  void _addCustomItemType() {
    final name = customTypeName.text.trim();
    if (name.isEmpty) return;
    if (customTypeLinkKey.isNotEmpty) {
      final linked = _deletedCatalogTypes
          .where((type) => type.key == customTypeLinkKey)
          .firstOrNull;
      if (linked == null) return;
      final key = linked.key;
      final iconKey = customTypeIconKey;
      setState(() {
        deletedTypeKeys.remove(key);
        typeLabelOverrides[key] = name;
        typeIconOverrides[key] = iconKey;
        customTypeName.clear();
        customTypeFields.clear();
        customTypeIconKey = 'tune';
        customTypeCanMarkDepleted = false;
        customTypeShowsStatus = false;
        customTypeLinkKey = '';
      });
      widget.onBuiltInTypeRenamed(MapEntry(key, name));
      widget.onBuiltInTypeIconChanged(MapEntry(key, iconKey));
      widget.onBuiltInTypeRestored(key);
      return;
    }
    if (customItemTypes.any(
      (type) => type.name.toLowerCase() == name.toLowerCase(),
    )) {
      return;
    }
    final fields = customTypeFields.text
        .split(RegExp(r'[,\n]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final customType = CustomItemTypeRecord(
      id: _newCatalogId('TYPE'),
      name: name,
      contextualFields: fields,
      iconKey: customTypeIconKey,
      canMarkDepleted: customTypeCanMarkDepleted,
      showsStatus: customTypeShowsStatus,
    );
    setState(() {
      customItemTypes.add(customType);
      customItemTypes.sort((a, b) => a.name.compareTo(b.name));
      customTypeName.clear();
      customTypeFields.clear();
      customTypeIconKey = 'tune';
      customTypeCanMarkDepleted = false;
      customTypeShowsStatus = false;
    });
    widget.onCustomItemTypeAdded(customType);
  }

  void _addProduct() {
    final name = productName.text.trim();
    if (name.isEmpty || productBrandId == null || productCategory == null) {
      return;
    }
    final product = CatalogProduct(
      id: _newCatalogId('PROD'),
      brandId: productBrandId!,
      category: productCategory!,
      name: name,
      defaultCost: double.tryParse(productCost.text) ?? 0,
      dryingMinutes: productCategory!.supportsDrying
          ? int.tryParse(productDrying.text)
          : null,
      printingInstructions: productCategory!.supportsPrinting
          ? printing.text.trim()
          : '',
      dryingInstructions: productCategory!.supportsDrying
          ? drying.text.trim()
          : '',
      storageInstructions: storage.text.trim(),
      imageBytes: productImage,
    );
    setState(() {
      products.add(product);
      productName.clear();
      productCost.clear();
      productDrying.clear();
      printing.clear();
      drying.clear();
      storage.clear();
      productImage = null;
    });
    widget.onProductAdded(product);
  }

  void _addMachineType() {
    final name = machineTypeName.text.trim();
    if (name.isEmpty) return;
    final type = MachineTypeRecord(
      id: _newCatalogId('MT'),
      name: name,
      parentId: machineTypeParentId,
    );
    setState(() {
      machineTypes.add(type);
      machineTypeName.clear();
      machineTypeParentId = null;
      selectedMachineTypeId ??= type.id;
    });
    widget.onMachineTypeAdded(type);
  }

  void _addMachine() {
    final name = machineName.text.trim();
    if (name.isEmpty || selectedMachineTypeId == null) return;
    final wasEditing = editingMachineId != null;
    final machine = MachineRecord(
      id: editingMachineId ?? _newCatalogId('MCH'),
      name: name,
      model: machineModel.text.trim(),
      address: machineAddress.text.trim(),
      typeId: selectedMachineTypeId!,
      kitIds: {...selectedMachineKitIds},
      sourceUrls:
          machines
              .where((candidate) => candidate.id == editingMachineId)
              .firstOrNull
              ?.sourceUrls ??
          const [],
      imageBytes: machineImage,
    );
    setState(() {
      final index = machines.indexWhere(
        (candidate) => candidate.id == editingMachineId,
      );
      if (index >= 0) {
        machines[index] = machine;
      } else {
        machines.add(machine);
      }
      _resetMachineEditor();
    });
    if (wasEditing) {
      widget.onMachineUpdated(machine);
    } else {
      widget.onMachineAdded(machine);
    }
  }

  void _startEditingMachine(MachineRecord machine) {
    setState(() {
      editingMachineId = machine.id;
      machineName.text = machine.name;
      machineModel.text = machine.model;
      machineAddress.text = machine.address;
      selectedMachineTypeId = machine.typeId;
      selectedMachineKitIds
        ..clear()
        ..addAll(machine.kitIds);
      machineImage = machine.imageBytes;
    });
  }

  void _resetMachineEditor() {
    editingMachineId = null;
    machineName.clear();
    machineModel.clear();
    machineAddress.clear();
    selectedMachineKitIds.clear();
    machineImage = null;
  }

  void _clearMachineEditor() => setState(_resetMachineEditor);

  String _bomEntryName(KitBomEntry line) =>
      line.name ??
      products
          .where((product) => product.id == line.productId)
          .firstOrNull
          ?.name ??
      kits.where((kit) => kit.id == line.productId).firstOrNull?.name ??
      'Missing item';

  bool _kitContainsKit(String kitId, String targetId, [Set<String>? visited]) {
    final checked = visited ?? <String>{};
    if (!checked.add(kitId)) return false;
    final kit = kits.where((candidate) => candidate.id == kitId).firstOrNull;
    if (kit == null) return false;
    return kit.bom.any(
      (line) =>
          line.productId == targetId ||
          _kitContainsKit(line.productId, targetId, checked),
    );
  }

  Future<void> _chooseKitProduct({String? section}) async {
    const createProduct = '__create_product__';
    const inventoryPrefix = '__inventory__:';
    var query = '';
    final productId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final matches = products
              .where(
                (product) =>
                    product.name.toLowerCase().contains(query.toLowerCase()),
              )
              .toList();
          final kitMatches = kits
              .where(
                (kit) =>
                    kit.id != editingKitId &&
                    (editingKitId == null ||
                        !_kitContainsKit(kit.id, editingKitId!)) &&
                    kit.name.toLowerCase().contains(query.toLowerCase()),
              )
              .toList();
          final inventoryMatches = widget.inventoryItems
              .where(
                (item) =>
                    !item.archived &&
                    item.name.toLowerCase().contains(query.toLowerCase()),
              )
              .toList();
          return AlertDialog(
            title: const Text('Add BOM item'),
            content: SizedBox(
              width: 520,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    key: const Key('kit-product-search'),
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      labelText: 'Search inventory, products, or kits',
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    key: const Key('create-kit-product'),
                    leading: const Icon(Icons.add_circle_outline_rounded),
                    title: const Text('Create new catalog item…'),
                    onTap: () => Navigator.of(dialogContext).pop(createProduct),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount:
                          inventoryMatches.length +
                          kitMatches.length +
                          matches.length,
                      itemBuilder: (context, index) {
                        if (index < inventoryMatches.length) {
                          final item = inventoryMatches[index];
                          return ListTile(
                            key: Key('kit-inventory-item-${item.id}'),
                            leading: Icon(_catalogInventoryItemIcon(item)),
                            title: Text(item.name),
                            subtitle: Text(
                              '${_typeLabel(item.type)} · ${_formatBomQuantity(item.quantity)} in inventory',
                            ),
                            onTap: () =>
                                Navigator.of(dialogContext)
                                    .pop('$inventoryPrefix${item.id}'),
                          );
                        }
                        final catalogIndex = index - inventoryMatches.length;
                        if (catalogIndex < kitMatches.length) {
                          final kit = kitMatches[catalogIndex];
                          return ListTile(
                            leading: const Icon(Icons.account_tree_outlined),
                            title: Text(kit.name),
                            subtitle: Text('Kit · ${kit.bom.length} BOM items'),
                            onTap: () =>
                                Navigator.of(dialogContext).pop(kit.id),
                          );
                        }
                        final product =
                            matches[catalogIndex - kitMatches.length];
                        return ListTile(
                          title: Text(product.name),
                          subtitle: Text(_typeLabel(product.category)),
                          onTap: () =>
                              Navigator.of(dialogContext).pop(product.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (productId == null || !mounted) return;

    String? selectedId;
    String? selectedName;
    if (productId == createProduct) {
      final product = await showDialog<CatalogProduct>(
        context: context,
        builder: (_) => const QuickCatalogProductDialog(),
      );
      if (product == null || !mounted) return;
      setState(() => products.add(product));
      widget.onProductAdded(product);
      selectedId = product.id;
    } else if (productId.startsWith(inventoryPrefix)) {
      final inventoryId = productId.substring(inventoryPrefix.length);
      final item = widget.inventoryItems
          .where((candidate) => candidate.id == inventoryId)
          .firstOrNull;
      if (item != null) {
        selectedId = item.catalogProductId ?? item.id;
        selectedName = item.name;
      }
    } else {
      final exists =
          products.any((product) => product.id == productId) ||
          kits.any((kit) => kit.id == productId);
      if (exists) selectedId = productId;
    }
    if (selectedId == null || !mounted) return;

    final targetSection =
        section ?? draftSections.firstOrNull ?? 'Main component';
    setState(() {
      if (!draftSections.contains(targetSection)) {
        draftSections.add(targetSection);
      }
      draftBom.add(
        KitBomEntry(
          id: 'BOM-${DateTime.now().microsecondsSinceEpoch}',
          productId: selectedId!,
          quantity: 1,
          name: selectedName,
          section: targetSection,
        ),
      );
    });
  }

  void _renameDraftBomLine(int index, String value) {
    if (index >= draftBom.length) return;
    final line = draftBom[index];
    draftBom[index] = KitBomEntry(
      id: line.id,
      productId: line.productId,
      quantity: line.quantity,
      name: value,
      section: line.section,
    );
  }

  void _setDraftBomQuantity(int index, String value) {
    final quantity = double.tryParse(value);
    if (index >= draftBom.length || quantity == null || quantity <= 0) return;
    final line = draftBom[index];
    draftBom[index] = KitBomEntry(
      id: line.id,
      productId: line.productId,
      quantity: quantity,
      name: line.name,
      section: line.section,
    );
  }

  void _moveDraftBomLine(int index, String section) {
    if (index >= draftBom.length) return;
    final line = draftBom[index];
    setState(() {
      draftBom[index] = KitBomEntry(
        id: line.id,
        productId: line.productId,
        quantity: line.quantity,
        name: line.name,
        section: section,
      );
    });
  }

  void _reorderSectionBom(String section, int oldIndex, int newIndex) {
    setState(() {
      final lines = draftBom.where((line) => line.section == section).toList();
      if (newIndex > oldIndex) newIndex--;
      final line = lines.removeAt(oldIndex);
      lines.insert(newIndex, line);
      var cursor = 0;
      for (var index = 0; index < draftBom.length; index++) {
        if (draftBom[index].section == section) {
          draftBom[index] = lines[cursor++];
        }
      }
    });
  }

  List<String> _sectionsForKit(KitRecord kit) {
    final result = <String>[];
    for (final section in [
      ...kit.sections,
      ...kit.bom.map((line) => line.section),
    ]) {
      final cleaned = section.trim().isEmpty || section == 'Unassigned'
          ? 'Main component'
          : section.trim();
      if (!result.contains(cleaned)) result.add(cleaned);
    }
    if (result.isEmpty) result.add('Main component');
    return result;
  }

  KitBomEntry _withDefaultKitSection(KitBomEntry line) => KitBomEntry(
    id: line.id,
    productId: line.productId,
    quantity: line.quantity,
    name: line.name,
    section: line.section.trim().isEmpty || line.section == 'Unassigned'
        ? 'Main component'
        : line.section,
  );

  Future<String?> _promptKitSectionName({
    required String title,
    String initialValue = '',
  }) async {
    var value = initialValue;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          key: const Key('kit-section-name'),
          initialValue: initialValue,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Section name',
            hintText: 'Extruder, Heatbed, Electronics…',
          ),
          onChanged: (next) => value = next,
          onFieldSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, value),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result?.trim();
  }

  Future<void> _addKitSection() async {
    final name = await _promptKitSectionName(title: 'Add component section');
    if (!mounted || name == null || name.isEmpty) return;
    if (draftSections.any(
      (section) => section.toLowerCase() == name.toLowerCase(),
    )) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('That section exists.')));
      return;
    }
    setState(() => draftSections.add(name));
  }

  Future<void> _renameKitSection(int sectionIndex) async {
    if (sectionIndex >= draftSections.length) return;
    final previous = draftSections[sectionIndex];
    final name = await _promptKitSectionName(
      title: 'Rename component section',
      initialValue: previous,
    );
    if (!mounted || name == null || name.isEmpty || name == previous) return;
    if (draftSections.any(
      (section) =>
          section != previous && section.toLowerCase() == name.toLowerCase(),
    )) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('That section exists.')));
      return;
    }
    setState(() {
      draftSections[sectionIndex] = name;
      for (var index = 0; index < draftBom.length; index++) {
        final line = draftBom[index];
        if (line.section != previous) continue;
        draftBom[index] = KitBomEntry(
          id: line.id,
          productId: line.productId,
          quantity: line.quantity,
          name: line.name,
          section: name,
        );
      }
    });
  }

  void _startEditingKit(KitRecord kit) {
    setState(() {
      editingKitId = kit.id;
      kitName.text = kit.name;
      kitImage = kit.imageBytes;
      kitNameError = null;
      draftBom
        ..clear()
        ..addAll(kit.bom.map(_withDefaultKitSection));
      draftSections
        ..clear()
        ..addAll(_sectionsForKit(kit));
    });
  }

  void _clearKitEditor() {
    setState(() {
      editingKitId = null;
      kitName.clear();
      kitImage = null;
      kitNameError = null;
      draftBom.clear();
      draftSections
        ..clear()
        ..add('Main component');
    });
  }

  void _saveKit() {
    final name = kitName.text.trim();
    if (name.isEmpty) {
      setState(() => kitNameError = 'Enter a kit name.');
      return;
    }
    final editedKitId = editingKitId;
    final kit = KitRecord(
      id: editedKitId ?? _newCatalogId('KIT'),
      name: name,
      bom: List.unmodifiable(draftBom),
      sections: List.unmodifiable(draftSections),
      sourceUrls:
          kits
              .where((candidate) => candidate.id == editedKitId)
              .firstOrNull
              ?.sourceUrls ??
          const [],
      imageBytes: kitImage,
    );
    setState(() {
      if (editedKitId == null) {
        kits.add(kit);
      } else {
        final index = kits.indexWhere(
          (candidate) => candidate.id == editedKitId,
        );
        if (index >= 0) kits[index] = kit;
      }
      editingKitId = null;
      kitName.clear();
      kitImage = null;
      kitNameError = null;
      draftBom.clear();
      draftSections
        ..clear()
        ..add('Main component');
    });
    if (editedKitId == null) {
      widget.onKitAdded(kit);
    } else {
      widget.onKitUpdated(kit);
    }
    if (kitOnly && mounted) Navigator.of(context).pop();
  }
}

class _KitBomLoadingState extends StatelessWidget {
  const _KitBomLoadingState();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Builder(
          builder: (context) => Container(
            width: 86,
            height: 86,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .1),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .32),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  strokeWidth: 4,
                ),
                const Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xffd2c3ff),
                  size: 25,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Assembling BOM…',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        const Text(
          'Loading kit items',
          style: TextStyle(color: Color(0xff929aac)),
        ),
      ],
    ),
  );
}

class _TypeIconSelector extends StatefulWidget {
  const _TypeIconSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TypeIconSelector> createState() => _TypeIconSelectorState();
}

class _TypeIconSelectorState extends State<_TypeIconSelector> {
  Future<void> _chooseLibraryIcon() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => _TypeIconLibraryDialog(selectedKey: widget.value),
    );
    if (selected != null) widget.onChanged(selected);
  }

  Future<void> _uploadIcon() async {
    final bytes = await _pickImageBytes();
    if (bytes == null || !mounted) return;
    try {
      widget.onChanged(_customTypeIconKeyFromBytes(bytes));
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
  }

  Future<void> _pasteBase64() async {
    var pastedValue = '';
    final source = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Paste Base64 icon'),
        content: SizedBox(
          width: 520,
          child: TextField(
            key: const Key('type-icon-base64-input'),
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Base64 image data',
              hintText: 'data:image/png;base64,...',
              helperText: 'PNG, JPEG, WebP, or animated GIF · 5 MB maximum',
            ),
            onChanged: (value) => pastedValue = value,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('apply-type-icon-base64'),
            onPressed: () => Navigator.pop(dialogContext, pastedValue),
            icon: const Icon(Icons.content_paste_rounded),
            label: const Text('Use icon'),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    try {
      widget.onChanged(_customTypeIconKeyFromBase64(source));
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InputDecorator(
        decoration: const InputDecoration(labelText: 'Icon'),
        child: Row(
          children: [
            _typeIconVisual(widget.value, Icons.inventory_2_outlined, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${_typeIconLibraryName(widget.value)} · ${_typeIconDisplayName(widget.value)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              key: const Key('choose-type-icon'),
              onPressed: _chooseLibraryIcon,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Browse'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const Key('upload-type-icon'),
            onPressed: _uploadIcon,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Upload image'),
          ),
          OutlinedButton.icon(
            key: const Key('paste-type-icon-base64'),
            onPressed: _pasteBase64,
            icon: const Icon(Icons.content_paste_rounded),
            label: const Text('Paste Base64'),
          ),
        ],
      ),
    ],
  );
}

class _TypeIconLibraryDialog extends StatefulWidget {
  const _TypeIconLibraryDialog({required this.selectedKey});

  final String selectedKey;

  @override
  State<_TypeIconLibraryDialog> createState() => _TypeIconLibraryDialogState();
}

class _TypeIconLibraryDialogState extends State<_TypeIconLibraryDialog> {
  String query = '';
  late String library = widget.selectedKey.startsWith('lucide:')
      ? 'lucide'
      : 'material';
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableHeight = MediaQuery.sizeOf(context).height;
    final entries =
        typeIconChoices.entries.where((entry) {
          final inLibrary = library == 'lucide'
              ? entry.key.startsWith('lucide:')
              : !entry.key.startsWith('lucide:');
          final needle = query.trim().toLowerCase();
          return inLibrary &&
              (needle.isEmpty ||
                  _typeIconDisplayName(entry.key)
                      .toLowerCase()
                      .contains(needle) ||
                  entry.key.toLowerCase().contains(needle));
        }).toList()..sort(
          (a, b) =>
              _typeIconDisplayName(a.key)
                  .compareTo(_typeIconDisplayName(b.key)),
        );
    return AlertDialog(
      title: const Text('Choose an icon'),
      content: SizedBox(
        width: 560,
        height: (availableHeight - 180).clamp(280.0, 560.0),
        child: Column(
          children: [
            SegmentedButton<String>(
              key: const Key('type-icon-library-selector'),
              segments: const [
                ButtonSegment(
                  value: 'material',
                  label: Text('Material'),
                  icon: Icon(Icons.widgets_outlined),
                ),
                ButtonSegment(
                  value: 'lucide',
                  label: Text('Lucide'),
                  icon: Icon(Icons.edit_outlined),
                ),
              ],
              selected: {library},
              onSelectionChanged: (selection) => setState(() {
                library = selection.single;
                query = '';
                searchController.clear();
              }),
            ),
            const SizedBox(height: 6),
            const Text(
              'Material Icons · Apache 2.0   •   Lucide · ISC',
              style: TextStyle(fontSize: 11, color: Color(0xff929aac)),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('type-icon-search'),
              autofocus: true,
              controller: searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText:
                    'Search ${library == 'lucide' ? 'Lucide' : 'Material'} icons',
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                itemCount: entries.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 130,
                  mainAxisExtent: 94,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final selected = entry.key == widget.selectedKey;
                  return InkWell(
                    key: Key('type-icon-option-${entry.key}'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, entry.key),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                                  .withValues(alpha: .2)
                            : Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(entry.value, size: 28),
                            const SizedBox(height: 7),
                            Text(
                              _typeIconDisplayName(entry.key),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _TypeNameEditorDialog extends StatefulWidget {
  const _TypeNameEditorDialog({
    required this.initialName,
    required this.initialIconKey,
    required this.initialCanMarkDepleted,
    required this.initialShowsStatus,
    required this.showDepletionSetting,
    required this.showStatusSetting,
    required this.existingNames,
  });

  final String initialName;
  final String initialIconKey;
  final bool initialCanMarkDepleted;
  final bool initialShowsStatus;
  final bool showDepletionSetting;
  final bool showStatusSetting;
  final Set<String> existingNames;

  @override
  State<_TypeNameEditorDialog> createState() => _TypeNameEditorDialogState();
}

class _TypeNameEditorDialogState extends State<_TypeNameEditorDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name = TextEditingController(
    text: widget.initialName,
  );
  late String iconKey = widget.initialIconKey;
  late bool canMarkDepleted = widget.initialCanMarkDepleted;
  late bool showsStatus = widget.initialShowsStatus;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename type'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('edit-built-in-type-name'),
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Type name'),
              validator: (value) {
                final candidate = value?.trim() ?? '';
                if (candidate.isEmpty) return 'Enter a type name';
                final duplicate = widget.existingNames.any(
                  (existing) =>
                      existing.toLowerCase() == candidate.toLowerCase(),
                );
                return duplicate ? 'That type already exists' : null;
              },
            ),
            const SizedBox(height: 12),
            _TypeIconSelector(
              key: const Key('edit-built-in-type-icon'),
              value: iconKey,
              onChanged: (value) => setState(() => iconKey = value),
            ),
            if (widget.showDepletionSetting) ...[
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                key: const Key('edit-built-in-type-can-mark-depleted'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow “Mark depleted”'),
                subtitle: const Text(
                  'Use for consumables that are exhausted rather than destroyed.',
                ),
                value: canMarkDepleted,
                onChanged: (value) => setState(() => canMarkDepleted = value),
              ),
            ],
            if (widget.showStatusSetting) ...[
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                key: const Key('edit-built-in-type-shows-status'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Show item status'),
                subtitle: Text(
                  widget.initialName.toLowerCase() == 'filament'
                      ? 'Show Ready, Deployed, Drying, or Wet status on item cards.'
                      : 'Show Ready or Deployed status on item cards.',
                ),
                value: showsStatus,
                onChanged: (value) => setState(() => showsStatus = value),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        key: const Key('save-built-in-type-name'),
        onPressed: () {
          if (formKey.currentState?.validate() != true) return;
          Navigator.pop(context, (
            name: name.text.trim(),
            iconKey: iconKey,
            canMarkDepleted: canMarkDepleted,
            showsStatus: showsStatus,
          ));
        },
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save'),
      ),
    ],
  );
}

class _CustomItemTypeEditorDialog extends StatefulWidget {
  const _CustomItemTypeEditorDialog({
    required this.type,
    required this.existingNames,
  });

  final CustomItemTypeRecord type;
  final Set<String> existingNames;

  @override
  State<_CustomItemTypeEditorDialog> createState() =>
      _CustomItemTypeEditorDialogState();
}

class _CustomItemTypeEditorDialogState
    extends State<_CustomItemTypeEditorDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name = TextEditingController(
    text: widget.type.name,
  );
  late final TextEditingController fields = TextEditingController(
    text: widget.type.contextualFields.join(', '),
  );
  late String iconKey = widget.type.iconKey;
  late bool canMarkDepleted = widget.type.canMarkDepleted;
  late bool showsStatus = widget.type.showsStatus;

  @override
  void dispose() {
    name.dispose();
    fields.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit item type'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('edit-custom-type-name'),
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Type name'),
                validator: (value) {
                  final candidate = value?.trim() ?? '';
                  if (candidate.isEmpty) return 'Enter a type name';
                  final duplicate = widget.existingNames.any(
                    (existing) =>
                        existing.toLowerCase() == candidate.toLowerCase(),
                  );
                  return duplicate ? 'That type already exists' : null;
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                key: const Key('edit-custom-type-can-mark-depleted'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow “Mark depleted”'),
                subtitle: const Text(
                  'Use for consumables that are exhausted rather than destroyed.',
                ),
                value: canMarkDepleted,
                onChanged: (value) => setState(() => canMarkDepleted = value),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                key: const Key('edit-custom-type-shows-status'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Show item status'),
                subtitle: const Text(
                  'Show Ready or Deployed status for items of this type.',
                ),
                value: showsStatus,
                onChanged: (value) => setState(() => showsStatus = value),
              ),
              const SizedBox(height: 12),
              _TypeIconSelector(
                key: const Key('edit-custom-type-icon'),
                value: iconKey,
                onChanged: (value) => setState(() => iconKey = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('edit-custom-type-fields'),
                controller: fields,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Contextual fields',
                  helperText: 'Separate field names with commas or new lines',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        key: const Key('save-custom-type-edit'),
        onPressed: () {
          if (formKey.currentState?.validate() != true) return;
          final contextualFields = fields.text
              .split(RegExp(r'[,\n]'))
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList();
          Navigator.pop(
            context,
            CustomItemTypeRecord(
              id: widget.type.id,
              name: name.text.trim(),
              contextualFields: contextualFields,
              iconKey: iconKey,
              canMarkDepleted: canMarkDepleted,
              showsStatus: showsStatus,
            ),
          );
        },
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save'),
      ),
    ],
  );
}

class QuickCatalogProductDialog extends StatefulWidget {
  const QuickCatalogProductDialog({super.key});

  @override
  State<QuickCatalogProductDialog> createState() =>
      _QuickCatalogProductDialogState();
}

class _QuickCatalogProductDialogState extends State<QuickCatalogProductDialog> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final cost = TextEditingController(text: '0.00');
  InventoryType type = InventoryType.other;

  @override
  void dispose() {
    name.dispose();
    cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add BOM item'),
    content: Form(
      key: formKey,
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('quick-product-name'),
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter an item name'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<InventoryType>(
              key: const Key('quick-product-type'),
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: InventoryType.values
                  .where((type) => type != InventoryType.custom)
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_typeLabel(value)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => type = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('quick-product-cost'),
              controller: cost,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Default price'),
              validator: (value) {
                final parsed = double.tryParse(value ?? '');
                return parsed == null || parsed < 0
                    ? 'Enter a valid price'
                    : null;
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        key: const Key('create-quick-product'),
        onPressed: _save,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create item'),
      ),
    ],
  );

  void _save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      CatalogProduct(
        id: _newCatalogId('PROD'),
        brandId: '',
        category: type,
        name: name.text.trim(),
        defaultCost: double.parse(cost.text),
      ),
    );
  }
}

class RapidizerDialog extends StatefulWidget {
  const RapidizerDialog({
    super.key,
    this.typeAliases = const {},
    this.materials = starterMaterials,
  });

  final Map<InventoryType, String> typeAliases;
  final List<MaterialRecord> materials;

  @override
  State<RapidizerDialog> createState() => _RapidizerDialogState();
}

class _RapidizerDialogState extends State<RapidizerDialog> {
  final input = TextEditingController();
  List<String> errors = const [];

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Color(0xffb8a6ff)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RAPIDIZER',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      Text(
                        'One text field. Spaces separate fields; line breaks create items.',
                        style: TextStyle(color: Color(0xff929aac)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                key: const Key('rapidizer-input'),
                controller: input,
                autofocus: true,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', height: 1.55),
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  labelText: 'Name / Color  Material  Type  Quantity?  Price',
                  hintText: 'Blue PLA Filament 22.85\nM3x10 socket screw Fastener 25 0.08\nBrass Nozzle 4 14.95',
                  helperText: 'Material and quantity are optional. Omitted quantity defaults to 1.',
                ),
                onChanged: (_) {
                  if (errors.isNotEmpty) setState(() => errors = const []);
                },
              ),
            ),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...errors
                  .take(4)
                  .map(
                    (error) => Text(
                      error,
                      style: const TextStyle(color: Color(0xffff6b7a)),
                    ),
                  ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'FORMAT: Name/Color  Material?  Type  Quantity?  Price',
                    style: TextStyle(
                      color: Color(0xff929aac),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('rapidize-items'),
                  onPressed: _rapidize,
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('RAPIDIZE!'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  void _rapidize() {
    final result = parseRapidizerText(
      input.text,
      typeAliases: widget.typeAliases,
      materials: widget.materials,
    );
    if (!result.isValid) {
      setState(
        () => errors = result.errors.isEmpty
            ? const ['Enter at least one item.']
            : result.errors,
      );
      return;
    }
    Navigator.pop(context, result.items);
  }
}

class PersonalizationSettingsDialog extends StatefulWidget {
  const PersonalizationSettingsDialog({
    super.key,
    required this.animationDurationPercent,
    required this.animationRecurrenceSeconds,
    required this.photoCardsEnabled,
    required this.customIconAnimationMode,
    required this.colorTheme,
    required this.brightnessMode,
    required this.customThemeColor,
    required this.onSettingsChanged,
    required this.onColorThemeChanged,
    required this.onBrightnessModeChanged,
    required this.onCustomThemeColorChanged,
    required this.onPhotoCardsChanged,
    required this.onCustomIconAnimationModeChanged,
  });
  final int animationDurationPercent;
  final int animationRecurrenceSeconds;
  final bool photoCardsEnabled;
  final CustomIconAnimationMode customIconAnimationMode;
  final AppColorTheme colorTheme;
  final AppBrightnessMode brightnessMode;
  final Color customThemeColor;
  final void Function(int durationPercent, int recurrenceSeconds)
  onSettingsChanged;
  final ValueChanged<AppColorTheme> onColorThemeChanged;
  final ValueChanged<AppBrightnessMode> onBrightnessModeChanged;
  final ValueChanged<Color> onCustomThemeColorChanged;
  final ValueChanged<bool> onPhotoCardsChanged;
  final ValueChanged<CustomIconAnimationMode> onCustomIconAnimationModeChanged;

  @override
  State<PersonalizationSettingsDialog> createState() =>
      _PersonalizationSettingsDialogState();
}

class _PersonalizationSettingsDialogState
    extends State<PersonalizationSettingsDialog> {
  late int durationPercent = widget.animationDurationPercent;
  late int recurrenceSeconds = widget.animationRecurrenceSeconds;
  late bool photoCardsEnabled = widget.photoCardsEnabled;
  late CustomIconAnimationMode customIconAnimationMode =
      widget.customIconAnimationMode;
  late AppColorTheme colorTheme = widget.colorTheme;
  late AppBrightnessMode brightnessMode = widget.brightnessMode;
  late Color customThemeColor = widget.customThemeColor;

  Future<void> _pickCustomThemeColor() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => ItemColorPickerDialog(
        initialValue: _colorHex(customThemeColor),
        title: 'Choose theme color',
        allowClear: false,
      ),
    );
    if (!mounted || selected == null) return;
    final parsed = _hexColor(selected);
    if (parsed == null) return;
    setState(() {
      customThemeColor = parsed;
      colorTheme = AppColorTheme.custom;
    });
    widget.onCustomThemeColorChanged(parsed);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.palette_outlined),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Personalization settings',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Appearance',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            SegmentedButton<AppBrightnessMode>(
              key: const Key('appearance-mode'),
              segments: const [
                ButtonSegment(
                  value: AppBrightnessMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark', key: Key('appearance-dark')),
                ),
                ButtonSegment(
                  value: AppBrightnessMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light', key: Key('appearance-light')),
                ),
              ],
              selected: {brightnessMode},
              onSelectionChanged: (selection) {
                final value = selection.single;
                setState(() => brightnessMode = value);
                widget.onBrightnessModeChanged(value);
              },
            ),
            const Divider(height: 28),
            const Text(
              'Color',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = math.max(
                  104.0,
                  (constraints.maxWidth - 8) / 2,
                );
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in AppColorTheme.values)
                      SizedBox(
                        width: tileWidth,
                        height: 52,
                        child: OutlinedButton(
                          key: Key('color-theme-${option.name}'),
                          onPressed: () {
                            if (option == AppColorTheme.custom) {
                              _pickCustomThemeColor();
                              return;
                            }
                            setState(() => colorTheme = option);
                            widget.onColorThemeChanged(option);
                          },
                          style: ButtonStyle(
                            side: WidgetStatePropertyAll(
                              BorderSide(
                                color: colorTheme == option
                                    ? InventorinatorColors.forTheme(
                                        option,
                                        customColor: customThemeColor,
                                        brightness: brightnessMode,
                                      ).accent
                                    : Colors.transparent,
                                width: colorTheme == option ? 2 : 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: option == AppColorTheme.custom
                                      ? customThemeColor
                                      : InventorinatorColors.forTheme(
                                          option,
                                          brightness: brightnessMode,
                                        ).base,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: InventorinatorColors.forTheme(
                                      option,
                                      customColor: customThemeColor,
                                      brightness: brightnessMode,
                                    ).accent,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  option.label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              if (colorTheme == option)
                                const Icon(Icons.check_rounded, size: 16),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const Divider(height: 28),
            SwitchListTile(
              key: const Key('photo-cards-toggle'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Photo cards'),
              subtitle: const Text(
                'Use product photos as card backgrounds with readable overlays.',
              ),
              value: photoCardsEnabled,
              onChanged: (value) {
                setState(() => photoCardsEnabled = value);
                widget.onPhotoCardsChanged(value);
              },
            ),
            const Divider(height: 28),
            const Text(
              'Performance',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<CustomIconAnimationMode>(
              key: const Key('custom-icon-animation-mode'),
              initialValue: customIconAnimationMode,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Custom type icon animation',
                helperText: 'Interaction-only reduces idle CPU use.',
              ),
              items: const [
                DropdownMenuItem(
                  value: CustomIconAnimationMode.interaction,
                  child: Text('On hover or touch · Recommended'),
                ),
                DropdownMenuItem(
                  value: CustomIconAnimationMode.always,
                  child: Text('Always animate'),
                ),
                DropdownMenuItem(
                  value: CustomIconAnimationMode.off,
                  child: Text('Still image'),
                ),
              ],
              selectedItemBuilder: (context) => const [
                Text(
                  'On hover or touch · Recommended',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Always animate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Still image',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => customIconAnimationMode = value);
                widget.onCustomIconAnimationModeChanged(value);
              },
            ),
            const Divider(height: 28),
            const Text(
              'Alert animations',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text('Animation duration · $durationPercent%'),
            Slider(
              key: const Key('animation-duration'),
              value: durationPercent.toDouble(),
              min: 25,
              max: 200,
              divisions: 7,
              label: '$durationPercent%',
              onChanged: (value) {
                setState(() => durationPercent = value.round());
                widget.onSettingsChanged(durationPercent, recurrenceSeconds);
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: const Key('animation-recurrence'),
              initialValue: recurrenceSeconds,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Repeat alerts while visible',
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Never')),
                DropdownMenuItem(value: 3, child: Text('Every 3 seconds')),
                DropdownMenuItem(value: 5, child: Text('Every 5 seconds')),
                DropdownMenuItem(value: 10, child: Text('Every 10 seconds')),
                DropdownMenuItem(value: 30, child: Text('Every 30 seconds')),
              ],
              selectedItemBuilder: (context) => const [
                Text('Never', maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  'Every 3 seconds',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Every 5 seconds',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Every 10 seconds',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Every 30 seconds',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => recurrenceSeconds = value);
                widget.onSettingsChanged(durationPercent, recurrenceSeconds);
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}

class DebugPanelDialog extends StatefulWidget {
  const DebugPanelDialog({super.key, required this.items});
  final List<InventoryItem> items;

  @override
  State<DebugPanelDialog> createState() => _DebugPanelDialogState();
}

class _DebugPanelDialogState extends State<DebugPanelDialog> {
  String? selectedItemId;

  @override
  void initState() {
    super.initState();
    selectedItemId = widget.items.firstOrNull?.id;
  }

  InventoryItem? get selectedItem =>
      widget.items.where((item) => item.id == selectedItemId).firstOrNull;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.bug_report_outlined),
        SizedBox(width: 10),
        Text('Debug effects'),
      ],
    ),
    content: SizedBox(
      width: 520,
      child: widget.items.isEmpty
          ? const Text('No items are visible under the current filters.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('debug-item'),
                  initialValue: selectedItemId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Target item'),
                  items: widget.items
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => selectedItemId = value),
                ),
                const SizedBox(height: 14),
                const Text(
                  'The panel closes before playing the effect.',
                  style: TextStyle(color: Color(0xff929aac)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('debug-quantity-sync'),
                  onPressed: () => _play(DebugCardEffect.remoteQuantity),
                  icon: const Icon(Icons.south_east_rounded),
                  label: const Text('Supabase quantity arrow'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('debug-low-stock'),
                  onPressed: () => _play(DebugCardEffect.lowStock),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Low-stock warning pulse'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('debug-moisture-wave'),
                  onPressed: selectedItem?.type == InventoryType.filament
                      ? () => _play(DebugCardEffect.moistureThreshold)
                      : null,
                  icon: const Icon(Icons.water_drop_rounded),
                  label: const Text('Moisture droplet wave'),
                ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );

  void _play(DebugCardEffect effect) {
    final itemId = selectedItemId;
    if (itemId == null) return;
    Navigator.pop(context, (itemId: itemId, effect: effect));
  }
}

String _formatBomQuantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

String _optionalNumber(double? value) =>
    value == null ? '' : _formatBomQuantity(value);

String _newCatalogId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

String _kitPackageStableId(String prefix, String packageId, [String? itemId]) {
  String clean(String value) => value
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final suffix = itemId == null ? '' : '-${clean(itemId)}';
  return '$prefix-PKG-${clean(packageId)}$suffix';
}

class _ImagePickerButton extends StatelessWidget {
  const _ImagePickerButton({
    super.key,
    required this.label,
    required this.bytes,
    required this.fallbackIcon,
    required this.onChanged,
  });
  final String label;
  final Uint8List? bytes;
  final IconData fallbackIcon;
  final ValueChanged<Uint8List?> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox.square(
          dimension: 44,
          child: bytes == null
              ? ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(fallbackIcon),
                )
              : Image.memory(bytes!, fit: BoxFit.cover),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () async {
            final picked = await _pickImageBytes();
            if (picked != null) onChanged(picked);
          },
          icon: const Icon(Icons.image_outlined),
          label: Text(
            bytes == null ? 'Choose $label' : 'Replace $label',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      if (bytes != null)
        IconButton(
          tooltip: 'Remove image',
          onPressed: () => onChanged(null),
          icon: const Icon(Icons.close_rounded),
        ),
    ],
  );
}

class _LogoAvatar extends StatelessWidget {
  const _LogoAvatar({required this.bytes, required this.fallbackIcon});
  final Uint8List? bytes;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: 22,
      child: bytes == null
          ? Icon(fallbackIcon, size: 18)
          : Image.memory(bytes!, fit: BoxFit.cover),
    ),
  );
}

Future<Uint8List?> _pickImageBytes() async {
  final result = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
  );
  return result?.readAsBytes();
}

Map<String, dynamic>? _findProductJson(Object? value) {
  if (value is List) {
    for (final entry in value) {
      final product = _findProductJson(entry);
      if (product != null) return product;
    }
  }
  if (value is Map) {
    final map = value.map((key, item) => MapEntry(key.toString(), item));
    final type = map['@type'];
    if (type == 'Product' || (type is List && type.contains('Product'))) {
      return map;
    }
    for (final entry in map.values) {
      final product = _findProductJson(entry);
      if (product != null) return product;
    }
  }
  return null;
}

Map<String, dynamic>? extractFallbackProductMetadata(String html, Uri uri) {
  final document = html_parser.parse(html);
  final bodyText = document.body?.text.toLowerCase() ?? '';
  if (bodyText.contains('enter the characters you see below') ||
      bodyText.contains('sorry, we just need to make sure you')) {
    return null;
  }

  String? attribute(String selector, String name) =>
      document.querySelector(selector)?.attributes[name]?.trim();
  String? text(String selector) {
    final value = document
        .querySelector(selector)
        ?.text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return value?.isEmpty == true ? null : value;
  }

  var name =
      text('#title') ??
      text('#productTitle') ??
      attribute('meta[property="og:title"]', 'content') ??
      attribute('meta[name="title"]', 'content') ??
      text('title');
  if (name == null || name.isEmpty) return null;
  if (uri.host.contains('amazon.')) {
    name = name.replaceFirst(RegExp(r'^Amazon\.[^:]+:\s*'), '');
    name = name.replaceFirst(RegExp(r'\s*:\s*[^:]+(?:&|and)\s*[^:]+\s*$'), '');
  }

  var brand =
      text('#bylineInfo') ??
      attribute('meta[property="product:brand"]', 'content');
  brand = brand
      ?.replaceFirst(RegExp(r'^Visit the\s+', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s+Store$', caseSensitive: false), '')
      .trim();

  final priceCandidates = [
    text('#apex-pricetopay-accessibility-label'),
    text('.a-price .a-offscreen'),
    attribute('[data-pricetopay-label]', 'data-pricetopay-label'),
    attribute('meta[property="product:price:amount"]', 'content'),
  ];
  String? price;
  for (final candidate in priceCandidates.whereType<String>()) {
    price = RegExp(r'\d+(?:[.,]\d{2})?')
        .firstMatch(candidate.replaceAll(',', ''))
        ?.group(0);
    if (price != null) break;
  }

  final image =
      attribute('#landingImage', 'data-old-hi') ??
      attribute('#landingImage', 'src') ??
      attribute('#landing-image', 'src') ??
      attribute('#landing-image-wrapper img', 'src') ??
      attribute('meta[property="og:image"]', 'content') ??
      attribute('meta[name="twitter:image"]', 'content');
  final description = [
    attribute('meta[name="description"]', 'content'),
    text('#feature-bullets'),
    text('#productFactsDesktopExpander'),
    text('#productDescription'),
  ].whereType<String>().where((value) => value.isNotEmpty).join('\n');

  return <String, dynamic>{
    '@type': 'Product',
    'name': name,
    if (brand?.isNotEmpty == true) 'brand': {'name': brand},
    if (price != null) 'offers': {'price': price},
    'image': ?image,
    if (description.isNotEmpty) 'description': description,
  };
}

class ProductImportRateLimitException implements Exception {
  const ProductImportRateLimitException(this.host, this.retryAfter);

  final String host;
  final Duration retryAfter;

  @override
  String toString() =>
      '$host asked us to slow down. Try again in ${retryAfter.inSeconds} seconds.';
}

final http.Client _productImportHttpClient = http.Client();
final Map<String, Future<void>> _productImportHostQueues = {};
final Map<String, DateTime> _productImportHostNextRequest = {};
final Map<String, DateTime> _productImportHostCooldown = {};
final Map<String, Map<String, dynamic>> _shopifyProductCache = {};

Duration _productRetryAfter(String? value, DateTime now) {
  final seconds = int.tryParse(value?.trim() ?? '');
  if (seconds != null) return Duration(seconds: seconds.clamp(1, 3600));
  DateTime? date;
  try {
    date = HttpDate.parse(value ?? '');
  } on FormatException {
    // Retry-After may be absent or malformed; use the conservative default.
  }
  if (date != null && date.isAfter(now)) {
    final difference = date.difference(now);
    if (difference > const Duration(hours: 1)) return const Duration(hours: 1);
    return difference < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : difference;
  }
  return const Duration(minutes: 1);
}

Future<http.Response> _politeProductGet(
  Uri uri, {
  required Map<String, String> headers,
}) async {
  final host = uri.host.toLowerCase();
  final previous = _productImportHostQueues[host] ?? Future<void>.value();
  final released = Completer<void>();
  _productImportHostQueues[host] = released.future;
  await previous;
  try {
    final now = DateTime.now();
    final cooldown = _productImportHostCooldown[host];
    if (cooldown != null && cooldown.isAfter(now)) {
      throw ProductImportRateLimitException(host, cooldown.difference(now));
    }
    final nextRequest = _productImportHostNextRequest[host];
    if (nextRequest != null && nextRequest.isAfter(now)) {
      await Future<void>.delayed(nextRequest.difference(now));
    }
    final response = await _productImportHttpClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));
    _productImportHostNextRequest[host] = DateTime.now().add(
      const Duration(seconds: 2),
    );
    if (response.statusCode == 429) {
      final retryAfter = _productRetryAfter(
        response.headers['retry-after'],
        DateTime.now(),
      );
      _productImportHostCooldown[host] = DateTime.now().add(retryAfter);
      throw ProductImportRateLimitException(host, retryAfter);
    }
    return response;
  } finally {
    released.complete();
    if (identical(_productImportHostQueues[host], released.future)) {
      _productImportHostQueues.remove(host);
    }
  }
}

Uri? shopifyProductEndpoint(Uri uri) {
  final segments = uri.pathSegments;
  final productsIndex = segments.lastIndexOf('products');
  if (productsIndex < 0 || productsIndex + 1 >= segments.length) return null;
  final handle = segments[productsIndex + 1].replaceFirst(RegExp(r'\.js$'), '');
  if (handle.isEmpty) return null;
  final locale = segments.firstOrNull;
  final localized =
      locale != null && RegExp(r'^[a-z]{2}-[a-z]{2}$').hasMatch(locale);
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: [if (localized) locale, 'products', '$handle.js'],
  );
}

Map<String, dynamic>? extractShopifyProductMetadata(
  Map<String, dynamic> source,
  Uri originalUri,
) {
  final title = source['title']?.toString().trim() ?? '';
  if (title.isEmpty || source['variants'] is! List) return null;
  final variants = (source['variants'] as List).whereType<Map>().toList();
  final selectedId = originalUri.queryParameters['variant'];
  final selected = variants.firstWhere(
    (variant) => variant['id']?.toString() == selectedId,
    orElse: () => variants.firstOrNull ?? const {},
  );
  final variantTitle =
      selected['public_title']?.toString().trim() ??
      selected['title']?.toString().trim() ??
      '';
  final displayName =
      variantTitle.isEmpty || variantTitle.toLowerCase() == 'default title'
      ? title
      : '$title — $variantTitle';
  final priceCents = selected['price'] ?? source['price'];
  final price = priceCents is num
      ? (priceCents / 100).toStringAsFixed(2)
      : null;
  final featured = selected['featured_image'];
  final image = featured is Map
      ? featured['src']?.toString()
      : source['featured_image']?.toString();
  final description = source['description']?.toString() ?? '';
  final vendor = source['vendor']?.toString().trim() ?? '';
  final barcode = selected['barcode']?.toString().trim() ?? '';
  return <String, dynamic>{
    '@type': 'Product',
    'name': displayName,
    if (vendor.isNotEmpty) 'brand': {'name': vendor},
    if (price != null) 'offers': {'price': price},
    if (image?.isNotEmpty == true) 'image': image,
    if (description.isNotEmpty) 'description': description,
    if (barcode.isNotEmpty) 'gtin13': barcode,
  };
}

void _collectImageUrls(Object? value, List<String> output) {
  if (value is String && value.trim().isNotEmpty) {
    output.add(value.trim());
    return;
  }
  if (value is List) {
    for (final entry in value) {
      _collectImageUrls(entry, output);
    }
    return;
  }
  if (value is Map) {
    for (final key in const ['url', 'contentUrl', '@id']) {
      _collectImageUrls(value[key], output);
    }
  }
}

typedef ImportedProductInstructions = ({
  String printing,
  String drying,
  String storage,
});

enum FilamentFamily { pla, htpla, petg, pctg, nylon, abs, asa, tpu }

typedef FilamentInstructionTemplate = ({
  FilamentFamily family,
  String label,
  String printing,
  String drying,
  String storage,
});

typedef DryingSettings = ({int? temperatureC, int? durationMinutes});

DryingSettings parseDryingSettings(String text) {
  final temperature = RegExp(
    r'(\d{2,3})\s*°?\s*C\b',
    caseSensitive: false,
  ).firstMatch(text);
  final duration = RegExp(
    r'(\d+(?:\.\d+)?)(?:\s*[-–]\s*(\d+(?:\.\d+)?))?\s*(hours?|hrs?|minutes?|mins?)\b',
    caseSensitive: false,
  ).firstMatch(text);
  final amount = double.tryParse(
    duration?.group(2) ?? duration?.group(1) ?? '',
  );
  final unit = duration?.group(3)?.toLowerCase() ?? '';
  return (
    temperatureC: int.tryParse(temperature?.group(1) ?? ''),
    durationMinutes: amount == null
        ? null
        : (amount * (unit.startsWith('h') ? 60 : 1)).round(),
  );
}

const _filamentTemplates = <FilamentFamily, FilamentInstructionTemplate>{
  FilamentFamily.pla: (
    family: FilamentFamily.pla,
    label: 'PLA',
    printing: 'Generic PLA starting profile: nozzle 185–235°C; bed 50–60°C. A heated enclosure is normally unnecessary. Verify the spool manufacturer’s settings.',
    drying: 'Generic PLA drying profile: 45°C for 6 hours. Do not exceed the spool manufacturer’s limit.',
    storage: 'Store sealed with fresh desiccant in a cool, dry place.',
  ),
  FilamentFamily.htpla: (
    family: FilamentFamily.htpla,
    label: 'HTPLA',
    printing: 'Generic HTPLA starting profile: nozzle 195–225°C; bed 50–60°C. Heat treatment/annealing is a separate process; follow the manufacturer’s procedure.',
    drying: 'Generic HTPLA drying profile: 45°C for 6 hours. Do not confuse drying with annealing.',
    storage: 'Store sealed with fresh desiccant in a cool, dry place.',
  ),
  FilamentFamily.petg: (
    family: FilamentFamily.petg,
    label: 'PETG',
    printing: 'Generic PETG starting profile: nozzle 215–270°C; bed 70–90°C. Use an appropriate release layer on surfaces where PETG may bond too strongly.',
    drying: 'Generic PETG drying profile: 55°C for 6 hours.',
    storage: 'Store sealed with fresh desiccant; use a dry box in humid environments.',
  ),
  FilamentFamily.pctg: (
    family: FilamentFamily.pctg,
    label: 'PCTG',
    printing: 'Generic PCTG starting profile: nozzle 250–270°C; bed 90–110°C. Verify the spool manufacturer’s settings.',
    drying: 'Generic PCTG drying profile: 60°C for 4–6 hours; use the manufacturer’s value when available.',
    storage: 'Store sealed with fresh desiccant; use a dry box in humid environments.',
  ),
  FilamentFamily.nylon: (
    family: FilamentFamily.nylon,
    label: 'Nylon',
    printing: 'Generic Nylon/PA starting profile: nozzle 240–285°C; bed 70–115°C; enclosure recommended. Print from a dry box when possible.',
    drying: 'Generic Nylon/PA drying profile: 70°C for 8–12 hours. PA blends vary widely, so prefer the manufacturer’s value.',
    storage: 'Highly moisture-sensitive: keep sealed with fresh desiccant or continuously in a dry box.',
  ),
  FilamentFamily.abs: (
    family: FilamentFamily.abs,
    label: 'ABS',
    printing: 'Generic ABS starting profile: nozzle 230–255°C; bed 95–110°C; enclosure recommended and part cooling low/off. Provide suitable ventilation.',
    drying: 'Generic ABS drying profile: 65°C for 4–6 hours; use the manufacturer’s value when available.',
    storage: 'Store sealed with desiccant in a cool, dry place.',
  ),
  FilamentFamily.asa: (
    family: FilamentFamily.asa,
    label: 'ASA',
    printing: 'Generic ASA starting profile: nozzle 220–275°C; bed 90–110°C; enclosure recommended. Provide suitable ventilation.',
    drying: 'Generic ASA drying profile: 80°C for 4 hours.',
    storage: 'Store sealed with desiccant in a cool, dry place.',
  ),
  FilamentFamily.tpu: (
    family: FilamentFamily.tpu,
    label: 'TPU',
    printing: 'Generic TPU starting profile: nozzle 220–260°C; bed 40–85°C. Print slowly with a constrained filament path and minimal retraction.',
    drying: 'Generic TPU drying profile: 60°C for 4–6 hours.',
    storage:
        'Moisture-sensitive: keep sealed with fresh desiccant or in a dry box.',
  ),
};

FilamentInstructionTemplate? detectFilamentTemplate(String text) {
  final value = text.toUpperCase();
  bool token(String pattern) =>
      RegExp('(?:^|[^A-Z0-9])$pattern(?:[^A-Z0-9]|\$)').hasMatch(value);
  final family = token('HT[ -]?PLA')
      ? FilamentFamily.htpla
      : token('PCTG')
      ? FilamentFamily.pctg
      : token('PETG')
      ? FilamentFamily.petg
      : token('NYLON') || token('PA(?:6|11|12|66)?')
      ? FilamentFamily.nylon
      : token('ASA')
      ? FilamentFamily.asa
      : token('ABS')
      ? FilamentFamily.abs
      : token('TPU')
      ? FilamentFamily.tpu
      : token('PLA')
      ? FilamentFamily.pla
      : null;
  return family == null ? null : _filamentTemplates[family];
}

ImportedProductInstructions applyFilamentFallbacks(
  ImportedProductInstructions extracted,
  FilamentInstructionTemplate? fallback,
) => fallback == null
    ? extracted
    : (
        printing: extracted.printing.isNotEmpty
            ? extracted.printing
            : fallback.printing,
        drying: extracted.drying.isNotEmpty
            ? extracted.drying
            : fallback.drying,
        storage: extracted.storage.isNotEmpty
            ? extracted.storage
            : fallback.storage,
      );

ImportedProductInstructions extractProductInstructions(
  String html, {
  String? structuredDescription,
}) {
  final document = html_parser.parse(html);
  final candidates = <String>[
    if (structuredDescription?.trim().isNotEmpty == true)
      structuredDescription!.trim(),
    ...document
        .querySelectorAll(
          'table tr, dl dt, dl dd, li, p, [class*="spec"], [class*="instruction"]',
        )
        .map((element) => element.text),
  ];
  final printing = <String>[];
  final drying = <String>[];
  final storage = <String>[];
  final seen = <String>{};
  final actionableValue = RegExp(
    r'\d+(?:\.\d+)?\s*(?:[-–—]\s*\d+(?:\.\d+)?)?\s*(?:°\s*[cf]|[cf]\b|mm/s|mm|%|hours?|hrs?|minutes?|mins?)',
    caseSensitive: false,
  );
  final printingTopic = RegExp(
    r'\b(?:nozzle|hotend|bed\s*temp(?:erature)?|print(?:ing)?\s*(?:temp(?:erature)?|speed)|fan\s*(?:speed)?|flow\s*rate|layer\s*height|extrusion\s*temp(?:erature)?)',
    caseSensitive: false,
  );
  final dryingTopic = RegExp(
    r'\b(?:dry|drying|dehydrate|dehydrator)\w*',
    caseSensitive: false,
  );
  final storageTopic = RegExp(
    r'\b(?:store|storage|humidity|desiccant|dry\s*box|airtight|sealed\s*bag)\b',
    caseSensitive: false,
  );
  final marketing = RegExp(
    r'\b(?:coming soon|sign up|download|special thanks|perfect for|beautiful|vibrant|rebranded|wide range|exceptional|next-generation|great color|community contributors?)\b',
    caseSensitive: false,
  );

  void add(List<String> target, String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty ||
        cleaned.length > 320 ||
        marketing.hasMatch(cleaned)) {
      return;
    }
    final key = cleaned.toLowerCase();
    if (seen.add(key) && target.length < 10) target.add(cleaned);
  }

  for (final candidate in candidates) {
    final pieces = candidate
        .replaceAllMapped(RegExp(r'([.!?])\s+'), (match) => '${match[1]}\n')
        .split(RegExp(r'[\r\n]+'));
    for (final piece in pieces) {
      final value = piece.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value.isEmpty || marketing.hasMatch(value)) continue;
      final hasValue =
          actionableValue.hasMatch(value) || RegExp(r'\d').hasMatch(value);
      if (printingTopic.hasMatch(value) && hasValue) add(printing, value);
      if (dryingTopic.hasMatch(value) && hasValue) add(drying, value);
      if (storageTopic.hasMatch(value) &&
          (hasValue ||
              RegExp(
                r'\b(?:keep|use|place|avoid|recommended|recommend)\b',
                caseSensitive: false,
              ).hasMatch(value))) {
        add(storage, value);
      }
    }
  }
  return (
    printing: printing.join('\n'),
    drying: drying.join('\n'),
    storage: storage.join('\n'),
  );
}

class AddItemDialog extends StatefulWidget {
  const AddItemDialog({
    super.key,
    this.initialItem,
    this.vendors = const [],
    this.brands = const [],
    this.spoolTypes = starterSpoolTypes,
    this.materials = starterMaterials,
    this.customItemTypes = const [],
    this.typeLabelOverrides = const {},
    this.typeIconOverrides = const {},
    this.products = const [],
    this.machineTypes = const [],
    this.machines = const [],
    this.locations = const [],
    this.initialBarcode = '',
    this.productTemplate,
    this.labelDraft,
    this.initialFilamentColor,
    this.database,
    this.filamentColorsClient,
  });
  final InventoryItem? initialItem;
  final List<VendorRecord> vendors;
  final List<BrandRecord> brands;
  final List<SpoolTypeRecord> spoolTypes;
  final List<MaterialRecord> materials;
  final List<CustomItemTypeRecord> customItemTypes;
  final Map<String, String> typeLabelOverrides;
  final Map<String, String> typeIconOverrides;
  final List<CatalogProduct> products;
  final List<MachineTypeRecord> machineTypes;
  final List<MachineRecord> machines;
  final List<StockLocationRecord> locations;
  final String initialBarcode;
  final InventoryItem? productTemplate;
  final LabelOcrDraft? labelDraft;
  final FilamentColorSwatch? initialFilamentColor;
  final LocalDatabase? database;
  final FilamentColorsClient? filamentColorsClient;

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  static const _maximumProductPageBytes = 8 * 1024 * 1024;
  static const _maximumProductImageBytes = 12 * 1024 * 1024;
  final formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final TextEditingController compatibilityController;
  late final TextEditingController costController;
  late final TextEditingController quantityController;
  late final TextEditingController quantityAlertThresholdController;
  late final TextEditingController dryingController;
  late final TextEditingController dryingTemperatureController;
  late final TextEditingController moistureLifespanController;
  late final TextEditingController moistureAlertThresholdController;
  late final TextEditingController vendorController;
  late final TextEditingController brandController;
  late final TextEditingController storageLocationController;
  String? storageLocationId;
  late final TextEditingController deploymentLocationController;
  late final TextEditingController printingController;
  late final TextEditingController dryingInstructionsController;
  late final TextEditingController storageController;
  late final TextEditingController barcodeController;
  late final TextEditingController productUrlController;
  late final TextEditingController customSearchController;
  late final TextEditingController spoolTareWeightController;
  late final TextEditingController spoolOuterDiameterController;
  late final TextEditingController spoolWidthController;
  late final TextEditingController spoolHoleDiameterController;
  late final TextEditingController masterSpoolController;
  late final TextEditingController itemColorController;
  late final TextEditingController itemColorLabelController;
  late InventoryType type;
  late bool deployed;
  late bool drying;
  late bool moistureAlertEnabled;
  late MoistureTimeUnit moistureTimeUnit;
  String? vendorId;
  String? brandId;
  String? productId;
  late String spoolTypeId;
  late bool amsCompatible;
  late bool refill;
  Uint8List? itemImage;
  Uint8List? itemThumbnail;
  Uint8List? labelImage;
  Uint8List? barcodeImage;
  bool importingProductPage = false;
  bool processingLabel = false;
  bool processingBarcodeImage = false;
  String? saveError;
  ProductSearchProvider searchProvider = ProductSearchProvider.google;
  late final Set<String> compatibleMachineIds;
  String? customTypeId;
  String? materialId;
  String? spoolMaterialId;
  String? masterSpoolMaterialId;
  final Map<String, TextEditingController> customFieldControllers = {};
  late final FilamentColorsClient _filamentColorsClient;
  late final bool _ownsFilamentColorsClient;

  @override
  void initState() {
    super.initState();
    _ownsFilamentColorsClient = widget.filamentColorsClient == null;
    _filamentColorsClient =
        widget.filamentColorsClient ??
        FilamentColorsClient(
          cacheRead: widget.database?.loadApiCache,
          cacheWrite: widget.database?.saveApiCache,
        );
    final item = widget.initialItem ?? widget.productTemplate;
    final label = widget.labelDraft;
    moistureTimeUnit = item?.moistureTimeUnit ?? MoistureTimeUnit.days;
    nameController = TextEditingController(
      text: item?.name.isNotEmpty == true ? item!.name : label?.name,
    );
    compatibilityController = TextEditingController(
      text: item?.compatibility.isNotEmpty == true
          ? item!.compatibility.join(', ')
          : label?.compatibility,
    );
    costController = TextEditingController(text: item?.cost.toStringAsFixed(2));
    quantityController = TextEditingController(
      text: _formatBomQuantity(item?.quantity ?? 1),
    );
    quantityAlertThresholdController = TextEditingController(
      text: item?.quantityAlertThreshold == null
          ? ''
          : _formatBomQuantity(item!.quantityAlertThreshold!),
    );
    dryingController = TextEditingController(
      text: item?.dryingMinutes?.toString(),
    );
    final existingDrying = parseDryingSettings(item?.dryingInstructions ?? '');
    dryingTemperatureController = TextEditingController(
      text: existingDrying.temperatureC?.toString() ?? '',
    );
    moistureLifespanController = TextEditingController(
      text: _formatDurationAmount(
        item?.moistureLifespanMinutes,
        moistureTimeUnit,
      ),
    );
    moistureAlertThresholdController = TextEditingController(
      text: _formatDurationAmount(
        item?.moistureAlertThresholdMinutes,
        moistureTimeUnit,
      ),
    );
    vendorController = TextEditingController(text: item?.vendor);
    brandController = TextEditingController(
      text: item?.brand.isNotEmpty == true ? item!.brand : label?.brand,
    );
    storageLocationController = TextEditingController(
      text: widget.initialItem?.storageLocation,
    );
    storageLocationId = widget.initialItem?.storageLocationId;
    deploymentLocationController = TextEditingController(
      text: widget.initialItem?.deploymentLocation,
    );
    printingController = TextEditingController(
      text: item?.printingInstructions.isNotEmpty == true
          ? item!.printingInstructions
          : label?.printingInstructions,
    );
    dryingInstructionsController = TextEditingController(
      text: item?.dryingInstructions,
    );
    storageController = TextEditingController(text: item?.storageInstructions);
    barcodeController = TextEditingController(
      text: item?.barcode.isNotEmpty == true
          ? item!.barcode
          : widget.initialBarcode,
    );
    productUrlController = TextEditingController(text: item?.productUrl);
    customSearchController = TextEditingController(
      text: 'https://www.google.com/search?q={query}',
    );
    spoolTareWeightController = TextEditingController(
      text: _optionalNumber(item?.spoolTareWeightGrams),
    );
    spoolOuterDiameterController = TextEditingController(
      text: _optionalNumber(item?.spoolOuterDiameterMm),
    );
    spoolWidthController = TextEditingController(
      text: _optionalNumber(item?.spoolWidthMm),
    );
    spoolHoleDiameterController = TextEditingController(
      text: _optionalNumber(item?.spoolHoleDiameterMm),
    );
    masterSpoolController = TextEditingController(text: item?.masterSpool);
    itemColorController = TextEditingController(
      text: _itemColorHex(item?.itemColorName ?? ''),
    );
    itemColorLabelController = TextEditingController(
      text: item?.itemColorLabel.isNotEmpty == true
          ? item!.itemColorLabel
          : item?.itemColorName.startsWith('#') == false
          ? item?.itemColorName
          : '',
    );
    // Recover older URL imports that were saved as Other despite an explicit
    // filament family in their product data.
    final inferredFilament = detectFilamentTemplate(
      '${item?.name ?? ''}\n${item?.printingInstructions ?? ''}\n${item?.dryingInstructions ?? ''}\n${label?.material ?? ''}',
    );
    final labelLooksLikeFilament = label?.filamentEvidence ?? false;
    type =
        item?.type == InventoryType.other &&
            (inferredFilament != null || labelLooksLikeFilament)
        ? InventoryType.filament
        : item?.type ??
              (labelLooksLikeFilament
                  ? InventoryType.filament
                  : InventoryType.other);
    customTypeId = item?.customTypeId.isNotEmpty == true
        ? item!.customTypeId
        : null;
    final inferredMaterial = _inferStarterMaterial(
      type,
      item?.name ?? label?.name ?? '',
      item?.compatibility ?? const [],
    );
    materialId = item?.materialId.isNotEmpty == true
        ? item!.materialId
        : widget.materials
              .where(
                (material) =>
                    material.typeKey == _selectedTypeChoice &&
                    material.name.toLowerCase() ==
                        (item?.materialName.isNotEmpty == true
                                ? item!.materialName
                                : label?.material ??
                                      inferredMaterial?.name ??
                                      '')
                            .toLowerCase(),
              )
              .firstOrNull
              ?.id;
    spoolMaterialId = item?.spoolMaterialId.isNotEmpty == true
        ? item!.spoolMaterialId
        : null;
    masterSpoolMaterialId = item?.masterSpoolMaterialId.isNotEmpty == true
        ? item!.masterSpoolMaterialId
        : null;
    _configureCustomFields(item?.customFieldValues ?? const {});
    deployed = widget.initialItem?.deployed ?? false;
    drying = widget.initialItem?.filamentStatus == FilamentStatus.drying;
    moistureAlertEnabled = item?.moistureAlertEnabled ?? false;
    vendorId = widget.vendors
        .where((vendor) => vendor.name == item?.vendor)
        .firstOrNull
        ?.id;
    brandId = widget.brands
        .where((brand) => brand.name == item?.brand)
        .firstOrNull
        ?.id;
    productId = item?.catalogProductId;
    if (!widget.brands.any(
      (brand) => brand.id == brandId && brand.categories.contains(type),
    )) {
      brandId = null;
    }
    spoolTypeId = item?.spoolTypeId ?? defaultSpoolTypeId;
    if (!widget.spoolTypes.any((spool) => spool.id == spoolTypeId)) {
      spoolTypeId = widget.spoolTypes.firstOrNull?.id ?? defaultSpoolTypeId;
    }
    amsCompatible = item?.amsCompatible ?? false;
    refill = item?.refill ?? false;
    itemImage = item?.imageBytes;
    itemThumbnail = item?.thumbnailBytes;
    labelImage = item?.labelImageBytes ?? label?.imageBytes;
    compatibleMachineIds = {...?item?.compatibleMachineIds};
    if (item == null && inferredFilament != null) {
      final settings = parseDryingSettings(inferredFilament.drying);
      dryingTemperatureController.text =
          settings.temperatureC?.toString() ?? '';
      dryingController.text = settings.durationMinutes?.toString() ?? '';
      if (printingController.text.isEmpty) {
        printingController.text = inferredFilament.printing;
      }
      storageController.text = inferredFilament.storage;
    }
    if (widget.initialFilamentColor case final swatch?) {
      _applyFilamentColor(swatch, notify: false);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    compatibilityController.dispose();
    costController.dispose();
    quantityController.dispose();
    quantityAlertThresholdController.dispose();
    dryingController.dispose();
    dryingTemperatureController.dispose();
    moistureLifespanController.dispose();
    moistureAlertThresholdController.dispose();
    vendorController.dispose();
    brandController.dispose();
    storageLocationController.dispose();
    deploymentLocationController.dispose();
    printingController.dispose();
    dryingInstructionsController.dispose();
    storageController.dispose();
    barcodeController.dispose();
    productUrlController.dispose();
    customSearchController.dispose();
    spoolTareWeightController.dispose();
    spoolOuterDiameterController.dispose();
    spoolWidthController.dispose();
    spoolHoleDiameterController.dispose();
    masterSpoolController.dispose();
    itemColorController.dispose();
    itemColorLabelController.dispose();
    for (final controller in customFieldControllers.values) {
      controller.dispose();
    }
    if (_ownsFilamentColorsClient) _filamentColorsClient.close();
    super.dispose();
  }

  Widget _responsiveFieldPair(bool compact, Widget first, Widget second) =>
      compact
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 16), second],
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );

  String? _validateOptionalPositiveNumber(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    return parsed == null || parsed <= 0 ? 'Enter a positive number' : null;
  }

  Future<void> _pickItemColor() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) =>
          ItemColorPickerDialog(initialValue: itemColorController.text),
    );
    if (!mounted || selected == null) return;
    setState(() => itemColorController.text = selected);
  }

  Future<void> _searchFilamentColors() async {
    final material =
        _selectedMaterial?.name ??
        detectFilamentTemplate(nameController.text)?.label ??
        '';
    final selected = await showDialog<FilamentColorSwatch>(
      context: context,
      builder: (_) => FilamentColorsSearchDialog(
        client: _filamentColorsClient,
        initialBrand: brandController.text,
        initialMaterial: material,
        initialQuery: itemColorLabelController.text,
      ),
    );
    if (!mounted || selected == null) return;
    _applyFilamentColor(selected);
  }

  void _applyFilamentColor(FilamentColorSwatch selected, {bool notify = true}) {
    final selectedMaterial = selected.material.isNotEmpty
        ? selected.material
        : selected.filamentType;
    final template = detectFilamentTemplate(selectedMaterial);
    final compatibility = compatibilityController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final apiPrinting = _filamentColorsPrintingInstructions(selected);
    final itemName = _filamentColorsItemName(selected);
    void apply() {
      if (itemName.isNotEmpty) nameController.text = itemName;
      type = InventoryType.filament;
      materialId = widget.materials
          .where(
            (material) =>
                material.typeKey == 'type:filament' &&
                material.name.toLowerCase() == selectedMaterial.toLowerCase(),
          )
          .firstOrNull
          ?.id;
      compatibilityController.text = compatibility.join(', ');
      itemColorLabelController.text = selected.name;
      itemColorController.text = selected.hex;
      if (selected.manufacturer.isNotEmpty) {
        brandController.text = selected.manufacturer;
        brandId = widget.brands
            .where(
              (brand) =>
                  brand.name.toLowerCase() ==
                  selected.manufacturer.toLowerCase(),
            )
            .firstOrNull
            ?.id;
      }
      productId = null;
      productUrlController.text = selected.purchaseUrl.isNotEmpty
          ? selected.purchaseUrl
          : selected.sourceUrl;
      if (apiPrinting.isNotEmpty) {
        printingController.text = apiPrinting;
      } else if (template != null) {
        printingController.text = template.printing;
      }
      if (template != null) {
        final drying = parseDryingSettings(template.drying);
        if (dryingTemperatureController.text.trim().isEmpty) {
          dryingTemperatureController.text =
              drying.temperatureC?.toString() ?? '';
        }
        if (dryingController.text.trim().isEmpty) {
          dryingController.text = drying.durationMinutes?.toString() ?? '';
        }
        if (storageController.text.trim().isEmpty) {
          storageController.text = template.storage;
        }
      }
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  String _filamentColorsItemName(FilamentColorSwatch swatch) {
    final parts = <String>[];
    void add(String value) {
      final cleaned = value.trim();
      if (cleaned.isEmpty) return;
      final normalized = _normalizedStockName(cleaned);
      if (parts.any(
        (part) => _normalizedStockName(part).contains(normalized),
      )) {
        return;
      }
      parts.add(cleaned);
    }

    add(swatch.manufacturer);
    add(swatch.filamentType);
    if (!swatch.filamentType.toLowerCase().contains(
      swatch.material.toLowerCase(),
    )) {
      add(swatch.material);
    }
    add(swatch.name);
    return parts.join(' ');
  }

  String _filamentColorsPrintingInstructions(FilamentColorSwatch swatch) {
    String temperature(String value) {
      final cleaned = value.trim();
      if (cleaned.isEmpty) return '';
      return RegExp(r'\b[CF]\b|\u00b0', caseSensitive: false).hasMatch(cleaned)
          ? cleaned
          : '$cleaned°C';
    }

    final nozzle = temperature(swatch.hotEndTemperature);
    final bed = temperature(swatch.bedTemperature);
    return [
      if (nozzle.isNotEmpty) 'Nozzle $nozzle',
      if (bed.isNotEmpty) 'Bed $bed',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final selectedItemColor = _itemColorSwatch(itemColorController.text);
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 8 : 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 820),
        child: SizedBox(
          width: 560,
          height: 820,
          child: Form(
            key: formKey,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 24,
                    compact ? 14 : 20,
                    compact ? 8 : 16,
                    compact ? 12 : 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.initialItem == null
                                  ? 'Add an item'
                                  : 'Edit item',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              'Give the workshop something new to track.',
                              style: TextStyle(color: Color(0xff929aac)),
                            ),
                            if (saveError != null)
                              Text(
                                saveError!,
                                key: const Key('item-save-error'),
                                style: const TextStyle(
                                  color: Color(0xffffcf4d),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('save-item'),
                        onPressed: _save,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save'),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(compact ? 16 : 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const Key('item-name'),
                          controller: nameController,
                          autofocus: true,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Item name',
                            hintText: 'Hardened steel 0.4 mm',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter an item name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _responsiveFieldPair(
                          compact,
                          TextFormField(
                            key: const Key('item-quantity'),
                            controller: quantityController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Quantity',
                              prefixText: '× ',
                              hintText: '1',
                              helperText:
                                  'Use 0 to define an item before stocking it',
                            ),
                            validator: (value) {
                              final quantity = double.tryParse(value ?? '');
                              if (quantity == null || quantity < 0) {
                                return 'Enter a non-negative quantity';
                              }
                              return null;
                            },
                          ),
                          TextFormField(
                            key: const Key('quantity-alert-threshold'),
                            controller: quantityAlertThresholdController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Low-stock alert at',
                              hintText: 'Optional',
                              helperText: 'Blank disables the alert',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null;
                              }
                              final threshold = double.tryParse(value);
                              return threshold == null || threshold < 0
                                  ? 'Enter a valid threshold'
                                  : null;
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (widget.locations.isEmpty ||
                            ((storageLocationId == null ||
                                    storageLocationId!.isEmpty) &&
                                storageLocationController.text
                                    .trim()
                                    .isNotEmpty))
                          TextFormField(
                            key: const Key('storage-location'),
                            controller: storageLocationController,
                            decoration: const InputDecoration(
                              labelText: 'Storage location',
                              helperText:
                                  'Add structured locations in Stockroom',
                            ),
                          )
                        else
                          DropdownButtonFormField<String?>(
                            key: const Key('storage-location'),
                            initialValue:
                                widget.locations.any(
                                  (location) =>
                                      location.id == storageLocationId,
                                )
                                ? storageLocationId
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Storage location',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Not assigned'),
                              ),
                              for (final location in widget.locations)
                                DropdownMenuItem(
                                  value: location.id,
                                  child: Text(
                                    _locationPathForEditor(location.id),
                                  ),
                                ),
                            ],
                            onChanged: (value) => setState(() {
                              storageLocationId = value;
                              storageLocationController.text = value == null
                                  ? ''
                                  : _locationPathForEditor(value);
                            }),
                          ),
                        if (type == InventoryType.filament) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              key: const Key('search-filament-colors'),
                              onPressed: _searchFilamentColors,
                              icon: const Icon(Icons.travel_explore_rounded),
                              label: const Text('Search FilamentColors.xyz'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (widget.productTemplate != null) ...[
                          Container(
                            key: const Key('local-barcode-match'),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xff45d2bd)
                                  .withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.offline_bolt_rounded,
                                  color: Color(0xff45d2bd),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Known barcode — product details filled from your inventory.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _responsiveFieldPair(
                          compact,
                          DropdownButtonFormField<String>(
                            key: const Key('item-type'),
                            isExpanded: true,
                            initialValue: _selectedTypeChoice,
                            decoration: const InputDecoration(
                              labelText: 'Type',
                            ),
                            items: _typeChoices,
                            onChanged: (value) {
                              if (value != null) _setTypeChoice(value);
                            },
                          ),
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'item-material-$_selectedTypeChoice-$materialId',
                            ),
                            isExpanded: true,
                            initialValue:
                                _availableMaterials.any(
                                  (material) => material.id == materialId,
                                )
                                ? materialId
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Material',
                              helperText: 'Optional subtype',
                            ),
                            items: _availableMaterials
                                .map(
                                  (material) => DropdownMenuItem(
                                    value: material.id,
                                    child: Text(material.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => materialId = value),
                          ),
                        ),
                        if (type == InventoryType.custom) ...[
                          for (final field
                              in _selectedCustomType?.contextualFields ??
                                  const <String>[]) ...[
                            const SizedBox(height: 14),
                            TextFormField(
                              key: Key(
                                'custom-field-${_normalizeTypeName(field)}',
                              ),
                              controller: customFieldControllers[field],
                              decoration: InputDecoration(labelText: field),
                            ),
                          ],
                        ],
                        const SizedBox(height: 16),
                        _responsiveFieldPair(
                          compact,
                          TextFormField(
                            key: const Key('item-color-name'),
                            controller: itemColorLabelController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Color name',
                              hintText: 'Galaxy Red',
                              helperText: 'Optional display name',
                            ),
                          ),
                          TextFormField(
                            key: const Key('item-color'),
                            controller: itemColorController,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: 'Color value',
                              hintText: '#8E75FF',
                              helperText: 'Hex value or color picker',
                              suffixIcon: IconButton(
                                key: const Key('open-item-color-picker'),
                                tooltip: 'Choose color',
                                onPressed: _pickItemColor,
                                icon: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color:
                                        selectedItemColor ??
                                        const Color(0xff252a36),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xff687185),
                                    ),
                                  ),
                                  child: selectedItemColor == null
                                      ? const Icon(
                                          Icons.palette_outlined,
                                          size: 16,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty &&
                                  itemColorLabelController.text
                                      .trim()
                                      .isNotEmpty) {
                                return 'Choose the color for this name';
                              }
                              if (text.isNotEmpty && _hexColor(text) == null) {
                                return 'Use #RGB, #RRGGBB, or #AARRGGBB';
                              }
                              return null;
                            },
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (widget.brands.isNotEmpty) ...[
                          const Text(
                            'Brand',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          DropdownMenu<String>(
                            key: ValueKey('brand-picker-$brandId'),
                            expandedInsets: EdgeInsets.zero,
                            initialSelection: brandId ?? '__custom_brand__',
                            enableFilter: true,
                            enableSearch: true,
                            requestFocusOnTap: true,
                            leadingIcon: const Icon(Icons.search_rounded),
                            label: const Text('Search brands'),
                            dropdownMenuEntries: [
                              ...([
                                ..._availableBrands,
                              ]..sort((a, b) => a.name.compareTo(b.name))).map(
                                (brand) => DropdownMenuEntry(
                                  value: brand.id,
                                  label: brand.name,
                                  leadingIcon: _LogoAvatar(
                                    bytes: brand.logoBytes,
                                    fallbackIcon: Icons.sell_outlined,
                                  ),
                                ),
                              ),
                              const DropdownMenuEntry(
                                value: '__custom_brand__',
                                label: 'Custom / new',
                                leadingIcon: Icon(Icons.add_rounded),
                              ),
                            ],
                            onSelected: (value) => setState(() {
                              productId = null;
                              if (value == '__custom_brand__' ||
                                  value == null) {
                                brandId = null;
                                brandController.clear();
                                return;
                              }
                              final brand = widget.brands.firstWhere(
                                (candidate) => candidate.id == value,
                              );
                              brandId = brand.id;
                              brandController.text = brand.name;
                              if (!brand.vendorIds.contains(vendorId)) {
                                vendorId = null;
                                vendorController.clear();
                              }
                            }),
                          ),
                          if (brandId == null) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('item-custom-brand'),
                              controller: brandController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Custom / new brand',
                                hintText: 'Cookiecad, Overture, Kaaber…',
                                helperText: 'Use when the brand is not in your catalog yet',
                              ),
                            ),
                          ],
                          if (brandId != null) ...[
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              key: const Key('catalog-vendor'),
                              initialValue: vendorId,
                              decoration: const InputDecoration(
                                labelText: 'Vendor',
                                helperText: 'Where this brand is purchased',
                              ),
                              items: _availableVendors
                                  .map(
                                    (vendor) => DropdownMenuItem(
                                      value: vendor.id,
                                      child: Row(
                                        children: [
                                          _LogoAvatar(
                                            bytes: vendor.logoBytes,
                                            fallbackIcon:
                                                Icons.storefront_outlined,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(vendor.name),
                                          if (vendor.isBrand) ...[
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.link_rounded,
                                              size: 16,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(() {
                                vendorId = value;
                                vendorController.text = widget.vendors
                                    .firstWhere((vendor) => vendor.id == value)
                                    .name;
                              }),
                            ),
                          ],
                          if (brandId != null) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Product / type',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            if (_availableProducts.length > 8)
                              DropdownButtonFormField<String>(
                                key: const Key('large-product-picker'),
                                initialValue: productId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'Choose a product',
                                  helperText:
                                      '${_availableProducts.length} products in this category',
                                ),
                                items:
                                    ([..._availableProducts]..sort(
                                          (a, b) => a.name.compareTo(b.name),
                                        ))
                                        .map(
                                          (product) => DropdownMenuItem(
                                            value: product.id,
                                            child: Row(
                                              children: [
                                                _LogoAvatar(
                                                  bytes: product.imageBytes,
                                                  fallbackIcon:
                                                      _displayTypeIcon(
                                                        product.category,
                                                      ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    product.name,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (id) {
                                  final product = _availableProducts
                                      .where((value) => value.id == id)
                                      .firstOrNull;
                                  if (product != null) _selectProduct(product);
                                },
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _availableProducts
                                    .map(
                                      (product) => ChoiceChip(
                                        key: Key('product-${product.id}'),
                                        avatar: _LogoAvatar(
                                          bytes: product.imageBytes,
                                          fallbackIcon: _displayTypeIcon(
                                            product.category,
                                          ),
                                        ),
                                        label: Text(product.name),
                                        selected: productId == product.id,
                                        onSelected: (_) =>
                                            _selectProduct(product),
                                      ),
                                    )
                                    .toList(),
                              ),
                          ],
                          const SizedBox(height: 20),
                        ],
                        TextFormField(
                          key: const Key('item-barcode'),
                          controller: barcodeController,
                          decoration: const InputDecoration(
                            labelText: 'Product barcode (optional)',
                            helperText: 'UPC / EAN shared by this product; the item gets its own QR',
                            prefixIcon: Icon(Icons.barcode_reader),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ImagePickerButton(
                          key: const Key('barcode-image-picker'),
                          label: 'barcode image',
                          bytes: barcodeImage,
                          fallbackIcon: Icons.barcode_reader,
                          onChanged: (bytes) =>
                              unawaited(_readBarcodeImage(bytes)),
                        ),
                        if (processingBarcodeImage) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(
                            key: Key('barcode-image-processing'),
                          ),
                        ],
                        const SizedBox(height: 14),
                        const Divider(key: Key('barcode-search-divider')),
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Search for a product',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Flex(
                          direction: compact ? Axis.vertical : Axis.horizontal,
                          crossAxisAlignment: compact
                              ? CrossAxisAlignment.stretch
                              : CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: compact ? double.infinity : 160,
                              child:
                                  DropdownButtonFormField<
                                    ProductSearchProvider
                                  >(
                                    key: const Key('search-provider'),
                                    initialValue: searchProvider,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Search with',
                                    ),
                                    items: ProductSearchProvider.values
                                        .map(
                                          (provider) => DropdownMenuItem(
                                            value: provider,
                                            child: Text(
                                              _searchProviderLabel(provider),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (provider) => setState(
                                      () => searchProvider = provider!,
                                    ),
                                  ),
                            ),
                            SizedBox(
                              width: compact ? 0 : 10,
                              height: compact ? 12 : 0,
                            ),
                            OutlinedButton.icon(
                              key: const Key('search-product-web'),
                              onPressed: _searchProductOnWeb,
                              icon: const Icon(Icons.travel_explore_rounded),
                              label: const Text('Search web'),
                            ),
                            SizedBox(
                              width: compact ? 0 : 10,
                              height: compact ? 8 : 0,
                            ),
                            if (compact)
                              const Text(
                                'Choose the correct product page, then paste its address below.',
                                style: TextStyle(
                                  color: Color(0xff929aac),
                                  fontSize: 12,
                                ),
                              )
                            else
                              const Expanded(
                                child: Text(
                                  'Choose the correct product page, then paste its address below.',
                                  style: TextStyle(
                                    color: Color(0xff929aac),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (searchProvider == ProductSearchProvider.custom) ...[
                          const SizedBox(height: 10),
                          TextFormField(
                            key: const Key('custom-search-url'),
                            controller: customSearchController,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Custom search URL',
                              hintText: 'https://search.example/?q={query}',
                              helperText: 'Use {query} where the product search should go.',
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        const Divider(key: Key('search-url-divider')),
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Import from a product URL',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Flex(
                          direction: compact ? Axis.vertical : Axis.horizontal,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (compact)
                              TextFormField(
                                key: const Key('product-page-url'),
                                controller: productUrlController,
                                keyboardType: TextInputType.url,
                                decoration: const InputDecoration(
                                  labelText: 'Product page URL',
                                  hintText: 'https://vendor.example/product…',
                                ),
                              )
                            else
                              Expanded(
                                child: TextFormField(
                                  key: const Key('product-page-url'),
                                  controller: productUrlController,
                                  keyboardType: TextInputType.url,
                                  decoration: const InputDecoration(
                                    labelText: 'Product page URL',
                                    hintText: 'https://vendor.example/product…',
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: compact ? 0 : 10,
                              height: compact ? 12 : 0,
                            ),
                            FilledButton.icon(
                              key: const Key('import-product-page'),
                              onPressed: importingProductPage
                                  ? null
                                  : _importProductPage,
                              icon: importingProductPage
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.download_rounded),
                              label: const Text('Import'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _ImagePickerButton(
                          key: const Key('item-image-picker'),
                          label: 'Item icon / image',
                          bytes: itemImage,
                          fallbackIcon: _displayTypeIcon(type),
                          onChanged: (bytes) => unawaited(_setItemImage(bytes)),
                        ),
                        const SizedBox(height: 10),
                        _ImagePickerButton(
                          key: const Key('label-image-picker'),
                          label: 'Label image',
                          bytes: labelImage,
                          fallbackIcon: Icons.document_scanner_outlined,
                          onChanged: (bytes) =>
                              setState(() => labelImage = bytes),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            key: const Key('process-label-image'),
                            onPressed: labelImage == null || processingLabel
                                ? null
                                : _processLabelImage,
                            icon: processingLabel
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.document_scanner_outlined),
                            label: Text(
                              processingLabel
                                  ? 'Reading label…'
                                  : 'Process label',
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (type == InventoryType.filament) ...[
                          const SizedBox(height: 14),
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Filament spool',
                              contentPadding: EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                12,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: widget.spoolTypes
                                      .map(
                                        (spool) => ChoiceChip(
                                          key: Key('spool-size-${spool.id}'),
                                          label: Text(spool.label),
                                          selected: spoolTypeId == spool.id,
                                          onSelected: (_) => setState(
                                            () => spoolTypeId = spool.id,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                                const SizedBox(height: 14),
                                DropdownButtonFormField<String>(
                                  key: const Key('spool-material'),
                                  initialValue: _materialById(
                                    spoolMaterialId,
                                    'component:spool',
                                  )?.id,
                                  decoration: const InputDecoration(
                                    labelText: 'Spool material',
                                    helperText: 'Optional',
                                  ),
                                  items: _materialsFor('component:spool')
                                      .map(
                                        (material) => DropdownMenuItem(
                                          value: material.id,
                                          child: Text(material.name),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) =>
                                      setState(() => spoolMaterialId = value),
                                ),
                                const SizedBox(height: 14),
                                _responsiveFieldPair(
                                  compact,
                                  TextFormField(
                                    key: const Key('spool-tare-weight'),
                                    controller: spoolTareWeightController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Empty spool weight',
                                      suffixText: 'g',
                                      helperText: 'Tare weight',
                                    ),
                                    validator: _validateOptionalPositiveNumber,
                                  ),
                                  TextFormField(
                                    key: const Key('spool-outer-diameter'),
                                    controller: spoolOuterDiameterController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Outer diameter',
                                      suffixText: 'mm',
                                    ),
                                    validator: _validateOptionalPositiveNumber,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _responsiveFieldPair(
                                  compact,
                                  TextFormField(
                                    key: const Key('spool-width'),
                                    controller: spoolWidthController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Spool width',
                                      suffixText: 'mm',
                                    ),
                                    validator: _validateOptionalPositiveNumber,
                                  ),
                                  TextFormField(
                                    key: const Key('spool-hole-diameter'),
                                    controller: spoolHoleDiameterController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Center-hole ID',
                                      suffixText: 'mm',
                                      helperText: 'Inner diameter',
                                    ),
                                    validator: _validateOptionalPositiveNumber,
                                  ),
                                ),
                                SwitchListTile(
                                  key: const Key('filament-refill'),
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Refill / reload'),
                                  subtitle: const Text(
                                    'This filament requires a reusable master spool.',
                                  ),
                                  value: refill,
                                  onChanged: (value) =>
                                      setState(() => refill = value),
                                ),
                                if (refill) ...[
                                  TextFormField(
                                    key: const Key('master-spool'),
                                    controller: masterSpoolController,
                                    decoration: const InputDecoration(
                                      labelText: 'Master spool / reload system',
                                      hintText: 'Polymaker MasterSpool',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    key: const Key('master-spool-material'),
                                    initialValue: _materialById(
                                      masterSpoolMaterialId,
                                      'component:master-spool',
                                    )?.id,
                                    decoration: const InputDecoration(
                                      labelText: 'Master-spool material',
                                      helperText: 'Optional',
                                    ),
                                    items:
                                        _materialsFor('component:master-spool')
                                            .map(
                                              (material) => DropdownMenuItem(
                                                value: material.id,
                                                child: Text(material.name),
                                              ),
                                            )
                                            .toList(),
                                    onChanged: (value) => setState(
                                      () => masterSpoolMaterialId = value,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                SwitchListTile(
                                  key: const Key('ams-compatible'),
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('AMS compatible'),
                                  subtitle: const Text(
                                    'The loaded spool dimensions and material work in an automatic material system.',
                                  ),
                                  value: amsCompatible,
                                  onChanged: (value) =>
                                      setState(() => amsCompatible = value),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (widget.machines.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            key: const Key('compatible-machine-dropdown'),
                            decoration: const InputDecoration(
                              labelText: 'Add compatible machine',
                            ),
                            items: widget.machines
                                .where(
                                  (machine) => !compatibleMachineIds.contains(
                                    machine.id,
                                  ),
                                )
                                .map((machine) {
                                  final type = widget.machineTypes
                                      .where(
                                        (value) => value.id == machine.typeId,
                                      )
                                      .firstOrNull;
                                  return DropdownMenuItem(
                                    value: machine.id,
                                    child: Text(
                                      type == null
                                          ? machine.name
                                          : '${machine.name} · ${type.name}',
                                    ),
                                  );
                                })
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => compatibleMachineIds.add(value));
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: widget.machines
                                .where(
                                  (machine) =>
                                      compatibleMachineIds.contains(machine.id),
                                )
                                .map((machine) {
                                  final type = widget.machineTypes
                                      .where(
                                        (value) => value.id == machine.typeId,
                                      )
                                      .firstOrNull;
                                  return InputChip(
                                    key: Key(
                                      'compatible-machine-${machine.id}',
                                    ),
                                    label: Text(
                                      type == null
                                          ? machine.name
                                          : '${machine.name} · ${type.name}',
                                    ),
                                    onDeleted: () => setState(
                                      () => compatibleMachineIds.remove(
                                        machine.id,
                                      ),
                                    ),
                                  );
                                })
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('item-compatibility'),
                          controller: compatibilityController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Compatibility / tags',
                            hintText: 'E3D V6, 1.75 mm, 24 V',
                            helperText: 'Separate tags with commas',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('item-cost'),
                          controller: costController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Cost',
                            prefixText: r'$ ',
                            hintText: '0.00',
                          ),
                          validator: (value) {
                            final cost = double.tryParse(value ?? '');
                            return cost == null || cost < 0
                                ? 'Enter a valid cost'
                                : null;
                          },
                        ),
                        if (widget.vendors.isEmpty) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('item-vendor'),
                            controller: vendorController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Vendor',
                              hintText: 'E3D, Polymaker, local supplier…',
                            ),
                          ),
                        ],
                        if (type == InventoryType.filament) ...[
                          if (widget.brands.isEmpty) ...[
                            const SizedBox(height: 14),
                            TextFormField(
                              key: const Key('item-brand'),
                              controller: brandController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Brand',
                                hintText: 'Polymaker, Overture, Prusament…',
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('deployment-location'),
                            controller: deploymentLocationController,
                            decoration: const InputDecoration(
                              labelText: 'Deployment location',
                            ),
                          ),
                        ],
                        if (type == InventoryType.filament) ...[
                          const SizedBox(height: 14),
                          _responsiveFieldPair(
                            compact,
                            TextFormField(
                              key: const Key('drying-temperature'),
                              controller: dryingTemperatureController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Drying temperature',
                                suffixText: '°C',
                              ),
                            ),
                            TextFormField(
                              key: const Key('drying-duration'),
                              controller: dryingController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Drying duration',
                                suffixText: 'min',
                              ),
                              validator: (value) {
                                if (!drying) return null;
                                final minutes = int.tryParse(value ?? '');
                                return minutes == null || minutes <= 0
                                    ? 'Required while drying'
                                    : null;
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('moisture-lifespan'),
                            controller: moistureLifespanController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Moisture lifespan',
                              suffixText: moistureTimeUnit.name,
                              helperText: 'Time from dry to too wet to print',
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty) {
                                return moistureAlertEnabled
                                    ? 'Required for moisture alerts'
                                    : null;
                              }
                              final amount = double.tryParse(text);
                              return amount == null || amount <= 0
                                  ? 'Enter a lifespan'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<MoistureTimeUnit>(
                            key: const Key('moisture-time-unit'),
                            segments: const [
                              ButtonSegment(
                                value: MoistureTimeUnit.hours,
                                label: Text('Hours'),
                              ),
                              ButtonSegment(
                                value: MoistureTimeUnit.days,
                                label: Text('Days'),
                              ),
                            ],
                            selected: {moistureTimeUnit},
                            onSelectionChanged: (selection) =>
                                _setMoistureTimeUnit(selection.first),
                          ),
                          SwitchListTile(
                            key: const Key('moisture-alert-toggle'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Moisture alert'),
                            subtitle: const Text(
                              'Show this filament in the notification list near expiry.',
                            ),
                            value: moistureAlertEnabled,
                            onChanged: (value) =>
                                setState(() => moistureAlertEnabled = value),
                          ),
                          if (moistureAlertEnabled)
                            TextFormField(
                              key: const Key('moisture-alert-threshold'),
                              controller: moistureAlertThresholdController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'Alert when time remaining reaches',
                                suffixText: moistureTimeUnit.name,
                              ),
                              validator: (value) {
                                final threshold = double.tryParse(value ?? '');
                                final lifespan = double.tryParse(
                                  moistureLifespanController.text,
                                );
                                if (threshold == null || threshold < 0) {
                                  return 'Enter an alert threshold';
                                }
                                if (lifespan != null && threshold > lifespan) {
                                  return 'Cannot exceed moisture lifespan';
                                }
                                return null;
                              },
                            ),
                        ],
                        if (type.supportsPrinting) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('printing-instructions'),
                            controller: printingController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Printing instructions',
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('storage-instructions'),
                          controller: storageController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Storage instructions',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setMoistureTimeUnit(MoistureTimeUnit next) {
    if (next == moistureTimeUnit) return;
    final lifespanMinutes = _minutesFromAmount(
      double.tryParse(moistureLifespanController.text),
      moistureTimeUnit,
    );
    final thresholdMinutes = _minutesFromAmount(
      double.tryParse(moistureAlertThresholdController.text),
      moistureTimeUnit,
    );
    setState(() {
      moistureTimeUnit = next;
      moistureLifespanController.text =
          _formatDurationAmount(lifespanMinutes, next) ?? '';
      moistureAlertThresholdController.text =
          _formatDurationAmount(thresholdMinutes, next) ?? '';
    });
  }

  void _save() {
    if (!formKey.currentState!.validate()) {
      setState(() {
        saveError = 'Some fields need attention. Check the form below.';
      });
      return;
    }
    saveError = null;
    final compatibility = compatibilityController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    Navigator.pop(
      context,
      InventoryItem(
        id: widget.initialItem?.id ?? _newInventoryId(),
        name: nameController.text.trim(),
        type: type,
        compatibility: compatibility,
        added: widget.initialItem?.added ?? DateTime.now(),
        cost: double.parse(costController.text),
        quantity: double.parse(quantityController.text),
        quantityAlertThreshold: double.tryParse(
          quantityAlertThresholdController.text,
        ),
        color: _typeColor(type),
        itemColorName: _normalizeItemColorValue(itemColorController.text),
        itemColorLabel: itemColorLabelController.text.trim(),
        dryingMinutes: type == InventoryType.filament
            ? int.tryParse(dryingController.text)
            : null,
        dryingRemaining: type == InventoryType.filament
            ? drying
                  ? widget.initialItem?.dryingRemaining ??
                        int.tryParse(dryingController.text)
                  : 0
            : null,
        dryingStartedAt: type == InventoryType.filament && drying
            ? widget.initialItem?.dryingStartedAt ?? DateTime.now()
            : null,
        moistureLifespanMinutes: type == InventoryType.filament
            ? _minutesFromAmount(
                double.tryParse(moistureLifespanController.text),
                moistureTimeUnit,
              )
            : null,
        moistureTimeUnit: moistureTimeUnit,
        moistureAlertEnabled:
            type == InventoryType.filament && moistureAlertEnabled,
        moistureAlertThresholdMinutes:
            type == InventoryType.filament && moistureAlertEnabled
            ? _minutesFromAmount(
                double.tryParse(moistureAlertThresholdController.text),
                moistureTimeUnit,
              )
            : null,
        deployed: deployed,
        vendor: vendorController.text.trim(),
        printingInstructions: type.supportsPrinting
            ? printingController.text.trim()
            : '',
        dryingInstructions:
            type.supportsDrying &&
                dryingTemperatureController.text.trim().isNotEmpty
            ? 'Dry at ${dryingTemperatureController.text.trim()}°C for ${dryingController.text.trim()} minutes.'
            : type.supportsDrying
            ? dryingInstructionsController.text.trim()
            : '',
        storageInstructions: storageController.text.trim(),
        archived: widget.initialItem?.archived ?? false,
        filamentStatus:
            widget.initialItem?.filamentStatus ?? FilamentStatus.ready,
        brand: brandController.text.trim(),
        storageLocation: storageLocationController.text.trim(),
        storageLocationId: storageLocationId ?? '',
        deploymentLocation: deploymentLocationController.text.trim(),
        lastDriedAt:
            widget.initialItem?.lastDriedAt ??
            (type == InventoryType.filament ? DateTime.now() : null),
        imageBytes: itemImage,
        thumbnailBytes: itemThumbnail,
        labelImageBytes: labelImage,
        barcode: barcodeController.text.trim(),
        productUrl: productUrlController.text.trim(),
        compatibleMachineIds: compatibleMachineIds.toList(),
        spoolTypeId: type == InventoryType.filament
            ? spoolTypeId
            : defaultSpoolTypeId,
        amsCompatible: type == InventoryType.filament && amsCompatible,
        spoolTareWeightGrams: type == InventoryType.filament
            ? double.tryParse(spoolTareWeightController.text.trim())
            : null,
        spoolOuterDiameterMm: type == InventoryType.filament
            ? double.tryParse(spoolOuterDiameterController.text.trim())
            : null,
        spoolWidthMm: type == InventoryType.filament
            ? double.tryParse(spoolWidthController.text.trim())
            : null,
        spoolHoleDiameterMm: type == InventoryType.filament
            ? double.tryParse(spoolHoleDiameterController.text.trim())
            : null,
        refill: type == InventoryType.filament && refill,
        masterSpool: type == InventoryType.filament && refill
            ? masterSpoolController.text.trim()
            : '',
        catalogProductId: productId,
        customTypeId: type == InventoryType.custom ? customTypeId ?? '' : '',
        customTypeName: type == InventoryType.custom
            ? _selectedCustomType?.name ?? ''
            : '',
        customFieldValues: type == InventoryType.custom
            ? {
                for (final entry in customFieldControllers.entries)
                  entry.key: entry.value.text.trim(),
              }
            : const {},
        materialId: materialId ?? '',
        materialName: _selectedMaterial?.name ?? '',
        spoolMaterialId: type == InventoryType.filament
            ? spoolMaterialId ?? ''
            : '',
        spoolMaterialName: type == InventoryType.filament
            ? _materialById(spoolMaterialId, 'component:spool')?.name ?? ''
            : '',
        masterSpoolMaterialId: type == InventoryType.filament && refill
            ? masterSpoolMaterialId ?? ''
            : '',
        masterSpoolMaterialName: type == InventoryType.filament && refill
            ? _materialById(
                    masterSpoolMaterialId,
                    'component:master-spool',
                  )?.name ??
                  ''
            : '',
      ),
    );
  }

  Future<void> _processLabelImage() async {
    final bytes = labelImage;
    if (bytes == null || processingLabel) return;
    setState(() => processingLabel = true);
    try {
      final draft = await recognizeProductLabel(bytes);
      if (!mounted) return;
      final template = detectFilamentTemplate(
        '${draft.material}\n${draft.name}\n${draft.rawText}',
      );
      var filled = 0;
      setState(() {
        if (draft.name.isNotEmpty) {
          nameController.text = draft.name;
          filled++;
        }
        if (draft.brand.isNotEmpty) {
          brandController.text = draft.brand;
          brandId = widget.brands
              .where(
                (brand) =>
                    brand.name.toLowerCase() == draft.brand.toLowerCase(),
              )
              .firstOrNull
              ?.id;
          filled++;
        }
        if (draft.compatibility.isNotEmpty) {
          compatibilityController.text = draft.compatibility;
          filled++;
        }
        if (draft.printingInstructions.isNotEmpty) {
          printingController.text = draft.printingInstructions;
          filled++;
        }
        if (template != null || draft.filamentEvidence) {
          type = InventoryType.filament;
          materialId = widget.materials
              .where(
                (material) =>
                    material.typeKey == 'type:filament' &&
                    material.name.toLowerCase() == draft.material.toLowerCase(),
              )
              .firstOrNull
              ?.id;
        }
        if (template != null) {
          final settings = parseDryingSettings(template.drying);
          if (dryingTemperatureController.text.isEmpty &&
              settings.temperatureC != null) {
            dryingTemperatureController.text = settings.temperatureC.toString();
            filled++;
          }
          if (dryingController.text.isEmpty &&
              settings.durationMinutes != null) {
            dryingController.text = settings.durationMinutes.toString();
            filled++;
          }
          if (printingController.text.isEmpty && template.printing.isNotEmpty) {
            printingController.text = template.printing;
            filled++;
          }
          if (storageController.text.isEmpty && template.storage.isNotEmpty) {
            storageController.text = template.storage;
            filled++;
          }
        }
        processingLabel = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            filled == 0
                ? 'Text was detected, but no item fields could be identified.'
                : 'Label processed — $filled fields filled. Review before saving.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => processingLabel = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not process label: $error')),
      );
    }
  }

  Future<void> _searchProductOnWeb() async {
    final barcode = barcodeController.text.trim();
    final name = nameController.text.trim();
    if (barcode.isEmpty && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter an item name or barcode before searching.'),
        ),
      );
      return;
    }
    final query = barcode.isNotEmpty ? '"$barcode" product' : '"$name" product';
    final template = switch (searchProvider) {
      ProductSearchProvider.google => 'https://www.google.com/search?q={query}',
      ProductSearchProvider.bing => 'https://www.bing.com/search?q={query}',
      ProductSearchProvider.duckDuckGo => 'https://duckduckgo.com/?q={query}',
      ProductSearchProvider.brave =>
        'https://search.brave.com/search?q={query}',
      ProductSearchProvider.custom => customSearchController.text.trim(),
    };
    if (!template.contains('{query}')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Custom search URL must contain {query}.'),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(
      template.replaceAll('{query}', Uri.encodeQueryComponent(query)),
    );
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid HTTP or HTTPS search URL.'),
        ),
      );
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the web browser.')),
      );
    }
  }

  Future<void> _readBarcodeImage(Uint8List? bytes) async {
    if (bytes == null) {
      if (mounted) setState(() => barcodeImage = null);
      return;
    }
    setState(() {
      barcodeImage = bytes;
      processingBarcodeImage = true;
    });
    try {
      final code = await compute(decodeAnyBarcodeFrame, bytes);
      if (!mounted) return;
      setState(() => processingBarcodeImage = false);
      if (code == null || code.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No readable barcode was found in that image.'),
          ),
        );
        return;
      }
      barcodeController.text = code.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode detected: ${code.trim()}')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => processingBarcodeImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read barcode image: $error')),
      );
    }
  }

  Future<void> _importProductPage() async {
    final uri = Uri.tryParse(productUrlController.text.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !{'http', 'https'}.contains(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paste a valid HTTP or HTTPS product URL.'),
        ),
      );
      return;
    }
    setState(() => importingProductPage = true);
    try {
      var sourceHtml = '';
      Map<String, dynamic>? product;
      final shopifyEndpoint = shopifyProductEndpoint(uri);
      if (shopifyEndpoint != null) {
        var shopifySource = _shopifyProductCache[shopifyEndpoint.toString()];
        if (shopifySource == null) {
          final response = await _politeProductGet(
            shopifyEndpoint,
            headers: const {
              'User-Agent': 'Inventorinator/1.1 (+https://github.com/DavidThePurple/Inventorinator)',
              'Accept': 'application/json,text/javascript',
              'Accept-Language': 'en-US,en;q=0.9',
            },
          );
          if (response.statusCode >= 200 && response.statusCode < 300) {
            try {
              final decoded = jsonDecode(response.body);
              if (decoded is Map) {
                shopifySource = decoded.map(
                  (key, value) => MapEntry(key.toString(), value),
                );
                _shopifyProductCache[shopifyEndpoint.toString()] =
                    shopifySource;
              }
            } catch (_) {
              // Not every /products/ site is Shopify; use its normal page.
            }
          }
        }
        if (shopifySource != null) {
          product = extractShopifyProductMetadata(shopifySource, uri);
          sourceHtml = product?['description']?.toString() ?? '';
        }
      }
      if (product == null) {
        final response = await _politeProductGet(
          uri,
          headers: const {
            'User-Agent': 'Inventorinator/1.1 (+https://github.com/DavidThePurple/Inventorinator)',
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'en-US,en;q=0.9',
          },
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('page returned HTTP ${response.statusCode}');
        }
        if (response.bodyBytes.length > _maximumProductPageBytes) {
          throw Exception('product page is larger than 8 MB');
        }
        sourceHtml = response.body;
        final pageDocument = html_parser.parse(sourceHtml);
        for (final script in pageDocument.querySelectorAll(
          'script[type="application/ld+json"]',
        )) {
          try {
            product ??= _findProductJson(jsonDecode(script.text));
          } catch (_) {
            // Some sites include malformed analytics JSON-LD; keep looking.
          }
        }
        product ??= extractFallbackProductMetadata(sourceHtml, uri);
      }
      if (product == null) {
        throw Exception('this page does not expose structured product details');
      }
      final document = html_parser.parse(sourceHtml);
      final brandValue = product['brand'];
      final brand = brandValue is Map
          ? brandValue['name']?.toString()
          : brandValue?.toString();
      final offers = product['offers'];
      final offer = offers is List
          ? offers.whereType<Map>().firstOrNull
          : offers is Map
          ? offers
          : null;
      final imageUrls = <String>[];
      _collectImageUrls(product['image'], imageUrls);
      for (final selector in const [
        'meta[property="og:image"]',
        'meta[name="twitter:image"]',
        'link[rel="image_src"]',
      ]) {
        final element = document.querySelector(selector);
        final candidate =
            element?.attributes['content'] ?? element?.attributes['href'];
        if (candidate != null) imageUrls.add(candidate);
      }
      Uint8List? downloadedImage;
      ProductImportRateLimitException? imageRateLimit;
      for (final imageUrl in imageUrls.toSet()) {
        try {
          final imageUri = uri.resolve(imageUrl);
          if (!{'http', 'https'}.contains(imageUri.scheme)) continue;
          final imageResponse = await _politeProductGet(
            imageUri,
            headers: {
              'User-Agent': 'Inventorinator/1.1 (+https://github.com/DavidThePurple/Inventorinator)',
              'Accept':
                  'image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8',
              'Referer': uri.toString(),
            },
          );
          final contentType = imageResponse.headers['content-type'] ?? '';
          if (imageResponse.statusCode == 200 &&
              imageResponse.bodyBytes.isNotEmpty &&
              imageResponse.bodyBytes.length <= _maximumProductImageBytes &&
              contentType.startsWith('image/') &&
              !contentType.contains('svg')) {
            downloadedImage = imageResponse.bodyBytes;
            break;
          }
        } on ProductImportRateLimitException catch (exception) {
          imageRateLimit = exception;
          break;
        } catch (_) {
          // Product sites often advertise several CDN variants; try the next.
        }
      }
      if (!mounted) return;
      final description = product['description']?.toString();
      final extractedInstructions = extractProductInstructions(
        sourceHtml,
        structuredDescription: description,
      );
      final productName = product['name']?.toString() ?? '';
      final template = detectFilamentTemplate(
        '$productName\n${description ?? ''}\n${document.body?.text ?? ''}',
      );
      final instructions = applyFilamentFallbacks(
        extractedInstructions,
        template,
      );
      final downloadedThumbnail = await compute(
        _createCardThumbnail,
        downloadedImage,
      );
      if (!mounted) return;
      setState(() {
        nameController.text =
            product!['name']?.toString() ?? nameController.text;
        brandController.text = brand ?? brandController.text;
        brandId = widget.brands
            .where((entry) => entry.name.toLowerCase() == brand?.toLowerCase())
            .firstOrNull
            ?.id;
        vendorController.text = uri.host.replaceFirst(RegExp(r'^www\.'), '');
        final price = offer?['price']?.toString();
        if (price != null && double.tryParse(price) != null) {
          costController.text = price;
        }
        final barcode = product['gtin13']?.toString().trim();
        if (barcode != null && barcode.isNotEmpty) {
          barcodeController.text = barcode;
        }
        if (printingController.text.isEmpty &&
            instructions.printing.isNotEmpty) {
          printingController.text = instructions.printing;
        }
        if (instructions.drying.isNotEmpty) {
          final settings = parseDryingSettings(instructions.drying);
          if (dryingTemperatureController.text.isEmpty &&
              settings.temperatureC != null) {
            dryingTemperatureController.text = settings.temperatureC.toString();
          }
          if (dryingController.text.isEmpty &&
              settings.durationMinutes != null) {
            dryingController.text = settings.durationMinutes.toString();
          }
          dryingInstructionsController.text = instructions.drying;
        }
        if (storageController.text.isEmpty && instructions.storage.isNotEmpty) {
          storageController.text = instructions.storage;
        }
        if (template != null) type = InventoryType.filament;
        if (downloadedImage != null) {
          itemImage = downloadedImage;
          itemThumbnail = downloadedThumbnail;
        }
        importingProductPage = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imageRateLimit != null
                ? 'Product details imported. Image download paused: $imageRateLimit'
                : downloadedImage == null
                ? 'Product details imported; no usable image was exposed.'
                : 'Product details and image imported. Review before saving.',
          ),
        ),
      );
    } catch (exception) {
      if (!mounted) return;
      setState(() => importingProductPage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import product: $exception')),
      );
    }
  }

  List<VendorRecord> get _availableVendors => widget.vendors
      .where((vendor) => _selectedBrand?.vendorIds.contains(vendor.id) ?? false)
      .toList();

  String _locationPathForEditor(String id, [Set<String>? visited]) {
    final seen = visited ?? <String>{};
    if (!seen.add(id)) return '';
    final location = widget.locations
        .where((value) => value.id == id)
        .firstOrNull;
    if (location == null) return '';
    if (location.parentId == null) return location.name;
    final parent = _locationPathForEditor(location.parentId!, seen);
    return parent.isEmpty ? location.name : '$parent / ${location.name}';
  }

  List<BrandRecord> get _availableBrands =>
      widget.brands.where((brand) => brand.categories.contains(type)).toList();

  CustomItemTypeRecord? get _selectedCustomType => widget.customItemTypes
      .where((customType) => customType.id == customTypeId)
      .firstOrNull;

  String _displayTypeLabel(InventoryType value) =>
      widget.typeLabelOverrides[_inventoryTypeDefinitionKey(value)] ??
      _typeLabel(value);

  String get _selectedTypeChoice => type == InventoryType.custom
      ? 'custom:${customTypeId ?? ''}'
      : 'type:${type.name}';

  List<DropdownMenuItem<String>> get _typeChoices => [
    for (final value in InventoryType.values.where(
      (value) => value != InventoryType.custom,
    ))
      DropdownMenuItem(
        value: 'type:${value.name}',
        child: Row(
          children: [
            _typeIconVisual(
              widget.typeIconOverrides[_inventoryTypeDefinitionKey(value)],
              _typeIcon(value),
              size: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _displayTypeLabel(value),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    for (final customType in widget.customItemTypes)
      DropdownMenuItem(
        value: 'custom:${customType.id}',
        child: Row(
          children: [
            _typeIconVisual(customType.iconKey, Icons.tune_rounded, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(customType.name, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    if (type == InventoryType.custom &&
        customTypeId != null &&
        !widget.customItemTypes.any((entry) => entry.id == customTypeId))
      DropdownMenuItem(
        value: 'custom:$customTypeId',
        child: Row(
          children: [
            const Icon(Icons.help_outline_rounded, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.initialItem?.customTypeName.isNotEmpty == true
                    ? widget.initialItem!.customTypeName
                    : 'Unavailable type',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
  ];

  IconData _displayTypeIcon(InventoryType value) =>
      value == InventoryType.custom
      ? _iconFromKey(_selectedCustomType?.iconKey, Icons.tune_rounded)
      : _iconFromKey(
          widget.typeIconOverrides[_inventoryTypeDefinitionKey(value)],
          _typeIcon(value),
        );

  void _configureCustomFields([Map<String, String> values = const {}]) {
    for (final controller in customFieldControllers.values) {
      controller.dispose();
    }
    customFieldControllers.clear();
    for (final field
        in _selectedCustomType?.contextualFields ?? const <String>[]) {
      customFieldControllers[field] = TextEditingController(
        text: values[field] ?? '',
      );
    }
  }

  BrandRecord? get _selectedBrand =>
      widget.brands.where((brand) => brand.id == brandId).firstOrNull;

  List<CatalogProduct> get _availableProducts => widget.products
      .where(
        (product) => product.brandId == brandId && product.category == type,
      )
      .toList();

  List<MaterialRecord> get _availableMaterials =>
      widget.materials
          .where((material) => material.typeKey == _selectedTypeChoice)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  MaterialRecord? get _selectedMaterial => widget.materials
      .where((material) => material.id == materialId)
      .firstOrNull;

  List<MaterialRecord> _materialsFor(String typeKey) =>
      widget.materials.where((material) => material.typeKey == typeKey).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  MaterialRecord? _materialById(String? id, String typeKey) => widget.materials
      .where((material) => material.id == id && material.typeKey == typeKey)
      .firstOrNull;

  MaterialRecord? _materialMatchingText(String value) {
    final source = value.toLowerCase();
    final candidates = [..._availableMaterials]
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    return candidates.where((material) {
      final escaped = RegExp.escape(material.name.toLowerCase());
      return RegExp('(?:^|[^a-z0-9])$escaped(?:[^a-z0-9]|\$)').hasMatch(source);
    }).firstOrNull;
  }

  void _setTypeChoice(String choice) {
    final customId = choice.startsWith('custom:')
        ? choice.substring('custom:'.length)
        : null;
    final next = customId == null
        ? InventoryType.values.byName(choice.substring('type:'.length))
        : InventoryType.custom;
    setState(() {
      type = next;
      customTypeId = customId;
      if (!widget.materials.any(
        (material) => material.id == materialId && material.typeKey == choice,
      )) {
        materialId = null;
      }
      _configureCustomFields();
      productId = null;
      if (_selectedBrand?.categories.contains(next) != true) {
        brandId = null;
        brandController.clear();
        vendorId = null;
        vendorController.clear();
      }
    });
  }

  Future<void> _setItemImage(Uint8List? bytes) async {
    final thumbnail = await compute(_createCardThumbnail, bytes);
    if (!mounted) return;
    setState(() {
      itemImage = bytes;
      itemThumbnail = thumbnail;
    });
  }

  void _selectProduct(CatalogProduct product) {
    setState(() {
      productId = product.id;
      type = product.category;
      materialId = _materialMatchingText(product.name)?.id;
      nameController.text = product.name;
      costController.text = product.defaultCost.toStringAsFixed(2);
      dryingController.text = product.dryingMinutes?.toString() ?? '';
      printingController.text = product.printingInstructions;
      dryingInstructionsController.text = product.dryingInstructions;
      final settings = parseDryingSettings(product.dryingInstructions);
      dryingTemperatureController.text =
          settings.temperatureC?.toString() ?? '';
      if (dryingController.text.isEmpty && settings.durationMinutes != null) {
        dryingController.text = settings.durationMinutes.toString();
      }
      storageController.text = product.storageInstructions;
    });
    unawaited(_setItemImage(product.imageBytes));
  }
}

String _typeLabel(InventoryType type) => switch (type) {
  InventoryType.other => 'Other',
  InventoryType.fastener => 'Fasteners',
  InventoryType.filament => 'Filament',
  InventoryType.printedPart => 'Printed parts',
  InventoryType.resin => 'Resin',
  InventoryType.nozzle => 'Nozzle',
  InventoryType.heatBreak => 'Heat break',
  InventoryType.heatBlock => 'Heat block',
  InventoryType.sock => 'Silicone sock',
  InventoryType.custom => 'Custom',
};

String _inventoryTypeDefinitionKey(InventoryType type) => 'item:${type.name}';

String _catalogViewDefinitionKey(CatalogViewFilter type) =>
    'catalog:${type.name}';

String _defaultCatalogViewLabel(CatalogViewFilter type) => switch (type) {
  CatalogViewFilter.kits => 'Kits',
  CatalogViewFilter.builds => 'Builds',
  CatalogViewFilter.machines => 'Machines',
  CatalogViewFilter.printers => 'Printers',
  CatalogViewFilter.tools => 'Tools',
};

InventoryType? smartMatchInventoryType(
  String input, {
  Map<InventoryType, String> typeAliases = const {},
}) {
  final needle = _normalizeTypeName(input);
  if (needle.isEmpty) return null;
  const aliases = <InventoryType, List<String>>{
    InventoryType.other: ['other', 'misc', 'miscellaneous'],
    InventoryType.fastener: [
      'fastener',
      'fasteners',
      'screw',
      'screws',
      'bolt',
      'bolts',
      'nut',
      'nuts',
      'washer',
      'washers',
    ],
    InventoryType.filament: [
      'filament',
      'filaments',
      'pla',
      'htpla',
      'petg',
      'pctg',
      'nylon',
      'abs',
      'asa',
      'tpu',
    ],
    InventoryType.printedPart: [
      'printed part',
      'printed parts',
      '3d printed part',
      'print',
    ],
    InventoryType.resin: ['resin', 'resins', 'sla resin'],
    InventoryType.nozzle: ['nozzle', 'nozzles'],
    InventoryType.heatBreak: ['heat break', 'heatbreak', 'heat breaks'],
    InventoryType.heatBlock: ['heat block', 'heatblock', 'heater block'],
    InventoryType.sock: ['silicone sock', 'sock', 'socks'],
  };
  final effectiveAliases = {
    for (final entry in aliases.entries)
      entry.key: [
        ...entry.value,
        if (typeAliases[entry.key]?.trim().isNotEmpty == true)
          typeAliases[entry.key]!,
      ],
  };
  for (final entry in effectiveAliases.entries) {
    if (entry.value.any((alias) => _normalizeTypeName(alias) == needle)) {
      return entry.key;
    }
  }
  InventoryType? bestType;
  var bestDistance = 1 << 20;
  var tied = false;
  for (final entry in effectiveAliases.entries) {
    for (final alias in entry.value) {
      final normalizedAlias = _normalizeTypeName(alias);
      final distance = _levenshteinDistance(needle, normalizedAlias);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestType = entry.key;
        tied = false;
      } else if (distance == bestDistance && bestType != entry.key) {
        tied = true;
      }
    }
  }
  final allowedDistance = needle.length <= 4
      ? 1
      : needle.length <= 7
      ? 2
      : 3;
  return !tied && bestDistance <= allowedDistance ? bestType : null;
}

InventoryJsonParseResult parseInventoryJson(String source) {
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    return InventoryJsonParseResult(
      items: const [],
      errors: ['Invalid JSON: ${error.message}'],
    );
  }
  List<Object?> rows;
  if (decoded is List) {
    rows = decoded;
  } else if (decoded is Map) {
    final normalizedRoot = <String, Object?>{
      for (final entry in decoded.entries)
        _normalizeJsonColumn(entry.key.toString()): entry.value,
    };
    final collection =
        normalizedRoot['items'] ??
        normalizedRoot['inventory'] ??
        normalizedRoot['rows'] ??
        normalizedRoot['data'];
    if (collection is List) {
      rows = collection;
    } else if (_jsonRowValue(normalizedRoot, const ['name', 'itemname']) !=
        null) {
      rows = [decoded];
    } else {
      return const InventoryJsonParseResult(
        items: [],
        errors: [
          'Expected a JSON array or an object containing an items array.',
        ],
      );
    }
  } else {
    return const InventoryJsonParseResult(
      items: [],
      errors: ['Expected a JSON array of inventory items.'],
    );
  }
  if (rows.isEmpty) {
    return const InventoryJsonParseResult(
      items: [],
      errors: ['The JSON file contains no inventory items.'],
    );
  }

  final items = <InventoryJsonDraft>[];
  final errors = <String>[];
  for (var index = 0; index < rows.length; index++) {
    final rowNumber = index + 1;
    final raw = rows[index];
    if (raw is! Map) {
      errors.add('Row $rowNumber: expected an object.');
      continue;
    }
    final row = <String, Object?>{
      for (final entry in raw.entries)
        _normalizeJsonColumn(entry.key.toString()): entry.value,
    };
    final name = _jsonText(
      _jsonRowValue(row, const [
        'name',
        'itemname',
        'productname',
        'item',
        'title',
        'description',
      ]),
    );
    if (name.isEmpty) {
      errors.add('Row $rowNumber: Item Name is required.');
      continue;
    }
    final quantity = _jsonNumber(
      _jsonRowValue(row, const ['quantity', 'qty', 'count', 'stock']),
      fallback: 1,
    );
    if (quantity == null || quantity < 0) {
      errors.add('Row $rowNumber: Quantity must be zero or greater.');
      continue;
    }
    final cost = _jsonNumber(
      _jsonRowValue(row, const ['cost', 'price', 'unitcost', 'unitprice']),
      fallback: 0,
    );
    if (cost == null || cost < 0) {
      errors.add('Row $rowNumber: Cost must be zero or greater.');
      continue;
    }
    final imageUrl = _jsonText(
      _jsonRowValue(row, const [
        'imageurl',
        'productimageurl',
        'photourl',
        'image',
        'productimage',
        'photo',
      ]),
    );
    if (imageUrl.isNotEmpty) {
      final uri = Uri.tryParse(imageUrl);
      if (uri == null ||
          !uri.hasAuthority ||
          !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
        errors.add(
          'Row $rowNumber: Image URL must be a valid HTTP or HTTPS URL.',
        );
        continue;
      }
    }
    items.add(
      InventoryJsonDraft(
        rowNumber: rowNumber,
        name: name,
        typeName: _jsonText(
          _jsonRowValue(row, const ['type', 'itemtype', 'category']),
        ),
        quantity: quantity,
        cost: cost,
        material: _jsonText(
          _jsonRowValue(row, const ['material', 'materialtype']),
        ),
        color: _jsonText(
          _jsonRowValue(row, const [
            'color',
            'colour',
            'hex',
            'colorhex',
            'colourhex',
          ]),
        ),
        colorLabel: _jsonText(
          _jsonRowValue(row, const [
            'colorname',
            'colourname',
            'colorlabel',
            'colourlabel',
          ]),
        ),
        brand: _jsonText(
          _jsonRowValue(row, const ['brand', 'maker', 'manufacturer']),
        ),
        vendor: _jsonText(
          _jsonRowValue(row, const ['vendor', 'supplier', 'store']),
        ),
        storageLocation: _jsonText(
          _jsonRowValue(row, const [
            'storagelocation',
            'location',
            'bin',
            'shelf',
          ]),
        ),
        barcode: _jsonText(
          _jsonRowValue(row, const ['barcode', 'upc', 'ean', 'sku']),
        ),
        productUrl: _jsonText(
          _jsonRowValue(row, const [
            'producturl',
            'url',
            'sourceurl',
            'source',
          ]),
        ),
        imageUrl: imageUrl,
        compatibility: _jsonStringList(
          _jsonRowValue(row, const [
            'compatibility',
            'compatiblewith',
            'compatiblemachines',
          ]),
        ),
        amsCompatible: _jsonBool(
          _jsonRowValue(row, const [
            'amscompatible',
            'amscompatibility',
            'ams',
          ]),
        ),
      ),
    );
  }
  return InventoryJsonParseResult(items: items, errors: errors);
}

class InventoryJsonImageImportResult {
  const InventoryJsonImageImportResult({
    required this.items,
    required this.imported,
    required this.failed,
  });

  final List<InventoryItem> items;
  final int imported;
  final int failed;
}

const _maximumInventoryJsonImageBytes = 12 * 1024 * 1024;

Future<InventoryJsonImageImportResult> downloadInventoryJsonImages(
  List<InventoryItem> items,
  List<InventoryJsonDraft> drafts, {
  http.Client? client,
  void Function(int completed, int total)? onProgress,
}) async {
  assert(items.length == drafts.length);
  final imageIndexes = <int>[
    for (var index = 0; index < drafts.length; index++)
      if (drafts[index].imageUrl.isNotEmpty) index,
  ];
  if (imageIndexes.isEmpty) {
    return InventoryJsonImageImportResult(
      items: List<InventoryItem>.of(items),
      imported: 0,
      failed: 0,
    );
  }

  final ownsClient = client == null;
  final httpClient = client ?? http.Client();
  final hydrated = List<InventoryItem>.of(items);
  var next = 0;
  var imported = 0;
  var failed = 0;
  var completed = 0;

  Future<void> worker() async {
    while (next < imageIndexes.length) {
      final itemIndex = imageIndexes[next++];
      final uri = Uri.parse(drafts[itemIndex].imageUrl);
      try {
        final request = http.Request('GET', uri)
          ..headers.addAll(const {
            'User-Agent': 'Inventorinator/1.1 (+https://github.com/DavidThePurple/Inventorinator)',
            'Accept':
                'image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8',
          });
        final response = await httpClient
            .send(request)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('HTTP ${response.statusCode}', uri: uri);
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 20),
        )) {
          if (bytes.length + chunk.length > _maximumInventoryJsonImageBytes) {
            throw const FormatException('Image is larger than 12 MB.');
          }
          bytes.add(chunk);
        }
        final imageBytes = bytes.takeBytes();
        if (!_looksLikeRasterImage(imageBytes) ||
            img.decodeImage(imageBytes) == null) {
          throw const FormatException('Response is not a supported image.');
        }
        final thumbnail = await compute(_createCardThumbnail, imageBytes);
        hydrated[itemIndex] = hydrated[itemIndex].copyWith(
          imageBytes: imageBytes,
          thumbnailBytes: thumbnail,
        );
        imported++;
      } catch (_) {
        failed++;
      } finally {
        completed++;
        onProgress?.call(completed, imageIndexes.length);
      }
    }
  }

  try {
    await Future.wait(
      List.generate(math.min(4, imageIndexes.length), (_) => worker()),
    );
  } finally {
    if (ownsClient) httpClient.close();
  }
  return InventoryJsonImageImportResult(
    items: hydrated,
    imported: imported,
    failed: failed,
  );
}

String _normalizeJsonColumn(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

Object? _jsonRowValue(Map<String, Object?> row, List<String> names) {
  for (final name in names) {
    if (row.containsKey(name)) return row[name];
  }
  return null;
}

String _jsonText(Object? value) => value == null ? '' : value.toString().trim();

double? _jsonNumber(Object? value, {required double fallback}) {
  if (value == null || value.toString().trim().isEmpty) return fallback;
  if (value is num) return value.toDouble();
  final cleaned = value
      .toString()
      .trim()
      .replaceAll(',', '')
      .replaceAll(RegExp(r'^[\$\u00a3\u20ac]'), '');
  return double.tryParse(cleaned);
}

bool _jsonBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return const {
    'true',
    'yes',
    'y',
    '1',
    'compatible',
  }.contains(value?.toString().trim().toLowerCase());
}

List<String> _jsonStringList(Object? value) {
  if (value is List) {
    return value
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }
  return _jsonText(value)
      .split(RegExp(r'[,;|]'))
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}

RapidizerParseResult parseRapidizerText(
  String input, {
  Map<InventoryType, String> typeAliases = const {},
  List<MaterialRecord> materials = starterMaterials,
}) {
  final items = <RapidItemDraft>[];
  final errors = <String>[];
  final lines = input.split(RegExp(r'\r?\n'));
  for (var index = 0; index < lines.length; index++) {
    final rawLine = lines[index].trim();
    if (rawLine.isEmpty) continue;
    final tokens = rawLine.split(RegExp(r'\s+'));
    if (tokens.length < 3) {
      errors.add('Line ${index + 1}: use Name Type Price.');
      continue;
    }
    final price = double.tryParse(_rapidNumberToken(tokens.last));
    if (price == null || price < 0) {
      errors.add('Line ${index + 1}: invalid price “${tokens.last}”.');
      continue;
    }
    final explicitQuantity = tokens.length >= 4
        ? double.tryParse(_rapidNumberToken(tokens[tokens.length - 2]))
        : null;
    final quantity = explicitQuantity ?? 1;
    if (quantity < 0) {
      errors.add(
        'Line ${index + 1}: invalid quantity “${tokens[tokens.length - 2]}”.',
      );
      continue;
    }
    final body = tokens.sublist(
      0,
      tokens.length - (explicitQuantity == null ? 1 : 2),
    );
    InventoryType? type;
    var typeWordCount = 0;
    final maximumTypeWords = body.length > 3 ? 3 : body.length - 1;
    for (var count = 1; count <= maximumTypeWords; count++) {
      final candidate = body.sublist(body.length - count).join(' ');
      final match = smartMatchInventoryType(
        candidate,
        typeAliases: typeAliases,
      );
      if (match != null) {
        type = match;
        typeWordCount = count;
        break;
      }
    }
    if (type == null) {
      errors.add(
        'Line ${index + 1}: could not recognize the type before quantity or price.',
      );
      continue;
    }
    var name = body.sublist(0, body.length - typeWordCount).join(' ').trim();
    if (name.length >= 2 &&
        ((name.startsWith('"') && name.endsWith('"')) ||
            (name.startsWith("'") && name.endsWith("'")))) {
      name = name.substring(1, name.length - 1).trim();
    }
    if (name.isEmpty) {
      errors.add('Line ${index + 1}: item name is missing.');
      continue;
    }
    final material = _rapidMaterialFor(name, type, materials);
    final color = _rapidColorFor(name);
    items.add(
      RapidItemDraft(
        name: name,
        type: type,
        quantity: quantity,
        price: price,
        materialId: material?.id ?? '',
        materialName: material?.name ?? '',
        itemColorName: color == null ? '' : _colorHex(color.value),
        itemColorLabel: color?.key ?? '',
      ),
    );
  }
  return RapidizerParseResult(items: items, errors: errors);
}

MaterialRecord? _rapidMaterialFor(
  String name,
  InventoryType type,
  List<MaterialRecord> materials,
) {
  final nameWords = _rapidWords(name);
  final matches =
      materials
          .where(
            (material) =>
                material.typeKey == 'type:${type.name}' &&
                _containsWordSequence(nameWords, _rapidWords(material.name)),
          )
          .toList()
        ..sort((a, b) => b.name.length.compareTo(a.name.length));
  return matches.firstOrNull;
}

List<String> _rapidWords(String value) => value
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((word) => word.isNotEmpty)
    .toList();

bool _containsWordSequence(List<String> words, List<String> sequence) {
  if (sequence.isEmpty || sequence.length > words.length) return false;
  for (var start = 0; start <= words.length - sequence.length; start++) {
    var matches = true;
    for (var offset = 0; offset < sequence.length; offset++) {
      if (words[start + offset] != sequence[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

MapEntry<String, Color>? _rapidColorFor(String name) {
  final normalizedName = name.toLowerCase();
  return itemColorPalette.entries
      .where(
        (entry) =>
            RegExp('\\b${RegExp.escape(entry.key.toLowerCase())}\\b')
                .hasMatch(normalizedName),
      )
      .firstOrNull;
}

String _rapidNumberToken(String value) => value
    .replaceAll(RegExp(r'[$,]'), '')
    .replaceFirst(RegExp(r'^[xX]'), '')
    .replaceFirst(RegExp(r'[xX]$'), '');

String _normalizeTypeName(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

int _levenshteinDistance(String left, String right) {
  if (left == right) return 0;
  if (left.isEmpty) return right.length;
  if (right.isEmpty) return left.length;
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var leftIndex = 0; leftIndex < left.length; leftIndex++) {
    final current = List<int>.filled(right.length + 1, 0);
    current[0] = leftIndex + 1;
    for (var rightIndex = 0; rightIndex < right.length; rightIndex++) {
      final substitution =
          previous[rightIndex] +
          (left.codeUnitAt(leftIndex) == right.codeUnitAt(rightIndex) ? 0 : 1);
      current[rightIndex + 1] = [
        current[rightIndex] + 1,
        previous[rightIndex + 1] + 1,
        substitution,
      ].reduce((a, b) => a < b ? a : b);
    }
    previous = current;
  }
  return previous.last;
}

IconData _typeIcon(InventoryType type) => switch (type) {
  InventoryType.other => Icons.inventory_2_outlined,
  InventoryType.fastener => Icons.hardware_rounded,
  InventoryType.filament => Icons.donut_large_rounded,
  InventoryType.printedPart => Icons.view_in_ar_outlined,
  InventoryType.resin => Icons.opacity_rounded,
  InventoryType.nozzle => Icons.change_history_rounded,
  InventoryType.heatBreak => Icons.compress_rounded,
  InventoryType.heatBlock => Icons.view_in_ar_rounded,
  InventoryType.sock => Icons.shield_outlined,
  InventoryType.custom => Icons.tune_rounded,
};

Color _typeColor(InventoryType type) => switch (type) {
  InventoryType.other => const Color(0xff929aac),
  InventoryType.fastener => const Color(0xffc8a96b),
  InventoryType.filament => const Color(0xff7455ff),
  InventoryType.printedPart => const Color(0xffa987ff),
  InventoryType.resin => const Color(0xffd15cff),
  InventoryType.nozzle => const Color(0xffffb13b),
  InventoryType.heatBreak => const Color(0xff45d2bd),
  InventoryType.heatBlock => const Color(0xffff6b6b),
  InventoryType.sock => const Color(0xff55a8ff),
  InventoryType.custom => const Color(0xff9aa4b8),
};

class _ItemVisual extends StatelessWidget {
  const _ItemVisual({
    required this.item,
    required this.size,
    this.typeIcon,
    this.typeIconImageBytes,
  });
  final InventoryItem item;
  final double size;
  final IconData? typeIcon;
  final Uint8List? typeIconImageBytes;

  @override
  Widget build(BuildContext context) {
    final typeColor = _typeColor(item.type);
    final colorSwatch = _itemColorSwatch(item.itemColorName);
    final previewBytes = item.thumbnailBytes ?? item.imageBytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .3),
      child: SizedBox.square(
        dimension: size,
        child: previewBytes != null
            ? Image.memory(
                previewBytes,
                key: Key('item-product-image-${item.id}'),
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context) * 2)
                    .round()
                    .clamp(96, 512),
              )
            : item.itemColorName.isNotEmpty
            ? Center(
                child: Container(
                  key: Key('item-color-swatch-${item.id}'),
                  width: size * .62,
                  height: size * .62,
                  decoration: BoxDecoration(
                    color: colorSwatch ?? const Color(0xff8c929f),
                    borderRadius: BorderRadius.circular(size * .18),
                  ),
                ),
              )
            : ColoredBox(
                key: Key('item-type-fallback-${item.id}'),
                color: typeColor.withValues(alpha: .16),
                child: typeIconImageBytes == null
                    ? Icon(typeIcon ?? item.icon, color: typeColor)
                    : Padding(
                        padding: EdgeInsets.all(size * .16),
                        child: _CustomTypeImage(
                          bytes: typeIconImageBytes!,
                          imageKey: Key('item-type-image-${item.id}'),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              Icon(typeIcon ?? item.icon, color: typeColor),
                        ),
                      ),
              ),
      ),
    );
  }
}

class _TypeBadgeIcon extends StatelessWidget {
  const _TypeBadgeIcon({this.icon, this.imageBytes, this.size = 16});

  final IconData? icon;
  final Uint8List? imageBytes;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: imageBytes == null
        ? Icon(icon ?? Icons.inventory_2_outlined, size: size)
        : _CustomTypeImage(
            bytes: imageBytes!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                Icon(icon ?? Icons.inventory_2_outlined, size: size),
          ),
  );
}

class _ArchiveBadge extends StatelessWidget {
  const _ArchiveBadge({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (item.archiveDisposition) {
      ArchiveDisposition.archived => (
        'Archived',
        Icons.archive_outlined,
        const Color(0xff929aac),
      ),
      ArchiveDisposition.depleted => (
        'Depleted',
        Icons.hourglass_empty_rounded,
        const Color(0xffffa552),
      ),
      ArchiveDisposition.destroyed => (
        'Destroyed',
        Icons.broken_image_outlined,
        const Color(0xffff6b6b),
      ),
    };
    return Chip(
      key: Key('archive-${item.archiveDisposition.name}-${item.id}'),
      avatar: Icon(icon, size: 17, color: color),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: .55)),
      backgroundColor: color.withValues(alpha: .12),
      visualDensity: VisualDensity.compact,
    );
  }
}

class ItemDetailsPanel extends StatefulWidget {
  const ItemDetailsPanel({
    super.key,
    required this.item,
    required this.onChanged,
    required this.machines,
    required this.machineTypes,
    required this.spoolTypes,
    this.onEdit,
    this.onSplitOne,
    this.typeLabel,
    this.typeIcon,
    this.typeIconImageBytes,
    this.initialWidth = 520,
    this.onWidthChanged,
    this.canEdit = true,
    this.canArchive = true,
    this.canMarkDepleted = true,
    this.showStatus = true,
    this.onStorageLocationTap,
  });
  final InventoryItem item;
  final ValueChanged<InventoryItem> onChanged;
  final List<MachineRecord> machines;
  final List<MachineTypeRecord> machineTypes;
  final List<SpoolTypeRecord> spoolTypes;
  final Future<void> Function(InventoryItem item)? onEdit;
  final Future<void> Function(InventoryItem item)? onSplitOne;
  final String? typeLabel;
  final IconData? typeIcon;
  final Uint8List? typeIconImageBytes;
  final double initialWidth;
  final ValueChanged<double>? onWidthChanged;
  final bool canEdit;
  final bool canArchive;
  final bool canMarkDepleted;
  final bool showStatus;
  final Future<void> Function()? onStorageLocationTap;

  @override
  State<ItemDetailsPanel> createState() => _ItemDetailsPanelState();
}

enum _FilamentSidebarTab { instructions, spool, brand }

class _ItemDetailsPanelState extends State<ItemDetailsPanel> {
  bool useFahrenheit = false;
  _FilamentSidebarTab filamentSidebarTab = _FilamentSidebarTab.instructions;
  late InventoryItem item;
  late double panelWidth;

  Future<void> _closeThen(
    Future<void> Function(InventoryItem item) action,
  ) async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await action(item);
  }

  Future<void> _openStorageLocation() async {
    final openLocation = widget.onStorageLocationTap;
    if (openLocation == null) return;
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await openLocation();
  }

  @override
  void initState() {
    super.initState();
    item = widget.item;
    panelWidth = widget.initialWidth;
  }

  Widget _sidebarStatusSelector() => Column(
    key: const Key('sidebar-status-selector'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.showStatus) ...[
        const Text('Status', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
      ],
      if (widget.showStatus && item.type == InventoryType.filament)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statusChip(
              FilamentStatus.ready,
              'Ready',
              Icons.check_rounded,
              const Color(0xff45d2bd),
            ),
            _statusChip(
              FilamentStatus.deployed,
              'Deployed',
              Icons.lock_outline_rounded,
              const Color(0xff55a8ff),
            ),
            _statusChip(
              FilamentStatus.drying,
              'Drying',
              Icons.water_drop_outlined,
              const Color(0xff9c83ff),
            ),
            _statusChip(
              FilamentStatus.queuedForDrying,
              'Wet',
              Icons.water_drop_rounded,
              const Color(0xffffa552),
            ),
          ],
        )
      else if (widget.showStatus)
        FilterChip(
          key: const Key('item-deployed'),
          avatar: const Icon(Icons.lock_outline_rounded, size: 18),
          label: const Text('Deployed'),
          selected: item.deployed,
          selectedColor: const Color(0xff55a8ff).withValues(alpha: .28),
          onSelected: widget.canEdit ? _setDeployed : null,
        ),
      if (_isLowStock(item)) ...[
        const SizedBox(height: 10),
        Chip(
          key: const Key('low-stock-status'),
          avatar: const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xffffa552),
            size: 18,
          ),
          label: Text(
            'Low stock · ${_formatBomQuantity(item.quantity)} remaining',
          ),
          side: const BorderSide(color: Color(0xffffa552)),
        ),
      ],
    ],
  );

  Widget _sidebarColorCard({required bool overlay}) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: overlay ? 12 : 0,
          sigmaY: overlay ? 12 : 0,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _themeCanvas(context).withValues(alpha: overlay ? .82 : .7),
            border: Border.all(
              color: Colors.white.withValues(alpha: overlay ? .2 : .1),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: overlay ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Container(
                key: const Key('sidebar-color-swatch'),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color:
                      _itemColorSwatch(item.itemColorName) ??
                      const Color(0xff8c929f),
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              const SizedBox(width: 11),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.itemColorLabel.isEmpty
                          ? 'Color'
                          : item.itemColorLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _itemColorHex(item.itemColorName),
                      style: const TextStyle(
                        color: Color(0xffc5c9d4),
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return KeyedSubtree(
      key: const Key('sidebar-color-detail'),
      child: overlay
          ? SizedBox(key: const Key('sidebar-color-lower-third'), child: card)
          : card,
    );
  }

  Widget _sidebarImageTitleCard() => ClipRRect(
    key: const Key('sidebar-item-title-overlay'),
    borderRadius: BorderRadius.circular(14),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _themeCanvas(context).withValues(alpha: .82),
          border: Border.all(color: Colors.white.withValues(alpha: .2)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                item.name,
                key: const Key('sidebar-item-name'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            KeyedSubtree(
              key: const Key('sidebar-item-quantity'),
              child: _QuantityBadge(item: item),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _sidebarTypeHeader() => Column(
    key: const Key('sidebar-type-indicator'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          _TypeBadgeIcon(
            icon: widget.typeIcon,
            imageBytes: widget.typeIconImageBytes,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              (widget.typeLabel ?? item.typeLabel).toUpperCase(),
              style: TextStyle(
                color: _itemCardChromeColor,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('split-one-item'),
              onPressed: item.quantity > 1 && widget.onSplitOne != null
                  ? () => _closeThen(widget.onSplitOne!)
                  : null,
              icon: const Icon(Icons.call_split_rounded),
              label: const Text('Split one'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              key: const Key('edit-item-top'),
              onPressed: widget.onEdit == null
                  ? null
                  : () => _closeThen(widget.onEdit!),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _filamentTabButton(
    _FilamentSidebarTab tab,
    String label,
    IconData icon,
  ) {
    final selected = filamentSidebarTab == tab;
    return Expanded(
      child: InkWell(
        key: Key('filament-details-tab-${tab.name}'),
        borderRadius: BorderRadius.circular(11),
        onTap: () => setState(() => filamentSidebarTab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: .28)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xff929aac),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xfff1edff)
                        : const Color(0xffa2a9b9),
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filamentDetailsTabs({
    required String printingInstructions,
    required String dryingInstructions,
    required String storageInstructions,
    required DryingSettings dryingSettings,
    required int? dryingDuration,
  }) {
    final spoolDimensions = [
      if (item.spoolOuterDiameterMm != null)
        'OD ${_optionalNumber(item.spoolOuterDiameterMm)} mm',
      if (item.spoolWidthMm != null)
        'width ${_optionalNumber(item.spoolWidthMm)} mm',
      if (item.spoolHoleDiameterMm != null)
        'hole ID ${_optionalNumber(item.spoolHoleDiameterMm)} mm',
    ].join(' · ');
    final content = switch (filamentSidebarTab) {
      _FilamentSidebarTab.instructions => <Widget>[
        _DetailSection(
          icon: Icons.print_outlined,
          title: 'Printing instructions',
          text: printingInstructions,
        ),
        _DetailSection(
          icon: Icons.air_rounded,
          title: 'Drying instructions',
          text: dryingInstructions,
        ),
        Row(
          children: [
            const Text(
              'Drying profile',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            SegmentedButton<bool>(
              key: const Key('temperature-unit-toggle'),
              segments: const [
                ButtonSegment(value: false, label: Text('°C')),
                ButtonSegment(value: true, label: Text('°F')),
              ],
              selected: {useFahrenheit},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => useFahrenheit = selection.first),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DetailSection(
          icon: Icons.thermostat_rounded,
          title: 'Drying temperature',
          text: dryingSettings.temperatureC == null
              ? 'Not configured'
              : _dryingTemperatureLabel(
                  dryingSettings.temperatureC!,
                  useFahrenheit,
                ),
        ),
        _DetailSection(
          icon: Icons.timer_outlined,
          title: 'Drying duration',
          text: dryingDuration == null
              ? 'Not configured'
              : _dryingDurationLabel(dryingDuration),
        ),
        _DetailSection(
          icon: Icons.inventory_2_outlined,
          title: 'Storage',
          text: storageInstructions,
        ),
      ],
      _FilamentSidebarTab.spool => <Widget>[
        _DetailSection(
          icon: Icons.scale_outlined,
          title: 'Filament weight',
          text:
              widget.spoolTypes
                  .where((spool) => spool.id == item.spoolTypeId)
                  .firstOrNull
                  ?.label ??
              '1 kg',
        ),
        if (item.spoolTareWeightGrams != null)
          _DetailSection(
            icon: Icons.monitor_weight_outlined,
            title: 'Empty spool weight',
            text: '${_optionalNumber(item.spoolTareWeightGrams)} g tare',
          ),
        _DetailSection(
          icon: Icons.straighten_rounded,
          title: 'Spool dimensions',
          text: spoolDimensions.isEmpty ? 'Not configured' : spoolDimensions,
        ),
        _DetailSection(
          icon: item.refill
              ? Icons.recycling_rounded
              : Icons.donut_large_rounded,
          title: 'Spool format',
          text: item.refill
              ? 'Refill / reload${item.masterSpool.isEmpty ? '' : ' · ${item.masterSpool}'}'
              : 'Factory spool',
        ),
        _DetailSection(
          icon: item.amsCompatible
              ? Icons.check_circle_outline_rounded
              : Icons.block_rounded,
          title: 'AMS compatibility',
          text: item.amsCompatible ? 'Compatible' : 'Not marked compatible',
        ),
      ],
      _FilamentSidebarTab.brand => <Widget>[
        _DetailSection(
          icon: Icons.storefront_outlined,
          title: 'Vendor',
          text: item.vendor,
        ),
        _DetailSection(
          icon: Icons.sell_outlined,
          title: 'Brand',
          text: item.brand,
        ),
      ],
    };
    return Column(
      key: const Key('filament-details-tabs'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _themeCanvas(context).withValues(alpha: .55),
            border: Border.all(color: const Color(0xff34394a)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _filamentTabButton(
                _FilamentSidebarTab.instructions,
                'Instructions',
                Icons.menu_book_outlined,
              ),
              _filamentTabButton(
                _FilamentSidebarTab.spool,
                'Spool / AMS',
                Icons.donut_large_rounded,
              ),
              _filamentTabButton(
                _FilamentSidebarTab.brand,
                'Brand',
                Icons.sell_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        AnimatedSwitcher(
          key: const Key('filament-details-tab-content'),
          duration: const Duration(milliseconds: 180),
          child: Column(
            key: ValueKey(filamentSidebarTab),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: content,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectivePrinting = _effectivePrintingInstructions(item);
    final effectiveDrying = _effectiveDryingInstructions(item);
    final effectiveStorage = _effectiveStorageInstructions(item);
    final dryingSettings = parseDryingSettings(effectiveDrying);
    final dryingDuration = item.dryingMinutes ?? dryingSettings.durationMinutes;
    final desktopResizable = Platform.isLinux || Platform.isWindows;
    final availableWidth = MediaQuery.sizeOf(context).width;
    final minimumWidth = math.min(380.0, availableWidth);
    final maximumWidth = desktopResizable
        ? math.max(minimumWidth, availableWidth - 48)
        : availableWidth;
    final effectivePanelWidth = desktopResizable
        ? panelWidth.clamp(minimumWidth, maximumWidth).toDouble()
        : availableWidth;
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceContainerLow,
            ],
          ),
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .55),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .22),
              blurRadius: 36,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: effectivePanelWidth,
            height: double.infinity,
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    desktopResizable ? 34 : 28,
                    28,
                    28,
                    28,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sidebarTypeHeader(),
                      const SizedBox(height: 14),
                      if (item.imageBytes != null)
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.memory(
                                item.imageBytes!,
                                key: const Key('sidebar-product-image'),
                                width: double.infinity,
                                fit: BoxFit.fitWidth,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            if (item.itemColorName.isNotEmpty)
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 12,
                                child: _sidebarColorCard(overlay: true),
                              ),
                            Positioned(
                              top: 12,
                              left: 12,
                              right: widget.showStatus && item.quantity > 0
                                  ? 82
                                  : 12,
                              child: _sidebarImageTitleCard(),
                            ),
                            if (widget.showStatus && item.quantity > 0)
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  key: const Key('sidebar-photo-status'),
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: _themeCanvas(context)
                                        .withValues(alpha: .8),
                                    shape: BoxShape.circle,
                                  ),
                                  child: CountdownRing(
                                    key: Key('sidebar-photo-timer-${item.id}'),
                                    item: item,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      SizedBox(height: item.imageBytes == null ? 10 : 24),
                      if (widget.showStatus || _isLowStock(item))
                        _sidebarStatusSelector(),
                      if (item.imageBytes == null) ...[
                        const SizedBox(height: 22),
                        Row(
                          key: const Key('sidebar-item-heading'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                key: const Key('sidebar-item-name'),
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            KeyedSubtree(
                              key: const Key('sidebar-item-quantity'),
                              child: _QuantityBadge(item: item),
                            ),
                          ],
                        ),
                      ],
                      SizedBox(height: item.imageBytes == null ? 8 : 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${item.cost.toStringAsFixed(2)}',
                            key: const Key('sidebar-item-cost'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (item.type == InventoryType.filament &&
                              (item.filamentStatus == FilamentStatus.ready ||
                                  item.filamentStatus ==
                                      FilamentStatus.deployed)) ...[
                            const Spacer(),
                            Column(
                              key: const Key('sidebar-item-dried'),
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'Dried',
                                  style: TextStyle(
                                    color: Color(0xff929aac),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _timeSinceDried(item.lastDriedAt),
                                  style: const TextStyle(
                                    color: Color(0xffd6d2df),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.compatibility.join('  •  '),
                        style: const TextStyle(color: Color(0xff929aac)),
                      ),
                      if (item.compatibleMachineIds.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Compatible machines',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.machines
                              .where(
                                (machine) => item.compatibleMachineIds.contains(
                                  machine.id,
                                ),
                              )
                              .map((machine) {
                                final type = widget.machineTypes
                                    .where(
                                      (value) => value.id == machine.typeId,
                                    )
                                    .firstOrNull;
                                return Chip(
                                  avatar: const Icon(
                                    Icons.memory_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    type == null
                                        ? machine.name
                                        : '${machine.name} · ${type.name}',
                                  ),
                                );
                              })
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Container(
                        key: const Key('sidebar-qr-code'),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: QrImageView(
                          data: 'inventorinator:item:${item.id}',
                          version: QrVersions.auto,
                          size: 180,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        item.id,
                        style: const TextStyle(
                          color: Color(0xff929aac),
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        key: const Key('download-qr'),
                        onPressed: () => _downloadQr(context, item),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download labeled QR'),
                      ),
                      if (item.itemColorName.isNotEmpty &&
                          item.imageBytes == null) ...[
                        const SizedBox(height: 22),
                        _sidebarColorCard(overlay: false),
                      ],
                      const SizedBox(height: 28),
                      if (item.quantityAlertThreshold != null)
                        _DetailSection(
                          icon: Icons.notification_important_outlined,
                          title: 'Low-stock alert threshold',
                          text: _formatBomQuantity(
                            item.quantityAlertThreshold!,
                          ),
                        ),
                      if (item.barcode.isNotEmpty)
                        _DetailSection(
                          icon: Icons.barcode_reader,
                          title: 'Product barcode',
                          text: item.barcode,
                        ),
                      if (item.labelImageBytes != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.document_scanner_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Label',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(
                            item.labelImageBytes!,
                            key: const Key('sidebar-label-image'),
                            width: double.infinity,
                            fit: BoxFit.fitWidth,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (item.type == InventoryType.filament)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Card(
                            margin: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              key: const Key('sidebar-storage-location'),
                              onTap: widget.onStorageLocationTap == null
                                  ? null
                                  : _openStorageLocation,
                              leading: const _LocationIcon(
                                key: Key('sidebar-location-pin'),
                              ),
                              title: const Text('Storage location'),
                              subtitle: Text(
                                item.storageLocation.isEmpty
                                    ? 'Not configured'
                                    : item.storageLocation,
                              ),
                              trailing: widget.onStorageLocationTap == null
                                  ? null
                                  : const Icon(
                                      Icons.arrow_forward_rounded,
                                      semanticLabel: 'Open Stockroom location',
                                    ),
                            ),
                          ),
                        ),
                      if (item.type == InventoryType.filament) ...[
                        const Divider(height: 40),
                        Column(
                          key: const Key('filament-moisture-tracking'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Moisture tracking',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 16),
                            _DetailSection(
                              icon: Icons.hourglass_bottom_rounded,
                              title: 'Moisture lifespan',
                              text: item.moistureLifespanMinutes == null
                                  ? 'Not configured — edit this filament to start the countdown'
                                  : _moistureLifespanLabel(item),
                            ),
                            if (item.filamentStatus == FilamentStatus.ready ||
                                item.filamentStatus == FilamentStatus.deployed)
                              _DetailSection(
                                icon: Icons.water_drop_outlined,
                                title: 'Moisture life remaining',
                                text: _moistureRemainingLabel(item),
                              ),
                          ],
                        ),
                      ],
                      if (item.type == InventoryType.filament)
                        _filamentDetailsTabs(
                          printingInstructions: effectivePrinting,
                          dryingInstructions: effectiveDrying,
                          storageInstructions: effectiveStorage,
                          dryingSettings: dryingSettings,
                          dryingDuration: dryingDuration,
                        ),
                      if (item.type != InventoryType.filament)
                        _DetailSection(
                          icon: Icons.storefront_outlined,
                          title: 'Vendor',
                          text: item.vendor,
                        ),
                      if (item.type == InventoryType.filament &&
                          item.filamentStatus == FilamentStatus.deployed)
                        _DetailSection(
                          icon: Icons.precision_manufacturing_outlined,
                          title: 'Deployment location',
                          text: item.deploymentLocation,
                        ),
                      if (item.type == InventoryType.filament &&
                          item.filamentStatus == FilamentStatus.drying)
                        _DetailSection(
                          icon: Icons.timer_outlined,
                          title: 'Drying time remaining',
                          text: '${dryingMinutesRemaining(item)} minutes',
                        ),
                      if (item.type != InventoryType.filament &&
                          item.type.supportsPrinting)
                        _DetailSection(
                          icon: Icons.print_outlined,
                          title: 'Printing instructions',
                          text: item.printingInstructions,
                        ),
                      if (item.type == InventoryType.custom)
                        for (final field in item.customFieldValues.entries)
                          _DetailSection(
                            icon: Icons.tune_rounded,
                            title: field.key,
                            text: field.value.isEmpty
                                ? 'Not configured'
                                : field.value,
                          ),
                      if (item.type != InventoryType.filament)
                        _DetailSection(
                          icon: Icons.inventory_2_outlined,
                          title: 'Storage',
                          text: item.storageInstructions,
                        ),
                      if (item.productUrl.isNotEmpty)
                        _ProductSourceSection(url: item.productUrl),
                      _DetailSection(
                        key: const Key('sidebar-added-to-inventory'),
                        icon: Icons.schedule_rounded,
                        title: 'Added to inventory',
                        text: _age(item.added),
                      ),
                      if (widget.canArchive) ...[
                        const Divider(height: 40),
                        const Text(
                          'Inventory lifecycle',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Retired items remain in Archived so their QR code, history, and salvage potential are preserved.',
                          style: const TextStyle(
                            color: Color(0xff929aac),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (item.archived) ...[
                          _ArchiveBadge(item: item),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const Key('restore-item'),
                            onPressed: () => _setArchiveDisposition(null),
                            icon: const Icon(Icons.unarchive_outlined),
                            label: const Text('Restore to inventory'),
                          ),
                        ] else
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              if (widget.canMarkDepleted)
                                OutlinedButton.icon(
                                  key: const Key('mark-depleted'),
                                  onPressed: () => _setArchiveDisposition(
                                    ArchiveDisposition.depleted,
                                  ),
                                  icon: const Icon(
                                    Icons.hourglass_empty_rounded,
                                  ),
                                  label: const Text('Mark depleted'),
                                ),
                              OutlinedButton.icon(
                                key: const Key('mark-destroyed'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xffff6b6b),
                                ),
                                onPressed: () => _setArchiveDisposition(
                                  ArchiveDisposition.destroyed,
                                ),
                                icon: const Icon(Icons.broken_image_outlined),
                                label: const Text('Mark destroyed'),
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
                if (desktopResizable)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        key: const Key('item-details-resize-handle'),
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (details) {
                          final nextWidth = (panelWidth - details.delta.dx)
                              .clamp(minimumWidth, maximumWidth)
                              .toDouble();
                          setState(() => panelWidth = nextWidth);
                          widget.onWidthChanged?.call(nextWidth);
                        },
                        child: SizedBox(
                          width: 16,
                          child: Center(
                            child: Container(
                              width: 4,
                              height: 54,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary
                                    .withValues(alpha: .7),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setDeployed(bool selected) {
    _commit(
      item.copyWith(
        deployed: selected,
        dryingRemaining: selected ? 0 : item.dryingRemaining,
      ),
    );
  }

  Widget _statusChip(
    FilamentStatus status,
    String label,
    IconData icon,
    Color color,
  ) => FilterChip(
    key: Key('status-${status.name}'),
    avatar: Icon(icon, size: 18),
    label: Text(label),
    selected: item.filamentStatus == status,
    selectedColor: color.withValues(alpha: .28),
    onSelected: widget.canEdit ? (_) => _setFilamentStatus(status) : null,
  );

  void _setFilamentStatus(FilamentStatus status) {
    final duration = item.dryingMinutes;
    if (status == FilamentStatus.drying &&
        (duration == null || duration <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a drying duration in Edit before starting.'),
        ),
      );
      return;
    }
    _commit(
      item.copyWith(
        filamentStatus: status,
        deployed: status == FilamentStatus.deployed,
        dryingRemaining: status == FilamentStatus.drying ? duration : 0,
        dryingStartedAt: status == FilamentStatus.drying
            ? DateTime.now()
            : item.dryingStartedAt,
        lastDriedAt:
            status == FilamentStatus.ready &&
                item.filamentStatus == FilamentStatus.drying
            ? DateTime.now()
            : item.lastDriedAt,
      ),
    );
  }

  void _commit(InventoryItem updated) {
    setState(() => item = updated);
    widget.onChanged(updated);
  }

  void _setArchiveDisposition(ArchiveDisposition? disposition) {
    _commit(
      item.copyWith(
        archived: disposition != null,
        archiveDisposition: disposition ?? ArchiveDisposition.archived,
        deployed: disposition == null ? item.deployed : false,
      ),
    );
    Navigator.pop(context);
  }
}

String _effectiveDryingInstructions(InventoryItem item) {
  if (item.dryingInstructions.trim().isNotEmpty) {
    return item.dryingInstructions.trim();
  }
  return detectFilamentTemplate(
        '${item.name}\n${item.brand}\n${item.printingInstructions}',
      )?.drying ??
      '';
}

String _effectivePrintingInstructions(InventoryItem item) {
  if (item.printingInstructions.trim().isNotEmpty) {
    return item.printingInstructions.trim();
  }
  return detectFilamentTemplate(
        '${item.name}\n${item.brand}\n${item.dryingInstructions}',
      )?.printing ??
      '';
}

String _effectiveStorageInstructions(InventoryItem item) {
  if (item.storageInstructions.trim().isNotEmpty) {
    return item.storageInstructions.trim();
  }
  return detectFilamentTemplate(
        '${item.name}\n${item.brand}\n${item.printingInstructions}\n${item.dryingInstructions}',
      )?.storage ??
      '';
}

String _dryingTemperatureLabel(int celsius, bool useFahrenheit) {
  if (!useFahrenheit) return '$celsius°C';
  return '${((celsius * 9 / 5) + 32).round()}°F';
}

String _dryingDurationLabel(int minutes) {
  if (minutes < 60) return '$minutes minutes';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours hours' : '$hours h $remainder min';
}

String _timeSinceDried(DateTime? lastDriedAt) {
  if (lastDriedAt == null) return 'Never recorded';
  final elapsed = DateTime.now().difference(lastDriedAt);
  if (elapsed.inDays > 0) return '${elapsed.inDays} days';
  if (elapsed.inHours > 0) return '${elapsed.inHours} hours';
  return '${elapsed.inMinutes} minutes';
}

Duration _dryingTimeRemaining(InventoryItem item, {DateTime? now}) {
  final baselineMinutes = item.dryingRemaining ?? item.dryingMinutes ?? 0;
  final startedAt = item.dryingStartedAt;
  if (startedAt == null) return Duration(minutes: baselineMinutes);
  final remaining =
      Duration(minutes: baselineMinutes) -
      (now ?? DateTime.now()).difference(startedAt);
  return remaining.isNegative ? Duration.zero : remaining;
}

int dryingMinutesRemaining(InventoryItem item, {DateTime? now}) {
  final remaining = _dryingTimeRemaining(item, now: now);
  if (remaining <= Duration.zero) return 0;
  return (remaining.inSeconds / 60).ceil();
}

int? _minutesFromAmount(double? amount, MoistureTimeUnit unit) {
  if (amount == null) return null;
  return (amount * (unit == MoistureTimeUnit.days ? 1440 : 60)).round();
}

double? _durationAmount(int? minutes, MoistureTimeUnit unit) {
  if (minutes == null) return null;
  return minutes / (unit == MoistureTimeUnit.days ? 1440 : 60);
}

String? _formatDurationAmount(int? minutes, MoistureTimeUnit unit) {
  final amount = _durationAmount(minutes, unit);
  if (amount == null) return null;
  return amount == amount.roundToDouble()
      ? amount.toInt().toString()
      : amount.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

String _moistureLifespanLabel(InventoryItem item) {
  final amount = _formatDurationAmount(
    item.moistureLifespanMinutes,
    item.moistureTimeUnit,
  );
  return '$amount ${item.moistureTimeUnit.name}';
}

Duration? _moistureRemaining(InventoryItem item, {DateTime? now}) {
  final lifespan = item.moistureLifespanMinutes;
  final lastDried = item.lastDriedAt;
  if (lifespan == null || lifespan <= 0 || lastDried == null) return null;
  return Duration(minutes: lifespan) -
      (now ?? DateTime.now()).difference(lastDried);
}

int compareMoistureRemaining(
  InventoryItem left,
  InventoryItem right, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final leftRemaining = left.type == InventoryType.filament
      ? _moistureRemaining(left, now: reference)
      : null;
  final rightRemaining = right.type == InventoryType.filament
      ? _moistureRemaining(right, now: reference)
      : null;
  if (leftRemaining == null && rightRemaining == null) {
    return left.name.compareTo(right.name);
  }
  if (leftRemaining == null) return 1;
  if (rightRemaining == null) return -1;
  final remainingOrder = leftRemaining.compareTo(rightRemaining);
  return remainingOrder != 0 ? remainingOrder : left.name.compareTo(right.name);
}

String _moistureRemainingLabel(InventoryItem item, {DateTime? now}) {
  final remaining = _moistureRemaining(item, now: now);
  if (remaining == null) return 'Dry date not recorded';
  if (remaining <= Duration.zero) {
    final overdueHours = -remaining.inHours;
    if (overdueHours < 24) return 'Needs Drying';
    return '${(overdueHours / 24).ceil()} days past moisture limit';
  }
  if (remaining.inHours < 24) return '${remaining.inHours + 1} hours remaining';
  return '${(remaining.inHours / 24).ceil()} days remaining';
}

String _moistureRingText(Duration remaining) {
  if (remaining <= Duration.zero) return 'WET';
  if (remaining.inHours < 24) return '${remaining.inHours + 1}H';
  return '${(remaining.inHours / 24).ceil()}D';
}

double moistureLifeProgress(InventoryItem item, {DateTime? now}) {
  final remaining = _moistureRemaining(item, now: now);
  final lifespan = item.moistureLifespanMinutes;
  if (remaining == null || lifespan == null || lifespan <= 0) return 1;
  return (remaining.inSeconds / Duration(minutes: lifespan).inSeconds).clamp(
    0.0,
    1.0,
  );
}

String qrDownloadFileName(InventoryItem item) {
  final safeName = item.name
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '${safeName.isEmpty ? 'Inventory-Item' : safeName}_${item.id}_QR.png';
}

String locationQrDownloadFileName(StockLocationRecord location, String path) {
  final safeName = path
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '${safeName.isEmpty ? 'Stockroom-Location' : safeName}_${location.id}_QR.png';
}

Future<void> _downloadQr(BuildContext context, InventoryItem item) =>
    _downloadLabeledQr(
      context,
      payload: 'inventorinator:item:${item.id}',
      title: item.name,
      id: item.id,
      fileName: qrDownloadFileName(item),
      dialogTitle: 'Save QR for ${item.name}',
    );

Future<void> _downloadLocationQr(
  BuildContext context,
  StockLocationRecord location,
  String path,
) => _downloadLabeledQr(
  context,
  payload: 'inventorinator:location:${location.id}',
  title: path,
  id: location.id,
  fileName: locationQrDownloadFileName(location, path),
  dialogTitle: 'Save QR for $path',
);

Future<void> _downloadLabeledQr(
  BuildContext context, {
  required String payload,
  required String title,
  required String id,
  required String fileName,
  required String dialogTitle,
}) async {
  const width = 1200.0;
  const height = 1400.0;
  const qrSize = 1040.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  canvas.save();
  canvas.translate(80, 80);
  QrPainter(
    data: payload,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Colors.black,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Colors.black,
    ),
  ).paint(canvas, const Size.square(qrSize));
  canvas.restore();
  final titlePainter = TextPainter(
    text: TextSpan(
      text: title,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 54,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: 1040);
  titlePainter.paint(canvas, Offset((width - titlePainter.width) / 2, 1160));
  final idPainter = TextPainter(
    text: TextSpan(
      text: id,
      style: const TextStyle(
        color: Color(0xff333333),
        fontSize: 34,
        fontFamily: 'monospace',
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 1040);
  idPainter.paint(canvas, Offset((width - idPainter.width) / 2, 1240));
  final image = await recorder.endRecording().toImage(
    width.toInt(),
    height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null || !context.mounted) return;
  final uri = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    bytes: data.buffer.asUint8List(),
    mimeType: 'image/png',
  );
  if (uri != null && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Saved $fileName')));
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(
                text.isEmpty ? 'No instructions recorded.' : text,
                style: const TextStyle(color: Color(0xffa2a9b9), height: 1.45),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProductSourceSection extends StatelessWidget {
  const _ProductSourceSection({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.link_rounded, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Product source',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              InkWell(
                key: const Key('open-product-source'),
                onTap: () {
                  final uri = Uri.tryParse(url);
                  if (uri != null) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(
                  url,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CompatibleFilamentsDialog extends StatelessWidget {
  const _CompatibleFilamentsDialog({
    required this.printedPart,
    required this.filaments,
    required this.spoolSizeLabel,
  });

  final InventoryItem printedPart;
  final List<InventoryItem> filaments;
  final String Function(InventoryItem) spoolSizeLabel;

  @override
  Widget build(BuildContext context) {
    final unconstrained =
        printedPart.compatibility.isEmpty &&
        printedPart.compatibleMachineIds.isEmpty;
    return AlertDialog(
      title: const Text('Compatible filaments'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              printedPart.name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              unconstrained
                  ? 'No material or machine constraints are set, so all stocked filament is shown.'
                  : 'Matched from shared compatible Machines and Compatibility / tags.',
              style: const TextStyle(color: Color(0xff929aac)),
            ),
            const SizedBox(height: 14),
            if (filaments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    Icon(Icons.search_off_rounded, size: 42),
                    SizedBox(height: 10),
                    Text('No compatible filament is currently in stock.'),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 430),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filaments.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final filament = filaments[index];
                    final details = <String>[
                      if (filament.brand.isNotEmpty) filament.brand,
                      spoolSizeLabel(filament),
                      '×${_formatBomQuantity(filament.quantity)} in stock',
                      if (filament.storageLocation.isNotEmpty)
                        filament.storageLocation,
                    ];
                    return ListTile(
                      key: Key('compatible-filament-${filament.id}'),
                      leading: _ItemVisual(item: filament, size: 38),
                      title: Text(filament.name),
                      subtitle: Text(details.join(' · ')),
                      trailing: filament.amsCompatible
                          ? const Tooltip(
                              message: 'AMS compatible',
                              child: Icon(Icons.check_circle_outline_rounded),
                            )
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class ItemContextRegion extends StatelessWidget {
  const ItemContextRegion({
    super.key,
    required this.item,
    required this.onAction,
    this.spoolSizeLabel = '',
    this.canEdit = true,
    this.canCreate = true,
    this.canArchive = true,
    this.canDelete = true,
    this.onSelect,
    required this.child,
  });
  final InventoryItem item;
  final ValueChanged<ItemAction> onAction;
  final String spoolSizeLabel;
  final bool canEdit;
  final bool canCreate;
  final bool canArchive;
  final bool canDelete;
  final VoidCallback? onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onSecondaryTapDown: (details) =>
        _showActions(context, details.globalPosition),
    onLongPressStart: (details) {
      final touchPlatform =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      if (touchPlatform && onSelect != null) {
        HapticFeedback.mediumImpact();
        onSelect!();
        return;
      }
      _showActions(context, details.globalPosition);
    },
    child: child,
  );

  Future<void> _showActions(BuildContext context, Offset position) async {
    final action = await showMenu<ItemAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 300),
      items: [
        if (item.type == InventoryType.printedPart)
          const PopupMenuItem(
            value: ItemAction.showCompatibleFilaments,
            height: 52,
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: _PopupActionRow(
              actionKey: 'compatible-filaments',
              icon: Icons.donut_large_rounded,
              label: 'Show compatible filaments',
            ),
          ),
        if (canEdit)
          const PopupMenuItem(
            value: ItemAction.resetDryTimer,
            height: 52,
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: _PopupActionRow(
              actionKey: 'reset-dry-timer',
              icon: Icons.restart_alt_rounded,
              label: 'Reset dry timer',
            ),
          ),
        if (canEdit)
          const PopupMenuItem(
            value: ItemAction.edit,
            height: 52,
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: _PopupActionRow(
              actionKey: 'edit',
              icon: Icons.edit_outlined,
              label: 'Edit',
            ),
          ),
        if (canCreate)
          const PopupMenuItem(
            value: ItemAction.duplicate,
            height: 52,
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: _PopupActionRow(
              actionKey: 'duplicate',
              icon: Icons.copy_rounded,
              label: 'Duplicate',
            ),
          ),
        if (canArchive)
          PopupMenuItem(
            value: ItemAction.archive,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _PopupActionRow(
              actionKey: item.archived ? 'restore' : 'archive',
              icon: item.archived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              label: item.archived ? 'Restore' : 'Archive',
            ),
          ),
        if (canDelete) const PopupMenuDivider(height: 12),
        if (canDelete)
          const PopupMenuItem(
            value: ItemAction.delete,
            height: 52,
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: _PopupActionRow(
              actionKey: 'delete',
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              destructive: true,
            ),
          ),
      ],
    );
    if (action != null) onAction(action);
  }
}

class _PopupActionRow extends StatelessWidget {
  const _PopupActionRow({
    required this.actionKey,
    required this.icon,
    required this.label,
    this.destructive = false,
    this.selected = false,
  });

  final String actionKey;
  final IconData icon;
  final String label;
  final bool destructive;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent = destructive
        ? const Color(0xffff6b7a)
        : Theme.of(context).colorScheme.primary;
    return Row(
      key: Key('context-action-$actionKey'),
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: destructive
                  ? accent
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (selected)
          Icon(
            Icons.check_rounded,
            size: 19,
            color: Theme.of(context).colorScheme.primary,
          ),
      ],
    );
  }
}

class _QuantityBadge extends StatelessWidget {
  const _QuantityBadge({required this.item, this.compact = false});

  final InventoryItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lowStock = _isLowStock(item);
    final accent = lowStock ? const Color(0xffffa552) : _itemCardChromeColor;
    final light = Theme.of(context).brightness == Brightness.light;
    final background = light
        ? Color.alphaBlend(
            accent.withValues(alpha: lowStock ? .22 : .04),
            const Color(0xff30313a),
          )
        : Color.alphaBlend(
            accent.withValues(alpha: lowStock ? .24 : .1),
            _themeCanvas(context).withValues(alpha: .82),
          );
    return Container(
      key: Key('item-quantity-${item.id}'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 11,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: lowStock
              ? accent.withValues(alpha: .72)
              : light
              ? const Color(0xff686a76)
              : accent.withValues(alpha: .65),
        ),
        boxShadow: lowStock
            ? [BoxShadow(color: accent.withValues(alpha: .2), blurRadius: 14)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lowStock) ...[
            Icon(
              Icons.warning_amber_rounded,
              color: const Color(0xffffa552),
              size: compact ? 15 : 17,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            '×${_formatBomQuantity(item.quantity)}',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 15 : 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (lowStock && !compact) ...[
            const SizedBox(width: 6),
            const Text(
              'LOW',
              style: TextStyle(
                color: Color(0xffffa552),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.item,
    this.onQuantityChanged,
    this.compact = false,
  });

  final InventoryItem item;
  final ValueChanged<double>? onQuantityChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final editable = onQuantityChanged != null && !item.archived;
    if (!editable) return _QuantityBadge(item: item, compact: compact);
    return Row(
      key: Key('item-quantity-stepper-${item.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _QuantityStepButton(
          key: Key('decrease-quantity-${item.id}'),
          icon: Icons.remove_rounded,
          tooltip: 'Decrease quantity',
          compact: compact,
          onPressed: item.quantity > 0 ? () => onQuantityChanged!(-1) : null,
        ),
        SizedBox(width: compact ? 3 : 5),
        _QuantityBadge(item: item, compact: compact),
        SizedBox(width: compact ? 3 : 5),
        _QuantityStepButton(
          key: Key('increase-quantity-${item.id}'),
          icon: Icons.add_rounded,
          tooltip: 'Increase quantity',
          compact: compact,
          onPressed: () => onQuantityChanged!(1),
        ),
      ],
    );
  }
}

class _QuantityStepButton extends StatelessWidget {
  const _QuantityStepButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.compact = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 28.0 : 32.0;
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        tooltip: tooltip,
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        iconSize: compact ? 17 : 19,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _MaterialBadge extends StatelessWidget {
  const _MaterialBadge({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('item-material-${item.id}'),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: _itemCardChromeColor.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _itemCardChromeColor.withValues(alpha: .65)),
    ),
    child: Text(
      item.materialName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

bool _isLowStock(InventoryItem item) =>
    !item.archived &&
    item.quantityAlertThreshold != null &&
    item.quantity <= item.quantityAlertThreshold!;

Set<String> remoteQuantityChangedItemIds(
  Iterable<InventoryItem> current,
  Iterable<InventoryItem> incoming,
) {
  final currentById = {for (final item in current) item.id: item};
  return incoming
      .where(
        (item) =>
            currentById.containsKey(item.id) &&
            currentById[item.id]!.quantity != item.quantity,
      )
      .map((item) => item.id)
      .toSet();
}

Set<String> lowStockEnteredItemIds(
  Iterable<InventoryItem> current,
  Iterable<InventoryItem> incoming,
) {
  final currentById = {for (final item in current) item.id: item};
  return incoming
      .where(
        (item) =>
            currentById.containsKey(item.id) &&
            !_isLowStock(currentById[item.id]!) &&
            _isLowStock(item),
      )
      .map((item) => item.id)
      .toSet();
}

Duration _scaledAnimationDuration(int milliseconds, int percent) => Duration(
  milliseconds: (milliseconds * percent.clamp(25, 200) / 100).round(),
);

bool _isEffectWidgetVisible(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached) return false;
  final origin = renderObject.localToGlobal(Offset.zero);
  final bounds = origin & renderObject.size;
  return bounds.overlaps(Offset.zero & MediaQuery.sizeOf(context));
}

bool _hasMoistureVisualAlert(InventoryItem item, {DateTime? now}) {
  if (item.archived ||
      item.type != InventoryType.filament ||
      item.filamentStatus == FilamentStatus.drying) {
    return false;
  }
  final remaining = _moistureRemaining(item, now: now);
  if (remaining == null) return false;
  if (remaining <= Duration.zero) return true;
  return item.moistureAlertEnabled &&
      item.moistureAlertThresholdMinutes != null &&
      remaining <= Duration(minutes: item.moistureAlertThresholdMinutes!);
}

class RemoteQuantityChangeEffect extends StatefulWidget {
  const RemoteQuantityChangeEffect({
    super.key,
    required this.itemId,
    required this.trigger,
    required this.durationPercent,
    required this.child,
  });
  final String itemId;
  final int trigger;
  final int durationPercent;
  final Widget child;

  @override
  State<RemoteQuantityChangeEffect> createState() =>
      _RemoteQuantityChangeEffectState();
}

class _RemoteQuantityChangeEffectState extends State<RemoteQuantityChangeEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: _scaledAnimationDuration(1700, widget.durationPercent),
  );

  @override
  void didUpdateWidget(covariant RemoteQuantityChangeEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.durationPercent != oldWidget.durationPercent) {
      controller.duration = _scaledAnimationDuration(
        1700,
        widget.durationPercent,
      );
    }
    if (widget.trigger > 0 && widget.trigger != oldWidget.trigger) {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final travel = Curves.easeInOutCubic.transform(controller.value);
        final opacity = controller.value < .22
            ? controller.value / .22
            : (1 - controller.value) / .78;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (.24 * opacity).clamp(0, 1),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1.8 + travel, -1.8 + travel),
                        end: Alignment(.2 + travel, .2 + travel),
                        colors: const [
                          Color(0xff7455ff),
                          Color(0xff45d2bd),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (.48 * opacity).clamp(0, 1),
                  child: Align(
                    alignment: Alignment(
                      -1.45 + (2.9 * travel),
                      -1.45 + (2.9 * travel),
                    ),
                    child: Transform.scale(
                      scale: .72 + (.28 * travel),
                      child: Icon(
                        Icons.south_east_rounded,
                        key: Key('remote-quantity-arrow-${widget.itemId}'),
                        size: 108,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Color(0xff45d2bd), blurRadius: 22),
                          Shadow(color: Color(0xff7455ff), blurRadius: 34),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child!,
          ],
        );
      },
    ),
  );
}

class LowStockPulseEffect extends StatefulWidget {
  const LowStockPulseEffect({
    super.key,
    required this.itemId,
    required this.trigger,
    required this.active,
    required this.durationPercent,
    required this.recurrenceSeconds,
    this.playWhenFirstVisible = true,
    required this.child,
  });
  final String itemId;
  final int trigger;
  final bool active;
  final int durationPercent;
  final int recurrenceSeconds;
  final bool playWhenFirstVisible;
  final Widget child;

  @override
  State<LowStockPulseEffect> createState() => _LowStockPulseEffectState();
}

class _LowStockPulseEffectState extends State<LowStockPulseEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: _scaledAnimationDuration(1450, widget.durationPercent),
  );
  Timer? recurrenceTimer;
  ValueNotifier<bool>? scrollingNotifier;
  bool wasVisible = false;

  @override
  void initState() {
    super.initState();
    _restartVisibilityTracking();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextNotifier = Scrollable.maybeOf(context)
        ?.position
        .isScrollingNotifier;
    if (identical(scrollingNotifier, nextNotifier)) return;
    scrollingNotifier?.removeListener(_handleScrollingChanged);
    scrollingNotifier = nextNotifier;
    scrollingNotifier?.addListener(_handleScrollingChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  @override
  void didUpdateWidget(covariant LowStockPulseEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.durationPercent != oldWidget.durationPercent) {
      controller.duration = _scaledAnimationDuration(
        1450,
        widget.durationPercent,
      );
    }
    if (widget.active != oldWidget.active ||
        widget.recurrenceSeconds != oldWidget.recurrenceSeconds) {
      _restartVisibilityTracking();
    }
    if (widget.trigger > 0 && widget.trigger != oldWidget.trigger) {
      controller.forward(from: 0);
    }
  }

  void _restartVisibilityTracking() {
    recurrenceTimer?.cancel();
    // Mounting a recycled sliver child is not a new alert. Starting an effect
    // here made every low-stock card animate as it entered the viewport.
    wasVisible = widget.active && !widget.playWhenFirstVisible;
    if (!widget.active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    if (widget.recurrenceSeconds > 0) {
      recurrenceTimer = Timer.periodic(
        Duration(seconds: widget.recurrenceSeconds),
        (_) => _playIfVisible(),
      );
    }
  }

  void _handleScrollingChanged() {
    if (scrollingNotifier?.value ?? false) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  void _checkVisibility() {
    if (!mounted || !widget.active) return;
    final visible = _isEffectWidgetVisible(context);
    if (visible && !wasVisible && !controller.isAnimating) {
      controller.forward(from: 0);
    }
    wasVisible = visible;
  }

  void _playIfVisible() {
    if (mounted &&
        widget.active &&
        _isEffectWidgetVisible(context) &&
        !controller.isAnimating) {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    scrollingNotifier?.removeListener(_handleScrollingChanged);
    recurrenceTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final pulse = controller.value < .35
            ? controller.value / .35
            : (1 - controller.value) / .65;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (.34 * pulse).clamp(0, 1),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0xffffc857), Color(0xffff8a3d)],
                        radius: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (.52 * pulse).clamp(0, 1),
                  child: Transform.scale(
                    scale: .72 + (.42 * pulse),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      key: Key('low-stock-pulse-${widget.itemId}'),
                      size: 112,
                      color: Colors.white,
                      shadows: const [
                        Shadow(color: Color(0xffffc857), blurRadius: 30),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            child!,
          ],
        );
      },
    ),
  );
}

class MoistureDropletWaveEffect extends StatefulWidget {
  const MoistureDropletWaveEffect({
    super.key,
    required this.itemId,
    required this.trigger,
    required this.active,
    required this.durationPercent,
    required this.recurrenceSeconds,
    this.playWhenFirstVisible = true,
    required this.child,
  });
  final String itemId;
  final int trigger;
  final bool active;
  final int durationPercent;
  final int recurrenceSeconds;
  final bool playWhenFirstVisible;
  final Widget child;

  @override
  State<MoistureDropletWaveEffect> createState() =>
      _MoistureDropletWaveEffectState();
}

class _MoistureDropletWaveEffectState extends State<MoistureDropletWaveEffect>
    with SingleTickerProviderStateMixin {
  static const horizontalPositions = [-.72, -.2, .38, .76, -.48, .08, .58];
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: _scaledAnimationDuration(2300, widget.durationPercent),
  );
  Timer? recurrenceTimer;
  ValueNotifier<bool>? scrollingNotifier;
  bool wasVisible = false;

  @override
  void initState() {
    super.initState();
    _restartVisibilityTracking();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextNotifier = Scrollable.maybeOf(context)
        ?.position
        .isScrollingNotifier;
    if (identical(scrollingNotifier, nextNotifier)) return;
    scrollingNotifier?.removeListener(_handleScrollingChanged);
    scrollingNotifier = nextNotifier;
    scrollingNotifier?.addListener(_handleScrollingChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  @override
  void didUpdateWidget(covariant MoistureDropletWaveEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.durationPercent != oldWidget.durationPercent) {
      controller.duration = _scaledAnimationDuration(
        2300,
        widget.durationPercent,
      );
    }
    if (widget.active != oldWidget.active ||
        widget.recurrenceSeconds != oldWidget.recurrenceSeconds) {
      _restartVisibilityTracking();
    }
    if (widget.trigger > 0 && widget.trigger != oldWidget.trigger) {
      controller.forward(from: 0);
    }
  }

  void _restartVisibilityTracking() {
    recurrenceTimer?.cancel();
    // Do not replay an old moisture alert just because scrolling remounted it.
    wasVisible = widget.active && !widget.playWhenFirstVisible;
    if (!widget.active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    if (widget.recurrenceSeconds > 0) {
      recurrenceTimer = Timer.periodic(
        Duration(seconds: widget.recurrenceSeconds),
        (_) => _playIfVisible(),
      );
    }
  }

  void _handleScrollingChanged() {
    if (scrollingNotifier?.value ?? false) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  void _checkVisibility() {
    if (!mounted || !widget.active) return;
    final visible = _isEffectWidgetVisible(context);
    if (visible && !wasVisible && !controller.isAnimating) {
      controller.forward(from: 0);
    }
    wasVisible = visible;
  }

  void _playIfVisible() {
    if (mounted &&
        widget.active &&
        _isEffectWidgetVisible(context) &&
        !controller.isAnimating) {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    scrollingNotifier?.removeListener(_handleScrollingChanged);
    recurrenceTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final wash = controller.value < .3
            ? controller.value / .3
            : (1 - controller.value) / .7;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (.2 * wash).clamp(0, 1),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xff55a8ff), Color(0xff45d2bd)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            for (var index = 0; index < horizontalPositions.length; index++)
              _droplet(index),
            child!,
          ],
        );
      },
    ),
  );

  Widget _droplet(int index) {
    final phase = ((controller.value * 1.65) - (index * .11)).clamp(0.0, 1.0);
    final visibility = phase < .22 ? phase / .22 : (1 - phase) / .78;
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: (.72 * visibility).clamp(0, 1),
          child: Align(
            alignment: Alignment(
              horizontalPositions[index],
              -1.35 + (2.7 * Curves.easeIn.transform(phase)),
            ),
            child: Icon(
              Icons.water_drop_rounded,
              key: index == 0 ? Key('moisture-wave-${widget.itemId}') : null,
              size: 22 + ((index % 3) * 8),
              color: index.isEven
                  ? const Color(0xff78c7ff)
                  : const Color(0xff45d2bd),
              shadows: const [Shadow(color: Color(0xff55a8ff), blurRadius: 18)],
            ),
          ),
        ),
      ),
    );
  }
}

class ItemCardEffects extends StatelessWidget {
  const ItemCardEffects({
    super.key,
    required this.itemId,
    required this.quantitySyncVersion,
    required this.lowStockVersion,
    required this.moistureVersion,
    required this.lowStockActive,
    required this.moistureActive,
    required this.durationPercent,
    required this.recurrenceSeconds,
    this.scrollingListenable,
    required this.child,
  });
  final String itemId;
  final int quantitySyncVersion;
  final int lowStockVersion;
  final int moistureVersion;
  final bool lowStockActive;
  final bool moistureActive;
  final int durationPercent;
  final int recurrenceSeconds;
  final ValueListenable<bool>? scrollingListenable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final staticChild = RepaintBoundary(child: child);
    final playWhenFirstVisible = scrollingListenable == null;
    Widget effects(Widget effectChild) => MoistureDropletWaveEffect(
      itemId: itemId,
      trigger: moistureVersion,
      active: moistureActive,
      durationPercent: durationPercent,
      recurrenceSeconds: recurrenceSeconds,
      playWhenFirstVisible: playWhenFirstVisible,
      child: LowStockPulseEffect(
        itemId: itemId,
        trigger: lowStockVersion,
        active: lowStockActive,
        durationPercent: durationPercent,
        recurrenceSeconds: recurrenceSeconds,
        playWhenFirstVisible: playWhenFirstVisible,
        child: RemoteQuantityChangeEffect(
          itemId: itemId,
          trigger: quantitySyncVersion,
          durationPercent: durationPercent,
          child: effectChild,
        ),
      ),
    );
    final scrolling = scrollingListenable;
    if (scrolling == null) return effects(staticChild);
    return ValueListenableBuilder<bool>(
      valueListenable: scrolling,
      child: staticChild,
      builder: (context, isScrolling, cachedChild) =>
          isScrolling ? cachedChild! : effects(cachedChild!),
    );
  }
}

class _PhotoInventoryCardContent extends StatelessWidget {
  const _PhotoInventoryCardContent({
    required this.item,
    required this.typeLabel,
    required this.typeIcon,
    required this.typeIconImageBytes,
    required this.spoolSizeLabel,
    required this.showStatus,
    this.onQuantityChanged,
  });

  final InventoryItem item;
  final String typeLabel;
  final IconData? typeIcon;
  final Uint8List? typeIconImageBytes;
  final String spoolSizeLabel;
  final bool showStatus;
  final ValueChanged<double>? onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final swatch = _itemColorSwatch(item.itemColorName);
    final metadata = [
      if (spoolSizeLabel.isNotEmpty) spoolSizeLabel,
      ...item.compatibility,
    ].join('  •  ');
    return Stack(
      key: Key('photo-card-${item.id}'),
      fit: StackFit.expand,
      children: [
        _CardPhotoBackground(
          bytes: item.thumbnailBytes ?? item.imageBytes!,
          imageKey: Key('photo-card-background-${item.id}'),
        ),
        if (swatch != null) ColoredBox(color: swatch.withValues(alpha: .12)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66080a10), Color(0x22080a10), Color(0xe60a0d14)],
              stops: [0, .42, 1],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _QuantityStepper(
                    item: item,
                    compact: true,
                    onQuantityChanged: onQuantityChanged,
                  ),
                  const Spacer(),
                  if (item.archived)
                    _ArchiveBadge(item: item)
                  else if (showStatus && item.quantity > 0)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _themeCanvas(context).withValues(alpha: .82),
                        shape: BoxShape.circle,
                      ),
                      child: CountdownRing(
                        key: Key('inventory-card-timer-${item.id}'),
                        item: item,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _themeCanvas(context).withValues(alpha: .84),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CardTypeAndPrice(
                      item: item,
                      typeLabel: typeLabel,
                      typeIcon: typeIcon,
                      typeIconImageBytes: typeIconImageBytes,
                      overlay: true,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        metadata,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xffc3c8d3),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (swatch != null || item.materialName.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          if (swatch != null) ...[
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: swatch,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            if (item.itemColorLabel.isNotEmpty) ...[
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  item.itemColorLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ] else
                              const Spacer(),
                          ] else
                            const Spacer(),
                          if (item.materialName.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 130),
                              child: _MaterialBadge(item: item),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardPhotoBackground extends StatelessWidget {
  const _CardPhotoBackground({required this.bytes, required this.imageKey});

  final Uint8List bytes;
  final Key imageKey;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final logicalWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 400.0;
      final requestedWidth =
          (logicalWidth * MediaQuery.devicePixelRatioOf(context)).round();
      // Keep the image-provider key stable while a desktop window is being
      // resized. A per-pixel cacheWidth forces a fresh decode on every frame.
      final cacheWidth = requestedWidth <= 320
          ? 320
          : requestedWidth <= 480
          ? 480
          : requestedWidth <= 720
          ? 720
          : requestedWidth <= 960
          ? 960
          : 1200;
      return Image.memory(
        bytes,
        key: imageKey,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xff1a1525)),
      );
    },
  );
}

class InventoryCard extends StatelessWidget {
  const InventoryCard({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onAction,
    this.onQuantityChanged,
    this.onSelect,
    this.selected = false,
    this.typeLabel,
    this.typeIcon,
    this.typeIconImageBytes,
    this.spoolSizeLabel = '',
    this.quantitySyncVersion = 0,
    this.lowStockAnimationVersion = 0,
    this.moistureAnimationVersion = 0,
    this.animationDurationPercent = 100,
    this.animationRecurrenceSeconds = 5,
    this.scrollingListenable,
    this.photoCard = false,
    this.showStatus = true,
    this.canEdit = true,
    this.canCreate = true,
    this.canArchive = true,
    this.canDelete = true,
  });
  final InventoryItem item;
  final VoidCallback onOpen;
  final ValueChanged<ItemAction> onAction;
  final ValueChanged<double>? onQuantityChanged;
  final VoidCallback? onSelect;
  final bool selected;
  final String? typeLabel;
  final IconData? typeIcon;
  final Uint8List? typeIconImageBytes;
  final String spoolSizeLabel;
  final int quantitySyncVersion;
  final int lowStockAnimationVersion;
  final int moistureAnimationVersion;
  final int animationDurationPercent;
  final int animationRecurrenceSeconds;
  final ValueListenable<bool>? scrollingListenable;
  final bool photoCard;
  final bool showStatus;
  final bool canEdit;
  final bool canCreate;
  final bool canArchive;
  final bool canDelete;

  @override
  Widget build(BuildContext context) => ItemContextRegion(
    item: item,
    onAction: onAction,
    canEdit: canEdit,
    canCreate: canCreate,
    canArchive: canArchive,
    canDelete: canDelete,
    onSelect: onSelect,
    child: Card(
      key: Key('inventory-card-${item.id}'),
      color: selected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: .16)
          : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        hoverColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: .12),
        focusColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: .12),
        highlightColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: .17),
        splashColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: .17),
        child: ItemCardEffects(
          itemId: item.id,
          quantitySyncVersion: quantitySyncVersion,
          lowStockVersion: lowStockAnimationVersion,
          moistureVersion: moistureAnimationVersion,
          lowStockActive: !item.archived && _isLowStock(item),
          moistureActive: _hasMoistureVisualAlert(item),
          durationPercent: animationDurationPercent,
          recurrenceSeconds: animationRecurrenceSeconds,
          scrollingListenable: scrollingListenable,
          child: photoCard && item.imageBytes != null
              ? _PhotoInventoryCardContent(
                  item: item,
                  typeLabel: typeLabel ?? item.typeLabel,
                  typeIcon: typeIcon,
                  typeIconImageBytes: typeIconImageBytes,
                  spoolSizeLabel: spoolSizeLabel,
                  showStatus: showStatus,
                  onQuantityChanged: canEdit ? onQuantityChanged : null,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 220;
                    return Padding(
                      padding: EdgeInsets.all(compact ? 12 : 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: _QuantityStepper(
                                      item: item,
                                      compact: compact,
                                      onQuantityChanged: canEdit
                                          ? onQuantityChanged
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (item.archived)
                                _ArchiveBadge(item: item)
                              else if (showStatus && item.quantity > 0)
                                CountdownRing(
                                  key: Key('inventory-card-timer-${item.id}'),
                                  item: item,
                                  compact: compact,
                                ),
                            ],
                          ),
                          const Spacer(),
                          _CardTypeAndPrice(
                            item: item,
                            typeLabel: typeLabel ?? item.typeLabel,
                            typeIcon: typeIcon,
                            typeIconImageBytes: typeIconImageBytes,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 15 : 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (!compact) ...[
                            const SizedBox(height: 8),
                            Text(
                              [
                                if (spoolSizeLabel.isNotEmpty) spoolSizeLabel,
                                ...item.compatibility,
                              ].join('  •  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xff929aac),
                                fontSize: 12,
                              ),
                            ),
                          ],
                          SizedBox(height: compact ? 5 : 14),
                          SizedBox(
                            width: double.infinity,
                            child: Row(
                              children: [
                                _ItemVisual(
                                  item: item,
                                  size: compact ? 32 : 38,
                                  typeIcon: typeIcon,
                                  typeIconImageBytes: typeIconImageBytes,
                                ),
                                const Spacer(),
                                if (item.materialName.isNotEmpty) ...[
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 110,
                                    ),
                                    child: _MaterialBadge(item: item),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    ),
  );
}

class _CardTypeAndPrice extends StatelessWidget {
  const _CardTypeAndPrice({
    required this.item,
    required this.typeLabel,
    required this.typeIcon,
    required this.typeIconImageBytes,
    this.overlay = false,
  });

  final InventoryItem item;
  final String typeLabel;
  final IconData? typeIcon;
  final Uint8List? typeIconImageBytes;
  final bool overlay;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        key: Key('item-type-row-${item.id}'),
        children: [
          _TypeBadgeIcon(
            icon: typeIcon,
            imageBytes: typeIconImageBytes,
            size: 14,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              typeLabel.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _itemCardChromeColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 3),
      Align(
        key: Key('item-price-row-${item.id}'),
        alignment: Alignment.centerRight,
        child: Text(
          '\$${item.cost.toStringAsFixed(2)}',
          style: TextStyle(
            color: overlay
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

class InventoryRow extends StatelessWidget {
  const InventoryRow({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onAction,
    this.onQuantityChanged,
    this.onSelect,
    this.selected = false,
    this.typeLabel,
    this.typeIcon,
    this.typeIconImageBytes,
    this.spoolSizeLabel = '',
    this.quantitySyncVersion = 0,
    this.lowStockAnimationVersion = 0,
    this.moistureAnimationVersion = 0,
    this.animationDurationPercent = 100,
    this.animationRecurrenceSeconds = 5,
    this.scrollingListenable,
    this.showStatus = true,
    this.canEdit = true,
    this.canCreate = true,
    this.canArchive = true,
    this.canDelete = true,
  });
  final InventoryItem item;
  final VoidCallback onOpen;
  final ValueChanged<ItemAction> onAction;
  final ValueChanged<double>? onQuantityChanged;
  final VoidCallback? onSelect;
  final bool selected;
  final String? typeLabel;
  final IconData? typeIcon;
  final Uint8List? typeIconImageBytes;
  final String spoolSizeLabel;
  final int quantitySyncVersion;
  final int lowStockAnimationVersion;
  final int moistureAnimationVersion;
  final int animationDurationPercent;
  final int animationRecurrenceSeconds;
  final ValueListenable<bool>? scrollingListenable;
  final bool showStatus;
  final bool canEdit;
  final bool canCreate;
  final bool canArchive;
  final bool canDelete;

  String get _metadata => [
    typeLabel ?? item.typeLabel,
    if (spoolSizeLabel.isNotEmpty) spoolSizeLabel,
    ...item.compatibility,
  ].join('  •  ');

  Widget _price() => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '\$${item.cost.toStringAsFixed(2)}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ],
  );

  Widget _mobileLayout() => ConstrainedBox(
    key: Key('mobile-inventory-row-${item.id}'),
    constraints: const BoxConstraints(minHeight: 132),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ItemVisual(
                item: item,
                size: 48,
                typeIcon: typeIcon,
                typeIconImageBytes: typeIconImageBytes,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      key: Key('mobile-item-name-${item.id}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff929aac),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xffb9a9ff),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _QuantityStepper(
                item: item,
                compact: true,
                onQuantityChanged: canEdit ? onQuantityChanged : null,
              ),
              if (item.archived) ...[
                const SizedBox(width: 8),
                Flexible(child: _ArchiveBadge(item: item)),
              ] else
                const Spacer(),
              _price(),
              const SizedBox(width: 10),
              if (showStatus && item.quantity > 0)
                CountdownRing(
                  key: Key('inventory-row-timer-${item.id}'),
                  item: item,
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _desktopLayout() => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 86),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _ItemVisual(
            item: item,
            size: 48,
            typeIcon: typeIcon,
            typeIconImageBytes: typeIconImageBytes,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff929aac),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (selected) ...[
            const Icon(Icons.check_circle_rounded, color: Color(0xffb9a9ff)),
            const SizedBox(width: 12),
          ],
          _QuantityStepper(
            item: item,
            onQuantityChanged: canEdit ? onQuantityChanged : null,
          ),
          const SizedBox(width: 12),
          if (item.archived) ...[
            _ArchiveBadge(item: item),
            const SizedBox(width: 12),
          ],
          _price(),
          if (showStatus && item.quantity > 0) ...[
            const SizedBox(width: 12),
            SizedBox(
              height: 62,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: CountdownRing(
                  key: Key('inventory-row-timer-${item.id}'),
                  item: item,
                  compact: true,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ItemContextRegion(
    item: item,
    onAction: onAction,
    canEdit: canEdit,
    canCreate: canCreate,
    canArchive: canArchive,
    canDelete: canDelete,
    onSelect: onSelect,
    child: Card(
      key: Key('inventory-row-${item.id}'),
      color: selected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: .16)
          : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onOpen,
        hoverColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: .12),
        focusColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: .12),
        highlightColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: .17),
        splashColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: .17),
        child: ItemCardEffects(
          itemId: item.id,
          quantitySyncVersion: quantitySyncVersion,
          lowStockVersion: lowStockAnimationVersion,
          moistureVersion: moistureAnimationVersion,
          lowStockActive: !item.archived && _isLowStock(item),
          moistureActive: _hasMoistureVisualAlert(item),
          durationPercent: animationDurationPercent,
          recurrenceSeconds: animationRecurrenceSeconds,
          scrollingListenable: scrollingListenable,
          child: LayoutBuilder(
            builder: (_, constraints) =>
                constraints.maxWidth < 600 ? _mobileLayout() : _desktopLayout(),
          ),
        ),
      ),
    ),
  );
}

class CountdownRing extends StatelessWidget {
  const CountdownRing({super.key, required this.item, this.compact = false});
  final InventoryItem item;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final dryingRemaining = _dryingTimeRemaining(item);
    final remaining = dryingMinutesRemaining(item);
    final total = item.dryingMinutes;
    final filament = item.type == InventoryType.filament;
    final lowStock = _isLowStock(item);
    final moistureRemaining = _moistureRemaining(item);
    final active =
        filament &&
        item.filamentStatus == FilamentStatus.drying &&
        remaining > 0 &&
        total != null &&
        total > 0;
    final deployed = filament
        ? item.filamentStatus == FilamentStatus.deployed
        : item.deployed;
    final queued =
        filament &&
        (item.filamentStatus == FilamentStatus.queuedForDrying ||
            moistureRemaining != null && moistureRemaining <= Duration.zero);
    final moistureAlert =
        !queued &&
        item.moistureAlertEnabled &&
        item.moistureAlertThresholdMinutes != null &&
        moistureRemaining != null &&
        moistureRemaining <=
            Duration(minutes: item.moistureAlertThresholdMinutes!);
    final progress = active
        ? (1 - (dryingRemaining.inSeconds / (total * 60))).clamp(0.0, 1.0)
        : moistureRemaining != null
        ? moistureLifeProgress(item)
        : 1.0;
    final size = compact ? 46.0 : 58.0;
    final statusColor = active
        ? const Color(0xff9c83ff)
        : queued
        ? const Color(0xffffa552)
        : moistureAlert
        ? const Color(0xffffc857)
        : deployed
        ? const Color(0xff55a8ff)
        : lowStock
        ? const Color(0xffffc857)
        : const Color(0xff45d2bd);
    final moistureLabel = _moistureRemainingLabel(item);
    final statusLabel = active
        ? 'Time until dry'
        : queued
        ? 'Wet'
        : deployed
        ? moistureRemaining == null
              ? 'Deployed'
              : 'Deployed · $moistureLabel'
        : lowStock
        ? 'Low stock'
        : moistureRemaining == null
        ? 'Ready'
        : moistureLabel;
    return Semantics(
      label: statusLabel,
      value: active ? '$remaining minutes' : moistureLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: statusLabel,
        child: TweenAnimationBuilder<double>(
          // Starting at the current value prevents recycled grid cards from
          // replaying the ring animation whenever they re-enter the viewport.
          // With no explicit begin, later end-value changes still animate from
          // the value currently on screen.
          tween: Tween(end: progress),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, animatedProgress, child) => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: .22),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: size,
                  child: CircularProgressIndicator(
                    value: animatedProgress,
                    strokeWidth: compact ? 4 : 5,
                    backgroundColor: const Color(0xff292f3d),
                    color: statusColor,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      active
                          ? Icons.water_drop_outlined
                          : queued
                          ? Icons.water_drop_rounded
                          : deployed
                          ? Icons.lock_outline_rounded
                          : lowStock
                          ? Icons.warning_amber_rounded
                          : Icons.check_rounded,
                      size: deployed
                          ? compact
                                ? 18
                                : 21
                          : compact
                          ? 14
                          : 16,
                      color: statusColor,
                    ),
                    if (!compact)
                      Text(
                        active
                            ? '${remaining}m'
                            : queued
                            ? 'WET'
                            : moistureRemaining != null
                            ? _moistureRingText(moistureRemaining)
                            : deployed
                            ? 'DEPLOYED'
                            : lowStock
                            ? 'LOW'
                            : 'READY',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinnedActionBarDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedActionBarDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(covariant _PinnedActionBarDelegate oldDelegate) => true;
}

String _age(DateTime added) {
  final days = DateTime(2026, 8, 25).difference(added).inDays;
  if (days < 30) return '${days}d old';
  if (days < 365) return '${days ~/ 30}mo old';
  return '${(days / 365).toStringAsFixed(1)}y old';
}
