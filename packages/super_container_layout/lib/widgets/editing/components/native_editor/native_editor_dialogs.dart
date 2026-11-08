// Boîtes de dialogue de configuration des régions, propriétés et flux flex
// d'un [NativeComponentEditorState].
part of '../native_component_editor.dart';

/// Extension gérant les dialogues de configuration et d'édition de flux d'un [NativeComponentEditorState].
extension NativeComponentEditorDialogs on NativeComponentEditorState {
  EditorDimensionDelegate _buildRegionFlowDelegate(
    String id, {
    NativeComponentConfig? initialOverride,
  }) {
    final spec = definition(id);
    final initial = initialOverride ?? _config.value;
    return NativeRegionFlowDimensionDelegate(
      title: 'Flux de la zone : ${spec.label}',
      onRestore: () {
        if (mounted) _update(initial);
      },
      onReset: () {
        _update(
          _config.value
              .withRegionAxis(id, spec.axis, defaultAxis: spec.axis)
              .withRegionFlow(id, const ZoneFlowConfig())
              .withRegionSize(id, null),
        );
      },
      builder: (context) => ListenableBuilder(
        listenable: _config,
        builder: (context, _) {
          final current = _config.value;
          final defaultSize = spec.emptySize.height.isFinite
              ? spec.emptySize.height
              : 100.0;
          final fixedSize = current.regionSizeOf(id);
          final effectiveAxis = current.regionAxisOf(id) ?? spec.axis;
          final hasNaturalHeight = effectiveAxis == Axis.vertical
              ? !spec.expand
              : !spec.stretch;
          return ZoneFlowSettingsEditor(
            keyPrefix: '${widget.keyPrefix}-flow-dialog-$id',
            axis: effectiveAxis,
            flow: current.regionFlowOf(id),
            isSide: true,
            sizeAxis: hasNaturalHeight ? Axis.vertical : null,
            autoSize: fixedSize == null,
            size: fixedSize ?? defaultSize,
            onAutoSizeChanged: (auto) => _update(
              current.withRegionSize(
                id,
                auto ? null : (fixedSize ?? defaultSize),
              ),
            ),
            onSizeChanged: (value) =>
                _update(current.withRegionSize(id, value)),
            onAxisChanged: (axis) => _update(
              current.withRegionAxis(id, axis, defaultAxis: spec.axis),
            ),
            onFlowChanged: (flow) => _update(current.withRegionFlow(id, flow)),
          );
        },
      ),
    );
  }

  Future<void> _openRegionFlowEditor(String id) async {
    if (widget.onEditRegion != null) {
      await EditorWizardNavigation.openWithTab(
        EditorWizardTab.dimensions,
        () => widget.onEditRegion!(id),
        delegate: _buildRegionFlowDelegate(id),
      );
      return;
    }
    await configure(regionId: id, initialTab: EditorWizardTab.dimensions);
  }

  /// Ouvre la boîte de dialogue de configuration des régions et propriétés natives.
  Future<void> configure({
    String? regionId,
    EditorWizardTab? initialTab,
  }) async {
    final targetRegion = regionId;
    if (targetRegion == null) {
      select(null);
    }
    final requestedTab = EditorWizardNavigation.consumeInitialTab(initialTab);
    final initial = _config.value;
    final regionDelegate =
        targetRegion != null && definition(targetRegion).editableFlow
        ? _buildRegionFlowDelegate(targetRegion, initialOverride: initial)
        : null;
    if (widget.onConfigure != null) {
      await EditorWizardNavigation.openWithTab(
        requestedTab,
        widget.onConfigure!,
        delegate: regionDelegate,
      );
      return;
    }
    final delegate =
        regionDelegate ??
        EditorWizardNavigation.resolveDimensionDelegate(context);
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    final activated = <String>{};
    var confirmed = false;
    try {
      confirmed =
          await showEditorDialog<bool>(
            context: context,
            target:
                (targetRegion != null ? _regionContext(targetRegion) : null) ??
                context,
            barrierDismissible: true,
            barrierColor: targetRegion != null ? Colors.transparent : null,
            builder: (dialogContext) => EditorTabbedAlertDialog(
              dialogKey: ValueKey('${widget.keyPrefix}-settings'),
              applyButtonKey: ValueKey('${widget.keyPrefix}-settings-apply'),
              cancelButtonKey: ValueKey('${widget.keyPrefix}-settings-cancel'),
              initialTab: requestedTab,
              propertiesTitle: Text(widget.settingsTitle),
              propertiesWidth: widget.propertyDescriptors.isEmpty ? 360 : 420,
              dimensionDelegate: delegate,
              propertiesContentBuilder: (context) =>
                  ValueListenableBuilder<NativeComponentConfig>(
                    valueListenable: _config,
                    builder: (context, config, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...?widget.settingsControls?.call(config, _update),
                        for (final region in widget.regions)
                          if (!region.required &&
                              (widget.isRegionAvailable?.call(
                                    config,
                                    region.id,
                                  ) ??
                                  true))
                            SwitchListTile(
                              key: ValueKey(
                                '${widget.keyPrefix}-switch-${region.id}',
                              ),
                              title: Text(region.label),
                              value: config.isEnabled(region.id),
                              onChanged: (value) {
                                _update(
                                  _config.value.withRegionEnabled(
                                    region.id,
                                    value,
                                  ),
                                );
                                if (value) activated.add(region.id);
                              },
                            ),
                        if (widget.propertyDescriptors.isNotEmpty) ...[
                          const Divider(),
                          for (final descriptor in widget.propertyDescriptors)
                            if (widget.isPropertyAvailable?.call(
                                  config,
                                  descriptor,
                                ) ??
                                true)
                              buildNativePropertyControl(
                                context: context,
                                keyPrefix: widget.keyPrefix,
                                config: config,
                                descriptor: descriptor,
                                onChanged: (next) => _update(
                                  _config.value.withProperty(
                                    descriptor.id,
                                    next.property(descriptor.id),
                                  ),
                                ),
                              ),
                        ],
                      ],
                    ),
                  ),
              propertiesExtraActions: [
                TextButton(
                  key: ValueKey('${widget.keyPrefix}-settings-reset'),
                  onPressed: () {
                    activated.clear();
                    _update(_config.value.withSettingsReset());
                  },
                  child: const Text('Réinitialiser'),
                ),
              ],
              onApply: () async {
                delegate?.apply();
                Navigator.of(dialogContext).pop(true);
                return true;
              },
              onCancel: () => Navigator.of(dialogContext).pop(false),
            ),
          ) ==
          true;
    } finally {
      if (!confirmed && mounted) {
        delegate?.restore();
        _update(initial);
      }
      if (confirmed) {
        history?.commitTransaction();
      } else {
        history?.cancelTransaction();
      }
      delegate?.dispose();
    }
    if (confirmed && mounted) {
      widget.onConfigured?.call(activated.where(enabled).toSet());
    }
  }
}
