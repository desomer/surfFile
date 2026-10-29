import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:super_container_layout/widgets/components/treeview/model_schema.dart';

class OnEvent {
  OnEvent({required this.id, required this.onPatch});

  String id;
  Function onPatch;
}

class SaveEvent {
  SaveEvent({
    required this.model,
    required this.version,
    required this.idIdempotence,
    required this.table,
    required this.data,
  });
  ModelSchema model;
  ModelVersion? version;
  String table;
  String idIdempotence;
  dynamic data;
  int sortIdx = 0;
}

Future<Map<String, dynamic>> computeSendYamlChangeEvent(
  Map<String, dynamic> event,
) async {
  String id = event['id'];
  String old = event['old'] ?? '';
  String value = event['value'];
  String version = event['version'];
  DiffMatchPatch dmp = DiffMatchPatch();
  List<Patch> patch = dmp.patch(old, value);

  String textPatch = patchToText(patch);
  return Future.value({
    'typeEvent': 'YAML',
    'id': id,
    'patch': textPatch,
    'old': old,
    'new': value,
    'version': version,
  });
}
