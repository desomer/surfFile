import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/explorer_filter.dart';
import 'package:surf_file/models/super_layout_config.dart';
import 'package:surf_file/widgets/explorer_filter_bar.dart';
import 'package:surf_file/widgets/slot_implementation.dart';
import 'package:surf_file/widgets/super_layout.dart';

void main() {
  const filterBar = ExplorerFilterBar(
    filter: ExplorerFilter(),
    onChanged: _ignore,
    onClose: _noop,
  );

  testWidgets('the filter bar takes the height of its content in the north', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          // Un Column donne une hauteur illimitée : la hauteur du contenu.
          body: Column(children: [filterBar]),
        ),
      ),
    );
    final natural = tester.getSize(find.byType(ExplorerFilterBar)).height;
    expect(natural, inInclusiveRange(40, 400));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuperLayout(
            config: const SuperLayoutConfig(
              south: false,
              west: false,
              east: false,
              autoSides: {SuperLayoutZone.north},
              placements: {
                SuperLayoutZone.north: ['filter'],
                SuperLayoutZone.center: ['content'],
              },
            ),
            slots: [
              BuilderSlot(
                id: 'filter',
                label: 'filter',
                sizing: SlotSizing.intrinsic,
                builder: (_) => filterBar,
              ),
              BuilderSlot(
                id: 'content',
                label: 'content',
                builder: (_) => const SizedBox.expand(key: ValueKey('content')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(ExplorerFilterBar)).height,
      closeTo(natural, .5),
    );
    // Le contenu reçoit tout le reste.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('content'))).dy,
      closeTo(natural, .5),
    );
  });
}

void _ignore(ExplorerFilter _) {}

void _noop() {}
