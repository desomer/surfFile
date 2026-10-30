<script lang="ts">
	import type {
		SlotPlacementRef,
		SlotSizeConstraints,
		ZoneFlowConfig
	} from '$lib/models/types.js';
	import SlotRenderer from './SlotRenderer.svelte';

	interface Props {
		placements?: SlotPlacementRef[];
		axis?: 'row' | 'column' | 'horizontal' | 'vertical';
		flow?: Partial<ZoneFlowConfig>;
		slotSizeConstraints?: Record<string, SlotSizeConstraints>;
		slotPreferredSizes?: Record<string, [number | null, number | null]>;
		defaultExpandSlots?: boolean;
	}

	let {
		placements = [],
		axis = 'column',
		flow,
		slotSizeConstraints = {},
		slotPreferredSizes = {},
		defaultExpandSlots = true
	}: Props = $props();

	const flexDir = $derived(axis === 'row' || axis === 'horizontal' ? 'row' : 'column');
	const expandSlots = $derived(flow?.expandSlots ?? defaultExpandSlots);
	const scrollable = $derived(Boolean(flow?.scrollable));
	const spacing = $derived(flow?.spacing ?? 0);

	const justifyMap: Record<string, string> = {
		start: 'flex-start',
		center: 'center',
		end: 'flex-end',
		spaceBetween: 'space-between',
		spaceAround: 'space-around',
		spaceEvenly: 'space-evenly'
	};

	const alignMap: Record<string, string> = {
		start: 'flex-start',
		center: 'center',
		end: 'flex-end',
		stretch: 'stretch'
	};

	const paddingCss = $derived.by(() => {
		if (flow?.paddingInsets) {
			const [t, r, b, l] = flow.paddingInsets;
			return `${t}px ${r}px ${b}px ${l}px`;
		}
		if (flow?.padding && flow.padding > 0) {
			return `${flow.padding}px`;
		}
		return '0px';
	});

	const containerStyle = $derived(
		[
			'display: flex',
			`flex-direction: ${flexDir}`,
			`justify-content: ${justifyMap[flow?.mainAxisAlignment ?? 'start'] ?? 'flex-start'}`,
			`align-items: ${alignMap[flow?.crossAxisAlignment ?? 'stretch'] ?? 'stretch'}`,
			`gap: ${spacing}px`,
			`padding: ${paddingCss}`,
			scrollable
				? flexDir === 'row'
					? 'overflow-x: auto; overflow-y: hidden'
					: 'overflow-y: auto; overflow-x: hidden'
				: 'overflow: visible',
			'width: 100%',
			expandSlots ? 'height: 100%; min-height: 0; min-width: 0' : 'min-width: 0'
		].join('; ')
	);
</script>

<div class="sc-zone-flow" style={containerStyle}>
	{#each placements as placement (placement.id)}
		<SlotRenderer
			id={placement.id}
			placementType={placement.type}
			constraints={slotSizeConstraints[placement.id]}
			preferredSize={slotPreferredSizes[placement.id]}
			defaultExpand={ !scrollable && expandSlots }
			mainAxis={flexDir}
		/>
	{/each}
</div>
