import { parseAppearanceExport } from '$lib/models/codec.js';
import { DEFAULT_EXPORT_JSON, DEFAULT_REPOSITORIES } from '$lib/data/default_showcase.js';

export const ssr = true;

export function load() {
	const appearance = parseAppearanceExport(DEFAULT_EXPORT_JSON);
	return {
		appearance,
		repositories: DEFAULT_REPOSITORIES
	};
}
