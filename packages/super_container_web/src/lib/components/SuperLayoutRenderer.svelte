<script lang="ts">
	import type { SuperLayoutConfig, SuperLayoutZone } from '$lib/models/types.js';
	import { arrangeGridItems } from '$lib/models/codec.js';
	import { getPlayerRuntimeContext } from '$lib/runtime/player_context.svelte.js';
	import ZoneFlowContainer from './ZoneFlowContainer.svelte';
	import SlotRenderer from './SlotRenderer.svelte';

	interface Props {
		id: string;
		config: SuperLayoutConfig;
	}

	let { id, config }: Props = $props();

	const player = getPlayerRuntimeContext();

	const hasNorth = $derived(config.north && !config.collapsedSides.includes('north'));
	const hasSouth = $derived(config.south && !config.collapsedSides.includes('south'));
	const hasWest = $derived(config.west && !config.collapsedSides.includes('west'));
	const hasEast = $derived(config.east && !config.collapsedSides.includes('east'));

	const isAuto = (zone: SuperLayoutZone) => config.autoSides.includes(zone);

	const northPx = $derived(player.getZoneSize(id, 'north', config.northSize));
	const southPx = $derived(player.getZoneSize(id, 'south', config.southSize));
	const westPx = $derived(player.getZoneSize(id, 'west', config.westSize));
	const eastPx = $derived(player.getZoneSize(id, 'east', config.eastSize));

	const gridTemplateRows = $derived.by(() => {
		const top = hasNorth ? (isAuto('north') ? 'auto' : `${northPx}px`) : '0px';
		const bottom = hasSouth ? (isAuto('south') ? 'auto' : `${southPx}px`) : '0px';
		const centerExpand = config.zoneFlows.center?.expandSlots !== false;
		const mid = centerExpand ? 'minmax(0, 1fr)' : 'auto';
		return `${top} ${mid} ${bottom}`;
	});

	const gridTemplateColumns = $derived.by(() => {
		const left = hasWest ? (isAuto('west') ? 'auto' : `${westPx}px`) : '0px';
		const right = hasEast ? (isAuto('east') ? 'auto' : `${eastPx}px`) : '0px';
		return `${left} minmax(0, 1fr) ${right}`;
	});

	const gridTemplateAreas = $derived.by(() => {
		const nwArea =
			hasNorth && hasWest
				? config.nw === 'row'
					? 'north'
					: config.nw === 'column'
						? 'west'
						: 'nw'
				: hasNorth
					? 'north'
					: hasWest
						? 'west'
						: 'center';

		const neArea =
			hasNorth && hasEast
				? config.ne === 'row'
					? 'north'
					: config.ne === 'column'
						? 'east'
						: 'ne'
				: hasNorth
					? 'north'
					: hasEast
						? 'east'
						: 'center';

		const swArea =
			hasSouth && hasWest
				? config.sw === 'row'
					? 'south'
					: config.sw === 'column'
						? 'west'
						: 'sw'
				: hasSouth
					? 'south'
					: hasWest
						? 'west'
						: 'center';

		const seArea =
			hasSouth && hasEast
				? config.se === 'row'
					? 'south'
					: config.se === 'column'
						? 'east'
						: 'se'
				: hasSouth
					? 'south'
					: hasEast
						? 'east'
						: 'center';

		const nArea = hasNorth ? 'north' : 'center';
		const sArea = hasSouth ? 'south' : 'center';
		const wArea = hasWest ? 'west' : 'center';
		const eArea = hasEast ? 'east' : 'center';

		return `"${nwArea} ${nArea} ${neArea}" "${wArea} center ${eArea}" "${swArea} ${sArea} ${seArea}"`;
	});

	const visibleZones = $derived.by(() => {
		const zones: SuperLayoutZone[] = ['center'];
		if (hasNorth) zones.push('north');
		if (hasSouth) zones.push('south');
		if (hasWest) zones.push('west');
		if (hasEast) zones.push('east');
		if (hasNorth && hasWest && config.nw === 'none') zones.push('nw');
		if (hasNorth && hasEast && config.ne === 'none') zones.push('ne');
		if (hasSouth && hasWest && config.sw === 'none') zones.push('sw');
		if (hasSouth && hasEast && config.se === 'none') zones.push('se');
		return zones;
	});

	const canResizeSide = (side: SuperLayoutZone) =>
		!isAuto(side) && (config.sideResizing[side] ?? config.resizeSides);

	function startResize(side: 'north' | 'south' | 'west' | 'east', event: PointerEvent) {
		event.preventDefault();
		const startX = event.clientX;
		const startY = event.clientY;
		const initialSize =
			side === 'north'
				? northPx
				: side === 'south'
					? southPx
					: side === 'west'
						? westPx
						: eastPx;

		function onMove(e: PointerEvent) {
			const dx = e.clientX - startX;
			const dy = e.clientY - startY;
			const delta =
				side === 'north' ? dy : side === 'south' ? -dy : side === 'west' ? dx : -dx;
			player.setZoneSize(id, side, initialSize + delta);
		}

		function onUp() {
			window.removeEventListener('pointermove', onMove);
			window.removeEventListener('pointerup', onUp);
		}

		window.addEventListener('pointermove', onMove);
		window.addEventListener('pointerup', onUp);
	}

	// 2D Grid positioning
	const allPlacedRefs = $derived.by(() => {
		const map = new Map<string, string>();
		for (const list of Object.values(config.placements)) {
			if (!list) continue;
			for (const ref of list) {
				map.set(ref.id, ref.type);
			}
		}
		return map;
	});

	const arrangedGrid = $derived.by(() => {
		if (!config.grid) return null;
		const items = arrangeGridItems(config.grid);
		return {
			...config.grid,
			items
		};
	});
</script>

{#if config.positioning === 'grid' && arrangedGrid}
	<div
		class="sc-super-grid"
		data-layout-id={id}
		style="display: grid; grid-template-columns: repeat({arrangedGrid.columns}, minmax(0, 1fr)); grid-auto-rows: {arrangedGrid.rowHeight}px; gap: {arrangedGrid.gap}px; width: 100%;"
	>
		{#each Object.entries(arrangedGrid.items) as [slotId, pos] (slotId)}
			<div
				class="sc-grid-cell"
				style="grid-column: {pos.x + 1} / span {pos.width}; grid-row: {pos.y + 1} / span {pos.height}; min-width: 0; min-height: 0; display: flex; flex-direction: column;"
			>
				<SlotRenderer
					id={slotId}
					placementType={allPlacedRefs.get(slotId) ?? config.slotTypes[slotId]}
					constraints={config.slotSizeConstraints[slotId]}
					preferredSize={config.slotPreferredSizes[slotId]}
					defaultExpand={true}
					mainAxis="column"
				/>
			</div>
		{/each}
	</div>
{:else}
	<div
		class="sc-super-layout"
		data-layout-id={id}
		style="display: grid; grid-template-rows: {gridTemplateRows}; grid-template-columns: {gridTemplateColumns}; grid-template-areas: {gridTemplateAreas}; width: 100%; height: {config.zoneFlows.center?.expandSlots === false ? 'auto' : '100%'}; min-height: 0; min-width: 0; position: relative;"
	>
		{#each visibleZones as zone (zone)}
			{@const placements = config.placements[zone] ?? []}
			{@const axis = config.zoneAxes[zone] ?? (zone === 'north' || zone === 'south' ? 'row' : 'column')}
			{@const flow = config.zoneFlows[zone]}
			<div
				class="sc-layout-zone sc-zone-{zone}"
				style="grid-area: {zone}; min-width: 0; min-height: 0; position: relative; display: flex;"
			>
				<ZoneFlowContainer
					{placements}
					{axis}
					{flow}
					slotSizeConstraints={config.slotSizeConstraints}
					slotPreferredSizes={config.slotPreferredSizes}
					defaultExpandSlots={flow?.expandSlots ?? true}
				/>

				{#if (zone === 'north' || zone === 'south' || zone === 'west' || zone === 'east') && canResizeSide(zone)}
					<div
						class="sc-resize-handle sc-resize-{zone}"
						role="separator"
						aria-orientation={zone === 'north' || zone === 'south' ? 'horizontal' : 'vertical'}
						onpointerdown={(e) => startResize(zone, e)}
					></div>
				{/if}
			</div>
		{/each}
	</div>
{/if}

<style>
	.sc-resize-handle {
		position: absolute;
		z-index: 10;
		transition: background-color 150ms ease;
	}
	.sc-resize-handle:hover {
		background-color: rgba(82, 104, 217, 0.35);
	}
	.sc-resize-west {
		top: 0;
		right: -3px;
		width: 6px;
		height: 100%;
		cursor: col-resize;
	}
	.sc-resize-east {
		top: 0;
		left: -3px;
		width: 6px;
		height: 100%;
		cursor: col-resize;
	}
	.sc-resize-north {
		bottom: -3px;
		left: 0;
		width: 100%;
		height: 6px;
		cursor: row-resize;
	}
	.sc-resize-south {
		top: -3px;
		left: 0;
		width: 100%;
		height: 6px;
		cursor: row-resize;
	}
</style>
