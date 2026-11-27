/// Bibliothèque publique du package `super_backend_editor`.
///
/// Expose les modèles immuables de la spécification Design importée
/// ([DomainDesignSpec]), de la surcouche d'implémentation Backend
/// ([BackendOverlayConfig]), des rapports de diff incrémentaux
/// ([DomainDesignDiff]), de l'audit de cohérence ([BackendCoherenceIssue]),
/// du projet de domaine ([BackendDomainProject]) et du magasin de persistance
/// atomique ([BackendWorkspaceStore]).
library;

export 'models/backend_coherence_issue.dart';
export 'models/backend_domain_project.dart';
export 'models/backend_overlay_config.dart';
export 'models/domain_design_diff.dart';
export 'models/domain_design_spec.dart';
export 'services/backend_workspace_store.dart';
