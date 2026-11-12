/// Visualiseur optimisé pour les documents JSON volumineux avec coloration syntaxique légère.
library;

import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Affiche un document JSON potentiellement volumineux avec coloration par ligne et copie rapide.
class LongJsonViewerSelectableColored extends StatelessWidget {
  final String json;

  const LongJsonViewerSelectableColored({super.key, required this.json});

  /// Formate une taille en octets en chaîne lisible.
  String getFileSizeString({required int bytes, int decimals = 0}) {
    const suffixes = ['b', 'kb', 'mb', 'gb', 'tb'];
    if (bytes == 0) return '0 ${suffixes[0]}';
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    int length = json.length;

    final lines = json.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          spacing: 20,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Export to clipboard'),
              onPressed: () => _exportJson(context, json),
            ),
            Text(
              'Size: ${getFileSizeString(bytes: length, decimals: 2)}  (${lines.length} lines)',
            ),
          ],
        ),
        if (length > 300000)
          // Mode optimisé pour les très gros JSON, avec un cache de 1000 pixels.
          Expanded(
            child: ListView.builder(
              scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
              prototypeItem: const SelectableText(
                maxLines: 1,
                'Prototype',
                style: TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
              padding: const EdgeInsets.all(16),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                return SelectableText.rich(
                  maxLines: 1,
                  _colorizeJsonLine(lines[index], false),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                );
              },
            ),
          ),

        if (length <= 300000)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText.rich(
                TextSpan(
                  children: lines
                      .map((line) => _colorizeJsonLine(line, true))
                      .toList(),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                textAlign: TextAlign.left,
                maxLines: null,
              ),
            ),
          ),
      ],
    );
  }

  TextSpan _colorizeJsonLine(String line, bool withCRLF) {
    final spans = <TextSpan>[];

    final regex = RegExp(
      r'("([^"\\]|\\.)*")|(\b\d+(\.\d+)?\b)|(true|false|null)',
    );

    int last = 0;

    for (final match in regex.allMatches(line)) {
      if (match.start > last) {
        spans.add(TextSpan(text: line.substring(last, match.start)));
      }

      final text = match.group(0)!;

      Color color;

      if (text.startsWith('"')) {
        final isKey = line.substring(match.end).trimLeft().startsWith(':');
        color = isKey ? Colors.redAccent : Colors.yellow;
      } else if (text == 'true' || text == 'false') {
        color = Colors.blue;
      } else if (text == 'null') {
        color = Colors.grey;
      } else {
        color = Colors.purple;
      }

      spans.add(
        TextSpan(
          text: text,
          style: TextStyle(color: color),
        ),
      );
      last = match.end;
    }

    if (last < line.length) {
      spans.add(TextSpan(text: line.substring(last)));
    }

    if (withCRLF) {
      spans.add(const TextSpan(text: '\n'));
    }
    return TextSpan(children: spans);
  }

  void _exportJson(BuildContext context, String content) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('JSON copied to clipboard')));
    await Clipboard.setData(ClipboardData(text: content));
  }
}
