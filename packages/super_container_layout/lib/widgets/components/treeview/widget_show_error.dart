import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

List<String> startError = [];
GlobalKey keyError = GlobalKey(debugLabel: 'keyError');

void showError(String message) {
  // SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
  //   ScaffoldMessenger.of(keyError.currentContext!).showSnackBar(
  //     SnackBar(
  //       duration: const Duration(seconds: 5),
  //       backgroundColor: Colors.red,

  //       content: Text(message, style: TextStyle(color: Colors.white)),
  //     ),
  //   );
  // });
}

class WidgetShowError extends StatelessWidget {
  const WidgetShowError({super.key});

  @override
  Widget build(BuildContext context) {
    if (startError.isNotEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(minutes: 1),
            backgroundColor: Colors.red,

            content: Text(
              'START ERROR ${startError.first}',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      });
    }

    return SizedBox(key: keyError, width: 10, height: 20);
  }
}
