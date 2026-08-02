import 'package:flutter_test/flutter_test.dart';

import 'package:cloudread/theme/serene_theme.dart';
import 'package:cloudread/theme/serene_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Serene theme builds for day and night palettes', () {
    expect(sereneTheme(SereneColorScheme.day), isNotNull);
    expect(sereneTheme(SereneColorScheme.night), isNotNull);
  });
}
