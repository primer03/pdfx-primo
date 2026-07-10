part of 'pdf_view.dart';

/// Pages control
class PdfController with BasePdfController {
  PdfController({
    required this.document,
    this.initialPage = 1,
    this.viewportFraction = 1.0,
  }) : assert(viewportFraction > 0.0);

  @override
  final ValueNotifier<PdfLoadingState> loadingState = ValueNotifier(
    PdfLoadingState.loading,
  );

  /// Document future for showing in [PdfView]
  Future<PdfDocument> document;

  /// The page to show when first creating the [PdfView].
  late int initialPage;

  /// The fraction of the viewport that each page should occupy.
  ///
  /// Defaults to 1.0, which means each page fills the viewport in the scrolling
  /// direction.
  final double viewportFraction;

  _PdfViewState? _pdfViewState;
  PageController? _pageController;
  PdfDocument? _document;

  /// Actual page number wrapped with ValueNotifier
  @override
  late final ValueNotifier<int> pageListenable = ValueNotifier(initialPage);

  /// Actual showed page
  @override
  int get page => pageListenable.value;

  /// Count of all pages in document
  @override
  int? get pagesCount => _document?.pagesCount;

  /// Changes which page is displayed in the controlled [PdfView].
  ///
  /// Jumps the page position from its current value to the given value,
  /// without animation, and without checking if the new value is in range.
  void jumpToPage(int page) {
    final itemIndex = _pageLayout.itemIndexForPage(page);
    _setCurrentItem(itemIndex);
    _pageController!.jumpToPage(itemIndex);
  }

  /// Animates the controlled [PdfView] from the current page to the given page.
  ///
  /// The animation lasts for the given duration and follows the given curve.
  /// The returned [Future] resolves when the animation completes.
  ///
  /// The `duration` and `curve` arguments must not be null.
  Future<void> animateToPage(
    int page, {
    required Duration duration,
    required Curve curve,
  }) =>
      _pageController!.animateToPage(
        _pageLayout.itemIndexForPage(page),
        duration: duration,
        curve: curve,
      );

  /// Animates the controlled [PdfView] to the next page.
  ///
  /// The animation lasts for the given duration and follows the given curve.
  /// The returned [Future] resolves when the animation completes.
  ///
  /// The `duration` and `curve` arguments must not be null.
  Future<void> nextPage({required Duration duration, required Curve curve}) =>
      _pageController!.animateToPage(
        _pageController!.page!.round() + 1,
        duration: duration,
        curve: curve,
      );

  /// Animates the controlled [PdfView] to the previous page.
  ///
  /// The animation lasts for the given duration and follows the given curve.
  /// The returned [Future] resolves when the animation completes.
  ///
  /// The `duration` and `curve` arguments must not be null.
  Future<void> previousPage({
    required Duration duration,
    required Curve curve,
  }) =>
      _pageController!.animateToPage(
        _pageController!.page!.round() - 1,
        duration: duration,
        curve: curve,
      );

  /// Load document
  Future<void> loadDocument(
    Future<PdfDocument> documentFuture, {
    int initialPage = 1,
  }) {
    loadingState.value = PdfLoadingState.loading;
    return _loadDocument(documentFuture, initialPage: initialPage);
  }

  Future<void> _loadDocument(
    Future<PdfDocument> documentFuture, {
    int initialPage = 1,
  }) async {
    if (_pdfViewState == null) return;

    try {
      final firstVisiblePage = _pageLayout.firstPageForItem(
        _pageLayout.itemIndexForPage(initialPage),
      );
      if (page != firstVisiblePage) {
        _pdfViewState?.widget.onPageChanged?.call(firstVisiblePage);
        pageListenable.value = firstVisiblePage;
      }
      _reInitPageController(initialPage);
      this.initialPage = initialPage;

      _document = await documentFuture;
      loadingState.value = PdfLoadingState.success;
    } catch (error) {
      _pdfViewState!._loadingError =
          error is Exception ? error : Exception('Unknown error');
      loadingState.value = PdfLoadingState.error;
    }
  }

  void _reInitPageController(int initialPage) {
    _pageController?.dispose();
    final itemIndex = _pageLayout.itemIndexForPage(initialPage);
    final firstVisiblePage = _pageLayout.firstPageForItem(itemIndex);
    if (pageListenable.value != firstVisiblePage) {
      pageListenable.value = firstVisiblePage;
    }
    _pageController = PageController(
      initialPage: itemIndex,
      viewportFraction: viewportFraction,
    );
  }

  PdfPageLayout get _pageLayout =>
      _pdfViewState?.widget.pageLayout ?? PdfPageLayout.single;

  void _setCurrentItem(int itemIndex) {
    final firstVisiblePage = _pageLayout.firstPageForItem(itemIndex);
    if (pageListenable.value == firstVisiblePage) return;

    pageListenable.value = firstVisiblePage;
    _pdfViewState?.widget.onPageChanged?.call(firstVisiblePage);
  }

  void _attach(_PdfViewState pdfViewState) {
    if (_pdfViewState != null) {
      return;
    }

    _pdfViewState = pdfViewState;

    _reInitPageController(page);

    if (_document == null) {
      _loadDocument(document, initialPage: initialPage);
    }
  }

  void _detach() {
    _pdfViewState = null;
  }

  void dispose() {
    _pageController?.dispose();
  }
}
