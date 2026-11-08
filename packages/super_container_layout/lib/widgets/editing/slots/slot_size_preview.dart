/// Aperçu géométrique interactif (Layout / Zone / Slot) pour l'éditeur de taille de slot ([SlotSizeDimensionDelegate]).
part of 'slot_size_editor.dart';

class _SlotSizePreview extends StatefulWidget {
  const _SlotSizePreview({required this.measure, required this.dimensions});

  final ({Size layout, Rect zone, Rect slot})? Function() measure;
  final SlotSizeConstraints dimensions;

  @override
  State<_SlotSizePreview> createState() => _SlotSizePreviewState();
}

class _SlotSizePreviewState extends State<_SlotSizePreview> {
  ({Size layout, Rect zone, Rect slot})? geometry;

  @override
  void initState() {
    super.initState();
    geometry = widget.measure();
    refresh();
  }

  @override
  void didUpdateWidget(_SlotSizePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    refresh();
  }

  void refresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = widget.measure();
      if (next != geometry) setState(() => geometry = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final measured = geometry;
    if (measured == null || measured.layout.isEmpty) {
      return const Text(
        'Preview indisponible : géométrie du slot non mesurable.',
      );
    }
    final colors = Theme.of(context).colorScheme;
    final basis = widget.dimensions.percentBasis == SlotPercentBasis.layout
        ? measured.layout
        : measured.zone.size;
    String dimension(SlotDimension? value, double extent) => value == null
        ? 'Auto'
        : '${value.resolve(extent).toStringAsFixed(1)} px';
    return Column(
      children: [
        const Text('Layout / zone / slot'),
        SizedBox(
          height: 150,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = (constraints.maxWidth / measured.layout.width)
                  .clamp(0.0, 150 / measured.layout.height);
              Rect scaled(Rect rect) => Rect.fromLTWH(
                rect.left * scale,
                rect.top * scale,
                rect.width * scale,
                rect.height * scale,
              );
              return Center(
                child: SizedBox(
                  width: measured.layout.width * scale,
                  height: measured.layout.height * scale,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          key: const ValueKey('slot-preview-layout'),
                          decoration: BoxDecoration(
                            border: Border.all(color: colors.outline),
                          ),
                        ),
                      ),
                      Positioned.fromRect(
                        rect: scaled(measured.zone),
                        child: DecoratedBox(
                          key: const ValueKey('slot-preview-zone'),
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer.withValues(
                              alpha: .4,
                            ),
                            border: Border.all(color: colors.secondary),
                          ),
                        ),
                      ),
                      for (final (name, width, height) in [
                        (
                          'min',
                          widget.dimensions.minWidth,
                          widget.dimensions.minHeight,
                        ),
                        (
                          'max',
                          widget.dimensions.maxWidth,
                          widget.dimensions.maxHeight,
                        ),
                      ])
                        if (width != null || height != null)
                          Positioned.fromRect(
                            rect: scaled(
                              Rect.fromLTWH(
                                measured.slot.left,
                                measured.slot.top,
                                (width?.resolve(basis.width) ??
                                        measured.slot.width)
                                    .clamp(0, measured.layout.width),
                                (height?.resolve(basis.height) ??
                                        measured.slot.height)
                                    .clamp(0, measured.layout.height),
                              ),
                            ),
                            child: CustomPaint(
                              key: ValueKey('slot-preview-$name'),
                              painter: _SlotSizeBoundsPainter(colors.tertiary),
                            ),
                          ),
                      Positioned.fromRect(
                        rect: scaled(measured.slot),
                        child: DecoratedBox(
                          key: const ValueKey('slot-preview-slot'),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: .25),
                            border: Border.all(color: colors.primary, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Text(
          'Préférée : ${dimension(widget.dimensions.preferredWidth, basis.width)}'
          ' × ${dimension(widget.dimensions.preferredHeight, basis.height)}',
        ),
        Text(
          'Effective : ${measured.slot.width.toStringAsFixed(1)}'
          ' × ${measured.slot.height.toStringAsFixed(1)} px',
          key: const ValueKey('slot-preview-effective'),
        ),
        Text(
          'Marge autour du contenu : '
          '${widget.dimensions.contentPadding}',
        ),
        if (widget.dimensions.minWidth != null ||
            widget.dimensions.minHeight != null ||
            widget.dimensions.maxWidth != null ||
            widget.dimensions.maxHeight != null)
          const Text('Pointillés : limites min / max'),
      ],
    );
  }
}

class _SlotSizeBoundsPainter extends CustomPainter {
  const _SlotSizeBoundsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    void dashed(Offset start, Offset end) {
      final length = (end - start).distance;
      if (length == 0) return;
      final direction = (end - start) / length;
      for (var position = 0.0; position < length; position += 8) {
        canvas.drawLine(
          start + direction * position,
          start + direction * (position + 4).clamp(0, length),
          paint,
        );
      }
    }

    dashed(Offset.zero, Offset(size.width, 0));
    dashed(Offset(size.width, 0), Offset(size.width, size.height));
    dashed(Offset(size.width, size.height), Offset(0, size.height));
    dashed(Offset(0, size.height), Offset.zero);
  }

  @override
  bool shouldRepaint(_SlotSizeBoundsPainter oldDelegate) =>
      color != oldDelegate.color;
}
