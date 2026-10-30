<script lang="ts">
	import { goto } from '$app/navigation';
	import SuperWebPlayer from '$lib/runtime/SuperWebPlayer.svelte';
	import type { Appearance } from '$lib/models/types.js';

	interface Props {
		data: {
			appearance: Appearance;
			repositories: Record<string, { name: string; data: unknown }>;
			currentPath: string;
		};
	}

	let { data }: Props = $props();

	const activePage = $derived.by(() => {
		const pages = data.appearance.pageCatalog.pages;
		return (
			pages.find((p) => p.path === data.currentPath) ??
			pages.find((p) => p.id === data.appearance.pageCatalog.homePageId) ??
			pages[0] ??
			null
		);
	});

	const pageTitle = $derived(
		activePage ? `${activePage.name} | SuperContainer Web` : 'SuperContainer Web Player'
	);

	const pageDescription = $derived(
		activePage
			? `Page "${activePage.name}" (${activePage.path}) rendue côté serveur (SSR/SEO) par le moteur SuperContainer Web.`
			: 'Moteur de rendu Web SSR/SEO pour exports JSON super_container_layout.'
	);

	function handleNavigate(path: string) {
		goto(path);
	}
</script>

<svelte:head>
	<title>{pageTitle}</title>
	<meta name="description" content={pageDescription} />
	<meta property="og:title" content={pageTitle} />
	<meta property="og:description" content={pageDescription} />
	<meta property="og:type" content="website" />
</svelte:head>

<SuperWebPlayer
	initialAppearance={data.appearance}
	initialRepositories={data.repositories}
	currentPath={data.currentPath}
	onNavigate={handleNavigate}
/>
