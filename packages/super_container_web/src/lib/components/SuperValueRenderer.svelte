<script lang="ts">
	import type { AutomaticState, SuperValueConfig } from '$lib/models/types.js';
	import {
		getJsonListScopeContext,
		getRepositoryStoreContext
	} from '$lib/services/json_repository.svelte.js';
	import {
		getContentHoverScope,
		getPlayerRuntimeContext
	} from '$lib/runtime/player_context.svelte.js';

	interface Props {
		id: string;
		config: SuperValueConfig;
	}

	let { id, config }: Props = $props();

	const repoStore = getRepositoryStoreContext();
	const listScope = getJsonListScopeContext();
	const contentHover = getContentHoverScope();
	const player = getPlayerRuntimeContext();

	let isHovered = $state(false);
	let isFocused = $state(false);
	let showPassword = $state(false);
	let localText = $state<string | null>(null);
	let localBool = $state<boolean | null>(null);

	const resolvedBinding = $derived(repoStore?.resolveBinding(config.binding, listScope) ?? null);
	const isUnresolvedWildcard = $derived(
		Boolean(config.binding && (!resolvedBinding || !resolvedBinding.isResolved))
	);

	const boundValue = $derived.by(() => {
		if (!config.binding || !repoStore) return undefined;
		return repoStore.readBinding(config.binding, listScope);
	});

	const currentText = $derived.by(() => {
		if (config.binding) {
			if (boundValue === undefined || boundValue === null) return '';
			return String(boundValue);
		}
		return localText ?? config.initialText;
	});

	const currentBool = $derived.by(() => {
		if (config.binding) {
			return Boolean(boundValue);
		}
		return localBool ?? config.initialBool;
	});

	function readPropBinding<T>(prop: string, fallback: T): T {
		const b = config.propertyBindings[prop];
		if (!b || !repoStore) return fallback;
		const v = repoStore.readBinding(b, listScope);
		if (v === undefined || v === null) return fallback;
		return v as T;
	}

	const activeStates = $derived.by(() => {
		const s = new Set<AutomaticState>();
		if (!config.enabled || isUnresolvedWildcard) s.add('disabled');
		if (config.field.errorText) s.add('error');
		if (config.kind === 'text' && !currentText) s.add('empty');
		if (isFocused) s.add('focused');
		if (contentHover?.isHovered) s.add('contentHover');
		if (isHovered) s.add('hover');
		return s;
	});

	const effectiveConfig = $derived.by(() => {
		let merged: SuperValueConfig = { ...config };
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

	const labelText = $derived(String(readPropBinding('label', effectiveConfig.label)));
	const placeholderText = $derived(
		String(readPropBinding('placeholder', effectiveConfig.placeholder))
	);
	const textColor = $derived(readPropBinding('color', effectiveConfig.color));
	const fontSize = $derived(
		Number(readPropBinding('fontSize', effectiveConfig.fontSize ?? player.appearance.fontSize))
	);

	function mapFontWeight(fw?: number | string): string | number {
		if (!fw) return 400;
		if (typeof fw === 'number') return fw;
		switch (fw) {
			case 'light':
				return 300;
			case 'normal':
				return 400;
			case 'medium':
				return 500;
			case 'semibold':
				return 600;
			case 'bold':
				return 700;
			default:
				return fw;
		}
	}

	const typographyStyle = $derived(
		[
			effectiveConfig.fontFamily ? `font-family: ${effectiveConfig.fontFamily}` : '',
			`font-size: ${fontSize}px`,
			`font-weight: ${mapFontWeight(effectiveConfig.fontWeight)}`,
			effectiveConfig.italic ? 'font-style: italic' : '',
			textColor ? `color: ${textColor}` : '',
			`text-align: ${effectiveConfig.textAlign}`,
			effectiveConfig.lineHeight ? `line-height: ${effectiveConfig.lineHeight}` : '',
			effectiveConfig.letterSpacing !== undefined
				? `letter-spacing: ${effectiveConfig.letterSpacing}px`
				: ''
		]
			.filter(Boolean)
			.join('; ')
	);

	function handleTextInput(e: Event) {
		const val = (e.currentTarget as HTMLInputElement | HTMLTextAreaElement).value;
		if (config.binding && repoStore) {
			repoStore.writeBinding(config.binding, val, listScope);
		} else {
			localText = val;
		}
	}

	function clearText() {
		if (config.binding && repoStore) {
			repoStore.writeBinding(config.binding, '', listScope);
		} else {
			localText = '';
		}
	}

	function handleBoolChange(e: Event) {
		const checked = (e.currentTarget as HTMLInputElement).checked;
		if (config.binding && repoStore) {
			repoStore.writeBinding(config.binding, checked, listScope);
		} else {
			localBool = checked;
		}
	}
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
	class="sc-value"
	data-component-id={id}
	onmouseenter={() => (isHovered = true)}
	onmouseleave={() => (isHovered = false)}
>
	{#if effectiveConfig.kind === 'checkbox'}
		<label class="sc-bool-control" style={typographyStyle}>
			<input
				type="checkbox"
				checked={currentBool}
				disabled={!effectiveConfig.enabled || effectiveConfig.readOnly || isUnresolvedWildcard}
				onchange={handleBoolChange}
				style="accent-color: {player.appearance.accent};"
			/>
			{#if labelText || currentText}
				<span>{labelText || currentText}</span>
			{/if}
		</label>
	{:else if effectiveConfig.kind === 'switchControl'}
		<label class="sc-switch-control" style={typographyStyle}>
			{#if labelText || currentText}
				<span class="sc-switch-label">{labelText || currentText}</span>
			{/if}
			<input
				type="checkbox"
				role="switch"
				class="sc-switch-input"
				checked={currentBool}
				disabled={!effectiveConfig.enabled || effectiveConfig.readOnly || isUnresolvedWildcard}
				onchange={handleBoolChange}
				style="--accent: {player.appearance.accent};"
			/>
		</label>
	{:else if effectiveConfig.mode === 'input'}
		{@const fld = effectiveConfig.field}
		{@const borderRadius = fld.radius ?? (fld.variant === 'outlined' || fld.variant === 'filled' ? 10 : 0)}
		<div class="sc-field-wrapper">
			{#if labelText}
				<label class="sc-field-label" for="input-{id}">{labelText}</label>
			{/if}
			<div
				class="sc-field-box variant-{fld.variant}"
				class:focused={isFocused}
				class:dense={fld.dense}
				style="border-radius: {borderRadius}px; {fld.fillColor ? `background: ${fld.fillColor};` : ''} {isFocused && fld.focusedBorderColor ? `border-color: ${fld.focusedBorderColor};` : fld.borderColor ? `border-color: ${fld.borderColor};` : `--focus-color: ${player.appearance.accent};`}"
			>
				{#if fld.prefixIcon}
					<span class="material-icons sc-field-icon">{fld.prefixIcon}</span>
				{/if}
				{#if fld.prefixText}
					<span class="sc-field-affix">{fld.prefixText}</span>
				{/if}

				{#if effectiveConfig.maxLines > 1}
					<textarea
						id="input-{id}"
						rows={effectiveConfig.minLines}
						value={currentText}
						placeholder={placeholderText}
						disabled={!effectiveConfig.enabled || isUnresolvedWildcard}
						readonly={effectiveConfig.readOnly}
						maxlength={fld.maxLength}
						style={typographyStyle}
						onfocus={() => (isFocused = true)}
						onblur={() => (isFocused = false)}
						oninput={handleTextInput}
					></textarea>
				{:else}
					<input
						id="input-{id}"
						type={effectiveConfig.obscureText && !showPassword ? 'password' : 'text'}
						value={currentText}
						placeholder={placeholderText}
						disabled={!effectiveConfig.enabled || isUnresolvedWildcard}
						readonly={effectiveConfig.readOnly}
						maxlength={fld.maxLength}
						style={typographyStyle}
						onfocus={() => (isFocused = true)}
						onblur={() => (isFocused = false)}
						oninput={handleTextInput}
					/>
				{/if}

				{#if fld.suffixText}
					<span class="sc-field-affix">{fld.suffixText}</span>
				{/if}
				{#if fld.clearButton && currentText && effectiveConfig.enabled && !effectiveConfig.readOnly}
					<button type="button" class="sc-field-action" onclick={clearText} title="Effacer">
						<span class="material-icons">close</span>
					</button>
				{/if}
				{#if effectiveConfig.obscureText && fld.obscureToggle}
					<button
						type="button"
						class="sc-field-action"
						onclick={() => (showPassword = !showPassword)}
					>
						<span class="material-icons">{showPassword ? 'visibility_off' : 'visibility'}</span>
					</button>
				{/if}
				{#if fld.suffixIcon}
					<span class="material-icons sc-field-icon">{fld.suffixIcon}</span>
				{/if}
			</div>
			{#if fld.errorText}
				<div class="sc-field-error">{fld.errorText}</div>
			{:else if fld.helperText}
				<div class="sc-field-helper">{fld.helperText}</div>
			{/if}
		</div>
	{:else}
		<div
			class="sc-value-display"
			style="{typographyStyle}; {effectiveConfig.maxLines === 1 ? 'white-space: nowrap; overflow: hidden; text-overflow: ellipsis;' : ''}"
		>
			{currentText || labelText}
		</div>
	{/if}
</div>

<style>
	.sc-value {
		width: 100%;
		min-width: 0;
	}
	.sc-value-display {
		word-break: break-word;
	}
	.sc-bool-control {
		display: inline-flex;
		align-items: center;
		gap: 10px;
		cursor: pointer;
		user-select: none;
	}
	.sc-bool-control input[type='checkbox'] {
		width: 18px;
		height: 18px;
		cursor: pointer;
	}
	.sc-switch-control {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		cursor: pointer;
		user-select: none;
	}
	.sc-switch-input {
		appearance: none;
		width: 42px;
		height: 24px;
		background: #cbd2e1;
		border-radius: 999px;
		position: relative;
		cursor: pointer;
		transition: background 160ms ease;
		margin: 0;
	}
	.sc-switch-input::after {
		content: '';
		position: absolute;
		top: 3px;
		left: 3px;
		width: 18px;
		height: 18px;
		border-radius: 50%;
		background: #ffffff;
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.25);
		transition: transform 160ms ease;
	}
	.sc-switch-input:checked {
		background: var(--accent, #5268d9);
	}
	.sc-switch-input:checked::after {
		transform: translateX(18px);
	}
	.sc-field-wrapper {
		display: flex;
		flex-direction: column;
		gap: 4px;
		width: 100%;
	}
	.sc-field-label {
		font-size: 12px;
		font-weight: 600;
		color: #4f5b76;
	}
	.sc-field-box {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 8px 12px;
		border: 1px solid #cfd7e6;
		background: #ffffff;
		transition: border-color 150ms ease, box-shadow 150ms ease;
	}
	.sc-field-box.dense {
		padding: 5px 10px;
	}
	.sc-field-box.variant-filled {
		background: #f2f5fc;
		border-color: transparent;
		border-bottom: 2px solid #b8c4de;
	}
	.sc-field-box.variant-underlined {
		background: transparent;
		border: none;
		border-bottom: 1.5px solid #cfd7e6;
		border-radius: 0 !important;
		padding-left: 2px;
		padding-right: 2px;
	}
	.sc-field-box.variant-bare {
		background: transparent;
		border: none;
		padding: 2px 0;
	}
	.sc-field-box.focused {
		border-color: var(--focus-color, #5268d9);
		box-shadow: 0 0 0 3px rgba(82, 104, 217, 0.14);
	}
	.sc-field-box input,
	.sc-field-box textarea {
		border: none;
		outline: none;
		background: transparent;
		width: 100%;
		font-family: inherit;
		resize: vertical;
	}
	.sc-field-icon {
		font-size: 18px;
		color: #6b7690;
	}
	.sc-field-affix {
		font-size: 13px;
		color: #6b7690;
	}
	.sc-field-action {
		border: none;
		background: transparent;
		padding: 2px;
		cursor: pointer;
		color: #6b7690;
		display: inline-flex;
		align-items: center;
	}
	.sc-field-action .material-icons {
		font-size: 16px;
	}
	.sc-field-helper {
		font-size: 11px;
		color: #6b7690;
	}
	.sc-field-error {
		font-size: 11px;
		color: #d93838;
	}
</style>
