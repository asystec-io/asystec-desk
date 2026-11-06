/// Local copy of a personal book. A null record value represents a deletion.
class CloudReplica {
  Map<String, dynamic> records;
  final Map<String, dynamic> pending;

  CloudReplica()
      : records = {},
        pending = {};

  CloudReplica.fromJson(Map<String, dynamic> data)
      : records = Map.from(data['records']),
        pending = Map.from(data['pending']);

  Map<String, dynamic> toJson() => {'records': records, 'pending': pending};

  dynamic value(String key) =>
      pending.containsKey(key) ? pending[key]['value'] : records[key]?['value'];

  void edit(String key, dynamic value) {
    pending[key] = {
      'rev': pending[key]?['rev'] ?? records[key]?['rev'] ?? 0,
      'value': value,
    };
  }

  List<String> receive(Map<String, dynamic> sent, Map<String, dynamic> reply) {
    records = Map.from(reply['records']);
    final conflicts = List<String>.from(reply['conflicts']);
    if (conflicts.isEmpty) {
      for (final key in sent.keys) {
        if (identical(sent[key], pending[key])) {
          pending.remove(key);
        } else if (pending.containsKey(key)) {
          // The user edited this entry while its previous change was in flight.
          resolve(key, true);
        }
      }
    }
    return conflicts;
  }

  void resolve(String key, bool keepLocal) {
    if (keepLocal) {
      pending[key] = {'rev': records[key]?['rev'] ?? 0, 'value': value(key)};
    } else {
      pending.remove(key);
    }
  }
}
