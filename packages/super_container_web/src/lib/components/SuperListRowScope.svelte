<script lang="ts">
	import type { Snippet } from 'svelte';
	import type { JsonTextBinding } from '$lib/models/types.js';
	import {
		childListScope,
		getJsonListScopeContext,
		setJsonListScopeContext
	} from '$lib/services/json_repository.svelte.js';
	import { setContentHoverScope } from '$lib/runtime/player_context.svelte.js';

	interface Props {
		binding?: JsonTextBinding;
		index: number;
		isHovered?: boolean;
		children: Snippet;
	}

	let { binding, index, isHovered = false, children }: Props = $props();

	const parentScope = getJsonListScopeContext();
	const currentScope = $derived(childListScope(parentScope, binding, index));

	// Provide reactive scope to children
	setJsonListScopeContext({
		get repositoryId() {
			return currentScope.repositoryId;
		},
		get arrayPath() {
			return currentScope.arrayPath;
		},
		get indices() {
			return currentScope.indices;
		}
	});

	setContentHoverScope(() => isHovered);
</script>

{@render children()}
