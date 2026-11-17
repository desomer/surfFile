/// Boîte de dialogue interactive du catalogue de systèmes de design `DESIGN.md` ([DesignSystemCatalogDialog]).
///
/// Présente une galerie inspirée de `getdesign.md` regroupant les 24 préréglages intégrés de
/// [DesignSystemCatalog] ainsi que les chartes importées depuis un fichier `.md` ([VibeChatAttachment])
/// ou collées via [DesignMdParser]. Offre le filtrage par catégorie et luminosité, la recherche
/// bilingue, un inspecteur plein texte `DESIGN.md` et le retour d'un [DesignSystemSelectionResult]
/// via [showEditorDialog].
library;

import 'dart:convert';

import 'package:flutter/services.dart'
    show AssetBundle, Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

import '../../../ai/design_md_parser.dart';
import '../../../ai/design_system_catalog.dart';
import '../../../ai/vibe_chat_attachment.dart';
import '../dialogs/editor_dialog.dart';
import 'design_system_preview_card.dart';

enum _CatalogModeFilter {
  all('Tous', ValueKey<String>('design-catalog-mode-all')),
  light('Clair', ValueKey<String>('design-catalog-mode-light')),
  dark('Sombre', ValueKey<String>('design-catalog-mode-dark'));

  const _CatalogModeFilter(this.label, this.chipKey);

  final String label;
  final ValueKey<String> chipKey;
}

/// Boîte de dialogue modale permettant d'explorer, d'inspecter et d'importer des systèmes `DESIGN.md`.
class DesignSystemCatalogDialog extends StatefulWidget {
  /// Crée une boîte de dialogue de catalogue `DESIGN.md`.
  const DesignSystemCatalogDialog({
    this.initialPreset,
    this.customPresets = const [],
    this.isScoped = false,
    this.pickMarkdownFiles,
    this.readClipboardText,
    this.assetBundle,
    super.key,
  });

  static const _preferredWidth = AlwaysStoppedAnimation<double>(960);

  /// Préréglage initialement sélectionné à l'ouverture (`null` pour `'Material 3 (Défaut)'`).
  final DesignSystemPreset? initialPreset;

  /// Préréglages personnalisés déjà importés dans la session courante.
  final List<DesignSystemPreset> customPresets;

  /// Indique qu'un périmètre partiel (`VibeChatScope`) est actif, désactivant la synchronisation globale du thème.
  final bool isScoped;

  /// Sélecteur personnalisé optionnel de fichiers Markdown (remplace [VibeChatAttachment.pickFiles] en test).
  final Future<List<VibeChatAttachment>> Function()? pickMarkdownFiles;

  /// Lecteur personnalisé optionnel du presse-papiers texte (remplace [Clipboard.getData] en test).
  final Future<String?> Function()? readClipboardText;

  /// Bundle d'assets optionnel utilisé pour charger les fichiers `DESIGN.md` embarqués.
  final AssetBundle? assetBundle;

  /// Ouvre la galerie `DESIGN.md` dans un [showEditorDialog] contraint à `1060x740` et retourne le choix validé.
  static Future<DesignSystemSelectionResult?> show(
    BuildContext context, {
    DesignSystemPreset? initialPreset,
    List<DesignSystemPreset> customPresets = const [],
    bool isScoped = false,
    Future<List<VibeChatAttachment>> Function()? pickMarkdownFiles,
    Future<String?> Function()? readClipboardText,
    AssetBundle? assetBundle,
  }) {
    final effectiveBundle = assetBundle ?? DefaultAssetBundle.of(context);
    return showEditorDialog<DesignSystemSelectionResult>(
      context: context,
      preferredWidth: _preferredWidth,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 740),
          child: DesignSystemCatalogDialog(
            initialPreset: initialPreset,
            customPresets: customPresets,
            isScoped: isScoped,
            pickMarkdownFiles: pickMarkdownFiles,
            readClipboardText: readClipboardText,
            assetBundle: effectiveBundle,
          ),
        ),
      ),
    );
  }

  /// Crée l'état interne gérant les filtres, l'import et l'inspection `DESIGN.md`.
  @override
  State<DesignSystemCatalogDialog> createState() =>
      _DesignSystemCatalogDialogState();
}

class _DesignSystemCatalogDialogState extends State<DesignSystemCatalogDialog> {
  final TextEditingController _searchController = TextEditingController();

  late List<DesignSystemPreset> _customPresets;
  DesignSystemPreset? _selectedPreset;
  DesignSystemPreset? _inspectedPreset;
  Future<String>? _inspectedMarkdownFuture;
  String? _loadedInspectedMarkdown;
  String? _copiedTokenFeedback;

  DesignSystemCategory? _selectedCategory;
  _CatalogModeFilter _modeFilter = _CatalogModeFilter.all;
  late bool _syncThemeTokens;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _customPresets = List<DesignSystemPreset>.of(widget.customPresets);
    final initial = widget.initialPreset;
    if (initial != null &&
        initial.isCustom &&
        !_customPresets.any((preset) => preset.id == initial.id) &&
        !DesignSystemCatalog.builtInPresets.any(
          (preset) => preset.id == initial.id,
        )) {
      _customPresets.insert(0, initial);
    }
    _selectedPreset = initial;
    _syncThemeTokens = !widget.isScoped;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  AssetBundle get _effectiveBundle =>
      widget.assetBundle ?? DefaultAssetBundle.of(context);

  List<DesignSystemPreset> get _allPresets {
    final seenIds = <String>{};
    final combined = <DesignSystemPreset>[];
    for (final preset in _customPresets) {
      if (seenIds.add(preset.id)) {
        combined.add(preset);
      }
    }
    for (final preset in DesignSystemCatalog.builtInPresets) {
      if (seenIds.add(preset.id)) {
        combined.add(preset);
      }
    }
    return combined;
  }

  bool _matchesCategory(
    DesignSystemPreset preset,
    DesignSystemCategory? category,
  ) {
    if (category == null) return true;
    if (category == DesignSystemCategory.custom) {
      return preset.category == DesignSystemCategory.custom || preset.isCustom;
    }
    return preset.category == category;
  }

  bool _matchesMode(DesignSystemPreset preset) => switch (_modeFilter) {
    _CatalogModeFilter.all => true,
    _CatalogModeFilter.light => !preset.palette.isDark,
    _CatalogModeFilter.dark => preset.palette.isDark,
  };

  List<DesignSystemPreset> _filteredPresetsFor({
    required DesignSystemCategory? category,
    required String query,
    required bool applyCategory,
  }) {
    final trimmedQuery = query.trim();
    return _allPresets
        .where((preset) {
          if (applyCategory && !_matchesCategory(preset, category)) {
            return false;
          }
          if (!_matchesMode(preset)) return false;
          if (trimmedQuery.isNotEmpty && !preset.matchesQuery(trimmedQuery)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  bool _shouldIncludeDefaultCard(String query) {
    if (_selectedCategory != null) return false;
    if (_modeFilter != _CatalogModeFilter.all) return false;
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return true;
    const defaultHaystack =
        'material 3 material3 défaut defaut default adaptatif theme:* super_container_layout';
    final tokens = trimmed
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty);
    return tokens.every(defaultHaystack.contains);
  }

  void _upsertCustomPreset(DesignSystemPreset imported) {
    setState(() {
      final existingIndex = _customPresets.indexWhere(
        (preset) => preset.id == imported.id,
      );
      if (existingIndex >= 0) {
        _customPresets[existingIndex] = imported;
      } else {
        _customPresets.insert(0, imported);
      }
      _selectedPreset = imported;
      _inspectedPreset = null;
      _inspectedMarkdownFuture = null;
      _loadedInspectedMarkdown = null;
      _errorMessage = null;

      if (!_matchesCategory(imported, _selectedCategory)) {
        _selectedCategory = null;
      }
      if (!_matchesMode(imported)) {
        _modeFilter = _CatalogModeFilter.all;
      }
      if (_searchController.text.trim().isNotEmpty &&
          !imported.matchesQuery(_searchController.text)) {
        _searchController.clear();
      }
    });
  }

  Future<void> _importFromFile() async {
    setState(() => _errorMessage = null);
    try {
      final picker = widget.pickMarkdownFiles ?? VibeChatAttachment.pickFiles;
      final attachments = await picker();
      if (!mounted || attachments.isEmpty) return;

      DesignSystemPreset? lastImported;
      for (final attachment in attachments) {
        final rawText =
            attachment.textContent ??
            utf8.decode(attachment.bytes, allowMalformed: true);
        if (rawText.trim().isEmpty) {
          throw FormatException('Le fichier "${attachment.name}" est vide.');
        }
        final parsed = DesignMdParser.parseExternal(
          rawText,
          fileName: attachment.name,
        );
        final existingIndex = _customPresets.indexWhere(
          (preset) => preset.id == parsed.id,
        );
        if (existingIndex >= 0) {
          _customPresets[existingIndex] = parsed;
        } else {
          _customPresets.insert(0, parsed);
        }
        lastImported = parsed;
      }

      if (lastImported != null) {
        _upsertCustomPreset(lastImported);
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Impossible d’importer le fichier DESIGN.md : $error',
        );
      }
    }
  }

  Future<void> _openPasteDialog() async {
    setState(() => _errorMessage = null);
    final imported = await showDialog<DesignSystemPreset>(
      context: context,
      builder: (subDialogContext) =>
          _PasteDesignMdDialog(readClipboardText: widget.readClipboardText),
    );
    if (!mounted || imported == null) return;
    _upsertCustomPreset(imported);
  }

  void _openInspector(DesignSystemPreset preset) {
    final future = DesignSystemCatalog.loadMarkdown(
      preset,
      bundle: _effectiveBundle,
    );
    setState(() {
      _inspectedPreset = preset;
      _loadedInspectedMarkdown = null;
      _copiedTokenFeedback = null;
      _inspectedMarkdownFuture = future.then((content) {
        if (mounted && _inspectedPreset?.id == preset.id) {
          _loadedInspectedMarkdown = content;
        }
        return content;
      });
    });
  }

  Future<void> _copyInspectedMarkdown(DesignSystemPreset preset) async {
    try {
      final markdown =
          _loadedInspectedMarkdown ??
          await DesignSystemCatalog.loadMarkdown(
            preset,
            bundle: _effectiveBundle,
          );
      await Clipboard.setData(ClipboardData(text: markdown));
      if (!mounted) return;
      setState(() => _copiedTokenFeedback = 'DESIGN.md copié');
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage =
            'Impossible de copier le contenu DESIGN.md : $error',
      );
    }
  }

  Future<void> _copyHexSwatch(Color color) async {
    final hex = DesignSystemPalettePreview.colorToHex(color);
    await Clipboard.setData(ClipboardData(text: hex));
    if (!mounted) return;
    setState(() => _copiedTokenFeedback = '$hex copié');
  }

  void _confirmSelection({required bool triggerImmediateRestyle}) {
    final canSyncTheme = !widget.isScoped && _selectedPreset != null;
    final effectiveSync = canSyncTheme && _syncThemeTokens;
    Navigator.of(context).pop(
      DesignSystemSelectionResult(
        preset: _selectedPreset,
        applyThemeTokensNow: effectiveSync,
        triggerImmediateRestyle: triggerImmediateRestyle,
        updatedCustomPresets: _customPresets,
      ),
    );
  }

  List<DesignSystemCategory> get _visibleCategories => [
    for (final category in DesignSystemCategory.values)
      if (category != DesignSystemCategory.custom ||
          _customPresets.isNotEmpty ||
          _selectedCategory == DesignSystemCategory.custom)
        category,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalSystemsCount = 24 + _customPresets.length;

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopHeader(scheme, totalSystemsCount),
          const Divider(height: 1),
          if (_inspectedPreset == null) ...[
            _buildSearchAndModeBar(scheme),
            const Divider(height: 1),
          ],
          if (_errorMessage case final errorText?)
            _buildErrorBanner(scheme, errorText),
          Expanded(
            child: _inspectedPreset != null
                ? _buildInspectorView(scheme, _inspectedPreset!)
                : _buildCatalogBody(scheme),
          ),
          const Divider(height: 1),
          _buildBottomActionBar(scheme),
        ],
      ),
    );
  }

  Widget _buildTopHeader(ColorScheme scheme, int totalSystemsCount) {
    final countPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$totalSystemsCount systèmes',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );

    final actionButtons = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('design-catalog-import-file'),
          onPressed: _importFromFile,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          icon: const Icon(Icons.upload_file_outlined, size: 16),
          label: const Text('Importer .md'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('design-catalog-paste-markdown'),
          onPressed: _openPasteDialog,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          icon: const Icon(Icons.content_paste_go_outlined, size: 16),
          label: const Text('Coller DESIGN.md'),
        ),
      ],
    );

    final closeButton = IconButton(
      key: const ValueKey('design-catalog-close'),
      tooltip: 'Fermer',
      onPressed: () => Navigator.of(context).pop(),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.close, size: 20),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide =
              !constraints.maxWidth.isFinite || constraints.maxWidth >= 660;
          if (isWide) {
            return Row(
              children: [
                Icon(Icons.palette_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Catalogue DESIGN.md',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                countPill,
                const Spacer(),
                actionButtons,
                const SizedBox(width: 4),
                closeButton,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.palette_outlined, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Catalogue DESIGN.md',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  countPill,
                  const SizedBox(width: 4),
                  closeButton,
                ],
              ),
              const SizedBox(height: 6),
              actionButtons,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchAndModeBar(ColorScheme scheme) {
    final searchField = TextField(
      key: const ValueKey('design-catalog-search'),
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Rechercher un système, une ambiance, une couleur…',
        prefixIcon: const Icon(Icons.search, size: 18),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 34,
        ),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer la recherche',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: () => setState(_searchController.clear),
                icon: const Icon(Icons.clear, size: 16),
              ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    final modeChips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final filter in _CatalogModeFilter.values)
          ChoiceChip(
            key: filter.chipKey,
            label: Text(filter.label),
            selected: _modeFilter == filter,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => setState(() => _modeFilter = filter),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide =
              !constraints.maxWidth.isFinite || constraints.maxWidth >= 560;
          if (isWide) {
            return Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 12),
                modeChips,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [searchField, const SizedBox(height: 8), modeChips],
          );
        },
      ),
    );
  }

  Widget _buildErrorBanner(ColorScheme scheme, String message) => Container(
    color: scheme.errorContainer,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    child: Row(
      children: [
        Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: scheme.onErrorContainer,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Masquer l’erreur',
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          onPressed: () => setState(() => _errorMessage = null),
          icon: Icon(Icons.close, size: 16, color: scheme.onErrorContainer),
        ),
      ],
    ),
  );

  Widget _buildCatalogBody(ColorScheme scheme) {
    final query = _searchController.text;
    final matchingAllCategories = _filteredPresetsFor(
      category: null,
      query: query,
      applyCategory: false,
    );
    final filteredPresets = _filteredPresetsFor(
      category: _selectedCategory,
      query: query,
      applyCategory: true,
    );
    final includeDefault = _shouldIncludeDefaultCard(query);
    final items = <DesignSystemPreset?>[
      if (includeDefault) null,
      ...filteredPresets,
    ];

    int countForCategory(DesignSystemCategory? category) {
      if (category == null) return matchingAllCategories.length;
      return matchingAllCategories
          .where((preset) => _matchesCategory(preset, category))
          .length;
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildCategoryWrap(
            scheme: scheme,
            countForCategory: countForCategory,
          ),
        ),
        const SliverToBoxAdapter(child: Divider(height: 1)),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyPresetsState(scheme),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(14),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 310,
                mainAxisExtent: 266,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final preset = items[index];
                final isSelected = preset == null
                    ? _selectedPreset == null
                    : _selectedPreset?.id == preset.id;
                return DesignSystemPreviewCard(
                  preset: preset,
                  selected: isSelected,
                  onTap: () => setState(() => _selectedPreset = preset),
                  onInspect: preset == null
                      ? null
                      : () => _openInspector(preset),
                );
              }, childCount: items.length),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryWrap({
    required ColorScheme scheme,
    required int Function(DesignSystemCategory?) countForCategory,
  }) {
    final categories = _visibleCategories;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Wrap(
        key: const ValueKey('design-catalog-category-wrap'),
        spacing: 6,
        runSpacing: 6,
        children: [
          ChoiceChip(
            key: const ValueKey('design-catalog-category-all'),
            avatar: Icon(
              Icons.apps_outlined,
              size: 15,
              color: _selectedCategory == null
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
            label: Text('Tous (${countForCategory(null)})'),
            labelStyle: const TextStyle(fontSize: 12),
            selected: _selectedCategory == null,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => setState(() => _selectedCategory = null),
          ),
          for (final cat in categories)
            ChoiceChip(
              key: ValueKey<String>('design-catalog-category-${cat.id}'),
              avatar: Icon(
                cat.icon,
                size: 15,
                color: _selectedCategory == cat
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
              label: Text('${cat.label} (${countForCategory(cat)})'),
              labelStyle: const TextStyle(fontSize: 12),
              selected: _selectedCategory == cat,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onSelected: (_) => setState(() => _selectedCategory = cat),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyPresetsState(ColorScheme scheme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 36,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            'Aucun système de design ne correspond aux filtres actifs.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => setState(() {
              _selectedCategory = null;
              _modeFilter = _CatalogModeFilter.all;
              _searchController.clear();
            }),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Réinitialiser les filtres'),
          ),
        ],
      ),
    ),
  );

  Widget _buildInspectorView(ColorScheme scheme, DesignSystemPreset preset) {
    final isAlreadySelected = _selectedPreset?.id == preset.id;
    final swatchRoles = <(String, Color)>[
      ('Canvas', preset.palette.canvas),
      ('Surface', preset.palette.surface),
      ('Accent', preset.palette.accent),
      ('Texte', preset.palette.textPrimary),
      ('Bordure', preset.palette.border),
    ];

    return Container(
      key: const ValueKey('design-catalog-inspector'),
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barre d'en-tête de l'inspecteur DESIGN.md.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('design-catalog-inspector-back'),
                      onPressed: () => setState(() {
                        _inspectedPreset = null;
                        _copiedTokenFeedback = null;
                      }),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.arrow_back, size: 17),
                      label: const Text('Retour au catalogue'),
                    ),
                    Text(
                      preset.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    _InspectorPill(
                      label: preset.category.label,
                      scheme: scheme,
                    ),
                    _InspectorPill(
                      label: preset.palette.surfaceSystem.label,
                      scheme: scheme,
                    ),
                    _InspectorPill(
                      label: preset.palette.fontHint,
                      scheme: scheme,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_copiedTokenFeedback case final feedback?)
                      Text(
                        feedback,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    if (!isAlreadySelected)
                      FilledButton.tonal(
                        onPressed: () =>
                            setState(() => _selectedPreset = preset),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Sélectionner ce système'),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('design-catalog-copy-markdown'),
                      onPressed: () => _copyInspectedMarkdown(preset),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.copy_outlined, size: 15),
                      label: const Text('Copier DESIGN.md'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Barre des jetons hexadécimaux copiables en un clic.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, (roleLabel, color))
                    in swatchRoles.indexed) ...[
                  if (index > 0) const SizedBox(width: 8),
                  _HexSwatchChip(
                    roleLabel: roleLabel,
                    color: color,
                    onTap: () => _copyHexSwatch(color),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // Lecteur Markdown sélectionnable.
          Expanded(
            child: FutureBuilder<String>(
              future: _inspectedMarkdownFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Impossible de charger le fichier DESIGN.md :\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  );
                }
                final markdown = snapshot.data ?? '';
                return Container(
                  color: scheme.surfaceContainerLowest,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: SelectableText(
                      markdown,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12.5,
                        height: 1.5,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(ColorScheme scheme) {
    final canSyncTheme = !widget.isScoped && _selectedPreset != null;
    final effectiveCheckboxValue = canSyncTheme && _syncThemeTokens;
    const scopedDisabledText = 'Désactivé lorsqu’un scope partiel est actif';

    final syncControl = Tooltip(
      message: widget.isScoped ? scopedDisabledText : 'Applique immédiatement la luminosité clair/sombre et la couleur d’accentuation du système choisi',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: canSyncTheme
            ? () => setState(() => _syncThemeTokens = !_syncThemeTokens)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                key: const ValueKey('design-catalog-sync-theme-checkbox'),
                value: effectiveCheckboxValue,
                visualDensity: VisualDensity.compact,
                onChanged: canSyncTheme
                    ? (value) =>
                          setState(() => _syncThemeTokens = value ?? false)
                    : null,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Synchroniser le mode clair/sombre et l’accent immédiatement',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: canSyncTheme
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                    if (widget.isScoped)
                      Text(
                        scopedDisabledText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final actionButtons = Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.tonal(
          key: const ValueKey('design-catalog-confirm-use'),
          onPressed: () => _confirmSelection(triggerImmediateRestyle: false),
          child: const Text('Utiliser pour le chat'),
        ),
        FilledButton.icon(
          key: const ValueKey('design-catalog-confirm-restyle'),
          onPressed: _selectedPreset == null
              ? null
              : () => _confirmSelection(triggerImmediateRestyle: true),
          icon: const Icon(Icons.auto_fix_high, size: 17),
          label: const Text('Appliquer et restyler'),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide =
              !constraints.maxWidth.isFinite || constraints.maxWidth >= 780;
          if (isWide) {
            return Row(
              children: [
                Expanded(child: syncControl),
                const SizedBox(width: 12),
                actionButtons,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              syncControl,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: actionButtons),
            ],
          );
        },
      ),
    );
  }
}

class _InspectorPill extends StatelessWidget {
  const _InspectorPill({required this.label, required this.scheme});

  final String label;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    ),
  );
}

class _HexSwatchChip extends StatelessWidget {
  const _HexSwatchChip({
    required this.roleLabel,
    required this.color,
    required this.onTap,
  });

  final String roleLabel;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hex = DesignSystemPalettePreview.colorToHex(color);
    final isLight =
        ThemeData.estimateBrightnessForColor(color) == Brightness.light;
    return Tooltip(
      message: 'Copier $hex',
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isLight
                          ? Colors.black.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$roleLabel · ',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  hex,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasteDesignMdDialog extends StatefulWidget {
  const _PasteDesignMdDialog({this.readClipboardText});

  final Future<String?> Function()? readClipboardText;

  @override
  State<_PasteDesignMdDialog> createState() => _PasteDesignMdDialogState();
}

class _PasteDesignMdDialogState extends State<_PasteDesignMdDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _markdownController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _nameController.dispose();
    _markdownController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final text = widget.readClipboardText != null
          ? await widget.readClipboardText!()
          : (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) {
        setState(
          () => _validationError =
              'Le presse-papiers ne contient aucun texte DESIGN.md.',
        );
        return;
      }
      setState(() {
        _markdownController.text = text;
        _validationError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _validationError = 'Lecture du presse-papiers impossible : $error',
      );
    }
  }

  void _confirmPaste() {
    final markdown = _markdownController.text;
    final customName = _nameController.text.trim();
    try {
      var parsed = DesignMdParser.parseExternal(
        markdown,
        fileName: customName.isEmpty ? null : customName,
      );
      if (customName.isNotEmpty) {
        parsed = parsed.copyWith(name: customName);
      }
      Navigator.of(context).pop(parsed);
    } on FormatException catch (error) {
      setState(() => _validationError = error.message);
    } catch (error) {
      setState(() => _validationError = 'Contenu DESIGN.md invalide : $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.content_paste_go_outlined,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Coller un fichier DESIGN.md',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('design-catalog-paste-clipboard-btn'),
                    onPressed: _pasteFromClipboard,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.content_paste, size: 15),
                    label: const Text('Coller du presse-papiers'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('design-catalog-paste-name'),
                controller: _nameController,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Nom du système (optionnel)',
                  hintText: 'Ex. Mon Design System',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('design-catalog-paste-input'),
                controller: _markdownController,
                minLines: 8,
                maxLines: 14,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5),
                decoration: InputDecoration(
                  alignLabelWithHint: true,
                  hintText: 'Collez ici le contenu d’un fichier DESIGN.md (ex: depuis getdesign.md)…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (_validationError case final errorText?) ...[
                const SizedBox(height: 10),
                Text(
                  errorText,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: scheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('design-catalog-paste-confirm'),
                    onPressed: _confirmPaste,
                    icon: const Icon(Icons.check, size: 17),
                    label: const Text('Importer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
