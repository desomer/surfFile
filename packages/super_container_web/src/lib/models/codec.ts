import type {
	Appearance,
	AutomaticState,
	ComponentBehavior,
	ComponentConfig,
	ComponentStates,
	ContainerFill,
	ContainerStyle,
	CornerMerge,
	EditorPageCatalog,
	EditorPageConfig,
	GridLayoutConfig,
	GridSlotPosition,
	JsonTextBinding,
	NativeComponentConfig,
	NeonStyle,
	Quad,
	ScrollbarStyleConfig,
	ShadowSpec,
	SlotDimension,
	SlotPlacementRef,
	SlotSizeConstraints,
	SuperActionConfig,
	SuperLayoutConfig,
	SuperLayoutZone,
	SuperListViewConfig,
	SuperTabConfig,
	SuperTextFieldConfig,
	SuperValueConfig,
	SurfaceStyleStates,
	ThemeMode,
	TransformSpec,
	ZoneFlowConfig
} from './types.js';

const ALL_ZONES: SuperLayoutZone[] = [
	'nw',
	'north',
	'ne',
	'west',
	'center',
	'east',
	'sw',
	'south',
	'se'
];

const SLOT_CONSTRAINT_KEYS = new Set([
	'minWidth',
	'minHeight',
	'maxWidth',
	'maxHeight',
	'preferredWidth',
	'preferredHeight',
	'padding',
	'paddingInsets',
	'percentBasis',
	'fitContent',
	'flex'
]);

/**
 * Normalizes any Flutter/GenUI color representation (#RRGGBB, #AARRGGBB, #RGB, #ARGB, 0xAARRGGBB, or ARGB32 int)
 * into a standard CSS color string (#RRGGBB or rgba(r, g, b, a)).
 */
export function parseJsonColor(raw: unknown, fallback = '#5268D9'): string {
	if (raw === null || raw === undefined) return fallback;
	if (typeof raw === 'number' && Number.isFinite(raw)) {
		const unsigned = raw >>> 0;
		const a = (unsigned >>> 24) & 0xff;
		const r = (unsigned >>> 16) & 0xff;
		const g = (unsigned >>> 8) & 0xff;
		const b = unsigned & 0xff;
		if (a === 255) {
			return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`.toUpperCase();
		}
		return `rgba(${r}, ${g}, ${b}, ${Number((a / 255).toFixed(3))})`;
	}
	if (typeof raw === 'string') {
		let s = raw.trim();
		if (!s) return fallback;
		if (s.startsWith('rgba(') || s.startsWith('rgb(') || s.startsWith('hsl(')) {
			return s;
		}
		if (s.startsWith('0x') || s.startsWith('0X')) {
			s = '#' + s.slice(2);
		}
		if (s.startsWith('#')) {
			const hex = s.slice(1);
			if (hex.length === 3) {
				const r = hex[0] + hex[0];
				const g = hex[1] + hex[1];
				const b = hex[2] + hex[2];
				return `#${r}${g}${b}`.toUpperCase();
			}
			if (hex.length === 4) {
				const a = parseInt(hex[0] + hex[0], 16);
				const r = parseInt(hex[1] + hex[1], 16);
				const g = parseInt(hex[2] + hex[2], 16);
				const b = parseInt(hex[3] + hex[3], 16);
				if (a === 255) {
					return `#${hex[1]}${hex[1]}${hex[2]}${hex[2]}${hex[3]}${hex[3]}`.toUpperCase();
				}
				return `rgba(${r}, ${g}, ${b}, ${Number((a / 255).toFixed(3))})`;
			}
			if (hex.length === 6) {
				return `#${hex.toUpperCase()}`;
			}
			if (hex.length === 8) {
				// Flutter/GenUI uses #AARRGGBB
				const a = parseInt(hex.slice(0, 2), 16);
				const r = parseInt(hex.slice(2, 4), 16);
				const g = parseInt(hex.slice(4, 6), 16);
				const b = parseInt(hex.slice(6, 8), 16);
				if (a === 255) {
					return `#${hex.slice(2).toUpperCase()}`;
				}
				return `rgba(${r}, ${g}, ${b}, ${Number((a / 255).toFixed(3))})`;
			}
		}
	}
	return fallback;
}

export function parseOptionalColor(raw: unknown): string | undefined {
	if (raw === null || raw === undefined || raw === '') return undefined;
	return parseJsonColor(raw, '');
}

export function parseQuad(raw: unknown): Quad | undefined {
	if (Array.isArray(raw) && raw.length === 4 && raw.every((n) => typeof n === 'number')) {
		return [raw[0], raw[1], raw[2], raw[3]];
	}
	if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
		const obj = raw as Record<string, unknown>;
		if ('top' in obj || 'left' in obj || 'right' in obj || 'bottom' in obj) {
			return [
				Number(obj.top ?? 0),
				Number(obj.right ?? 0),
				Number(obj.bottom ?? 0),
				Number(obj.left ?? 0)
			];
		}
		if ('topLeft' in obj || 'topRight' in obj || 'bottomRight' in obj || 'bottomLeft' in obj) {
			return [
				Number(obj.topLeft ?? 0),
				Number(obj.topRight ?? 0),
				Number(obj.bottomRight ?? 0),
				Number(obj.bottomLeft ?? 0)
			];
		}
	}
	return undefined;
}

export function parseSlotDimension(raw: unknown): SlotDimension | undefined {
	if (raw === null || raw === undefined) return undefined;
	if (typeof raw === 'number' && Number.isFinite(raw)) {
		return { value: raw, unit: 'px' };
	}
	if (typeof raw === 'string') {
		const trimmed = raw.trim();
		if (trimmed.endsWith('%')) {
			const val = parseFloat(trimmed.slice(0, -1));
			if (Number.isFinite(val)) return { value: val, unit: 'percent' };
		}
		if (trimmed.toLowerCase().endsWith('px')) {
			const val = parseFloat(trimmed.slice(0, -2));
			if (Number.isFinite(val)) return { value: val, unit: 'px' };
		}
		const val = parseFloat(trimmed);
		if (Number.isFinite(val)) return { value: val, unit: 'px' };
	}
	if (raw && typeof raw === 'object') {
		const obj = raw as Record<string, unknown>;
		const val = Number(obj.value);
		if (Number.isFinite(val)) {
			const unit = obj.unit === 'percent' || obj.unit === '%' ? 'percent' : 'px';
			return { value: val, unit };
		}
	}
	return undefined;
}

export function parseJsonTextBinding(raw: unknown): JsonTextBinding | undefined {
	if (!raw) return undefined;
	if (typeof raw === 'string') {
		const trimmed = raw.trim();
		if (!trimmed) return undefined;
		const colonIdx = trimmed.indexOf(':');
		if (colonIdx === 32 && /^[0-9a-fA-F]{32}$/.test(trimmed.slice(0, 32))) {
			return {
				repositoryId: trimmed.slice(0, 32).toLowerCase(),
				path: trimmed.slice(33).trim()
			};
		}
		return { path: trimmed };
	}
	if (typeof raw === 'object') {
		const obj = raw as Record<string, unknown>;
		const path = typeof obj.path === 'string' ? obj.path.trim() : '';
		if (!path) return undefined;
		const repositoryId =
			typeof obj.repositoryId === 'string' && obj.repositoryId.trim()
				? obj.repositoryId.trim()
				: undefined;
		return { repositoryId, path };
	}
	return undefined;
}

export function parsePropertyBindings(raw: unknown): Record<string, JsonTextBinding> {
	if (!raw || typeof raw !== 'object') return {};
	const result: Record<string, JsonTextBinding> = {};
	for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
		const parsed = parseJsonTextBinding(v);
		if (parsed) result[k] = parsed;
	}
	return result;
}

export function isDirectConstraintsMap(raw: unknown): boolean {
	if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return false;
	const entries = Object.entries(raw as Record<string, unknown>);
	if (entries.length === 0) return false;
	return (
		entries.every(([k]) => SLOT_CONSTRAINT_KEYS.has(k)) &&
		entries.some(
			([, v]) =>
				typeof v !== 'object' ||
				v === null ||
				Array.isArray(v) ||
				'value' in (v as Record<string, unknown>) ||
				'unit' in (v as Record<string, unknown>)
		)
	);
}

export function parseSlotSizeConstraints(raw: unknown): SlotSizeConstraints {
	const obj = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
	let fitContent: boolean | undefined =
		typeof obj.fitContent === 'boolean' ? obj.fitContent : undefined;
	if (fitContent === undefined && typeof obj.flex === 'number') {
		fitContent = obj.flex === 0;
	}
	const paddingInsets = parseQuad(obj.paddingInsets) ?? parseQuad(obj.padding);
	const padding = typeof obj.padding === 'number' ? obj.padding : 0;
	return {
		minWidth: parseSlotDimension(obj.minWidth),
		minHeight: parseSlotDimension(obj.minHeight),
		maxWidth: parseSlotDimension(obj.maxWidth),
		maxHeight: parseSlotDimension(obj.maxHeight),
		preferredWidth: parseSlotDimension(obj.preferredWidth),
		preferredHeight: parseSlotDimension(obj.preferredHeight),
		padding,
		paddingInsets,
		percentBasis: obj.percentBasis === 'layout' ? 'layout' : 'zone',
		fitContent
	};
}

export function parseSlotSizeConstraintsMap(
	raw: unknown,
	placedIds: string[] = []
): Record<string, SlotSizeConstraints> {
	if (!raw || typeof raw !== 'object') return {};
	if (isDirectConstraintsMap(raw)) {
		if (placedIds.length === 1) {
			return { [placedIds[0]]: parseSlotSizeConstraints(raw) };
		}
		return {};
	}
	const result: Record<string, SlotSizeConstraints> = {};
	for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
		if (v && typeof v === 'object') {
			result[k] = parseSlotSizeConstraints(v);
		}
	}
	return result;
}

export function parseContainerFill(raw: unknown): ContainerFill {
	const obj = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
	const type =
		obj.type === 'linear' || obj.type === 'radial' || obj.type === 'sweep' ? obj.type : 'solid';
	return {
		type,
		start: parseJsonColor(obj.start, '#5268D9'),
		end: parseJsonColor(obj.end, '#B794F4'),
		angle: typeof obj.angle === 'number' ? obj.angle : 45,
		radius: typeof obj.radius === 'number' ? obj.radius : 0.8,
		imageUrl: typeof obj.imageUrl === 'string' && obj.imageUrl.trim() ? obj.imageUrl.trim() : undefined,
		imageFit: (obj.imageFit as ContainerFill['imageFit']) ?? 'cover',
		imageOpacity: typeof obj.imageOpacity === 'number' ? obj.imageOpacity : 1,
		imageBinding: parseJsonTextBinding(obj.imageBinding)
	};
}

export function parseShadowSpec(raw: unknown): ShadowSpec | undefined {
	if (!raw || typeof raw !== 'object') return undefined;
	const obj = raw as Record<string, unknown>;
	return {
		enabled: obj.enabled !== false,
		color: parseJsonColor(obj.color, '#000000'),
		opacity: typeof obj.opacity === 'number' ? obj.opacity : 0.15,
		blur: typeof obj.blur === 'number' ? obj.blur : 16,
		spread: typeof obj.spread === 'number' ? obj.spread : 0,
		dx: typeof obj.dx === 'number' ? obj.dx : 0,
		dy: typeof obj.dy === 'number' ? obj.dy : 8
	};
}

export function parseNeonStyle(raw: unknown): NeonStyle | undefined {
	if (raw === true) {
		return { enabled: true, intensity: 0.6 };
	}
	if (!raw || typeof raw !== 'object') return undefined;
	const obj = raw as Record<string, unknown>;
	return {
		enabled: obj.enabled !== false,
		color: parseOptionalColor(obj.color),
		intensity: typeof obj.intensity === 'number' ? obj.intensity : 0.6
	};
}

export function parseTransformSpec(raw: unknown): TransformSpec | undefined {
	if (!raw || typeof raw !== 'object') return undefined;
	const obj = raw as Record<string, unknown>;
	return {
		dx: typeof obj.dx === 'number' ? obj.dx : 0,
		dy: typeof obj.dy === 'number' ? obj.dy : 0,
		rotation: typeof obj.rotation === 'number' ? obj.rotation : 0,
		scale: typeof obj.scale === 'number' ? obj.scale : 1
	};
}

export function parseContainerStyle(raw: unknown): ContainerStyle {
	const obj = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
	const radii = parseQuad(obj.radii) ?? parseQuad(obj.radius);
	const borderWidths = parseQuad(obj.borderWidths) ?? parseQuad(obj.borderWidth);
	const paddingInsets = parseQuad(obj.paddingInsets) ?? parseQuad(obj.padding);
	const marginInsets = parseQuad(obj.marginInsets) ?? parseQuad(obj.margin);

	let states: SurfaceStyleStates | undefined;
	if (obj.states && typeof obj.states === 'object') {
		const stObj = obj.states as Record<string, unknown>;
		const named: Record<string, Partial<ContainerStyle>> = {};
		const automatic: Partial<Record<AutomaticState, Partial<ContainerStyle>>> = {};
		const autoKeys = new Set<AutomaticState>([
			'hover',
			'pressed',
			'focused',
			'selected',
			'disabled',
			'empty',
			'error',
			'contentHover'
		]);
		if (stObj.named && typeof stObj.named === 'object') {
			for (const [k, v] of Object.entries(stObj.named as Record<string, unknown>)) {
				if (v && typeof v === 'object') named[k] = parsePartialContainerStyle(v as Record<string, unknown>);
			}
		}
		const autoSource =
			stObj.automatic && typeof stObj.automatic === 'object'
				? (stObj.automatic as Record<string, unknown>)
				: stObj;
		for (const [k, v] of Object.entries(autoSource)) {
			const normalizedKey = k === 'hovered' ? 'hover' : k;
			if (autoKeys.has(normalizedKey as AutomaticState) && v && typeof v === 'object') {
				automatic[normalizedKey as AutomaticState] = parsePartialContainerStyle(
					v as Record<string, unknown>
				);
			}
		}
		states = {
			activeState: typeof stObj.activeState === 'string' ? stObj.activeState : undefined,
			named,
			automatic
		};
	}

	return {
		color: parseOptionalColor(obj.color),
		fill: parseContainerFill(obj.fill),
		radius: typeof obj.radius === 'number' ? obj.radius : 0,
		borderWidth: typeof obj.borderWidth === 'number' ? obj.borderWidth : 0,
		borderColor: parseOptionalColor(obj.borderColor),
		elevation: typeof obj.elevation === 'number' ? obj.elevation : 0,
		shadowOpacity: typeof obj.shadowOpacity === 'number' ? obj.shadowOpacity : 0.2,
		neon: parseNeonStyle(obj.neon),
		padding: typeof obj.padding === 'number' ? obj.padding : 0,
		margin: typeof obj.margin === 'number' ? obj.margin : 0,
		designSystem:
			obj.designSystem === 'neumorphism' || obj.designSystem === 'liquidGlass'
				? obj.designSystem
				: 'material',
		interactionEffect:
			obj.interactionEffect === 'none' ||
			obj.interactionEffect === 'scale' ||
			obj.interactionEffect === 'glow'
				? obj.interactionEffect
				: 'ripple',
		hoverEffect: Boolean(obj.hoverEffect),
		hoverTint:
			obj.hoverTint === 'accent' || obj.hoverTint === 'custom' ? obj.hoverTint : 'material',
		hoverColor: parseOptionalColor(obj.hoverColor),
		radii,
		borderWidths,
		borderLine:
			obj.borderLine === 'dashed' || obj.borderLine === 'dotted' ? obj.borderLine : 'solid',
		shadow: parseShadowSpec(obj.shadow),
		innerShadow: parseShadowSpec(obj.innerShadow),
		opacity: typeof obj.opacity === 'number' ? obj.opacity : 1,
		paddingInsets,
		marginInsets,
		backdropBlur: typeof obj.backdropBlur === 'number' ? obj.backdropBlur : undefined,
		pattern:
			obj.pattern === 'grain' || obj.pattern === 'lines' || obj.pattern === 'dots'
				? obj.pattern
				: 'none',
		patternOpacity: typeof obj.patternOpacity === 'number' ? obj.patternOpacity : 0.1,
		transform: parseTransformSpec(obj.transform),
		propertyBindings: parsePropertyBindings(obj.propertyBindings),
		states
	};
}

export function parsePartialContainerStyle(raw: Record<string, unknown>): Partial<ContainerStyle> {
	const full = parseContainerStyle(raw);
	const partial: Partial<ContainerStyle> = {};
	if ('color' in raw) partial.color = full.color;
	if ('fill' in raw) partial.fill = full.fill;
	if ('radius' in raw) partial.radius = full.radius;
	if ('radii' in raw) partial.radii = full.radii;
	if ('borderWidth' in raw) partial.borderWidth = full.borderWidth;
	if ('borderWidths' in raw) partial.borderWidths = full.borderWidths;
	if ('borderColor' in raw) partial.borderColor = full.borderColor;
	if ('borderLine' in raw) partial.borderLine = full.borderLine;
	if ('elevation' in raw) partial.elevation = full.elevation;
	if ('shadowOpacity' in raw) partial.shadowOpacity = full.shadowOpacity;
	if ('shadow' in raw) partial.shadow = full.shadow;
	if ('innerShadow' in raw) partial.innerShadow = full.innerShadow;
	if ('neon' in raw) partial.neon = full.neon;
	if ('padding' in raw) partial.padding = full.padding;
	if ('paddingInsets' in raw) partial.paddingInsets = full.paddingInsets;
	if ('margin' in raw) partial.margin = full.margin;
	if ('marginInsets' in raw) partial.marginInsets = full.marginInsets;
	if ('opacity' in raw) partial.opacity = full.opacity;
	if ('backdropBlur' in raw) partial.backdropBlur = full.backdropBlur;
	if ('designSystem' in raw) partial.designSystem = full.designSystem;
	if ('pattern' in raw) partial.pattern = full.pattern;
	if ('patternOpacity' in raw) partial.patternOpacity = full.patternOpacity;
	if ('transform' in raw) partial.transform = full.transform;
	return partial;
}

export function parseZoneFlowConfig(raw: unknown): ZoneFlowConfig {
	const obj = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
	let scrollbarStyle: ScrollbarStyleConfig | undefined;
	if (obj.scrollbarStyle && typeof obj.scrollbarStyle === 'object') {
		const sb = obj.scrollbarStyle as Record<string, unknown>;
		scrollbarStyle = {
			thumbVisibility: sb.thumbVisibility !== false,
			trackVisibility: Boolean(sb.trackVisibility),
			interactive: sb.interactive !== false,
			thickness: typeof sb.thickness === 'number' ? sb.thickness : 8,
			radius: typeof sb.radius === 'number' ? sb.radius : 4,
			mainAxisMargin: typeof sb.mainAxisMargin === 'number' ? sb.mainAxisMargin : 0,
			crossAxisMargin: typeof sb.crossAxisMargin === 'number' ? sb.crossAxisMargin : 0,
			thumbColor: parseOptionalColor(sb.thumbColor),
			trackColor: parseOptionalColor(sb.trackColor),
			trackBorderColor: parseOptionalColor(sb.trackBorderColor),
			side: sb.side === 'start' || sb.side === 'end' ? sb.side : 'auto'
		};
	}
	return {
		scrollable: Boolean(obj.scrollable),
		showScrollbar: Boolean(obj.showScrollbar),
		scrollbarStyle,
		expandSlots: obj.expandSlots !== false,
		mainAxisAlignment: (obj.mainAxisAlignment as ZoneFlowConfig['mainAxisAlignment']) ?? 'start',
		crossAxisAlignment:
			(obj.crossAxisAlignment as ZoneFlowConfig['crossAxisAlignment']) ?? 'stretch',
		spacing: typeof obj.spacing === 'number' ? obj.spacing : 0,
		padding: typeof obj.padding === 'number' ? obj.padding : 0,
		paddingInsets: parseQuad(obj.paddingInsets) ?? parseQuad(obj.padding)
	};
}

export function parsePlacementList(
	raw: unknown,
	slotTypesFallback: Record<string, string>
): SlotPlacementRef[] {
	if (!Array.isArray(raw)) return [];
	const list: SlotPlacementRef[] = [];
	for (const entry of raw) {
		if (typeof entry === 'string' && entry.trim()) {
			const id = entry.trim();
			list.push({ id, type: slotTypesFallback[id] ?? 'registry:Layout' });
		} else if (entry && typeof entry === 'object') {
			const e = entry as Record<string, unknown>;
			const id = typeof e.id === 'string' ? e.id.trim() : '';
			const type =
				typeof e.type === 'string' && e.type.trim()
					? e.type.trim()
					: (slotTypesFallback[id] ?? 'registry:Layout');
			if (id) list.push({ id, type });
		}
	}
	return list;
}

/**
 * Resolves collisions and optionally compacts items vertically, matching Dart's GridLayoutConfig.arrange().
 */
export function arrangeGridItems(
	config: GridLayoutConfig,
	activeId?: string
): Record<string, GridSlotPosition> {
	const entries = Object.entries(config.items).map(([k, v]) => [k, { ...v }] as const);
	entries.sort(([idA, a], [idB, b]) => {
		if (idA === activeId) return -1;
		if (idB === activeId) return 1;
		return a.y !== b.y ? a.y - b.y : a.x - b.x;
	});

	const overlaps = (a: GridSlotPosition, b: GridSlotPosition) =>
		a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;

	const result: Record<string, GridSlotPosition> = {};
	for (const [id, pos] of entries) {
		const p = { ...pos };
		p.x = Math.max(0, Math.min(p.x, Math.max(0, config.columns - p.width)));
		while (true) {
			const colliding = Object.values(result).filter((other) => overlaps(p, other));
			if (colliding.length === 0) break;
			p.y = Math.max(...colliding.map((o) => o.y + o.height));
		}
		result[id] = p;
	}

	if (config.compact) {
		const orderedIds = Object.keys(result).sort((a, b) => {
			const pa = result[a];
			const pb = result[b];
			return pa.y !== pb.y ? pa.y - pb.y : pa.x - pb.x;
		});
		for (const id of orderedIds) {
			const p = result[id];
			while (p.y > 0) {
				const candidate = { ...p, y: p.y - 1 };
				const hasCollision = Object.entries(result).some(
					([otherId, other]) => otherId !== id && overlaps(candidate, other)
				);
				if (hasCollision) break;
				p.y -= 1;
			}
		}
	}

	return result;
}

export function parseGridLayoutConfig(raw: unknown, placedIds: string[] = []): GridLayoutConfig {
	const obj = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
	const columns = typeof obj.columns === 'number' ? Math.max(1, Math.min(48, obj.columns)) : 12;
	const rowHeight = typeof obj.rowHeight === 'number' ? obj.rowHeight : 64;
	const gap = typeof obj.gap === 'number' ? obj.gap : 8;
	const compact = obj.compact !== false;
	const items: Record<string, GridSlotPosition> = {};

	if (obj.items && typeof obj.items === 'object') {
		for (const [k, v] of Object.entries(obj.items as Record<string, unknown>)) {
			if (v && typeof v === 'object') {
				const p = v as Record<string, unknown>;
				const width = Math.max(1, Math.min(columns, Number(p.width ?? 4)));
				const height = Math.max(1, Number(p.height ?? 3));
				const x = Math.max(0, Math.min(columns - width, Number(p.x ?? 0)));
				const y = Math.max(0, Number(p.y ?? 0));
				items[k] = { x, y, width, height };
			}
		}
	}

	// Synchronize missing placedIds
	let nextX = 0;
	let nextY = 0;
	for (const id of placedIds) {
		if (!items[id]) {
			const width = Math.min(4, columns);
			if (nextX + width > columns) {
				nextX = 0;
				nextY += 3;
			}
			items[id] = { x: nextX, y: nextY, width, height: 3 };
			nextX += width;
		}
	}

	const base: GridLayoutConfig = { columns, rowHeight, gap, compact, items };
	return { ...base, items: arrangeGridItems(base) };
}

export function parseSuperLayoutConfig(raw: Record<string, unknown>): SuperLayoutConfig {
	const slotTypes: Record<string, string> = {};
	if (raw.slotTypes && typeof raw.slotTypes === 'object') {
		for (const [k, v] of Object.entries(raw.slotTypes as Record<string, unknown>)) {
			if (typeof v === 'string') slotTypes[k] = v;
		}
	}

	const placements: Partial<Record<SuperLayoutZone, SlotPlacementRef[]>> = {};
	const placedIds: string[] = [];
	if (raw.placements && typeof raw.placements === 'object') {
		for (const zone of ALL_ZONES) {
			const zoneRaw = (raw.placements as Record<string, unknown>)[zone];
			const list = parsePlacementList(zoneRaw, slotTypes);
			if (list.length > 0) {
				placements[zone] = list;
				for (const item of list) {
					slotTypes[item.id] = item.type;
					placedIds.push(item.id);
				}
			}
		}
	}

	const autoSides: SuperLayoutZone[] = Array.isArray(raw.autoSides)
		? (raw.autoSides.filter((z) => typeof z === 'string') as SuperLayoutZone[])
		: ['north', 'south', 'east', 'west'];

	const zoneAxes: Partial<Record<SuperLayoutZone, 'row' | 'column'>> = {};
	if (raw.zoneAxes && typeof raw.zoneAxes === 'object') {
		for (const [z, axis] of Object.entries(raw.zoneAxes as Record<string, unknown>)) {
			zoneAxes[z as SuperLayoutZone] =
				axis === 'row' || axis === 'horizontal' ? 'row' : 'column';
		}
	}

	const zoneFlows: Partial<Record<SuperLayoutZone, ZoneFlowConfig>> = {};
	if (raw.zoneFlows && typeof raw.zoneFlows === 'object') {
		for (const [z, flow] of Object.entries(raw.zoneFlows as Record<string, unknown>)) {
			zoneFlows[z as SuperLayoutZone] = parseZoneFlowConfig(flow);
		}
	}

	const corner = (v: unknown): CornerMerge =>
		v === 'row' || v === 'column' ? v : 'none';

	const positioning = raw.positioning === 'grid' ? 'grid' : 'zones';

	return {
		type: 'layout',
		label: typeof raw.label === 'string' ? raw.label : undefined,
		positioning,
		north: Boolean(raw.north),
		south: Boolean(raw.south),
		west: Boolean(raw.west),
		east: Boolean(raw.east),
		nw: corner(raw.nw),
		ne: corner(raw.ne),
		sw: corner(raw.sw),
		se: corner(raw.se),
		northSize: typeof raw.northSize === 'number' ? raw.northSize : 50,
		southSize: typeof raw.southSize === 'number' ? raw.southSize : 50,
		westSize: typeof raw.westSize === 'number' ? raw.westSize : 100,
		eastSize: typeof raw.eastSize === 'number' ? raw.eastSize : 100,
		resizeSides: Boolean(raw.resizeSides),
		sideResizing:
			raw.sideResizing && typeof raw.sideResizing === 'object'
				? (raw.sideResizing as Partial<Record<SuperLayoutZone, boolean>>)
				: {},
		collapsedSides: Array.isArray(raw.collapsedSides)
			? (raw.collapsedSides as SuperLayoutZone[])
			: [],
		autoSides,
		placements,
		slotTypes,
		slotPreferredSizes: parsePreferredSizesMap(raw.slotPreferredSizes),
		slotSizeConstraints: parseSlotSizeConstraintsMap(raw.slotSizeConstraints, placedIds),
		zoneAxes,
		zoneFlows,
		slotLabels: parseStringMap(raw.slotLabels),
		grid:
			positioning === 'grid' || raw.grid
				? parseGridLayoutConfig(raw.grid, placedIds)
				: undefined
	};
}

function parsePreferredSizesMap(raw: unknown): Record<string, [number | null, number | null]> {
	if (!raw || typeof raw !== 'object') return {};
	const res: Record<string, [number | null, number | null]> = {};
	for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
		if (Array.isArray(v) && v.length >= 2) {
			res[k] = [
				typeof v[0] === 'number' ? v[0] : null,
				typeof v[1] === 'number' ? v[1] : null
			];
		} else if (v && typeof v === 'object') {
			const o = v as Record<string, unknown>;
			res[k] = [
				typeof o.width === 'number' ? o.width : null,
				typeof o.height === 'number' ? o.height : null
			];
		}
	}
	return res;
}

function parseStringMap(raw: unknown): Record<string, string> {
	if (!raw || typeof raw !== 'object') return {};
	const res: Record<string, string> = {};
	for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
		if (typeof v === 'string') res[k] = v;
	}
	return res;
}

export function parseNativeComponentConfig(
	raw: Record<string, unknown>,
	kind: 'native' | 'scaffold' = 'native'
): NativeComponentConfig {
	const reserved = new Set([
		'type',
		'componentType',
		'binding',
		'regions',
		'regionAxes',
		'regionFlows',
		'regionSizes',
		'placements',
		'slotTypes',
		'slotPreferredSizes',
		'slotSizeConstraints',
		'slotLabels'
	]);
	const properties: Record<string, unknown> = {};
	for (const [k, v] of Object.entries(raw)) {
		if (!reserved.has(k)) {
			properties[k] = v;
		}
	}

	const slotTypes = parseStringMap(raw.slotTypes);
	const placements: Record<string, SlotPlacementRef[]> = {};
	const placedIds: string[] = [];
	if (raw.placements && typeof raw.placements === 'object') {
		for (const [region, listRaw] of Object.entries(raw.placements as Record<string, unknown>)) {
			const list = parsePlacementList(listRaw, slotTypes);
			placements[region] = list;
			for (const item of list) {
				slotTypes[item.id] = item.type;
				placedIds.push(item.id);
			}
		}
	}

	const regions: Record<string, boolean> = {};
	if (raw.regions && typeof raw.regions === 'object') {
		for (const [r, active] of Object.entries(raw.regions as Record<string, unknown>)) {
			regions[r] = Boolean(active);
		}
	}

	const regionAxes: Record<string, 'horizontal' | 'vertical' | 'row' | 'column'> = {};
	if (raw.regionAxes && typeof raw.regionAxes === 'object') {
		for (const [r, ax] of Object.entries(raw.regionAxes as Record<string, unknown>)) {
			if (ax === 'horizontal' || ax === 'vertical' || ax === 'row' || ax === 'column') {
				regionAxes[r] = ax;
			}
		}
	}

	const regionFlows: Record<string, ZoneFlowConfig> = {};
	if (raw.regionFlows && typeof raw.regionFlows === 'object') {
		for (const [r, fl] of Object.entries(raw.regionFlows as Record<string, unknown>)) {
			regionFlows[r] = parseZoneFlowConfig(fl);
		}
	}

	const regionSizes: Record<string, number> = {};
	if (raw.regionSizes && typeof raw.regionSizes === 'object') {
		for (const [r, sz] of Object.entries(raw.regionSizes as Record<string, unknown>)) {
			if (typeof sz === 'number' && Number.isFinite(sz)) regionSizes[r] = sz;
		}
	}

	return {
		type: kind,
		binding: parseJsonTextBinding(raw.binding),
		properties,
		regions,
		regionAxes,
		regionFlows,
		regionSizes,
		placements,
		slotTypes,
		slotPreferredSizes: parsePreferredSizesMap(raw.slotPreferredSizes),
		slotSizeConstraints: parseSlotSizeConstraintsMap(raw.slotSizeConstraints, placedIds),
		slotLabels: parseStringMap(raw.slotLabels)
	};
}

export function parseSuperTextFieldConfig(raw: unknown): SuperTextFieldConfig {
	const obj = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
	return {
		variant:
			obj.variant === 'filled' || obj.variant === 'underlined' || obj.variant === 'bare'
				? obj.variant
				: 'outlined',
		dense: Boolean(obj.dense),
		prefixIcon: typeof obj.prefixIcon === 'string' ? obj.prefixIcon : undefined,
		suffixIcon: typeof obj.suffixIcon === 'string' ? obj.suffixIcon : undefined,
		prefixText: typeof obj.prefixText === 'string' ? obj.prefixText : undefined,
		suffixText: typeof obj.suffixText === 'string' ? obj.suffixText : undefined,
		helperText: typeof obj.helperText === 'string' ? obj.helperText : undefined,
		errorText: typeof obj.errorText === 'string' ? obj.errorText : undefined,
		showCounter: Boolean(obj.showCounter),
		maxLength: typeof obj.maxLength === 'number' ? obj.maxLength : undefined,
		clearButton: Boolean(obj.clearButton),
		obscureToggle: Boolean(obj.obscureToggle),
		fillColor: parseOptionalColor(obj.fillColor),
		borderColor: parseOptionalColor(obj.borderColor),
		focusedBorderColor: parseOptionalColor(obj.focusedBorderColor),
		radius: typeof obj.radius === 'number' ? obj.radius : undefined,
		borderWidth: typeof obj.borderWidth === 'number' ? obj.borderWidth : undefined,
		contentPadding: parseQuad(obj.contentPadding)
	};
}

function parseComponentStates<T>(
	raw: unknown,
	patchParser: (obj: Record<string, unknown>) => Partial<T>
): ComponentStates<T> | undefined {
	if (!raw || typeof raw !== 'object') return undefined;
	const stObj = raw as Record<string, unknown>;
	const named: Record<string, Partial<T>> = {};
	const automatic: Partial<Record<AutomaticState, Partial<T>>> = {};
	const autoKeys = new Set<AutomaticState>([
		'hover',
		'pressed',
		'focused',
		'selected',
		'disabled',
		'empty',
		'error',
		'contentHover'
	]);
	if (stObj.named && typeof stObj.named === 'object') {
		for (const [k, v] of Object.entries(stObj.named as Record<string, unknown>)) {
			if (v && typeof v === 'object') named[k] = patchParser(v as Record<string, unknown>);
		}
	}
	const autoSource =
		stObj.automatic && typeof stObj.automatic === 'object'
			? (stObj.automatic as Record<string, unknown>)
			: stObj;
	for (const [k, v] of Object.entries(autoSource)) {
		const normalizedKey = k === 'hovered' ? 'hover' : k;
		if (autoKeys.has(normalizedKey as AutomaticState) && v && typeof v === 'object') {
			automatic[normalizedKey as AutomaticState] = patchParser(v as Record<string, unknown>);
		}
	}
	return {
		activeState: typeof stObj.activeState === 'string' ? stObj.activeState : undefined,
		named,
		automatic
	};
}

export function parseSuperValueConfig(raw: Record<string, unknown>): SuperValueConfig {
	const kindRaw = raw.kind;
	const kind =
		kindRaw === 'checkbox'
			? 'checkbox'
			: kindRaw === 'switch' || kindRaw === 'switchControl'
				? 'switchControl'
				: 'text';
	const initialText =
		typeof raw.text === 'string'
			? raw.text
			: typeof raw.initialText === 'string'
				? raw.initialText
				: '';
	const initialBool =
		typeof raw.value === 'boolean'
			? raw.value
			: typeof raw.initialBool === 'boolean'
				? raw.initialBool
				: false;
	return {
		type: 'value',
		mode: raw.mode === 'input' ? 'input' : 'display',
		kind,
		initialText,
		initialBool,
		label: typeof raw.label === 'string' ? raw.label : '',
		placeholder: typeof raw.placeholder === 'string' ? raw.placeholder : '',
		enabled: raw.enabled !== false,
		readOnly: Boolean(raw.readOnly),
		obscureText: Boolean(raw.obscureText),
		minLines: typeof raw.minLines === 'number' ? Math.max(1, raw.minLines) : 1,
		maxLines: typeof raw.maxLines === 'number' ? Math.max(1, raw.maxLines) : 1,
		fontFamily: typeof raw.fontFamily === 'string' ? raw.fontFamily : undefined,
		fontSize: typeof raw.fontSize === 'number' ? raw.fontSize : undefined,
		fontWeight:
			typeof raw.fontWeight === 'number' || typeof raw.fontWeight === 'string'
				? raw.fontWeight
				: undefined,
		italic: typeof raw.italic === 'boolean' ? raw.italic : undefined,
		color: parseOptionalColor(raw.color),
		textAlign: (raw.textAlign as SuperValueConfig['textAlign']) ?? 'start',
		lineHeight: typeof raw.lineHeight === 'number' ? raw.lineHeight : undefined,
		letterSpacing: typeof raw.letterSpacing === 'number' ? raw.letterSpacing : undefined,
		binding: parseJsonTextBinding(raw.binding),
		propertyBindings: parsePropertyBindings(raw.propertyBindings),
		field: parseSuperTextFieldConfig(raw.field),
		states: parseComponentStates(raw.states, (o) => {
			const p = parseSuperValueConfig(o);
			const res: Partial<SuperValueConfig> = {};
			if ('color' in o) res.color = p.color;
			if ('fontSize' in o) res.fontSize = p.fontSize;
			if ('fontWeight' in o) res.fontWeight = p.fontWeight;
			if ('italic' in o) res.italic = p.italic;
			if ('label' in o) res.label = p.label;
			if ('text' in o || 'initialText' in o) res.initialText = p.initialText;
			return res;
		})
	};
}

export function parseSuperActionConfig(raw: Record<string, unknown>): SuperActionConfig {
	const kind =
		raw.kind === 'icon' || raw.kind === 'textAndIcon' ? raw.kind : 'text';
	const variant = (raw.variant as SuperActionConfig['variant']) ?? 'filled';
	const label =
		typeof raw.label === 'string'
			? raw.label
			: typeof raw.text === 'string'
				? raw.text
				: 'Action';
	return {
		type: 'action',
		kind,
		variant,
		label,
		tooltip: typeof raw.tooltip === 'string' ? raw.tooltip : '',
		icon: typeof raw.icon === 'string' && raw.icon.trim() ? raw.icon.trim() : 'touch_app',
		iconPosition: raw.iconPosition === 'trailing' ? 'trailing' : 'leading',
		iconSize: typeof raw.iconSize === 'number' ? raw.iconSize : undefined,
		iconSpacing: typeof raw.iconSpacing === 'number' ? raw.iconSpacing : 8,
		enabled: raw.enabled !== false,
		fontFamily: typeof raw.fontFamily === 'string' ? raw.fontFamily : undefined,
		fontSize: typeof raw.fontSize === 'number' ? raw.fontSize : undefined,
		fontWeight:
			typeof raw.fontWeight === 'number' || typeof raw.fontWeight === 'string'
				? raw.fontWeight
				: undefined,
		italic: typeof raw.italic === 'boolean' ? raw.italic : undefined,
		color: parseOptionalColor(raw.color),
		iconColor: parseOptionalColor(raw.iconColor),
		backgroundColor: parseOptionalColor(raw.backgroundColor),
		borderColor: parseOptionalColor(raw.borderColor),
		radius: typeof raw.radius === 'number' ? raw.radius : undefined,
		borderWidth: typeof raw.borderWidth === 'number' ? raw.borderWidth : undefined,
		elevation: typeof raw.elevation === 'number' ? raw.elevation : undefined,
		horizontalPadding: typeof raw.horizontalPadding === 'number' ? raw.horizontalPadding : undefined,
		verticalPadding: typeof raw.verticalPadding === 'number' ? raw.verticalPadding : undefined,
		textAlign: (raw.textAlign as SuperActionConfig['textAlign']) ?? 'center',
		letterSpacing: typeof raw.letterSpacing === 'number' ? raw.letterSpacing : undefined,
		style: raw.style && typeof raw.style === 'object' ? parseContainerStyle(raw.style) : undefined,
		propertyBindings: parsePropertyBindings(raw.propertyBindings),
		states: parseComponentStates(raw.states, (o) => {
			const p = parseSuperActionConfig(o);
			const res: Partial<SuperActionConfig> = {};
			if ('label' in o || 'text' in o) res.label = p.label;
			if ('icon' in o) res.icon = p.icon;
			if ('color' in o) res.color = p.color;
			if ('iconColor' in o) res.iconColor = p.iconColor;
			if ('backgroundColor' in o) res.backgroundColor = p.backgroundColor;
			if ('borderColor' in o) res.borderColor = p.borderColor;
			if ('radius' in o) res.radius = p.radius;
			if ('elevation' in o) res.elevation = p.elevation;
			return res;
		})
	};
}

export function parseSuperListViewConfig(raw: Record<string, unknown>): SuperListViewConfig {
	const templateRaw =
		(raw.template && typeof raw.template === 'object'
			? raw.template
			: raw.row && typeof raw.row === 'object'
				? raw.row
				: {}) as Record<string, unknown>;
	return {
		type: 'list',
		binding: parseJsonTextBinding(raw.binding),
		axis: raw.axis === 'horizontal' ? 'horizontal' : 'vertical',
		wrap: Boolean(raw.wrap),
		wrapSizing: raw.wrapSizing === 'automatic' ? 'automatic' : 'fixed',
		itemWidth: typeof raw.itemWidth === 'number' ? raw.itemWidth : 160,
		itemExtent: typeof raw.itemExtent === 'number' ? raw.itemExtent : 56,
		spacing: typeof raw.spacing === 'number' ? raw.spacing : 0,
		allowAdd: Boolean(raw.allowAdd),
		allowRemove: Boolean(raw.allowRemove),
		emptyText: typeof raw.emptyText === 'string' ? raw.emptyText : 'Aucun élément',
		itemId: typeof raw.itemId === 'string' && raw.itemId.trim() ? raw.itemId.trim() : undefined,
		template: parseSuperLayoutConfig(templateRaw)
	};
}

export function parseSuperTabConfig(raw: Record<string, unknown>): SuperTabConfig {
	const slotTypes = parseStringMap(raw.slotTypes);
	const placements: Record<string, SlotPlacementRef[]> = {};
	const placedIds: string[] = [];
	if (raw.placements && typeof raw.placements === 'object') {
		for (const [zone, listRaw] of Object.entries(raw.placements as Record<string, unknown>)) {
			const list = parsePlacementList(listRaw, slotTypes);
			placements[zone] = list;
			for (const item of list) {
				slotTypes[item.id] = item.type;
				placedIds.push(item.id);
			}
		}
	}
	return {
		type: 'tab',
		mode: raw.mode === 'dynamic' ? 'dynamic' : 'static',
		binding: parseJsonTextBinding(raw.binding),
		tabBarPosition: raw.tabBarPosition === 'bottom' ? 'bottom' : 'top',
		isScrollable: Boolean(raw.isScrollable),
		initialIndex: typeof raw.initialIndex === 'number' ? Math.max(0, raw.initialIndex) : 0,
		tabAlignment: raw.tabAlignment as SuperTabConfig['tabAlignment'],
		tabBarStyle: parseContainerStyle(raw.tabBarStyle),
		indicatorKind:
			raw.indicatorKind === 'box' || raw.indicatorKind === 'none'
				? raw.indicatorKind
				: 'underline',
		indicatorSize: raw.indicatorSize === 'label' ? 'label' : 'tab',
		indicatorColor: parseOptionalColor(raw.indicatorColor),
		indicatorWeight: typeof raw.indicatorWeight === 'number' ? raw.indicatorWeight : 2,
		indicatorRadius: typeof raw.indicatorRadius === 'number' ? raw.indicatorRadius : 0,
		indicatorHorizontalPadding:
			typeof raw.indicatorHorizontalPadding === 'number' ? raw.indicatorHorizontalPadding : 0,
		indicatorVerticalPadding:
			typeof raw.indicatorVerticalPadding === 'number' ? raw.indicatorVerticalPadding : 0,
		labelColor: parseOptionalColor(raw.labelColor),
		unselectedLabelColor: parseOptionalColor(raw.unselectedLabelColor),
		dividerColor: parseOptionalColor(raw.dividerColor),
		dividerHeight: typeof raw.dividerHeight === 'number' ? raw.dividerHeight : 1,
		allowAdd: Boolean(raw.allowAdd),
		allowRemove: Boolean(raw.allowRemove),
		emptyText: typeof raw.emptyText === 'string' ? raw.emptyText : 'Aucun onglet',
		placements,
		slotTypes,
		slotSizeConstraints: parseSlotSizeConstraintsMap(raw.slotSizeConstraints, placedIds),
		slotLabels: parseStringMap(raw.slotLabels)
	};
}

export function parseComponentConfig(raw: Record<string, unknown>): ComponentConfig {
	const rawType = String(raw.type ?? raw.componentType ?? 'layout').trim();
	switch (rawType) {
		case 'layout':
			return parseSuperLayoutConfig(raw);
		case 'native':
			return parseNativeComponentConfig(raw, 'native');
		case 'scaffold':
			return parseNativeComponentConfig(raw, 'scaffold');
		case 'value':
			return parseSuperValueConfig(raw);
		case 'action':
			return parseSuperActionConfig(raw);
		case 'list':
			return parseSuperListViewConfig(raw);
		case 'tab':
			return parseSuperTabConfig(raw);
		default: {
			const known =
				rawType === 'table' || rawType === 'treeView' || rawType === 'chart'
					? rawType
					: 'unknown';
			return { type: known, rawType, raw };
		}
	}
}

export function parseComponentBehavior(raw: unknown): ComponentBehavior | undefined {
	if (!raw || typeof raw !== 'object') return undefined;
	const obj = raw as Record<string, unknown>;
	const actionRaw =
		obj.action && typeof obj.action === 'object' ? (obj.action as Record<string, unknown>) : {};
	const actionType = typeof actionRaw.type === 'string' ? actionRaw.type.trim() : 'goToPage';
	if (actionType === 'goToPage') {
		return {
			id: typeof obj.id === 'string' ? obj.id : 'behavior',
			trigger: typeof obj.trigger === 'string' ? obj.trigger : 'click',
			enabled: obj.enabled !== false,
			action: {
				type: 'goToPage',
				pagePath: String(actionRaw.pagePath ?? actionRaw.path ?? '/').trim() || '/',
				pageId: typeof actionRaw.pageId === 'string' ? actionRaw.pageId : undefined,
				pageName: typeof actionRaw.pageName === 'string' ? actionRaw.pageName : undefined
			}
		};
	}
	return {
		id: typeof obj.id === 'string' ? obj.id : 'behavior',
		trigger: typeof obj.trigger === 'string' ? obj.trigger : 'click',
		enabled: obj.enabled !== false,
		action: { ...actionRaw, type: actionType }
	};
}

export function parseEditorPageCatalog(raw: unknown): EditorPageCatalog {
	if (!raw || typeof raw !== 'object') return { pages: [], homePageId: null };
	const obj = raw as Record<string, unknown>;
	const pages: EditorPageConfig[] = [];
	if (Array.isArray(obj.pages)) {
		for (const item of obj.pages) {
			if (item && typeof item === 'object') {
				const p = item as Record<string, unknown>;
				const id = typeof p.id === 'string' ? p.id.trim() : '';
				const name = typeof p.name === 'string' ? p.name.trim() : id;
				const path = typeof p.path === 'string' && p.path.startsWith('/') ? p.path.trim() : `/${id}`;
				if (id) {
					pages.push({
						id,
						name,
						path,
						defaultParameters: parseStringMap(p.defaultParameters)
					});
				}
			}
		}
	}
	const homePageId = typeof obj.homePageId === 'string' ? obj.homePageId : null;
	return { pages, homePageId };
}

/**
 * Parses an AppearanceTransfer export envelope (`{ format, version, groups, data }`)
 * or a flat GenUI `Appearance` JSON document into a strongly-typed `Appearance` object.
 */
export function parseAppearanceExport(input: string | Record<string, unknown>): Appearance {
	const root: Record<string, unknown> =
		typeof input === 'string' ? (JSON.parse(input) as Record<string, unknown>) : input;

	const data: Record<string, unknown> =
		root.data && typeof root.data === 'object' && !Array.isArray(root.data)
			? (root.data as Record<string, unknown>)
			: root;

	const mode: ThemeMode =
		data.mode === 'dark' || data.mode === 'system' ? data.mode : 'light';
	const accent = parseJsonColor(data.accent, '#5268D9');

	const styles: Record<string, ContainerStyle> = {};
	if (data.styles && typeof data.styles === 'object') {
		for (const [id, st] of Object.entries(data.styles as Record<string, unknown>)) {
			if (st && typeof st === 'object') {
				styles[id] = parseContainerStyle(st);
			}
		}
	}

	const selfConstraints: Record<string, SlotSizeConstraints> = {};
	const components: Record<string, ComponentConfig> = {};
	if (data.components && typeof data.components === 'object') {
		for (const [id, compRaw] of Object.entries(data.components as Record<string, unknown>)) {
			if (!compRaw || typeof compRaw !== 'object') continue;
			const compObj = { ...(compRaw as Record<string, unknown>) };
			if (isDirectConstraintsMap(compObj.slotSizeConstraints)) {
				selfConstraints[id] = parseSlotSizeConstraints(compObj.slotSizeConstraints);
				delete compObj.slotSizeConstraints;
			}
			components[id] = parseComponentConfig(compObj);
		}
	}

	// Attach extracted selfConstraints to parent containers that place the slot
	for (const [slotId, constraints] of Object.entries(selfConstraints)) {
		for (const comp of Object.values(components)) {
			if (comp.type === 'layout') {
				const placed = Object.values(comp.placements).some((list) =>
					list?.some((item) => item.id === slotId)
				);
				if (placed) {
					comp.slotSizeConstraints[slotId] = constraints;
				}
			} else if (comp.type === 'native' || comp.type === 'scaffold') {
				const placed = Object.values(comp.placements).some((list) =>
					list?.some((item) => item.id === slotId)
				);
				if (placed) {
					comp.slotSizeConstraints[slotId] = constraints;
				}
			}
		}
	}

	const behaviors: Record<string, ComponentBehavior[]> = {};
	if (data.behaviors && typeof data.behaviors === 'object') {
		for (const [id, bList] of Object.entries(data.behaviors as Record<string, unknown>)) {
			if (Array.isArray(bList)) {
				behaviors[id] = bList
					.map(parseComponentBehavior)
					.filter((b): b is ComponentBehavior => b !== undefined);
			}
		}
	}

	return {
		version: typeof root.version === 'number' ? root.version : 1,
		mode,
		accent,
		backgroundOpacity: typeof data.backgroundOpacity === 'number' ? data.backgroundOpacity : 1,
		windowOpacity: typeof data.windowOpacity === 'number' ? data.windowOpacity : 1,
		windowEffect: typeof data.windowEffect === 'string' ? data.windowEffect : 'transparent',
		styles,
		components,
		behaviors,
		pageCatalog: parseEditorPageCatalog(data.pageCatalog),
		cardHeight: typeof data.cardHeight === 'number' ? data.cardHeight : 92,
		cardWidth: typeof data.cardWidth === 'number' ? data.cardWidth : 220,
		rowHeight: typeof data.rowHeight === 'number' ? data.rowHeight : 44,
		spacing: typeof data.spacing === 'number' ? data.spacing : 12,
		fontSize: typeof data.fontSize === 'number' ? data.fontSize : 14,
		iconSize: typeof data.iconSize === 'number' ? data.iconSize : 20,
		scrollFadeEnabled: data.scrollFadeEnabled !== false,
		scrollFadeExtent: typeof data.scrollFadeExtent === 'number' ? data.scrollFadeExtent : 28
	};
}

/**
 * Extracts all distinct 32-hex repositoryIds referenced in an Appearance document.
 */
export function extractReferencedRepositoryIds(appearance: Appearance): string[] {
	const ids = new Set<string>();
	const visit = (val: unknown) => {
		if (!val) return;
		if (typeof val === 'object') {
			const obj = val as Record<string, unknown>;
			if (typeof obj.repositoryId === 'string' && obj.repositoryId.trim()) {
				ids.add(obj.repositoryId.trim());
			}
			for (const child of Object.values(obj)) {
				visit(child);
			}
		}
	};
	visit(appearance.components);
	visit(appearance.styles);
	return Array.from(ids);
}
