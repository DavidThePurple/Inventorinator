import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'local_database.dart';

/// Idle timeouts offered in settings, in minutes. Zero means never.
const appLockTimeoutOptions = <int>[0, 1, 2, 5, 10, 15, 30, 60];

enum AppLockResult { success, wrong, lockedOut, notSet }

/// An optional PIN screen for shared terminals.
///
/// This is a screen lock, not encryption: it keeps the next person at the
/// terminal out of the app, but it does not protect a copy of the database
/// file. The PIN and the unlock key are stored only as salted hashes.
class AppLockController extends ChangeNotifier {
  AppLockController(
    this._database, {
    DateTime Function()? clock,
    this.iterations = 10000,
    this.idleCheckInterval = const Duration(seconds: 5),
  }) : _clock = clock ?? DateTime.now {
    final database = _database;
    if (database != null) {
      String read(String key) =>
          database.loadStringPreference(key, fallback: '');
      _pinHash = read(_pinHashKey);
      _pinSalt = read(_pinSaltKey);
      _keyHash = read(_keyHashKey);
      _keySalt = read(_keySaltKey);
      _storedIterations = int.tryParse(read(_iterationsKey)) ?? iterations;
      _timeoutMinutes = int.tryParse(read(_timeoutKey)) ?? 0;
      _failures = int.tryParse(read(_failuresKey)) ?? 0;
      _lockedUntil = DateTime.tryParse(read(_lockedUntilKey));
    }
    _lastActivity = _clock();
    // A PIN, once set, is asked for again each time the app starts.
    _locked = hasPin;
    _syncIdleTimer();
  }

  static const _pinHashKey = 'app_lock_pin_hash';
  static const _pinSaltKey = 'app_lock_pin_salt';
  static const _keyHashKey = 'app_lock_key_hash';
  static const _keySaltKey = 'app_lock_key_salt';
  static const _iterationsKey = 'app_lock_iterations';
  static const _timeoutKey = 'app_lock_timeout_minutes';
  static const _failuresKey = 'app_lock_failures';
  static const _lockedUntilKey = 'app_lock_locked_until';
  static const _keyAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const _keyLength = 20;

  final LocalDatabase? _database;
  final DateTime Function() _clock;

  /// PBKDF2 rounds for new PINs and keys. Each stored hash records its own
  /// count, so this can change later without invalidating existing PINs.
  final int iterations;
  final Duration idleCheckInterval;

  String _pinHash = '';
  String _pinSalt = '';
  String _keyHash = '';
  String _keySalt = '';
  int _storedIterations = 10000;
  int _timeoutMinutes = 0;
  int _failures = 0;
  DateTime? _lockedUntil;
  bool _locked = false;
  late DateTime _lastActivity;
  Timer? _idleTimer;

  bool get hasPin => _database != null && _pinHash.isNotEmpty;
  bool get locked => _locked;
  int get timeoutMinutes => _timeoutMinutes;

  Duration get lockoutRemaining {
    final until = _lockedUntil;
    if (until == null) return Duration.zero;
    final remaining = until.difference(_clock().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static bool isValidPin(String pin) => RegExp(r'^\d{4,12}$').hasMatch(pin);

  void lock() {
    if (!hasPin || _locked) return;
    _locked = true;
    _syncIdleTimer();
    notifyListeners();
  }

  AppLockResult unlock(String pin) {
    final result = _guarded(() => _matches(pin, _pinSalt, _pinHash));
    if (result == AppLockResult.success) {
      _locked = false;
      _lastActivity = _clock();
      _syncIdleTimer();
      notifyListeners();
    }
    return result;
  }

  /// Turns the lock on. Returns the unlock key, which is shown once and kept
  /// only as a hash, or null if a PIN is already set or [pin] is not valid.
  String? setPin(String pin) {
    if (hasPin || !isValidPin(pin)) return null;
    final key = _storeNewCredentials(pin);
    notifyListeners();
    return key;
  }

  AppLockResult changePin(String current, String next) {
    if (!isValidPin(next)) return AppLockResult.wrong;
    final result = _guarded(() => _matches(current, _pinSalt, _pinHash));
    if (result == AppLockResult.success) {
      final salt = _newSalt();
      _pinSalt = salt;
      _pinHash = _derive(next, salt, iterations);
      _storedIterations = iterations;
      _save({
        _pinSaltKey: _pinSalt,
        _pinHashKey: _pinHash,
        _iterationsKey: '$_storedIterations',
      });
      notifyListeners();
    }
    return result;
  }

  AppLockResult removePin(String current) {
    final result = _guarded(() => _matches(current, _pinSalt, _pinHash));
    if (result == AppLockResult.success) {
      _clearCredentials();
      notifyListeners();
    }
    return result;
  }

  /// Replaces the unlock key. The PIN must be entered to do this.
  ({AppLockResult result, String? key}) regenerateUnlockKey(String pin) {
    final result = _guarded(() => _matches(pin, _pinSalt, _pinHash));
    if (result != AppLockResult.success) return (result: result, key: null);
    final key = _newUnlockKey();
    _keySalt = _newSalt();
    _keyHash = _derive(_normalizeKey(key), _keySalt, iterations);
    _save({_keySaltKey: _keySalt, _keyHashKey: _keyHash});
    return (result: result, key: key);
  }

  /// Checks the unlock key without changing anything. Failed attempts count
  /// toward the same lockout as wrong PINs.
  AppLockResult checkUnlockKey(String key) => _guarded(
    () => _matches(_normalizeKey(key), _keySalt, _keyHash),
    hash: () => _keyHash,
  );

  /// Forgot-PIN path. On success the PIN is replaced by [newPin], or the lock
  /// is turned off when [newPin] is null. A replaced PIN comes with a fresh
  /// unlock key; the app stays locked until [finishReset] so that key can be
  /// saved first.
  ({AppLockResult result, String? newKey}) resetWithUnlockKey(
    String key, {
    String? newPin,
  }) {
    if (newPin != null && !isValidPin(newPin)) {
      return (result: AppLockResult.wrong, newKey: null);
    }
    final result = checkUnlockKey(key);
    if (result != AppLockResult.success) return (result: result, newKey: null);
    if (newPin == null) {
      _clearCredentials();
      _locked = false;
      _syncIdleTimer();
      notifyListeners();
      return (result: result, newKey: null);
    }
    final newKey = _storeNewCredentials(newPin);
    return (result: result, newKey: newKey);
  }

  /// Ends the forgot-PIN flow once the new unlock key has been saved.
  void finishReset() {
    _locked = false;
    _lastActivity = _clock();
    _syncIdleTimer();
    notifyListeners();
  }

  void setTimeoutMinutes(int minutes) {
    if (minutes < 0 || minutes == _timeoutMinutes) return;
    _timeoutMinutes = minutes;
    _save({_timeoutKey: '$minutes'});
    _lastActivity = _clock();
    _syncIdleTimer();
    notifyListeners();
  }

  void recordActivity() => _lastActivity = _clock();

  /// Locks the app if it has been idle for the chosen time. Runs on a timer
  /// and is public so tests can drive it.
  void checkIdle() {
    if (!hasPin || _locked || _timeoutMinutes <= 0) return;
    if (_clock().difference(_lastActivity) >=
        Duration(minutes: _timeoutMinutes)) {
      lock();
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _syncIdleTimer() {
    final needed = hasPin && !_locked && _timeoutMinutes > 0;
    if (!needed) {
      _idleTimer?.cancel();
      _idleTimer = null;
    } else {
      _idleTimer ??= Timer.periodic(idleCheckInterval, (_) => checkIdle());
    }
  }

  /// Runs [matches] behind the wrong-attempt lockout. After five misses each
  /// further miss doubles the wait, from 30 seconds up to 15 minutes. The count
  /// is stored, so restarting the app does not reset it.
  AppLockResult _guarded(bool Function() matches, {String Function()? hash}) {
    if ((hash?.call() ?? _pinHash).isEmpty) return AppLockResult.notSet;
    if (lockoutRemaining > Duration.zero) return AppLockResult.lockedOut;
    if (matches()) {
      if (_failures != 0 || _lockedUntil != null) {
        _failures = 0;
        _lockedUntil = null;
        _save({_failuresKey: '0', _lockedUntilKey: ''});
      }
      return AppLockResult.success;
    }
    _failures++;
    if (_failures >= 5) {
      final seconds = math.min(30 * (1 << math.min(_failures - 5, 5)), 900);
      _lockedUntil = _clock().toUtc().add(Duration(seconds: seconds));
    }
    _save({
      _failuresKey: '$_failures',
      _lockedUntilKey: _lockedUntil?.toIso8601String() ?? '',
    });
    return AppLockResult.wrong;
  }

  bool _matches(String secret, String salt, String hash) {
    if (salt.isEmpty || hash.isEmpty) return false;
    return _sameText(_derive(secret, salt, _storedIterations), hash);
  }

  String _storeNewCredentials(String pin) {
    final key = _newUnlockKey();
    _pinSalt = _newSalt();
    _pinHash = _derive(pin, _pinSalt, iterations);
    _keySalt = _newSalt();
    _keyHash = _derive(_normalizeKey(key), _keySalt, iterations);
    _storedIterations = iterations;
    _failures = 0;
    _lockedUntil = null;
    _save({
      _pinSaltKey: _pinSalt,
      _pinHashKey: _pinHash,
      _keySaltKey: _keySalt,
      _keyHashKey: _keyHash,
      _iterationsKey: '$_storedIterations',
      _failuresKey: '0',
      _lockedUntilKey: '',
    });
    _lastActivity = _clock();
    _syncIdleTimer();
    return key;
  }

  void _clearCredentials() {
    _pinHash = _pinSalt = _keyHash = _keySalt = '';
    _failures = 0;
    _lockedUntil = null;
    _locked = false;
    _save({
      _pinHashKey: '',
      _pinSaltKey: '',
      _keyHashKey: '',
      _keySaltKey: '',
      _failuresKey: '0',
      _lockedUntilKey: '',
    });
    _syncIdleTimer();
  }

  void _save(Map<String, String> values) =>
      _database?.saveStringPreferences(values);

  static String _newSalt() {
    final random = math.Random.secure();
    return base64Encode([for (var i = 0; i < 16; i++) random.nextInt(256)]);
  }

  static String _newUnlockKey() {
    final random = math.Random.secure();
    final characters = [
      for (var i = 0; i < _keyLength; i++)
        _keyAlphabet[random.nextInt(_keyAlphabet.length)],
    ];
    return [
      for (var i = 0; i < _keyLength; i += 4)
        characters.sublist(i, i + 4).join(),
    ].join('-');
  }

  /// Accepts the key as typed: any case, with or without dashes or spaces, and
  /// the letters that are easily misread for digits.
  static String _normalizeKey(String key) => key
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');

  /// PBKDF2-HMAC-SHA256, one 32-byte block.
  static String _derive(String secret, String salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    var block = hmac.convert([...base64Decode(salt), 0, 0, 0, 1]).bytes;
    final result = List<int>.of(block);
    for (var i = 1; i < iterations; i++) {
      block = hmac.convert(block).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= block[j];
      }
    }
    return base64Encode(result);
  }

  static bool _sameText(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}

class AppLockScope extends InheritedNotifier<AppLockController> {
  const AppLockScope({
    super.key,
    required AppLockController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLockController? maybeOf(
    BuildContext context, {
    bool listen = true,
  }) => listen
      ? context.dependOnInheritedWidgetOfExactType<AppLockScope>()?.notifier
      : context.getInheritedWidgetOfExactType<AppLockScope>()?.notifier;
}

/// Hides everything behind a lock screen while the app is locked.
///
/// The app underneath stays mounted, so unlocking returns to exactly where the
/// user was, but it is not painted, hit-tested, focusable or exposed to screen
/// readers while locked.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.controller, required this.child});

  final AppLockController controller;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  bool _noteKey(KeyEvent event) {
    widget.controller.recordActivity();
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_noteKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_noteKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => widget.controller.recordActivity(),
    onPointerMove: (_) => widget.controller.recordActivity(),
    onPointerSignal: (_) => widget.controller.recordActivity(),
    child: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final locked = widget.controller.locked;
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: locked,
              child: ExcludeFocus(
                excluding: locked,
                child: TickerMode(enabled: !locked, child: widget.child),
              ),
            ),
            if (locked)
              Positioned.fill(
                child: _LockOverlay(controller: widget.controller),
              ),
          ],
        );
      },
    ),
  );
}

/// The lock screen needs its own Overlay: the gate sits above the app's
/// Navigator, so text selection menus and tooltips would otherwise find none.
class _LockOverlay extends StatefulWidget {
  const _LockOverlay({required this.controller});

  final AppLockController controller;

  @override
  State<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<_LockOverlay> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => _LockedScreen(controller: widget.controller),
  );

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

enum _UnlockStep { idle, pin, key, newPin, saveKey }

class _LockedScreen extends StatefulWidget {
  const _LockedScreen({required this.controller});

  final AppLockController controller;

  @override
  State<_LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<_LockedScreen> {
  final _pin = TextEditingController();
  final _key = TextEditingController();
  final _newPin = TextEditingController();
  final _confirm = TextEditingController();
  _UnlockStep _step = _UnlockStep.idle;
  String? _error;
  String? _newKey;
  Timer? _lockoutTicker;

  @override
  void dispose() {
    _lockoutTicker?.cancel();
    _pin.dispose();
    _key.dispose();
    _newPin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _go(_UnlockStep step) => setState(() {
    _step = step;
    _error = null;
  });

  String _lockoutMessage() {
    final remaining = widget.controller.lockoutRemaining;
    final seconds =
        remaining.inSeconds + (remaining.inMilliseconds % 1000 > 0 ? 1 : 0);
    return 'Too many attempts. Try again in ${seconds >= 60 ? '${(seconds / 60).ceil()} min' : '$seconds sec'}.';
  }

  void _showResult(AppLockResult result, String wrongMessage) {
    setState(() {
      _error = switch (result) {
        AppLockResult.wrong
            when widget.controller.lockoutRemaining > Duration.zero =>
          _lockoutMessage(),
        AppLockResult.wrong => wrongMessage,
        AppLockResult.lockedOut => _lockoutMessage(),
        _ => null,
      };
    });
    _lockoutTicker?.cancel();
    if (widget.controller.lockoutRemaining > Duration.zero) {
      _lockoutTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        if (widget.controller.lockoutRemaining > Duration.zero) {
          setState(() => _error = _lockoutMessage());
        } else {
          timer.cancel();
          setState(() => _error = null);
        }
      });
    }
  }

  void _submitPin() {
    final result = widget.controller.unlock(_pin.text);
    if (result != AppLockResult.success) {
      _pin.clear();
      _showResult(result, 'Incorrect PIN.');
    }
  }

  void _submitKey() {
    final result = widget.controller.checkUnlockKey(_key.text);
    if (result == AppLockResult.success) {
      _go(_UnlockStep.newPin);
    } else {
      _showResult(result, 'That unlock key is not correct.');
    }
  }

  void _submitNewPin() {
    if (!AppLockController.isValidPin(_newPin.text)) {
      setState(() => _error = 'Use 4 to 12 digits.');
      return;
    }
    if (_newPin.text != _confirm.text) {
      setState(() => _error = 'The two PINs do not match.');
      return;
    }
    final outcome = widget.controller.resetWithUnlockKey(
      _key.text,
      newPin: _newPin.text,
    );
    if (outcome.result != AppLockResult.success || outcome.newKey == null) {
      _showResult(outcome.result, 'That unlock key is not correct.');
      return;
    }
    setState(() {
      _newKey = outcome.newKey;
      _step = _UnlockStep.saveKey;
      _error = null;
    });
  }

  void _turnLockOff() {
    final outcome = widget.controller.resetWithUnlockKey(_key.text);
    if (outcome.result != AppLockResult.success) {
      _showResult(outcome.result, 'That unlock key is not correct.');
    }
  }

  Widget _pinField(
    TextEditingController controller,
    String label, {
    VoidCallback? onSubmitted,
    Key? key,
    bool autofocus = false,
  }) => TextField(
    key: key,
    controller: controller,
    autofocus: autofocus,
    obscureText: true,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(12),
    ],
    decoration: InputDecoration(labelText: label),
    onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
  );

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            _error!,
            key: const Key('app-lock-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        );

  List<Widget> _stepContent() {
    switch (_step) {
      case _UnlockStep.idle:
        return [
          FilledButton.icon(
            key: const Key('unlock-with-pin'),
            onPressed: () => _go(_UnlockStep.pin),
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Unlock with PIN'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('forgot-pin'),
            onPressed: () => _go(_UnlockStep.key),
            child: const Text('Forgot PIN?'),
          ),
        ];
      case _UnlockStep.pin:
        return [
          _pinField(
            _pin,
            'PIN',
            key: const Key('unlock-pin-field'),
            autofocus: true,
            onSubmitted: _submitPin,
          ),
          _errorText(),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('unlock-submit'),
            onPressed: _submitPin,
            child: const Text('Unlock'),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: () => _go(_UnlockStep.idle),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const Key('forgot-pin'),
                onPressed: () => _go(_UnlockStep.key),
                child: const Text('Forgot PIN?'),
              ),
            ],
          ),
        ];
      case _UnlockStep.key:
        return [
          const Text(
            'Enter the unlock key you saved when you set the PIN.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('unlock-key-field'),
            controller: _key,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Unlock key',
              hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX',
            ),
            onSubmitted: (_) => _submitKey(),
          ),
          _errorText(),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('unlock-key-submit'),
            onPressed: _submitKey,
            child: const Text('Continue'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _go(_UnlockStep.idle),
            child: const Text('Back'),
          ),
        ];
      case _UnlockStep.newPin:
        return [
          const Text(
            'Key accepted. Choose a new PIN, or turn the lock off.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          _pinField(
            _newPin,
            'New PIN (4 to 12 digits)',
            key: const Key('reset-new-pin'),
            autofocus: true,
          ),
          const SizedBox(height: 10),
          _pinField(
            _confirm,
            'Confirm new PIN',
            key: const Key('reset-confirm-pin'),
            onSubmitted: _submitNewPin,
          ),
          _errorText(),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('reset-set-pin'),
            onPressed: _submitNewPin,
            child: const Text('Set new PIN'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('reset-turn-off'),
            onPressed: _turnLockOff,
            child: const Text('Turn lock off'),
          ),
        ];
      case _UnlockStep.saveKey:
        return [
          UnlockKeyPanel(
            unlockKey: _newKey!,
            confirmLabel: 'Open Inventorinator',
            onDone: widget.controller.finishReset,
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('app-lock-screen'),
    body: SafeArea(
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: IconButton(
                key: const Key('app-unlock-icon'),
                tooltip: 'Unlock with PIN',
                onPressed: _step == _UnlockStep.idle
                    ? () => _go(_UnlockStep.pin)
                    : null,
                icon: const Icon(Icons.lock_rounded),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 56),
                    const SizedBox(height: 14),
                    const Text(
                      'Inventorinator is locked',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 22),
                    ..._stepContent(),
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

/// Shows a new unlock key once and will not let the person continue until they
/// confirm it is saved.
class UnlockKeyPanel extends StatefulWidget {
  const UnlockKeyPanel({
    super.key,
    required this.unlockKey,
    required this.onDone,
    this.confirmLabel = 'Done',
  });

  final String unlockKey;
  final VoidCallback onDone;
  final String confirmLabel;

  @override
  State<UnlockKeyPanel> createState() => _UnlockKeyPanelState();
}

class _UnlockKeyPanelState extends State<UnlockKeyPanel> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Save your unlock key. If you forget the PIN, this key is the only way '
        'to unlock Inventorinator from the lock screen. It is shown once and '
        'cannot be looked up later. Keep it somewhere safe, away from this '
        'computer.',
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SelectableText(
          widget.unlockKey,
          key: const Key('unlock-key-value'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const Key('copy-unlock-key'),
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: widget.unlockKey)),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy key'),
        ),
      ),
      CheckboxListTile(
        key: const Key('unlock-key-saved'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _saved,
        onChanged: (value) => setState(() => _saved = value ?? false),
        title: const Text('I have saved this key'),
      ),
      const SizedBox(height: 8),
      FilledButton(
        key: const Key('unlock-key-done'),
        onPressed: _saved ? widget.onDone : null,
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

/// The App lock section of the settings dialog.
class AppLockSettingsSection extends StatefulWidget {
  const AppLockSettingsSection({super.key, required this.controller});

  final AppLockController controller;

  @override
  State<AppLockSettingsSection> createState() => _AppLockSettingsSectionState();
}

class _AppLockSettingsSectionState extends State<AppLockSettingsSection> {
  AppLockController get _lock => widget.controller;

  Future<void> _showKey(String key) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Save your unlock key'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: UnlockKeyPanel(
            unlockKey: key,
            onDone: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    ),
  );

  Future<void> _setPin() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) =>
          const _PinDialog(title: 'Set a PIN', askCurrent: false, askNew: true),
    );
    if (pin == null || !mounted) return;
    final key = _lock.setPin(pin);
    setState(() {});
    if (key != null) await _showKey(key);
  }

  Future<void> _changePin() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PinDialog(
        title: 'Change PIN',
        askCurrent: true,
        askNew: true,
        submit: (current, next) => _lock.changePin(current, next!),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _removePin() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PinDialog(
        title: 'Turn off the PIN lock',
        askCurrent: true,
        askNew: false,
        submit: (current, _) => _lock.removePin(current),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _newKey() async {
    String? key;
    await showDialog<void>(
      context: context,
      builder: (_) => _PinDialog(
        title: 'New unlock key',
        askCurrent: true,
        askNew: false,
        submit: (current, _) {
          final outcome = _lock.regenerateUnlockKey(current);
          key = outcome.key;
          return outcome.result;
        },
      ),
    );
    if (key != null && mounted) await _showKey(key!);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _lock,
    builder: (context, _) => Column(
      key: const Key('app-lock-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'App lock',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          _lock.hasPin
              ? 'A PIN is set. Use the lock button at the top right to lock '
                    'Inventorinator, and the PIN to open it again.'
              : 'Optional. Set a PIN to hide Inventorinator behind a lock '
                    'screen on shared terminals. It works offline and with Remote '
                    'Sync.',
        ),
        const SizedBox(height: 4),
        const Text(
          'This is a screen lock, not encryption. It keeps other people out of '
          'the app but does not protect a copy of the database file.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (!_lock.hasPin)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('set-app-pin'),
              onPressed: _setPin,
              icon: const Icon(Icons.lock_outline_rounded),
              label: const Text('Set PIN…'),
            ),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const Key('change-app-pin'),
                onPressed: _changePin,
                child: const Text('Change PIN…'),
              ),
              OutlinedButton(
                key: const Key('new-unlock-key'),
                onPressed: _newKey,
                child: const Text('New unlock key…'),
              ),
              OutlinedButton(
                key: const Key('remove-app-pin'),
                onPressed: _removePin,
                child: const Text('Turn off…'),
              ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lock after inactivity'),
            subtitle: const Text(
              'Lock automatically when nobody has used the app.',
            ),
            trailing: DropdownButton<int>(
              key: const Key('app-lock-timeout'),
              value: appLockTimeoutOptions.contains(_lock.timeoutMinutes)
                  ? _lock.timeoutMinutes
                  : 0,
              items: [
                for (final minutes in appLockTimeoutOptions)
                  DropdownMenuItem(
                    value: minutes,
                    child: Text(
                      minutes == 0
                          ? 'Never'
                          : minutes == 60
                          ? '1 hour'
                          : '$minutes min',
                    ),
                  ),
              ],
              onChanged: (minutes) {
                if (minutes != null) _lock.setTimeoutMinutes(minutes);
              },
            ),
          ),
        ],
      ],
    ),
  );
}

/// Asks for a PIN (and optionally the current one). Returns the new PIN when
/// no [submit] callback is given; otherwise reports through [submit].
class _PinDialog extends StatefulWidget {
  const _PinDialog({
    required this.title,
    required this.askCurrent,
    required this.askNew,
    this.submit,
  });

  final String title;
  final bool askCurrent;
  final bool askNew;
  final AppLockResult Function(String current, String? next)? submit;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Widget _field(String label, TextEditingController controller, Key key) =>
      TextField(
        key: key,
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(12),
        ],
        decoration: InputDecoration(labelText: label),
      );

  void _submit() {
    if (widget.askNew) {
      if (!AppLockController.isValidPin(_next.text)) {
        setState(() => _error = 'Use 4 to 12 digits.');
        return;
      }
      if (_next.text != _confirm.text) {
        setState(() => _error = 'The two PINs do not match.');
        return;
      }
    }
    final submit = widget.submit;
    if (submit == null) {
      Navigator.of(context).pop(_next.text);
      return;
    }
    final result = submit(_current.text, widget.askNew ? _next.text : null);
    if (result == AppLockResult.success) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _error = result == AppLockResult.lockedOut
          ? 'Too many attempts. Try again later.'
          : 'Incorrect PIN.';
      _current.clear();
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.askCurrent)
            _field('Current PIN', _current, const Key('pin-current')),
          if (widget.askNew) ...[
            _field('New PIN (4 to 12 digits)', _next, const Key('pin-new')),
            _field('Confirm new PIN', _confirm, const Key('pin-confirm')),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                key: const Key('pin-dialog-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('pin-dialog-submit'),
        onPressed: _submit,
        child: const Text('OK'),
      ),
    ],
  );
}
