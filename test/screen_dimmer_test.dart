import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/navigation/screen_dimmer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(ScreenDimmer.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  /// Branche un faux côté natif. [answer] permet de jouer une plateforme qui
  /// refuse l'appel.
  void mockNative({Object? Function()? answer}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return answer?.call();
    });
  }

  setUp(() {
    calls = [];
    mockNative();
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('éteint le rétroéclairage sans le couper franchement', () async {
    // Zéro pile ferait disparaître le bandeau de virage que la page continue
    // d'afficher sur son fond noir.
    await ScreenDimmer().dim();

    expect(calls.single.method, 'setBrightness');
    expect(calls.single.arguments as double, greaterThan(0));
    expect(calls.single.arguments as double, lessThan(0.05));
  });

  test('rend la main au réglage système', () async {
    await ScreenDimmer().restore();

    expect(calls.single.arguments, ScreenDimmer.systemDefault);
  });

  test('ignore une plateforme sans implémentation', () async {
    // Le desktop, un test, une version de l'appli plus ancienne : la
    // navigation doit continuer, simplement à la luminosité habituelle.
    messenger.setMockMethodCallHandler(channel, null);

    await expectLater(ScreenDimmer().dim(), completes);
  });

  test('ignore une erreur du côté natif', () async {
    mockNative(answer: () => throw PlatformException(code: 'boom'));

    await expectLater(ScreenDimmer().dim(), completes);
  });
}
