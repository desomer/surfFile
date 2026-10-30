<script lang="ts">
	import type { AutomaticState, SlotSizeConstraints } from '$lib/models/types.js';
	import {
		getContentHoverScope,
		getPlayerRuntimeContext,
		setContentHoverScope
	} from '$lib/runtime/player_context.svelte.js';
	import {
		getJsonListScopeContext,
		getRepositoryStoreContext
	} from '$lib/services/json_repository.svelte.js';
	import {
		buildContainerStyleCss,
		buildSlotConstraintsCss,
		resolveEffectiveContainerStyle
	} from '$lib/styles/container_style_css.js';
	import SuperLayoutRenderer from './SuperLayoutRenderer.svelte';
	import SuperValueRenderer from './SuperValueRenderer.svelte';
	import SuperActionRenderer from './SuperActionRenderer.svelte';
	import NativeComponentRenderer from './NativeComponentRenderer.svelte';
	import SuperListViewRenderer from './SuperListViewRenderer.svelte';
	import SuperTabRenderer from './SuperTabRenderer.svelte';

	interface Props {
		id: string;
		placementType?: string;
		constraints?: SlotSizeConstraints;
		preferredSize?: [number | null, number | null];
		defaultExpand?: boolean;
		mainAxis?: 'row' | 'column';
	}

	let {
		id,
		placementType = '',
		constraints,
		preferredSize,
		defaultExpand = false,
		mainAxis = 'column'
	}: Props = $props();

	const player = getPlayerRuntimeContext();
	const repoStore = getRepositoryStoreContext();
	const listScope = getJsonListScopeContext();
	const parentContentHover = getContentHoverScope();

	let isHovered = $state(false);
	let isPressed = $state(false);

	// Resolve "scaffold:body" alias to "mainLayout" when no dedicated component is under "scaffold:body"
	const effectiveId = $derived(
		id === 'scaffold:body' &&
			!player.appearance.components['scaffold:body'] &&
			player.appearance.components['mainLayout']
			? 'mainLayout'
			: id
	);

	const comp = $derived(player.appearance.components[effectiveId]);
	const style = $derived(player.appearance.styles[effectiveId]);
	const isIterableContent = $derived(
		placementType.toLowerCase().includes('iterablecontent') ||
			(comp?.type === 'layout' && style !== undefined)
	);

	setContentHoverScope(() =>
		isIterableContent
			? isHovered || Boolean(parentContentHover?.isHovered)
			: Boolean(parentContentHover?.isHovered)
	);

	const activeStates = $derived.by(() => {
		const s = new Set<AutomaticState>();
		if (isHovered) s.add('hover');
		if (isPressed) s.add('pressed');
		if (parentContentHover?.isHovered) s.add('contentHover');
		return s;
	});

	const slotWrapperStyle = $derived.by(() => {
		// Leaf controls (value, action) naturally fit their content unless explicitly constrained
		const isNaturalLeaf = comp?.type === 'value' || comp?.type === 'action';
		const effectiveExpand = isNaturalLeaf ? false : defaultExpand;
		const constraintsCss = buildSlotConstraintsCss(
			constraints,
			preferredSize,
			effectiveExpand,
			mainAxis
		);

		if (isIterableContent && style) {
			const effStyle = resolveEffectiveContainerStyle(style, activeStates);
			const imgBind = effStyle.propertyBindings?.imageUrl ?? effStyle.fill.imageBinding;
			const dynImg =
				imgBind && repoStore
					? String(repoStore.readBinding(imgBind, listScope) ?? '')
					: undefined;
			const surfaceCss = buildContainerStyleCss(effStyle, {
				accent: player.appearance.accent,
				mode: player.appearance.mode,
				dynamicImageUrl: dynImg || undefined
			});
			return `${constraintsCss}; ${surfaceCss}`;
		}

		return constraintsCss;
	});
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
	class="sc-slot"
	class:sc-iterable-content={isIterableContent}
	data-slot-id={effectiveId}
	style={slotWrapperStyle}
	onmouseenter={() => (isHovered = true)}
	onmouseleave={() => {
		isHovered = false;
		isPressed = false;
	}}
	onmousedown={() => (isPressed = true)}
	onmouseup={() => (isPressed = false)}
>
	{#if !comp && style}
		<!-- Pure visual Card (style-only entry in styles[id]) -->
		<div
			class="sc-visual-card"
			style={buildContainerStyleCss(resolveEffectiveContainerStyle(style, activeStates), {
				accent: player.appearance.accent,
				mode: player.appearance.mode
			})}
		></div>
	{:else if comp?.type === 'layout'}
		<SuperLayoutRenderer id={effectiveId} config={comp} />
	{:else if comp?.type === 'value'}
		<SuperValueRenderer id={effectiveId} config={comp} />
	{:else if comp?.type === 'action'}
		<SuperActionRenderer id={effectiveId} config={comp} />
	{:else if comp?.type === 'native' || comp?.type === 'scaffold'}
		<NativeComponentRenderer id={effectiveId} config={comp} {placementType} {style} />
	{:else if comp?.type === 'list'}
		<SuperListViewRenderer id={effectiveId} config={comp} />
	{:else if comp?.type === 'tab'}
		<SuperTabRenderer id={effectiveId} config={comp} />
	{:else if comp}
		<!-- Phase 2 extensibility placeholder for table, treeView, chart -->
		<div class="sc-phase2-placeholder">
			<span class="material-icons">widgets</span>
			<span>Composant <strong>{comp.type}</strong> ({effectiveId})</span>
		</div>
	{/if}
</div>

<style>
	.sc-slot {
		display: flex;
		flex-direction: column;
		min-width: 0;
		min-height: 0;
		box-sizing: border-box;
	}
	.sc-visual-card {
		width: 100%;
		height: 100%;
	}
	.sc-phase2-placeholder {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 16px;
		border-radius: 10px;
		border: 1px dashed #b9c4dc;
		color: #5b6682;
		font-size: 13px;
	}
</style>
