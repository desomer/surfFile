import 'package:material_ui/material_ui.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/theme/disk_gauge_style.dart';
import 'package:super_container_layout/widgets/container_style_editor.dart';
import 'disk_gauge.dart';

/// Ouvre l'éditeur des jauges du panneau des disques. Les changements sont
/// appliqués en direct ; « Annuler » restaure l'apparence initiale.
Future<void> showDiskGaugeStyleEditor(BuildContext context) async {
  final controller = AppearanceScope.controllerOf(context);
  if (controller == null) return;
  final preferences = SurfFilePreferencesScope.controllerOf(context);
  final initial = preferences.value;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) => AlertDialog(
      title: const Text('Style de la jauge des disques'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: ValueListenableBuilder<SurfFilePreferences>(
            valueListenable: preferences,
            builder: (context, preference, _) => DiskGaugeStyleEditor(
              value: preference.diskGaugeStyle,
              accent: controller.value.accent,
              onChanged: (style) => preferences.value = preferences.value
                  .copyWith(diskGaugeStyle: style),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Appliquer'),
        ),
      ],
    ),
  );
  if (confirmed != true && preferences.value != initial) {
    preferences.value = preferences.value.copyWith(diskGaugeStyle: initial.diskGaugeStyle);
  }
}

class DiskGaugeStyleEditor extends StatelessWidget {
  const DiskGaugeStyleEditor({
    required this.value,
    required this.accent,
    required this.onChanged,
    super.key,
  });

  final DiskGaugeStyle value;
  final Color accent;
  final ValueChanged<DiskGaugeStyle> onChanged;

  static const _gradientDefaults = [
    Color(0xFF43A047),
    Color(0xFFFFB300),
    Color(0xFFE53935),
  ];

  Widget _slider(
    String label,
    double v,
    double min,
    double max,
    ValueChanged<double> changed, {
    int? divisions,
    String Function(double)? format,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('$label : ${format?.call(v) ?? v.toStringAsFixed(0)}'),
      Slider(
        key: ValueKey('gauge-$label'),
        value: v.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: changed,
      ),
    ],
  );

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ring = value.shape == DiskGaugeShape.ring;
    final bar = value.shape == DiskGaugeShape.bar;
    final fill = value.fillColor ?? accent;
    final alert = value.alertColor ?? colors.error;
    final track = value.trackColor ?? colors.onSurface.withValues(alpha: .12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final MapEntry(key: name, value: preset)
                in DiskGaugeStyle.presets.entries)
              ActionChip(
                key: ValueKey('gauge-preset-$name'),
                label: Text(name),
                onPressed: () =>
                    onChanged(preset.copyWith(columns: value.columns)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final sample in const [.42, .72, .95])
              SizedBox(
                width: bar ? 110 : null,
                child: DiskGauge(
                  value: sample,
                  style: value,
                  fillColor: fill,
                  alertColor: alert,
                  trackColor: track,
                  foreground: colors.onSurface,
                ),
              ),
          ],
        ),
        _section(context, 'Forme'),
        SegmentedButton<DiskGaugeShape>(
          segments: [
            for (final shape in DiskGaugeShape.values)
              ButtonSegment(value: shape, label: Text(shape.label)),
          ],
          selected: {value.shape},
          onSelectionChanged: (s) => onChanged(value.copyWith(shape: s.first)),
        ),
        const SizedBox(height: 8),
        if (!bar)
          _slider(
            'Taille',
            value.size,
            DiskGaugeStyle.minSize,
            DiskGaugeStyle.maxSize,
            (v) => onChanged(value.copyWith(size: v)),
          ),
        _slider(
          'Épaisseur de la piste',
          value.thickness,
          DiskGaugeStyle.minThickness,
          DiskGaugeStyle.maxThickness,
          (v) => onChanged(value.copyWith(thickness: v)),
          format: (v) => v.toStringAsFixed(1),
        ),
        SwitchListTile(
          title: const Text('Extrémités arrondies'),
          value: value.roundCaps,
          onChanged: (v) => onChanged(value.copyWith(roundCaps: v)),
        ),
        if (ring) ...[
          const Text('Départ'),
          const SizedBox(height: 4),
          SegmentedButton<DiskGaugeStart>(
            segments: [
              for (final start in DiskGaugeStart.values)
                ButtonSegment(value: start, label: Text(start.label)),
            ],
            selected: {value.start},
            onSelectionChanged: (s) =>
                onChanged(value.copyWith(start: s.first)),
          ),
          SwitchListTile(
            title: const Text('Sens horaire'),
            value: value.clockwise,
            onChanged: (v) => onChanged(value.copyWith(clockwise: v)),
          ),
        ],
        _section(context, 'Couleurs'),
        styleColorTile(
          'Piste vide',
          track,
          (c) => onChanged(value.copyWith(trackColor: c)),
        ),
        styleColorTile(
          'Remplissage',
          fill,
          (c) => onChanged(value.copyWith(fillColor: c)),
        ),
        SwitchListTile(
          title: const Text('Dégradé le long de la piste'),
          value: value.gradient.length >= 2,
          onChanged: (v) => onChanged(
            value.copyWith(
              gradient: v ? _gradientDefaults.take(2).toList() : const [],
            ),
          ),
        ),
        if (value.gradient.length >= 2) ...[
          for (final (i, color) in value.gradient.indexed)
            styleColorTile(
              'Dégradé ${i + 1}',
              color,
              (c) => onChanged(
                value.copyWith(gradient: [...value.gradient]..[i] = c),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: value.gradient.length < 3
                ? TextButton.icon(
                    onPressed: () => onChanged(
                      value.copyWith(
                        gradient: [...value.gradient, _gradientDefaults[2]],
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter une couleur'),
                  )
                : TextButton.icon(
                    onPressed: () => onChanged(
                      value.copyWith(gradient: value.gradient.take(2).toList()),
                    ),
                    icon: const Icon(Icons.remove),
                    label: const Text('Retirer la 3e couleur'),
                  ),
          ),
        ],
        styleColorTile(
          'Alerte',
          alert,
          (c) => onChanged(value.copyWith(alertColor: c)),
        ),
        _slider(
          'Seuil d’alerte',
          value.alertThreshold,
          .5,
          1,
          (v) => onChanged(value.copyWith(alertThreshold: v)),
          divisions: 50,
          format: (v) => '${(v * 100).round()} %',
        ),
        Wrap(
          children: [
            TextButton(
              onPressed: () => onChanged(
                value.copyWith(
                  resetTrackColor: true,
                  resetFillColor: true,
                  resetAlertColor: true,
                  gradient: const [],
                ),
              ),
              child: const Text('Couleurs automatiques'),
            ),
          ],
        ),
        _section(context, 'Néon'),
        NeonStyleEditor(
          label: 'gauge',
          value: value.trackNeon,
          accent: fill,
          onChanged: (v) => onChanged(value.copyWith(trackNeon: v)),
        ),
        if (value.trackNeon.enabled)
          SwitchListTile(
            title: const Text('Pulsation en alerte'),
            subtitle: const Text('Le halo pulse au-delà du seuil'),
            value: value.alertPulse,
            onChanged: (v) => onChanged(value.copyWith(alertPulse: v)),
          ),
        SwitchListTile(
          title: const Text('Néon sur le pourcentage'),
          value: value.labelNeon,
          onChanged: (v) => onChanged(value.copyWith(labelNeon: v)),
        ),
        _section(context, 'Animation'),
        SwitchListTile(
          title: const Text('Remplissage animé'),
          subtitle: const Text('Depuis 0 à l’affichage et à l’actualisation'),
          value: value.animate,
          onChanged: (v) => onChanged(value.copyWith(animate: v)),
        ),
        if (value.animate)
          _slider(
            'Durée (ms)',
            value.animationMs,
            0,
            DiskGaugeStyle.maxAnimation,
            (v) => onChanged(value.copyWith(animationMs: v)),
            divisions: 40,
          ),
        _section(context, 'Textes'),
        _slider(
          'Taille du pourcentage',
          value.percentSize,
          8,
          24,
          (v) => onChanged(value.copyWith(percentSize: v)),
        ),
        _slider(
          'Graisse du pourcentage',
          value.percentWeight.toDouble(),
          1,
          9,
          (v) => onChanged(value.copyWith(percentWeight: v.round())),
          divisions: 8,
          format: (v) => '${v.round() * 100}',
        ),
        _slider(
          'Taille du nom',
          value.nameSize,
          9,
          20,
          (v) => onChanged(value.copyWith(nameSize: v)),
        ),
        _slider(
          'Taille de « libres »',
          value.captionSize,
          8,
          16,
          (v) => onChanged(value.copyWith(captionSize: v)),
        ),
        _section(context, 'Disposition'),
        const Text('Tuiles par ligne'),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1')),
            ButtonSegment(value: 2, label: Text('2')),
            ButtonSegment(value: 3, label: Text('3')),
          ],
          selected: {value.columns},
          onSelectionChanged: (s) =>
              onChanged(value.copyWith(columns: s.first)),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => onChanged(const DiskGaugeStyle()),
          child: const Text('Réinitialiser ce style'),
        ),
      ],
    );
  }
}
