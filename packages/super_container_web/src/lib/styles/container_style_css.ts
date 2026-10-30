import { parseJsonColor, parseOptionalColor, parseQuad } from '../models/codec.js';
import type {
 AutomaticState,
 ContainerStyle,
 ImageFit,
 NativeShapeConfig,
 Quad,
 ShadowSpec,
 SlotDimension,
 SlotSizeConstraints,
 ThemeMode
} from '../models/types.js';

const AUTOMATIC_STATE_PRIORITY: AutomaticState[] = [
 'disabled',
 'error',
 'empty',
 'selected',
 'focused',
 'contentHover',
 'hover',
 'pressed'
];

function mergeContainerStyle(
 base: ContainerStyle,
 patch?: Partial<ContainerStyle>
): ContainerStyle {
 if (!patch) return base;
 const merged: ContainerStyle = {
 ...base,
 ...patch,
 fill: patch.fill ? { ...base.fill, ...patch.fill } : { ...base.fill }
 };
 if ('radius' in patch && !('radii' in patch)) {
 merged.radii = undefined;
 }
 if ('borderWidth' in patch && !('borderWidths' in patch)) {
 merged.borderWidths = undefined;
 }
 if ('padding' in patch && !('paddingInsets' in patch)) {
 merged.paddingInsets = undefined;
 }
 if ('margin' in patch && !('marginInsets' in patch)) {
 merged.marginInsets = undefined;
 }
 return merged;
}

/**
 * Merges `base` with `base.states?.named[namedState || base.states.activeState]`
 * and any matching `base.states?.automatic[state]` in priority order
 * (`disabled`, `error`, `empty`, `selected`, `focused`, `contentHover`, `hover`, `pressed`).
 */
export function resolveEffectiveContainerStyle(
 base: ContainerStyle,
 activeStates: Set<AutomaticState>,
 namedState?: string
): ContainerStyle {
 let resolved: ContainerStyle = {
 ...base,
 fill: { ...base.fill }
 };
 const states = base.states;
 if (!states) return resolved;

 const targetNamed = namedState || states.activeState;
 if (targetNamed && states.named?.[targetNamed]) {
 resolved = mergeContainerStyle(resolved, states.named[targetNamed]);
 }

 if (states.automatic && activeStates && activeStates.size > 0) {
 for (const state of AUTOMATIC_STATE_PRIORITY) {
 if (activeStates.has(state) && states.automatic[state]) {
 resolved = mergeContainerStyle(resolved, states.automatic[state]);
 }
 }
 }

 return resolved;
}

export interface ContainerStyleCssOptions {
 accent?: string;
 mode?: ThemeMode;
 isBackground?: boolean;
 backgroundOpacity?: number;
 dynamicImageUrl?: string;
}

interface RgbaColor {
 r: number;
 g: number;
 b: number;
 a: number;
}

function clamp(val: number, min: number, max: number): number {
 return Math.max(min, Math.min(max, val));
}

const RGBA_PATTERN = new RegExp(
 'rgba?\\(\\s*(\\d+(?:\\.\\d+)?)\\s*,\\s*(\\d+(?:\\.\\d+)?)\\s*,\\s*(\\d+(?:\\.\\d+)?)(?:\\s*,\\s*(\\d+(?:\\.\\d+)?))?\\s*\\)',
 'i'
);

function parseColorToRgba(colorStr: string | undefined, fallback = '#FFFFFF'): RgbaColor {
 const normalized = parseJsonColor(colorStr ?? fallback, fallback);
 if (normalized.startsWith('#')) {
 const hex = normalized.slice(1);
 if (hex.length === 3) {
 return {
 r: parseInt(hex[0] + hex[0], 16),
 g: parseInt(hex[1] + hex[1], 16),
 b: parseInt(hex[2] + hex[2], 16),
 a: 1
 };
 }
 if (hex.length >= 6) {
 return {
 r: parseInt(hex.slice(0, 2), 16),
 g: parseInt(hex.slice(2, 4), 16),
 b: parseInt(hex.slice(4, 6), 16),
 a: 1
 };
 }
 }
 const rgbaMatch = normalized.match(RGBA_PATTERN);
 if (rgbaMatch) {
 return {
 r: clamp(Math.round(Number(rgbaMatch[1])), 0, 255),
 g: clamp(Math.round(Number(rgbaMatch[2])), 0, 255),
 b: clamp(Math.round(Number(rgbaMatch[3])), 0, 255),
 a: rgbaMatch[4] !== undefined ? clamp(Number(rgbaMatch[4]), 0, 1) : 1
 };
 }
 return { r: 255, g: 255, b: 255, a: 1 };
}

function toRgbaCss(c: RgbaColor, overrideAlpha?: number): string {
 const a = clamp(overrideAlpha !== undefined ? overrideAlpha : c.a, 0, 1);
 if (a >= 0.999) {
 const rx = c.r.toString(16).padStart(2, '0');
 const gx = c.g.toString(16).padStart(2, '0');
 const bx = c.b.toString(16).padStart(2, '0');
 return ('#' + rx + gx + bx).toUpperCase();
 }
 return 'rgba(' + c.r + ', ' + c.g + ', ' + c.b + ', ' + Number(a.toFixed(3)) + ')';
}

function applyAlphaToColorString(colorStr: string, alphaMultiplier: number): string {
 const c = parseColorToRgba(colorStr);
 return toRgbaCss(c, c.a * clamp(alphaMultiplier, 0, 1));
}

function shiftLightness(c: RgbaColor, delta: number, alpha = 1): string {
 const factor = clamp(Math.abs(delta), 0, 1);
 const target = delta >= 0 ? 255 : 0;
 const r = clamp(Math.round(c.r + (target - c.r) * factor), 0, 255);
 const g = clamp(Math.round(c.g + (target - c.g) * factor), 0, 255);
 const b = clamp(Math.round(c.b + (target - c.b) * factor), 0, 255);
 return toRgbaCss({ r, g, b, a: alpha });
}

function computeRelativeLuminance(c: RgbaColor): number {
 const srgb = [c.r / 255, c.g / 255, c.b / 255].map((v) =>
 v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
 );
 return 0.2126 * srgb[0] + 0.7152 * srgb[1] + 0.0722 * srgb[2];
}

function formatImageUrlForCss(rawUrl: string): string {
 const trimmed = rawUrl.trim();
 if (trimmed.startsWith('<svg')) {
 const encoded = encodeURIComponent(trimmed)
 .split(String.fromCharCode(39)).join('%27')
 .split('(').join('%28')
 .split(')').join('%29');
 return 'url("data:image/svg+xml;utf8,' + encoded + '")';
 }
 const escaped = trimmed.split('"').join('\"');
 return 'url("' + escaped + '")';
}

function mapImageFitToBackgroundSize(fit: ImageFit | undefined): string {
 switch (fit) {
 case 'cover':
 return 'cover';
 case 'contain':
 return 'contain';
 case 'fill':
 return '100% 100%';
 case 'fitWidth':
 return '100% auto';
 case 'fitHeight':
 return 'auto 100%';
 case 'none':
 return 'none';
 case 'scaleDown':
 return 'contain';
 default:
 return 'cover';
 }
}

function buildPatternLayer(
 pattern: ContainerStyle['pattern'],
 opacity: number,
 isDark: boolean
): { image: string; size?: string } | undefined {
 const alpha = Number(clamp(opacity || 0.1, 0, 1).toFixed(3));
 if (alpha <= 0 || pattern === 'none') return undefined;
 const ink = isDark ? 'rgba(255, 255, 255, ' + alpha + ')' : 'rgba(0, 0, 0, ' + alpha + ')';
 const softAlpha = Number((alpha * 0.5).toFixed(3));
 const inkSoft = isDark
 ? 'rgba(255, 255, 255, ' + softAlpha + ')'
 : 'rgba(0, 0, 0, ' + softAlpha + ')';

 switch (pattern) {
 case 'dots':
 return {
 image: 'radial-gradient(circle, ' + ink + ' 1px, transparent 1px)',
 size: '12px 12px'
 };
 case 'lines':
 return {
 image:
 'repeating-linear-gradient(45deg, ' +
 ink +
 ' 0px, ' +
 ink +
 ' 1px, transparent 1px, transparent 8px)'
 };
 case 'grain':
 return {
 image:
 'radial-gradient(circle at 20% 30%, ' +
 ink +
 ' 0.75px, transparent 1px), radial-gradient(circle at 75% 65%, ' +
 inkSoft +
 ' 0.75px, transparent 1px)',
 size: '6px 6px'
 };
 default:
 return undefined;
 }
}

function formatShadowSpec(spec: ShadowSpec, inset = false): string {
 const c = parseColorToRgba(spec.color, '#000000');
 const rgba = toRgbaCss(c, clamp(spec.opacity, 0, 1));
 const prefix = inset ? 'inset ' : '';
 return prefix + spec.dx + 'px ' + spec.dy + 'px ' + spec.blur + 'px ' + spec.spread + 'px ' + rgba;
}

function formatQuadPx(quad: Quad): string {
 return quad[0] + 'px ' + quad[1] + 'px ' + quad[2] + 'px ' + quad[3] + 'px';
}

/**
 * Returns a valid inline CSS string (`key: value; ...`) for a `ContainerStyle`.
 */
export function buildContainerStyleCss(
 style: ContainerStyle,
 options?: ContainerStyleCssOptions
): string {
 const mode: ThemeMode = options?.mode ?? 'light';
 const isDarkMode = mode === 'dark';
 const accent = options?.accent ?? '#5268D9';
 const bgOpacity =
 options?.isBackground && typeof options.backgroundOpacity === 'number'
 ? clamp(options.backgroundOpacity, 0, 1)
 : 1;

 const defaultSurface = isDarkMode ? '#1E2230' : '#FFFFFF';
 const fillType = style.fill?.type ?? 'solid';
 const rawBaseColor =
 style.color ?? (fillType !== 'solid' ? style.fill.start : undefined) ?? defaultSurface;
 const baseRgba = parseColorToRgba(rawBaseColor, defaultSurface);
 const lum = computeRelativeLuminance(baseRgba);
 const isDarkSurface = lum < 0.45;
 const contrastTextColor = isDarkSurface ? '#F8F9FC' : '#1A1D26';

 const declarations: string[] = [];
 declarations.push('box-sizing: border-box');

 // Background & Fill
 const bgLayers: string[] = [];
 const bgSizes: string[] = [];
 const bgPositions: string[] = [];
 const bgRepeats: string[] = [];

 // 1. Pattern layer
 const patternLayer = buildPatternLayer(style.pattern, style.patternOpacity, isDarkSurface);
 if (patternLayer) {
 bgLayers.push(patternLayer.image);
 bgSizes.push(patternLayer.size ?? 'auto');
 bgPositions.push('0 0');
 bgRepeats.push('repeat');
 }

 // 2. Image / dynamicImageUrl layer
 const effectiveImageUrl = options?.dynamicImageUrl?.trim() || style.fill?.imageUrl?.trim();
 if (effectiveImageUrl) {
 const imageOpacity = clamp((style.fill?.imageOpacity ?? 1) * bgOpacity, 0, 1);
 if (imageOpacity < 0.999) {
 const overlayAlpha = Number((1 - imageOpacity).toFixed(3));
 const maskColor = toRgbaCss(baseRgba, overlayAlpha * bgOpacity);
 bgLayers.push('linear-gradient(' + maskColor + ', ' + maskColor + ')');
 bgSizes.push('100% 100%');
 bgPositions.push('center');
 bgRepeats.push('no-repeat');
 }
 bgLayers.push(formatImageUrlForCss(effectiveImageUrl));
 bgSizes.push(mapImageFitToBackgroundSize(style.fill?.imageFit));
 bgPositions.push('center');
 bgRepeats.push('no-repeat');
 }

 // 3. Fill gradient or solid / liquidGlass surface
 const startColor = applyAlphaToColorString(style.fill?.start ?? rawBaseColor, bgOpacity);
 const endColor = applyAlphaToColorString(style.fill?.end ?? rawBaseColor, bgOpacity);
 const angle = typeof style.fill?.angle === 'number' ? style.fill.angle : 45;
 const radiusPct = Math.round(
 (typeof style.fill?.radius === 'number' ? style.fill.radius : 0.8) * 100
 );

 if (fillType === 'linear') {
 bgLayers.push('linear-gradient(' + angle + 'deg, ' + startColor + ', ' + endColor + ')');
 bgSizes.push('100% 100%');
 bgPositions.push('center');
 bgRepeats.push('no-repeat');
 } else if (fillType === 'radial') {
 bgLayers.push(
 'radial-gradient(circle, ' + startColor + ' 0%, ' + endColor + ' ' + radiusPct + '%)'
 );
 bgSizes.push('100% 100%');
 bgPositions.push('center');
 bgRepeats.push('no-repeat');
 } else if (fillType === 'sweep') {
 bgLayers.push(
 'conic-gradient(from ' +
 angle +
 'deg, ' +
 startColor +
 ', ' +
 endColor +
 ', ' +
 startColor +
 ')'
 );
 bgSizes.push('100% 100%');
 bgPositions.push('center');
 bgRepeats.push('no-repeat');
 } else if (style.designSystem === 'liquidGlass') {
 const glassAlpha = clamp((baseRgba.a < 1 ? baseRgba.a : 0.38) * bgOpacity, 0.08, 0.85);
 const glassStart = shiftLightness(baseRgba, isDarkSurface ? 0.18 : 0.25, glassAlpha);
 const glassEnd = shiftLightness(baseRgba, isDarkSurface ? -0.05 : -0.04, glassAlpha * 0.72);
 bgLayers.push('linear-gradient(135deg, ' + glassStart + ', ' + glassEnd + ')');
 bgSizes.push('100% 100%');
 bgPositions.push('center');
 bgRepeats.push('no-repeat');
 }

 if (style.designSystem === 'liquidGlass') {
 const fallbackGlassColor = toRgbaCss(
 baseRgba,
 clamp((baseRgba.a < 1 ? baseRgba.a : 0.28) * bgOpacity, 0.05, 0.85)
 );
 declarations.push('background-color: ' + fallbackGlassColor);
 } else {
 const solidCss = toRgbaCss(baseRgba, baseRgba.a * bgOpacity);
 declarations.push('background-color: ' + solidCss);
 }

 if (bgLayers.length > 0) {
 declarations.push('background-image: ' + bgLayers.join(', '));
 declarations.push('background-size: ' + bgSizes.join(', '));
 declarations.push('background-position: ' + bgPositions.join(', '));
 declarations.push('background-repeat: ' + bgRepeats.join(', '));
 }

 // Contrast text color
 declarations.push('color: ' + contrastTextColor);

 // Radii
 if (style.radii && style.radii.length === 4) {
 declarations.push('border-radius: ' + formatQuadPx(style.radii));
 } else if (typeof style.radius === 'number' && style.radius >= 0) {
 declarations.push('border-radius: ' + style.radius + 'px');
 }

 // Borders
 const borderLine = style.borderLine ?? 'solid';
 const defaultBorderColor =
 style.designSystem === 'liquidGlass'
 ? isDarkSurface
 ? 'rgba(255, 255, 255, 0.24)'
 : 'rgba(255, 255, 255, 0.6)'
 : isDarkSurface
 ? 'rgba(255, 255, 255, 0.14)'
 : 'rgba(0, 0, 0, 0.12)';
 const resolvedBorderColor = style.borderColor
 ? parseJsonColor(style.borderColor, defaultBorderColor)
 : defaultBorderColor;

 if (style.borderWidths && style.borderWidths.length === 4) {
 const [bt, br, bb, bl] = style.borderWidths;
 if (bt > 0 || br > 0 || bb > 0 || bl > 0) {
 declarations.push('border-top: ' + bt + 'px ' + borderLine + ' ' + resolvedBorderColor);
 declarations.push('border-right: ' + br + 'px ' + borderLine + ' ' + resolvedBorderColor);
 declarations.push(
 'border-bottom: ' + bb + 'px ' + borderLine + ' ' + resolvedBorderColor
 );
 declarations.push('border-left: ' + bl + 'px ' + borderLine + ' ' + resolvedBorderColor);
 }
 } else if (typeof style.borderWidth === 'number' && style.borderWidth > 0) {
 declarations.push(
 'border: ' + style.borderWidth + 'px ' + borderLine + ' ' + resolvedBorderColor
 );
 } else if (style.designSystem === 'liquidGlass') {
 declarations.push('border: 1px ' + borderLine + ' ' + resolvedBorderColor);
 }

 // Shadows (outer + inner + neon)
 const shadows: string[] = [];
 const elevation = typeof style.elevation === 'number' ? Math.max(0, style.elevation) : 0;
 const shadowOpacity = clamp(
 typeof style.shadowOpacity === 'number' ? style.shadowOpacity : 0.2,
 0,
 1
 );

 if (style.shadow && style.shadow.enabled) {
 shadows.push(formatShadowSpec(style.shadow, false));
 } else if (style.designSystem === 'neumorphism' && elevation > 0) {
 const dist = Math.max(2, Math.round(elevation * 1.2));
 const blur = Math.max(4, Math.round(elevation * 2.5));
 const lightShadowColor = shiftLightness(
 baseRgba,
 isDarkSurface ? 0.16 : 0.45,
 clamp(shadowOpacity * (isDarkSurface ? 0.55 : 0.85), 0.05, 1)
 );
 const darkShadowColor = shiftLightness(
 baseRgba,
 isDarkSurface ? -0.45 : -0.25,
 clamp(shadowOpacity, 0.05, 1)
 );
 shadows.push('-' + dist + 'px -' + dist + 'px ' + blur + 'px 0px ' + lightShadowColor);
 shadows.push(dist + 'px ' + dist + 'px ' + blur + 'px 0px ' + darkShadowColor);
 } else if (elevation > 0) {
 const dy = Math.max(1, Math.round(elevation * 0.9));
 const blur = Math.max(2, Math.round(elevation * 2.2));
 const spread = Math.round(elevation * 0.1);
 const ambientAlpha = Number(clamp(shadowOpacity * 0.45, 0.02, 0.6).toFixed(3));
 const keyAlpha = Number(clamp(shadowOpacity, 0.04, 0.85).toFixed(3));
 shadows.push(
 '0px ' + dy + 'px ' + blur + 'px ' + spread + 'px rgba(0, 0, 0, ' + keyAlpha + ')'
 );
 shadows.push(
 '0px ' +
 Math.max(1, Math.round(dy * 0.4)) +
 'px ' +
 Math.max(2, Math.round(blur * 0.6)) +
 'px 0px rgba(0, 0, 0, ' +
 ambientAlpha +
 ')'
 );
 }

 if (style.innerShadow && style.innerShadow.enabled) {
 shadows.push(formatShadowSpec(style.innerShadow, true));
 }

 if (style.neon && style.neon.enabled) {
 const intensity = Math.max(
 0,
 typeof style.neon.intensity === 'number' ? style.neon.intensity : 0.6
 );
 if (intensity > 0) {
 const neonColor = parseJsonColor(style.neon.color || accent, accent);
 const r1 = Number((12 * intensity).toFixed(2));
 const r2 = Number((28 * intensity).toFixed(2));
 shadows.push('0 0 ' + r1 + 'px ' + neonColor);
 shadows.push('0 0 ' + r2 + 'px ' + neonColor);
 }
 }

 if (shadows.length > 0) {
 declarations.push('box-shadow: ' + shadows.join(', '));
 }

 // Spacing: padding & margin
 if (style.paddingInsets && style.paddingInsets.length === 4) {
 declarations.push('padding: ' + formatQuadPx(style.paddingInsets));
 } else if (typeof style.padding === 'number' && style.padding > 0) {
 declarations.push('padding: ' + style.padding + 'px');
 }

 if (style.marginInsets && style.marginInsets.length === 4) {
 declarations.push('margin: ' + formatQuadPx(style.marginInsets));
 } else if (typeof style.margin === 'number' && style.margin !== 0) {
 declarations.push('margin: ' + style.margin + 'px');
 }

 // Opacity
 if (typeof style.opacity === 'number' && style.opacity < 1) {
 declarations.push('opacity: ' + Number(clamp(style.opacity, 0, 1).toFixed(3)));
 }

 // Backdrop Blur
 const blurVal =
 style.designSystem === 'liquidGlass'
 ? (style.backdropBlur ?? 20)
 : (style.backdropBlur ?? 0);
 if (blurVal > 0) {
 declarations.push('backdrop-filter: blur(' + blurVal + 'px)');
 declarations.push('-webkit-backdrop-filter: blur(' + blurVal + 'px)');
 }

 // Transform
 if (style.transform) {
 const { dx = 0, dy = 0, rotation = 0, scale = 1 } = style.transform;
 if (dx !== 0 || dy !== 0 || rotation !== 0 || scale !== 1) {
 declarations.push(
 'transform: translate(' +
 dx +
 'px, ' +
 dy +
 'px) rotate(' +
 rotation +
 'deg) scale(' +
 scale +
 ')'
 );
 }
 }

 // Smooth transition
 declarations.push(
 'transition: background 160ms ease, box-shadow 160ms ease, transform 160ms ease, border-color 160ms ease, opacity 160ms ease'
 );

 return declarations.join('; ') + ';';
}

function parseNativeShape(shapeRaw: unknown): NativeShapeConfig | undefined {
 if (shapeRaw === null || shapeRaw === undefined) return undefined;
 if (typeof shapeRaw === 'number' && Number.isFinite(shapeRaw)) {
 return {
 kind: 'rounded',
 radius: shapeRaw,
 borderWidth: 0,
 top: true,
 right: true,
 bottom: true,
 left: true
 };
 }
 const quadShorthand = parseQuad(shapeRaw);
 if (quadShorthand && Array.isArray(shapeRaw)) {
 return {
 kind: 'rounded',
 radius: quadShorthand[0],
 radii: quadShorthand,
 borderWidth: 0,
 top: true,
 right: true,
 bottom: true,
 left: true
 };
 }
 if (typeof shapeRaw === 'object') {
 const obj = shapeRaw as Record<string, unknown>;
 const rawKind = String(obj.kind ?? obj.type ?? 'rounded');
 const kind: NativeShapeConfig['kind'] =
 rawKind === 'continuous' ||
 rawKind === 'beveled' ||
 rawKind === 'stadium' ||
 rawKind === 'linear'
 ? rawKind
 : 'rounded';
 const radii = parseQuad(obj.radii) ?? parseQuad(obj.radius);
 const radius = typeof obj.radius === 'number' ? obj.radius : radii ? radii[0] : 0;
 const borderWidth = typeof obj.borderWidth === 'number' ? obj.borderWidth : 0;
 const borderColor = parseOptionalColor(obj.borderColor);
 return {
 kind,
 radius,
 radii,
 borderWidth,
 borderColor,
 top: obj.top !== false,
 right: obj.right !== false,
 bottom: obj.bottom !== false,
 left: obj.left !== false
 };
 }
 return undefined;
}

/**
 * Converts `NativeShapeConfig` (or number / Quad shorthand) used by `ApplicationBar`
 * and `BottomAppBar` into CSS `border-radius`, `border`, and `clip-path` (for `beveled`).
 */
export function buildNativeShapeCss(shapeRaw: unknown): string {
 const shape = parseNativeShape(shapeRaw);
 if (!shape) return '';

 const declarations: string[] = [];
 const [tl, tr, br, bl]: Quad = shape.radii ?? [
 shape.radius,
 shape.radius,
 shape.radius,
 shape.radius
 ];

 if (shape.kind === 'stadium') {
 declarations.push('border-radius: 9999px');
 } else if (shape.kind === 'linear') {
 declarations.push('border-radius: 0px');
 } else if (shape.kind === 'beveled') {
 declarations.push(
 'border-radius: ' + tl + 'px ' + tr + 'px ' + br + 'px ' + bl + 'px'
 );
 if (tl > 0 || tr > 0 || br > 0 || bl > 0) {
 declarations.push(
 'clip-path: polygon(' +
 tl +
 'px 0%, calc(100% - ' +
 tr +
 'px) 0%, 100% ' +
 tr +
 'px, 100% calc(100% - ' +
 br +
 'px), calc(100% - ' +
 br +
 'px) 100%, ' +
 bl +
 'px 100%, 0% calc(100% - ' +
 bl +
 'px), 0% ' +
 tl +
 'px)'
 );
 }
 } else {
 declarations.push(
 'border-radius: ' + tl + 'px ' + tr + 'px ' + br + 'px ' + bl + 'px'
 );
 }

 if (shape.borderWidth > 0) {
 const color = shape.borderColor ?? 'rgba(128, 128, 128, 0.25)';
 if (shape.top && shape.right && shape.bottom && shape.left) {
 declarations.push('border: ' + shape.borderWidth + 'px solid ' + color);
 } else {
 if (shape.top) declarations.push('border-top: ' + shape.borderWidth + 'px solid ' + color);
 if (shape.right) {
 declarations.push('border-right: ' + shape.borderWidth + 'px solid ' + color);
 }
 if (shape.bottom) {
 declarations.push('border-bottom: ' + shape.borderWidth + 'px solid ' + color);
 }
 if (shape.left) {
 declarations.push('border-left: ' + shape.borderWidth + 'px solid ' + color);
 }
 }
 }

 return declarations.length > 0 ? declarations.join('; ') + ';' : '';
}

function formatSlotDimension(dim: SlotDimension | undefined): string | undefined {
 if (!dim || !Number.isFinite(dim.value)) return undefined;
 return dim.unit === 'percent' ? dim.value + '%' : dim.value + 'px';
}

/**
 * Generates CSS for slot sizing (`width`, `height`, `min-width`, `min-height`,
 * `max-width`, `max-height`, `padding`, and `flex: 1 1 0%` vs `flex: 0 0 auto`
 * based on `constraints?.fitContent` and `defaultExpand`).
 */
export function buildSlotConstraintsCss(
 constraints: SlotSizeConstraints | undefined,
 preferredSize?: [number | null, number | null],
 defaultExpand = true,
 mainAxis: 'row' | 'column' = 'column'
): string {
 const declarations: string[] = ['box-sizing: border-box'];

 const prefW =
 formatSlotDimension(constraints?.preferredWidth) ??
 (preferredSize && typeof preferredSize[0] === 'number' ? preferredSize[0] + 'px' : undefined);
 const prefH =
 formatSlotDimension(constraints?.preferredHeight) ??
 (preferredSize && typeof preferredSize[1] === 'number' ? preferredSize[1] + 'px' : undefined);

 const minW = formatSlotDimension(constraints?.minWidth);
 const minH = formatSlotDimension(constraints?.minHeight);
 const maxW = formatSlotDimension(constraints?.maxWidth);
 const maxH = formatSlotDimension(constraints?.maxHeight);

 if (prefW) declarations.push('width: ' + prefW);
 if (prefH) declarations.push('height: ' + prefH);
 if (minW) declarations.push('min-width: ' + minW);
 if (minH) declarations.push('min-height: ' + minH);
 if (maxW) declarations.push('max-width: ' + maxW);
 if (maxH) declarations.push('max-height: ' + maxH);

 if (constraints?.paddingInsets && constraints.paddingInsets.length === 4) {
 declarations.push('padding: ' + formatQuadPx(constraints.paddingInsets));
 } else if (constraints && typeof constraints.padding === 'number' && constraints.padding > 0) {
 declarations.push('padding: ' + constraints.padding + 'px');
 }

 const hasExplicitMainSize = mainAxis === 'row' ? Boolean(prefW) : Boolean(prefH);
 const shouldFitContent =
 constraints?.fitContent !== undefined
 ? constraints.fitContent
 : hasExplicitMainSize
 ? true
 : !defaultExpand;

 if (shouldFitContent) {
 declarations.push('flex: 0 0 auto');
 } else {
 declarations.push('flex: 1 1 0%');
 if (mainAxis === 'row' && !minW) {
 declarations.push('min-width: 0');
 } else if (mainAxis === 'column' && !minH) {
 declarations.push('min-height: 0');
 }
 }

 return declarations.join('; ') + ';';
}
