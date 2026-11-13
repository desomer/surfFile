/// Formulaire d'édition d'un provider HTTP ([HttpProviderForm]).
///
/// Saisie guidée d'une [HttpProviderConfig] : identité, requête (méthode, URL,
/// en-têtes, paramètres, corps), réponse, repositories (filtre, résultats,
/// indicateurs) et recherche automatique. Le formulaire ne connaît pas le
/// registre : le gestionnaire lit la saisie courante avec
/// [HttpProviderFormState.draft], puis l'enregistre ou la teste.
library;

import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io' show FileSystemException;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../models/providers/data_provider.dart';
import '../../../models/providers/http_provider_config.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../repositories/repository_binding_fields.dart';

/// Saisie courante d'un [HttpProviderForm] : une configuration valide ou le
/// message d'erreur affichable qui l'en sépare.
typedef HttpProviderDraft = ({HttpProviderConfig? config, String? error});

/// Cible provisoire tant que l'utilisateur n'en a pas choisi : elle laisse la
/// validation signaler d'abord les erreurs situées plus haut dans le formulaire.
const _placeholderTarget = JsonTextBinding(repositoryId: '_', path: '_');

const _prettyJson = JsonEncoder.withIndent('  ');

String _joinPairs(Map<String, String>? pairs, String separator) => [
  for (final entry in (pairs ?? const <String, String>{}).entries)
    '${entry.key}$separator${entry.value}',
].join('\n');

/// Lit une valeur par ligne (`Nom: valeur`, `nom=valeur`) ; les lignes vides
/// sont ignorées. Les messages citent le numéro de ligne, jamais son contenu
/// (un en-tête peut porter un secret).
Map<String, String> _parsePairs(
  String text, {
  required String separator,
  required String what,
  required String example,
}) {
  final result = <String, String>{};
  final lines = const LineSplitter().convert(text);
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isEmpty) continue;
    final cut = line.indexOf(separator);
    final name = cut < 0 ? '' : line.substring(0, cut).trim();
    if (name.isEmpty) {
      throw FormatException(
        '$what : la ligne ${index + 1} doit avoir la forme $example.',
      );
    }
    if (result.containsKey(name)) {
      throw FormatException('$what : « $name » est défini deux fois.');
    }
    result[name] = line.substring(cut + 1).trim();
  }
  return result;
}

int _parseMilliseconds(String text, String what) {
  final value = int.tryParse(text.trim());
  if (value == null) {
    throw FormatException('$what doit être un nombre entier de millisecondes.');
  }
  return value;
}

/// Formulaire de saisie d'un [HttpProviderConfig].
class HttpProviderForm extends StatefulWidget {
  /// Crée le formulaire ; [initial] est `null` pour un nouveau provider.
  const HttpProviderForm({
    required this.onEdited,
    this.initial,
    this.store,
    this.isNew = true,
    super.key,
  });

  /// Provider à modifier, ou `null` pour en créer un.
  final HttpProviderConfig? initial;

  /// Store dont les repositories sont proposés.
  final JsonRepositoryStore? store;

  /// Vrai tant que l'identifiant (nom du fichier) peut être choisi.
  final bool isNew;

  /// Appelé après chaque modification de l'utilisateur.
  final VoidCallback onEdited;

  @override
  State<HttpProviderForm> createState() => HttpProviderFormState();
}

/// État de [HttpProviderForm] ; [draft] expose la saisie courante.
class HttpProviderFormState extends State<HttpProviderForm> {
  late final TextEditingController _id;
  late final TextEditingController _label;
  late final TextEditingController _url;
  late final TextEditingController _headers;
  late final TextEditingController _query;
  late final TextEditingController _body;
  late final TextEditingController _timeout;
  late final TextEditingController _responsePath;
  late final TextEditingController _debounce;
  late String _method;
  late bool _autoParams;
  late bool _autoSearch;
  late bool _onStart;
  String _filter = '';
  JsonTextBinding? _target;
  JsonTextBinding? _loading;
  JsonTextBinding? _errorFlag;
  List<JsonRepositoryEntry> _repositories = const [];
  String? _loadError;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final request = initial?.request;
    final body = request?.body;
    _id = TextEditingController(text: initial?.id ?? '');
    _label = TextEditingController(text: initial?.label ?? '');
    _url = TextEditingController(text: request?.url ?? '');
    _headers = TextEditingController(text: _joinPairs(request?.headers, ': '));
    _query = TextEditingController(text: _joinPairs(request?.query, '='));
    _body = TextEditingController(
      text: body == null ? '' : _prettyJson.convert(body),
    );
    _timeout = TextEditingController(
      text: '${request?.timeoutMs ?? HttpRequestTemplate.defaultTimeoutMs}',
    );
    _responsePath = TextEditingController(text: initial?.responsePath ?? '');
    _debounce = TextEditingController(
      text:
          '${initial?.autoSearch?.debounceMs ?? ProviderAutoSearch.defaultDebounceMs}',
    );
    _method = request?.method ?? 'GET';
    _autoParams = request?.autoParams ?? true;
    _autoSearch = initial?.autoSearch != null;
    _onStart = initial?.autoSearch?.onStart ?? false;
    _filter = initial?.filterRepositoryId ?? '';
    _target = initial?.target;
    _loading = initial?.loading;
    _errorFlag = initial?.error;
    unawaited(_loadRepositories());
  }

  @override
  void dispose() {
    for (final controller in [
      _id,
      _label,
      _url,
      _headers,
      _query,
      _body,
      _timeout,
      _responsePath,
      _debounce,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRepositories() async {
    final store = widget.store;
    if (store == null) return;
    try {
      final entries = await store.catalog();
      if (mounted) setState(() => _repositories = entries);
    } on FormatException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } on FileSystemException {
      if (mounted) {
        setState(() => _loadError = 'Impossible de charger les repositories.');
      }
    }
  }

  /// Applique [mutate] puis signale au gestionnaire que la saisie a changé.
  void _change(VoidCallback mutate) {
    setState(() {
      mutate();
      _touched = true;
    });
    widget.onEdited();
  }

  Object? _bodyJson() {
    final text = _body.text.trim();
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException catch (error) {
      throw FormatException('Corps JSON invalide : ${error.message}');
    }
  }

  /// Saisie courante : la configuration complète et valide, ou le message
  /// d'erreur affichable de la première erreur rencontrée.
  HttpProviderDraft draft() {
    try {
      final id = _id.text.trim();
      final label = _label.text.trim();
      final responsePath = _responsePath.text.trim();
      final config = HttpProviderConfig(
        id: id,
        label: label.isEmpty ? id : label,
        filterRepositoryId: _filter.isEmpty ? null : _filter,
        target: _target ?? _placeholderTarget,
        loading: _loading,
        error: _errorFlag,
        autoSearch: _autoSearch
            ? ProviderAutoSearch(
                debounceMs: _parseMilliseconds(
                  _debounce.text,
                  'Le délai de la recherche automatique',
                ),
                onStart: _onStart,
              )
            : null,
        request: HttpRequestTemplate(
          method: _method,
          url: _url.text.trim(),
          headers: _parsePairs(
            _headers.text,
            separator: ':',
            what: 'En-têtes',
            example: 'Nom: valeur',
          ),
          query: _parsePairs(
            _query.text,
            separator: '=',
            what: 'Paramètres',
            example: 'nom=valeur',
          ),
          body: _method == 'POST' ? _bodyJson() : null,
          autoParams: _autoParams,
          timeoutMs: _parseMilliseconds(
            _timeout.text,
            'Le délai de la requête',
          ),
        ),
        responsePath: responsePath.isEmpty ? null : responsePath,
      );
      config.validate();
      if (_target == null) {
        throw const FormatException(
          'Résultats : choisissez le repository et le chemin du tableau qui '
          'reçoit les lignes.',
        );
      }
      return (config: config, error: null);
    } on FormatException catch (error) {
      return (config: null, error: error.message);
    }
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );

  Widget _field(
    String key,
    TextEditingController controller,
    String label, {
    String? hint,
    String? helper,
    int maxLines = 1,
    bool monospace = false,
    bool enabled = true,
    String? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: ValueKey(key),
      controller: controller,
      enabled: enabled,
      minLines: maxLines > 1 ? 2 : 1,
      maxLines: maxLines,
      keyboardType:
          keyboardType ?? (maxLines > 1 ? TextInputType.multiline : null),
      inputFormatters: formatters,
      style: monospace ? const TextStyle(fontFamily: 'monospace') : null,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        suffixText: suffix,
        alignLabelWithHint: maxLines > 1,
      ),
      onChanged: (_) => _change(() {}),
    ),
  );

  Widget _switch(
    String key,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool>? onChanged,
  ) => SwitchListTile(
    key: ValueKey(key),
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: onChanged,
  );

  Widget _caption(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );

  Widget _filterField() {
    final known =
        _filter.isEmpty || _repositories.any((entry) => entry.id == _filter);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InputDecorator(
        key: const ValueKey('provider-filter'),
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'Repository de filtre',
          prefixIcon: Icon(Icons.filter_alt_outlined),
          helperText: 'Ses champs deviennent les paramètres de la requête.',
          helperMaxLines: 2,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _filter,
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: '', child: Text('Aucun filtre')),
              for (final entry in _repositories)
                DropdownMenuItem(
                  value: entry.id,
                  child: Text(entry.name, overflow: TextOverflow.ellipsis),
                ),
              if (!known)
                DropdownMenuItem(
                  value: _filter,
                  child: const Text('Repository indisponible'),
                ),
            ],
            onChanged: widget.store == null
                ? null
                : (value) => _change(() {
                    _filter = value ?? '';
                    if (_filter.isEmpty) _autoSearch = false;
                  }),
          ),
        ),
      ),
    );
  }

  Widget _binding(
    String name,
    String label, {
    required JsonTextBinding? binding,
    required ValueChanged<JsonTextBinding?> onChanged,
    required String pathHint,
    required String helper,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _caption(label),
      RepositoryBindingFields(
        keyPrefix: 'provider-binding-$name',
        binding: binding,
        store: widget.store,
        pathHint: pathHint,
        helper: helper,
        onChanged: (value) => _change(() => onChanged(value)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final post = _method == 'POST';
    final error = _touched ? draft().error : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(
                  'provider-id',
                  _id,
                  'Identifiant',
                  hint: 'clients_api',
                  helper:
                      'a-z, 0-9 et _ (32 caractères au plus) ; nom du fichier '
                      'et valeur de l’action « Lancer la recherche ».',
                  enabled: widget.isNew,
                ),
                _field(
                  'provider-label',
                  _label,
                  'Libellé',
                  helper: 'Facultatif : l’identifiant par défaut.',
                ),
                _heading('Requête HTTP'),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SegmentedButton<String>(
                    key: const ValueKey('provider-method'),
                    showSelectedIcon: false,
                    segments: [
                      for (final method in HttpRequestTemplate.methods)
                        ButtonSegment(value: method, label: Text(method)),
                    ],
                    selected: {_method},
                    onSelectionChanged: (selection) =>
                        _change(() => _method = selection.first),
                  ),
                ),
                _field(
                  'provider-url',
                  _url,
                  'URL',
                  hint: 'https://api.exemple.com/clients',
                  helper:
                      'L’hôte est fixe. Le reste accepte {{champ}} (champ du '
                      'filtre) et {{env.PROVIDER_NOM}} (variable '
                      'd’environnement).',
                ),
                _field(
                  'provider-headers',
                  _headers,
                  'En-têtes (un par ligne : Nom: valeur)',
                  hint: 'Authorization: Bearer {{env.PROVIDER_TOKEN}}',
                  maxLines: 5,
                  monospace: true,
                ),
                _field(
                  'provider-query',
                  _query,
                  'Paramètres (un par ligne : nom=valeur)',
                  hint: 'q={{recherche}}',
                  maxLines: 5,
                  monospace: true,
                ),
                if (post)
                  _field(
                    'provider-body',
                    _body,
                    'Corps JSON',
                    hint: '{"q": "{{recherche}}"}',
                    helper:
                        'Une chaîne exactement égale à {{champ}} garde le type '
                        'de la valeur lue.',
                    maxLines: 8,
                    monospace: true,
                  ),
                _switch(
                  'provider-auto-params',
                  'Ajouter automatiquement les champs du filtre',
                  post
                      ? 'Sans corps défini, les champs du filtre non utilisés '
                            'par un {{gabarit}} forment le corps JSON.'
                      : 'Les champs du filtre non utilisés par un {{gabarit}} '
                            'sont ajoutés à l’URL.',
                  _autoParams,
                  (value) => _change(() => _autoParams = value),
                ),
                _field(
                  'provider-timeout',
                  _timeout,
                  'Délai maximal',
                  suffix: 'ms',
                  helper:
                      '${HttpRequestTemplate.minTimeoutMs} à '
                      '${HttpRequestTemplate.maxTimeoutMs} ms.',
                  keyboardType: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                _heading('Réponse'),
                _field(
                  'provider-response-path',
                  _responsePath,
                  'Chemin des lignes dans la réponse',
                  hint: 'data.items',
                  helper:
                      'Tableau JSON qui devient la liste des lignes ; vide : '
                      'la réponse elle-même.',
                ),
                _heading('Repositories'),
                _filterField(),
                _binding(
                  'target',
                  'Résultats (obligatoire)',
                  binding: _target,
                  onChanged: (value) => _target = value,
                  pathHint: 'clients',
                  helper: 'Tableau remplacé à chaque recherche.',
                ),
                _binding(
                  'loading',
                  'Indicateur de chargement (facultatif)',
                  binding: _loading,
                  onChanged: (value) => _loading = value,
                  pathHint: 'recherche.enCours',
                  helper: 'Booléen mis à true pendant la recherche.',
                ),
                _binding(
                  'error',
                  'Indicateur d’erreur (facultatif)',
                  binding: _errorFlag,
                  onChanged: (value) => _errorFlag = value,
                  pathHint: 'recherche.erreur',
                  helper: 'Texte du dernier message d’erreur, vide si succès.',
                ),
                if (widget.store != null && _repositories.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Créez d’abord les repositories dans le gestionnaire '
                      'de repositories.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_loadError case final message?)
                  Text(
                    message,
                    key: const ValueKey('provider-form-load-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                _heading('Recherche automatique'),
                _switch(
                  'provider-auto-search',
                  'Relancer la recherche quand le filtre change',
                  _filter.isEmpty
                      ? 'Choisissez d’abord un repository de filtre.'
                      : 'Après un délai sans modification du filtre.',
                  _autoSearch,
                  _filter.isEmpty
                      ? null
                      : (value) => _change(() => _autoSearch = value),
                ),
                if (_autoSearch) ...[
                  _field(
                    'provider-debounce',
                    _debounce,
                    'Délai sans modification',
                    suffix: 'ms',
                    helper:
                        '${ProviderAutoSearch.minDebounceMs} à '
                        '${ProviderAutoSearch.maxDebounceMs} ms.',
                    keyboardType: TextInputType.number,
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  _switch(
                    'provider-on-start',
                    'Lancer aussi au démarrage',
                    'Une recherche part dès le chargement des providers.',
                    _onStart,
                    (value) => _change(() => _onStart = value),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              key: const ValueKey('provider-form-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
