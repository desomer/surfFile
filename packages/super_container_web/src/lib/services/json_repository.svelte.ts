import { getContext, hasContext, setContext } from 'svelte';
import type { JsonTextBinding } from '../models/types.js';
import {
	appendArrayItem,
	readJsonPath,
	removeArrayItem,
	resolvePath,
	writeJsonPath
} from './json_path.js';

export interface JsonListScopeContext {
	repositoryId?: string;
	arrayPath: string;
	indices: number[];
}

export interface ResolvedBinding {
	repositoryId: string;
	resolvedPath: string;
	isResolved: boolean;
}

const REPOSITORY_STORE_CONTEXT_KEY = Symbol('JsonRepositoryStore');
const JSON_LIST_SCOPE_CONTEXT_KEY = Symbol('JsonListScopeContext');

/**
 * Builds a child `JsonListScopeContext` for a row at `index` inside a list component.
 */
export function childListScope(
	parent: JsonListScopeContext | undefined,
	binding: JsonTextBinding | undefined,
	index: number
): JsonListScopeContext {
	const repositoryId = binding?.repositoryId || parent?.repositoryId;
	const parentIndices = parent?.indices ?? [];
	const rawArrayPath =
		binding?.path !== undefined && binding.path !== ''
			? binding.path
			: (parent?.arrayPath ?? '');
	const { resolvedPath } = resolvePath(rawArrayPath, parentIndices);

	return {
		repositoryId,
		arrayPath: resolvedPath,
		indices: [...parentIndices, index]
	};
}

/**
 * SSR-safe reactive store for JSON repositories and master-detail row selections using Svelte 5 `$state`.
 */
export class JsonRepositoryStore {
	documents = $state<Record<string, unknown>>({});
	names = $state<Record<string, string>>({});
	selectedIndices = $state<Record<string, Record<string, number>>>({});

	constructor(
		initialDocuments?: Record<string, unknown>,
		initialNames?: Record<string, string>
	) {
		if (initialDocuments) {
			for (const [id, doc] of Object.entries(initialDocuments)) {
				this.setRepository(id, doc, initialNames?.[id]);
			}
		}
		if (initialNames) {
			for (const [id, name] of Object.entries(initialNames)) {
				this.names[id] = name;
			}
		}
	}

	setRepository(id: string, data: unknown, name?: string): void {
		this.documents[id] = data;
		if (name !== undefined) {
			this.names[id] = name;
		}
		if (!this.selectedIndices[id]) {
			this.selectedIndices[id] = {};
		}
	}

	getRepository(id: string): unknown {
		return this.documents[id];
	}

	selectRow(repositoryId: string, arrayPath: string, index: number): void {
		if (!this.selectedIndices[repositoryId]) {
			this.selectedIndices[repositoryId] = {};
		}
		this.selectedIndices[repositoryId][arrayPath] = index;
	}

	getSelectedRow(repositoryId: string, arrayPath: string): number | undefined {
		return this.selectedIndices[repositoryId]?.[arrayPath];
	}

	resolveBinding(
		binding: JsonTextBinding | undefined,
		scope?: JsonListScopeContext
	): ResolvedBinding | null {
		if (!binding) {
			return null;
		}

		const repositoryId =
			binding.repositoryId && binding.repositoryId.trim() !== ''
				? binding.repositoryId
				: scope?.repositoryId;

		if (!repositoryId) {
			return null;
		}

		const indices = scope?.indices ?? [];
		const selectedByArrayPath = this.selectedIndices[repositoryId];
		const { resolvedPath, isResolved } = resolvePath(
			binding.path,
			indices,
			selectedByArrayPath
		);

		return {
			repositoryId,
			resolvedPath,
			isResolved
		};
	}

	readBinding(binding: JsonTextBinding | undefined, scope?: JsonListScopeContext): unknown {
		const resolved = this.resolveBinding(binding, scope);
		if (!resolved || !resolved.isResolved) {
			return undefined;
		}

		const doc = this.documents[resolved.repositoryId];
		if (doc === undefined) {
			return undefined;
		}

		return readJsonPath(doc, resolved.resolvedPath);
	}

	writeBinding(
		binding: JsonTextBinding | undefined,
		value: unknown,
		scope?: JsonListScopeContext
	): void {
		const resolved = this.resolveBinding(binding, scope);
		if (!resolved || !resolved.isResolved) {
			return;
		}

		const currentDoc = this.documents[resolved.repositoryId];
		this.documents[resolved.repositoryId] = writeJsonPath(
			currentDoc,
			resolved.resolvedPath,
			value
		);
	}

	addRow(binding: JsonTextBinding | undefined, scope?: JsonListScopeContext): void {
		const resolved = this.resolveBinding(binding, scope);
		if (!resolved || !resolved.isResolved) {
			return;
		}

		const currentDoc = this.documents[resolved.repositoryId];
		this.documents[resolved.repositoryId] = appendArrayItem(
			currentDoc,
			resolved.resolvedPath
		);
	}

	removeRow(
		binding: JsonTextBinding | undefined,
		index: number,
		scope?: JsonListScopeContext
	): void {
		const resolved = this.resolveBinding(binding, scope);
		if (!resolved || !resolved.isResolved) {
			return;
		}

		const currentDoc = this.documents[resolved.repositoryId];
		this.documents[resolved.repositoryId] = removeArrayItem(
			currentDoc,
			resolved.resolvedPath,
			index
		);

		const repoSelections = this.selectedIndices[resolved.repositoryId];
		if (repoSelections && resolved.resolvedPath in repoSelections) {
			const selected = repoSelections[resolved.resolvedPath];
			if (selected === index) {
				delete repoSelections[resolved.resolvedPath];
			} else if (selected !== undefined && selected > index) {
				repoSelections[resolved.resolvedPath] = selected - 1;
			}
		}
	}
}

export function setRepositoryStoreContext(
	store: JsonRepositoryStore = new JsonRepositoryStore()
): JsonRepositoryStore {
	return setContext(REPOSITORY_STORE_CONTEXT_KEY, store);
}

export function getRepositoryStoreContext(): JsonRepositoryStore | undefined {
	if (!hasContext(REPOSITORY_STORE_CONTEXT_KEY)) {
		return undefined;
	}
	return getContext<JsonRepositoryStore>(REPOSITORY_STORE_CONTEXT_KEY);
}

export function setJsonListScopeContext(scope: JsonListScopeContext): JsonListScopeContext {
	return setContext(JSON_LIST_SCOPE_CONTEXT_KEY, scope);
}

export function getJsonListScopeContext(): JsonListScopeContext | undefined {
	if (!hasContext(JSON_LIST_SCOPE_CONTEXT_KEY)) {
		return undefined;
	}
	return getContext<JsonListScopeContext>(JSON_LIST_SCOPE_CONTEXT_KEY);
}
