import { describe, expect, it } from 'vitest';
import {
	arrangeGridItems,
	extractReferencedRepositoryIds,
	normalizeBehaviorEvent,
	parseAppearanceExport,
	parseBehaviorValidator,
	parseComponentBehavior,
	parseJsonColor,
	parseSlotDimension
} from '../src/lib/models/codec.js';
import { PlayerRuntimeState } from '../src/lib/runtime/player_context.svelte.js';
import { JsonRepositoryStore } from '../src/lib/services/json_repository.svelte.js';
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

describe('ComponentBehavior Event Normalization & Validators', () => {
	it('normalizes legacy triggers and preserves canonical behavior events', () => {
		expect(normalizeBehaviorEvent('click')).toBe('onTap');
		expect(normalizeBehaviorEvent('doubleClick')).toBe('onDoubleTap');
		expect(normalizeBehaviorEvent('hover')).toBe('onHover');
		expect(normalizeBehaviorEvent('binding')).toBe('onBinding');
		expect(normalizeBehaviorEvent('create')).toBe('onCreate');
		expect(normalizeBehaviorEvent('onTap')).toBe('onTap');
		expect(normalizeBehaviorEvent('onSelected')).toBe('onSelected');
		expect(normalizeBehaviorEvent('onChanged')).toBe('onChanged');
		expect(normalizeBehaviorEvent(undefined)).toBe('onTap');
	});

	it('parses legacy trigger, canonical event, and nested validators', () => {
		const legacy = parseComponentBehavior({
			id: 'b-legacy',
			trigger: 'click',
			action: { type: 'goToPage', pagePath: '/details' }
		});
		expect(legacy?.event).toBe('onTap');
		expect(legacy?.trigger).toBe('onTap');

		const composite = parseComponentBehavior({
			id: 'b-guarded',
			event: 'onTap',
			validator: {
				type: 'all',
				validators: [
					{ type: 'isNotEmpty' },
					{ type: 'otherIsFilled', targetComponentId: 'email' },
					{
						type: 'not',
						validator: {
							type: 'value',
							source: 'component',
							operator: 'equals',
							targetComponentId: 'status',
							value: 'archived'
						}
					}
				]
			},
			action: { type: 'goToPage', pagePath: '/confirm' }
		});

		expect(composite?.event).toBe('onTap');
		expect(composite?.validator?.type).toBe('all');
		if (composite?.validator?.type === 'all') {
			expect(composite.validator.validators).toHaveLength(3);
			expect(composite.validator.validators[0]).toMatchObject({
				type: 'isFill',
				source: 'self',
				operator: 'isFill'
			});
			expect(composite.validator.validators[1]).toMatchObject({
				type: 'otherIsFill',
				source: 'component',
				operator: 'isFill',
				targetComponentId: 'email'
			});
		}

		expect(parseBehaviorValidator({ type: 'otherIsFill' })).toBeUndefined();
		expect(parseBehaviorValidator({ type: 'bindingIsFill' })).toBeUndefined();
	});

	it('evaluates validators and gates executeBehaviors in PlayerRuntimeState', () => {
		const navigated: string[] = [];
		const repoStore = new JsonRepositoryStore({
			[DEFAULT_REPOSITORY_ID]: { flags: { allowed: true } }
		});
		const appearance = parseAppearanceExport({
			behaviors: {
				'btn-submit': [
					{
						id: 'go-next',
						event: 'onTap',
						validator: {
							type: 'all',
							validators: [
								{ type: 'otherIsFill', targetComponentId: 'input-email' },
								{
									type: 'otherMatchesRegex',
									targetComponentId: 'input-email',
									value: '^[^@]+@[^@]+\\.[^@]+$'
								},
								{
									type: 'otherGreaterThan',
									targetComponentId: 'input-age',
									value: 17
								},
								{
									type: 'bindingIsTrue',
									binding: { repositoryId: DEFAULT_REPOSITORY_ID, path: 'flags.allowed' }
								}
							]
						},
						action: { type: 'goToPage', pagePath: '/done' }
					}
				],
				'row-item': [
					{
						id: 'select-nav',
						event: 'onSelected',
						action: { type: 'goToPage', pagePath: '/details' }
					}
				]
			}
		});

		const player = new PlayerRuntimeState(
			appearance,
			'/',
			(p) => navigated.push(p),
			repoStore
		);

		expect(player.getGoToPageHref('btn-submit', 'click')).toBe('/done');
		expect(player.getGoToPageHref('row-item', 'onSelected')).toBe('/details');

		// Blocked while fields are empty/invalid
		expect(player.executeBehaviors('btn-submit', 'click')).toBe(false);
		expect(navigated).toEqual([]);

		player.setComponentValue('input-email', 'alice@example.com');
		player.setComponentValue('input-age', '25');
		expect(player.getComponentValue('input-email')).toBe('alice@example.com');

		// Passes once validators are satisfied
		expect(player.executeBehaviors('btn-submit', 'onTap')).toBe(true);
		expect(navigated).toEqual(['/done']);
		expect(player.currentPath).toBe('/done');

		// Additional operator checks
		player.setComponentValue('self-comp', 'hello world');
		expect(player.evaluateValidator({ type: 'contains', value: 'world' }, 'self-comp')).toBe(
			true
		);
		expect(player.evaluateValidator({ type: 'startsWith', value: 'hello' }, 'self-comp')).toBe(
			true
		);
		expect(player.evaluateValidator({ type: 'notEquals', value: 'bye' }, 'self-comp')).toBe(true);
		expect(
			player.evaluateValidator(
				{
					type: 'any',
					validators: [
						{ type: 'isEmpty' },
						{ type: 'otherLessThan', targetComponentId: 'input-age', value: 30 }
					]
				},
				'self-comp'
			)
		).toBe(true);

		player.setComponentValue('flag', false);
		expect(player.evaluateValidator({ type: 'isFalse' }, 'flag')).toBe(true);
		expect(player.evaluateValidator({ type: 'isTrue' }, 'flag')).toBe(false);
		expect(
			player.evaluateValidator({ type: 'not', validator: { type: 'isTrue' } }, 'flag')
		).toBe(true);

		// Selection event execution
		expect(player.executeBehaviors('row-item', 'onSelected')).toBe(true);
		expect(player.currentPath).toBe('/details');
	});
});
