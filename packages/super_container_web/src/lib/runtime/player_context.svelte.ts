import { getContext, setContext } from 'svelte';
import type { Appearance, ComponentBehavior, EditorPageConfig } from '../models/types.js';
import { parseAppearanceExport } from '../models/codec.js';

const PLAYER_CONTEXT_KEY = Symbol('super_container_web.player_context');
const CONTENT_HOVER_KEY = Symbol('super_container_web.content_hover');

export class PlayerRuntimeState {
	appearance = $state<Appearance>(parseAppearanceExport({}));
	currentPath = $state<string>('/');
	zoneSizeOverrides = $state<Record<string, number>>({});
	navigateCallback?: (path: string) => void;

	constructor(initialAppearance: Appearance, initialPath = '/', onNavigate?: (path: string) => void) {
		this.appearance = initialAppearance;
		this.currentPath = initialPath;
		this.navigateCallback = onNavigate;
	}

	setAppearance(next: Appearance): void {
		this.appearance = next;
		this.zoneSizeOverrides = {};
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

	getGoToPageHref(slotId: string): string | undefined {
		const behaviors = this.getBehaviors(slotId);
		for (const b of behaviors) {
			if (b.trigger === 'click' && b.action.type === 'goToPage') {
				const target = (b.action as { pagePath?: string }).pagePath;
				if (target) return target;
			}
		}
		return undefined;
	}

	executeBehaviors(slotId: string, trigger = 'click'): boolean {
		const behaviors = this.getBehaviors(slotId).filter((b) => b.trigger === trigger);
		let handled = false;
		for (const b of behaviors) {
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
