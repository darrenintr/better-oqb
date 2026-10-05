import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/catalog_controller.dart';
import '../controllers/study_controller.dart';
import '../models/oqb_api_data.dart';
import '../models/oqb_network_event.dart';
import '../models/oqb_page_state.dart';
import '../models/oqb_review.dart';
import '../services/oqb_api_client.dart';
import '../services/oqb_bridge.dart';
import '../services/oqb_repository.dart';
import '../widgets/oqb_browser.dart';
import '../widgets/oqb_html.dart';
import '../widgets/oqb_network_inspector.dart';
import 'catalog_view.dart';
import 'legacy_question_view.dart';
import 'status_views.dart';
import 'study_view.dart';

/// Hosts the authenticated OQB WebView (session holder + fallback) and the
/// API-backed Better OQB screens on top of it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final OqbBrowserController _browserController = OqbBrowserController();
  late final OqbWebViewApiClient _api;
  late final OqbRepository _repository;
  late final CatalogController _catalog;
  late final StudyController _study;
  late final OqbAssetLoader _assets;
  late final Widget _browser;

  OqbPageState _page = const OqbPageState();
  final List<OqbNetworkEvent> _networkEvents = <OqbNetworkEvent>[];
  bool _showOriginal = false;
  bool _autoShownForLogin = false;

  /// Paper the user (or the OQB route) last asked to open.
  int _requestedPaperId = 0;
  int _requestedQuestionNo = 0;

  /// Question-route paper already handled, so leaving the study view while
  /// OQB stays on that route does not immediately re-open it.
  int _handledRoutePaperId = 0;

  int _reviewPaperId = 0;
  OqbPaperSummary? _reviewSummary;
  OqbReview? _review;
  StudyController? _reviewStudy;
  Object? _reviewError;

  @override
  void initState() {
    super.initState();
    _api = OqbWebViewApiClient(runner: _browserController.evaluate);
    _repository = OqbRepository(_api);
    _catalog = CatalogController(_repository);
    _study = StudyController(_repository);
    _assets = OqbAssetLoader(_api);
    _api.status.addListener(_onApiStatus);
    _browser = OqbBrowser(
      controller: _browserController,
      bridge: OqbBridge(
        onPageState: _onPageState,
        onNetworkEvent: _recordNetworkEvent,
        onApiData: (event) => _catalog.observe(event),
        onApiClientMessage: _api.handleMessage,
      ),
    );
  }

  @override
  void dispose() {
    _api.status.removeListener(_onApiStatus);
    _reviewStudy?.dispose();
    _study.dispose();
    _catalog.dispose();
    _api.dispose();
    super.dispose();
  }

  // ---- inputs from the WebView ------------------------------------------------

  void _onApiStatus() {
    final status = _api.status.value;
    if (!status.isReady) return;
    if (!_catalog.hasLoaded && !_catalog.isLoading) _catalog.refresh();
    if (_autoShownForLogin && mounted) {
      setState(() {
        _autoShownForLogin = false;
        _showOriginal = false;
      });
    }
    _maybeAttachRoute();
  }

  void _onPageState(OqbPageState state) {
    if (!mounted) return;
    setState(() {
      _page = state;
      final needsLogin = state.isLoggedIn == false &&
          !_api.status.value.hasToken &&
          !_catalog.hasCatalog;
      if (needsLogin && !_showOriginal && !_autoShownForLogin) {
        // Not signed in: show the real OQB login page.
        _autoShownForLogin = true;
        _showOriginal = true;
      }
    });
    _maybeAttachRoute();
  }

  void _recordNetworkEvent(OqbNetworkEvent event) {
    if (!mounted) return;
    setState(() {
      _networkEvents.add(event);
      if (_networkEvents.length > 500) {
        _networkEvents.removeRange(0, _networkEvents.length - 500);
      }
    });
  }

  /// OQB itself is showing /paper/{id}/do/{n} (e.g. the user picked a paper
  /// in the original page): load that attempt through the API and switch to
  /// the Better OQB study view at the same question.
  void _maybeAttachRoute() {
    if (!_page.isQuestionRoute) {
      _handledRoutePaperId = 0;
      return;
    }
    final paperId = _page.routePaperId;
    if (paperId <= 0 || paperId == _handledRoutePaperId) return;
    if (!_api.status.value.isReady) return; // retried on the next status
    _handledRoutePaperId = paperId;
    if (_study.session?.paper.id == paperId || _study.loadingPaperId == paperId) return;
    _openPaper(paperId, questionNo: _page.routeQuestionNumber, showStudy: true);
  }

  // ---- actions ---------------------------------------------------------------

  Future<void> _openPaper(int paperId, {int questionNo = 0, bool showStudy = false}) async {
    if (_study.hasSession && _study.session!.paper.id != paperId) {
      if (!await _study.flush()) {
        _snack('Answers in the current paper are not saved yet; staying on it.');
        return;
      }
      _study.close();
      _assets.clear();
    }
    _closeReview();
    setState(() {
      _requestedPaperId = paperId;
      _requestedQuestionNo = questionNo;
      if (showStudy) _showOriginal = false;
    });
    await _study.open(paperId, questionNo: questionNo);
  }

  Future<void> _exitStudy() async {
    if (_study.unsavedCount > 0 && !await _study.flush()) {
      if (!mounted) return;
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Leave with unsaved answers?'),
          content: Text(
            '${_study.unsavedCount} answer(s) could not be saved to OQB. '
            'If you leave now they will be lost.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
          ],
        ),
      );
      if (leave != true) return;
    }
    _study.close();
    _assets.clear();
    if (mounted) setState(() => _requestedPaperId = 0);
  }

  Future<void> _submit() async {
    final paper = _study.session?.paper;
    if (paper == null) return;
    await _study.submit(); // errors are shown by StudyView
    if (!mounted) return;
    _snack('Paper submitted.');
    _catalog.refreshPapers(paper.subjectCode);
    _study.close();
    setState(() => _requestedPaperId = 0);
    await _openReview(paper.id);
  }

  Future<void> _openReview(int paperId, {OqbPaperSummary? summary}) async {
    _closeReview();
    setState(() {
      _reviewPaperId = paperId;
      _reviewSummary = summary;
      _showOriginal = false;
    });
    try {
      final review = await _repository.loadReview(paperId, summary: summary);
      if (!mounted || _reviewPaperId != paperId) return;
      final controller = StudyController(_repository)..attach(review.session);
      setState(() {
        _review = review;
        _reviewStudy = controller;
      });
    } catch (error) {
      if (!mounted || _reviewPaperId != paperId) return;
      setState(() => _reviewError = error);
    }
  }

  void _closeReview() {
    if (_reviewPaperId == 0) return;
    final old = _reviewStudy;
    setState(() {
      _reviewPaperId = 0;
      _review = null;
      _reviewStudy = null;
      _reviewError = null;
      _reviewSummary = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  /// Shows the original OQB page. During an attempt it is first navigated to
  /// the same question so both views agree.
  Future<void> _showOriginalPage() async {
    final session = _study.session;
    if (session != null && !_study.isReadOnly && _reviewPaperId == 0) {
      final onSameQuestion = _page.routePaperId == session.paper.id &&
          _page.routeQuestionNumber == _study.questionNumber;
      if (!onSameQuestion) {
        await _study.flush();
        _handledRoutePaperId = session.paper.id;
        await _browserController.openPath(
          '/paper/${session.paper.id}/do/${_study.questionNumber}',
        );
      }
    }
    if (mounted) setState(() => _showOriginal = true);
  }

  void _hideOriginalPage() {
    setState(() {
      _showOriginal = false;
      _autoShownForLogin = false;
    });
    // Pick up the question (and any answers) the user changed in OQB.
    final session = _study.session;
    if (session != null && !_study.isReadOnly && _page.routePaperId == session.paper.id) {
      final number = _page.routeQuestionNumber;
      if (number > 0) _study.goTo(number - 1);
      _study.reloadFromServer(questionNo: number);
    }
  }

  void _toggleOriginal() => _showOriginal ? _hideOriginalPage() : _showOriginalPage();

  void _createPaper() {
    _browserController.openPath('/student/viewtest');
    _showOriginalPage();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openNetworkInspector() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: OqbNetworkInspector(
          events: List<OqbNetworkEvent>.unmodifiable(_networkEvents),
          clientLog: _api.diagnostics.value,
          onClear: () {
            setState(_networkEvents.clear);
            _browserController.clearNetworkCapture();
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  bool _handleBack() {
    if (_showOriginal) {
      _hideOriginalPage();
    } else if (_reviewPaperId != 0) {
      _closeReview();
    } else if (_study.hasSession || _study.isLoading || _study.loadError != null) {
      _exitStudy();
    } else {
      return false;
    }
    return true;
  }

  // ---- view selection -----------------------------------------------------------

  bool get _inStudyScreen =>
      _reviewPaperId != 0 || _study.hasSession;

  Widget _buildBetterView() {
    final status = _api.status.value;

    if (_reviewPaperId != 0) {
      final review = _review;
      final controller = _reviewStudy;
      if (review == null || controller == null) {
        return PaperLoadingView(
          error: _reviewError,
          onRetry: _reviewError == null
              ? null
              : () => _openReview(_reviewPaperId, summary: _reviewSummary),
          onBack: _closeReview,
          onOpenOriginal: _showOriginalPage,
        );
      }
      return StudyView(
        key: ValueKey('review-${review.session.trial.id}'),
        controller: controller,
        meta: _catalog.meta,
        review: review,
        onExit: _closeReview,
        onOpenOriginal: _showOriginalPage,
        onOpenInspector: _openNetworkInspector,
      );
    }

    if (_study.hasSession) {
      return StudyView(
        key: ValueKey('trial-${_study.session!.trial.id}'),
        controller: _study,
        meta: _catalog.meta,
        onExit: _exitStudy,
        onOpenOriginal: _showOriginalPage,
        onOpenInspector: _openNetworkInspector,
        onSubmit: _submit,
      );
    }

    if (_study.isLoading) {
      return PaperLoadingView(
        questionNumber: _requestedQuestionNo,
        onBack: _exitStudy,
        onOpenOriginal: _showOriginalPage,
      );
    }

    final loadError = _study.loadError;
    if (loadError != null && _requestedPaperId != 0) {
      void retry() => _study.open(_requestedPaperId, questionNo: _requestedQuestionNo);
      if (_page.hasQuestion && _page.routePaperId == _requestedPaperId) {
        return LegacyQuestionView(
          state: _page,
          controller: _browserController,
          apiError: loadError,
          onRetryApi: retry,
          onOpenOriginal: _showOriginalPage,
        );
      }
      return PaperLoadingView(
        error: loadError,
        onRetry: retry,
        onBack: _exitStudy,
        onOpenOriginal: _showOriginalPage,
      );
    }

    if (_page.isQuestionRoute && !status.isReady) {
      // OQB shows a question but the API session is not usable yet.
      if (_page.hasQuestion) {
        return LegacyQuestionView(
          state: _page,
          controller: _browserController,
          onOpenOriginal: _showOriginalPage,
        );
      }
      return PaperLoadingView(
        questionNumber: _page.routeQuestionNumber,
        waitingForSession: true,
        onOpenOriginal: _showOriginalPage,
      );
    }

    if (_catalog.hasCatalog) {
      return CatalogView(
        controller: _catalog,
        onStartPaper: (paper) => _openPaper(paper.id),
        onReviewPaper: (paper) => _openReview(paper.id, summary: paper),
        onOpenOriginal: _showOriginalPage,
        onCreatePaper: _createPaper,
      );
    }

    if (status.isReady) {
      if (_catalog.hasLoaded && _catalog.error != null) {
        return PaperLoadingView(
          error: 'Could not load your question banks: ${_catalog.error}',
          onRetry: _catalog.refresh,
          onOpenOriginal: _showOriginalPage,
        );
      }
      return const BusyView(message: 'Loading your question banks…');
    }

    return ConnectView(
      isLoggedIn: _page.isLoggedIn,
      url: _page.url,
      onOpenOriginal: _showOriginalPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_study, _catalog, _api.status]),
      builder: (context, _) {
        final hideAppBar = !_showOriginal && _inStudyScreen;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (!_handleBack()) SystemNavigator.pop();
          },
          child: Scaffold(
            appBar: hideAppBar ? null : _buildAppBar(),
            body: SafeArea(
              top: hideAppBar,
              bottom: false,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_showOriginal,
                      child: _browser,
                    ),
                  ),
                  if (!_showOriginal)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                        child: OqbAssetScope(
                          loader: _assets,
                          child: _buildBetterView(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      titleSpacing: 16,
      toolbarHeight: 52,
      title: Text(_showOriginal ? 'Original OQB' : 'Better OQB'),
      actions: [
        IconButton(
          tooltip: 'OQB API inspector (${_networkEvents.length})',
          onPressed: _openNetworkInspector,
          icon: Badge(
            isLabelVisible: _networkEvents.isNotEmpty,
            label: Text(
              _networkEvents.length > 99 ? '99+' : '${_networkEvents.length}',
            ),
            child: const Icon(Icons.monitor_heart_outlined),
          ),
        ),
        _showOriginal
            ? FilledButton.tonalIcon(
                onPressed: _toggleOriginal,
                icon: const Icon(Icons.auto_awesome_mosaic),
                label: const Text('Better OQB'),
              )
            : IconButton(
                tooltip: 'Open original OQB',
                onPressed: _toggleOriginal,
                icon: const Icon(Icons.open_in_browser),
              ),
        const SizedBox(width: 8),
      ],
    );
  }
}
