// Basic smoke test: the app boots and renders its initial (loading) frame
// without throwing. VokulApp.init() talks to path_provider over a platform
// channel that isn't wired up under `flutter test`, so this deliberately
// does not pump past the first frame or assert on which screen follows.

import 'package:flutter_test/flutter_test.dart';

import 'package:vokul_mobile/main.dart';

void main() {
  testWidgets('boots without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const VokulApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
