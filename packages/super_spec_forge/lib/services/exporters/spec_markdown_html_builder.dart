/// Générateur de document HTML5 autonome pour la visualisation avancée
/// du cahier des charges Markdown (Mermaid, TOC, Highlight.js, KaTeX, GFM, Print/PDF)
/// ([SpecMarkdownHtmlBuilder]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bundle immuable des scripts et feuilles de style embarqués hors-ligne.
@immutable
class SpecMarkdownViewerAssets {
  /// Construit un bundle d'assets pour le visualisateur Markdown.
  const SpecMarkdownViewerAssets({
    required this.markedJs,
    required this.mermaidJs,
    required this.highlightJs,
    required this.highlightLightCss,
    required this.highlightDarkCss,
    required this.katexJs,
    required this.katexAutoRenderJs,
    required this.katexCss,
  });

  /// Bundle vide utilisé en repli ou dans les tests unitaires sans `rootBundle`.
  const SpecMarkdownViewerAssets.empty()
    : markedJs = '',
      mermaidJs = '',
      highlightJs = '',
      highlightLightCss = '',
      highlightDarkCss = '',
      katexJs = '',
      katexAutoRenderJs = '',
      katexCss = '';

  /// Contenu de `marked.min.js`.
  final String markedJs;

  /// Contenu de `mermaid.min.js`.
  final String mermaidJs;

  /// Contenu de `highlight.min.js`.
  final String highlightJs;

  /// CSS thème clair de Highlight.js.
  final String highlightLightCss;

  /// CSS thème sombre de Highlight.js.
  final String highlightDarkCss;

  /// Contenu de `katex.min.js`.
  final String katexJs;

  /// Contenu de `katex-auto-render.min.js`.
  final String katexAutoRenderJs;

  /// CSS KaTeX (sans `@font-face` externes pour rester 100 % autonome).
  final String katexCss;

  /// Vrai si les principaux moteurs JS hors-ligne sont présents.
  bool get hasOfflineScripts => markedJs.isNotEmpty && mermaidJs.isNotEmpty;
}

/// Construit une page HTML5 autonome rendant un document Markdown complet hors-ligne.
abstract final class SpecMarkdownHtmlBuilder {
  static SpecMarkdownViewerAssets? _cachedAssets;

  /// Charge et met en cache les assets JS/CSS embarqués dans `assets/markdown_viewer/`.
  static Future<SpecMarkdownViewerAssets> loadAssets({
    AssetBundle? bundle,
  }) async {
    if (bundle == null && _cachedAssets != null) {
      return _cachedAssets!;
    }
    final loader = bundle ?? rootBundle;

    Future<String> loadAsset(String fileName) async {
      final candidates = <String>[
        'packages/super_spec_forge/assets/markdown_viewer/$fileName',
        'assets/markdown_viewer/$fileName',
      ];
      for (final key in candidates) {
        try {
          return await loader.loadString(key);
        } catch (_) {}
      }
      return '';
    }

    final rawKatexCss = await loadAsset('katex.min.css');
    final cleanKatexCss = rawKatexCss.replaceAll(
      RegExp(r'@font-face\s*\{[^}]*\}'),
      '',
    );

    final loaded = SpecMarkdownViewerAssets(
      markedJs: await loadAsset('marked.min.js'),
      mermaidJs: await loadAsset('mermaid.min.js'),
      highlightJs: await loadAsset('highlight.min.js'),
      highlightLightCss: await loadAsset('highlight-light.min.css'),
      highlightDarkCss: await loadAsset('highlight-dark.min.css'),
      katexJs: await loadAsset('katex.min.js'),
      katexAutoRenderJs: await loadAsset('katex-auto-render.min.js'),
      katexCss: cleanKatexCss,
    );
    if (bundle == null && loaded.hasOfflineScripts) {
      _cachedAssets = loaded;
    }
    return loaded;
  }

  /// Construit le document HTML5 complet à partir de [markdown] et des [assets].
  static String buildHtml({
    required String markdown,
    required String title,
    SpecMarkdownViewerAssets assets = const SpecMarkdownViewerAssets.empty(),
    bool darkMode = false,
    bool showToc = true,
  }) {
    final safeTitle = const HtmlEscape(HtmlEscapeMode.element).convert(title);
    final safeMarkdownJson = jsonEncode(
      markdown,
    ).replaceAll('</', r'<\/').replaceAll('<!--', r'<\!--');
    final initialTheme = darkMode ? 'dark' : 'light';
    final initialTocClass = showToc ? '' : ' ssf-toc-hidden';

    String safeInlineScript(String js) =>
        js.replaceAll('</script>', r'<\/script>');

    String safeInlineStyle(String css) =>
        css.replaceAll('</style>', r'<\/style>');

    return _htmlTemplate
        .replaceAll('__SSF_THEME__', initialTheme)
        .replaceAll('__SSF_TOC_CLASS__', initialTocClass)
        .replaceAll('__SSF_TITLE__', safeTitle)
        .replaceAll(
          '__SSF_HLJS_LIGHT_MEDIA__',
          darkMode ? ' media="not all"' : '',
        )
        .replaceAll(
          '__SSF_HLJS_DARK_MEDIA__',
          darkMode ? '' : ' media="not all"',
        )
        .replaceAll('__SSF_KATEX_CSS__', safeInlineStyle(assets.katexCss))
        .replaceAll(
          '__SSF_HLJS_LIGHT_CSS__',
          safeInlineStyle(assets.highlightLightCss),
        )
        .replaceAll(
          '__SSF_HLJS_DARK_CSS__',
          safeInlineStyle(assets.highlightDarkCss),
        )
        .replaceAll('__SSF_MARKDOWN_JSON__', safeMarkdownJson)
        .replaceAll('__SSF_MARKED_JS__', safeInlineScript(assets.markedJs))
        .replaceAll('__SSF_HLJS_JS__', safeInlineScript(assets.highlightJs))
        .replaceAll('__SSF_KATEX_JS__', safeInlineScript(assets.katexJs))
        .replaceAll(
          '__SSF_KATEX_AUTO_JS__',
          safeInlineScript(assets.katexAutoRenderJs),
        )
        .replaceAll('__SSF_MERMAID_JS__', safeInlineScript(assets.mermaidJs));
  }

  static const String _htmlTemplate = r'''<!DOCTYPE html>
<html lang="fr" data-theme="__SSF_THEME__">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>__SSF_TITLE__</title>
  <style id="ssf-katex-css">__SSF_KATEX_CSS__</style>
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
      font-size: 15px;
      line-height: 1.65;
    }
    .ssf-layout {
      display: flex;
      min-height: 100vh;
    }
    .ssf-sidebar {
      width: 276px;
      flex: 0 0 276px;
      position: sticky;
      top: 0;
      height: 100vh;
      overflow-y: auto;
      background: var(--surface);
      border-right: 1px solid var(--border);
      padding: 18px 14px 28px;
    }
    .ssf-toc-hidden .ssf-sidebar {
      display: none;
    }
    .ssf-sidebar-title {
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--text-muted);
      margin: 0 8px 10px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    #ssf-toc-list {
      list-style: none;
      margin: 0;
      padding: 0;
    }
    #ssf-toc-list li {
      margin: 2px 0;
    }
    #ssf-toc-list a {
      display: block;
      padding: 5px 8px;
      border-radius: 6px;
      color: var(--text-muted);
      text-decoration: none;
      font-size: 13px;
      line-height: 1.35;
      border-left: 2px solid transparent;
      transition: background 120ms ease, color 120ms ease;
    }
    #ssf-toc-list a:hover {
      background: var(--surface-alt);
      color: var(--text);
    }
    #ssf-toc-list a.active {
      background: var(--accent-soft);
      color: var(--accent);
      border-left-color: var(--accent);
      font-weight: 600;
    }
    #ssf-toc-list a[data-level="1"] { font-weight: 700; color: var(--text); }
    #ssf-toc-list a[data-level="2"] { padding-left: 12px; font-weight: 600; }
    #ssf-toc-list a[data-level="3"] { padding-left: 24px; font-size: 12.5px; }
    #ssf-toc-list a[data-level="4"] { padding-left: 34px; font-size: 12px; }
    .ssf-main {
      flex: 1 1 auto;
      min-width: 0;
      padding: 28px 36px 64px;
    }
    .ssf-doc {
      max-width: 980px;
      margin: 0 auto;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 36px 44px;
      box-shadow: var(--shadow);
    }
    .ssf-browser-bar {
      max-width: 980px;
      margin: 0 auto 14px;
      display: flex;
      gap: 8px;
      justify-content: flex-end;
      flex-wrap: wrap;
    }
    .ssf-btn {
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
    .ssf-btn:hover {
      border-color: var(--accent);
      color: var(--accent);
    }
    h1, h2, h3, h4 {
      color: var(--text);
      line-height: 1.3;
      margin-top: 1.5em;
      margin-bottom: 0.55em;
      scroll-margin-top: 16px;
    }
    h1 {
      margin-top: 0;
      font-size: 1.9em;
      padding-bottom: 10px;
      border-bottom: 2px solid var(--border);
    }
    h2 {
      font-size: 1.4em;
      padding-bottom: 6px;
      border-bottom: 1px solid var(--border);
    }
    h3 { font-size: 1.15em; }
    a { color: var(--accent); }
    hr {
      border: none;
      border-top: 1px solid var(--border);
      margin: 24px 0;
    }
    blockquote {
      margin: 14px 0;
      padding: 10px 16px;
      border-left: 4px solid var(--accent);
      background: var(--accent-soft);
      border-radius: 0 8px 8px 0;
    }
    blockquote p:last-child { margin-bottom: 0; }
    blockquote p:first-child { margin-top: 0; }
    .ssf-alert {
      margin: 16px 0;
      padding: 12px 16px;
      border-radius: 10px;
      border: 1px solid var(--border);
      border-left-width: 4px;
      background: var(--surface-alt);
    }
    .ssf-alert-title {
      font-size: 12.5px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      margin-bottom: 4px;
    }
    .ssf-alert-note { border-left-color: #2563eb; background: rgba(37, 99, 235, 0.08); }
    .ssf-alert-note .ssf-alert-title { color: #2563eb; }
    .ssf-alert-tip { border-left-color: #16a34a; background: rgba(22, 163, 74, 0.08); }
    .ssf-alert-tip .ssf-alert-title { color: #16a34a; }
    .ssf-alert-important { border-left-color: #7c3aed; background: rgba(124, 58, 237, 0.08); }
    .ssf-alert-important .ssf-alert-title { color: #7c3aed; }
    .ssf-alert-warning { border-left-color: #d97706; background: rgba(217, 119, 6, 0.10); }
    .ssf-alert-warning .ssf-alert-title { color: #d97706; }
    .ssf-alert-caution { border-left-color: #dc2626; background: rgba(220, 38, 38, 0.09); }
    .ssf-alert-caution .ssf-alert-title { color: #dc2626; }
    table {
      width: 100%;
      border-collapse: collapse;
      margin: 14px 0 18px;
      font-size: 13.5px;
      display: block;
      overflow-x: auto;
    }
    th, td {
      border: 1px solid var(--border);
      padding: 8px 11px;
      text-align: left;
      vertical-align: top;
    }
    th {
      background: var(--surface-alt);
      font-weight: 700;
    }
    tr:nth-child(even) td {
      background: rgba(148, 163, 184, 0.05);
    }
    code {
      font-family: "JetBrains Mono", "Cascadia Code", Consolas, monospace;
      font-size: 0.9em;
      background: var(--code-bg);
      border: 1px solid var(--border);
      padding: 1px 5px;
      border-radius: 5px;
    }
    pre {
      background: var(--code-bg);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 12px 14px;
      overflow-x: auto;
      position: relative;
    }
    pre code {
      border: none;
      background: transparent;
      padding: 0;
      font-size: 13px;
      line-height: 1.5;
    }
    .ssf-code-wrap {
      position: relative;
      margin: 14px 0;
    }
    .ssf-code-lang {
      position: absolute;
      top: 8px;
      right: 10px;
      font-size: 11px;
      font-weight: 600;
      color: var(--text-muted);
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 1px 7px;
      z-index: 2;
    }
    .ssf-mermaid-card {
      margin: 16px 0;
      border: 1px solid var(--border);
      border-radius: 12px;
      background: var(--surface-alt);
      overflow: hidden;
      break-inside: avoid;
    }
    .ssf-mermaid-bar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 6px 12px;
      background: var(--surface);
      border-bottom: 1px solid var(--border);
      font-size: 12px;
      color: var(--text-muted);
    }
    .ssf-mermaid-actions {
      display: flex;
      gap: 6px;
      align-items: center;
    }
    .ssf-mermaid-stage {
      padding: 14px;
      overflow: auto;
      text-align: center;
    }
    .ssf-mermaid-inner {
      display: inline-block;
      transform-origin: top center;
      transition: transform 120ms ease;
    }
    .ssf-mermaid-error {
      text-align: left;
      color: #dc2626;
      font-size: 12.5px;
      padding: 8px;
    }
    @media (max-width: 900px) {
      .ssf-sidebar { display: none; }
      .ssf-main { padding: 14px; }
      .ssf-doc { padding: 20px; }
    }
    @media print {
      body { background: #ffffff; color: #000000; }
      .ssf-sidebar, .ssf-browser-bar, .ssf-mermaid-bar, .ssf-code-lang {
        display: none !important;
      }
      .ssf-main { padding: 0; }
      .ssf-doc {
        max-width: none;
        border: none;
        box-shadow: none;
        padding: 0;
      }
      .ssf-mermaid-card, table, pre, .ssf-alert {
        break-inside: avoid;
      }
    }
  </style>
</head>
<body class="ssf-body__SSF_TOC_CLASS__">
  <div class="ssf-layout">
    <aside class="ssf-sidebar" aria-label="Sommaire">
      <div class="ssf-sidebar-title">
        <span>Sommaire</span>
      </div>
      <ul id="ssf-toc-list"></ul>
    </aside>
    <main class="ssf-main">
      <div class="ssf-browser-bar">
        <button class="ssf-btn" type="button" onclick="window.ssfViewer.toggleToc()">Sommaire</button>
        <button class="ssf-btn" type="button" onclick="window.ssfViewer.toggleTheme()">Thème</button>
        <button class="ssf-btn" type="button" onclick="window.print()">Imprimer / PDF</button>
      </div>
      <article id="ssf-markdown-target" class="ssf-doc"></article>
    </main>
  </div>

  <script id="ssf-markdown-source" type="application/json">__SSF_MARKDOWN_JSON__</script>
  <script>__SSF_MARKED_JS__</script>
  <script>__SSF_HLJS_JS__</script>
  <script>__SSF_KATEX_JS__</script>
  <script>__SSF_KATEX_AUTO_JS__</script>
  <script>__SSF_MERMAID_JS__</script>
  <script>
    (function () {
      const sourceEl = document.getElementById('ssf-markdown-source');
      const targetEl = document.getElementById('ssf-markdown-target');
      const tocEl = document.getElementById('ssf-toc-list');
      const markdownText = sourceEl ? JSON.parse(sourceEl.textContent || '""') : '';

      function slugify(text) {
        return (text || '')
          .toLowerCase()
          .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
          .replace(/[^a-z0-9]+/g, '-')
          .replace(/^-+|-+$/g, '') || 'section';
      }

      function renderMarkdown() {
        if (typeof window.marked !== 'undefined') {
          window.marked.setOptions({ gfm: true, breaks: false });
          targetEl.innerHTML = window.marked.parse(markdownText);
        } else {
          const pre = document.createElement('pre');
          pre.textContent = markdownText;
          targetEl.appendChild(pre);
          return;
        }

        const alertTitles = {
          NOTE: 'Note',
          TIP: 'Astuce',
          IMPORTANT: 'Important',
          WARNING: 'Attention',
          CAUTION: 'Précaution'
        };
        targetEl.querySelectorAll('blockquote').forEach(function (bq) {
          const firstP = bq.querySelector('p');
          if (!firstP) return;
          const m = firstP.innerHTML.match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\](?:<br\s*\/?>|\s)*/i);
          if (!m) return;
          const kind = m[1].toUpperCase();
          firstP.innerHTML = firstP.innerHTML.slice(m[0].length);
          bq.classList.add('ssf-alert', 'ssf-alert-' + kind.toLowerCase());
          const titleDiv = document.createElement('div');
          titleDiv.className = 'ssf-alert-title';
          titleDiv.textContent = alertTitles[kind] || kind;
          bq.insertBefore(titleDiv, bq.firstChild);
        });

        let mermaidIndex = 0;
        targetEl.querySelectorAll('pre > code.language-mermaid').forEach(function (codeEl) {
          const preEl = codeEl.parentElement;
          const rawDiagram = codeEl.textContent || '';
          const card = document.createElement('div');
          card.className = 'ssf-mermaid-card';
          const bar = document.createElement('div');
          bar.className = 'ssf-mermaid-bar';
          bar.innerHTML = '<span><strong>Mermaid</strong> · Diagramme ' + (++mermaidIndex) + '</span>';
          const actions = document.createElement('div');
          actions.className = 'ssf-mermaid-actions';

          let zoom = 1.0;
          const stage = document.createElement('div');
          stage.className = 'ssf-mermaid-stage';
          const inner = document.createElement('div');
          inner.className = 'ssf-mermaid-inner';
          const diagramDiv = document.createElement('div');
          diagramDiv.className = 'mermaid';
          diagramDiv.setAttribute('data-mermaid-source', rawDiagram);
          diagramDiv.textContent = rawDiagram;
          inner.appendChild(diagramDiv);
          stage.appendChild(inner);

          function applyZoom(nextZoom) {
            zoom = Math.max(0.5, Math.min(2.4, nextZoom));
            inner.style.transform = 'scale(' + zoom.toFixed(2) + ')';
            resetBtn.textContent = Math.round(zoom * 100) + '%';
          }

          const minusBtn = document.createElement('button');
          minusBtn.type = 'button';
          minusBtn.className = 'ssf-btn';
          minusBtn.textContent = '−';
          minusBtn.onclick = function () { applyZoom(zoom - 0.15); };

          const resetBtn = document.createElement('button');
          resetBtn.type = 'button';
          resetBtn.className = 'ssf-btn';
          resetBtn.textContent = '100%';
          resetBtn.onclick = function () { applyZoom(1.0); };

          const plusBtn = document.createElement('button');
          plusBtn.type = 'button';
          plusBtn.className = 'ssf-btn';
          plusBtn.textContent = '+';
          plusBtn.onclick = function () { applyZoom(zoom + 0.15); };

          actions.appendChild(minusBtn);
          actions.appendChild(resetBtn);
          actions.appendChild(plusBtn);
          bar.appendChild(actions);
          card.appendChild(bar);
          card.appendChild(stage);
          preEl.replaceWith(card);
        });

        targetEl.querySelectorAll('pre > code').forEach(function (codeEl) {
          const preEl = codeEl.parentElement;
          const wrap = document.createElement('div');
          wrap.className = 'ssf-code-wrap';
          const langMatch = (codeEl.className || '').match(/language-([a-zA-Z0-9_-]+)/);
          if (langMatch) {
            const badge = document.createElement('span');
            badge.className = 'ssf-code-lang';
            badge.textContent = langMatch[1];
            wrap.appendChild(badge);
          }
          preEl.parentNode.insertBefore(wrap, preEl);
          wrap.appendChild(preEl);
          if (typeof window.hljs !== 'undefined') {
            try { window.hljs.highlightElement(codeEl); } catch (_) {}
          }
        });

        if (typeof window.renderMathInElement === 'function') {
          try {
            window.renderMathInElement(targetEl, {
              delimiters: [
                { left: '$$', right: '$$', display: true },
                { left: '$', right: '$', display: false },
                { left: '\\(', right: '\\)', display: false },
                { left: '\\[', right: '\\]', display: true }
              ],
              ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
              ignoredClasses: ['mermaid', 'ssf-mermaid-card'],
              throwOnError: false
            });
          } catch (_) {}
        }

        const usedSlugs = new Set();
        const headings = targetEl.querySelectorAll('h1, h2, h3, h4');
        tocEl.innerHTML = '';
        headings.forEach(function (h) {
          var base = slugify(h.textContent);
          var slug = base;
          var idx = 2;
          while (usedSlugs.has(slug)) { slug = base + '-' + (idx++); }
          usedSlugs.add(slug);
          h.id = slug;

          const li = document.createElement('li');
          const a = document.createElement('a');
          a.href = '#' + slug;
          a.textContent = h.textContent;
          a.setAttribute('data-level', h.tagName.substring(1));
          a.onclick = function (e) {
            e.preventDefault();
            h.scrollIntoView({ behavior: 'smooth', block: 'start' });
          };
          li.appendChild(a);
          tocEl.appendChild(li);
        });

        if (typeof IntersectionObserver !== 'undefined' && headings.length > 0) {
          const observer = new IntersectionObserver(function (entries) {
            entries.forEach(function (entry) {
              if (!entry.isIntersecting) return;
              const link = tocEl.querySelector('a[href="#' + entry.target.id + '"]');
              if (!link) return;
              tocEl.querySelectorAll('a.active').forEach(function (el) { el.classList.remove('active'); });
              link.classList.add('active');
            });
          }, { rootMargin: '-10% 0px -75% 0px' });
          headings.forEach(function (h) { observer.observe(h); });
        }
      }

      async function renderMermaid(themeName) {
        if (typeof window.mermaid === 'undefined') return;
        const nodes = targetEl.querySelectorAll('.mermaid[data-mermaid-source]');
        if (!nodes.length) return;
        nodes.forEach(function (el) {
          el.removeAttribute('data-processed');
          el.textContent = el.getAttribute('data-mermaid-source') || '';
        });
        try {
          window.mermaid.initialize({
            startOnLoad: false,
            theme: themeName === 'dark' ? 'dark' : 'default',
            securityLevel: 'strict'
          });
          await window.mermaid.run({ nodes: Array.from(nodes) });
        } catch (err) {
          nodes.forEach(function (el) {
            if (!el.querySelector('svg')) {
              el.innerHTML = '<div class="ssf-mermaid-error">Erreur de rendu Mermaid : ' +
                String(err) + '</div><pre>' +
                (el.getAttribute('data-mermaid-source') || '') + '</pre>';
            }
          });
        }
      }

      window.ssfViewer = {
        setTheme: function (themeName) {
          const isDark = themeName === 'dark';
          document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
          const lightStyle = document.getElementById('ssf-hljs-light');
          const darkStyle = document.getElementById('ssf-hljs-dark');
          if (lightStyle) lightStyle.media = isDark ? 'not all' : '';
          if (darkStyle) darkStyle.media = isDark ? '' : 'not all';
          renderMermaid(isDark ? 'dark' : 'light');
        },
        toggleTheme: function () {
          const curr = document.documentElement.getAttribute('data-theme') || 'light';
          window.ssfViewer.setTheme(curr === 'dark' ? 'light' : 'dark');
        },
        setTocVisible: function (visible) {
          document.body.classList.toggle('ssf-toc-hidden', !visible);
        },
        toggleToc: function () {
          document.body.classList.toggle('ssf-toc-hidden');
        }
      };

      renderMarkdown();
      renderMermaid('__SSF_THEME__');
    })();
  </script>
</body>
</html>
''';
}
