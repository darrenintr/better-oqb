import 'dart:async';
import 'package:better_oqb/src/controllers/catalog_controller.dart';
import 'package:better_oqb/src/services/oqb_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';

void main() {
  test('bootstrap starts independent requests before any completes', () async {
    final gates = <Completer<dynamic>>[];
    final transport = FakeTransport((r) {
      final c = Completer<dynamic>();
      gates.add(c);
      return c.future;
    });
    final catalog = CatalogController(OqbRepository(transport));
    addTearDown(catalog.dispose);
    final refresh = catalog.refresh();
    expect(transport.requests.length, 3);
    expect(catalog.isLoading, isTrue);
    for (final c in gates) {
      c.complete(envelope([]));
    }
    await refresh;
    expect(catalog.isLoading, isFalse);
    expect(catalog.hasLoaded, isTrue);
  });
  test('background subject queue has two workers and selected subject priority',
      () async {
    final subjects = <String>[];
    final gates = <Completer<dynamic>>[];
    final transport = FakeTransport((r) {
      if (r.command == 'getUsablePackages') {
        return envelope([
          for (final code in ['a', 'b', 'c', 'd'])
            {'id': code.codeUnitAt(0), 'subject_code': code}
        ]);
      }
      if ((r.command == 'loadPapers' || r.command == 'loadSubmittedPapers')) {
        final subject = r.fields['criteria[subject_code]'];
        if (subject != null) {
          subjects.add(subject);
          final c = Completer<dynamic>();
          gates.add(c);
          return c.future;
        }
      }
      return envelope([]);
    });
    final catalog = CatalogController(OqbRepository(transport));
    addTearDown(catalog.dispose);
    catalog.preferredSubject = 'd';
    await catalog.refresh();
    expect(subjects.length, 4);
    expect(subjects.take(2), ['d', 'd']);
    for (final c in List.of(gates)) {
      c.complete(envelope([]));
    }
    await Future<void>.delayed(Duration.zero);
    expect(subjects.length, 8);
    for (final c in gates.where((g) => !g.isCompleted)) {
      c.complete(envelope([]));
    }
    await Future<void>.delayed(Duration.zero);
  });
}
