import 'package:flutter/foundation.dart';

import '../models/oqb_api_data.dart';
import '../models/oqb_meta.dart';
import '../services/oqb_repository.dart';

/// Packages, papers and labels for the Better OQB home screen.
///
/// Fed actively through [OqbRepository] once the WebView session is ready,
/// and passively from OQB's own observed API traffic, into one store.
class CatalogController extends ChangeNotifier {
  CatalogController(this.repository);

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

    if (_meta.isEmpty) {
      try {
        _meta = await repository.getMeta();
      } catch (_) {
        // Labels are optional; codes are shown instead.
      }
    }

    try {
      final packages = await repository.getUsablePackages();
      _data = _data.withPackages(packages);
    } catch (error) {
      _error = error;
    }

    try {
      final papers = await repository.loadPapersToSubmit();
      _data = _data.copyWith(availablePapers: papers);
    } catch (error) {
      _error ??= error;
    }

    _loading = false;
    _loadedOnce = true;
    _notify();

    await Future.wait(_data.subjects.map((subject) => loadSubject(subject)));
  }

  /// Submitted and preset papers for [subject].
  Future<void> loadSubject(String subject) async {
    if (subject.isEmpty || _subjectsLoading.contains(subject)) return;
    _subjectsLoading.add(subject);
    _subjectErrors.remove(subject);
    _notify();
    try {
      final results = await Future.wait([
        repository.loadSubmittedPapers(subject),
        repository.loadPresetPapers(subject),
      ]);
      _data = _data.withSubmitted(subject, results[0]).withPreset(subject, results[1]);
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
    _disposed = true;
    super.dispose();
  }
}
