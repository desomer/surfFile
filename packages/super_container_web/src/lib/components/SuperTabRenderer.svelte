<script lang="ts">
	import type { SuperActionConfig, SuperTabConfig } from '$lib/models/types.js';
	import {
		getJsonListScopeContext,
		getRepositoryStoreContext
	} from '$lib/services/json_repository.svelte.js';
	import { getPlayerRuntimeContext } from '$lib/runtime/player_context.svelte.js';
	import { buildContainerStyleCss } from '$lib/styles/container_style_css.js';
	import ZoneFlowContainer from './ZoneFlowContainer.svelte';
	import SuperListRowScope from './SuperListRowScope.svelte';

	interface Props {
		id: string;
		config: SuperTabConfig;
	}

	let { id, config }: Props = $props();

	const player = getPlayerRuntimeContext();
	const repoStore = getRepositoryStoreContext();
	const parentScope = getJsonListScopeContext();

	let selectedTabOverride = $state<number | null>(null);
	const activeIndex = $derived(selectedTabOverride ?? (config.initialIndex || 0));

	const staticTabs = $derived(config.placements.tabs ?? []);
	const dynamicItems = $derived.by(() => {
		if (config.mode !== 'dynamic' || !config.binding || !repoStore) return [] as unknown[];
		const v = repoStore.readBinding(config.binding, parentScope);
		return Array.isArray(v) ? v : [];
	});

	const tabCount = $derived(config.mode === 'dynamic' ? dynamicItems.length : staticTabs.length);
	const clampedIndex = $derived(
		tabCount > 0 ? Math.max(0, Math.min(activeIndex, tabCount - 1)) : 0
	);

	function selectTab(idx: number) {
		selectedTabOverride = idx;
		if (config.mode === 'static' && config.binding && repoStore) {
			repoStore.writeBinding(config.binding, idx, parentScope);
		} else if (config.mode === 'dynamic' && config.binding && repoStore) {
			const resolved = repoStore.resolveBinding(config.binding, parentScope);
			if (resolved?.isResolved) {
				repoStore.selectRow(resolved.repositoryId, resolved.resolvedPath, idx);
			}
		}
	}

	function getTabAction(slotId: string): SuperActionConfig | null {
		const comp = player.appearance.components[slotId];
		return comp && comp.type === 'action' ? comp : null;
	}

	const tabBarCss = $derived(
		buildContainerStyleCss(config.tabBarStyle, {
			accent: player.appearance.accent,
			mode: player.appearance.mode
		})
	);
	const indicatorColor = $derived(config.indicatorColor ?? player.appearance.accent);
	const activeLabelColor = $derived(config.labelColor ?? player.appearance.accent);
	const inactiveLabelColor = $derived(config.unselectedLabelColor ?? '#68738D');
</script>

{#snippet tabBar()}
	<div
		class="sc-tabbar"
		class:scrollable={config.isScrollable}
		style="{tabBarCss}; border-bottom: {config.dividerHeight}px solid {config.dividerColor ?? 'rgba(0,0,0,0.08)'};"
		role="tablist"
	>
		{#if config.mode === 'static'}
			{#each staticTabs as tabRef, idx (tabRef.id)}
				{@const act = getTabAction(tabRef.id)}
				{@const isSelected = idx === clampedIndex}
				<button
					type="button"
					role="tab"
					aria-selected={isSelected}
					class="sc-tab-btn"
					class:selected={isSelected}
					class:indicator-box={isSelected && config.indicatorKind === 'box'}
					class:indicator-underline={isSelected && config.indicatorKind === 'underline'}
					style="color: {isSelected ? activeLabelColor : inactiveLabelColor}; --ind-color: {indicatorColor}; --ind-weight: {config.indicatorWeight}px; --ind-radius: {config.indicatorRadius}px;"
					onclick={() => selectTab(idx)}
				>
					{#if act && (act.kind === 'icon' || act.kind === 'textAndIcon')}
						<span class="material-icons" style="font-size: 18px;">{act.icon}</span>
					{/if}
					<span>{act?.label ?? tabRef.id}</span>
				</button>
			{/each}
		{:else}
			{@const templateTabRef = staticTabs[0]}
			{@const templateAct = templateTabRef ? getTabAction(templateTabRef.id) : null}
			{#each dynamicItems as _, idx (idx)}
				{@const isSelected = idx === clampedIndex}
				<button
					type="button"
					role="tab"
					aria-selected={isSelected}
					class="sc-tab-btn"
					class:selected={isSelected}
					class:indicator-underline={isSelected && config.indicatorKind === 'underline'}
					style="color: {isSelected ? activeLabelColor : inactiveLabelColor}; --ind-color: {indicatorColor}; --ind-weight: {config.indicatorWeight}px;"
					onclick={() => selectTab(idx)}
				>
					<span>{templateAct?.label ?? `Onglet ${idx + 1}`}</span>
				</button>
			{/each}
		{/if}
	</div>
{/snippet}

<div class="sc-tabs-container" data-component-id={id}>
	{#if config.tabBarPosition === 'top'}
		{@render tabBar()}
	{/if}

	<div class="sc-tab-view" role="tabpanel">
		{#if config.mode === 'static'}
			{@const currentTab = staticTabs[clampedIndex]}
			{#if currentTab}
				{@const contentPlacements = config.placements[`content:${currentTab.id}`] ?? []}
				<ZoneFlowContainer
					placements={contentPlacements}
					axis="column"
					slotSizeConstraints={config.slotSizeConstraints}
					defaultExpandSlots={true}
				/>
			{/if}
		{:else if dynamicItems.length === 0}
			<div class="sc-tab-empty">{config.emptyText}</div>
		{:else}
			<SuperListRowScope binding={config.binding} index={clampedIndex}>
				<ZoneFlowContainer
					placements={config.placements.content ?? []}
					axis="column"
					slotSizeConstraints={config.slotSizeConstraints}
					defaultExpandSlots={true}
				/>
			</SuperListRowScope>
		{/if}
	</div>

	{#if config.tabBarPosition === 'bottom'}
		{@render tabBar()}
	{/if}
</div>

<style>
	.sc-tabs-container {
		display: flex;
		flex-direction: column;
		width: 100%;
		height: 100%;
		min-height: 0;
	}
	.sc-tabbar {
		display: flex;
		align-items: center;
		gap: 4px;
		flex-shrink: 0;
	}
	.sc-tabbar.scrollable {
		overflow-x: auto;
	}
	.sc-tab-btn {
		flex: 1 1 0%;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		padding: 12px 16px;
		border: none;
		background: transparent;
		font-size: 14px;
		font-weight: 600;
		cursor: pointer;
		position: relative;
		transition: color 150ms ease, background 150ms ease;
	}
	.sc-tabbar.scrollable .sc-tab-btn {
		flex: 0 0 auto;
	}
	.sc-tab-btn.indicator-underline::after {
		content: '';
		position: absolute;
		left: 12px;
		right: 12px;
		bottom: 0;
		height: var(--ind-weight, 2px);
		background: var(--ind-color, #5268d9);
		border-radius: 2px;
	}
	.sc-tab-btn.indicator-box {
		background: rgba(82, 104, 217, 0.12);
		border-radius: var(--ind-radius, 10px);
	}
	.sc-tab-view {
		flex: 1 1 0%;
		min-height: 0;
		padding-top: 12px;
		display: flex;
		flex-direction: column;
	}
	.sc-tab-empty {
		padding: 24px;
		text-align: center;
		color: #7b86a2;
	}
</style>
