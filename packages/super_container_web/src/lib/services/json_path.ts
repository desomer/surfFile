export type JsonPathSegment = string | number | '?';

export interface ResolvedJsonPath {
	resolvedPath: string;
	isResolved: boolean;
}

const SEGMENT_PATTERN = /(?:^|\.)([^.\[\]\s?]+)|\[([0-9]+|\?)\]/g;

/**
 * Parses a JSON attribute path (e.g. `client.nom`, `clients[0].nom`,
 * `clients[?].commandes[?].ref`, or `""`) into an array of segments.
 */
export function parseJsonPath(path: string): JsonPathSegment[] {
	const trimmed = path.trim();
	if (trimmed === '') {
		return [];
	}

	const segments: JsonPathSegment[] = [];
	let offset = 0;
	SEGMENT_PATTERN.lastIndex = 0;

	let match: RegExpExecArray | null;
	while ((match = SEGMENT_PATTERN.exec(trimmed)) !== null) {
		const fullMatch = match[0];
		const keySegment = match[1];
		const bracketSegment = match[2];

		if (match.index !== offset) {
			throw new Error(`Invalid JSON attribute path: "${path}"`);
		}

		if (keySegment !== undefined) {
			const hasLeadingDot = fullMatch.startsWith('.');
			if ((offset === 0 && hasLeadingDot) || (offset > 0 && !hasLeadingDot)) {
				throw new Error(`Invalid JSON attribute path: "${path}"`);
			}
			segments.push(keySegment);
		} else if (bracketSegment !== undefined) {
			if (bracketSegment === '?') {
				segments.push('?');
			} else {
				const parsed = Number.parseInt(bracketSegment, 10);
				if (!Number.isInteger(parsed) || parsed < 0) {
					throw new Error(`Invalid JSON array index in path: "${path}"`);
				}
				segments.push(parsed);
			}
		}

		offset = match.index + fullMatch.length;
	}

	if (offset !== trimmed.length) {
		throw new Error(`Invalid JSON attribute path: "${path}"`);
	}

	return segments;
}

/**
 * Formats an array of path segments back into canonical path notation.
 */
export function formatJsonPath(segments: readonly JsonPathSegment[]): string {
	let result = '';
	for (const segment of segments) {
		if (typeof segment === 'string' && segment !== '?') {
			if (result.length > 0) {
				result += '.';
			}
			result += segment;
		} else if (segment === '?') {
			result += '[?]';
		} else {
			result += `[${segment}]`;
		}
	}
	return result;
}

/**
 * Counts the number of `[?]` wildcards in `path`.
 */
export function countWildcards(path: string): number {
	const trimmed = path.trim();
	if (trimmed === '') {
		return 0;
	}
	try {
		return parseJsonPath(trimmed).filter((segment) => segment === '?').length;
	} catch {
		const matches = trimmed.match(/\[\?\]/g);
		return matches ? matches.length : 0;
	}
}

/**
 * Resolves `[?]` wildcards in `path` from outermost array to innermost array:
 * 1. First using `indices` from enclosing `JsonListScope`s.
 * 2. For any remaining `[?]`, looks up the array prefix path (e.g. `clients`
 *    or `clients[0].commandes`) in `selectedIndicesByArrayPath`. If a selected
 *    index exists (`>= 0`), substitutes it; otherwise `isResolved` is `false`.
 */
export function resolvePath(
	path: string,
	indices: number[] = [],
	selectedIndicesByArrayPath?: Record<string, number>
): ResolvedJsonPath {
	const trimmed = path.trim();
	if (trimmed === '') {
		return { resolvedPath: '', isResolved: true };
	}

	let segments: JsonPathSegment[];
	try {
		segments = parseJsonPath(trimmed);
	} catch {
		return { resolvedPath: trimmed, isResolved: false };
	}

	const resolvedSegments: JsonPathSegment[] = [];
	const templateSegments: JsonPathSegment[] = [];
	let wildcardOrdinal = 0;
	let isResolved = true;

	for (const segment of segments) {
		if (segment !== '?') {
			resolvedSegments.push(segment);
			templateSegments.push(segment);
			continue;
		}

		const scopeIndex = wildcardOrdinal < indices.length ? indices[wildcardOrdinal] : undefined;
		wildcardOrdinal += 1;

		if (typeof scopeIndex === 'number' && Number.isInteger(scopeIndex) && scopeIndex >= 0) {
			resolvedSegments.push(scopeIndex);
			templateSegments.push('?');
			continue;
		}

		const resolvedPrefix = formatJsonPath(resolvedSegments);
		const templatePrefix = formatJsonPath(templateSegments);
		const selectedIndex =
			selectedIndicesByArrayPath?.[resolvedPrefix] ??
			selectedIndicesByArrayPath?.[templatePrefix];

		if (
			typeof selectedIndex === 'number' &&
			Number.isInteger(selectedIndex) &&
			selectedIndex >= 0
		) {
			resolvedSegments.push(selectedIndex);
			templateSegments.push('?');
		} else {
			isResolved = false;
			resolvedSegments.push('?');
			templateSegments.push('?');
		}
	}

	return {
		resolvedPath: formatJsonPath(resolvedSegments),
		isResolved
	};
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function cloneJsonValue<T>(value: T): T {
	if (Array.isArray(value)) {
		return value.map((item) => cloneJsonValue(item)) as unknown as T;
	}
	if (isPlainObject(value)) {
		const copy: Record<string, unknown> = {};
		for (const [k, v] of Object.entries(value)) {
			copy[k] = cloneJsonValue(v);
		}
		return copy as unknown as T;
	}
	return value;
}

/**
 * Reads the value at `resolvedPath` from `doc`.
 * An empty string `""` returns `doc` itself (root or current element).
 */
export function readJsonPath(doc: unknown, resolvedPath: string): unknown {
	if (doc === undefined || doc === null) {
		return undefined;
	}

	const trimmed = resolvedPath.trim();
	if (trimmed === '') {
		return doc;
	}

	let segments: JsonPathSegment[];
	try {
		segments = parseJsonPath(trimmed);
	} catch {
		return undefined;
	}

	let current: unknown = doc;
	for (const segment of segments) {
		if (segment === '?' || current === undefined || current === null) {
			return undefined;
		}
		if (typeof segment === 'string') {
			if (!isPlainObject(current)) {
				return undefined;
			}
			current = current[segment];
		} else {
			if (!Array.isArray(current) || segment < 0 || segment >= current.length) {
				return undefined;
			}
			current = current[segment];
		}
	}

	return current;
}

/**
 * Immutably writes `newValue` at `resolvedPath` in `doc` and returns the updated document.
 * Intermediate objects are created if missing.
 */
export function writeJsonPath(doc: unknown, resolvedPath: string, newValue: unknown): unknown {
	const trimmed = resolvedPath.trim();
	if (trimmed === '') {
		return cloneJsonValue(newValue);
	}

	let segments: JsonPathSegment[];
	try {
		segments = parseJsonPath(trimmed);
	} catch {
		return doc;
	}

	if (segments.some((segment) => segment === '?')) {
		return doc;
	}

	function updateNode(current: unknown, depth: number): unknown {
		if (depth === segments.length) {
			return cloneJsonValue(newValue);
		}

		const segment = segments[depth];
		const nextSegment = segments[depth + 1];

		if (typeof segment === 'string') {
			const baseObj: Record<string, unknown> = isPlainObject(current) ? { ...current } : {};
			const currentChild = baseObj[segment];
			const initialChild =
				currentChild !== undefined
					? currentChild
					: depth + 1 < segments.length
						? typeof nextSegment === 'number'
							? []
							: {}
						: undefined;
			baseObj[segment] = updateNode(initialChild, depth + 1);
			return baseObj;
		}

		if (typeof segment === 'number') {
			if (!Array.isArray(current) || segment < 0 || segment >= current.length) {
				return current;
			}
			const nextArray = [...current];
			nextArray[segment] = updateNode(nextArray[segment], depth + 1);
			return nextArray;
		}

		return current;
	}

	return updateNode(doc, 0);
}

/**
 * Creates a blank template value preserving the structure of `sample`:
 * `""` for strings, `0` for numbers, `false` for booleans, `[]` for arrays,
 * and recursively blanked keys for plain objects.
 */
export function createBlankItem(sample: unknown): unknown {
	if (typeof sample === 'string') {
		return '';
	}
	if (typeof sample === 'number') {
		return 0;
	}
	if (typeof sample === 'boolean') {
		return false;
	}
	if (Array.isArray(sample)) {
		return [];
	}
	if (isPlainObject(sample)) {
		const result: Record<string, unknown> = {};
		for (const [key, value] of Object.entries(sample)) {
			result[key] = createBlankItem(value);
		}
		return result;
	}
	return null;
}

/**
 * Appends a new item to the array at `arrayPath` and returns an immutably updated document.
 * If `templateItem` is omitted, infers a blank item from existing array items or defaults to `{}`.
 */
export function appendArrayItem(
	doc: unknown,
	arrayPath: string,
	templateItem?: unknown
): unknown {
	const current = readJsonPath(doc, arrayPath);

	if (current !== undefined && current !== null && !Array.isArray(current)) {
		return doc;
	}

	const existingArray = Array.isArray(current) ? current : [];
	let itemToAppend: unknown;

	if (templateItem !== undefined) {
		itemToAppend = cloneJsonValue(templateItem);
	} else if (existingArray.length > 0) {
		const sample = existingArray[existingArray.length - 1];
		itemToAppend = sample !== null && sample !== undefined ? createBlankItem(sample) : {};
	} else {
		itemToAppend = {};
	}

	const updatedArray = [...existingArray, itemToAppend];
	return writeJsonPath(doc, arrayPath, updatedArray);
}

/**
 * Removes the item at `index` from the array at `arrayPath` and returns an immutably updated document.
 */
export function removeArrayItem(doc: unknown, arrayPath: string, index: number): unknown {
	const current = readJsonPath(doc, arrayPath);
	if (!Array.isArray(current) || index < 0 || index >= current.length) {
		return doc;
	}

	const updatedArray = current.filter((_, itemIndex) => itemIndex !== index);
	return writeJsonPath(doc, arrayPath, updatedArray);
}

/**
 * Object-oriented wrapper for JSON attribute paths, mirroring Dart's `JsonAttributePath`.
 */
export class JsonAttributePath {
	readonly raw: string;
	readonly segments: readonly JsonPathSegment[];

	constructor(path: string) {
		this.raw = path.trim();
		this.segments = parseJsonPath(this.raw);
	}

	get wildcardCount(): number {
		return this.segments.filter((segment) => segment === '?').length;
	}

	get isResolved(): boolean {
		return this.wildcardCount === 0;
	}

	get arrayTemplates(): string[] {
		const templates: string[] = [];
		for (let i = 0; i < this.segments.length; i++) {
			if (this.segments[i] === '?') {
				templates.push(formatJsonPath(this.segments.slice(0, i)));
			}
		}
		return templates;
	}

	resolve(
		indices: number[] = [],
		selectedIndicesByArrayPath?: Record<string, number>
	): ResolvedJsonPath {
		return resolvePath(this.raw, indices, selectedIndicesByArrayPath);
	}

	read(doc: unknown): unknown {
		if (!this.isResolved) {
			return undefined;
		}
		return readJsonPath(doc, this.toString());
	}

	write(doc: unknown, newValue: unknown): unknown {
		if (!this.isResolved) {
			return doc;
		}
		return writeJsonPath(doc, this.toString(), newValue);
	}

	toString(): string {
		return formatJsonPath(this.segments);
	}

	static countWildcards = countWildcards;
	static resolvePath = resolvePath;
	static readJsonPath = readJsonPath;
	static writeJsonPath = writeJsonPath;
	static appendArrayItem = appendArrayItem;
	static removeArrayItem = removeArrayItem;
}
