import 'package:fuzzy/data/result.dart';
import 'package:fuzzy/fuzzy.dart';
import 'package:super_container_layout/widgets/components/treeview/json_browser.dart';
import 'package:super_container_layout/widgets/components/treeview/model_schema.dart';

final CompanyModelSchema currentCompany = CompanyModelSchema();

class ProposalInfo {
  final String name;
  final Map<String, dynamic>? properties;
  final String model;
  final String domain;
  final String path;

  ProposalInfo({
    required this.name,
    this.properties,
    required this.model,
    required this.domain,
    required this.path,
  });
}

class CompanyModelSchema {
  bool isInit = false;
  //List<String> log = [];

  ModelSchema? listEnv;
  ModelSchema? listDomain;
  ModelSchema? listDataSrc;

  ModelSchema? listModel;
  ModelSchema? listAsync;
  ModelSchema? currentModel;
  NodeAttribut? currentModelSel;
  String? currentType;

  ModelSchema? listAPI;
  ModelSchema? currentAPIResquest;
  ModelSchema? currentAPIResponse;

  ModelSchema? currentDataSource;
  ModelSchema? currentDataMap;
  NodeAttribut? currentDataMapSel;

  late ModelSchema listGlossary;
  late ModelSchema listGlossarySuffixPrefix;
  ModelSchema? currentApps;
  ModelSchema? currentFlow;
  ModelSchema? currentAPM;
  ModelSchema? currentTechno;

  ModelSchema? currentUseCaseSchema;

  //MappingEngineConfig? currentMapEngine;
  //GlossaryManager glossaryManager = GlossaryManager();

  String companyId = '?';
  String shortUserId = '?';

  //User? user;
  Map? userProfil;
  Map userAuth = {};

  Set fuseSet = {};
  Fuzzy<ProposalInfo>? fuse;

  FuzzyOptions<ProposalInfo> getOptionFuse() {
    return FuzzyOptions(
      tokenize: true,
      shouldSort: true,
      shouldNormalize: true,
      keys: [
        WeightedKey(
          name: "name",
          getter: (ProposalInfo obj) {
            return obj.name;
          },
          weight: 1.0,
        ),
        WeightedKey(
          name: "title",
          getter: (ProposalInfo obj) {
            return obj.properties?['title'] ?? '';
          },
          weight: 0.8,
        ),
        WeightedKey(
          name: "description",
          getter: (ProposalInfo obj) {
            return obj.properties?['description'] ?? '';
          },
          weight: 0.6,
        ),
      ],
    );
  }

  bool isSearchFuse = false;

  List<Result<ProposalInfo>> searchProposal(NodeAttribut attr) {
    if (currentCompany.fuse == null) {
      return [];
    }
    final result = currentCompany.fuse!.search(attr.info.name, 5);
    isSearchFuse = true;
    return result;
  }

  final Map<String, List<AttributInfo>> copiedMapInfoByName = {};

  Map? getRule(String category, String authId) {
    return userAuth[category]?[authId];
  }

  void addProposal(ModelSchema model, AttributInfo attr) {
    String key = attr.getMasterID();

    Map<String, dynamic> hasProp = {...attr.properties ?? {}};
    hasProp.removeWhere((key, value) {
      return key.startsWith('\$') ||
          key.startsWith('#') ||
          value == null ||
          (value is String && value.isEmpty);
    });

    if (!fuseSet.contains(key) && hasProp.isNotEmpty) {
      if (isSearchFuse || fuse == null) {
        isSearchFuse = false;
        fuse = Fuzzy<ProposalInfo>(fuse?.list ?? [], options: getOptionFuse());
      }

      fuseSet.add(key);
      var proposalInfo = ProposalInfo(
        name: attr.name,
        path: attr.getJsonPath(sep: '.', withRoot: false),
        properties: hasProp,
        model: model.headerName,
        domain: currentCompany.listDomain?.selectedAttr?.info.name ?? '',
      );
      currentCompany.fuse!.list.add(proposalInfo);
    }
  }

  String get currentNameSpace {
    if (isInit && listDomain?.selectedAttr != null) {
      return listDomain!.selectedAttr!.info.masterID!;
    }
    return 'default';
  }

  // Future<ModelSchema?> getModelByMasterId(
  //   String idDomain,
  //   String idModel,
  // ) async {
  //   var listModel = await loadSchema(
  //     TypeMD.listmodel,
  //     'model',
  //     'Business models',
  //     TypeModelBreadcrumb.businessmodel,
  //     namespace: idDomain,
  //     config: BrowserConfig(),
  //   );
  //   var m = listModel.getNodeByMasterIdPath(idModel);
  //   if (m != null) {
  //     var aModel = ModelSchema(
  //       category: Category.model,
  //       infoManager: InfoManagerModel(typeMD: TypeMD.model),
  //       headerName: m.info.name,
  //       id: idModel,
  //       refDomain: listModel,
  //     );
  //     aModel.namespace = idDomain;
  //     await aModel.loadYamlAndProperties(cache: false, withProperties: true);
  //     //print(m);
  //     return aModel;
  //   }

  //   return null;
  // }

  // Future<ModelSchema?> getModelByName(String idDomain, String idModel) async {
  //   var aDomain = currentCompany.listDomain?.mapInfoByName[idDomain];
  //   var attr = aDomain?.firstOrNull;
  //   if (attr != null) {
  //     var listModel = await loadSchema(
  //       TypeMD.listmodel,
  //       'model',
  //       'Business models',
  //       TypeModelBreadcrumb.businessmodel,
  //       namespace: attr.masterID!,
  //       config: BrowserConfig(),
  //     );
  //     var m = listModel.mapInfoByName[idModel]?.first;
  //     if (m != null) {
  //       var aModel = ModelSchema(
  //         category: Category.model,
  //         infoManager: InfoManagerModel(typeMD: TypeMD.model),
  //         headerName: m.name,
  //         id: m.masterID!,
  //         refDomain: listModel,
  //       );
  //       aModel.namespace = attr.masterID!;
  //       await aModel.loadYamlAndProperties(cache: false, withProperties: true);
  //       //print(m);
  //       return aModel;
  //     }
  //   }

  //   return null;
  // }

  // void setDomainByMasterID(String? currentDomain, {BrowseSingle? browser}) {
  //   if (browser == null) {
  //     browser = BrowseSingle(config: BrowserConfig());
  //     browser.browse(currentCompany.listDomain!, false);
  //   }

  //   if (currentDomain == null) {
  //     currentCompany.listDomain?.setCurrentAttr(browser.root.first.info);
  //     prefs.setString("currentDomain", browser.root.first.info.masterID!);
  //   } else {
  //     var cur = browser.root.firstWhereOrNull(
  //       (element) => element.info.masterID == currentDomain,
  //     );
  //     if (cur == null) {
  //       currentCompany.listDomain?.setCurrentAttr(browser.root.first.info);
  //     } else {
  //       currentCompany.listDomain?.setCurrentAttr(cur.info);
  //     }
  //   }
  // }
}

///////////////////////////////////////////////////////////////////
///
enum ChangeOpe { change, clear, rename, path, move, add, remove }

enum Category {
  allModel,
  model,
  selector,
  allApi,
  api,
  allGlossary,
  exampleApi,
  env,
  domain,
  variable,
  dataMap,
  apps,
  asyncApi,
  appflow,
  apm,
  behavior,
  skills
}
