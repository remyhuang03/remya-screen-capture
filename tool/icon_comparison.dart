// fvm flutter run -d linux -t tool/icon_comparison.dart --dart-entrypoint-args=--settings
// The settings flag opens a regular GTK window for this preview entry point.
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(const IconComparisonApp());

class IconComparisonApp extends StatelessWidget {
  const IconComparisonApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Capture icon comparison',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
    darkTheme: ThemeData(colorSchemeSeed: Colors.deepPurple, brightness: .dark),
    home: const _ComparisonPage(),
  );
}

class _ComparisonPage extends StatelessWidget {
  const _ComparisonPage();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture icon comparison'),
        actions: [
          IconButton(
            tooltip: 'Close preview',
            onPressed: () async {
              await const MethodChannel('top.remya.screen_capture/settings')
                  .invokeMethod<void>('close');
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const .fromLTRB(24, 0, 24, 12),
            child: Text(
              '${_comparisons.length} retained interface SVGs · same tint and current UI size for each pair',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: .horizontal,
                child: SelectionArea(
                  child: DataTable(
                    horizontalMargin: 16,
                    columnSpacing: 16,
                    columns: const [
                      DataColumn(label: Text('SVG asset')),
                      DataColumn(label: Text('px'), numeric: true),
                      DataColumn(label: Text('SVG')),
                      DataColumn(label: Text('Material Icons candidate')),
                      DataColumn(label: Text('Notes')),
                    ],
                    rows: [
                      for (final item in _comparisons)
                        item.buildRow(colors.onSurface),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Comparison {
  const _Comparison(
    this.asset,
    this.iconName,
    this.icon, {
    this.size = 20,
    this.note = '',
  });

  final String asset;
  final String iconName;
  final IconData icon;
  final double size;
  final String note;

  DataRow buildRow(Color color) => DataRow(
    cells: [
      DataCell(Text('$asset.svg')),
      DataCell(Text(size.toStringAsFixed(0))),
      DataCell(
        SvgPicture.asset(
          'assets/icons/capture/$asset.svg',
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(color, .srcIn),
          excludeFromSemantics: true,
        ),
      ),
      DataCell(
        Row(
          mainAxisSize: .min,
          spacing: 12,
          children: [
            SizedBox.square(
              dimension: 28,
              child: Center(
                child: Icon(icon, size: size, color: color),
              ),
            ),
            Text(iconName),
          ],
        ),
      ),
      DataCell(SizedBox(width: 140, child: Text(note))),
    ],
  );
}

const _comparisons = [
  _Comparison(
    'region',
    'Icons.select_all_rounded',
    Icons.select_all_rounded,
    note: 'Controls gallery only',
  ),
  _Comparison('window', 'Icons.filter_none_rounded', Icons.filter_none_rounded),
  _Comparison(
    'cursor',
    'Icons.near_me_rounded',
    Icons.near_me_rounded,
    note: 'Approximate · navigation arrow',
  ),
  _Comparison(
    'laser-pointer',
    'Icons.ads_click_rounded',
    Icons.ads_click_rounded,
    note: 'Approximate · target and pointer',
  ),
  _Comparison(
    'highlighter',
    'Icons.border_color_rounded',
    Icons.border_color_rounded,
    note: 'Approximate · marker and underline',
  ),
  _Comparison(
    'mosaic',
    'Icons.grid_on_rounded',
    Icons.grid_on_rounded,
    note: 'Approximate · pixel grid',
  ),
  _Comparison(
    'counter',
    'Icons.filter_1_rounded',
    Icons.filter_1_rounded,
    note: 'Approximate · fixed numeral',
  ),
  _Comparison('save', 'Icons.save_rounded', Icons.save_rounded),
  _Comparison(
    'region-small',
    'Icons.select_all_rounded',
    Icons.select_all_rounded,
    size: 18,
    note: 'Screenshot mode selector',
  ),
  _Comparison(
    'window-small',
    'Icons.filter_none_rounded',
    Icons.filter_none_rounded,
    size: 18,
    note: 'Screenshot mode selector',
  ),
];
