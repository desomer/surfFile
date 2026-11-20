/// Page document au format A4 multi-feuilles ([A4DocumentPage]) avec édition WYSIWYG.
///
/// Affiche les feuilles explicites définies dans [A4PageConfig] aux dimensions
/// exactes du format A4 (`595.28 × 841.89 pt` en portrait, inversées en paysage),
/// sous [EditorZoom], avec gestion des marges, en-tête/pied de page répétés,
/// numérotation et outils d'ajout/duplication/réorganisation des feuilles en mode édition.
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/a4_page_config.dart';
import '../../models/behaviours/generate_pdf_action.dart';
import '../../models/registry.dart';
import '../../models/super_layout_config.dart';
import '../../super_app.dart';
import '../../theme/appearance.dart';
import '../appearance/appearance_scope.dart';
import '../editing/dialogs/editor_dialog_header.dart';
import '../editing/history/editor_history.dart';
import '../editing/overlay/editor_zoom.dart';
import '../editing/slots/editor_slot.dart';
import 'super_component.dart';
import 'super_layout/super_layout.dart';

/// Page document multi-feuilles au format A4 destinée à l'édition WYSIWYG et à l'export PDF.
class A4DocumentPage extends SuperStatefulComponent<A4PageConfig?> {
  /// Crée une [A4DocumentPage] identifiée par [id].
  const A4DocumentPage({
    required this.id,
    this.label = 'Document A4',
    this.pageConfig,
    this.maxAutoZoomExtent = EditorZoom.defaultMaxAutoZoomExtent,
    super.behaviours,
    super.key,
  });

  /// Identifiant stable de la page dans `Appearance.components`.
  @override
  final String id;

  /// Libellé affiché dans l'éditeur.
  final String label;

  /// Configuration initiale facultative ; les éditions persistées priment.
  final A4PageConfig? pageConfig;

  @override
  A4PageConfig? get config => pageConfig;

  /// Seuil de taille à partir duquel le zoom automatique n'encadre plus la sélection.
  final double maxAutoZoomExtent;

  @override
  State<A4DocumentPage> createState() => _A4DocumentPageState();
}

class _A4DocumentPageState extends State<A4DocumentPage> {
  late final ValueNotifier<A4PageConfig> _localConfig = ValueNotifier(
    widget.pageConfig ?? A4PageConfig.initialForPage(widget.id),
  );
  bool _exportingPdf = false;

  @override
  void didUpdateWidget(A4DocumentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageConfig != widget.pageConfig && widget.pageConfig != null) {
      _localConfig.value = widget.pageConfig!;
    }
  }

  @override
  void dispose() {
    _localConfig.dispose();
    super.dispose();
  }

  ValueNotifier<A4PageConfig> _controller(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    return registry?.a4PageController(
          widget.id,
          fallback:
              widget.pageConfig ?? A4PageConfig.initialForPage(widget.id),
        ) ??
        _localConfig;
  }

  void _updateConfig(
    BuildContext context,
    ValueNotifier<A4PageConfig> controller,
    A4PageConfig next,
  ) {
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    try {
      controller.value = next;
    } finally {
      history?.commitTransaction();
    }
  }

  void _addSheet(BuildContext context, ValueNotifier<A4PageConfig> controller) {
    final current = controller.value;
    final suffix = shortid.generate();
    final sheetNumber = current.sheets.length + 1;
    final nextSheet = A4SheetConfig(
      id: 'sheet-$suffix',
      label: 'Feuille $sheetNumber',
      rootSlotId: '${widget.id}-sheet-$suffix',
    );
    _updateConfig(
      context,
      controller,
      current.copyWith(sheets: [...current.sheets, nextSheet]),
    );
  }

  void _duplicateSheet(
    BuildContext context,
    ValueNotifier<A4PageConfig> controller,
    int index,
  ) {
    final current = controller.value;
    final source = current.sheets[index];
    final suffix = shortid.generate();
    final newSlotId = '${widget.id}-sheet-$suffix';
    final copySheet = A4SheetConfig(
      id: 'sheet-$suffix',
      label: '${source.label} (copie)',
      rootSlotId: newSlotId,
      rootSlotType: source.rootSlotType,
      backgroundColor: source.backgroundColor,
    );
    final appearanceController = AppearanceScope.controllerOf(context);
    final registry = SuperApp.maybeOf(context)?.registry;
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    try {
      // Copie superficielle du layout racine de la feuille si présent.
      if (appearanceController != null) {
        final snapshot =
            registry?.appearanceSnapshot(appearanceController.value) ??
            appearanceController.value;
        final sourceConfig = snapshot.components[source.rootSlotId];
        if (sourceConfig is SuperLayoutConfig) {
          appearanceController.value = appearanceController.value.withLayout(
            newSlotId,
            sourceConfig,
          );
        }
      }
      final nextSheets = [...current.sheets]..insert(index + 1, copySheet);
      controller.value = current.copyWith(sheets: nextSheets);
    } finally {
      history?.commitTransaction();
    }
  }

  void _removeSheet(
    BuildContext context,
    ValueNotifier<A4PageConfig> controller,
    int index,
  ) {
    final current = controller.value;
    if (current.sheets.length <= 1) return;
    final removed = current.sheets[index];
    final registry = SuperApp.maybeOf(context)?.registry;
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    try {
      final nextSheets = [...current.sheets]..removeAt(index);
      controller.value = current.copyWith(sheets: nextSheets);
      registry?.purgeInstance(
        removed.rootSlotId,
        removed.rootSlotType,
        EditorConfigKind.a4Page,
      );
    } finally {
      history?.commitTransaction();
    }
  }

  void _moveSheet(
    BuildContext context,
    ValueNotifier<A4PageConfig> controller,
    int index,
    int delta,
  ) {
    final current = controller.value;
    final target = index + delta;
    if (target < 0 || target >= current.sheets.length) return;
    final nextSheets = [...current.sheets];
    final item = nextSheets.removeAt(index);
    nextSheets.insert(target, item);
    _updateConfig(context, controller, current.copyWith(sheets: nextSheets));
  }

  Future<void> _renameSheet(
    BuildContext context,
    ValueNotifier<A4PageConfig> controller,
    int index,
  ) async {
    final current = controller.value;
    final sheet = current.sheets[index];
    final textController = TextEditingController(text: sheet.label);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Renommer la feuille'),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nom de la feuille'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = textController.text.trim();
                if (trimmed.isNotEmpty) {
                  Navigator.pop(dialogContext, trimmed);
                }
              },
              child: const Text('Valider'),
            ),
          ],
        ),
      );
      if (result == null || !context.mounted) return;
      final nextSheets = [
        for (var i = 0; i < current.sheets.length; i++)
          i == index ? current.sheets[i].copyWith(label: result) : current.sheets[i],
      ];
      _updateConfig(context, controller, current.copyWith(sheets: nextSheets));
    } finally {
      textController.dispose();
    }
  }

  Future<void> _openSettings(
    BuildContext context,
    ValueNotifier<A4PageConfig> controller,
  ) async {
    final next = await showDialog<A4PageConfig>(
      context: context,
      builder: (_) => _A4PageSettingsDialog(
        pageId: widget.id,
        initial: controller.value,
      ),
    );
    if (next == null || !context.mounted) return;
    _updateConfig(context, controller, next);
  }

  Future<void> _exportPdf(BuildContext context) async {
    if (_exportingPdf) return;
    setState(() => _exportingPdf = true);
    try {
      await GeneratePdfAction(
        pageId: widget.id,
        pageName: widget.label,
        outputMode: PdfOutputMode.exportDialog,
      ).execute(context);
    } finally {
      if (mounted) {
        setState(() => _exportingPdf = false);
      }
    }
  }

  Widget _buildSlotContent(
    BuildContext context,
    Registry? registry,
    String slotId,
    String slotType,
    String label,
  ) {
    final normalizedKey = _extractRegistryKey(slotType);
    if (normalizedKey != null && registry != null) {
      final builder = registry.registry[normalizedKey];
      if (builder != null) {
        return builder.getWidget(XuiBuildCtx(id: slotId));
      }
    }
    final superApp = SuperApp.maybeOf(context);
    if (superApp != null) {
      final layoutConfig = superApp.getLayoutConfigById(slotId);
      return ValueListenableBuilder<SuperLayoutConfig>(
        valueListenable: layoutConfig,
        builder: (context, config, _) => SuperLayout(
          id: slotId,
          label: label,
          config: config,
          onChanged: (value) => layoutConfig.value = value,
        ),
      );
    }
    return SuperLayout(
      id: slotId,
      label: label,
      config: const SuperLayoutConfig(),
      onChanged: (_) {},
    );
  }

  static String? _extractRegistryKey(String slotType) {
    var trimmed = slotType.trim();
    if (trimmed.isEmpty) return 'Layout';
    if (trimmed.startsWith('factory:')) {
      return trimmed.substring('factory:'.length);
    }
    if (trimmed.startsWith('registry:')) {
      return Uri.decodeComponent(trimmed.substring('registry:'.length));
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller(context);
    final editController = StyleEditScope.controllerOf(context);
    final registry = SuperApp.maybeOf(context)?.registry;
    final appearance = AppearanceScope.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        ?editController,
      ]),
      builder: (context, _) {
        final config = controller.value;
        final editing = editController?.value ?? false;
        final pageSize = config.pageSize;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: EditorZoom(
            maxAutoZoomExtent: widget.maxAutoZoomExtent,
            child: ColoredBox(
              key: ValueKey('a4-page-workspace-${widget.id}'),
            color: editing
                ? Theme.of(context).colorScheme.surfaceContainerLowest
                      .withValues(alpha: 0.72)
                : Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (editing)
                  _A4EditorToolbar(
                    pageLabel: widget.label,
                    config: config,
                    onToggleOrientation: () => _updateConfig(
                      context,
                      controller,
                      config.copyWith(
                        orientation: config.orientation == A4Orientation.portrait
                            ? A4Orientation.landscape
                            : A4Orientation.portrait,
                      ),
                    ),
                    onAddSheet: () => _addSheet(context, controller),
                    onOpenSettings: () => _openSettings(context, controller),
                    exportingPdf: _exportingPdf,
                    onExportPdf: () => _exportPdf(context),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey('a4-page-scroll-${widget.id}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 28,
                    ),
                    child: Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < config.sheets.length; i++) ...[
                              if (i > 0) const SizedBox(height: 28),
                              _A4SheetFrame(
                                key: ValueKey(
                                  'a4-sheet-${widget.id}-${config.sheets[i].id}',
                                ),
                                sheet: config.sheets[i],
                                index: i,
                                totalSheets: config.sheets.length,
                                pageSize: pageSize,
                                config: config,
                                appearance: appearance,
                                editing: editing,
                                onRename: () =>
                                    _renameSheet(context, controller, i),
                                onDuplicate: () =>
                                    _duplicateSheet(context, controller, i),
                                onDelete: config.sheets.length > 1
                                    ? () => _removeSheet(context, controller, i)
                                    : null,
                                onMoveUp: i > 0
                                    ? () => _moveSheet(context, controller, i, -1)
                                    : null,
                                onMoveDown: i < config.sheets.length - 1
                                    ? () => _moveSheet(context, controller, i, 1)
                                    : null,
                                headerChild: config.headerSlotId == null
                                    ? null
                                    : _buildSlotContent(
                                        context,
                                        registry,
                                        config.headerSlotId!,
                                        config.headerSlotType,
                                        'En-tête A4',
                                      ),
                                bodyChild: _buildSlotContent(
                                  context,
                                  registry,
                                  config.sheets[i].rootSlotId,
                                  config.sheets[i].rootSlotType,
                                  config.sheets[i].label,
                                ),
                                footerChild: config.footerSlotId == null
                                    ? null
                                    : _buildSlotContent(
                                        context,
                                        registry,
                                        config.footerSlotId!,
                                        config.footerSlotType,
                                        'Pied de page A4',
                                      ),
                              ),
                            ],
                          ],
                        ),
                      ),
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
}

class _A4EditorToolbar extends StatelessWidget {
  const _A4EditorToolbar({
    required this.pageLabel,
    required this.config,
    required this.onToggleOrientation,
    required this.onAddSheet,
    required this.onOpenSettings,
    required this.exportingPdf,
    required this.onExportPdf,
  });

  final String pageLabel;
  final A4PageConfig config;
  final VoidCallback onToggleOrientation;
  final VoidCallback onAddSheet;
  final VoidCallback onOpenSettings;
  final bool exportingPdf;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = config.pageSize;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '$pageLabel · A4 ${config.orientation.label} '
                  '(${size.width.round()} × ${size.height.round()} pt) · '
                  '${config.sheets.length} feuille${config.sheets.length > 1 ? 's' : ''}',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            OutlinedButton.icon(
              key: const ValueKey('a4-toggle-orientation'),
              onPressed: onToggleOrientation,
              icon: Icon(
                config.orientation == A4Orientation.portrait
                    ? Icons.stay_current_landscape_outlined
                    : Icons.stay_current_portrait_outlined,
                size: 16,
              ),
              label: Text(
                config.orientation == A4Orientation.portrait
                    ? 'Passer en paysage'
                    : 'Passer en portrait',
              ),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('a4-add-sheet'),
              onPressed: onAddSheet,
              icon: const Icon(Icons.note_add_outlined, size: 16),
              label: const Text('Ajouter une feuille'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('a4-page-settings'),
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune_outlined, size: 16),
              label: const Text('Mise en page A4'),
            ),
            FilledButton.icon(
              key: const ValueKey('a4-export-pdf'),
              onPressed: exportingPdf ? null : onExportPdf,
              icon: exportingPdf
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('Export PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

class _A4SheetFrame extends StatelessWidget {
  const _A4SheetFrame({
    required this.sheet,
    required this.index,
    required this.totalSheets,
    required this.pageSize,
    required this.config,
    required this.appearance,
    required this.editing,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.headerChild,
    required this.bodyChild,
    required this.footerChild,
    super.key,
  });

  final A4SheetConfig sheet;
  final int index;
  final int totalSheets;
  final Size pageSize;
  final A4PageConfig config;
  final Appearance appearance;
  final bool editing;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final Widget? headerChild;
  final Widget bodyChild;
  final Widget? footerChild;

  @override
  Widget build(BuildContext context) {
    final paperColor = sheet.backgroundColor ?? Colors.white;
    final paperBrightness = paperColor.computeLuminance() < 0.45
        ? Brightness.dark
        : Brightness.light;
    final sheetTheme = appearance.theme(paperBrightness);
    final showGuides = editing && config.showPageGuides;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (editing)
          SizedBox(
            width: pageSize.width,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    '${sheet.label} (${index + 1}/$totalSheets)',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Renommer la feuille',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: onRename,
                  ),
                  IconButton(
                    tooltip: 'Monter la feuille',
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    onPressed: onMoveUp,
                  ),
                  IconButton(
                    tooltip: 'Descendre la feuille',
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    onPressed: onMoveDown,
                  ),
                  IconButton(
                    tooltip: 'Dupliquer la feuille',
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    onPressed: onDuplicate,
                  ),
                  IconButton(
                    tooltip: 'Supprimer la feuille',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
          ),
        Container(
          width: pageSize.width,
          height: pageSize.height,
          decoration: BoxDecoration(
            color: paperColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
            border: showGuides
                ? Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                  )
                : null,
          ),
          child: Theme(
            data: sheetTheme,
            child: DefaultTextStyle.merge(
              style: TextStyle(color: sheetTheme.colorScheme.onSurface),
              child: Padding(
                padding: config.margins,
                child: DecoratedBox(
                  decoration: showGuides
                      ? BoxDecoration(
                          border: Border.all(
                            color: sheetTheme.colorScheme.primary.withValues(
                              alpha: 0.2,
                            ),
                            width: 0.8,
                          ),
                        )
                      : const BoxDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (headerChild != null) ...[
                        SizedBox(
                          height: config.headerHeight,
                          child: headerChild,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Expanded(child: bodyChild),
                      if (footerChild != null || config.showPageNumbers) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: config.footerHeight,
                          child: Row(
                            children: [
                              if (footerChild != null)
                                Expanded(child: footerChild!)
                              else
                                const Spacer(),
                              if (config.showPageNumbers)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    'Page ${index + 1} / $totalSheets',
                                    style: sheetTheme.textTheme.labelSmall
                                        ?.copyWith(
                                          color: sheetTheme
                                              .colorScheme
                                              .onSurfaceVariant,
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
            ),
          ),
        ),
      ],
    );
  }
}

class _A4PageSettingsDialog extends StatefulWidget {
  const _A4PageSettingsDialog({
    required this.pageId,
    required this.initial,
  });

  final String pageId;
  final A4PageConfig initial;

  @override
  State<_A4PageSettingsDialog> createState() => _A4PageSettingsDialogState();
}

class _A4PageSettingsDialogState extends State<_A4PageSettingsDialog> {
  late A4Orientation _orientation = widget.initial.orientation;
  late final TextEditingController _top = TextEditingController(
    text: widget.initial.marginTop.toStringAsFixed(0),
  );
  late final TextEditingController _right = TextEditingController(
    text: widget.initial.marginRight.toStringAsFixed(0),
  );
  late final TextEditingController _bottom = TextEditingController(
    text: widget.initial.marginBottom.toStringAsFixed(0),
  );
  late final TextEditingController _left = TextEditingController(
    text: widget.initial.marginLeft.toStringAsFixed(0),
  );
  late final TextEditingController _fileName = TextEditingController(
    text: widget.initial.defaultFileName,
  );
  late bool _enableHeader = widget.initial.headerSlotId != null;
  late bool _enableFooter = widget.initial.footerSlotId != null;
  late bool _showPageNumbers = widget.initial.showPageNumbers;
  late bool _showPageGuides = widget.initial.showPageGuides;
  String? _error;

  @override
  void dispose() {
    _top.dispose();
    _right.dispose();
    _bottom.dispose();
    _left.dispose();
    _fileName.dispose();
    super.dispose();
  }

  void _apply() {
    final top = double.tryParse(_top.text.trim());
    final right = double.tryParse(_right.text.trim());
    final bottom = double.tryParse(_bottom.text.trim());
    final left = double.tryParse(_left.text.trim());
    if (top == null || right == null || bottom == null || left == null) {
      setState(() => _error = 'Les marges doivent être des nombres valides.');
      return;
    }
    try {
      final headerSlotId = _enableHeader
          ? (widget.initial.headerSlotId ?? '${widget.pageId}-a4-header')
          : null;
      final footerSlotId = _enableFooter
          ? (widget.initial.footerSlotId ?? '${widget.pageId}-a4-footer')
          : null;
      final next = widget.initial.copyWith(
        orientation: _orientation,
        marginTop: top,
        marginRight: right,
        marginBottom: bottom,
        marginLeft: left,
        headerSlotId: headerSlotId,
        clearHeaderSlot: !_enableHeader,
        footerSlotId: footerSlotId,
        clearFooterSlot: !_enableFooter,
        showPageNumbers: _showPageNumbers,
        showPageGuides: _showPageGuides,
        defaultFileName: _fileName.text.trim().isEmpty
            ? 'document.pdf'
            : _fileName.text.trim(),
      );
      Navigator.pop(context, next);
    } on ArgumentError catch (e) {
      setState(() => _error = e.message?.toString() ?? e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mise en page A4'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EditorDialogHeader(label: 'Format et marges (points PDF)'),
              const SizedBox(height: 8),
              SegmentedButton<A4Orientation>(
                segments: const [
                  ButtonSegment(
                    value: A4Orientation.portrait,
                    label: Text('Portrait'),
                    icon: Icon(Icons.stay_current_portrait_outlined),
                  ),
                  ButtonSegment(
                    value: A4Orientation.landscape,
                    label: Text('Paysage'),
                    icon: Icon(Icons.stay_current_landscape_outlined),
                  ),
                ],
                selected: {_orientation},
                onSelectionChanged: (values) =>
                    setState(() => _orientation = values.first),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _top,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Haut (pt)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _right,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Droite (pt)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _bottom,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Bas (pt)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _left,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Gauche (pt)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _fileName,
                decoration: const InputDecoration(
                  labelText: 'Nom du fichier PDF par défaut',
                  hintText: 'facture.pdf',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('En-tête répété sur chaque feuille'),
                value: _enableHeader,
                onChanged: (v) => setState(() => _enableHeader = v),
              ),
              SwitchListTile(
                title: const Text('Pied de page répété sur chaque feuille'),
                value: _enableFooter,
                onChanged: (v) => setState(() => _enableFooter = v),
              ),
              SwitchListTile(
                title: const Text('Numérotation automatique (Page X / Y)'),
                value: _showPageNumbers,
                onChanged: (v) => setState(() => _showPageNumbers = v),
              ),
              SwitchListTile(
                title: const Text('Afficher les repères de marges en édition'),
                value: _showPageGuides,
                onChanged: (v) => setState(() => _showPageGuides = v),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _apply, child: const Text('Appliquer')),
      ],
    );
  }
}
