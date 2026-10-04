import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/widgets/super_container.dart';


void main() {
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) => SuperApp(
    title: 'Surf File V 0.0.1 by Gauthier Desomer',
    home: getRootWidget(),
  );

 Widget getRootWidget() => SuperContainer(
      slot: AppearanceSlot.background,
      decorate: false,
      applyPadding: true,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: Text('Hello World')),
            Positioned(
              top: 56,
              right: 16,
              bottom: 16,
              child: Align(
                alignment: Alignment.topRight,
                child: SingleChildScrollView(child: overlyRight()),
              ),
            ),
          ],
        ),
      ),
    );

  Widget overlyRight() {
    return Container(
      color: Colors.blueAccent,
      width: 200,
      height: 200,
      child: const Center(child: Text('Overlay Right')),
    );
  }

}
