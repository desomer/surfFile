import { getContext, setContext } from 'svelte';
import type {
	Appearance,
	BehaviorValidator,
	BehaviorValidatorOperator,
	BehaviorValueSource,
	ComponentBehavior,
	EditorPageConfig,
	ValueBehaviorValidator
} from '../models/types.js';
import {
	normalizeBehaviorEvent,
	normalizeValidatorOperator,
	parseAppearanceExport,
	resolveBehaviorValidatorShorthand
} from '../models/codec.js';
import type { JsonRepositoryStore } from '../services/json_repository.svelte.js';

const PLAYER_CONTEXT_KEY = Symbol('super_container_web.player_context');
const CONTENT_HOVER_KEY = Symbol('super_container_web.content_hover');

function isValueEmpty(value: unknown): boolean {
	if (value === null || value === undefined) return true;
	if (typeof value === 'string') return value.trim().length === 0;
	if (Array.isArray(value)) return value.length === 0;
	if (typeof value === 'object') {
		return Object.keys(value as Record<string, unknown>).length === 0;
	}
	return false;
}

function toFiniteNumber(value: unknown): number | null {
	if (typeof value === 'number') return Number.isFinite(value) ? value : null;
	if (typeof value === 'string') {
		const trimmed = value.trim();
		if (!trimmed) return null;
		const parsed = Number(trimmed);
		return Number.isFinite(parsed) ? parsed : null;
	}
	return null;
}

function areValuesEqual(actual: unknown, expected: unknown): boolean {
	if (actual === expected) return true;
	if (actual === null || actual === undefined || expected === null || expected === undefined) {
		return actual == null && expected == null;
	}
	if (typeof actual === 'number' || typeof expected === 'number') {
		const aNum = toFiniteNumber(actual);
		const bNum = toFiniteNumber(expected);
		if (aNum !== null && bNum !== null) return aNum === bNum;
	}
	if (typeof actual === 'boolean' && typeof expected === 'string') {
		return String(actual) === expected.trim().toLowerCase();
	}
	if (typeof expected === 'boolean' && typeof actual === 'string') {
		return actual.trim().toLowerCase() === String(expected);
	}
	if (typeof actual === 'object' && typeof expected === 'object') {
		try {
			return JSON.stringify(actual) === JSON.stringify(expected);
		} catch {
			return false;
		}
	}
	return false;
}

function resolveValueValidatorSpec(
	validator: ValueBehaviorValidator
): { source: BehaviorValueSource; operator: BehaviorValidatorOperator } | null {
	if (validator.type === 'value') {
		const rawSource = validator.source as string | undefined;
		const source: BehaviorValueSource | undefined =
			rawSource === undefined
				? 'self'
				: rawSource === 'other'
					? 'component'
					: rawSource === 'self' || rawSource === 'component' || rawSource === 'binding'
						? rawSource
						: undefined;
		const operator = normalizeValidatorOperator(validator.operator);
		if (!source || !operator) return null;
		return { source, operator };
	}
	const shorthand = resolveBehaviorValidatorShorthand(validator.type);
	if (shorthand) {
		return { source: shorthand.source, operator: shorthand.operator };
	}
	const operator = normalizeValidatorOperator(validator.operator);
	if (!operator) return null;
	return { source: validator.source ?? 'self', operator };
}

export class PlayerRuntimeState {
	appearance = $state<Appearance>(parseAppearanceExport({}));
	currentPath = $state<string>('/');
	zoneSizeOverrides = $state<Record<string, number>>({});
	componentValues = $state<Record<string, unknown>>({});
	navigateCallback?: (path: string) => void;
	repositoryStore?: JsonRepositoryStore;

	constructor(
		initialAppearance: Appearance,
		initialPath = '/',
		onNavigate?: (path: string) => void,
		repositoryStore?: JsonRepositoryStore
	) {
		this.appearance = initialAppearance;
		this.currentPath = initialPath;
		this.navigateCallback = onNavigate;
		this.repositoryStore = repositoryStore;
	}

	setAppearance(next: Appearance): void {
		this.appearance = next;
		this.zoneSizeOverrides = {};
		this.componentValues = {};
	}

	setComponentValue(id: string, value: unknown): void {
		if (this.componentValues[id] === value) return;
		this.componentValues[id] = value;
	}

	getComponentValue(id: string): unknown {
		return this.componentValues[id];
	}

	getZoneSize(layoutId: string, zone: string, fallback: number): number {
		const key = `${layoutId}:${zone}`;
		return this.zoneSizeOverrides[key] ?? fallback;
	}

	setZoneSize(layoutId: string, zone: string, size: number): void {
		const clamped = Math.max(20, Math.min(600, Math.round(size)));
		this.zoneSizeOverrides[`${layoutId}:${zone}`] = clamped;
	}

	resolveActivePage(path: string): { page: EditorPageConfig | null; rootSlotId: string } {
		const normalized = path.trim() || '/';
		const catalog = this.appearance.pageCatalog;
		const matched = catalog.pages.find((p) => p.path === normalized);
		if (matched) {
			const rootSlotId = this.appearance.components[matched.id] ? matched.id : 'root';
			return { page: matched, rootSlotId };
		}
		if (catalog.homePageId) {
			const home = catalog.pages.find((p) => p.id === catalog.homePageId) ?? null;
			const rootSlotId =
				home && this.appearance.components[home.id] ? home.id : 'root';
			return { page: home, rootSlotId };
		}
		if (catalog.pages.length > 0) {
			const first = catalog.pages[0];
			const rootSlotId = this.appearance.components[first.id] ? first.id : 'root';
			return { page: first, rootSlotId };
		}
		return { page: null, rootSlotId: 'root' };
	}

	getBehaviors(slotId: string): ComponentBehavior[] {
		return (this.appearance.behaviors[slotId] ?? []).filter((b) => b.enabled);
	}

	evaluateValidator(validator: BehaviorValidator | undefined, selfComponentId: string): boolean {
		if (!validator) return true;

		if (validator.type === 'all') {
			return validator.validators.every((child) =>
				this.evaluateValidator(child, selfComponentId)
			);
		}
		if (validator.type === 'any') {
			return validator.validators.some((child) =>
				this.evaluateValidator(child, selfComponentId)
			);
		}
		if (validator.type === 'not') {
			return !this.evaluateValidator(validator.validator, selfComponentId);
		}

		const spec = resolveValueValidatorSpec(validator);
		if (!spec) return false;

		const { source, operator } = spec;
		let actual: unknown;
		let targetId: string | undefined;

		if (source === 'self') {
			targetId = selfComponentId;
			actual = this.getComponentValue(selfComponentId);
		} else if (source === 'component') {
			targetId = validator.targetComponentId?.trim();
			if (!targetId) return false;
			actual = this.getComponentValue(targetId);
		} else {
			if (!validator.binding || !this.repositoryStore) {
				actual = undefined;
			} else {
				actual = this.repositoryStore.readBinding(validator.binding);
			}
		}

		const expected = validator.value;

		switch (operator) {
			case 'isEmpty':
				return isValueEmpty(actual);
			case 'isFill':
				return !isValueEmpty(actual);
			case 'isTrue':
				return (
					actual === true ||
					(typeof actual === 'string' && actual.trim().toLowerCase() === 'true')
				);
			case 'isFalse':
				return (
					actual === false ||
					(typeof actual === 'string' && actual.trim().toLowerCase() === 'false')
				);
			case 'equals':
				return areValuesEqual(actual, expected);
			case 'notEquals':
				return !areValuesEqual(actual, expected);
			case 'contains':
				if (Array.isArray(actual)) {
					return actual.some((item) => areValuesEqual(item, expected));
				}
				if (actual === null || actual === undefined || expected === null || expected === undefined) {
					return false;
				}
				return String(actual).includes(String(expected));
			case 'startsWith':
				if (actual === null || actual === undefined || expected === null || expected === undefined) {
					return false;
				}
				return String(actual).startsWith(String(expected));
			case 'greaterThan': {
				const aNum = toFiniteNumber(actual);
				const bNum = toFiniteNumber(expected);
				return aNum !== null && bNum !== null && aNum > bNum;
			}
			case 'lessThan': {
				const aNum = toFiniteNumber(actual);
				const bNum = toFiniteNumber(expected);
				return aNum !== null && bNum !== null && aNum < bNum;
			}
			case 'matchesRegex':
				if (typeof expected !== 'string' || !expected) return false;
				if (actual === null || actual === undefined) return false;
				try {
					return new RegExp(expected).test(String(actual));
				} catch {
					return false;
				}
			case 'isValid':
			case 'isInvalid': {
				const comp = targetId ? this.appearance.components[targetId] : undefined;
				const hasError = Boolean(comp && comp.type === 'value' && comp.field.errorText);
				return operator === 'isValid' ? !hasError : hasError;
			}
		}
	}

	getGoToPageHref(slotId: string, event = 'onTap'): string | undefined {
		const targetEvent = normalizeBehaviorEvent(event);
		const behaviors = this.getBehaviors(slotId);
		for (const b of behaviors) {
			const behaviorEvent = normalizeBehaviorEvent(b.event ?? b.trigger);
			if (behaviorEvent === targetEvent && b.action.type === 'goToPage') {
				const target = (b.action as { pagePath?: string }).pagePath;
				if (target) return target;
			}
		}
		return undefined;
	}

	executeBehaviors(slotId: string, event = 'onTap'): boolean {
		const targetEvent = normalizeBehaviorEvent(event);
		const behaviors = this.getBehaviors(slotId).filter(
			(b) => normalizeBehaviorEvent(b.event ?? b.trigger) === targetEvent
		);
		let handled = false;
		for (const b of behaviors) {
			if (!this.evaluateValidator(b.validator, slotId)) {
				continue;
			}
			if (b.action.type === 'goToPage') {
				const target = (b.action as { pagePath?: string }).pagePath || '/';
				this.currentPath = target;
				if (this.navigateCallback) {
					this.navigateCallback(target);
				}
				handled = true;
			}
		}
		return handled;
	}
}

export function setPlayerRuntimeContext(state: PlayerRuntimeState): PlayerRuntimeState {
	setContext(PLAYER_CONTEXT_KEY, state);
	return state;
}

export function getPlayerRuntimeContext(): PlayerRuntimeState {
	return getContext<PlayerRuntimeState>(PLAYER_CONTEXT_KEY);
}

export interface ContentHoverScope {
	readonly isHovered: boolean;
}

export function setContentHoverScope(getter: () => boolean): void {
	setContext<ContentHoverScope>(CONTENT_HOVER_KEY, {
		get isHovered() {
			return getter();
		}
	});
}

export function getContentHoverScope(): ContentHoverScope | undefined {
	return getContext<ContentHoverScope | undefined>(CONTENT_HOVER_KEY);
}
