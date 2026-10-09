import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:surf_file/services/disk_space.dart';

// Run with Flutter on Windows, not the mocked flutter_test runner.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Text('Disk smoke test'))));
  try {
    final disks = await DiskSpace.load();
    final systemDrive = '${Platform.environment['SystemDrive']}\\';
    final system = disks.firstWhere(
        (disk) => disk.path.toLowerCase() == systemDrive.toLowerCase());
    if (system.usedFraction == null ||
        system.totalBytes! <= 0 ||
        system.freeBytes! < 0 ||
        system.freeBytes! > system.totalBytes!) {
      throw StateError('Windows did not return a valid system drive capacity.');
    }
    if (system.ejectable) {
      throw StateError('The system drive must never be ejectable.');
    }
    final ejectable = disks.where((disk) => disk.ejectable).map((d) => d.path);
    stdout.writeln('NATIVE_DISK_SMOKE_PASSED (${disks.length} disks, '
        'ejectable: ${ejectable.join(', ')})');
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  }
  exit(exitCode);
}
