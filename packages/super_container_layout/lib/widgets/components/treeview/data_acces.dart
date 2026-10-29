import 'dart:async';
import 'dart:core';

import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/components/treeview/authorization_manager.dart';
import 'package:super_container_layout/widgets/components/treeview/data_event.dart';
import 'package:super_container_layout/widgets/components/treeview/json_browser.dart';
import 'package:super_container_layout/widgets/components/treeview/model_schema.dart';
import 'package:super_container_layout/widgets/components/treeview/widget_show_error.dart';


DataAcces bddStorage = DataAcces();
bool withBdd = true;

const String cstStorage = '##_storage_##';
const String cstStorageID = 'id';
const String cstStorageChange = 'changed';

class DataAcces {
  static const String _supabaseUrl = 'https://oielmrsjyymltbkyeuec.supabase.co';
  static const String _supabaseAnonKey =
      'sb_publishable_e9UTDwq91xn659rSjkzhCw_Z-nO5k06';

  // SupabaseClient? _sup;
  // late SupabaseClient supabase;
  StoreManager storeManager = StoreManager();

  // SupabaseClient getAuthClient() {
  //   _sup ??= SupabaseClient(
  //     _supabaseUrl,
  //     _supabaseAnonKey,
  //     authOptions: const AuthClientOptions(
  //       autoRefreshToken: true,
  //       authFlowType: AuthFlowType.implicit,
  //     ),
  //     //authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  //   );
  //   return _sup!;
  // }

  Future<void> ensureSessionValid() async {
    // final session = supabase.auth.currentSession;
    // if (session == null) return;

    // final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // final exp = session.expiresAt ?? 0;

    // // Si le token expire dans moins de 60 secondes → refresh
    // if (exp - now < 60) {
    //   AuthResponse newSession = await supabase.auth.refreshSession(
    //     session.refreshToken!,
    //   );
    //   supabase.auth.setSession(
    //     newSession.session!.refreshToken!,
    //     accessToken: newSession.session!.accessToken,
    //   );
    // }
  }

  Future<bool> connect(
    String usermail,
    String password, {
    String? accessToken,
    String? refreshToken,
  }) async {
    print("connect to supabase");
  //   try {
  //     supabase = getAuthClient();

  //     print("signInWithPassword to supabase");
  //     AuthResponse res;
  //     if (accessToken != null && refreshToken != null) {
  //       res = await supabase.auth.setSession(
  //         refreshToken,
  //         accessToken: accessToken,
  //       );
  //       // await ensureSessionValid();
  //     } else {
  //       res = await supabase.auth.signInWithPassword(
  //         email: usermail,
  //         password: password, //'test.archi',
  //       );
  //     }
  //     // ignore: unused_local_variable
  //     final Session? session = res.session;
  //     currentCompany.user = res.user;

  //     await prefs.setString("access_token", session!.accessToken);
  //     await prefs.setString("refresh_token", session.refreshToken!);
  //     await prefs.setString("mail", currentCompany.user!.email!);
  //     await prefs.remove("pwd");

  //     print("connect to supabase ok ${currentCompany.user!.email}");
  //     Map<String, dynamic>? userMeta = session.user.userMetadata;
  //     // final Map<String, dynamic> appMeta = session.user.appMetadata;

  //     var userCompagny = userMeta?['company_id'];
  //     var userPlan = userMeta?['plan'];

  //     print('userCompagny $userCompagny plan $userPlan');
  //     if (userCompagny != null) {
  //       currentCompany.companyId = userCompagny;
  //     }

  //     UserAuthentication.stateConnection.value = 'Loading profile ...';

  //     var queryattr = supabase
  //         .from('user_profil')
  //         .select('*')
  //         .eq('uid', currentCompany.user!.id);

  //     var ret2 = await queryattr;
  //     if (ret2.isNotEmpty) {
  //       // profil trouver par uid, c'est un user qui se connecte en creation d'admin
  //       await initProfilData(ret2);
  //     } else {
  //       var rule = userCompagny == null ? 'invit' : 'admin';
  //       List<dynamic> rules = [rule];

  //       var queryattr = supabase
  //           .from('user_profil')
  //           .select('*')
  //           .eq('namedId', currentCompany.user!.email!);
  //       ret2 = await queryattr;
  //       if (ret2.isNotEmpty) {
  //         print(
  //           'profil inviter trouver par email ${currentCompany.user!.email} >> ${ret2.first}',
  //         );
  //         // profil trouver, c'est un user qui se connecte sans uid (ex: magic link)
  //         // supprime l'ancien profil (affecter par l'admin) et en recréé un nouveau avec le uid
  //         currentCompany.userProfil = ret2.first;
  //         rules = currentCompany.userProfil!['data']['rule'];
  //         currentCompany.companyId = currentCompany.userProfil!['company_id'];

  //         await supabase
  //             .from('user_profil')
  //             .delete()
  //             .eq('uid', currentCompany.user!.email!);
  //       } else {
  //         print(
  //           'aucun profil trouver pour ${currentCompany.user!.email}, creation d\'un nouveau profil',
  //         );
  //         if (currentCompany.companyId == '?') {
  //           print(
  //             'aucune company id trouver pour ${currentCompany.user!.email}, creation d\'une nouvelle company',
  //           );
  //           currentCompany.companyId =
  //               'company_${DateTime.now().millisecondsSinceEpoch}';
  //         }
  //       }

  //       UserAuthentication.stateConnection.value =
  //           'Create ${currentCompany.user!.email}';

  //       currentCompany.userProfil = <String, dynamic>{
  //         'uid': currentCompany.user!.id,
  //         'namedId': currentCompany.user!.email,
  //         'data': {'rule': rules},
  //         'company_id': currentCompany.companyId,
  //       };
  //       print('user profil created ${currentCompany.userProfil}');
  //       await supabase.from('user_profil').upsert([currentCompany.userProfil]);
  //     }

  //     // var l = await supabase.auth.admin.listUsers();
  //     // print("l");
  //   } on Exception catch (e) {
  //     print(e);
  //     return false;
  //   }

  //   // Listen to auth state changes
  //   // supabase.auth.onAuthStateChange.listen((data) {
  //   //   final AuthChangeEvent event = data.event;
  //   //   final Session? session = data.session;
  //   //   // Do something when there is an auth event
  //   // });

  //   print("init realtime to supabase");
  //   myChannel = supabase.channel('room-one'); // set your topic here

  //   // Simple function to log any messages we receive
  //   void messageReceived(payload) {
  //     //print(payload);
  //     doEventListner[payload['id']]?.onPatch(payload);
  //   }

  //   // Subscribe to the Channel
  //   myChannel
  //       .onBroadcast(
  //         event: 'shout',
  //         // Listen for "shout". Can be "*" to listen to all events
  //         callback: (payload) => messageReceived(payload),
  //       )
  //       .subscribe();

  //   print("end connect to supabase");
     return true;
  }

  // Future<void> initProfilData(PostgrestList ret2) async {
  //   for (var element in ret2) {
  //     // liste des company
  //     print('user profil $element >> ${currentCompany.user}');
  //     currentCompany.userProfil = element;
  //     currentCompany.companyId = element['company_id'];
  //     if (element['namedId'] == null) {
  //       currentCompany.userProfil!['namedId'] = currentCompany.user!.email;
  //       await supabase.from('user_profil').upsert([currentCompany.userProfil]);
  //     }
  //   }
  // }

  //late RealtimeChannel myChannel;
  Map<String, CacheValue> localCache = {};
  Map<String, OnEvent> doEventListner = {};
  Map<String, ModelVersion> lastVersionByMaster = {};

  Future<dynamic> getTrashSupabase(
    ModelSchema model,
    String id,
    String pathYaml,
  ) async {
    await ensureSessionValid();
    // var queryattr = supabase
    //     .from('attributs')
    //     .select('*')
    //     .eq('company_id', currentCompany.companyId)
    //     .eq('state', 'D')
    //     .eq('schema_id', id)
    //     .eq('category', model.category.name)
    //     .eq('namespace', model.namespace ?? currentCompany.currentNameSpace)
    //     .order('update_at', ascending: false);
    // var ret2 = await queryattr;

    // if (ret2.isNotEmpty) {
    //   model.modelPropertiesByPath = {};
    //   for (var element in ret2) {
    //     AttributInfo info = AttributInfo();
    //     info.masterID = element['attr_id'];
    //     info.path = element['path'];
    //     info.properties = element['prop'];
    //     info.tooltipError = element['type'] ?? '?';

    //     info.action = element['state'];
    //     info.timeLastUpdate = DateTime.tryParse(element['update_at'] ?? '');
    //     model.mapInfoByTreePath[info.masterID!] = info;
    //     var path = 'root>$pathYaml>${info.masterID}';
    //     model.modelPropertiesByPath[path] = info.properties;
    //     model.modelPropertiesByPath[path]['_\$\$version'] =
    //         element['version'] ?? '1';
    //     model.mapInfoByJsonPath[path] = info;
    //   }
    //   return model.mapInfoByTreePath;
    // }
    // return null;
  }

  Future<dynamic> getFlowApp(ModelSchema model, String id) async {
    await ensureSessionValid();
    // var queryattr = supabase
    //     .from('attributs')
    //     .select('*')
    //     .eq('company_id', currentCompany.companyId)
    //     .eq('state', 'R')
    //     .eq('namespace', model.namespace ?? currentCompany.currentNameSpace)
    //     .eq('attr_id', id)
    //     .eq('schema_id', '${model.id}/data')
    //     .order('update_at', ascending: false);
    // var ret2 = await queryattr;
    // if (ret2.isNotEmpty) {
    //   return ret2.first['prop'];
    // }
    return null;
  }

  Future<dynamic> _getFromModelSupabase(
    ModelSchema model,
    String id,
    ModelVersion? version,
  ) async {
    await ensureSessionValid();

    // if (id.startsWith('json/')) {
    //   //print("load prop from bdd $id");
    //   var queryattr = supabase
    //       .from('attributs')
    //       .select('*')
    //       .eq('version', version?.version ?? '1')
    //       .eq('company_id', currentCompany.companyId)
    //       .eq('namespace', model.namespace ?? currentCompany.currentNameSpace)
    //       .eq('schema_id', id.substring('json/'.length))
    //       .eq('category', model.category.name)
    //       .eq('state', 'R');

    //   var ret2 = await queryattr;
    //   if (ret2.isNotEmpty) {
    //     model.modelPropertiesByPath = {};
    //     for (var element in ret2) {
    //       AttributInfo info = AttributInfo();
    //       info.masterID = element['attr_id'];
    //       info.path = element['path'];
    //       info.properties = element['prop'];
    //       info.action = element['state'];
    //       if (info.masterID?.startsWith('#') ?? false) {
    //         model.modelPropExtended[info.masterID!] = model.createExtend(info);
    //       } else {
    //         model.modelPropertiesByPath[info.path] = info.properties;
    //         model.mapInfoByJsonPath[info.path] = info;
    //       }
    //     }
    //     return {
    //       'prop': model.modelPropertiesByPath,
    //       'extended': model.modelPropExtended,
    //     };
    //   }
    // } else {
    //   //print("load yaml from bdd $id");
    //   var query = supabase
    //       .from('models')
    //       .select('json, namespace')
    //       .eq('namespace', model.namespace ?? currentCompany.currentNameSpace)
    //       .eq('compagny_id', currentCompany.companyId)
    //       .eq('model_id', id)
    //       .eq('version', version?.version ?? '1');

    //   var ret = await query;
    //   if (ret.isNotEmpty) {
    //     model.namespace =
    //         ret.first['namespace'] ?? currentCompany.currentNameSpace;
    //     return ret.first['json'];
    //   } else {
    //     model.namespace = currentCompany.currentNameSpace;
    //   }
    // }

    return null;
  }

  dynamic getItemSync({
    required ModelSchema model,
    required String id,
    required int delay,
    required ModelVersion? version,
  }) {
    if (delay == -1) {
      String cacheId = getCacheId(model, id, version);
      if (localCache[cacheId] != null) {
        return localCache[cacheId]!.value;
      }
    }
    return null;
  }

  dynamic getItem({
    required ModelSchema model,
    required String id,
    required ModelVersion? version,
    required int delay,
    required bool setcache,
  }) {
    if (delay == -1) {
      String cacheId = getCacheId(model, id, version);
      if (localCache[cacheId] != null) {
        return localCache[cacheId]!.value;
      }
    }
    return _getItemAsync(
      model: model,
      id: id,
      version: version,
      setcache: setcache,
    );
  }

  Future<dynamic> _getItemAsync({
    required ModelSchema model,
    required String id,
    required ModelVersion? version,
    required bool setcache,
  }) async {
    var ret = await _getFromModelSupabase(model, id, version);
    if (setcache) {
      String cacheId = getCacheId(model, id, version);
      _setCache(cacheId, ret);
    }
    return ret;
  }

  String getCacheId(ModelSchema model, String id, ModelVersion? version) {
    return '${model.namespace}/$id/${version?.version ?? '1'}';
  }

  Future<void> saveYAML({
    required String type,
    required ModelSchema model,
    dynamic value,
  }) async {
    ModelVersion? version = model.currentVersion;
    String cacheId = getCacheId(model, model.id, version);
    if (localCache[cacheId] != null) {
      var l = localCache[cacheId]!.value;
      if (type == 'YAML') {
        computeSendYamlChangeEvent({
          'old': l,
          'value': value,
          'id': '${model.namespace}/${model.id}',
          'version': version?.version ?? '1',
        })
        //compute(computeSendEvent, {'old': l, 'value': value, 'id': model.id});
        .then(_sendMessage);
      }
    }
    setYaml(model, value, version);
  }

  // void dispatchChangeProperties(
  //   ModelSchema model,
  //   dynamic patch,
  //   CodeEditorConfig textConfig,
  //   String version,
  // ) {
  //   var element = patch['payload'];
  //   if (model.getVersionId() == element['version']) {
  //     var info = model.mapInfoByJsonPath[element['path']] ?? AttributInfo();
  //     info.masterID = element['attr_id'];
  //     info.path = element['path'];
  //     info.properties = element['prop'];
  //     info.action = element['state'];
  //     model.modelPropertiesByPath[info.path] = info.properties;
  //     model.mapInfoByJsonPath[info.path] = info;
  //     info.cacheRowWidget = null;
  //     info.numUpdateForKey++;
  //     if (textConfig.treeJsonState?.mounted ?? false) {
  //       // ignore: invalid_use_of_protected_member
  //       textConfig.treeJsonState?.setState(() {});
  //     }
  //   }
  // }

  dynamic dispatchChangeYaml({
    required String id,
    dynamic patch,
    dynamic value,
    required String version,
  }) {
    String cacheId = '$id/$version';
    if (value == patch['old']) {
      localCache[cacheId]!.value = patch['new'];
      return localCache[cacheId]!.value;
    } else {
      List<Patch> patchDest = patchFromText(patch['patch']);
      DiffMatchPatch dmp = DiffMatchPatch();
      var result = dmp.patch_apply(patchDest, value);
      localCache[cacheId]!.value = result.first;
      return localCache[cacheId]!.value;
    }
  }

  Future<void> prepareSaveModel(ModelSchema model) async {
    var saveAttrDelete = [...model.notUseAttributInfo];
    var saveAttr = [...model.useAttributInfo];

    var extendedNode = model.modelPropExtended.values.toList();
    for (var element in extendedNode) {
      saveAttr.add(element.info);
    }

    for (var attr in saveAttrDelete) {
      if (attr.masterID != null && !attr.isInitByRef && attr.action != 'D') {
        if (model.onDeleteAttr(model, attr)) {
          attr.action = 'D';

          var payload = {
            'company_id': currentCompany.companyId,
            'namespace': model.namespace ?? currentCompany.currentNameSpace,
            'category': model.category.name,
            'schema_id': model.id,
            'version': model.getVersionId(),
            'attr_id': attr.masterID,
            'path': attr.path,
            'prop': attr.properties,
            'type': attr.type,
            'state': attr.action ?? 'D',
            'update_at': DateTime.now().toIso8601String(),
          };

          var save = SaveEvent(
            model: model,
            version: model.currentVersion,
            idIdempotence: '${model.id};${attr.masterID}',
            table: 'attributs',
            data: payload,
          );

          storeManager.add(save);

          // supprime le use> si il existe plus
          var payloadUse = {
            'company_id': currentCompany.companyId,
            'namespace': model.namespace ?? currentCompany.currentNameSpace,
            'category': model.category.name,
            'schema_id': "use>${model.id}",
            'version': model.getVersionId(),
            'attr_id': attr.masterID,
            'path': attr.path,
            'prop': attr.properties,
            'type': attr.type,
            'state': attr.action ?? 'D',
            'update_at': DateTime.now().toIso8601String(),
          };

          save = SaveEvent(
            model: model,
            version: model.currentVersion,
            idIdempotence: 'use>${model.id};${attr.masterID};D',
            table: 'attributs',
            data: payloadUse,
          );
          storeManager.add(save);

          // event
          _sendMessage({
            'typeEvent': 'PROP',
            'company_id': currentCompany.companyId,
            'id': '${model.namespace}/${model.id}',
            'payload': payload,
          });
        }
      }
    }

    var modelVerif = ModelSchema(
      category: model.category,
      headerName: '',
      id: '',
      infoManager: model.infoManager,
      refDomain: model.refDomain,
    );
    modelVerif.namespace = model.namespace;

    await _getFromModelSupabase(
      modelVerif,
      'json/${model.id}',
      model.currentVersion,
    );

    int nbUpdate = 0;
    for (var attr in saveAttr) {
      if (attr.masterID != null && !attr.isInitByRef && attr.action != 'R') {
        attr.action = 'R';
        nbUpdate++;
        String prefix = '';
        if (attr.singleSaveKey != null) {
          prefix = '${attr.singleSaveKey}>';
          print(
            'save cat=$prefix${model.category.name} ${attr.masterID} ${attr.path}',
          );
        }

        var payload = {
          'company_id': currentCompany.companyId,
          'namespace': model.namespace ?? currentCompany.currentNameSpace,
          'category': '$prefix${model.category.name}',
          'schema_id': model.id,
          'version': model.getVersionId(),
          'attr_id': attr.masterID,
          'path': attr.path,
          'prop': attr.properties,
          'state': attr.action ?? 'R',
          'update_at': DateTime.now().toIso8601String(),
        };

        var save = SaveEvent(
          model: model,
          version: model.currentVersion,
          idIdempotence: '$prefix${model.id};${attr.masterID};R',
          table: 'attributs',
          data: payload,
        );

        var old = modelVerif.mapInfoByJsonPath[attr.path];
        if (old != null && old.masterID != attr.masterID) {
          print('pb ********** double master id **************');
          print('${model.namespace}/json/${model.id} path = ${attr.path}');
          showError('double master id on ${attr.path}');
        } else {
          _sendMessage({
            'typeEvent': 'PROP',
            'id': '${model.namespace}/${model.id}',
            'payload': payload,
          });

          storeManager.add(save);
        }
      }
    }
    print('nbUpdate = $nbUpdate');
  }

  FutureOr<Null> _sendMessage(dynamic payload) async {
    try {
      //print('send by ${payload['id']} $payload'); // event $payload
      //final res =
      //await myChannel.sendBroadcastMessage(event: "shout", payload: payload);
      //print('call $res');
    } on Exception catch (e) {
      print(e);
    }
  }

  void store(SaveEvent event) {
    _setSupabase(event);
  }

  void doStore() {
    var store = {...storeManager.toStore};
    storeManager.toStore.clear();

    print('doStore ${store.length}');
    List storeList = store.entries.toList()
      ..sort((a, b) => a.value.sortIdx.compareTo(b.value.sortIdx));

    for (var element in storeList) {
      _setSupabase(element.value);
    }
  }

  Future<void> doStoreSync() async {
    var store = {...storeManager.toStore};
    storeManager.toStore.clear();
    print('doStore ${store.length}');

    List storeList = store.entries.toList()
      ..sort((a, b) => a.value.sortIdx.compareTo(b.value.sortIdx));

    for (var element in storeList) {
      await _setSupabase(element.value);
    }
  }

  Future<List<ModelVersion>> getAllVersion(ModelSchema model) async {
    await ensureSessionValid();
    // var id = model.id;
    // var queryattr = supabase
    //     .from('versions')
    //     .select('*')
    //     .eq('company_id', currentCompany.companyId)
    //     .eq('model_id', id);

    // var ret2 = await queryattr;

    var listVersion = <ModelVersion>[];
    // if (ret2.isNotEmpty) {
    //   for (var element in ret2) {
    //     ModelVersion version = ModelVersion(
    //       id: id,
    //       version: element['version'],
    //       data: element['json'],
    //     );
    //     listVersion.add(version);
    //   }
    //   listVersion.sort();
    // }
    // model.versions = listVersion;
    // print("load versions from bdd $id nb=${listVersion.length}");
    return listVersion;
  }

  Future<void> storeVersion(ModelSchema model, ModelVersion version) async {
    SaveEvent event = SaveEvent(
      version: version,
      model: model,
      idIdempotence: '',
      table: 'versions',
      data: {
        'company_id': currentCompany.companyId,
        'model_id': model.id,
        'version': version.version,
        'json': version.data,
      },
    );
    return await _setSupabase(event);
  }

  Future<void> addApiParam(
    ModelSchema model,
    String id,
    String category,
    dynamic json,
  ) async {
    SaveEvent event = SaveEvent(
      version: null,
      model: model,
      idIdempotence: '',
      table: 'api_params',
      data: {
        'id': id,
        'company_id': currentCompany.companyId,
        'api_id': model.id,
        'category': category,
        'param': json,
      },
    );
    return await _setSupabase(event);
  }

  Future<Map<String, dynamic>?> getAPIParam(
    ModelSchema model,
    String id,
  ) async {
    await ensureSessionValid();
    var apiid = model.id;
    //print("load param api from bdd $apiid");
    // var queryattr = supabase
    //     .from('api_params')
    //     .select('*')
    //     .eq('company_id', currentCompany.companyId)
    //     .eq('api_id', apiid)
    //     .eq('id', id);
    // var ret2 = await queryattr;
    // if (ret2.isNotEmpty) {
    //   for (var element in ret2) {
    //     return element['param'];
    //   }
    // }

    return null;
  }

  Future<void> _setSupabase(SaveEvent event) async {
    await ensureSessionValid();
   // await supabase.from(event.table).upsert([event.data]);
  }

  Future<void> restoreAttribut(ModelSchema model, NodeAttribut attr) async {
    await ensureSessionValid();
    //passe de D a R
    // await supabase
    //     .from('attributs')
    //     .update({'state': 'R'})
    //     .eq('attr_id', attr.info.getMasterID())
    //     .eq('company_id', currentCompany.companyId)
    //     .eq('version', model.currentVersion?.version ?? '1')
    //     .eq('namespace', model.namespace ?? currentCompany.currentNameSpace)
    //     .eq('schema_id', model.id);
  }

  void setYaml(ModelSchema model, dynamic value, ModelVersion? version) async {
    String cacheId = getCacheId(model, model.id, version);
    _setCache(cacheId, value);
    await _setYaml(model, value, version);
  }

  Future _setYaml(
    ModelSchema model,
    dynamic value,
    ModelVersion? version,
  ) async {
    print("save models yaml ${model.id}");

    var save = SaveEvent(
      model: model,
      version: version,
      idIdempotence: '${model.id};',
      table: 'models',
      data: {
        'compagny_id': currentCompany.companyId,
        'namespace': model.namespace ?? currentCompany.currentNameSpace,
        'model_id': model.id,
        'version': version?.version ?? '1',
        'json': value,
      },
    );

    storeManager.add(save);
  }

  void _setCache(String id, dynamic value) {
    if (value == null) {
      if (id.contains('/json/')) {
        value = <String, dynamic>{};
      } else {
        value = '';
      }
      print('setcache $id');
    }

    if (localCache[id] != null) {
      localCache[id]!.time = DateTime.now().millisecondsSinceEpoch;
      localCache[id]!.value = value;
    } else {
      localCache[id] = CacheValue()
        ..time = DateTime.now().millisecondsSinceEpoch
        ..value = value;
    }
  }

  Future<void> duplicateVersion(
    ModelSchema model,
    ModelVersion version,
    String modelYaml,
    List<AttributInfo> properties,
    Map<String, NodeAttribut> extend,
  ) async {
    await saveYAML(model: model, type: 'YAML', value: modelYaml);
    for (AttributInfo element in properties) {
      model.useAttributInfo.add(element.clone()..action = 'U');
    }
    for (var entry in extend.entries) {
      var ne = NodeAttribut(
        parent: null,
        yamlNode: MapEntry('extended', 'extended'),
        info: entry.value.info.clone()..action = 'U',
      );
      model.modelPropExtended[entry.key] = ne;
    }
    await prepareSaveModel(model);
    await doStoreSync();
  }

  Future<List<Map<String, dynamic>>?> getUserAuthByAuthId(
    String category,
    String authId,
  ) async {
    await ensureSessionValid();
    //print("load param api from bdd $apiid");
    // var queryattr = supabase
    //     .from('user_auth')
    //     .select('*, user_profil(namedId)')
    //     .eq('company_id', currentCompany.companyId)
    //     .eq('category', category)
    //     .eq('auth_id', authId);
    // var ret2 = await queryattr;

    // return ret2;
    return null;
  }

  Future<List<Map<String, dynamic>>?> getUserAuth(String userId) async {
    //print("load param api from bdd $apiid");
    await ensureSessionValid();

    // var queryattr = supabase
    //     .from('user_auth')
    //     .select('*')
    //     .eq('company_id', currentCompany.companyId)
    //     .eq('uid', userId);
    // var ret2 = await queryattr;

 // return ret2;
    return null;
  }

  Future<Map<String, dynamic>?> getCurrentUserSubscription() async {
    await ensureSessionValid();

    // final user = currentCompany.user;
    // if (user == null) {
    //   return null;
    // }

    // final email = user.email;
    // if (email != null && email.isNotEmpty) {
    //   final byEmail = await supabase
    //       .from('customer_subscriptions')
    //       .select('*')
    //       .eq('email', email)
    //       .order('updated_at', ascending: false)
    //       .limit(1);

    //   if (byEmail.isNotEmpty) {
    //     return Map<String, dynamic>.from(byEmail.first as Map);
    //   }
    // }

    // if (currentCompany.companyId.isNotEmpty &&
    //     currentCompany.companyId != '?') {
    //   final byCompany = await supabase
    //       .from('customer_subscriptions')
    //       .select('*')
    //       .eq('company_id', currentCompany.companyId)
    //       .order('updated_at', ascending: false)
    //       .limit(1);

    //   if (byCompany.isNotEmpty) {
    //     return Map<String, dynamic>.from(byCompany.first as Map);
    //   }
    // }

    return null;
  }

  Future<List<Map<String, dynamic>>?> getHistories(
    ModelSchema modelSchema,
  ) async {
    await ensureSessionValid();

    // var queryattr = supabase
    //     .from('histories')
    //     .select('*')
    //     .eq('company_id', currentCompany.companyId)
    //     .eq('version', modelSchema.getVersionId())
    //     .eq('model_id', modelSchema.id)
    //     .eq(
    //       'namespace',
    //       modelSchema.namespace ?? currentCompany.currentNameSpace,
    //     )
    //     .order('created_at', ascending: false)
    //     .limit(100);

    // var ret2 = await queryattr;
    // modelSchema.histories.clear();
    // for (var element in ret2) {
    //   modelSchema.histories.add(element['history']);
    // }

    // return ret2;
    return null;
  }

  void saveHistory(ModelSchema modelSchema, Map<String, dynamic> histo) {
    var saveHisto = {...histo};
    saveHisto.remove('node');

    // var save = SaveEvent(
    //   model: modelSchema,
    //   version: modelSchema.currentVersion,
    //   idIdempotence: '',
    //   table: 'histories',
    //   data: {
    //     'company_id': currentCompany.companyId,
    //     'model_id': modelSchema.id,
    //     'version': modelSchema.getVersionId(),
    //     'namespace': modelSchema.namespace ?? currentCompany.currentNameSpace,
    //     'user_id': currentCompany.user?.id,
    //     'uuid': histo['uuid'],
    //     'history': saveHisto,
    //   },
    // );
    // storeManager.add(save);
  }

  // ---- Comments ----

  // Future<List<Comment>> getComments(String contextId) async {
  //   await ensureSessionValid();

  //   var ret = await supabase
  //       .from('comments')
  //       .select('*')
  //       .eq('company_id', currentCompany.companyId)
  //       .eq('context_id', contextId)
  //       .order('date', ascending: true);

  //   return ret
  //       .map<Comment>(
  //         (e) => Comment.fromJson({
  //           'id': e['id'],
  //           'author': e['author'],
  //           'text': e['text'],
  //           'date': e['date'],
  //           'color': e['color'],
  //           'reactions': e['reactions'] ?? [],
  //           'replies': e['replies'] ?? [],
  //         }),
  //       )
  //       .toList();
  // }

  // Future<void> saveComment(String contextId, Comment comment) async {
  //   await ensureSessionValid();
  //   await supabase.from('comments').upsert([
  //     {
  //       'id': comment.id,
  //       'company_id': currentCompany.companyId,
  //       'context_id': contextId,
  //       'author': comment.author,
  //       'text': comment.text,
  //       'date': comment.date.toIso8601String(),
  //       'color': comment.color,
  //       'reactions': comment.reactions.map((r) => r.toJson()).toList(),
  //       'replies': comment.replies.map((r) => r.toJson()).toList(),
  //     },
  //   ]);
  // }

  // Future<void> deleteComment(String contextId, String commentId) async {
  //   await ensureSessionValid();
  //   await supabase
  //       .from('comments')
  //       .delete()
  //       .eq('company_id', currentCompany.companyId)
  //       .eq('context_id', contextId)
  //       .eq('id', commentId);
  // }

  // void saveData(
  //   CallerDatasource? callerDatasource,
  //   ModelSchema? currentAPIResponse,
  //   dynamic data,
  // ) {
  //   if (currentAPIResponse != null) {
  //     var facets = [];

  //     for (var element in callerDatasource?.facets ?? []) {
  //       var k = element.toString();
  //       facets.add({'key': k, 'value': data[k]});
  //     }

  //     int? id = data[cstStorage]?[cstStorageID];
  //     //var updatedAt = data[cstStorage]?['updated_at'];
  //     var backup1 = data.remove(cstStorage);

  //     SaveEvent event = SaveEvent(
  //       model: currentAPIResponse,
  //       version: currentAPIResponse.currentVersion,
  //       idIdempotence: '',
  //       table: 'user_data',
  //       data: {
  //         'company_id': currentCompany.companyId,
  //         'schema_id': callerDatasource?.modelShortName,
  //         'version': currentAPIResponse.getVersionId(),
  //         'json': data,
  //         'facets': facets,
  //         'id': ?id,
  //         'updated_at': DateTime.now().toUtc().toIso8601String(),
  //       },
  //     );
  //     store(event);
  //     if (backup1 != null) {
  //       data[cstStorage] = backup1;
  //     }
  //   }
  // }

  // ignore: slash_for_doc_comments
  /** 
final page = 3;
final pageSize = 20;

final from = (page - 1) * pageSize;
final to = from + pageSize - 1;

data = await supabase
    .from('products')
    .select()
    .select('*', const FetchOptions(count: CountOption.exact))
    .order('id')
    .range(from, to);

print(res.count);
 **/

  // Future<List<Map<String, dynamic>>> getInternalData(
  //   CallerDatasource callerDatasource,
  //   APICallManager apiCallInfo,
  // ) async {
  //   await ensureSessionValid();
  //   String escape(String s) => s.replaceAll('"', '\\"');

  //   var q = supabase.from('user_data').select();

  //   q = q.eq('company_id', currentCompany.companyId);
  //   q = q.eq('schema_id', callerDatasource.modelShortName!);
  //   q = q.eq('version', apiCallInfo.currentAPIResponse?.getVersionId() ?? '1');

  //   dynamic resolveValue(dynamic value, bool withEscape) {
  //     if (value is String) {
  //       return value.replaceAllMapped(RegExp(r'{{(.*?)}}'), (match) {
  //         var varName = match.group(1);
  //         var varValue = apiCallInfo.getParamValue('query', varName ?? '');
  //         if (withEscape && varValue is String) {
  //           varValue = escape(varValue);
  //         }
  //         return varValue != null ? varValue.toString() : '';
  //       });
  //     }
  //     return value;
  //   }

  //   String? normalizeLogicValue(dynamic value) {
  //     if (value == null) return null;
  //     if (value is num || value is bool) return value.toString();
  //     if (value is String) {
  //       final escaped = escape(value);
  //       final requiresQuotes =
  //           escaped.contains(',') ||
  //           escaped.contains('(') ||
  //           escaped.contains(')') ||
  //           escaped.contains(' ');
  //       return requiresQuotes ? '"$escaped"' : escaped;
  //     }
  //     return value.toString();
  //   }

  //   String? buildLogicClause(dynamic node) {
  //     if (node is! Map) return null;

  //     final hasField = node['field'] != null && node['ope'] != null;
  //     final hasAnd = node['and'] is List;
  //     final hasOr = node['or'] is List;

  //     if (hasField && !hasAnd && !hasOr) {
  //       final field = node['field'];
  //       final op = node['ope'];
  //       final value = normalizeLogicValue(resolveValue(node['value'], true));
  //       if (value != null && value.toString().isNotEmpty) {
  //         return 'json->>$field.$op.$value';
  //       } else {
  //         return 'id.gte.0'; // toujours true
  //       }
  //     }

  //     String? buildGroup(String logic, List group) {
  //       final clauses = <String>[];
  //       for (final child in group) {
  //         final childClause = buildLogicClause(child);
  //         if (childClause != null && childClause.isNotEmpty) {
  //           clauses.add(childClause);
  //         }
  //       }
  //       if (clauses.isEmpty) return null;
  //       if (clauses.length == 1) return clauses.first;
  //       return '$logic(${clauses.join(',')})';
  //     }

  //     final allClauses = <String>[];

  //     if (hasAnd) {
  //       final andClause = buildGroup('and', node['and']);
  //       if (andClause != null) allClauses.add(andClause);
  //     }

  //     if (hasOr) {
  //       final orClause = buildGroup('or', node['or']);
  //       if (orClause != null) allClauses.add(orClause);
  //     }

  //     if (allClauses.isEmpty) return null;
  //     if (allClauses.length == 1) return allClauses.first;
  //     return 'and(${allClauses.join(',')})';
  //   }

  //   void applyAndNode(dynamic node) {
  //     if (node is! Map) return;

  //     final hasField = node['field'] != null && node['ope'] != null;
  //     final hasAnd = node['and'] is List;
  //     final hasOr = node['or'] is List;

  //     if (hasField && !hasAnd && !hasOr) {
  //       final field = node['field'];
  //       final op = node['ope'];
  //       final value = resolveValue(node['value'], false);
  //       if (value != null && value.toString().isNotEmpty) {
  //         q = q.filter('json->>$field', op, value);
  //       } else {
  //         q = q.filter('id', 'gte', 0); // toujours true
  //       }
  //       return;
  //     }

  //     if (hasAnd) {
  //       for (final child in node['and']) {
  //         applyAndNode(child);
  //       }
  //     }

  //     if (hasOr) {
  //       final orClause = buildLogicClause({'or': node['or']});
  //       if (orClause != null && orClause.isNotEmpty) {
  //         if (orClause.startsWith('or(') && orClause.endsWith(')')) {
  //           q = q.or(orClause.substring(3, orClause.length - 1));
  //         } else {
  //           q = q.or(orClause);
  //         }
  //       }
  //     }
  //   }

  //   /**  
  //   where :
  //   - or :
  //        - field : value
  //          ope : eq              
  //          value : "{{value}}"          
  //        - and :                  
  //         - field : test
  //           ope : eq
  //           value : toto          
  //   */

  //   for (final whereNode in callerDatasource.where ?? []) {
  //     applyAndNode(whereNode);
  //   }

  //   PostgrestTransformBuilder? qs;
  //   for (Map sortNode in callerDatasource.sort ?? []) {
  //     var k = sortNode.keys.first;
  //     var s = sortNode.values.first;
  //     if (qs == null) {
  //       qs = q.order('json->>$k', ascending: s == 'asc');
  //     } else {
  //       qs = qs.order('json->>$k', ascending: s == 'asc');
  //     }
  //   }

  //   var ret = await (qs ?? q);

  //   List<Map<String, dynamic>> result = ret.map<Map<String, dynamic>>((e) {
  //     Map<String, dynamic> r = e['json'];
  //     r[cstStorage] = {};
  //     r[cstStorage]['id'] = e['id'];
  //     r[cstStorage]['updated_at'] = e['updated_at'];
  //     return r;
  //   }).toList();

  //   if (callerDatasource.dsConfig.data.rowsVariable != null) {
  //     result = <Map<String, dynamic>>[
  //       <String, dynamic>{
  //         callerDatasource.dsConfig.data.rowsVariable!: result,
  //         // wrap the list in a map with the specified variable name
  //       },
  //     ];
  //   }
  //   return result;
  // }

  // Future<Map<String, dynamic>> callDeleteUserApi({String? userId}) async {
  //   await ensureSessionValid();

  //   final session = supabase.auth.currentSession;
  //   if (session == null) {
  //     return <String, dynamic>{'message': 'No active session', 'status': 401};
  //   }

  //   final payload = <String, dynamic>{'confirm': true};
  //   if (userId != null && userId.trim().isNotEmpty) {
  //     payload['user_id'] = userId.trim();
  //   }

  //   final response = await supabase.functions.invoke(
  //     'delete-user',
  //     method: HttpMethod.post,
  //     body: payload,
  //     headers: <String, String>{
  //       'Authorization': 'Bearer ${session.accessToken}',
  //     },
  //   );

  //   final data = response.data;
  //   if (data is Map) {
  //     return Map<String, dynamic>.from(data);
  //   }

  //   return <String, dynamic>{
  //     'message': data?.toString() ?? 'No data',
  //     'status': response.status,
  //   };
  // }
}

//--------------------------------------------------------------------------

class StoreManager {
  Debouncer debouncer = Debouncer(milliseconds: 3000);
  Map<String, SaveEvent> toStore = {};
  void add(SaveEvent event) {
    toStore[event.idIdempotence] = event;
    event.sortIdx = toStore.length;
    debouncer.run(() {
      bddStorage.doStoreSync();
    });
  }
}

class Debouncer {
  final int milliseconds;
  Timer? _timer;
  Debouncer({required this.milliseconds});

  void run(VoidCallback action) {
    if (_timer != null) {
      _timer!.cancel();
    }
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  void dispose() {
    _timer?.cancel();
  }
}

class CacheValue {
  int time = 0;
  dynamic value;
}

//postgre pw = alPMsV1bPKgs10v4
