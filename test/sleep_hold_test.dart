import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/navigation/screen_dimmer.dart';
import 'package:sports_scope_companion/sleep/screen_sleep.dart';
import 'package:sports_scope_companion/sleep/sleep_hold.dart';

/// La veille par appui long, celle de l'appli — le site tient la sienne sur la
/// carte (voir `map_swipe_zone_test.dart`, qui vérifie qu'on lui rend le doigt).
///
/// Deux choses se jouent ici, et aucune ne tient dans une fonction pure : ce que
/// le geste **prend** (l'appui immobile, et lui seul) et ce qu'il **laisse
/// passer** (taps, défilements). Se tromper dans un sens éteint l'écran d'un
/// cycliste qui lit ses watts ; dans l'autre, la veille ne s'obtient plus.
void main() {
  late int slept;
  late int tapped;

  /// La couche, posée sur un bouton : c'est la composition réelle — un écran
  /// entier passe sous la zone de veille.
  Future<void> pumpZone(WidgetTester tester, {bool enabled = true}) async {
    slept = 0;
    tapped = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SleepHoldZone(
          enabled: enabled,
          onSleep: () => slept++,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => tapped++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  testWidgets('un appui immobile de 700 ms endort', (tester) async {
    await pumpZone(tester);

    final finger = await tester.startGesture(const Offset(200, 300));
    await tester.pump(sleepHoldDuration + const Duration(milliseconds: 20));

    expect(slept, 1);

    await finger.up();
    await tester.pumpAndSettle();
    // Et le relâchement n'est pas en plus un tap : la zone a gagné son arène en
    // aboutissant, ce qui a annulé le bouton du dessous. Sans ça, un appui sur
    // les watts endormirait l'écran ET ouvrirait la calibration.
    expect(tapped, 0);
  });

  testWidgets('un tap n\'endort rien', (tester) async {
    // Le tap endormait, avant. En roulant on tape l'écran pour tout et pour
    // rien — et il s'éteignait au moment précis où on le regardait.
    await pumpZone(tester);

    await tester.tapAt(const Offset(200, 300));
    await tester.pumpAndSettle();

    expect(slept, 0);
    expect(tapped, 1);
  });

  testWidgets('un appui trop court n\'endort pas', (tester) async {
    await pumpZone(tester);

    final finger = await tester.startGesture(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 400));
    await finger.up();
    await tester.pumpAndSettle();

    expect(slept, 0);
  });

  testWidgets('un doigt qui part n\'endort pas', (tester) async {
    // C'est un défilement de page, pas une veille — et le laisser aboutir
    // éteindrait l'écran à chaque changement de page un peu lent.
    await pumpZone(tester);

    final finger = await tester.startGesture(const Offset(200, 300));
    await finger.moveBy(const Offset(-60, 0));
    await tester.pump(sleepHoldDuration + const Duration(milliseconds: 20));

    expect(slept, 0);

    await finger.up();
    await tester.pumpAndSettle();
  });

  testWidgets('l\'anneau paraît pendant l\'appui et s\'efface au relâchement',
      (tester) async {
    // Sans lui, l'appui long est un trou noir : rien ne se passe, puis tout se
    // passe. C'est aussi ce qui apprend le geste à qui pressait par habitude.
    await pumpZone(tester);

    final finger = await tester.startGesture(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CustomPaint), findsWidgets);

    await finger.up();
    await tester.pumpAndSettle();
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('débranchée, elle ne prend plus rien', (tester) async {
    // Sur la carte, c'est le site qui détecte le geste : deux détecteurs pour
    // un seul appui se disputeraient le doigt.
    await pumpZone(tester, enabled: false);

    final finger = await tester.startGesture(const Offset(200, 300));
    await tester.pump(sleepHoldDuration + const Duration(milliseconds: 20));
    await finger.up();
    await tester.pumpAndSettle();

    expect(slept, 0);
    expect(tapped, 1, reason: 'le bouton du dessous garde son tap');
  });

  group('l\'écran ordinaire', () {
    const channel = MethodChannel(ScreenDimmer.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> pumpScreen(WidgetTester tester) async {
      tapped = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScreenSleep(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapped++,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
    }

    testWidgets('l\'appui pose le voile et éteint le rétroéclairage',
        (tester) async {
      await pumpScreen(tester);

      final finger = await tester.startGesture(const Offset(200, 300));
      await tester.pump(sleepHoldDuration + const Duration(milliseconds: 20));
      await finger.up();
      await tester.pumpAndSettle();

      expect(find.byType(SleepVeil), findsOneWidget);
      expect(calls.single.arguments as double, lessThan(0.05));
    });

    testWidgets('le voile prend tout ce qui passe', (tester) async {
      // Un écran endormi qu'on effleure au fond d'une poche ne doit rien
      // déclencher de ce qui dort dessous.
      await pumpScreen(tester);

      final finger = await tester.startGesture(const Offset(200, 300));
      await tester.pump(sleepHoldDuration + const Duration(milliseconds: 20));
      await finger.up();
      await tester.pumpAndSettle();
      tapped = 0;

      await tester.tapAt(const Offset(600, 100));
      await tester.pumpAndSettle();

      expect(tapped, 0);
    });

    testWidgets('un tap réveille et rend la luminosité', (tester) async {
      // Endormir demande un appui, réveiller ne demande qu'un tap : sortir de
      // veille doit rester le geste le plus facile de l'écran, gant compris.
      await pumpScreen(tester);

      final finger = await tester.startGesture(const Offset(200, 300));
      await tester.pump(sleepHoldDuration + const Duration(milliseconds: 20));
      await finger.up();
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(200, 300));
      await tester.pumpAndSettle();

      expect(find.byType(SleepVeil), findsNothing);
      expect(calls.last.arguments, ScreenDimmer.systemDefault);
    });

    testWidgets('quitter l\'écran en veille rend la luminosité',
        (tester) async {
      // Le retour système ne passe par aucun de nos gestes : sans ce filet,
      // l'appareil resterait à 1 % après avoir quitté la page.
      await pumpScreen(tester);

      final finger = await tester.startGesture(const Offset(200, 300));
      await tester.pump(sleepHoldDuration + const Duration(milliseconds: 20));
      await finger.up();
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(calls.last.arguments, ScreenDimmer.systemDefault);
    });
  });
}
