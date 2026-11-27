/// Bouton « Context » et modale lecture seule affichant la totalité du contexte
/// envoyé à l'IA ([SpecChatContextButton], [showSpecAiContextDialog]).
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/spec_ai_context_snapshot.dart';

/// Bouton compact « Context » placé dans l'en-tête des chats IA de `super_spec_forge`.
///
/// Reste actif même pendant un tour IA ou avant le premier message afin de
/// permettre l'inspection en lecture seule du contexte complet envoyé au modèle.
class SpecChatContextButton extends StatelessWidget {
  /// Crée le bouton « Context » préfixé par [keyPrefix].
  const SpecChatContextButton({
    required this.onPressed,
    required this.keyPrefix,
    super.key,
  });

  /// Action déclenchée au clic pour ouvrir la modale de contexte.
  final VoidCallback? onPressed;

  /// Préfixe de la clé de widget (`$keyPrefix-context-btn`).
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Voir la totalité du contexte envoyé à l’IA (lecture seule)',
      child: OutlinedButton.icon(
        key: ValueKey('$keyPrefix-context-btn'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.data_object_rounded, size: 15),
        label: const Text('Context'),
      ),
    );
  }
}

/// Ouvre la fenêtre modale en lecture seule inspectant [inspection] (aperçu en
/// direct du prochain envoi et dernier envoi réel capturé).
Future<void> showSpecAiContextDialog(
  BuildContext context, {
  required SpecAiContextInspection inspection,
  bool? initialShowLastSent,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SpecAiContextDialog(
    inspection: inspection,
    initialShowLastSent: initialShowLastSent ?? inspection.hasLastSent,
  ),
);

enum _ContextTab {
  full,
  system,
  staticGuide,
  prompt,
  tools,
  attachmentsAndRounds,
}

class _SpecAiContextDialog extends StatefulWidget {
  const _SpecAiContextDialog({
    required this.inspection,
    required this.initialShowLastSent,
  });

  final SpecAiContextInspection inspection;
  final bool initialShowLastSent;

  @override
  State<_SpecAiContextDialog> createState() => _SpecAiContextDialogState();
}

class _SpecAiContextDialogState extends State<_SpecAiContextDialog> {
  late bool _showLastSent =
      widget.initialShowLastSent && widget.inspection.hasLastSent;
  _ContextTab _selectedTab = _ContextTab.full;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  String? _copiedFeedback;
  Timer? _copiedTimer;

  SpecAiContextSnapshot get _snapshot =>
      (_showLastSent ? widget.inspection.lastSent : null) ??
      widget.inspection.preview;

  List<_ContextTab> get _availableTabs => [
    _ContextTab.full,
    _ContextTab.system,
    _ContextTab.staticGuide,
    _ContextTab.prompt,
    _ContextTab.tools,
    if (_snapshot.hasAttachmentsOrRounds) _ContextTab.attachmentsAndRounds,
  ];

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _selectSource(bool showLastSent) {
    if (showLastSent && !widget.inspection.hasLastSent) return;
    setState(() {
      _showLastSent = showLastSent;
      if (!_availableTabs.contains(_selectedTab)) {
        _selectedTab = _ContextTab.full;
      }
    });
    _scrollToTop();
  }

  void _selectTab(_ContextTab tab) {
    if (_selectedTab == tab) return;
    setState(() => _selectedTab = tab);
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  String _textForTab(_ContextTab tab) {
    final s = _snapshot;
    return switch (tab) {
      _ContextTab.full => s.toFullText(),
      _ContextTab.system =>
        s.systemInstruction.trim().isEmpty
            ? '(Aucune instruction système)'
            : s.systemInstruction,
      _ContextTab.staticGuide =>
        s.staticGuide.trim().isEmpty ? '(Aucun guide statique)' : s.staticGuide,
      _ContextTab.prompt =>
        s.prompt.trim().isEmpty ? '(Prompt dynamique vide)' : s.prompt,
      _ContextTab.tools =>
        s.tools.isEmpty ? '(Aucun outil déclaré pour ce chat)' : s.toolsPrettyJson,
      _ContextTab.attachmentsAndRounds => _buildAttachmentsAndRoundsText(s),
    };
  }

  String _buildAttachmentsAndRoundsText(SpecAiContextSnapshot s) {
    final parts = <String>[];
    if (s.attachments.isNotEmpty) {
      parts.add(
        '=== PIÈCES JOINTES (${s.attachments.length}) ===\n\n${s.attachmentsText}',
      );
    }
    if (s.hasToolRounds) {
      parts.add(
        '=== ÉCHANGES MULTI-ROUNDS D’OUTILS (${s.conversationContents.length} entrées) ===\n\n'
        '${s.conversationRoundsPrettyJson}',
      );
    }
    return parts.isEmpty
        ? '(Aucune pièce jointe ni échange d’outil)'
        : parts.join('\n\n');
  }

  String _labelForTab(_ContextTab tab) {
    final s = _snapshot;
    return switch (tab) {
      _ContextTab.full => 'Complet',
      _ContextTab.system => 'System (${_formatCompactCount(s.systemChars)})',
      _ContextTab.staticGuide =>
        'Guide statique (${_formatCompactCount(s.staticGuideChars)})',
      _ContextTab.prompt =>
        'Prompt dynamique (${_formatCompactCount(s.promptChars)})',
      _ContextTab.tools => 'Outils (${s.tools.length})',
      _ContextTab.attachmentsAndRounds => 'Pièces jointes & Tours',
    };
  }

  String _tabKeySuffix(_ContextTab tab) => switch (tab) {
    _ContextTab.full => 'full',
    _ContextTab.system => 'system',
    _ContextTab.staticGuide => 'guide',
    _ContextTab.prompt => 'prompt',
    _ContextTab.tools => 'tools',
    _ContextTab.attachmentsAndRounds => 'extras',
  };

  Future<void> _copyText(String text, String feedback) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() => _copiedFeedback = feedback);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copiedFeedback = null);
      }
    });
  }

  ({TextSpan span, int matchCount}) _buildHighlightedSpan(
    String content,
    String query,
    TextStyle baseStyle,
    Color highlightBg,
    Color highlightFg,
  ) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return (span: TextSpan(text: content, style: baseStyle), matchCount: 0);
    }
    final lower = content.toLowerCase();
    final spans = <InlineSpan>[];
    var count = 0;
    var cursor = 0;
    const maxHighlightedSpans = 400;

    while (true) {
      final index = lower.indexOf(needle, cursor);
      if (index < 0) break;
      count++;
      if (count <= maxHighlightedSpans) {
        if (index > cursor) {
          spans.add(TextSpan(text: content.substring(cursor, index)));
        }
        spans.add(
          TextSpan(
            text: content.substring(index, index + needle.length),
            style: baseStyle.copyWith(
              backgroundColor: highlightBg,
              color: highlightFg,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }
      cursor = index + needle.length;
    }

    if (count == 0) {
      return (span: TextSpan(text: content, style: baseStyle), matchCount: 0);
    }
    if (count <= maxHighlightedSpans && cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor)));
    } else if (count > maxHighlightedSpans) {
      final lastHighlightedEnd = _findNthMatchEnd(
        lower,
        needle,
        maxHighlightedSpans,
      );
      if (lastHighlightedEnd < content.length) {
        spans.add(TextSpan(text: content.substring(lastHighlightedEnd)));
      }
    }
    return (span: TextSpan(style: baseStyle, children: spans), matchCount: count);
  }

  int _findNthMatchEnd(String lower, String needle, int n) {
    var cursor = 0;
    for (var i = 0; i < n; i++) {
      final idx = lower.indexOf(needle, cursor);
      if (idx < 0) return lower.length;
      cursor = idx + needle.length;
    }
    return cursor;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width * 0.92).clamp(480.0, 1140.0);
    final dialogHeight = (screenSize.height * 0.90).clamp(360.0, 840.0);

    final snapshot = _snapshot;
    final activeText = _textForTab(_selectedTab);
    final monoStyle = TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: const ['Cascadia Mono', 'Courier New', 'monospace'],
      fontSize: 12.5,
      height: 1.45,
      color: colors.onSurface,
    );
    final highlighted = _buildHighlightedSpan(
      activeText,
      _searchQuery,
      monoStyle,
      colors.tertiaryContainer,
      colors.onTertiaryContainer,
    );

    final localTime = snapshot.capturedAt.toLocal();
    final timeLabel =
        '${localTime.hour.toString().padLeft(2, '0')}:'
        '${localTime.minute.toString().padLeft(2, '0')}:'
        '${localTime.second.toString().padLeft(2, '0')}';

    return Dialog(
      key: const ValueKey('spec-ai-context-dialog'),
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: colors.primaryContainer,
                    child: Icon(
                      Icons.data_object_rounded,
                      size: 17,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Contexte IA · ${snapshot.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.secondaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 12,
                                    color: colors.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Lecture seule',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.onSecondaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          snapshot.isLivePreview
                              ? 'Aperçu en direct de la totalité du contexte prêt à être envoyé à l’IA'
                              : 'Dernier contexte réellement envoyé à l’IA (capturé à $timeLabel)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_copiedFeedback != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.tertiaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _copiedFeedback!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    key: const ValueKey('spec-ai-context-close-btn'),
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            // Bandeaux supérieurs (source, recherche, métadonnées) bornés pour éviter tout débordement
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: dialogHeight * 0.34),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Barre de source + recherche + copie
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border(
                          bottom: BorderSide(color: colors.outlineVariant),
                        ),
                      ),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ChoiceChip(
                                key: const ValueKey(
                                  'spec-ai-context-source-preview',
                                ),
                                label: const Text('Aperçu prochain envoi'),
                                selected: !_showLastSent,
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) => _selectSource(false),
                              ),
                              Tooltip(
                                message: widget.inspection.hasLastSent
                                    ? 'Afficher le dernier contexte réellement envoyé à l’IA'
                                    : 'Aucun envoi IA n’a encore eu lieu dans ce chat',
                                child: ChoiceChip(
                                  key: const ValueKey(
                                    'spec-ai-context-source-last',
                                  ),
                                  label: const Text('Dernier envoi réel'),
                                  selected: _showLastSent,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: widget.inspection.hasLastSent
                                      ? (_) => _selectSource(true)
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 220,
                                child: TextField(
                                  key: const ValueKey('spec-ai-context-search'),
                                  controller: _searchController,
                                  onChanged: (value) =>
                                      setState(() => _searchQuery = value),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'Rechercher dans l’onglet…',
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                      size: 16,
                                    ),
                                    suffixIcon: _searchQuery.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Effacer la recherche',
                                            iconSize: 16,
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() => _searchQuery = '');
                                            },
                                            icon: const Icon(
                                              Icons.clear_rounded,
                                            ),
                                          ),
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                  ),
                                ),
                              ),
                              if (_searchQuery.trim().isNotEmpty)
                                Text(
                                  '${highlighted.matchCount} occ.',
                                  key: const ValueKey(
                                    'spec-ai-context-search-count',
                                  ),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: highlighted.matchCount > 0
                                        ? colors.primary
                                        : colors.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              OutlinedButton.icon(
                                key: const ValueKey(
                                  'spec-ai-context-copy-tab-btn',
                                ),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () =>
                                    _copyText(activeText, 'Onglet copié'),
                                icon: const Icon(Icons.copy_rounded, size: 15),
                                label: const Text('Copier onglet'),
                              ),
                              FilledButton.tonalIcon(
                                key: const ValueKey(
                                  'spec-ai-context-copy-all-btn',
                                ),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _copyText(
                                  snapshot.toFullText(),
                                  'Contexte copié',
                                ),
                                icon: const Icon(
                                  Icons.content_copy_rounded,
                                  size: 15,
                                ),
                                label: const Text('Copier tout'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Bandeau de métadonnées
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLowest,
                        border: Border(
                          bottom: BorderSide(color: colors.outlineVariant),
                        ),
                      ),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _MetaPill(
                            icon: Icons.memory_rounded,
                            label:
                                '${snapshot.speedMode.defaultModel} (${snapshot.speedMode.label})',
                          ),
                          _MetaPill(
                            icon: Icons.quiz_outlined,
                            label:
                                'Questions : ${snapshot.questioningLevel.label}',
                          ),
                          _MetaPill(
                            icon: Icons.code_rounded,
                            label:
                                'JSON forcé : ${snapshot.enforceJsonResponse ? 'oui' : 'non'}',
                          ),
                          _MetaPill(
                            icon: Icons.cached_rounded,
                            label:
                                'Cache explicite : ${snapshot.usesExplicitCacheCandidate ? 'éligible' : 'non'}',
                          ),
                          _MetaPill(
                            icon: Icons.straighten_rounded,
                            label:
                                'Total : ${_formatInt(snapshot.totalChars)} car. (~${_formatInt(snapshot.estimatedTokens)} tokens)',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Onglets par section (toujours visibles au-dessus du contenu)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tab in _availableTabs)
                    ChoiceChip(
                      key: ValueKey(
                        'spec-ai-context-tab-${_tabKeySuffix(tab)}',
                      ),
                      label: Text(_labelForTab(tab)),
                      selected: _selectedTab == tab,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _selectTab(tab),
                    ),
                ],
              ),
            ),

            // Zone lecture seule sélectionnable
            Expanded(
              child: Container(
                color: colors.surface,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: SelectableText.rich(
                        highlighted.span,
                        key: const ValueKey('spec-ai-context-content'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatInt(int value) {
  final str = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    final remaining = str.length - i;
    buf.write(str[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buf.write('\u202F');
    }
  }
  return buf.toString();
}

String _formatCompactCount(int value) {
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
  return '$value';
}
