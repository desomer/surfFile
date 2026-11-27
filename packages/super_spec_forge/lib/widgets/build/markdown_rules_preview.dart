/// Aperçu Markdown natif léger pour la lecture des règles et consignes
/// techniques dans l'éditeur de stacks ([MarkdownRulesPreview]).
library;

import 'package:material_ui/material_ui.dart';

/// Affiche un contenu Markdown formaté (titres, listes, cases à cocher,
/// blocs de code et styles en ligne) dans un panneau scrollable et sélectionnable
/// homogène avec les champs d'édition de `BuildTechStacksDialog`.
class MarkdownRulesPreview extends StatelessWidget {
  /// Crée un aperçu Markdown encadré avec [label] et [helperText] optionnels.
  const MarkdownRulesPreview({
    required this.markdown,
    required this.label,
    this.helperText,
    this.emptyPlaceholder = 'Aucun contenu saisi.',
    this.onOpenFullViewer,
    super.key,
  });

  /// Texte Markdown source à rendre.
  final String markdown;

  /// Titre du panneau affiché en en-tête.
  final String label;

  /// Indication optionnelle affichée sous le panneau.
  final String? helperText;

  /// Message affiché lorsque [markdown] est vide.
  final String emptyPlaceholder;

  /// Callback optionnelle ouvrant le visualiseur HTML complet.
  final VoidCallback? onOpenFullViewer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final trimmed = markdown.trim();
    final blocks = trimmed.isEmpty
        ? const <_MdBlock>[]
        : _parseMarkdownBlocks(markdown);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.outline.withValues(alpha: 0.7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    border: Border(
                      bottom: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 15,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (onOpenFullViewer != null && trimmed.isNotEmpty)
                        Tooltip(
                          message: 'Ouvrir dans le visualiseur complet',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: onOpenFullViewer,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.open_in_new_rounded,
                                size: 15,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: trimmed.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            emptyPlaceholder,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      : SelectionArea(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(14),
                            itemCount: blocks.length,
                            itemBuilder: (context, index) =>
                                _buildBlockWidget(context, blocks[index]),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        if (helperText != null && helperText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              helperText!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBlockWidget(BuildContext context, _MdBlock block) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return switch (block) {
      _MdHeadingBlock(:final level, :final text) => Padding(
        padding: EdgeInsets.only(top: level == 1 ? 8 : 10, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              _parseInlineSpans(
                text,
                baseStyle: (switch (level) {
                  1 => theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
                  ),
                  2 => theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                  _ => theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                })!,
                colors: colors,
              ),
            ),
            if (level <= 2)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Divider(
                  height: 1,
                  color: colors.outlineVariant.withValues(alpha: 0.65),
                ),
              ),
          ],
        ),
      ),
      _MdCodeBlock(:final language, :final code) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (language.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  language,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            Text(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      _MdListItemBlock(
        :final indent,
        :final marker,
        :final checked,
        :final text,
      ) =>
        Padding(
          padding: EdgeInsets.only(
            left: (indent * 16.0).clamp(0.0, 64.0),
            top: 2,
            bottom: 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (checked != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6),
                  child: Icon(
                    checked
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 15,
                    color: checked ? colors.primary : colors.onSurfaceVariant,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    marker,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                      height: 1.45,
                    ),
                  ),
                ),
              Expanded(
                child: Text.rich(
                  _parseInlineSpans(
                    text,
                    baseStyle: theme.textTheme.bodySmall!.copyWith(
                      height: 1.45,
                      color: colors.onSurface,
                    ),
                    colors: colors,
                  ),
                ),
              ),
            ],
          ),
        ),
      _MdDividerBlock() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Divider(height: 1, color: colors.outlineVariant),
      ),
      _MdParagraphBlock(:final text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text.rich(
          _parseInlineSpans(
            text,
            baseStyle: theme.textTheme.bodySmall!.copyWith(
              height: 1.45,
              color: colors.onSurface,
            ),
            colors: colors,
          ),
        ),
      ),
    };
  }
}

sealed class _MdBlock {
  const _MdBlock();
}

final class _MdHeadingBlock extends _MdBlock {
  const _MdHeadingBlock({required this.level, required this.text});

  final int level;
  final String text;
}

final class _MdCodeBlock extends _MdBlock {
  const _MdCodeBlock({required this.language, required this.code});

  final String language;
  final String code;
}

final class _MdListItemBlock extends _MdBlock {
  const _MdListItemBlock({
    required this.indent,
    required this.marker,
    required this.text,
    this.checked,
  });

  final int indent;
  final String marker;
  final bool? checked;
  final String text;
}

final class _MdDividerBlock extends _MdBlock {
  const _MdDividerBlock();
}

final class _MdParagraphBlock extends _MdBlock {
  const _MdParagraphBlock({required this.text});

  final String text;
}

List<_MdBlock> _parseMarkdownBlocks(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_MdBlock>[];
  var inCode = false;
  var codeLang = '';
  final codeBuffer = StringBuffer();

  final headingRe = RegExp(r'^(#{1,4})\s+(.*)$');
  final taskRe = RegExp(r'^(\s*)[-*]\s+\[([ xX])\]\s+(.*)$');
  final bulletRe = RegExp(r'^(\s*)[-*]\s+(.*)$');
  final orderedRe = RegExp(r'^(\s*)(\d+\.)\s+(.*)$');
  final dividerRe = RegExp(r'^\s*([-*_])\1{2,}\s*$');

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('```')) {
      if (!inCode) {
        inCode = true;
        codeLang = trimmed.substring(3).trim();
        codeBuffer.clear();
      } else {
        blocks.add(
          _MdCodeBlock(
            language: codeLang,
            code: codeBuffer.toString().trimRight(),
          ),
        );
        inCode = false;
        codeLang = '';
        codeBuffer.clear();
      }
      continue;
    }

    if (inCode) {
      codeBuffer.writeln(line);
      continue;
    }

    if (trimmed.isEmpty) continue;

    if (dividerRe.hasMatch(line)) {
      blocks.add(const _MdDividerBlock());
      continue;
    }

    if (headingRe.firstMatch(trimmed) case final m?) {
      blocks.add(
        _MdHeadingBlock(level: m.group(1)!.length, text: m.group(2)!.trim()),
      );
      continue;
    }

    if (taskRe.firstMatch(line) case final m?) {
      final spaces = m.group(1)!.length;
      blocks.add(
        _MdListItemBlock(
          indent: spaces ~/ 2,
          marker: '',
          checked: m.group(2)!.toLowerCase() == 'x',
          text: m.group(3)!,
        ),
      );
      continue;
    }

    if (bulletRe.firstMatch(line) case final m?) {
      final spaces = m.group(1)!.length;
      blocks.add(
        _MdListItemBlock(
          indent: spaces ~/ 2,
          marker: '•',
          text: m.group(2)!,
        ),
      );
      continue;
    }

    if (orderedRe.firstMatch(line) case final m?) {
      final spaces = m.group(1)!.length;
      blocks.add(
        _MdListItemBlock(
          indent: spaces ~/ 2,
          marker: m.group(2)!,
          text: m.group(3)!,
        ),
      );
      continue;
    }

    blocks.add(_MdParagraphBlock(text: trimmed));
  }

  if (inCode && codeBuffer.isNotEmpty) {
    blocks.add(
      _MdCodeBlock(
        language: codeLang,
        code: codeBuffer.toString().trimRight(),
      ),
    );
  }

  return blocks;
}

TextSpan _parseInlineSpans(
  String text, {
  required TextStyle baseStyle,
  required ColorScheme colors,
}) {
  final spans = <InlineSpan>[];
  final tokenRe = RegExp(
    r'(`[^`]+`|\*\*[^*]+\*\*|\*(?!\s)[^*\n]+?(?<!\s)\*)',
  );
  var cursor = 0;

  for (final match in tokenRe.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, match.start), style: baseStyle),
      );
    }
    final token = match.group(0)!;
    if (token.startsWith('`') && token.endsWith('`') && token.length >= 2) {
      spans.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            fontSize: (baseStyle.fontSize ?? 12.5) - 0.5,
            backgroundColor: colors.surfaceContainerHighest.withValues(
              alpha: 0.75,
            ),
            color: colors.primary,
          ),
        ),
      );
    } else if (token.startsWith('**') &&
        token.endsWith('**') &&
        token.length >= 4) {
      spans.add(
        TextSpan(
          text: token.substring(2, token.length - 2),
          style: baseStyle.copyWith(fontWeight: FontWeight.w700),
        ),
      );
    } else if (token.startsWith('*') &&
        token.endsWith('*') &&
        token.length >= 2) {
      spans.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    } else {
      spans.add(TextSpan(text: token, style: baseStyle));
    }
    cursor = match.end;
  }

  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }

  return TextSpan(children: spans, style: baseStyle);
}
