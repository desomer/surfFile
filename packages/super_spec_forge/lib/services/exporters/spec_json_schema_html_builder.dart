/// Générateur de documentation HTML5 interactive autonome pour les couples
/// JSON Schema Draft 2020-12 & Seed Data ([SpecJsonSchemaHtmlBuilder]).
library;

import 'dart:convert';

import 'package:super_container_layout/super_container_layout.dart';

import 'spec_markdown_html_builder.dart';
import 'spec_super_designer_exporter.dart';

/// Construit une page HTML5 autonome hors-ligne explorant un [SuperDesignerExportBundle].
abstract final class SpecJsonSchemaHtmlBuilder {
  /// Génère le document HTML5 complet à partir de [bundle].
  static String buildHtml({
    required SuperDesignerExportBundle bundle,
    required String title,
    SpecMarkdownViewerAssets assets = const SpecMarkdownViewerAssets.empty(),
    bool darkMode = false,
  }) {
    final safeTitle = const HtmlEscape(HtmlEscapeMode.element).convert(title);
    final initialTheme = darkMode ? 'dark' : 'light';

    final reposPayload = <Map<String, Object?>>[];
    final aliases = <String>{
      ...bundle.repositoriesJsonSchemas.keys,
      ...bundle.repositoriesSeedData.keys,
    }.toList()
      ..sort();

    for (final alias in aliases) {
      final schema = bundle.repositoriesJsonSchemas[alias];
      final seed = bundle.repositoriesSeedData[alias];
      var isValid = true;
      var issues = const <Map<String, String>>[];
      if (schema != null && seed != null) {
        try {
          final res = JsonSchemaValidator.validate(seed, schema);
          isValid = res.isValid;
          issues = [
            for (final issue in res.issues)
              <String, String>{
                'path': issue.instancePath,
                'keyword': issue.keyword,
                'message': issue.message,
              },
          ];
        } on FormatException catch (e) {
          isValid = false;
          issues = [
            <String, String>{
              'path': '#',
              'keyword': 'schema',
              'message': e.message,
            },
          ];
        }
      }
      reposPayload.add(<String, Object?>{
        'alias': alias,
        'title': (schema?['title'] as String?)?.trim().isNotEmpty == true
            ? schema!['title'] as String
            : alias,
        'description': (schema?['description'] as String?) ?? '',
        'schema': schema ?? const <String, Object?>{},
        'seed': seed ?? const <String, Object?>{},
        'isValid': isValid,
        'issues': issues,
      });
    }

    final safeJsonPayload = jsonEncode(
      reposPayload,
    ).replaceAll('</', r'<\/').replaceAll('<!--', r'<\!--');

    String safeInlineScript(String js) =>
        js.replaceAll('</script>', r'<\/script>');

    String safeInlineStyle(String css) =>
        css.replaceAll('</style>', r'<\/style>');

    return _htmlTemplate
        .replaceAll('__SSF_THEME__', initialTheme)
        .replaceAll('__SSF_TITLE__', safeTitle)
        .replaceAll(
          '__SSF_HLJS_LIGHT_MEDIA__',
          darkMode ? ' media="not all"' : '',
        )
        .replaceAll(
          '__SSF_HLJS_DARK_MEDIA__',
          darkMode ? '' : ' media="not all"',
        )
        .replaceAll('__SSF_HLJS_LIGHT_CSS__', safeInlineStyle(assets.highlightLightCss))
        .replaceAll('__SSF_HLJS_DARK_CSS__', safeInlineStyle(assets.highlightDarkCss))
        .replaceAll('__SSF_REPOS_JSON__', safeJsonPayload)
        .replaceAll('__SSF_HLJS_JS__', safeInlineScript(assets.highlightJs));
  }

  static const String _htmlTemplate = r'''<!DOCTYPE html>
<html lang="fr" data-theme="__SSF_THEME__">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>__SSF_TITLE__</title>
  <style id="ssf-hljs-light"__SSF_HLJS_LIGHT_MEDIA__>__SSF_HLJS_LIGHT_CSS__</style>
  <style id="ssf-hljs-dark"__SSF_HLJS_DARK_MEDIA__>__SSF_HLJS_DARK_CSS__</style>
  <style>
    :root {
      --bg: #f8fafc;
      --surface: #ffffff;
      --surface-alt: #f1f5f9;
      --border: #e2e8f0;
      --text: #0f172a;
      --text-muted: #475569;
      --accent: #2563eb;
      --accent-soft: rgba(37, 99, 235, 0.10);
      --ok-bg: rgba(22, 163, 74, 0.12);
      --ok-fg: #15803d;
      --err-bg: rgba(220, 38, 38, 0.12);
      --err-fg: #b91c1c;
      --code-bg: #f6f8fa;
      --shadow: 0 2px 10px rgba(15, 23, 42, 0.06);
    }
    html[data-theme="dark"] {
      --bg: #0b1120;
      --surface: #111827;
      --surface-alt: #1e293b;
      --border: #293548;
      --text: #e2e8f0;
      --text-muted: #94a3b8;
      --accent: #60a5fa;
      --accent-soft: rgba(96, 165, 250, 0.14);
      --ok-bg: rgba(34, 197, 94, 0.16);
      --ok-fg: #4ade80;
      --err-bg: rgba(248, 113, 113, 0.16);
      --err-fg: #f87171;
      --code-bg: #0d1117;
      --shadow: 0 4px 16px rgba(0, 0, 0, 0.35);
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, Roboto, sans-serif;
      font-size: 14px;
      line-height: 1.55;
    }
    .layout { display: flex; min-height: 100vh; }
    .sidebar {
      width: 280px;
      flex: 0 0 280px;
      position: sticky;
      top: 0;
      height: 100vh;
      overflow-y: auto;
      background: var(--surface);
      border-right: 1px solid var(--border);
      padding: 18px 14px;
    }
    .sidebar-title {
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--text-muted);
      margin: 0 8px 10px;
    }
    .repo-btn {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      width: 100%;
      text-align: left;
      background: transparent;
      border: 1px solid transparent;
      border-radius: 8px;
      padding: 8px 10px;
      color: var(--text);
      cursor: pointer;
      margin-bottom: 4px;
      font-size: 13px;
    }
    .repo-btn:hover { background: var(--surface-alt); }
    .repo-btn.active {
      background: var(--accent-soft);
      border-color: rgba(37, 99, 235, 0.35);
      color: var(--accent);
      font-weight: 700;
    }
    .repo-sub {
      display: block;
      font-family: "JetBrains Mono", Consolas, monospace;
      font-size: 11px;
      color: var(--text-muted);
      font-weight: 500;
    }
    .badge {
      display: inline-block;
      padding: 1px 7px;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 700;
      white-space: nowrap;
    }
    .badge-ok { background: var(--ok-bg); color: var(--ok-fg); }
    .badge-err { background: var(--err-bg); color: var(--err-fg); }
    .badge-type {
      background: var(--accent-soft);
      color: var(--accent);
      font-family: "JetBrains Mono", Consolas, monospace;
    }
    .badge-req { background: var(--err-bg); color: var(--err-fg); }
    .badge-constraint {
      background: var(--surface-alt);
      color: var(--text-muted);
      border: 1px solid var(--border);
      font-family: "JetBrains Mono", Consolas, monospace;
      font-weight: 600;
    }
    .main {
      flex: 1 1 auto;
      min-width: 0;
      padding: 24px 32px 60px;
    }
    .topbar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      flex-wrap: wrap;
      margin-bottom: 16px;
    }
    .search {
      min-width: 240px;
      padding: 6px 10px;
      border-radius: 8px;
      border: 1px solid var(--border);
      background: var(--surface);
      color: var(--text);
      font-size: 13px;
    }
    .btn {
      appearance: none;
      border: 1px solid var(--border);
      background: var(--surface);
      color: var(--text);
      border-radius: 8px;
      padding: 5px 11px;
      font-size: 12.5px;
      font-weight: 600;
      cursor: pointer;
    }
    .btn:hover { border-color: var(--accent); color: var(--accent); }
    .card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 20px 24px;
      margin-bottom: 18px;
      box-shadow: var(--shadow);
      break-inside: avoid;
    }
    .card h2 { margin: 0 0 6px; font-size: 18px; }
    .card h3 { margin: 0 0 10px; font-size: 15px; }
    .muted { color: var(--text-muted); font-size: 13px; }
    .prop-node {
      border: 1px solid var(--border);
      border-radius: 9px;
      margin: 8px 0;
      background: var(--surface-alt);
      overflow: hidden;
    }
    .prop-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      padding: 8px 12px;
      flex-wrap: wrap;
      cursor: pointer;
    }
    .prop-name {
      font-family: "JetBrains Mono", Consolas, monospace;
      font-weight: 700;
      font-size: 13px;
    }
    .prop-badges {
      display: flex;
      gap: 5px;
      flex-wrap: wrap;
      align-items: center;
    }
    .prop-body {
      padding: 0 12px 10px 20px;
      border-top: 1px solid var(--border);
      background: var(--surface);
    }
    .prop-node.collapsed > .prop-body { display: none; }
    pre {
      background: var(--code-bg);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 12px 14px;
      overflow-x: auto;
      margin: 0;
      font-family: "JetBrains Mono", Consolas, monospace;
      font-size: 12.5px;
      line-height: 1.5;
    }
    @media print {
      .sidebar, .topbar, .btn { display: none !important; }
      .main { padding: 0; }
      .card { box-shadow: none; break-inside: avoid; }
    }
  </style>
</head>
<body>
  <div class="layout">
    <aside class="sidebar">
      <div class="sidebar-title">Repositories (__SSF_TITLE__)</div>
      <div id="ssf-repo-list"></div>
    </aside>
    <main class="main">
      <div class="topbar">
        <input id="ssf-search" class="search" type="search" placeholder="Filtrer propriétés ou contraintes…" />
        <div style="display:flex;gap:8px;flex-wrap:wrap;">
          <button class="btn" type="button" onclick="window.ssfSchemaViewer.toggleTheme()">Thème</button>
          <button class="btn" type="button" onclick="window.print()">Imprimer / PDF</button>
        </div>
      </div>
      <div id="ssf-repo-detail"></div>
    </main>
  </div>

  <script id="ssf-repos-data" type="application/json">__SSF_REPOS_JSON__</script>
  <script>__SSF_HLJS_JS__</script>
  <script>
    (function () {
      const rawEl = document.getElementById('ssf-repos-data');
      const repos = rawEl ? JSON.parse(rawEl.textContent || '[]') : [];
      const listEl = document.getElementById('ssf-repo-list');
      const detailEl = document.getElementById('ssf-repo-detail');
      const searchEl = document.getElementById('ssf-search');
      let selectedIndex = 0;
      let query = '';

      function esc(str) {
        return String(str)
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;');
      }

      function collectConstraintBadges(node) {
        if (!node || typeof node !== 'object') return [];
        const keys = [
          'format', 'minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum',
          'multipleOf', 'minLength', 'maxLength', 'pattern', 'minItems', 'maxItems',
          'uniqueItems', 'minProperties', 'maxProperties', 'additionalProperties',
          'readOnly', 'writeOnly', 'deprecated', 'contentMediaType', 'contentEncoding'
        ];
        const badges = [];
        if ('const' in node) badges.push('const=' + JSON.stringify(node.const));
        if (Array.isArray(node.enum)) badges.push('enum(' + node.enum.join(', ') + ')');
        for (const k of keys) {
          if (node[k] !== undefined) badges.push(k + ': ' + JSON.stringify(node[k]));
        }
        if (Array.isArray(node.oneOf)) badges.push('oneOf(' + node.oneOf.length + ')');
        if (Array.isArray(node.anyOf)) badges.push('anyOf(' + node.anyOf.length + ')');
        if (Array.isArray(node.allOf)) badges.push('allOf(' + node.allOf.length + ')');
        if (node.if) badges.push('if/then/else');
        return badges;
      }

      function formatType(node) {
        if (!node || typeof node !== 'object') return 'any';
        if (Array.isArray(node.type)) return node.type.join(' | ');
        return node.type || (node.properties ? 'object' : 'any');
      }

      function matchesQuery(name, node) {
        if (!query) return true;
        const hay = (name + ' ' + JSON.stringify(node || {})).toLowerCase();
        return hay.includes(query);
      }

      function renderSchemaNode(name, node, isRequired) {
        if (!node || typeof node !== 'object' || !matchesQuery(name, node)) return '';
        const typeStr = formatType(node);
        const badges = collectConstraintBadges(node);
        const hasChildren =
          (node.properties && typeof node.properties === 'object') ||
          (node.items && typeof node.items === 'object');

        let childHtml = '';
        if (node.description) {
          childHtml += '<p class="muted" style="margin:8px 0 6px;">' + esc(node.description) + '</p>';
        }
        if (Array.isArray(node.examples) && node.examples.length) {
          childHtml += '<p class="muted" style="margin:4px 0 6px;">Exemples : <code>' +
            esc(JSON.stringify(node.examples)) + '</code></p>';
        }
        if (node.properties && typeof node.properties === 'object') {
          const reqSet = new Set(Array.isArray(node.required) ? node.required : []);
          for (const [k, v] of Object.entries(node.properties)) {
            childHtml += renderSchemaNode(k, v, reqSet.has(k));
          }
        }
        if (node.items && typeof node.items === 'object') {
          childHtml += renderSchemaNode('[items]', node.items, false);
        }

        const badgeHtml = [
          '<span class="badge badge-type">' + esc(typeStr) + '</span>',
          isRequired ? '<span class="badge badge-req">required</span>' : '',
          ...badges.map(b => '<span class="badge badge-constraint">' + esc(b) + '</span>')
        ].join('');

        return '<div class="prop-node">' +
          '<div class="prop-head" onclick="this.parentElement.classList.toggle(\'collapsed\')">' +
            '<span class="prop-name">' + (hasChildren ? '▾ ' : '• ') + esc(name) + '</span>' +
            '<span class="prop-badges">' + badgeHtml + '</span>' +
          '</div>' +
          (childHtml ? '<div class="prop-body">' + childHtml + '</div>' : '') +
        '</div>';
      }

      function renderSidebar() {
        listEl.innerHTML = '';
        repos.forEach(function (repo, idx) {
          const btn = document.createElement('button');
          btn.type = 'button';
          btn.className = 'repo-btn' + (idx === selectedIndex ? ' active' : '');
          btn.innerHTML =
            '<span>' + esc(repo.title) + '<span class="repo-sub">' + esc(repo.alias) + '</span></span>' +
            '<span class="badge ' + (repo.isValid ? 'badge-ok' : 'badge-err') + '">' +
              (repo.isValid ? 'Valide' : (repo.issues.length + ' err.')) +
            '</span>';
          btn.onclick = function () {
            selectedIndex = idx;
            renderSidebar();
            renderDetail();
          };
          listEl.appendChild(btn);
        });
      }

      function renderDetail() {
        if (!repos.length) {
          detailEl.innerHTML = '<div class="card"><p class="muted">Aucun repository JSON Schema généré.</p></div>';
          return;
        }
        const repo = repos[selectedIndex] || repos[0];
        const validationBanner = repo.isValid
          ? '<span class="badge badge-ok">Seed conforme au JSON Schema (JsonSchemaValidator)</span>'
          : '<div style="margin-top:8px;"><span class="badge badge-err">' + repo.issues.length +
              ' erreur(s) de validation</span><ul>' +
              repo.issues.map(i => '<li><code>' + esc(i.path) + '</code> (' + esc(i.keyword) + ') : ' + esc(i.message) + '</li>').join('') +
            '</ul></div>';

        const treeHtml = renderSchemaNode(repo.alias, repo.schema, true) ||
          '<p class="muted">Aucune propriété ne correspond au filtre.</p>';

        detailEl.innerHTML =
          '<div class="card">' +
            '<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px;flex-wrap:wrap;">' +
              '<div><h2>' + esc(repo.title) + ' <span class="repo-sub" style="display:inline;">(' + esc(repo.alias) + ')</span></h2>' +
              (repo.description ? '<p class="muted" style="margin:4px 0 8px;">' + esc(repo.description) + '</p>' : '') +
              '</div>' +
              validationBanner +
            '</div>' +
          '</div>' +
          '<div class="card"><h3>Structure du JSON Schema</h3>' + treeHtml + '</div>' +
          '<div class="card"><h3>Données Seed générées</h3><pre><code class="language-json">' +
            esc(JSON.stringify(repo.seed, null, 2)) +
          '</code></pre></div>' +
          '<div class="card"><h3>Source JSON Schema (Draft 2020-12)</h3><pre><code class="language-json">' +
            esc(JSON.stringify(repo.schema, null, 2)) +
          '</code></pre></div>';

        if (typeof window.hljs !== 'undefined') {
          detailEl.querySelectorAll('pre code').forEach(function (el) {
            try { window.hljs.highlightElement(el); } catch (_) {}
          });
        }
      }

      searchEl.addEventListener('input', function () {
        query = (searchEl.value || '').trim().toLowerCase();
        renderDetail();
      });

      window.ssfSchemaViewer = {
        setTheme: function (themeName) {
          const isDark = themeName === 'dark';
          document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
          const lightStyle = document.getElementById('ssf-hljs-light');
          const darkStyle = document.getElementById('ssf-hljs-dark');
          if (lightStyle) lightStyle.media = isDark ? 'not all' : '';
          if (darkStyle) darkStyle.media = isDark ? '' : 'not all';
        },
        toggleTheme: function () {
          const curr = document.documentElement.getAttribute('data-theme') || 'light';
          window.ssfSchemaViewer.setTheme(curr === 'dark' ? 'light' : 'dark');
        }
      };

      renderSidebar();
      renderDetail();
    })();
  </script>
</body>
</html>
''';
}
