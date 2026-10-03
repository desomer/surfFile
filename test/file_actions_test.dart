import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/actions/file_actions.dart';
import 'package:surf_file/services/file_operations.dart';

void main() {
  late Directory root;
  late String left;
  late String right;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('surf_file_ops_');
    left = (await Directory(
      '${root.path}${Platform.pathSeparator}left',
    ).create()).path;
    right = (await Directory(
      '${root.path}${Platform.pathSeparator}right',
    ).create()).path;
  });
  tearDown(() => root.delete(recursive: true));

  String at(String dir, String name) => FileOperations.join(dir, name);

  test('copy suffixes the name when the target exists', () async {
    await File(at(left, 'a.txt')).writeAsString('one');
    await File(at(right, 'a.txt')).writeAsString('two');

    final copy = await FileOperations.copy(at(left, 'a.txt'), right);

    expect(copy, at(right, 'a (2).txt'));
    expect(await File(copy).readAsString(), 'one');
    expect(await File(at(left, 'a.txt')).exists(), isTrue);
  });

  test('copy duplicates folders recursively', () async {
    final folder = await Directory(at(left, 'dir')).create();
    await Directory(at(folder.path, 'sub')).create();
    await File(at(at(folder.path, 'sub'), 'x.txt')).writeAsString('x');

    final copy = await FileOperations.copy(folder.path, right);

    expect(await File(at(at(copy, 'sub'), 'x.txt')).readAsString(), 'x');
    expect(await folder.exists(), isTrue);
  });

  test('move relocates and refuses to nest a folder in itself', () async {
    final folder = await Directory(at(left, 'dir')).create();
    await File(at(folder.path, 'x.txt')).writeAsString('x');

    await expectLater(
      FileOperations.copy(folder.path, folder.path),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      FileOperations.move(left, folder.path),
      throwsA(isA<FileSystemException>()),
    );

    final moved = await FileOperations.move(folder.path, right);
    expect(moved, at(right, 'dir'));
    expect(await folder.exists(), isFalse);
    expect(await File(at(moved, 'x.txt')).readAsString(), 'x');
  });

  test('split actions work on the left selection', () async {
    final file = at(left, 'a.txt');
    await File(file).writeAsString('a');
    final calls = <String>[];
    FileActionContext context({List<String> selection = const []}) =>
        FileActionContext(
          left: PaneSnapshot(path: left, selection: selection),
          right: PaneSnapshot(path: right),
          navigate: (l, r) async => calls.add('navigate $l $r'),
          refresh: () async => calls.add('refresh'),
        );

    expect(const CopyToRightAction().isEnabled(context()), isFalse);
    expect(const SwapPanesAction().isEnabled(context()), isTrue);

    expect(
      await const CopyToRightAction().run(context(selection: [file])),
      '1 élément copié',
    );
    expect(await File(at(right, 'a.txt')).exists(), isTrue);
    expect(
      await const MoveToRightAction().run(context(selection: [file])),
      '1 élément déplacé',
    );
    expect(await File(file).exists(), isFalse);
    expect(await File(at(right, 'a (2).txt')).exists(), isTrue);

    await const SwapPanesAction().run(context());
    expect(calls, ['refresh', 'refresh', 'navigate $right $left']);
  });
}
