import 'package:flutter/widgets.dart';
import 'package:pdfx/src/renderer/interfaces/document.dart';
import 'package:pdfx/src/renderer/interfaces/page.dart';
import 'package:pdfx/src/viewer/base/base_pdf_builders.dart';
import 'package:pdfx/src/viewer/base/base_pdf_controller.dart';
import 'package:pdfx/src/viewer/pdf_page_image_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:synchronized/synchronized.dart';

part 'pdf_controller.dart';
part 'pdf_view_builders.dart';

typedef PDfViewPageRenderer = Future<PdfPageImage?> Function(PdfPage page);

final Lock _lock = Lock();

/// Controls how PDF pages are grouped inside a [PdfView] viewport.
enum PdfPageLayout {
  /// Shows one PDF page at a time.
  single,

  /// Shows pages in pairs starting with pages 1 and 2.
  ///
  /// This is useful for newspapers and documents whose first page is not a
  /// standalone cover.
  twoUp,

  /// Shows page 1 by itself, then pages 2-3, 4-5, and so on.
  ///
  /// This matches the usual layout of a bound book.
  book,
}

extension _PdfPageLayoutX on PdfPageLayout {
  int itemCount(int pagesCount) => switch (this) {
        PdfPageLayout.single => pagesCount,
        PdfPageLayout.twoUp => (pagesCount + 1) ~/ 2,
        PdfPageLayout.book => pagesCount == 0 ? 0 : 1 + pagesCount ~/ 2,
      };

  int itemIndexForPage(int pageNumber) => switch (this) {
        PdfPageLayout.single => pageNumber - 1,
        PdfPageLayout.twoUp => (pageNumber - 1) ~/ 2,
        PdfPageLayout.book => pageNumber <= 1 ? 0 : 1 + (pageNumber - 2) ~/ 2,
      };

  int firstPageForItem(int itemIndex) => switch (this) {
        PdfPageLayout.single => itemIndex + 1,
        PdfPageLayout.twoUp => itemIndex * 2 + 1,
        PdfPageLayout.book => itemIndex == 0 ? 1 : itemIndex * 2,
      };

  List<int> pageIndexesForItem(int itemIndex, int pagesCount) {
    final firstIndex = firstPageForItem(itemIndex) - 1;
    final pageIndexes = <int>[firstIndex];
    if (this != PdfPageLayout.single &&
        !(this == PdfPageLayout.book && itemIndex == 0) &&
        firstIndex + 1 < pagesCount) {
      pageIndexes.add(firstIndex + 1);
    }
    return pageIndexes;
  }
}

/// Widget for viewing PDF documents
class PdfView extends StatefulWidget {
  const PdfView({
    required this.controller,
    this.onPageChanged,
    this.onDocumentLoaded,
    this.onDocumentError,
    this.builders = const PdfViewBuilders<DefaultBuilderOptions>(
      options: DefaultBuilderOptions(),
    ),
    this.renderer = _render,
    this.scrollDirection = Axis.horizontal,
    this.pageLayout = PdfPageLayout.single,
    this.spreadSpacing = 8,
    this.reverse = false,
    this.pageSnapping = true,
    this.physics,
    this.backgroundDecoration = const BoxDecoration(),
    super.key,
  }) : assert(spreadSpacing >= 0);

  /// Page management
  final PdfController controller;

  /// Called whenever the page in the center of the viewport changes
  final void Function(int page)? onPageChanged;

  /// Called when a document is loaded
  final void Function(PdfDocument document)? onDocumentLoaded;

  /// Called when a document loading error
  final void Function(Object error)? onDocumentError;

  /// Builders
  final PdfViewBuilders builders;

  /// Custom PdfRenderer options
  final PDfViewPageRenderer renderer;

  /// Page turning direction
  final Axis scrollDirection;

  /// How PDF pages are grouped in each viewport.
  final PdfPageLayout pageLayout;

  /// Space between pages when [pageLayout] shows a two-page spread.
  final double spreadSpacing;

  /// Reverse scroll direction, useful for RTL support
  final bool reverse;

  /// Set to false to disable page snapping, useful for custom scroll behavior.
  final bool pageSnapping;

  /// Pdf widget page background decoration
  final BoxDecoration? backgroundDecoration;

  /// Determines the physics of a [PdfView] widget.
  final ScrollPhysics? physics;

  /// Default PdfRenderer options
  static Future<PdfPageImage?> _render(PdfPage page) => page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#ffffff',
      );

  @override
  State<PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<PdfView> {
  final Map<int, PdfPageImage?> _pages = {};
  PdfController get _controller => widget.controller;
  Exception? _loadingError;

  @override
  void initState() {
    super.initState();
    _controller._attach(this);
    _controller.loadingState.addListener(_onLoadingStateChanged);
  }

  void _onLoadingStateChanged() {
    switch (_controller.loadingState.value) {
      case PdfLoadingState.loading:
        _pages.clear();
        break;
      case PdfLoadingState.success:
        widget.onDocumentLoaded?.call(_controller._document!);
        break;
      case PdfLoadingState.error:
        widget.onDocumentError?.call(_loadingError!);
        break;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.loadingState.removeListener(_onLoadingStateChanged);
    _controller._detach();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.loadingState.removeListener(_onLoadingStateChanged);
      oldWidget.controller._detach();
      widget.controller._attach(this);
      widget.controller.loadingState.addListener(_onLoadingStateChanged);
    } else if (oldWidget.pageLayout != widget.pageLayout) {
      final oldPage = _controller.page;
      _controller._reInitPageController(_controller.page);
      if (_controller.page != oldPage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onPageChanged?.call(_controller.page);
          }
        });
      }
    }
  }

  Future<PdfPageImage> _getPageImage(int pageIndex) =>
      _lock.synchronized<PdfPageImage>(() async {
        if (_pages[pageIndex] != null) {
          return _pages[pageIndex]!;
        }

        final page = await _controller._document!.getPage(pageIndex + 1);

        try {
          _pages[pageIndex] = await widget.renderer(page);
        } finally {
          await page.close();
        }

        return _pages[pageIndex]!;
      });

  @override
  Widget build(BuildContext context) {
    return widget.builders.builder(
      context,
      widget.builders,
      _controller.loadingState.value,
      _buildLoaded,
      _controller._document,
      _loadingError,
    );
  }

  static Widget _builder(
    BuildContext context,
    PdfViewBuilders builders,
    PdfLoadingState state,
    WidgetBuilder loadedBuilder,
    PdfDocument? document,
    Exception? loadingError,
  ) {
    final Widget content = () {
      switch (state) {
        case PdfLoadingState.loading:
          return KeyedSubtree(
            key: const Key('pdfx.root.loading'),
            child: builders.documentLoaderBuilder?.call(context) ??
                const SizedBox(),
          );
        case PdfLoadingState.error:
          return KeyedSubtree(
            key: const Key('pdfx.root.error'),
            child: builders.errorBuilder?.call(context, loadingError!) ??
                Center(child: Text(loadingError.toString())),
          );
        case PdfLoadingState.success:
          return KeyedSubtree(
            key: Key('pdfx.root.success.${document!.id}'),
            child: loadedBuilder(context),
          );
      }
    }();

    final defaultBuilder = builders as PdfViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;

    return AnimatedSwitcher(
      duration: options.loaderSwitchDuration,
      transitionBuilder: options.transitionBuilder,
      child: content,
    );
  }

  /// Default page builder
  static PhotoViewGalleryPageOptions _pageBuilder(
    BuildContext context,
    Future<PdfPageImage> pageImage,
    int index,
    PdfDocument document,
  ) =>
      PhotoViewGalleryPageOptions(
        imageProvider: PdfPageImageProvider(pageImage, index, document.id),
        minScale: PhotoViewComputedScale.contained * 1,
        maxScale: PhotoViewComputedScale.contained * 3.0,
        initialScale: PhotoViewComputedScale.contained * 1.0,
        heroAttributes: PhotoViewHeroAttributes(tag: '${document.id}-$index'),
      );

  PhotoViewGalleryPageOptions _spreadBuilder(
    BuildContext context,
    List<Future<PdfPageImage>> pageImages,
    List<int> pageIndexes,
    PdfDocument document,
  ) {
    final pageLoader = widget.builders.pageLoaderBuilder;
    final children = <Widget>[
      for (var i = 0; i < pageImages.length; i++)
        Expanded(
          child: FutureBuilder<PdfPageImage>(
            future: pageImages[i],
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text(snapshot.error.toString()));
              }
              if (!snapshot.hasData) {
                return pageLoader?.call(context) ?? const SizedBox();
              }
              return Align(
                alignment: pageImages.length == 1
                    ? Alignment.center
                    : i == 0
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                child: Image(
                  image: PdfPageImageProvider(
                    pageImages[i],
                    pageIndexes[i],
                    document.id,
                  ),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              );
            },
          ),
        ),
    ];

    return PhotoViewGalleryPageOptions.customChild(
      child: Row(
        key: Key('pdfx.spread.${pageIndexes.first}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: pageImages.length == 2
            ? [
                children.first,
                SizedBox(width: widget.spreadSpacing),
                children.last,
              ]
            : children,
      ),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.contained * 5.0,
      initialScale: PhotoViewComputedScale.contained,
      gestureDetectorBehavior: HitTestBehavior.opaque,
      heroAttributes: PhotoViewHeroAttributes(
        tag: '${document.id}-spread-${pageIndexes.first}',
      ),
    );
  }

  Widget _buildLoaded(BuildContext context) => PhotoViewGallery.builder(
        builder: (context, index) {
          final document = _controller._document!;
          final pageIndexes = widget.pageLayout.pageIndexesForItem(
            index,
            document.pagesCount,
          );
          if (widget.pageLayout == PdfPageLayout.single) {
            return widget.builders.pageBuilder(
              context,
              _getPageImage(pageIndexes.single),
              pageIndexes.single,
              document,
            );
          }
          final pageImages = pageIndexes.map(_getPageImage).toList();
          return widget.builders.spreadBuilder?.call(
                context,
                pageImages,
                pageIndexes,
                document,
              ) ??
              _spreadBuilder(context, pageImages, pageIndexes, document);
        },
        itemCount: widget.pageLayout.itemCount(
          _controller._document?.pagesCount ?? 0,
        ),
        loadingBuilder: (_, __) =>
            widget.builders.pageLoaderBuilder?.call(context) ??
            const SizedBox(),
        backgroundDecoration: widget.backgroundDecoration,
        pageController: _controller._pageController,
        onPageChanged: (index) {
          _controller._setCurrentItem(index);
        },
        scrollDirection: widget.scrollDirection,
        reverse: widget.reverse,
        scrollPhysics: widget.physics,
        pageSnapping: widget.pageSnapping,
      );
}
