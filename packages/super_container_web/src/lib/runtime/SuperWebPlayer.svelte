<script lang="ts">
	import { untrack } from 'svelte';
	import type { Appearance } from '$lib/models/types.js';
	import {
		extractReferencedRepositoryIds,
		parseAppearanceExport
	} from '$lib/models/codec.js';
	import {
		JsonRepositoryStore,
		setRepositoryStoreContext
	} from '$lib/services/json_repository.svelte.js';
	import {
		PlayerRuntimeState,
		setPlayerRuntimeContext
	} from '$lib/runtime/player_context.svelte.js';
	import { buildContainerStyleCss } from '$lib/styles/container_style_css.js';
	import SlotRenderer from '../components/SlotRenderer.svelte';

	interface Props {
		initialAppearance: Appearance;
		initialRepositories: Record<string, { name: string; data: unknown }>;
		currentPath?: string;
		onNavigate?: (path: string) => void;
	}

	let {
		initialAppearance,
		initialRepositories,
		currentPath = '/',
		onNavigate
	}: Props = $props();

	const repoStore = untrack(() => {
		const initialDocs: Record<string, unknown> = {};
		const initialNames: Record<string, string> = {};
		for (const [id, entry] of Object.entries(initialRepositories)) {
			initialDocs[id] = entry.data;
			initialNames[id] = entry.name;
		}
		return new JsonRepositoryStore(initialDocs, initialNames);
	});
	setRepositoryStoreContext(repoStore);

	const player = untrack(
		() => new PlayerRuntimeState(initialAppearance, currentPath, onNavigate)
	);
	setPlayerRuntimeContext(player);

	$effect(() => {
		player.currentPath = currentPath;
	});

	let loaderOpen = $state(false);
	let exportJsonInput = $state('');
	let repoIdInput = $state('');
	let repoJsonInput = $state('');
	let importError = $state<string | null>(null);
	let importSuccess = $state<string | null>(null);

	const activePageInfo = $derived(player.resolveActivePage(player.currentPath));
	const referencedRepoIds = $derived(extractReferencedRepositoryIds(player.appearance));

	const backgroundCss = $derived.by(() => {
		const bgStyle = player.appearance.styles.background;
		if (!bgStyle) {
			return player.appearance.mode === 'dark'
				? 'background: #171A23; color: #F8F9FC; padding: 12px;'
				: 'background: #F8F9FC; color: #1A1D26; padding: 12px;';
		}
		return buildContainerStyleCss(bgStyle, {
			accent: player.appearance.accent,
			mode: player.appearance.mode,
			isBackground: true,
			backgroundOpacity: player.appearance.backgroundOpacity
		});
	});

	function handleApplyExportJson() {
		importError = null;
		importSuccess = null;
		try {
			const parsed = JSON.parse(exportJsonInput) as Record<string, unknown>;
			// Support combined bundle `{ appearance, repositories }` or direct AppearanceTransfer export
			if (parsed.appearance && typeof parsed.appearance === 'object') {
				const nextApp = parseAppearanceExport(parsed.appearance as Record<string, unknown>);
				player.setAppearance(nextApp);
				if (parsed.repositories && typeof parsed.repositories === 'object') {
					for (const [id, val] of Object.entries(
						parsed.repositories as Record<string, unknown>
					)) {
						repoStore.setRepository(id, val, `${id.slice(0, 8)}.json`);
					}
				}
			} else {
				const nextApp = parseAppearanceExport(parsed);
				player.setAppearance(nextApp);
			}
			importSuccess = 'Export JSON chargé avec succès !';
		} catch (err) {
			importError = err instanceof Error ? err.message : 'JSON invalide.';
		}
	}

	async function handleExportFileUpload(e: Event) {
		const file = (e.currentTarget as HTMLInputElement).files?.[0];
		if (!file) return;
		exportJsonInput = await file.text();
		handleApplyExportJson();
	}

	function handleApplyRepoJson() {
		importError = null;
		importSuccess = null;
		const targetId =
			repoIdInput.trim() || referencedRepoIds[0] || '0123456789abcdef0123456789abcdef';
		try {
			const data = JSON.parse(repoJsonInput);
			repoStore.setRepository(targetId, data, `${targetId.slice(0, 8)}.json`);
			importSuccess = `Repository "${targetId}" mis à jour !`;
		} catch (err) {
			importError = err instanceof Error ? err.message : 'JSON de repository invalide.';
		}
	}

	async function handleRepoFileUpload(e: Event) {
		const file = (e.currentTarget as HTMLInputElement).files?.[0];
		if (!file) return;
		repoJsonInput = await file.text();
		if (!repoIdInput.trim() && referencedRepoIds.length > 0) {
			repoIdInput = referencedRepoIds[0];
		}
		handleApplyRepoJson();
	}
</script>

<div class="sc-player-viewport" style={backgroundCss}>
	<div class="sc-player-stage">
		<SlotRenderer
			id={activePageInfo.rootSlotId}
			placementType="scaffold"
			defaultExpand={true}
		/>
	</div>

	<!-- Floating trigger to load/inspect JSON exports & repositories -->
	<button
		type="button"
		class="sc-loader-trigger"
		title="Charger un export JSON / Repository"
		onclick={() => (loaderOpen = !loaderOpen)}
	>
		<span class="material-icons">{loaderOpen ? 'close' : 'upload_file'}</span>
		<span>Export JSON</span>
	</button>

	{#if loaderOpen}
		<!-- svelte-ignore a11y_click_events_have_key_events -->
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<div class="sc-loader-backdrop" onclick={() => (loaderOpen = false)}>
			<div class="sc-loader-drawer" role="dialog" tabindex="-1" onclick={(e) => e.stopPropagation()}>
				<header class="sc-loader-header">
					<div>
						<h2>Chargeur d’export & Repositories</h2>
						<p>Importez un export <code>AppearanceTransfer</code> et vos fichiers <code>JsonRepository</code></p>
					</div>
					<button type="button" class="sc-icon-btn" onclick={() => (loaderOpen = false)}>
						<span class="material-icons">close</span>
					</button>
				</header>

				{#if importError}
					<div class="sc-alert error">{importError}</div>
				{/if}
				{#if importSuccess}
					<div class="sc-alert success">{importSuccess}</div>
				{/if}

				{#if player.appearance.pageCatalog.pages.length > 0}
					<section class="sc-loader-section">
						<h3>Pages de l’export (SEO & Routage)</h3>
						<div class="sc-page-pills">
							{#each player.appearance.pageCatalog.pages as pg (pg.id)}
								<a
									href={pg.path}
									class="sc-page-pill"
									class:active={activePageInfo.page?.id === pg.id}
									onclick={() => {
										player.currentPath = pg.path;
									}}
								>
									<span class="material-icons" style="font-size: 15px;">web</span>
									<span>{pg.name}</span>
									<code>{pg.path}</code>
								</a>
							{/each}
						</div>
					</section>
				{/if}

				<section class="sc-loader-section">
					<div class="sc-section-title-row">
						<h3>1. Export JSON Appearance</h3>
						<label class="sc-file-btn">
							<span class="material-icons" style="font-size: 16px;">folder_open</span>
							<span>Fichier .json</span>
							<input type="file" accept=".json,application/json" onchange={handleExportFileUpload} />
						</label>
					</div>
					<textarea
						rows="6"
						placeholder="Collez ici le JSON exporté depuis AppearanceTransfer.export(...)..."
						bind:value={exportJsonInput}
					></textarea>
					<button type="button" class="sc-primary-btn" onclick={handleApplyExportJson}>
						Appliquer l’export JSON
					</button>
				</section>

				<section class="sc-loader-section">
					<div class="sc-section-title-row">
						<h3>2. Données JsonRepository</h3>
						<label class="sc-file-btn">
							<span class="material-icons" style="font-size: 16px;">data_object</span>
							<span>Charger .json</span>
							<input type="file" accept=".json,application/json" onchange={handleRepoFileUpload} />
						</label>
					</div>
					{#if referencedRepoIds.length > 0}
						<div class="sc-repo-chips">
							<span>IDs détectés :</span>
							{#each referencedRepoIds as rId (rId)}
								<button
									type="button"
									class="sc-repo-chip"
									onclick={() => {
										repoIdInput = rId;
										const current = repoStore.getRepository(rId);
										if (current) repoJsonInput = JSON.stringify(current, null, 2);
									}}
								>
									{rId.slice(0, 12)}…
								</button>
							{/each}
						</div>
					{/if}
					<input
						type="text"
						class="sc-text-input"
						placeholder="ID du repository (32 caractères hex)"
						bind:value={repoIdInput}
					/>
					<textarea
						rows="6"
						placeholder="Collez ici le contenu JSON du repository..."
						bind:value={repoJsonInput}
					></textarea>
					<button type="button" class="sc-primary-btn" onclick={handleApplyRepoJson}>
						Mettre à jour le Repository
					</button>
				</section>
			</div>
		</div>
	{/if}
</div>

<style>
	.sc-player-viewport {
		width: 100vw;
		height: 100vh;
		display: flex;
		flex-direction: column;
		overflow: hidden;
		position: relative;
		box-sizing: border-box;
	}
	.sc-player-stage {
		flex: 1 1 0%;
		min-height: 0;
		min-width: 0;
		width: 100%;
		height: 100%;
		display: flex;
		flex-direction: column;
	}
	.sc-loader-trigger {
		position: fixed;
		right: 18px;
		bottom: 18px;
		z-index: 900;
		display: inline-flex;
		align-items: center;
		gap: 6px;
		padding: 8px 14px;
		border-radius: 999px;
		border: 1px solid rgba(82, 104, 217, 0.35);
		background: rgba(25, 30, 46, 0.88);
		color: #ffffff;
		font-size: 12px;
		font-weight: 600;
		cursor: pointer;
		backdrop-filter: blur(10px);
		box-shadow: 0 6px 20px rgba(0, 0, 0, 0.22);
	}
	.sc-loader-backdrop {
		position: fixed;
		inset: 0;
		background: rgba(15, 20, 34, 0.45);
		z-index: 1000;
		display: flex;
		justify-content: flex-end;
	}
	.sc-loader-drawer {
		width: min(460px, 94vw);
		height: 100%;
		background: #ffffff;
		color: #1b2234;
		padding: 20px;
		overflow-y: auto;
		display: flex;
		flex-direction: column;
		gap: 18px;
		box-shadow: -8px 0 32px rgba(0, 0, 0, 0.18);
	}
	.sc-loader-header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 12px;
	}
	.sc-loader-header h2 {
		margin: 0;
		font-size: 17px;
	}
	.sc-loader-header p {
		margin: 4px 0 0;
		font-size: 12px;
		color: #64708b;
	}
	.sc-icon-btn {
		border: none;
		background: #f1f4fb;
		border-radius: 8px;
		padding: 6px;
		cursor: pointer;
	}
	.sc-loader-section {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 12px;
		border-radius: 12px;
		background: #f7f9fe;
		border: 1px solid #e3e9f6;
	}
	.sc-loader-section h3 {
		margin: 0;
		font-size: 13px;
	}
	.sc-section-title-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}
	.sc-file-btn {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		font-size: 12px;
		font-weight: 600;
		color: #5268d9;
		cursor: pointer;
	}
	.sc-file-btn input {
		display: none;
	}
	.sc-loader-section textarea,
	.sc-text-input {
		width: 100%;
		border: 1px solid #cfd7e6;
		border-radius: 8px;
		padding: 8px 10px;
		font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
		font-size: 12px;
	}
	.sc-primary-btn {
		background: #5268d9;
		color: #ffffff;
		border: none;
		border-radius: 8px;
		padding: 9px 14px;
		font-size: 13px;
		font-weight: 600;
		cursor: pointer;
	}
	.sc-page-pills {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.sc-page-pill {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 8px 10px;
		border-radius: 8px;
		background: #ffffff;
		border: 1px solid #dce3f2;
		text-decoration: none;
		color: #1b2234;
		font-size: 12px;
	}
	.sc-page-pill.active {
		border-color: #5268d9;
		background: #eef1ff;
		font-weight: 600;
	}
	.sc-page-pill code {
		margin-left: auto;
		color: #5268d9;
	}
	.sc-repo-chips {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 6px;
		font-size: 11px;
		color: #5f6b86;
	}
	.sc-repo-chip {
		border: 1px solid #c6d0e8;
		background: #ffffff;
		border-radius: 6px;
		padding: 2px 8px;
		font-family: monospace;
		font-size: 11px;
		cursor: pointer;
	}
	.sc-alert {
		padding: 10px 12px;
		border-radius: 8px;
		font-size: 12px;
		font-weight: 500;
	}
	.sc-alert.error {
		background: #fdecec;
		color: #b82828;
	}
	.sc-alert.success {
		background: #eaf8f0;
		color: #167946;
	}
</style>
