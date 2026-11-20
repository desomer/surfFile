/// Service principal de génération de PDF ([A4PdfGenerator]) à partir d'une page A4.
///
/// Assemble un [pw.Document] multi-pages au format A4 (`portrait` ou `landscape`)
/// en traduisant chaque feuille de [A4PageConfig] via [PdfComponentTranslator]
/// (vectoriel + fallback raster [PdfRasterFallback]) avec les données live des
/// repositories et les polices TrueType embarquées ([PdfFontResolver]).
library;

import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/a4_page_config.dart';
import '../../models/editor_page_config.dart';
import '../../models/registry.dart';
import '../../super_app.dart';
import '../../theme/appearance.dart';
import '../../widgets/appearance/appearance_scope.dart';
import '../repositories/json_repository_scope.dart';
import '../repositories/json_repository_store.dart';
import 'pdf_component_translator.dart';
import 'pdf_font_resolver.dart';
import 'pdf_raster_fallback.dart';

/// Résultat d'une génération PDF depuis une page A4.
@immutable
class A4PdfResult {
  /// Crée un résultat de génération PDF.
  const A4PdfResult({
    required this.bytes,
    required this.fileName,
    required this.pageCount,
    required this.rasterFallbackCount,
  });

  /// Octets bruts du fichier PDF généré.
  final Uint8List bytes;

  /// Nom de fichier suggéré (se terminant par `.pdf`).
  final String fileName;

  /// Nombre de pages A4 générées dans le document.
  final int pageCount;

  /// Nombre de composants rendus via le fallback raster haute résolution.
  final int rasterFallbackCount;
}

/// Génère un document PDF hybride (vectoriel + fallback raster) depuis une [A4PageConfig].
abstract final class A4PdfGenerator {
  /// Génère le PDF de la page A4 [pageId] à partir du [context] applicatif.
  static Future<A4PdfResult> generateFromContext(
    BuildContext context, {
    required String pageId,
    String? fileNameOverride,
    double rasterPixelRatio = 3.0,
    PdfFontResolver? fontResolver,
    PdfRasterCaptureCallback? customRasterCapture,
  }) {
    final app = SuperApp.maybeOf(context);
    final appearance = AppearanceScope.of(context);
    final registry = app?.registry;
    final store = JsonRepositoryScope.maybeOf(context);

    return generate(
      pageId: pageId,
      appearance: appearance,
      registry: registry,
      repositoryStore: store,
      context: context,
      fileNameOverride: fileNameOverride,
      rasterPixelRatio: rasterPixelRatio,
      fontResolver: fontResolver,
      customRasterCapture: customRasterCapture,
    );
  }

  /// Génère le PDF de la page A4 [pageId] depuis un modèle [Appearance] et un [JsonRepositoryStore].
  static Future<A4PdfResult> generate({
    required String pageId,
    required Appearance appearance,
    Registry? registry,
    JsonRepositoryStore? repositoryStore,
    BuildContext? context,
    String? fileNameOverride,
    double rasterPixelRatio = 3.0,
    PdfFontResolver? fontResolver,
    PdfRasterCaptureCallback? customRasterCapture,
  }) async {
    final snapshot = registry?.appearanceSnapshot(appearance) ?? appearance;
    final pageMeta = snapshot.pageCatalog.pages
        .where((p) => p.id == pageId)
        .firstOrNull;
    final rawConfig = snapshot.components[pageId];
    if (rawConfig != null && rawConfig is! A4PageConfig) {
      throw FormatException(
        'La page « $pageId » n’est pas une page Document A4.',
      );
    }
    if (rawConfig == null &&
        pageMeta != null &&
        pageMeta.pageType != EditorPageType.a4Document) {
      throw FormatException(
        'La page « ${pageMeta.name} » est de type standard et ne peut pas '
        'être exportée directement en document A4.',
      );
    }

    final a4Config =
        (rawConfig as A4PageConfig?) ?? A4PageConfig.initialForPage(pageId);
    final resolver = fontResolver ?? PdfFontResolver();
    final defaultPdfTheme = await resolver.buildDefaultTheme();

    final pageFormat = a4Config.orientation == A4Orientation.landscape
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4;
    final contentWidth =
        pageFormat.width - a4Config.marginLeft - a4Config.marginRight;
    final contentHeight =
        pageFormat.height - a4Config.marginTop - a4Config.marginBottom;
    final headerSpace = a4Config.headerSlotId != null
        ? a4Config.headerHeight + 8
        : 0.0;
    final footerSpace =
        (a4Config.footerSlotId != null || a4Config.showPageNumbers)
        ? a4Config.footerHeight + 8
        : 0.0;
    final bodySize = Size(
      contentWidth.clamp(40.0, pageFormat.width),
      (contentHeight - headerSpace - footerSpace).clamp(
        40.0,
        pageFormat.height,
      ),
    );

    final doc = pw.Document(
      title: pageMeta?.name ?? pageId,
      theme: defaultPdfTheme,
    );

    var totalRasterCount = 0;
    final totalSheets = a4Config.sheets.length;

    for (var i = 0; i < totalSheets; i++) {
      final sheet = a4Config.sheets[i];
      final paperColor = sheet.backgroundColor ?? Colors.white;
      final paperBrightness = paperColor.computeLuminance() < 0.45
          ? Brightness.dark
          : Brightness.light;
      final flutterTheme = snapshot.theme(paperBrightness);

      final translationCtx = PdfTranslationContext(
        buildContext: (context != null && context.mounted) ? context : null,
        appearance: snapshot,
        registry: registry,
        repositoryStore: repositoryStore,
        flutterTheme: flutterTheme,
        fontResolver: resolver,
        rasterPixelRatio: rasterPixelRatio,
        customRasterCapture: customRasterCapture,
      );
      final translator = PdfComponentTranslator(translationCtx);

      final pw.Widget? headerWidget = a4Config.headerSlotId == null
          ? null
          : await translator.translateSlot(
              slotId: a4Config.headerSlotId!,
              slotType: a4Config.headerSlotType,
              availableSize: Size(contentWidth, a4Config.headerHeight),
            );

      final bodyWidget = await translator.translateSlot(
        slotId: sheet.rootSlotId,
        slotType: sheet.rootSlotType,
        availableSize: bodySize,
      );

      final pw.Widget? footerSlotWidget = a4Config.footerSlotId == null
          ? null
          : await translator.translateSlot(
              slotId: a4Config.footerSlotId!,
              slotType: a4Config.footerSlotType,
              availableSize: Size(contentWidth, a4Config.footerHeight),
            );

      totalRasterCount += translationCtx.rasterFallbackCount;

      final pdfPaperColor = PdfColor.fromInt(paperColor.toARGB32());
      final pageNumberColor = PdfColor.fromInt(
        flutterTheme.colorScheme.onSurfaceVariant.toARGB32(),
      );

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Container(
            width: pageFormat.width,
            height: pageFormat.height,
            color: pdfPaperColor,
            padding: pw.EdgeInsets.fromLTRB(
              a4Config.marginLeft,
              a4Config.marginTop,
              a4Config.marginRight,
              a4Config.marginBottom,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (headerWidget != null) ...[
                  pw.SizedBox(
                    height: a4Config.headerHeight,
                    child: headerWidget,
                  ),
                  pw.SizedBox(height: 8),
                ],
                pw.Expanded(child: bodyWidget),
                if (footerSlotWidget != null || a4Config.showPageNumbers) ...[
                  pw.SizedBox(height: 8),
                  pw.SizedBox(
                    height: a4Config.footerHeight,
                    child: pw.Row(
                      children: [
                        if (footerSlotWidget != null)
                          pw.Expanded(child: footerSlotWidget)
                        else
                          pw.Spacer(),
                        if (a4Config.showPageNumbers)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(left: 8),
                            child: pw.Text(
                              'Page ${i + 1} / $totalSheets',
                              style: pw.TextStyle(
                                fontSize: 9,
                                color: pageNumberColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final rawName = (fileNameOverride?.trim().isNotEmpty == true)
        ? fileNameOverride!.trim()
        : a4Config.defaultFileName.trim();
    final safeName = rawName.toLowerCase().endsWith('.pdf')
        ? rawName
        : '$rawName.pdf';

    final bytes = await doc.save();
    return A4PdfResult(
      bytes: bytes,
      fileName: safeName,
      pageCount: totalSheets,
      rasterFallbackCount: totalRasterCount,
    );
  }
}
