import { describe, expect, it } from 'vitest';
import {
	arrangeGridItems,
	extractReferencedRepositoryIds,
	parseAppearanceExport,
	parseJsonColor,
	parseSlotDimension
} from '../src/lib/models/codec.js';
import {
	appendArrayItem,
	countWildcards,
	readJsonPath,
	removeArrayItem,
	resolvePath,
	writeJsonPath
} from '../src/lib/services/json_path.js';
import {
	buildContainerStyleCss,
	buildSlotConstraintsCss,
	resolveEffectiveContainerStyle
} from '../src/lib/styles/container_style_css.js';
import { DEFAULT_EXPORT_JSON, DEFAULT_REPOSITORIES, DEFAULT_REPOSITORY_ID } from '../src/lib/data/default_showcase.js';

describe('JSON Codec & Primitives Normalization', () => {
	it('normalizes #RRGGBB, #AARRGGBB, and ARGB32 integers', () => {
		expect(parseJsonColor('#5268D9')).toBe('#5268D9');
		expect(parseJsonColor('#FF5268D9')).toBe('#5268D9');
		expect(parseJsonColor('#80FFFFFF')).toContain('rgba(255, 255, 255');
		expect(parseJsonColor(0xff5268d9)).toBe('#5268D9');
	});

	it('parses SlotDimension in px and percent', () => {
		expect(parseSlotDimension('240px')).toEqual({ value: 240, unit: 'px' });
		expect(parseSlotDimension('50%')).toEqual({ value: 50, unit: 'percent' });
		expect(parseSlotDimension(64)).toEqual({ value: 64, unit: 'px' });
	});

	it('parses full AppearanceTransfer export and extracts repository IDs', () => {
		const appearance = parseAppearanceExport(DEFAULT_EXPORT_JSON);
		expect(appearance.pageCatalog.pages.length).toBe(2);
		expect(appearance.components.mainLayout.type).toBe('layout');
		expect(extractReferencedRepositoryIds(appearance)).toContain(DEFAULT_REPOSITORY_ID);
	});

	it('arranges 2D Grid items without collisions and compacts vertically', () => {
		const arranged = arrangeGridItems({
			columns: 12,
			rowHeight: 64,
			gap: 8,
			compact: true,
			items: {
				a: { x: 0, y: 2, width: 6, height: 2 },
				b: { x: 0, y: 2, width: 6, height: 2 }
			}
		});
		expect(arranged.a.y).toBe(0);
		expect(arranged.b.y).toBe(2);
	});
});

describe('JsonAttributePath & Wildcard [?] Resolution', () => {
	const sampleDoc = DEFAULT_REPOSITORIES[DEFAULT_REPOSITORY_ID].data;

	it('counts and resolves nested [?] wildcards from scope and master-detail selection', () => {
		expect(countWildcards('clients[?].commandes[?].ref')).toBe(2);

		// First wildcard from enclosing scope [1], second from selected row map
		const res = resolvePath('clients[?].commandes[?].ref', [1], {
			'clients[1].commandes': 0
		});
		expect(res.isResolved).toBe(true);
		expect(res.resolvedPath).toBe('clients[1].commandes[0].ref');
		expect(readJsonPath(sampleDoc, res.resolvedPath)).toBe('CMD-2026-02');
	});

	it('immutably updates, appends, and removes JSON values', () => {
		const updated = writeJsonPath(sampleDoc, 'clients[0].nom', 'Atelier Lumière International');
		expect(readJsonPath(updated, 'clients[0].nom')).toBe('Atelier Lumière International');
		expect(readJsonPath(sampleDoc, 'clients[0].nom')).toBe('Atelier Lumière SAS');

		const withAdded = appendArrayItem(sampleDoc, 'clients[0].commandes');
		const listAfterAdd = readJsonPath(withAdded, 'clients[0].commandes') as unknown[];
		expect(listAfterAdd.length).toBe(3);

		const withRemoved = removeArrayItem(withAdded, 'clients[0].commandes', 0);
		const listAfterRemove = readJsonPath(withRemoved, 'clients[0].commandes') as unknown[];
		expect(listAfterRemove.length).toBe(2);
	});
});

describe('ContainerStyle CSS Generator', () => {
	it('generates CSS for Material, LiquidGlass, Neumorphism, and state overrides', () => {
		const appearance = parseAppearanceExport(DEFAULT_EXPORT_JSON);
		const listRowStyle = appearance.styles['list-clients:item'];
		const selectedStyle = resolveEffectiveContainerStyle(listRowStyle, new Set(['selected']));
		expect(selectedStyle.color).toBe('#EEF1FF');
		expect(selectedStyle.borderWidth).toBe(2);

		const css = buildContainerStyleCss(appearance.styles['kpi-ca']);
		expect(css).toContain('backdrop-filter: blur(16px)');
		expect(css).toContain('border-radius: 16px');

		const constraintsCss = buildSlotConstraintsCss(
			{
				padding: 8,
				percentBasis: 'zone',
				preferredHeight: { value: 64, unit: 'px' },
				fitContent: true
			},
			undefined,
			true,
			'column'
		);
		expect(constraintsCss).toContain('height: 64px');
		expect(constraintsCss).toContain('flex: 0 0 auto');
	});
});
