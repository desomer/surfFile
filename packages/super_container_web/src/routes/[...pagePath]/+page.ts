import type { EntryGenerator } from './$types.js';
import { parseAppearanceExport } from '$lib/models/codec.js';
import { DEFAULT_EXPORT_JSON } from '$lib/data/default_showcase.js';

export const prerender = true;

export const entries: EntryGenerator = () => {
	const appearance = parseAppearanceExport(DEFAULT_EXPORT_JSON);
	const routes = appearance.pageCatalog.pages.map((p) => ({
		pagePath: p.path.replace(/^\/+/, '')
	}));
	if (!routes.some((r) => r.pagePath === '')) {
		routes.unshift({ pagePath: '' });
	}
	return routes;
};

export function load({ params }) {
	const raw = params.pagePath ?? '';
	const currentPath = raw ? `/${raw.replace(/^\/+/, '')}` : '/';
	return {
		currentPath
	};
}
