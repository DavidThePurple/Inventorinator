import 'dart:convert';

import 'local_database.dart';

const resumeLatestItemDraftPreference = 'resume_latest_item_draft';

class ItemDraftStore {
  ItemDraftStore(this.database, this.scope);
  final LocalDatabase database;
  final String scope;
  String get _prefix => 'item_drafts:${base64Url.encode(utf8.encode(scope))}';
  List<Map<String, dynamic>> list({String? itemId}) {
    final raw = database.loadStringPreference('$_prefix:index', fallback: '[]');
    final entries = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return entries.where((e) => e['itemId'] == itemId).toList()..sort(
      (a, b) => (b['updated'] as String).compareTo(a['updated'] as String),
    );
  }

  Map<String, dynamic>? load(String id) {
    final raw = database.loadStringPreference('$_prefix:$id', fallback: '');
    return raw.isEmpty
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  String save(
    String? id,
    Map<String, dynamic> data, {
    String? itemId,
    required String title,
  }) {
    id ??= DateTime.now().microsecondsSinceEpoch.toString();
    final index = (jsonDecode(
      database.loadStringPreference('$_prefix:index', fallback: '[]'),
    ) as List).where((e) => e['id'] != id).toList();
    index.add({
      'id': id,
      'itemId': itemId,
      'title': title.trim().isEmpty ? 'Untitled item' : title.trim(),
      'updated': DateTime.now().toUtc().toIso8601String(),
    });
    database.saveStringPreferences({
      '$_prefix:$id': jsonEncode(data),
      '$_prefix:index': jsonEncode(index),
    });
    return id;
  }

  void delete(String id) {
    final index = (jsonDecode(
      database.loadStringPreference('$_prefix:index', fallback: '[]'),
    ) as List).where((e) => e['id'] != id).toList();
    database.saveStringPreferences({
      '$_prefix:$id': '',
      '$_prefix:index': jsonEncode(index),
    });
  }
}
