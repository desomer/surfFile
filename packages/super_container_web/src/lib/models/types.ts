export type ThemeMode = 'light' | 'dark' | 'system';

export type DesignSystem = 'material' | 'neumorphism' | 'liquidGlass';
export type InteractionEffect = 'none' | 'ripple' | 'scale' | 'glow';
export type HoverTint = 'material' | 'accent' | 'custom';
export type BorderLine = 'solid' | 'dashed' | 'dotted';
export type SurfacePattern = 'none' | 'grain' | 'lines' | 'dots';
export type ContainerFillType = 'solid' | 'linear' | 'radial' | 'sweep';
export type ImageFit = 'cover' | 'contain' | 'fill' | 'fitWidth' | 'fitHeight' | 'none' | 'scaleDown';

export type Quad = [number, number, number, number]; // [top/topLeft, right/topRight, bottom/bottomRight, left/bottomLeft]

export interface JsonTextBinding {
	repositoryId?: string;
	path: string;
}

export interface ContainerFill {
	type: ContainerFillType;
	start: string;
	end: string;
	angle: number;
	radius: number;
	imageUrl?: string;
	imageFit: ImageFit;
	imageOpacity: number;
	imageBinding?: JsonTextBinding;
}

export interface ShadowSpec {
	enabled: boolean;
	color: string;
	opacity: number;
	blur: number;
	spread: number;
	dx: number;
	dy: number;
}

export interface NeonStyle {
	enabled: boolean;
	color?: string;
	intensity: number;
}

export interface TransformSpec {
	dx: number;
	dy: number;
	rotation: number; // degrees
	scale: number;
}

export type AutomaticState =
	| 'hover'
	| 'pressed'
	| 'focused'
	| 'selected'
	| 'disabled'
	| 'empty'
	| 'error'
	| 'contentHover';

export interface SurfaceStyleStates {
	activeState?: string;
	named: Record<string, Partial<ContainerStyle>>;
	automatic: Partial<Record<AutomaticState, Partial<ContainerStyle>>>;
}

export interface ContainerStyle {
	color?: string;
	fill: ContainerFill;
	radius: number;
	borderWidth: number;
	borderColor?: string;
	elevation: number;
	shadowOpacity: number;
	neon?: NeonStyle;
	padding: number;
	margin: number;
	designSystem: DesignSystem;
	interactionEffect: InteractionEffect;
	hoverEffect: boolean;
	hoverTint: HoverTint;
	hoverColor?: string;
	radii?: Quad;
	borderWidths?: Quad;
	borderLine: BorderLine;
	shadow?: ShadowSpec;
	innerShadow?: ShadowSpec;
	opacity: number;
	paddingInsets?: Quad;
	marginInsets?: Quad;
	backdropBlur?: number;
	pattern: SurfacePattern;
	patternOpacity: number;
	transform?: TransformSpec;
	propertyBindings: Record<string, JsonTextBinding>;
	states?: SurfaceStyleStates;
}

export type SuperLayoutZone =
	| 'nw'
	| 'north'
	| 'ne'
	| 'west'
	| 'center'
	| 'east'
	| 'sw'
	| 'south'
	| 'se';

export type CornerMerge = 'none' | 'row' | 'column';
export type SlotSizeUnit = 'px' | 'percent';
export type SlotPercentBasis = 'zone' | 'layout';

export interface SlotDimension {
	value: number;
	unit: SlotSizeUnit;
}

export interface SlotSizeConstraints {
	minWidth?: SlotDimension;
	minHeight?: SlotDimension;
	maxWidth?: SlotDimension;
	maxHeight?: SlotDimension;
	preferredWidth?: SlotDimension;
	preferredHeight?: SlotDimension;
	padding: number;
	paddingInsets?: Quad;
	percentBasis: SlotPercentBasis;
	fitContent?: boolean;
}

export interface ScrollbarStyleConfig {
	thumbVisibility: boolean;
	trackVisibility: boolean;
	interactive: boolean;
	thickness: number;
	radius: number;
	mainAxisMargin: number;
	crossAxisMargin: number;
	thumbColor?: string;
	trackColor?: string;
	trackBorderColor?: string;
	side: 'auto' | 'start' | 'end';
}

export type MainAxisAlignment =
	| 'start'
	| 'center'
	| 'end'
	| 'spaceBetween'
	| 'spaceAround'
	| 'spaceEvenly';

export type CrossAxisAlignment = 'start' | 'center' | 'end' | 'stretch';

export interface ZoneFlowConfig {
	scrollable: boolean;
	showScrollbar: boolean;
	scrollbarStyle?: ScrollbarStyleConfig;
	expandSlots: boolean;
	mainAxisAlignment: MainAxisAlignment;
	crossAxisAlignment: CrossAxisAlignment;
	spacing: number;
	padding: number;
	paddingInsets?: Quad;
}

export interface SlotPlacementRef {
	id: string;
	type: string;
}

export interface GridSlotPosition {
	x: number;
	y: number;
	width: number;
	height: number;
}

export interface GridLayoutConfig {
	columns: number;
	rowHeight: number;
	gap: number;
	compact: boolean;
	items: Record<string, GridSlotPosition>;
}

export interface SuperLayoutConfig {
	type: 'layout';
	label?: string;
	positioning: 'zones' | 'grid';
	north: boolean;
	south: boolean;
	west: boolean;
	east: boolean;
	nw: CornerMerge;
	ne: CornerMerge;
	sw: CornerMerge;
	se: CornerMerge;
	northSize: number;
	southSize: number;
	westSize: number;
	eastSize: number;
	resizeSides: boolean;
	sideResizing: Partial<Record<SuperLayoutZone, boolean>>;
	collapsedSides: SuperLayoutZone[];
	autoSides: SuperLayoutZone[];
	placements: Partial<Record<SuperLayoutZone, SlotPlacementRef[]>>;
	slotTypes: Record<string, string>;
	slotPreferredSizes: Record<string, [number | null, number | null]>;
	slotSizeConstraints: Record<string, SlotSizeConstraints>;
	zoneAxes: Partial<Record<SuperLayoutZone, 'row' | 'column'>>;
	zoneFlows: Partial<Record<SuperLayoutZone, ZoneFlowConfig>>;
	slotLabels: Record<string, string>;
	grid?: GridLayoutConfig;
}

export interface NativeShapeConfig {
	kind: 'rounded' | 'continuous' | 'beveled' | 'stadium' | 'linear';
	radius: number;
	radii?: Quad;
	borderWidth: number;
	borderColor?: string;
	top: boolean;
	right: boolean;
	bottom: boolean;
	left: boolean;
}

export interface NativeComponentConfig {
	type: 'native' | 'scaffold';
	binding?: JsonTextBinding;
	properties: Record<string, unknown>;
	regions: Record<string, boolean>;
	regionAxes: Record<string, 'horizontal' | 'vertical' | 'row' | 'column'>;
	regionFlows: Record<string, ZoneFlowConfig>;
	regionSizes: Record<string, number>;
	placements: Record<string, SlotPlacementRef[]>;
	slotTypes: Record<string, string>;
	slotPreferredSizes: Record<string, [number | null, number | null]>;
	slotSizeConstraints: Record<string, SlotSizeConstraints>;
	slotLabels: Record<string, string>;
}

export interface SuperTextFieldConfig {
	variant: 'outlined' | 'filled' | 'underlined' | 'bare';
	dense: boolean;
	prefixIcon?: string;
	suffixIcon?: string;
	prefixText?: string;
	suffixText?: string;
	helperText?: string;
	errorText?: string;
	showCounter: boolean;
	maxLength?: number;
	clearButton: boolean;
	obscureToggle: boolean;
	fillColor?: string;
	borderColor?: string;
	focusedBorderColor?: string;
	radius?: number;
	borderWidth?: number;
	contentPadding?: Quad;
}

export interface ComponentStates<T> {
	activeState?: string;
	named: Record<string, Partial<T>>;
	automatic: Partial<Record<AutomaticState, Partial<T>>>;
}

export interface SuperValueConfig {
	type: 'value';
	mode: 'display' | 'input';
	kind: 'text' | 'checkbox' | 'switchControl';
	initialText: string;
	initialBool: boolean;
	label: string;
	placeholder: string;
	enabled: boolean;
	readOnly: boolean;
	obscureText: boolean;
	minLines: number;
	maxLines: number;
	fontFamily?: string;
	fontSize?: number;
	fontWeight?: number | string;
	italic?: boolean;
	color?: string;
	textAlign: 'start' | 'center' | 'end' | 'left' | 'right' | 'justify';
	lineHeight?: number;
	letterSpacing?: number;
	binding?: JsonTextBinding;
	propertyBindings: Record<string, JsonTextBinding>;
	field: SuperTextFieldConfig;
	states?: ComponentStates<SuperValueConfig>;
}

export type SuperActionVariant =
	| 'filled'
	| 'tonal'
	| 'elevated'
	| 'outlined'
	| 'text'
	| 'icon'
	| 'surface';

export interface SuperActionConfig {
	type: 'action';
	kind: 'text' | 'icon' | 'textAndIcon';
	variant: SuperActionVariant;
	label: string;
	tooltip: string;
	icon: string;
	iconPosition: 'leading' | 'trailing';
	iconSize?: number;
	iconSpacing: number;
	enabled: boolean;
	fontFamily?: string;
	fontSize?: number;
	fontWeight?: number | string;
	italic?: boolean;
	color?: string;
	iconColor?: string;
	backgroundColor?: string;
	borderColor?: string;
	radius?: number;
	borderWidth?: number;
	elevation?: number;
	horizontalPadding?: number;
	verticalPadding?: number;
	textAlign: 'start' | 'center' | 'end' | 'left' | 'right' | 'justify';
	letterSpacing?: number;
	style?: ContainerStyle;
	propertyBindings: Record<string, JsonTextBinding>;
	states?: ComponentStates<SuperActionConfig>;
}

export interface SuperListViewConfig {
	type: 'list';
	binding?: JsonTextBinding;
	axis: 'vertical' | 'horizontal';
	wrap: boolean;
	wrapSizing: 'fixed' | 'automatic';
	itemWidth: number;
	itemExtent: number;
	spacing: number;
	allowAdd: boolean;
	allowRemove: boolean;
	emptyText: string;
	itemId?: string;
	template: SuperLayoutConfig;
}

export interface SuperTabConfig {
	type: 'tab';
	mode: 'static' | 'dynamic';
	binding?: JsonTextBinding;
	tabBarPosition: 'top' | 'bottom';
	isScrollable: boolean;
	initialIndex: number;
	tabAlignment?: 'fill' | 'start' | 'startOffset' | 'center';
	tabBarStyle: ContainerStyle;
	indicatorKind: 'underline' | 'box' | 'none';
	indicatorSize: 'tab' | 'label';
	indicatorColor?: string;
	indicatorWeight: number;
	indicatorRadius: number;
	indicatorHorizontalPadding: number;
	indicatorVerticalPadding: number;
	labelColor?: string;
	unselectedLabelColor?: string;
	dividerColor?: string;
	dividerHeight: number;
	allowAdd: boolean;
	allowRemove: boolean;
	emptyText: string;
	placements: Record<string, SlotPlacementRef[]>;
	slotTypes: Record<string, string>;
	slotSizeConstraints: Record<string, SlotSizeConstraints>;
	slotLabels: Record<string, string>;
}

export interface GenericComponentConfig {
	type: 'table' | 'treeView' | 'chart' | 'unknown';
	rawType: string;
	raw: Record<string, unknown>;
}

export type ComponentConfig =
	| SuperLayoutConfig
	| NativeComponentConfig
	| SuperValueConfig
	| SuperActionConfig
	| SuperListViewConfig
	| SuperTabConfig
	| GenericComponentConfig;

export interface GoToPageAction {
	type: 'goToPage';
	pagePath: string;
	pageId?: string;
	pageName?: string;
}

export type BehaviorAction = GoToPageAction | { type: string; [key: string]: unknown };

export interface ComponentBehavior {
	id: string;
	trigger: 'click' | string;
	enabled: boolean;
	action: BehaviorAction;
}

export interface EditorPageConfig {
	id: string;
	name: string;
	path: string;
	defaultParameters: Record<string, string>;
}

export interface EditorPageCatalog {
	pages: EditorPageConfig[];
	homePageId: string | null;
}

export interface Appearance {
	version: number;
	mode: ThemeMode;
	accent: string;
	backgroundOpacity: number;
	windowOpacity: number;
	windowEffect: string;
	styles: Record<string, ContainerStyle>;
	components: Record<string, ComponentConfig>;
	behaviors: Record<string, ComponentBehavior[]>;
	pageCatalog: EditorPageCatalog;
	cardHeight: number;
	cardWidth: number;
	rowHeight: number;
	spacing: number;
	fontSize: number;
	iconSize: number;
	scrollFadeEnabled: boolean;
	scrollFadeExtent: number;
}
