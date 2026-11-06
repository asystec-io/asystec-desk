part of 'ab_model.dart';

/// Only selected for personal books advertised by the Asystec API.
class CloudAb extends Ab {
  CloudAb(AbProfile profile, this.endpoint, this.owner) : super(profile, true) {
    _load();
  }

  final String endpoint;
  final String owner;
  final status = 'Pendiente de sincronizar'.obs;
  final conflicts = <String>[].obs;
  CloudReplica _replica = CloudReplica();
  String get _key => '${locator(endpoint, owner)}-${profile.guid}';
  Map<String, dynamic>? _credentials;
  bool canStorePassword(String id) => Uri.tryParse(endpoint)?.scheme == 'https' &&
      _credentials != null && RegExp(r'^[0-9]{1,16}$').hasMatch(id) &&
      _replica.records['p:$id']?['value'] != null;
  bool hasPassword(String id) => _credentials?[id]?['saved'] == true;
  int credentialRevision(String id) => _credentials?[id]?['rev'] ?? 0;
  int peerRevision(String id) => _replica.records['p:$id']?['rev'] ?? 0;

  Future<Map<String, dynamic>> credentialRequest(String id,
      {Map<String, dynamic>? change}) async {
    final token = bind.mainGetLocalOption(key: 'access_token');
    bool current() => token.isNotEmpty && identical(gFFI.abModel.current, this) &&
        owner == gFFI.userModel.userName.value &&
        token == bind.mainGetLocalOption(key: 'access_token');
    if (!canStorePassword(id) || endpoint != await bind.mainGetApiServer() || !current()) {
      throw StateError('La sesión de la libreta cambió.');
    }
    final client = credential_http.Client();
    try {
      final request = credential_http.Request('POST', Uri.parse('$endpoint/api/asystec/credential'))
        ..followRedirects = false
        ..headers.addAll({'Authorization': 'Bearer $token', 'Content-Type': 'application/json'})
        ..body = jsonEncode({'guid': profile.guid, 'id': id, ...?change});
      final response = await client.send(request).then(credential_http.Response.fromStream)
          .timeout(const Duration(seconds: 8));
      if (!current() || endpoint != await bind.mainGetApiServer() || !current()) {
        throw StateError('La sesión de la libreta cambió.');
      }
      if (response.statusCode == 409) {
        throw StateError('El equipo cambió en otra PC. Volvé a abrir su menú.');
      }
      if (response.statusCode != 200) throw StateError('La libreta no está disponible.');
      final result = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (change != null) _credentials?[id] = result;
      return result;
    } finally {
      client.close();
    }
  }

  bool _sending = false;
  Future<void> _writes = Future.value();
  bool _readable = true;

  static String locator(String endpoint, String owner) =>
      'asystec-book-owner-${base64Url.encode(utf8.encode(jsonEncode([
            endpoint,
            owner
          ])))}';

  void _load() {
    final saved = bind.mainGetLocalOption(key: _key);
    if (saved.isNotEmpty) {
      try {
        final data = jsonDecode(saved);
        _replica = CloudReplica.fromJson(data);
      } catch (_) {
        _readable = false;
        status.value = 'Error al leer la copia local';
        return;
      }
    }
    _render();
  }

  Future<void> _save() {
    final snapshot = jsonEncode(_replica.toJson());
    final write = _writes
        .then((_) => bind.mainSetLocalOption(key: _key, value: snapshot));
    _writes = write.catchError((Object _) {});
    return write;
  }

  dynamic _value(String key) => _replica.value(key);

  void _render() {
    final items = <Peer>[];
    final colors = <String, int>{};
    for (final key in {..._replica.records.keys, ..._replica.pending.keys}) {
      final v = _value(key);
      if (v == null) continue;
      if (key.startsWith('p:')) {
        items.add(Peer.fromJson(
            {'id': key.substring(2), ...Map<String, dynamic>.from(v)}));
      } else {
        colors[key.substring(2)] = v;
      }
    }
    peers.value = items;
    tags.value = colors.keys.toList();
    tagColors.value = colors;
    if (identical(gFFI.abModel.current, this)) gFFI.abModel._refreshTab();
  }

  Future<bool> edit(Map<String, dynamic> values) async {
    if (!_readable || !identical(gFFI.abModel.current, this)) return false;
    for (final entry in values.entries) {
      _replica.edit(entry.key, entry.value);
    }
    status.value = 'Cambios pendientes';
    _render();
    await _save();
    return true;
  }

  @override
  Future<bool> pullAbImpl({quiet = false}) async {
    if (_sending || !_readable) return _readable;
    _sending = true;
    try {
      final token = bind.mainGetLocalOption(key: 'access_token');
      if (owner != gFFI.userModel.userName.value ||
          token.isEmpty ||
          endpoint != await bind.mainGetApiServer()) return false;
      await _writes;
      final sent = Map.of(_replica.pending);
      final resp = await http.post(Uri.parse('$endpoint/api/asystec/book'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'guid': profile.guid, 'changes': sent}));
      if (token != bind.mainGetLocalOption(key: 'access_token') ||
          !identical(gFFI.abModel.current, this)) return false;
      if (resp.statusCode == 401) {
        await gFFI.userModel.reset(resetOther: true);
        return false;
      }
      if (resp.statusCode != 200) {
        status.value = 'Error de sincronización (HTTP ${resp.statusCode})';
        return true;
      }
      final data = jsonDecode(decode_http_response(resp));
      _credentials = data['credentials'];
      conflicts.assignAll(_replica.receive(sent, data));
      _render();
      await _save();
      status.value = conflicts.isNotEmpty
          ? 'Conflicto'
          : _replica.pending.isEmpty
              ? 'Sincronizado'
              : 'Cambios pendientes';
    } catch (_) {
      status.value = _replica.pending.isEmpty
          ? 'Sin conexión'
          : 'Sin conexión · cambios pendientes';
    } finally {
      _sending = false;
    }
    return _readable;
  }

  String describeConflict(String key, {required bool local}) {
    final value = local ? _value(key) : _replica.records[key]?['value'];
    if (value == null) return 'Eliminado';
    if (key.startsWith('t:'))
      return 'Color ${(value as int).toRadixString(16)}';
    return [value['alias'], value['note'], (value['tags'] as List).join(', ')]
        .where((s) => s.isNotEmpty)
        .join(' · ');
  }

  Future<void> resolve(String key, bool keepLocal) async {
    if (_sending || !conflicts.contains(key)) return;
    _replica.resolve(key, keepLocal);
    conflicts.remove(key);
    _render();
    await _save();
    await pullAbImpl();
  }

  @override
  Future<String?> addPeers(List<Map<String, dynamic>> ps) async {
    final values = <String, dynamic>{};
    for (final p in ps) {
      final key = 'p:${p['id']}';
      if (_value(key) != null) return 'El equipo ya existe';
      values[key] = {
        'alias': p['alias'] ?? '',
        'tags': p['tags'] ?? [],
        'note': p['note'] ?? ''
      };
    }
    return await edit(values) ? null : 'No se pudo guardar';
  }

  Future<bool> _patch(List<String> ids, String field, dynamic value) => edit({
        for (final id in ids)
          if (_value('p:$id') != null)
            'p:$id': {
              ...Map<String, dynamic>.from(_value('p:$id')),
              field: value
            }
      });

  @override
  Future<bool> changeAlias({required String id, required String alias}) =>
      _patch([id], 'alias', alias);
  @override
  Future<bool> changeNote({required String id, required String note}) =>
      _patch([id], 'note', note);
  @override
  Future<bool> changeTagForPeers(List<String> ids, List<dynamic> tags) =>
      _patch(ids, 'tags', tags);
  @override
  Future<bool> deletePeers(List<String> ids) =>
      edit({for (final id in ids) 'p:$id': null});
  @override
  Future<bool> addTags(List<String> tagList, Map<String, int> tagColorMap) =>
      edit({
        for (final name in tagList) 't:$name': tagColorMap[name] ?? 0xff607d8b
      });
  @override
  Future<bool> setTagColor(String tag, Color color) =>
      edit({'t:$tag': color.value});
  @override
  Future<bool> renameTag(String oldTag, String newTag) =>
      _replaceTag(oldTag, newTag);
  @override
  Future<bool> deleteTag(String tag) => _replaceTag(tag, null);

  Future<bool> _replaceTag(String oldTag, String? newTag) {
    final values = <String, dynamic>{'t:$oldTag': null};
    if (newTag != null) values['t:$newTag'] = tagColors[oldTag];
    for (final p in peers.where((p) => p.tags.contains(oldTag))) {
      values['p:${p.id}'] = {
        ...Map<String, dynamic>.from(_value('p:${p.id}')),
        'tags': {
          for (final t in p.tags)
            if (t != oldTag) t,
          if (newTag != null) newTag
        }.toList()
      };
    }
    return edit(values);
  }

  @override
  Future<bool> changeSharedPassword(String id, String password) async => false;
  @override
  Future<bool> changePersonalHashPassword(String id, String hash) async =>
      false;
  @override
  Future<void> syncFromRecent(List<Peer> recents) async {}
}
