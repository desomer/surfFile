<script lang="ts">
	import type { AutomaticState, SuperListViewConfig } from '$lib/models/types.js';
	import {
		getJsonListScopeContext,
		getRepositoryStoreContext
	} from '$lib/services/json_repository.svelte.js';
	import { getPlayerRuntimeContext } from '$lib/runtime/player_context.svelte.js';
	import {
		buildContainerStyleCss,
		resolveEffectiveContainerStyle
	} from '$lib/styles/container_style_css.js';
	import SuperLayoutRenderer from './SuperLayoutRenderer.svelte';
	import SuperListRowScope from './SuperListRowScope.svelte';

	interface Props {
		id: string;
		config: SuperListViewConfig;
	}

	let { id, config }: Props = $props();

	const repoStore = getRepositoryStoreContext();
	const parentScope = getJsonListScopeContext();
	const player = getPlayerRuntimeContext();

	let hoveredIndex = $state<number | null>(null);

	const resolvedArray = $derived(repoStore?.resolveBinding(config.binding, parentScope) ?? null);
	const items = $derived.by(() => {
		if (!config.binding || !repoStore) return [] as unknown[];
		const val = repoStore.readBinding(config.binding, parentScope);
		return Array.isArray(val) ? val : [];
	});

	const selectedIndex = $derived.by(() => {
		if (!resolvedArray || !resolvedArray.isResolved || !repoStore) return 0;
		return repoStore.getSelectedRow(resolvedArray.repositoryId, resolvedArray.resolvedPath) ?? 0;
	});

	// Ensure default row 0 is selected for master/detail synchronization
	$effect(() => {
		if (resolvedArray?.isResolved && repoStore && items.length > 0) {
			const current = repoStore.getSelectedRow(
				resolvedArray.repositoryId,
				resolvedArray.resolvedPath
			);
			if (current === undefined || current >= items.length) {
				repoStore.selectRow(resolvedArray.repositoryId, resolvedArray.resolvedPath, 0);
			}
		}
	});

	const itemStyleId = $derived(config.itemId ?? `${id}:item`);
	const baseItemStyle = $derived(
		player.appearance.styles[itemStyleId] ?? player.appearance.styles[id]
	);
	const itemGoToPageHref = $derived(player.getGoToPageHref(itemStyleId));

	function getRowCss(index: number): string {
		if (!baseItemStyle) {
			const isSel = index === selectedIndex;
			return `padding: 10px 12px; border-radius: 10px; background: ${isSel ? 'rgba(82,104,217,0.1)' : '#FFFFFF'}; border: 1px solid ${isSel ? player.appearance.accent : '#E2E8F4'};`;
		}
		const states = new Set<AutomaticState>();
		if (index === selectedIndex) states.add('selected');
		if (index === hoveredIndex) {
			states.add('hover');
			states.add('contentHover');
		}
		const effective = resolveEffectiveContainerStyle(baseItemStyle, states);
		return buildContainerStyleCss(effective, {
			accent: player.appearance.accent,
			mode: player.appearance.mode
		});
	}

	function handleRowClick(index: number) {
		if (resolvedArray?.isResolved && repoStore) {
			repoStore.selectRow(resolvedArray.repositoryId, resolvedArray.resolvedPath, index);
		}
		player.executeBehaviors(itemStyleId, 'click');
	}

	function handleAddRow() {
		if (config.binding && repoStore) {
			repoStore.addRow(config.binding, parentScope);
		}
	}

	function handleRemoveRow(index: number, e: MouseEvent) {
		e.stopPropagation();
		if (config.binding && repoStore) {
			repoStore.removeRow(config.binding, index, parentScope);
		}
	}
</script>

<div class="sc-listview-wrapper" data-component-id={id}>
	{#if config.allowAdd}
		<div class="sc-listview-toolbar">
			<button
				type="button"
				class="sc-listview-add-btn"
				onclick={handleAddRow}
				style="--accent: {player.appearance.accent};"
			>
				<span class="material-icons">add</span>
				<span>Ajouter</span>
			</button>
		</div>
	{/if}

	{#if items.length === 0}
		<div class="sc-listview-empty">{config.emptyText}</div>
	{:else}
		<div
			class="sc-listview-items"
			class:horizontal={config.axis === 'horizontal'}
			class:wrap={config.wrap}
			style="gap: {config.spacing}px;"
		>
			{#each items as _, index (index)}
				<!-- svelte-ignore a11y_click_events_have_key_events -->
				<!-- svelte-ignore a11y_no_static_element_interactions -->
				<div
					class="sc-listview-row"
					class:selected={index === selectedIndex}
					style="{getRowCss(index)}; min-height: {config.itemExtent}px; {config.wrap && config.wrapSizing === 'fixed' ? `width: ${config.itemWidth}px;` : ''}"
					onmouseenter={() => (hoveredIndex = index)}
					onmouseleave={() => {
						if (hoveredIndex === index) hoveredIndex = null;
					}}
					onclick={() => handleRowClick(index)}
				>
					<SuperListRowScope
						binding={config.binding}
						{index}
						isHovered={hoveredIndex === index}
					>
						<div class="sc-listview-row-content">
							<SuperLayoutRenderer id="{id}:layout" config={config.template} />
						</div>
					</SuperListRowScope>

					{#if itemGoToPageHref}
						<a
							href={itemGoToPageHref}
							class="sc-row-seo-link"
							aria-label="Ouvrir l'élément {index + 1}"
							onclick={(e) => {
								e.stopPropagation();
								handleRowClick(index);
							}}
						></a>
					{/if}

					{#if config.allowRemove}
						<button
							type="button"
							class="sc-listview-remove-btn"
							title="Supprimer la ligne"
							onclick={(e) => handleRemoveRow(index, e)}
						>
							<span class="material-icons">delete_outline</span>
						</button>
					{/if}
				</div>
			{/each}
		</div>
	{/if}
</div>

<style>
	.sc-listview-wrapper {
		display: flex;
		flex-direction: column;
		gap: 8px;
		width: 100%;
		height: 100%;
		min-height: 0;
	}
	.sc-listview-toolbar {
		display: flex;
		justify-content: flex-end;
	}
	.sc-listview-add-btn {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 5px 12px;
		border-radius: 8px;
		border: 1px solid var(--accent, #5268d9);
		background: rgba(82, 104, 217, 0.08);
		color: var(--accent, #5268d9);
		font-size: 12px;
		font-weight: 600;
		cursor: pointer;
	}
	.sc-listview-items {
		display: flex;
		flex-direction: column;
		overflow-y: auto;
		flex: 1 1 auto;
		min-height: 0;
	}
	.sc-listview-items.horizontal {
		flex-direction: row;
		overflow-x: auto;
		overflow-y: hidden;
	}
	.sc-listview-items.wrap {
		flex-direction: row;
		flex-wrap: wrap;
	}
	.sc-listview-row {
		display: flex;
		align-items: center;
		gap: 8px;
		cursor: pointer;
		position: relative;
		user-select: none;
	}
	.sc-listview-row-content {
		flex: 1 1 auto;
		min-width: 0;
	}
	.sc-listview-remove-btn {
		border: none;
		background: transparent;
		color: #8b95ad;
		cursor: pointer;
		padding: 4px;
		border-radius: 6px;
		display: inline-flex;
		align-items: center;
	}
	.sc-listview-remove-btn:hover {
		color: #d93838;
		background: rgba(217, 56, 56, 0.08);
	}
	.sc-listview-empty {
		padding: 24px;
		text-align: center;
		color: #7b86a2;
		font-size: 13px;
		border: 1px dashed #d5dceb;
		border-radius: 12px;
	}
	.sc-row-seo-link {
		position: absolute;
		inset: 0;
		opacity: 0;
		pointer-events: none;
	}
</style>
