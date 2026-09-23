import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Key/value store backed by the operating system's credential store.
abstract interface class SecretVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecretVaultUnavailable implements Exception {
  const SecretVaultUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Windows Credential Manager/DPAPI, Android Keystore, or the Linux Secret
/// Service (GNOME Keyring, KDE Wallet). Every failure surfaces as
/// [SecretVaultUnavailable] so callers can fall back without guessing at
/// platform-specific exception types.
class KeyringSecretVault implements SecretVault {
  KeyringSecretVault({
    FlutterSecureStorage? storage,
    this.timeout = const Duration(seconds: 10),
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// A locked keyring may wait for the user to unlock it. Do not let that
  /// stall app startup or a settings dialog indefinitely.
  final Duration timeout;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(timeout);
    } on TimeoutException {
      throw const SecretVaultUnavailable(
        'The system keyring did not respond. It may be locked.',
      );
    } catch (error) {
      throw SecretVaultUnavailable(
        'The system keyring is not available: $error',
      );
    }
  }

  @override
  Future<String?> read(String key) => _guard(() => _storage.read(key: key));

  @override
  Future<void> write(String key, String value) =>
      _guard(() => _storage.write(key: key, value: value));

  @override
  Future<void> delete(String key) => _guard(() => _storage.delete(key: key));
}

/// Access and refresh tokens for one Remote Sync session.
class SessionTokens {
  const SessionTokens({this.accessToken, this.refreshToken});

  static const empty = SessionTokens();

  final String? accessToken;
  final String? refreshToken;

  bool get isEmpty =>
      (accessToken ?? '').isEmpty && (refreshToken ?? '').isEmpty;

  String encode() =>
      jsonEncode({'accessToken': accessToken, 'refreshToken': refreshToken});

  static SessionTokens decode(String? source) {
    if (source == null) return empty;
    try {
      final json = jsonDecode(source);
      return json is Map<String, dynamic> ? fromJson(json) : empty;
    } on FormatException {
      return empty;
    }
  }

  /// Reads the tokens out of a persisted `SupabaseConfig` JSON map.
  static SessionTokens fromJson(Map<String, dynamic> json) => SessionTokens(
    accessToken: json['accessToken'] as String?,
    refreshToken: json['refreshToken'] as String?,
  );

  /// Returns [json] with the token fields removed.
  static Map<String, dynamic> strip(Map<String, dynamic> json) => {
    for (final entry in json.entries)
      if (entry.key != 'accessToken' && entry.key != 'refreshToken')
        entry.key: entry.value,
  };

  /// Returns [json] with these tokens added, leaving it untouched when empty.
  Map<String, dynamic> mergeInto(Map<String, dynamic> json) => isEmpty
      ? json
      : {...json, 'accessToken': accessToken, 'refreshToken': refreshToken};

  @override
  bool operator ==(Object other) =>
      other is SessionTokens &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken);
}

/// In-memory copy of the session tokens kept in a [SecretVault].
///
/// Sync code reads the Remote Sync config synchronously, but keyrings are
/// asynchronous. This loads the tokens once at startup, answers reads from
/// memory, and writes changes through to the vault in order.
class SessionSecretCache {
  static const _probeKey = 'inventorinator.probe';

  SecretVault? _vault;
  final Map<String, SessionTokens> _tokens = {};

  /// Slots whose vault contents are known, either read or written. A slot that
  /// could not be read must never be deleted: an unreadable entry is not an
  /// empty one, and a locked keyring must not wipe a working session.
  final Set<String> _known = {};
  Future<void> _tail = Future<void>.value();

  /// The most recent keyring failure, or null once a later operation succeeds.
  Object? error;

  bool get attached => _vault != null;

  static String keyFor(String slot) => 'inventorinator.session.$slot';

  SessionTokens tokensFor(String slot) => _tokens[slot] ?? SessionTokens.empty;

  Iterable<String> get workspaceSlots =>
      {..._tokens.keys, ..._known}.where((slot) => slot.startsWith('ws:'));

  Future<void> flush() => _tail;

  /// Checks that the vault can store, return and remove a value.
  Future<void> probe(SecretVault vault) async {
    await vault.write(_probeKey, 'probe');
    if (await vault.read(_probeKey) != 'probe') {
      throw const SecretVaultUnavailable(
        'The system keyring did not return a stored value.',
      );
    }
    await vault.delete(_probeKey);
  }

  /// Startup with the feature already on: reads each slot's stored tokens.
  Future<void> restore(SecretVault vault, Iterable<String> slots) async {
    _vault = vault;
    await Future.wait([
      for (final slot in slots)
        () async {
          try {
            final tokens = SessionTokens.decode(await vault.read(keyFor(slot)));
            if (!tokens.isEmpty) _tokens[slot] = tokens;
            _known.add(slot);
          } on SecretVaultUnavailable catch (failure) {
            error = failure;
          }
        }(),
    ]);
  }

  /// Copies [tokens] into [vault] and reads them back to prove the round trip.
  /// Throws [SecretVaultUnavailable] without changing this cache on failure.
  Future<void> adopt(
    SecretVault vault,
    Map<String, SessionTokens> tokens,
  ) async {
    for (final entry in tokens.entries) {
      if (entry.value.isEmpty) continue;
      final key = keyFor(entry.key);
      await vault.write(key, entry.value.encode());
      if (SessionTokens.decode(await vault.read(key)) != entry.value) {
        throw const SecretVaultUnavailable(
          'The system keyring did not return the stored sign-in.',
        );
      }
    }
  }

  /// Best-effort removal of entries that [adopt] wrote before a failure.
  Future<void> discard(SecretVault vault, Iterable<String> slots) async {
    for (final slot in slots) {
      try {
        await vault.delete(keyFor(slot));
      } on SecretVaultUnavailable {
        // Nothing more can be done; the entries are overwritten on retry.
      }
    }
  }

  /// Switches to [vault] after [adopt] succeeded. Synchronous on purpose.
  void activate(SecretVault vault, Map<String, SessionTokens> tokens) {
    _vault = vault;
    _tokens
      ..clear()
      ..addAll({
        for (final entry in tokens.entries)
          if (!entry.value.isEmpty) entry.key: entry.value,
      });
    _known
      ..clear()
      ..addAll(tokens.keys);
    error = null;
  }

  /// Records new tokens for [slot] and writes them through to the vault.
  void put(String slot, SessionTokens tokens) {
    final unchanged =
        _known.contains(slot) &&
        (tokens.isEmpty ? !_tokens.containsKey(slot) : _tokens[slot] == tokens);
    if (tokens.isEmpty) {
      _tokens.remove(slot);
    } else {
      _tokens[slot] = tokens;
    }
    if (unchanged) return;
    _tail = _tail.then((_) => _writeThrough(slot));
  }

  Future<void> _writeThrough(String slot) async {
    final vault = _vault;
    if (vault == null) return;
    // Read at run time so a burst of updates writes only the newest tokens.
    final tokens = _tokens[slot];
    try {
      if (tokens != null) {
        await vault.write(keyFor(slot), tokens.encode());
        _known.add(slot);
        error = null;
      } else if (_known.contains(slot)) {
        await vault.delete(keyFor(slot));
        error = null;
      }
    } on SecretVaultUnavailable catch (failure) {
      error = failure;
    }
  }

  /// Detaches from the vault immediately and then deletes its entries.
  /// Resolves to false if any entry could not be removed.
  Future<bool> release() {
    final vault = _vault;
    final keys = _known.map(keyFor).toList();
    final pending = _tail;
    _vault = null;
    _tokens.clear();
    _known.clear();
    error = null;
    return _deleteAll(vault, keys, pending);
  }

  Future<bool> _deleteAll(
    SecretVault? vault,
    List<String> keys,
    Future<void> pending,
  ) async {
    await pending;
    if (vault == null) return true;
    var removedAll = true;
    for (final key in keys) {
      try {
        await vault.delete(key);
      } on SecretVaultUnavailable {
        removedAll = false;
      }
    }
    return removedAll;
  }
}
