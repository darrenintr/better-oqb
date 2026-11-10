import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/oqb_api_data.dart';
import '../models/oqb_meta.dart';
import '../services/oqb_repository.dart';
import '../services/local_preferences.dart';

/// Packages, papers and labels for the Better OQB home screen.
///
/// Fed actively through [OqbRepository] once the WebView session is ready,
/// and passively from OQB's own observed API traffic, into one store.
class CatalogController extends ChangeNotifier {
  CatalogController(this.repository, {this.cache}) {
    if (cache != null) unawaited(restore());
  }
  final LocalPreferences? cache;
  String? preferredSubject;
  final List<String> _queue = [];
  final Map<String, Future<void>> _subjectTasks = {};
  int _workers = 0;
  bool _freshPackages = false;
  bool get isStale => !_freshPackages && _data.hasCatalog;
  Future<void> restore() async {
    try {
      final saved = await cache?.read('catalog');
      if (_disposed || _freshPackages || saved == null) return;
      // Cache contains package statistics only, never session or private paper URLs.
      final rows = saved['packages'];
      if (rows is List) {
        _data = _data.withPackages(
          rows
              .map(
                (p) => OqbPackageSummary.fromJson(
                  Map<String, dynamic>.from(p as Map),
                ),
              )
              .toList(),
        );
        _notify();
      }
    } catch (_) {
      /* A missing/corrupt cache never blocks authenticated refresh. */
    }
  }

  Future<void> _persist() async {
    try {
      await cache?.write('catalog', {
        'version': 1,
        'packages': [
          for (final p in _data.packages)
            {
              'id': p.id,
              'subject_code': p.subjectCode,
              'publisher_code': p.publisherCode,
              'title_zh': p.titleZh,
              'title_en': p.titleEn,
              'access_type': p.accessType,
              'stat': {
                'count_topic': p.topicCounts,
                'count_topic_difficulty': {
                  for (final e in p.topicDifficultyCounts.entries)
                    e.key: {
                      for (final d in e.value.entries)
                        d.key.toString(): d.value,
                    },
                },
              },
            },
        ],
      });
    } catch (_) {}
  }

  void prioritizeSubject(String subject) {
    preferredSubject = subject;
    _queue.remove(subject);
    _queue.insert(0, subject);
    _drain();
  }

  void _drain() {
    while (!_disposed && _workers < 2 && _queue.isNotEmpty) {
      final subject = _queue.removeAt(0);
      _workers++;
      unawaited(
        loadSubject(subject).whenComplete(() {
          _workers--;
          _drain();
        }),
      );
    }
  }

  final OqbRepository repository;

  OqbObservedApiState _data = const OqbObservedApiState();
  OqbMeta _meta = OqbMeta.empty;
  bool _loading = false;
  bool _loadedOnce = false;
  Object? _error;
  final Set<String> _subjectsLoading = <String>{};
  final Map<String, Object> _subjectErrors = <String, Object>{};
  bool _disposed = false;

  OqbObservedApiState get data => _data;
  OqbMeta get meta => _meta;
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  Object? get error => _error;
  bool get hasCatalog => _data.hasCatalog;

  bool isSubjectLoading(String subject) => _subjectsLoading.contains(subject);
  Object? subjectError(String subject) => _subjectErrors[subject];

  /// Folds an observed (passive) OQB API event into the catalog.
  void observe(OqbApiDataEvent event) {
    final next = _data.apply(event);
    if (identical(next, _data)) return;
    _data = next;
    _notify();
  }

  /// Loads labels, accessible packages and resumable papers, then each
  /// subject's submitted papers.
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _notify();

    await Future.wait([
      (() async {
        if (!_meta.isEmpty) return;
        try {
          _meta = await repository.getMeta();
          _notify();
        } catch (_) {}
      })(),
      (() async {
        try {
          final packages = await repository.getUsablePackages();
          if (_disposed) return;
          _freshPackages = true;
          _data = _data.withPackages(packages);
          _notify();
          unawaited(_persist());
        } catch (error) {
          _error = error;
        }
      })(),
      (() async {
        try {
          final papers = await repository.loadPapersToSubmit();
          if (!_disposed) {
            _data = _data.copyWith(availablePapers: papers);
            _notify();
          }
        } catch (error) {
          _error ??= error;
        }
      })(),
    ]);
    _loading = false;
    _loadedOnce = true;
    _notify();
    if (_disposed) return;
    final subjects = _data.subjects;
    _queue
      ..clear()
      ..addAll(subjects);
    if (preferredSubject != null && _queue.remove(preferredSubject)) {
      _queue.insert(0, preferredSubject!);
    }
    _drain();
  }

  /// Submitted and preset papers for [subject].
  Future<void> loadSubject(String subject) {
    return _subjectTasks[subject] ??= _loadSubject(
      subject,
    ).whenComplete(() {
      _subjectTasks.remove(subject);
    });
  }

  Future<void> _loadSubject(String subject) async {
    if (subject.isEmpty || _subjectsLoading.contains(subject)) return;
    _subjectsLoading.add(subject);
    _subjectErrors.remove(subject);
    _notify();
    try {
      final results = await Future.wait([
        repository.loadSubmittedPapers(subject),
        repository.loadPresetPapers(subject),
      ]);
      _data = _data
          .withSubmitted(subject, results[0])
          .withPreset(subject, results[1]);
    } catch (error) {
      _subjectErrors[subject] = error;
    } finally {
      _subjectsLoading.remove(subject);
      _notify();
    }
  }

  /// Refreshes paper lists after a submission.
  Future<void> refreshPapers(String subject) async {
    try {
      final papers = await repository.loadPapersToSubmit();
      _data = _data.copyWith(availablePapers: papers);
      _notify();
    } catch (_) {}
    await loadSubject(subject);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _queue.clear();
    _disposed = true;
    super.dispose();
  }
}
