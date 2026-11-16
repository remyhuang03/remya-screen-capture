import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../tool/icon_comparison.dart';

void main() {
  testWidgets('compares each bundled capture SVG at the candidate size', (
    tester,
  ) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final captureAssets = manifest.listAssets().where(
      (asset) =>
          asset.startsWith('assets/icons/capture/') && asset.endsWith('.svg'),
    );
    expect(captureAssets, isNotEmpty);

    await tester.pumpWidget(const IconComparisonApp());
    final table = tester.widget<DataTable>(find.byType(DataTable));
    final compared = [
      for (final row in table.rows)
        ((row.cells[2].child as SvgPicture).bytesLoader as SvgAssetLoader)
            .assetName,
    ];
    expect(compared, unorderedEquals(captureAssets));
    for (final row in table.rows) {
      final svg = row.cells[2].child as SvgPicture;
      final cell = row.cells[3].child as Row;
      final icon =
          ((cell.children.first as SizedBox).child as Center).child as Icon;
      expect(icon.size, svg.width);
      expect(icon.size, svg.height);
    }
  });
}
