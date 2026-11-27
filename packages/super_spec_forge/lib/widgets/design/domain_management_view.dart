/// Interface de gouvernance des domaines, environnements, microservices et
/// configurations du workspace ([DomainManagementView]).
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/domain_catalog.dart';
import '../../services/domain_env_exporter.dart';
import '../../services/domain_secret_cipher.dart';
import '../../services/spec_forge_controller.dart';

/// Vue de gestion des domaines fonctionnels depuis le menu Design.
class DomainManagementView extends StatefulWidget {
  /// Crée la vue connectée au [controller].
  const DomainManagementView({
    required this.controller,
    this.onDomainSelected,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Signale au shell le domaine affiché dans le panneau de détail.
  final ValueChanged<String?>? onDomainSelected;

  @override
  State<DomainManagementView> createState() => _DomainManagementViewState();
}

class _DomainManagementViewState extends State<DomainManagementView> {
  String? _selectedDomainId;
  final DomainSecretCipher _cipher = DomainSecretCipher();

  void _selectDomain(String? id) {
    setState(() => _selectedDomainId = id);
    widget.controller.setActiveDesignDomainId(id);
    widget.onDomainSelected?.call(id);
  }

  Future<void> _saveCatalog(DomainCatalog next) async {
    try {
      await widget.controller.updateDomainCatalog(next);
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Impossible d’enregistrer le catalogue : $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  AuditLogEntry _audit(
    String domainId, {
    required DomainAuditAction action,
    String? environmentId,
    String? targetKey,
    bool isSecret = false,
    required String details,
  }) => AuditLogEntry(
    id: 'audit_${shortid.generate()}',
    recordedAt: DateTime.now().toUtc(),
    actorUsername: 'local-user',
    domainId: domainId,
    environmentId: environmentId,
    actionType: action,
    targetKey: targetKey,
    isSecret: isSecret,
    details: details,
  );

  DomainCatalog _withAudit(DomainCatalog catalog, AuditLogEntry event) =>
      catalog.copyWith(
        auditLog: [...catalog.auditLog, event],
        updatedAt: event.recordedAt,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      key: const ValueKey('domain-management-view'),
      listenable: widget.controller,
      builder: (context, _) {
        final catalog = widget.controller.domainCatalog;
        final selected = catalog.domains
            .where((domain) => domain.id == _selectedDomainId)
            .firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, catalog),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 390,
                    child: _buildDomainList(context, catalog, selected),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: selected == null
                        ? _buildEmptySelection(context, catalog)
                        : _buildDomainDetails(context, catalog, selected),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, DomainCatalog catalog) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.domain_rounded, size: 22, color: colors.primary),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gestion des domaines',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${catalog.domains.length} domaine(s) · '
                    '${catalog.environments.length} environnement(s) · '
                    '${catalog.microservices.length} microservice(s)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Text(
            'Catalogue local au workspace',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDomainList(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain? selected,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerLow.withValues(alpha: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Domaines',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: const ValueKey('domain-management-add-domain-btn'),
                  tooltip: 'Nouveau domaine',
                  onPressed: () => _editDomain(context),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: catalog.domains.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Aucun domaine déclaré.\nAjoutez votre premier domaine fonctionnel.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      for (final domain in catalog.domains)
                        _domainListTile(context, catalog, domain, selected),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              key: const ValueKey('domain-management-add-domain-wide-btn'),
              onPressed: () => _editDomain(context),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Nouveau domaine'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _domainListTile(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
    FunctionalDomain? selected,
  ) {
    final environmentCount = catalog.environments
        .where((item) => item.domainId == domain.id)
        .length;
    final serviceCount = catalog.microservices
        .where((item) => item.domainId == domain.id)
        .length;
    final active = selected?.id == domain.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          key: ValueKey('domain-item-${domain.id}'),
          selected: active,
          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          onTap: () => _selectDomain(domain.id),
          title: Text(
            domain.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${domain.domainCode} · $environmentCount env. · $serviceCount svc.'
            '${domain.isActive ? '' : ' · inactif'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          leading: Icon(
            domain.isActive
                ? Icons.domain_rounded
                : Icons.domain_disabled_rounded,
            size: 20,
          ),
          trailing: IconButton(
            tooltip: 'Modifier ${domain.name}',
            onPressed: () => _editDomain(context, existing: domain),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySelection(BuildContext context, DomainCatalog catalog) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub_outlined, size: 42, color: colors.outline),
          const SizedBox(height: 12),
          Text(
            catalog.domains.isEmpty ? 'Créez un domaine pour commencer.' : 'Sélectionnez un domaine pour gérer ses environnements et services.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDomainDetails(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
  ) {
    final colors = Theme.of(context).colorScheme;
    final environmentCount = catalog.environments
        .where((item) => item.domainId == domain.id)
        .length;
    final serviceCount = catalog.microservices
        .where((item) => item.domainId == domain.id)
        .length;
    final techStack = catalog.techStackForDomain(domain);
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      domain.name,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${domain.domainCode} · $environmentCount environnement(s) · '
                      '$serviceCount microservice(s)'
                      '${techStack == null ? '' : ' · Stack : ${techStack.name}'}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    if (domain.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(domain.description),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    FilterChip(
                      key: const ValueKey('domain-management-active-chip'),
                      label: Text(domain.isActive ? 'Actif' : 'Inactif'),
                      selected: domain.isActive,
                      onSelected: (active) => _updateDomain(
                        catalog,
                        domain.copyWith(isActive: active),
                        DomainAuditAction.update,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Modifier le domaine',
                      onPressed: () => _editDomain(context, existing: domain),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Supprimer le domaine',
                      onPressed: () => _deleteDomain(context, catalog, domain),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(
                key: ValueKey('domain-tab-environments'),
                text: 'Environnements',
              ),
              Tab(key: ValueKey('domain-tab-services'), text: 'Microservices'),
              Tab(key: ValueKey('domain-tab-audit'), text: 'Audit'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildEnvironments(context, catalog, domain),
                _buildMicroservices(context, catalog, domain),
                _buildAudit(context, catalog, domain),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvironments(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
  ) {
    final environments =
        catalog.environments
            .where((item) => item.domainId == domain.id)
            .toList()
          ..sort((a, b) => a.environmentCode.compareTo(b.environmentCode));
    return ListView(
      key: const ValueKey('domain-environments-list'),
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const ValueKey('domain-add-environment-btn'),
            onPressed: () => _editEnvironment(context, catalog, domain),
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('Créer un environnement'),
          ),
        ),
        const SizedBox(height: 10),
        if (environments.isEmpty)
          const _DomainEmptyCard(
            message: 'Aucun environnement. Créez dev, recette, prod ou un environnement éphémère.',
          ),
        for (final environment in environments)
          _environmentCard(context, catalog, domain, environment),
      ],
    );
  }

  Widget _environmentCard(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
    LogicalEnvironment environment,
  ) {
    final entries =
        catalog.configurationEntries
            .where((entry) => entry.environmentId == environment.id)
            .toList()
          ..sort((a, b) => a.configKey.compareTo(b.configKey));
    final services = catalog.microservices
        .where((service) => service.domainId == domain.id)
        .toList();
    final archived = environment.status == LogicalEnvironmentStatus.archived;
    final uninitialized = entries
        .where(
          (entry) =>
              entry.entryType == ConfigurationEntryType.secret &&
              !entry.isInitialized,
        )
        .length;
    return Card(
      key: ValueKey('domain-environment-${environment.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      archived ? Icons.archive_outlined : Icons.layers_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          environment.name,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${environment.environmentCode} · ${environment.status.name}'
                          '${environment.isCloned ? ' · cloné' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
                Wrap(
                  spacing: 2,
                  children: [
                    IconButton(
                      tooltip: 'Ajouter une variable ou un secret',
                      onPressed: archived
                          ? null
                          : () => _editConfiguration(
                              context,
                              catalog,
                              domain,
                              environment,
                              services,
                            ),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                    IconButton(
                      tooltip: 'Cloner cet environnement',
                      onPressed: () => _cloneEnvironment(
                        context,
                        catalog,
                        domain,
                        environment,
                      ),
                      icon: const Icon(Icons.copy_all_outlined),
                    ),
                    IconButton(
                      tooltip: 'Exporter .env',
                      onPressed: () =>
                          _showEnvExport(context, entries, environment),
                      icon: const Icon(Icons.download_outlined),
                    ),
                    IconButton(
                      tooltip: 'Modifier l’environnement',
                      onPressed: archived
                          ? null
                          : () => _editEnvironment(
                              context,
                              catalog,
                              domain,
                              existing: environment,
                            ),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Supprimer l’environnement',
                      onPressed: () => _deleteEnvironment(
                        context,
                        catalog,
                        domain,
                        environment,
                        entries.length,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ],
            ),
            if (environment.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(environment.description),
              ),
            if (uninitialized > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Chip(
                  avatar: const Icon(Icons.warning_amber_rounded, size: 17),
                  label: Text('$uninitialized secret(s) à initialiser'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            const Divider(height: 20),
            if (entries.isEmpty)
              Text(
                'Aucune variable de configuration.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              for (final entry in entries)
                _configurationTile(
                  context,
                  catalog,
                  domain,
                  environment,
                  entry,
                  services,
                  readOnly: archived,
                ),
          ],
        ),
      ),
    );
  }

  Widget _configurationTile(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
    LogicalEnvironment environment,
    ConfigurationEntry entry,
    List<Microservice> services, {
    required bool readOnly,
  }) {
    final scopedService = services
        .where((service) => service.id == entry.microserviceId)
        .firstOrNull;
    final isSecret = entry.entryType == ConfigurationEntryType.secret;
    return ListTile(
      key: ValueKey('domain-config-${entry.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isSecret ? Icons.key_outlined : Icons.tune_rounded,
        size: 19,
      ),
      title: Text(entry.configKey),
      subtitle: Text(
        '${isSecret ? (entry.isInitialized ? '••••••••' : 'À initialiser') : entry.plainValue}'
        '${scopedService != null ? ' · ${scopedService.serviceCode}' : ''}'
        '${entry.description.isNotEmpty ? ' · ${entry.description}' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: readOnly
          ? null
          : Wrap(
              spacing: 0,
              children: [
                IconButton(
                  tooltip: 'Modifier ${entry.configKey}',
                  onPressed: () => _editConfiguration(
                    context,
                    catalog,
                    domain,
                    environment,
                    services,
                    existing: entry,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: 'Supprimer ${entry.configKey}',
                  onPressed: () => _deleteConfiguration(
                    context,
                    catalog,
                    domain,
                    environment,
                    entry,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                ),
              ],
            ),
    );
  }

  Widget _buildMicroservices(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
  ) {
    final services =
        catalog.microservices
            .where((item) => item.domainId == domain.id)
            .toList()
          ..sort((a, b) => a.serviceCode.compareTo(b.serviceCode));
    return ListView(
      key: const ValueKey('domain-microservices-list'),
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const ValueKey('domain-add-microservice-btn'),
            onPressed: () => _editMicroservice(context, catalog, domain),
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('Ajouter un microservice'),
          ),
        ),
        const SizedBox(height: 10),
        if (services.isEmpty)
          const _DomainEmptyCard(
            message: 'Aucun microservice inventorié pour ce domaine.',
          ),
        for (final service in services)
          Card(
            key: ValueKey('domain-microservice-${service.id}'),
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.apps_rounded),
              title: Text(service.name),
              subtitle: Text(
                '${service.serviceCode} · ${service.kind.shortLabel}'
                '${service.vendor.isNotEmpty ? ' (${service.vendor})' : ''}'
                '${service.description.isNotEmpty ? ' · ${service.description}' : ''}'
                '${service.isActive ? '' : ' · inactif'}',
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Modifier ${service.name}',
                    onPressed: () => _editMicroservice(
                      context,
                      catalog,
                      domain,
                      existing: service,
                    ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Supprimer ${service.name}',
                    onPressed: () =>
                        _deleteMicroservice(context, catalog, domain, service),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAudit(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
  ) {
    final events =
        catalog.auditLog.where((event) => event.domainId == domain.id).toList()
          ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return ListView(
      key: const ValueKey('domain-audit-list'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Journal local en lecture seule. Les valeurs des secrets ne sont jamais journalisées.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        if (events.isEmpty)
          const _DomainEmptyCard(message: 'Aucun événement pour ce domaine.'),
        for (final event in events)
          ListTile(
            leading: Icon(
              event.isSecret ? Icons.key_outlined : Icons.history_rounded,
            ),
            title: Text(
              '${event.actionType.name} · ${event.targetKey ?? 'domaine/environnement'}',
            ),
            subtitle: Text(
              '${event.recordedAt.toLocal()} · ${event.actorUsername} · ${event.details}',
            ),
          ),
      ],
    );
  }

  Future<void> _editDomain(
    BuildContext context, {
    FunctionalDomain? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final code = TextEditingController(text: existing?.domainCode ?? '');
    final name = TextEditingController(text: existing?.name ?? '');
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    final active = ValueNotifier<bool>(existing?.isActive ?? true);
    final availableStacks = widget.controller.domainCatalog.techStacks;
    final selectedStackId = ValueNotifier<String?>(
      existing == null
          ? availableStacks.firstOrNull?.id
          : (availableStacks.any((s) => s.id == existing.techStackId)
                ? existing.techStackId
                : null),
    );
    final result = await showDialog<FunctionalDomain>(
      context: context,
      builder: (dialogContext) => _DialogDisposalScope(
        disposables: [code, name, description, active, selectedStackId],
        child: AlertDialog(
          title: Text(
            existing == null ? 'Nouveau domaine' : 'Modifier le domaine',
          ),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: ListView(
                shrinkWrap: true,
                children: [
                  TextFormField(
                    key: const ValueKey('domain-code-field'),
                    controller: code,
                    decoration: const InputDecoration(
                      labelText: 'Code canonique',
                      hintText: 'billing-domain',
                      helperText: 'kebab-case, 2 à 64 caractères',
                    ),
                    validator: (value) => _validateCode(value, 'domaine'),
                  ),
                  TextFormField(
                    key: const ValueKey('domain-name-field'),
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nom'),
                    validator: (value) => (value?.trim().length ?? 0) < 2
                        ? 'Nom requis (2 caractères minimum).'
                        : null,
                  ),
                  TextFormField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description métier',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String?>(
                    valueListenable: selectedStackId,
                    builder: (context, value, _) =>
                        DropdownButtonFormField<String?>(
                          key: const ValueKey('domain-tech-stack-field'),
                          isExpanded: true,
                          initialValue: value,
                          decoration: const InputDecoration(
                            labelText: 'Stack technique (prompts Build)',
                            icon: Icon(Icons.layers_rounded),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'Aucune stack',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            for (final stack in availableStacks)
                              DropdownMenuItem<String?>(
                                value: stack.id,
                                child: Text(
                                  '${stack.name} (${stack.code})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (next) => selectedStackId.value = next,
                        ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: active,
                    builder: (context, value, _) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Domaine actif'),
                      value: value,
                      onChanged: (next) => active.value = next,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('domain-save-btn'),
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final duplicate = widget.controller.domainCatalog.domains.any(
                  (item) =>
                      item.domainCode == code.text.trim() &&
                      item.id != existing?.id,
                );
                if (duplicate) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Ce code de domaine existe déjà.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  FunctionalDomain(
                    id: existing?.id ?? 'domain_${shortid.generate()}',
                    domainCode: code.text.trim(),
                    name: name.text.trim(),
                    description: description.text.trim(),
                    isActive: active.value,
                    techStackId: selectedStackId.value,
                    contracts: existing?.contracts,
                    useCaseOrchestration: existing?.useCaseOrchestration,
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final catalog = widget.controller.domainCatalog;
    await _updateDomain(
      catalog,
      result,
      existing == null ? DomainAuditAction.create : DomainAuditAction.update,
    );
    if (existing == null && mounted) {
      _selectDomain(result.id);
    }
  }

  Future<void> _updateDomain(
    DomainCatalog catalog,
    FunctionalDomain domain,
    DomainAuditAction action,
  ) async {
    final now = DateTime.now().toUtc();
    final next = catalog.copyWith(
      domains: [
        for (final item in catalog.domains)
          if (item.id == domain.id) domain else item,
        if (!catalog.domains.any((item) => item.id == domain.id)) domain,
      ],
    );
    await _saveCatalog(
      _withAudit(
        next,
        _audit(
          domain.id,
          action: action,
          details: action == DomainAuditAction.create
              ? 'Domaine créé.'
              : 'Domaine modifié.',
        ),
      ).copyWith(updatedAt: now),
    );
  }

  Future<void> _deleteDomain(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
  ) async {
    final environments = catalog.environments
        .where((item) => item.domainId == domain.id)
        .length;
    final services = catalog.microservices
        .where((item) => item.domainId == domain.id)
        .length;
    if (environments + services > 0) {
      _notice(
        'Suppression impossible : $environments environnement(s) et $services microservice(s) sont encore rattachés.',
      );
      return;
    }
    if (!await _confirm(context, 'Supprimer le domaine « ${domain.name} » ?')) {
      return;
    }
    final next = catalog.copyWith(
      domains: catalog.domains.where((item) => item.id != domain.id).toList(),
      auditLog: [
        ...catalog.auditLog,
        _audit(
          domain.id,
          action: DomainAuditAction.delete,
          details: 'Domaine supprimé.',
        ),
      ],
      updatedAt: DateTime.now().toUtc(),
    );
    await _saveCatalog(next);
    if (mounted) _selectDomain(null);
  }

  Future<void> _editEnvironment(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain, {
    LogicalEnvironment? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final code = TextEditingController(text: existing?.environmentCode ?? '');
    final name = TextEditingController(text: existing?.name ?? '');
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    var status = existing?.status ?? LogicalEnvironmentStatus.active;
    final result = await showDialog<LogicalEnvironment>(
      context: context,
      builder: (dialogContext) => _DialogDisposalScope(
        disposables: [code, name, description],
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              existing == null
                  ? 'Créer un environnement'
                  : 'Modifier l’environnement',
            ),
            content: SizedBox(
              width: 440,
              child: Form(
                key: formKey,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    TextFormField(
                      key: const ValueKey('environment-code-field'),
                      controller: code,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        hintText: 'review-pr-12',
                        helperText: 'kebab-case, unique dans le domaine',
                      ),
                      validator: (value) =>
                          _validateCode(value, 'environnement'),
                    ),
                    TextFormField(
                      key: const ValueKey('environment-name-field'),
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Nom'),
                      validator: (value) => (value?.trim().length ?? 0) < 2
                          ? 'Nom requis (2 caractères minimum).'
                          : null,
                    ),
                    TextFormField(
                      controller: description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    DropdownButtonFormField<LogicalEnvironmentStatus>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Statut'),
                      items: [
                        for (final item in LogicalEnvironmentStatus.values)
                          DropdownMenuItem(value: item, child: Text(item.name)),
                      ],
                      onChanged: (value) {
                        if (value != null) setDialogState(() => status = value);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler'),
              ),
              FilledButton(
                key: const ValueKey('environment-save-btn'),
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final duplicate = widget.controller.domainCatalog.environments
                      .any(
                        (item) =>
                            item.domainId == domain.id &&
                            item.environmentCode == code.text.trim() &&
                            item.id != existing?.id,
                      );
                  if (duplicate) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Ce code existe déjà dans ce domaine.'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    LogicalEnvironment(
                      id: existing?.id ?? 'env_${shortid.generate()}',
                      domainId: domain.id,
                      environmentCode: code.text.trim(),
                      name: name.text.trim(),
                      description: description.text.trim(),
                      status: status,
                      isCloned: existing?.isCloned ?? false,
                      sourceEnvironmentId: existing?.sourceEnvironmentId,
                    ),
                  );
                },
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final current = widget.controller.domainCatalog;
    final exists = current.environments.any((item) => item.id == result.id);
    final next = current.copyWith(
      environments: [
        for (final item in current.environments)
          if (item.id == result.id) result else item,
        if (!exists) result,
      ],
    );
    await _saveCatalog(
      _withAudit(
        next,
        _audit(
          domain.id,
          action: exists ? DomainAuditAction.update : DomainAuditAction.create,
          environmentId: result.id,
          details: exists ? 'Environnement modifié.' : 'Environnement créé.',
        ),
      ),
    );
  }

  Future<void> _deleteEnvironment(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
    LogicalEnvironment environment,
    int configurationCount,
  ) async {
    final cloneCount = catalog.environments
        .where((item) => item.sourceEnvironmentId == environment.id)
        .length;
    if (configurationCount > 0 || cloneCount > 0) {
      _notice(
        'Suppression impossible : $configurationCount entrée(s) de configuration et $cloneCount clone(s) dépendent encore de cet environnement.',
      );
      return;
    }
    if (!await _confirm(
      context,
      'Supprimer l’environnement « ${environment.name} » ?',
    )) {
      return;
    }
    final next = catalog.copyWith(
      environments: catalog.environments
          .where((item) => item.id != environment.id)
          .toList(),
      auditLog: [
        ...catalog.auditLog,
        _audit(
          domain.id,
          action: DomainAuditAction.delete,
          environmentId: environment.id,
          details: 'Environnement supprimé.',
        ),
      ],
      updatedAt: DateTime.now().toUtc(),
    );
    await _saveCatalog(next);
  }

  Future<void> _cloneEnvironment(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
    LogicalEnvironment source,
  ) async {
    final formKey = GlobalKey<FormState>();
    final code = TextEditingController();
    final name = TextEditingController();
    final result = await showDialog<({String code, String name})>(
      context: context,
      builder: (dialogContext) => _DialogDisposalScope(
        disposables: [code, name],
        child: AlertDialog(
          title: Text('Cloner ${source.name}'),
          content: SizedBox(
            width: 380,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: code,
                    decoration: const InputDecoration(
                      labelText: 'Code cible',
                      hintText: 'feature-auth',
                    ),
                    validator: (value) => _validateCode(value, 'environnement'),
                  ),
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nom cible'),
                    validator: (value) =>
                        (value?.trim().length ?? 0) < 2 ? 'Nom requis.' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('environment-clone-confirm-btn'),
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final duplicate = widget.controller.domainCatalog.environments
                    .any(
                      (item) =>
                          item.domainId == domain.id &&
                          item.environmentCode == code.text.trim(),
                    );
                if (duplicate) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Ce code existe déjà dans ce domaine.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, (
                  code: code.text.trim(),
                  name: name.text.trim(),
                ));
              },
              child: const Text('Cloner'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final current = widget.controller.domainCatalog;
    final cloneId = 'env_${shortid.generate()}';
    final clone = LogicalEnvironment(
      id: cloneId,
      domainId: domain.id,
      environmentCode: result.code,
      name: result.name,
      description: 'Cloné depuis ${source.environmentCode}.',
      isCloned: true,
      sourceEnvironmentId: source.id,
    );
    final clonedEntries = [
      for (final entry in current.configurationEntries.where(
        (item) => item.environmentId == source.id,
      ))
        ConfigurationEntry(
          id: 'config_${shortid.generate()}',
          domainId: entry.domainId,
          environmentId: cloneId,
          microserviceId: entry.microserviceId,
          configKey: entry.configKey,
          entryType: entry.entryType,
          plainValue: entry.entryType == ConfigurationEntryType.plainVariable
              ? entry.plainValue
              : null,
          isInitialized:
              entry.entryType == ConfigurationEntryType.plainVariable,
          description: entry.description,
        ),
    ];
    await _saveCatalog(
      _withAudit(
        current.copyWith(
          environments: [...current.environments, clone],
          configurationEntries: [
            ...current.configurationEntries,
            ...clonedEntries,
          ],
        ),
        _audit(
          domain.id,
          action: DomainAuditAction.clone,
          environmentId: cloneId,
          details:
              'Clonage de ${source.environmentCode} ; ${clonedEntries.where((item) => item.entryType == ConfigurationEntryType.secret).length} secret(s) à réinitialiser.',
        ),
      ),
    );
  }

  Future<void> _editMicroservice(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain, {
    Microservice? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final code = TextEditingController(text: existing?.serviceCode ?? '');
    final name = TextEditingController(text: existing?.name ?? '');
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    var selectedKind = existing?.kind ?? DomainSystemKind.microservice;
    final result = await showDialog<Microservice>(
      context: context,
      builder: (dialogContext) => _DialogDisposalScope(
        disposables: [code, name, description],
        child: StatefulBuilder(
          builder: (dialogContext, setLocal) => AlertDialog(
            title: Text(
              existing == null
                  ? 'Nouveau système ou service'
                  : 'Modifier le système / service',
            ),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<DomainSystemKind>(
                      initialValue: selectedKind,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Catégorie',
                      ),
                      items: [
                        for (final kind in DomainSystemKind.values)
                          DropdownMenuItem(
                            value: kind,
                            child: Text(
                              kind.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setLocal(() => selectedKind = v);
                      },
                    ),
                    TextFormField(
                      controller: code,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        hintText: 'order-api',
                      ),
                      validator: (value) => _validateCode(value, 'microservice'),
                    ),
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Nom'),
                      validator: (value) =>
                          (value?.trim().length ?? 0) < 2 ? 'Nom requis.' : null,
                    ),
                    TextFormField(
                      controller: description,
                      decoration: const InputDecoration(labelText: 'Description'),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler'),
              ),
              FilledButton(
                key: const ValueKey('microservice-save-btn'),
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final duplicate = widget.controller.domainCatalog.microservices
                      .any(
                        (item) =>
                            item.domainId == domain.id &&
                            item.serviceCode == code.text.trim() &&
                            item.id != existing?.id,
                      );
                  if (duplicate) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Ce code existe déjà.')),
                    );
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    Microservice(
                      id: existing?.id ?? 'service_${shortid.generate()}',
                      domainId: domain.id,
                      serviceCode: code.text.trim(),
                      name: name.text.trim(),
                      kind: selectedKind,
                      description: description.text.trim(),
                      isActive: existing?.isActive ?? true,
                      techStackId: selectedKind.isOffTheShelf
                          ? null
                          : existing?.techStackId,
                      vendor: existing?.vendor ?? '',
                    ),
                  );
                },
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final current = widget.controller.domainCatalog;
    final exists = current.microservices.any((item) => item.id == result.id);
    final next = current.copyWith(
      microservices: [
        for (final item in current.microservices)
          if (item.id == result.id) result else item,
        if (!exists) result,
      ],
    );
    await _saveCatalog(
      _withAudit(
        next,
        _audit(
          domain.id,
          action: exists ? DomainAuditAction.update : DomainAuditAction.create,
          details: exists ? 'Microservice modifié.' : 'Microservice créé.',
        ),
      ),
    );
  }

  Future<void> _deleteMicroservice(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
    Microservice service,
  ) async {
    final assigned = catalog.configurationEntries
        .where((entry) => entry.microserviceId == service.id)
        .length;
    if (assigned > 0) {
      _notice(
        'Suppression impossible : $assigned entrée(s) de configuration ciblent ce microservice.',
      );
      return;
    }
    if (!await _confirm(context, 'Supprimer « ${service.name} » ?')) return;
    await _saveCatalog(
      _withAudit(
        catalog.copyWith(
          microservices: catalog.microservices
              .where((item) => item.id != service.id)
              .toList(),
        ),
        _audit(
          domain.id,
          action: DomainAuditAction.delete,
          details: 'Microservice supprimé.',
        ),
      ),
    );
  }

  Future<void> _editConfiguration(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
    LogicalEnvironment environment,
    List<Microservice> services, {
    ConfigurationEntry? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final key = TextEditingController(text: existing?.configKey ?? '');
    final value = TextEditingController(
      text: existing?.entryType == ConfigurationEntryType.plainVariable
          ? existing?.plainValue ?? ''
          : '',
    );
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    var type = existing?.entryType ?? ConfigurationEntryType.plainVariable;
    String? serviceId = existing?.microserviceId;
    final result = await showDialog<ConfigurationEntry>(
      context: context,
      builder: (dialogContext) => _DialogDisposalScope(
        disposables: [key, value, description],
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              existing == null
                  ? 'Nouvelle configuration'
                  : 'Modifier ${existing.configKey}',
            ),
            content: SizedBox(
              width: 480,
              child: Form(
                key: formKey,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    TextFormField(
                      key: const ValueKey('config-key-field'),
                      controller: key,
                      decoration: const InputDecoration(
                        labelText: 'Clé',
                        hintText: 'DATABASE_URL',
                        helperText: 'UPPER_SNAKE_CASE',
                      ),
                      validator: (raw) {
                        final text = raw?.trim() ?? '';
                        if (text.length < 2 ||
                            text.length > 128 ||
                            !RegExp(r'^[A-Z0-9]+(?:_[A-Z0-9]+)*$')
                                .hasMatch(text)) {
                          return 'Utilisez UPPER_SNAKE_CASE (ex. DATABASE_URL).';
                        }
                        final duplicate = widget
                            .controller
                            .domainCatalog
                            .configurationEntries
                            .any(
                              (entry) =>
                                  entry.id != existing?.id &&
                                  entry.domainId == domain.id &&
                                  entry.environmentId == environment.id &&
                                  entry.microserviceId == serviceId &&
                                  entry.configKey == text,
                            );
                        return duplicate
                            ? 'Cette clé existe déjà pour cette portée.'
                            : null;
                      },
                    ),
                    DropdownButtonFormField<ConfigurationEntryType>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(
                          value: ConfigurationEntryType.plainVariable,
                          child: Text('Variable en clair'),
                        ),
                        DropdownMenuItem(
                          value: ConfigurationEntryType.secret,
                          child: Text('Secret chiffré'),
                        ),
                      ],
                      onChanged: (next) {
                        if (next != null) setDialogState(() => type = next);
                      },
                    ),
                    DropdownButtonFormField<String?>(
                      initialValue: serviceId,
                      decoration: const InputDecoration(
                        labelText: 'Portée (facultatif)',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Domaine entier'),
                        ),
                        for (final service in services)
                          DropdownMenuItem<String?>(
                            value: service.id,
                            child: Text(service.serviceCode),
                          ),
                      ],
                      onChanged: (next) =>
                          setDialogState(() => serviceId = next),
                    ),
                    TextFormField(
                      key: const ValueKey('config-value-field'),
                      controller: value,
                      obscureText: type == ConfigurationEntryType.secret,
                      maxLines: type == ConfigurationEntryType.secret ? 1 : 3,
                      decoration: InputDecoration(
                        labelText: type == ConfigurationEntryType.secret
                            ? 'Valeur secrète'
                            : 'Valeur',
                        helperText:
                            type == ConfigurationEntryType.secret &&
                                existing?.isInitialized == true
                            ? 'Laisser vide pour conserver la valeur actuelle.'
                            : null,
                      ),
                      validator: (raw) {
                        if (type == ConfigurationEntryType.secret &&
                            existing?.isInitialized != true &&
                            (raw?.isEmpty ?? true)) {
                          return 'Une valeur est requise pour initialiser ce secret.';
                        }
                        if (raw != null && raw.length > 2000) {
                          return 'Maximum 2000 caractères.';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: description,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    if (type == ConfigurationEntryType.secret)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'La valeur sera chiffrée avant sa persistance et masquée dans le catalogue.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler'),
              ),
              FilledButton(
                key: const ValueKey('config-save-btn'),
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final rawValue = value.text;
                  String? plainValue;
                  String? encryptedValue;
                  var initialized = true;
                  if (type == ConfigurationEntryType.plainVariable) {
                    plainValue = rawValue;
                  } else if (rawValue.isNotEmpty) {
                    try {
                      encryptedValue = await _cipher.encrypt(rawValue);
                    } on Exception catch (error) {
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('Chiffrement impossible : $error'),
                        ),
                      );
                      return;
                    }
                  } else if (existing?.isInitialized == true) {
                    encryptedValue = existing!.encryptedValue;
                  } else {
                    initialized = false;
                  }
                  if (existing != null && type == existing.entryType) {
                    if (type == ConfigurationEntryType.secret &&
                        rawValue.isEmpty) {
                      encryptedValue = existing.encryptedValue;
                      initialized = existing.isInitialized;
                    } else if (type == ConfigurationEntryType.plainVariable &&
                        rawValue.isEmpty) {
                      plainValue = '';
                    }
                  }
                  final entry = ConfigurationEntry(
                    id: existing?.id ?? 'config_${shortid.generate()}',
                    domainId: domain.id,
                    environmentId: environment.id,
                    microserviceId: serviceId,
                    configKey: key.text.trim(),
                    entryType: type,
                    plainValue: plainValue,
                    encryptedValue: encryptedValue,
                    isInitialized: initialized,
                    description: description.text.trim(),
                  );
                  try {
                    entry.validate();
                  } on FormatException catch (error) {
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(SnackBar(content: Text(error.message)));
                    return;
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, entry);
                  }
                },
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final current = widget.controller.domainCatalog;
    final exists = current.configurationEntries.any(
      (item) => item.id == result.id,
    );
    final next = current.copyWith(
      configurationEntries: [
        for (final item in current.configurationEntries)
          if (item.id == result.id) result else item,
        if (!exists) result,
      ],
    );
    await _saveCatalog(
      _withAudit(
        next,
        _audit(
          domain.id,
          action: exists ? DomainAuditAction.update : DomainAuditAction.create,
          environmentId: environment.id,
          targetKey: result.configKey,
          isSecret: result.entryType == ConfigurationEntryType.secret,
          details: exists
              ? (result.entryType == ConfigurationEntryType.secret
                    ? 'Valeur du secret mise à jour (masquée).'
                    : 'Variable de configuration modifiée.')
              : (result.entryType == ConfigurationEntryType.secret
                    ? 'Secret créé (valeur masquée).'
                    : 'Variable de configuration créée.'),
        ),
      ),
    );
  }

  Future<void> _deleteConfiguration(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
    LogicalEnvironment environment,
    ConfigurationEntry entry,
  ) async {
    if (!await _confirm(context, 'Supprimer la clé ${entry.configKey} ?')) {
      return;
    }
    await _saveCatalog(
      _withAudit(
        catalog.copyWith(
          configurationEntries: catalog.configurationEntries
              .where((item) => item.id != entry.id)
              .toList(),
        ),
        _audit(
          domain.id,
          action: DomainAuditAction.delete,
          environmentId: environment.id,
          targetKey: entry.configKey,
          isSecret: entry.entryType == ConfigurationEntryType.secret,
          details: entry.entryType == ConfigurationEntryType.secret
              ? 'Secret supprimé (valeur masquée).'
              : 'Variable de configuration supprimée.',
        ),
      ),
    );
  }

  Future<void> _showEnvExport(
    BuildContext context,
    List<ConfigurationEntry> entries,
    LogicalEnvironment environment,
  ) async {
    final text = DomainEnvExporter.toEnv(entries);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Export .env · ${environment.environmentCode}'),
        content: SizedBox(
          width: 600,
          child: SelectableText(
            text.isEmpty ? 'Aucune variable à exporter.' : text,
            key: const ValueKey('domain-env-export-content'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
          if (text.isNotEmpty)
            FilledButton.icon(
              key: const ValueKey('domain-env-export-copy-btn'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _notice('Export .env copié dans le presse-papiers.');
              },
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: const Text('Copier'),
            ),
        ],
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ) ??
      false;

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  static String? _validateCode(String? raw, String kind) {
    final code = raw?.trim() ?? '';
    if (code.length < 2 ||
        code.length > 64 ||
        !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(code)) {
      return 'Code de $kind invalide : kebab-case (2 à 64 caractères).';
    }
    return null;
  }
}

class _DomainEmptyCard extends StatelessWidget {
  const _DomainEmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

class _DialogDisposalScope extends StatefulWidget {
  const _DialogDisposalScope({required this.disposables, required this.child});

  final List<ChangeNotifier> disposables;
  final Widget child;

  @override
  State<_DialogDisposalScope> createState() => _DialogDisposalScopeState();
}

class _DialogDisposalScopeState extends State<_DialogDisposalScope> {
  @override
  void dispose() {
    for (final disposable in widget.disposables) {
      disposable.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
