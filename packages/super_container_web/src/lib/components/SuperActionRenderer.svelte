<script lang="ts">
	import type { AutomaticState, SuperActionConfig } from '$lib/models/types.js';
	import {
		getJsonListScopeContext,
		getRepositoryStoreContext
	} from '$lib/services/json_repository.svelte.js';
	import {
		getContentHoverScope,
		getPlayerRuntimeContext
	} from '$lib/runtime/player_context.svelte.js';
	import { buildContainerStyleCss } from '$lib/styles/container_style_css.js';

	interface Props {
		id: string;
		config: SuperActionConfig;
		onclick?: (e: MouseEvent) => void;
	}

	let { id, config, onclick }: Props = $props();

	const repoStore = getRepositoryStoreContext();
	const listScope = getJsonListScopeContext();
	const contentHover = getContentHoverScope();
	const player = getPlayerRuntimeContext();

	let isHovered = $state(false);
	let isPressed = $state(false);

	function readPropBinding<T>(prop: string, fallback: T): T {
		const b = config.propertyBindings[prop];
		if (!b || !repoStore) return fallback;
		const v = repoStore.readBinding(b, listScope);
		if (v === undefined || v === null) return fallback;
		return v as T;
	}

	const activeStates = $derived.by(() => {
		const s = new Set<AutomaticState>();
		if (!config.enabled) s.add('disabled');
		if (contentHover?.isHovered) s.add('contentHover');
		if (isHovered) s.add('hover');
		if (isPressed) s.add('pressed');
		return s;
	});

	const effective = $derived.by(() => {
		let merged: SuperActionConfig = { ...config };
		const st = config.states;
		if (st) {
			if (st.activeState && st.named[st.activeState]) {
				merged = { ...merged, ...st.named[st.activeState] };
			}
			const order: AutomaticState[] = [
				'disabled',
				'error',
				'empty',
				'selected',
				'focused',
				'contentHover',
				'hover',
				'pressed'
			];
			for (const k of order) {
				if (activeStates.has(k) && st.automatic[k]) {
					merged = { ...merged, ...st.automatic[k] };
				}
			}
		}
		return merged;
	});

	const label = $derived(String(readPropBinding('label', effective.label)));
	const tooltip = $derived(String(readPropBinding('tooltip', effective.tooltip)));
	const iconName = $derived(String(readPropBinding('icon', effective.icon)));
	const enabled = $derived(Boolean(readPropBinding('enabled', effective.enabled)));
	const hasIcon = $derived(effective.kind === 'icon' || effective.kind === 'textAndIcon');
	const hasText = $derived(effective.kind === 'text' || effective.kind === 'textAndIcon');

	// Crawlability SEO: if this action has a goToPage behavior, render an <a href="...">
	const goToPageHref = $derived(player.getGoToPageHref(id));

	const buttonStyle = $derived.by(() => {
		const accent = player.appearance.accent || '#5268D9';
		const radius = effective.radius ?? (effective.kind === 'icon' ? 999 : 20);
		const padX = effective.horizontalPadding ?? (effective.kind === 'icon' ? 8 : 16);
		const padY = effective.verticalPadding ?? (effective.kind === 'icon' ? 8 : 10);

		let bg = effective.backgroundColor;
		let fg = effective.color;
		let border = effective.borderColor
			? `${effective.borderWidth ?? 1}px solid ${effective.borderColor}`
			: 'none';
		let shadow = effective.elevation
			? `0 ${effective.elevation}px ${effective.elevation * 3}px rgba(0,0,0,0.16)`
			: 'none';

		if (!bg || !fg) {
			switch (effective.variant) {
				case 'filled':
					bg = bg ?? accent;
					fg = fg ?? '#FFFFFF';
					break;
				case 'tonal':
					bg = bg ?? 'rgba(82, 104, 217, 0.14)';
					fg = fg ?? accent;
					break;
				case 'elevated':
					bg = bg ?? '#FFFFFF';
					fg = fg ?? accent;
					shadow = effective.elevation ? shadow : '0 2px 6px rgba(0,0,0,0.12)';
					break;
				case 'outlined':
					bg = bg ?? 'transparent';
					fg = fg ?? accent;
					border = effective.borderColor
						? border
						: `${effective.borderWidth ?? 1}px solid ${accent}`;
					break;
				case 'text':
				case 'icon':
					bg = bg ?? 'transparent';
					fg = fg ?? accent;
					break;
				case 'surface':
					bg = bg ?? '#FFFFFF';
					fg = fg ?? '#1B2234';
					break;
			}
		}

		const extraSurface = effective.style
			? buildContainerStyleCss(effective.style, { accent, mode: player.appearance.mode })
			: '';

		return [
			`background: ${bg}`,
			`color: ${fg}`,
			`border: ${border}`,
			`border-radius: ${radius}px`,
			`box-shadow: ${shadow}`,
			`padding: ${padY}px ${padX}px`,
			`gap: ${effective.iconSpacing}px`,
			`font-size: ${effective.fontSize ?? player.appearance.fontSize}px`,
			effective.fontWeight ? `font-weight: ${effective.fontWeight}` : 'font-weight: 500',
			effective.fontFamily ? `font-family: ${effective.fontFamily}` : '',
			effective.italic ? 'font-style: italic' : '',
			effective.letterSpacing !== undefined ? `letter-spacing: ${effective.letterSpacing}px` : '',
			!enabled ? 'opacity: 0.5; pointer-events: none' : 'cursor: pointer',
			extraSurface
		]
			.filter(Boolean)
			.join('; ');
	});

	function handleClick(e: MouseEvent) {
		if (!enabled) {
			e.preventDefault();
			return;
		}
		if (onclick) {
			onclick(e);
		}
		player.executeBehaviors(id, 'click');
	}
</script>

{#snippet actionContent()}
	{#if hasIcon && effective.iconPosition === 'leading'}
		<span
			class="material-icons"
			style="font-size: {effective.iconSize ?? player.appearance.iconSize}px; {effective.iconColor ? `color: ${effective.iconColor};` : ''}"
		>
			{iconName}
		</span>
	{/if}
	{#if hasText}
		<span class="sc-action-label">{label}</span>
	{/if}
	{#if hasIcon && effective.iconPosition === 'trailing'}
		<span
			class="material-icons"
			style="font-size: {effective.iconSize ?? player.appearance.iconSize}px; {effective.iconColor ? `color: ${effective.iconColor};` : ''}"
		>
			{iconName}
		</span>
	{/if}
{/snippet}

{#if goToPageHref}
	<a
		href={goToPageHref}
		class="sc-action sc-action-link"
		data-component-id={id}
		title={tooltip || undefined}
		style={buttonStyle}
		onmouseenter={() => (isHovered = true)}
		onmouseleave={() => {
			isHovered = false;
			isPressed = false;
		}}
		onmousedown={() => (isPressed = true)}
		onmouseup={() => (isPressed = false)}
		onclick={handleClick}
	>
		{@render actionContent()}
	</a>
{:else}
	<button
		type="button"
		class="sc-action"
		data-component-id={id}
		title={tooltip || undefined}
		disabled={!enabled}
		style={buttonStyle}
		onmouseenter={() => (isHovered = true)}
		onmouseleave={() => {
			isHovered = false;
			isPressed = false;
		}}
		onmousedown={() => (isPressed = true)}
		onmouseup={() => (isPressed = false)}
		onclick={handleClick}
	>
		{@render actionContent()}
	</button>
{/if}

<style>
	.sc-action {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		text-decoration: none;
		user-select: none;
		transition: transform 120ms ease, filter 150ms ease, box-shadow 150ms ease;
		box-sizing: border-box;
	}
	.sc-action:hover:not(:disabled) {
		filter: brightness(0.96);
	}
	.sc-action:active:not(:disabled) {
		transform: scale(0.98);
	}
</style>
