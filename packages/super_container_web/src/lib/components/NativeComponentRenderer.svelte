<script lang="ts">
	import type {
		AutomaticState,
		ContainerStyle,
		NativeComponentConfig
	} from '$lib/models/types.js';
	import { parseJsonColor } from '$lib/models/codec.js';
	import {
		getJsonListScopeContext,
		getRepositoryStoreContext
	} from '$lib/services/json_repository.svelte.js';
	import {
		getContentHoverScope,
		getPlayerRuntimeContext,
		setContentHoverScope
	} from '$lib/runtime/player_context.svelte.js';
	import {
		buildContainerStyleCss,
		buildNativeShapeCss,
		resolveEffectiveContainerStyle
	} from '$lib/styles/container_style_css.js';
	import ZoneFlowContainer from './ZoneFlowContainer.svelte';
	import SlotRenderer from './SlotRenderer.svelte';

	interface Props {
		id: string;
		config: NativeComponentConfig;
		placementType?: string;
		style?: ContainerStyle;
	}

	let { id, config, placementType = '', style }: Props = $props();

	const player = getPlayerRuntimeContext();
	const repoStore = getRepositoryStoreContext();
	const listScope = getJsonListScopeContext();
	const parentContentHover = getContentHoverScope();

	let isHovered = $state(false);
	let isPressed = $state(false);
	let drawerOpen = $state(false);
	let endDrawerOpen = $state(false);
	let localExpanded = $state<boolean | null>(null);

	// Provide ContentHoverScope when this is a Card or IterableContent
	setContentHoverScope(() => isHovered || Boolean(parentContentHover?.isHovered));

	const normalizedKind = $derived.by(() => {
		const pt = placementType.toLowerCase();
		if (config.type === 'scaffold' || id === 'root' || id.startsWith('page-')) return 'scaffold';
		if (pt.includes('applicationbar') || pt.includes('appbar')) return 'appBar';
		if (pt.includes('bottomnavigationbar')) return 'bottomNav';
		if (pt.includes('bottomappbar') || pt.includes('bottombar')) return 'bottomAppBar';
		if (pt.includes('expansible')) return 'expansible';
		if (pt.includes('menu')) return 'menu';
		if (pt.includes('card') || 'child' in config.regions || 'child' in config.placements) {
			return 'card';
		}
		if ('destinations' in config.placements) return 'bottomNav';
		if ('left' in config.placements || 'right' in config.placements) return 'bottomAppBar';
		if ('header' in config.placements && 'body' in config.placements) return 'expansible';
		if ('title' in config.placements || 'actions' in config.placements) return 'appBar';
		if ('appBar' in config.placements || 'body' in config.placements) return 'scaffold';
		return 'card';
	});

	const isExpanded = $derived.by(() => {
		if (config.binding && repoStore) {
			const v = repoStore.readBinding(config.binding, listScope);
			if (typeof v === 'boolean') return v;
		}
		if (localExpanded !== null) return localExpanded;
		return Boolean(config.properties.initiallyExpanded);
	});

	function toggleExpanded() {
		const next = !isExpanded;
		if (config.binding && repoStore) {
			repoStore.writeBinding(config.binding, next, listScope);
		} else {
			localExpanded = next;
		}
	}

	const activeStates = $derived.by(() => {
		const s = new Set<AutomaticState>();
		if (isHovered) s.add('hover');
		if (isPressed) s.add('pressed');
		if (parentContentHover?.isHovered) s.add('contentHover');
		return s;
	});

	const surfaceCss = $derived.by(() => {
		if (!style) return '';
		const eff = resolveEffectiveContainerStyle(style, activeStates);
		const imgBind = eff.propertyBindings?.imageUrl ?? eff.fill.imageBinding;
		const dynImg =
			imgBind && repoStore ? String(repoStore.readBinding(imgBind, listScope) ?? '') : undefined;
		return buildContainerStyleCss(eff, {
			accent: player.appearance.accent,
			mode: player.appearance.mode,
			dynamicImageUrl: dynImg || undefined
		});
	});

	function isRegionActive(region: string, defaultActive = true): boolean {
		if (region in config.regions) return Boolean(config.regions[region]);
		return defaultActive && Boolean(config.placements[region]?.length);
	}
</script>

{#if normalizedKind === 'scaffold'}
	{@const bodyMode = String(config.properties.bodyMode ?? 'standard')}
	{@const hasDrawer = isRegionActive('drawer', false)}
	{@const hasEndDrawer = isRegionActive('endDrawer', false)}
	<div class="sc-scaffold" data-component-id={id}>
		{#if isRegionActive('appBar')}
			<header class="sc-scaffold-header">
				<ZoneFlowContainer
					placements={config.placements.appBar ?? []}
					axis="row"
					flow={config.regionFlows.appBar}
					slotSizeConstraints={config.slotSizeConstraints}
					slotPreferredSizes={config.slotPreferredSizes}
					defaultExpandSlots={true}
				/>
			</header>
		{/if}

		<div class="sc-scaffold-middle">
			{#if hasDrawer && drawerOpen}
				<aside class="sc-scaffold-drawer">
					<ZoneFlowContainer
						placements={config.placements.drawer ?? []}
						axis={config.regionAxes.drawer ?? 'column'}
						flow={config.regionFlows.drawer}
						slotSizeConstraints={config.slotSizeConstraints}
						slotPreferredSizes={config.slotPreferredSizes}
						defaultExpandSlots={false}
					/>
				</aside>
			{/if}

			<main
				class="sc-scaffold-body"
				class:scrollable={bodyMode === 'singleChildScrollView' || bodyMode === 'customScrollView'}
			>
				<ZoneFlowContainer
					placements={config.placements.body ?? []}
					axis={config.regionAxes.body ?? 'column'}
					flow={config.regionFlows.body}
					slotSizeConstraints={config.slotSizeConstraints}
					slotPreferredSizes={config.slotPreferredSizes}
					defaultExpandSlots={bodyMode === 'standard'}
				/>
			</main>

			{#if hasEndDrawer && endDrawerOpen}
				<aside class="sc-scaffold-drawer end">
					<ZoneFlowContainer
						placements={config.placements.endDrawer ?? []}
						axis={config.regionAxes.endDrawer ?? 'column'}
						flow={config.regionFlows.endDrawer}
						slotSizeConstraints={config.slotSizeConstraints}
						slotPreferredSizes={config.slotPreferredSizes}
						defaultExpandSlots={false}
					/>
				</aside>
			{/if}
		</div>

		{#if isRegionActive('bottomSheet', false)}
			<section class="sc-scaffold-bottom-sheet">
				<ZoneFlowContainer
					placements={config.placements.bottomSheet ?? []}
					axis={config.regionAxes.bottomSheet ?? 'column'}
					flow={config.regionFlows.bottomSheet}
					slotSizeConstraints={config.slotSizeConstraints}
					slotPreferredSizes={config.slotPreferredSizes}
					defaultExpandSlots={false}
				/>
			</section>
		{/if}

		{#if isRegionActive('floatingActionButton', false)}
			<div class="sc-scaffold-fab">
				<ZoneFlowContainer
					placements={config.placements.floatingActionButton ?? []}
					axis="row"
					defaultExpandSlots={false}
				/>
			</div>
		{/if}

		{#if isRegionActive('bottomNavigationBar')}
			<nav class="sc-scaffold-bottom-nav" aria-label="Navigation principale">
				<ZoneFlowContainer
					placements={config.placements.bottomNavigationBar ?? []}
					axis="row"
					flow={config.regionFlows.bottomNavigationBar}
					slotSizeConstraints={config.slotSizeConstraints}
					slotPreferredSizes={config.slotPreferredSizes}
					defaultExpandSlots={true}
				/>
			</nav>
		{/if}
	</div>
{:else if normalizedKind === 'appBar'}
	{@const bg = config.properties.backgroundColor
		? parseJsonColor(config.properties.backgroundColor, '#FFFFFF')
		: '#FFFFFF'}
	{@const fg = config.properties.foregroundColor
		? parseJsonColor(config.properties.foregroundColor, '#1B2234')
		: '#1B2234'}
	{@const height = typeof config.properties.toolbarHeight === 'number' ? config.properties.toolbarHeight : 56}
	{@const elev = typeof config.properties.elevation === 'number' ? config.properties.elevation : 0}
	{@const shapeCss = buildNativeShapeCss(config.properties.shape)}
	<div
		class="sc-appbar"
		data-component-id={id}
		style="background: {bg}; color: {fg}; min-height: {height}px; box-shadow: {elev > 0 ? `0 ${elev}px ${elev * 3}px rgba(0,0,0,0.08)` : 'none'}; {shapeCss}; {surfaceCss}"
	>
		<div class="sc-appbar-toolbar" style="min-height: {height}px;">
			{#if isRegionActive('leading')}
				<div class="sc-appbar-leading">
					<ZoneFlowContainer
						placements={config.placements.leading ?? []}
						axis="row"
						flow={config.regionFlows.leading}
						defaultExpandSlots={false}
					/>
				</div>
			{/if}
			{#if isRegionActive('title')}
				<div
					class="sc-appbar-title"
					style="justify-content: {config.properties.centerTitle ? 'center' : 'flex-start'};"
				>
					<ZoneFlowContainer
						placements={config.placements.title ?? []}
						axis="row"
						flow={config.regionFlows.title}
						defaultExpandSlots={false}
					/>
				</div>
			{/if}
			{#if isRegionActive('actions')}
				<div class="sc-appbar-actions">
					<ZoneFlowContainer
						placements={config.placements.actions ?? []}
						axis="row"
						flow={config.regionFlows.actions}
						defaultExpandSlots={false}
					/>
				</div>
			{/if}
		</div>
		{#if isRegionActive('bottom', false)}
			<div class="sc-appbar-bottom">
				<ZoneFlowContainer
					placements={config.placements.bottom ?? []}
					axis="row"
					flow={config.regionFlows.bottom}
					defaultExpandSlots={false}
				/>
			</div>
		{/if}
	</div>
{:else if normalizedKind === 'bottomNav'}
	{@const bg = config.properties.backgroundColor
		? parseJsonColor(config.properties.backgroundColor, '#FFFFFF')
		: '#FFFFFF'}
	{@const height = typeof config.properties.height === 'number' ? config.properties.height : 60}
	<div
		class="sc-bottom-nav-bar"
		data-component-id={id}
		style="background: {bg}; min-height: {height}px; {surfaceCss}"
	>
		{#each config.placements.destinations ?? [] as dest (dest.id)}
			<div class="sc-bottom-nav-item">
				<SlotRenderer id={dest.id} placementType={dest.type} defaultExpand={false} />
			</div>
		{/each}
	</div>
{:else if normalizedKind === 'bottomAppBar'}
	{@const bg = config.properties.color
		? parseJsonColor(config.properties.color, '#FFFFFF')
		: '#FFFFFF'}
	{@const height = typeof config.properties.height === 'number' ? config.properties.height : 56}
	<div
		class="sc-bottom-appbar"
		data-component-id={id}
		style="background: {bg}; min-height: {height}px; {surfaceCss}"
	>
		<div class="sc-bottom-appbar-section">
			<ZoneFlowContainer
				placements={config.placements.left ?? []}
				axis="row"
				flow={config.regionFlows.left}
				defaultExpandSlots={false}
			/>
		</div>
		<div class="sc-bottom-appbar-section center">
			<ZoneFlowContainer
				placements={config.placements.center ?? []}
				axis="row"
				flow={config.regionFlows.center}
				defaultExpandSlots={false}
			/>
		</div>
		<div class="sc-bottom-appbar-section right">
			<ZoneFlowContainer
				placements={config.placements.right ?? []}
				axis="row"
				flow={config.regionFlows.right}
				defaultExpandSlots={false}
			/>
		</div>
	</div>
{:else if normalizedKind === 'expansible' || normalizedKind === 'menu'}
	{@const toggleIcon = String(config.properties.toggleIcon ?? 'chevron')}
	<div class="sc-expansible" data-component-id={id} style={surfaceCss}>
		<!-- svelte-ignore a11y_click_events_have_key_events -->
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<div
			class="sc-expansible-header"
			onclick={() => {
				if (config.properties.headerClickToggles !== false) toggleExpanded();
			}}
		>
			<div class="sc-expansible-header-content">
				<ZoneFlowContainer
					placements={config.placements.header ?? []}
					axis="row"
					flow={config.regionFlows.header}
					defaultExpandSlots={false}
				/>
			</div>
			{#if toggleIcon !== 'none'}
				<span class="material-icons sc-expansible-icon" class:open={isExpanded}>
					expand_more
				</span>
			{/if}
		</div>
		{#if isExpanded}
			<div class="sc-expansible-body" class:menu-popup={normalizedKind === 'menu'}>
				<ZoneFlowContainer
					placements={config.placements.body ?? []}
					axis="column"
					flow={config.regionFlows.body}
					defaultExpandSlots={false}
				/>
			</div>
		{/if}
	</div>
{:else}
	<!-- Card / Container -->
	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<section
		class="sc-card"
		data-component-id={id}
		style={surfaceCss}
		onmouseenter={() => (isHovered = true)}
		onmouseleave={() => {
			isHovered = false;
			isPressed = false;
		}}
		onmousedown={() => (isPressed = true)}
		onmouseup={() => (isPressed = false)}
	>
		{#each config.placements.child ?? [] as childRef (childRef.id)}
			<SlotRenderer
				id={childRef.id}
				placementType={childRef.type}
				constraints={config.slotSizeConstraints[childRef.id]}
				preferredSize={config.slotPreferredSizes[childRef.id]}
				defaultExpand={true}
			/>
		{/each}
	</section>
{/if}

<style>
	.sc-scaffold {
		display: flex;
		flex-direction: column;
		width: 100%;
		height: 100%;
		min-height: 0;
		position: relative;
	}
	.sc-scaffold-header {
		flex-shrink: 0;
		width: 100%;
	}
	.sc-scaffold-middle {
		display: flex;
		flex: 1 1 0%;
		min-height: 0;
		width: 100%;
	}
	.sc-scaffold-body {
		flex: 1 1 0%;
		min-height: 0;
		min-width: 0;
		display: flex;
		flex-direction: column;
	}
	.sc-scaffold-body.scrollable {
		overflow-y: auto;
	}
	.sc-scaffold-bottom-nav {
		flex-shrink: 0;
		width: 100%;
	}
	.sc-scaffold-fab {
		position: absolute;
		right: 20px;
		bottom: 76px;
		z-index: 20;
	}
	.sc-appbar {
		width: 100%;
		display: flex;
		flex-direction: column;
		padding: 0 16px;
		border-bottom: 1px solid rgba(0, 0, 0, 0.06);
	}
	.sc-appbar-toolbar {
		display: flex;
		align-items: center;
		gap: 12px;
		width: 100%;
	}
	.sc-appbar-title {
		flex: 1 1 auto;
		display: flex;
		align-items: center;
		min-width: 0;
	}
	.sc-appbar-actions {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.sc-bottom-nav-bar {
		width: 100%;
		display: flex;
		align-items: center;
		justify-content: space-around;
		border-top: 1px solid rgba(0, 0, 0, 0.08);
		padding: 4px 12px;
	}
	.sc-bottom-appbar {
		width: 100%;
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0 16px;
		border-top: 1px solid rgba(0, 0, 0, 0.08);
	}
	.sc-bottom-appbar-section {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.sc-card {
		display: flex;
		flex-direction: column;
		width: 100%;
		height: 100%;
		min-height: 0;
		min-width: 0;
	}
	.sc-expansible {
		display: flex;
		flex-direction: column;
		width: 100%;
		border: 1px solid rgba(0, 0, 0, 0.08);
		border-radius: 12px;
		overflow: hidden;
	}
	.sc-expansible-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 10px 14px;
		cursor: pointer;
		background: rgba(82, 104, 217, 0.04);
	}
	.sc-expansible-icon {
		transition: transform 180ms ease;
	}
	.sc-expansible-icon.open {
		transform: rotate(180deg);
	}
	.sc-expansible-body {
		padding: 12px 14px;
	}
</style>
