import 'dart:convert';
import 'package:flutter_hbb/models/cloud_replica.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'an offline edit survives restart and edits made during upload stay pending',
      () {
    var book = CloudReplica();
    book.edit('p:1', {'alias': 'Caja'});
    book = CloudReplica.fromJson(jsonDecode(jsonEncode(book.toJson())));
    final sent = Map.of(book.pending);
    book.edit('p:1', {'alias': 'Oficina'});
    book.receive(sent, {
      'records': {
        'p:1': {
          'rev': 1,
          'value': {'alias': 'Caja'}
        }
      },
      'conflicts': [],
    });
    expect(book.pending['p:1'], {
      'rev': 1,
      'value': {'alias': 'Oficina'}
    });
  });

  test('a stale offline edit keeps both versions until the user chooses', () {
    final book = CloudReplica();
    book.edit('p:1', {'alias': 'Caja'});
    final sent = Map.of(book.pending);
    final reply = {
      'records': {
        'p:1': {'rev': 3, 'value': null}
      },
      'conflicts': ['p:1'],
    };
    expect(book.receive(sent, reply), ['p:1']);
    expect(book.value('p:1'), {'alias': 'Caja'});
    book.resolve('p:1', true);
    expect(book.pending['p:1']['rev'], 3);
    book.resolve('p:1', false);
    expect(book.value('p:1'), isNull);
    expect(book.pending, isEmpty);
  });
}
