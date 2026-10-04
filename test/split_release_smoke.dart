import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:surf_file/app.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_toolbar.dart';
import 'package:surf_file/widgets/file_operations/file_action_bar.dart';

void main() {
  runApp(const SurfFileApp());
  var toggles = 0;
  var attempts = 0;
  Timer.periodic(const Duration(seconds: 2), (timer) {
    final toolbars = <ExplorerToolbar>[];
    FileActionBar? bar;
    void visit(Element element) {
      if (element.widget case ExplorerToolbar value) {
        toolbars.add(value);
      }
      if (element.widget case FileActionBar value) {
        bar = value;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    if (toolbars.isEmpty || (toggles.isOdd && bar?.actionContext == null)) {
      if (++attempts >= 15) {
        stderr.writeln('SPLIT_SMOKE_FAILED: panes not ready');
        exit(1);
      }
      return;
    }
    final expected = toggles.isOdd ? 2 : 1;
    if (toolbars.length != expected) {
      stderr.writeln(
        'SPLIT_SMOKE_FAILED: ${toolbars.length} panes instead of $expected',
      );
      exit(1);
    }
    if (toggles == 6) {
      timer.cancel();
      stdout.writeln('SPLIT_SMOKE_PASSED: six split toggles');
      exit(0);
    }
    toolbars.first.onToggleSplit!();
    toggles++;
    stdout.writeln('SPLIT_SMOKE_TOGGLE: $toggles');
  });
}
