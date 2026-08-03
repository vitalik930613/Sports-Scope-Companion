import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/ride_pages.dart';
import 'package:sports_scope_companion/ride/widgets/map_swipe_zone.dart';

/// Le partage du doigt entre la carte et le tableau de bord.
///
/// La règle tient en une phrase — **un doigt change de page, deux appartiennent
/// à la carte** — et tout l'intérêt de ces tests est qu'elle ne tient pas dans
/// une fonction pure : elle se joue dans l'arène des gestes, et le glissé est
/// mené jusqu'au `PageView` lui-même. Se tromper ici casse le déplacement de la
/// carte, ce qu'aucun test de logique ne verrait.
///
/// La maquette reprend la pile de `RideShellPage` — page web au fond, zone de
/// glissé, défilement, et un enfant qui va et vient — parce que c'est la
/// composition entière qui se cassait : sans clé, l'apparition d'un enfant
/// décale tous les suivants d'un cran, Flutter réapparie les éléments par leur
/// rang et le `PageView` repart de l'élément du voisin. La discipline des clés,
/// elle, se tient dans la coquille, où elle est expliquée.
void main() {
  const mapPage = 1;
  const count = 4;

  /// Les pointeurs que la page web a fini par gagner.
  late Set<int> mapWon;
  late _ShellHarnessState shell;

  Future<void> pumpZone(WidgetTester tester) async {
    mapWon = {};
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _ShellHarness(mapWon: mapWon),
      ),
    );
    shell = tester.state<_ShellHarnessState>(find.byType(_ShellHarness));
    expect(shell.page, mapPage, reason: 'la maquette démarre sur la carte');
  }

  /// Le glissé du cycliste : un doigt qui part à gauche demande la page
  /// suivante.
  Future<void> swipeLeft(WidgetTester tester) async {
    // Par les coordonnées et non par le widget : passé la carte, c'est le
    // `PageView` qui prend le geste au même endroit — comme sur la route.
    await tester.flingFrom(const Offset(400, 300), const Offset(-200, 0), 800);
    await tester.pumpAndSettle();
  }

  testWidgets('un doigt fait défiler jusqu\'à la page suivante', (tester) async {
    await pumpZone(tester);

    await swipeLeft(tester);

    expect(shell.page, mapPage + 1);
  });

  testWidgets('deux glissés de suite avancent de deux pages', (tester) async {
    // Le bug tel qu'il se voyait sur la route : le premier glissé quittait bien
    // la carte, le second y revenait, et il fallait glisser dans l'autre sens
    // pour atteindre le reste du catalogue.
    await pumpZone(tester);

    await swipeLeft(tester);
    await swipeLeft(tester);
    await swipeLeft(tester);

    expect(shell.page, pageOf(mapPage + 3, count: count));
  });

  testWidgets('la page suit le doigt avant même qu\'il ne se lève',
      (tester) async {
    // C'est ce qui manquait à la première version, qui décidait au relâchement :
    // il fallait parcourir une distance à l'aveugle, et ça se lisait comme un
    // écran qui ne répond pas.
    await pumpZone(tester);

    final start = shell.raw.toDouble();
    final finger = await tester.startGesture(const Offset(400, 300));
    // Par petits pas, comme un vrai doigt : la marge de reconnaissance est
    // rendue au premier mouvement qui la dépasse, pas au geste entier.
    for (var step = 0; step < 4; step++) {
      await finger.moveBy(const Offset(-40, 0));
    }
    await tester.pump();

    // Entre deux pages, et pas encore arrivée : la page a bougé sous le doigt.
    expect(shell.pages.page, greaterThan(start));
    expect(shell.pages.page, lessThan(start + 1));

    await finger.up();
    await tester.pumpAndSettle();
  });

  testWidgets('un doigt qui part à droite recule', (tester) async {
    await pumpZone(tester);

    await tester.flingFrom(const Offset(400, 300), const Offset(200, 0), 800);
    await tester.pumpAndSettle();

    expect(shell.page, mapPage - 1);
  });

  testWidgets('deux doigts appartiennent à la carte', (tester) async {
    // Le déplacement à deux doigts, et le pincement avec lui : les prendre pour
    // un changement de page rendrait la carte impossible à déplacer.
    await pumpZone(tester);

    final first = await tester.startGesture(const Offset(300, 300));
    final second = await tester.startGesture(const Offset(360, 300));
    for (var step = 0; step < 6; step++) {
      await first.moveBy(const Offset(-30, 0));
      await second.moveBy(const Offset(-30, 0));
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(shell.page, mapPage);
    // Et pas seulement « rien n'a bougé » : les deux doigts sont bien arrivés à
    // la carte, faute de quoi le pincement lui parviendrait amputé.
    expect(mapWon.length, 2);
  });

  testWidgets('un second doigt rend le premier à la carte', (tester) async {
    // Les deux doigts ne se posent jamais à la même milliseconde, et le premier
    // a le temps de bouger un peu.
    await pumpZone(tester);

    final first = await tester.startGesture(const Offset(300, 300));
    await first.moveBy(const Offset(-8, 0));
    final second = await tester.startGesture(const Offset(360, 300));
    await first.moveBy(const Offset(-120, 0));
    await second.moveBy(const Offset(-120, 0));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(shell.page, mapPage);
    expect(mapWon.length, 2);
  });

  testWidgets('un second doigt posé trop tard ramène la page de départ',
      (tester) async {
    // Ici le retrait de l'arène arrive trop tard : le glissé avait déjà gagné le
    // premier doigt, qu'on ne peut plus rendre. Reste à ne pas changer de page —
    // le doigt qui vient de se poser demande la carte, pas la page suivante.
    await pumpZone(tester);

    final first = await tester.startGesture(const Offset(600, 300));
    await first.moveBy(const Offset(-500, 0));
    final second = await tester.startGesture(const Offset(660, 300));
    await first.moveBy(const Offset(-60, 0));
    await second.moveBy(const Offset(-60, 0));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(shell.page, mapPage);
  });

  testWidgets('le doigt suivant retrouve le changement de page',
      (tester) async {
    // Le compte des doigts est tenu à la main : s'il fuyait, la carte avalerait
    // tous les glissés d'après et le changement de page mourrait en silence au
    // premier pincement.
    await pumpZone(tester);

    final first = await tester.startGesture(const Offset(300, 300));
    final second = await tester.startGesture(const Offset(360, 300));
    await first.moveBy(const Offset(-60, 0));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    await swipeLeft(tester);

    expect(shell.page, mapPage + 1);
  });

  testWidgets('l\'appui traverse jusqu\'à la page web', (tester) async {
    // C'est l'appui qui réveille l'écran et qui ouvre un POI : il appartient à
    // la page, et la couche de gestes ne doit pas s'y interposer.
    await pumpZone(tester);

    await tester.tapAt(const Offset(300, 300));
    await tester.pumpAndSettle();

    expect(shell.page, mapPage);
    expect(mapWon, isNotEmpty);
  });

  testWidgets('le glissé vertical reste à la carte', (tester) async {
    await pumpZone(tester);

    await tester.flingFrom(const Offset(400, 300), const Offset(0, -200), 800);
    await tester.pumpAndSettle();

    expect(shell.page, mapPage);
    expect(mapWon, isNotEmpty);
  });

  group('rendre le doigt sans attendre le relâchement', () {
    // Le cœur du sujet : une vue de plateforme **met les événements en cache**
    // tant qu'un recognizer n'a pas tranché, et ne les lui remet qu'en gagnant
    // son arène. Tant que le glissé attendait le lever du doigt pour se
    // retirer, la page web ne recevait son `pointerdown` qu'au relâchement —
    // et l'appui long qui met le site en veille (700 ms d'immobilité) ne
    // démarrait donc jamais dans l'appli.

    testWidgets('l\'appui immobile part à la page web, doigt encore posé',
        (tester) async {
      await pumpZone(tester);

      final finger = await tester.startGesture(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(mapWon, isNotEmpty,
          reason: 'sans ça, la page ne peut pas compter ses 700 ms');
      expect(shell.page, mapPage);

      await finger.up();
      await tester.pumpAndSettle();
    });

    testWidgets('un appui qui tremble un peu reste un appui', (tester) async {
      // Une main gantée sur un vélo qui roule n'est pas immobile. Le site
      // tolère 16 px de dérive : en rendre moins reviendrait à ne rendre que
      // les appuis qu'on fait à l'arrêt.
      await pumpZone(tester);

      final finger = await tester.startGesture(const Offset(400, 300));
      for (var step = 0; step < 4; step++) {
        await finger.moveBy(const Offset(2, 1));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: 200));

      expect(mapWon, isNotEmpty);
      expect(shell.page, mapPage);

      await finger.up();
      await tester.pumpAndSettle();
    });

    testWidgets('le glissé vertical est rendu tout de suite', (tester) async {
      // Le tiroir de commandes du site s'ouvre d'un glissé vers le haut : livré
      // d'un bloc au relâchement, il ne s'ouvrait pas.
      await pumpZone(tester);

      final finger = await tester.startGesture(const Offset(400, 300));
      for (var step = 0; step < 3; step++) {
        await finger.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(mapWon, isNotEmpty);

      await finger.up();
      await tester.pumpAndSettle();
      expect(shell.page, mapPage);
    });

    testWidgets('un glissé qui démarre lentement change quand même de page',
        (tester) async {
      // Le compteur d'immobilité se réarme à chaque mouvement, et c'est ce qui
      // sauve le geste mou : l'annuler définitivement au premier tic aurait
      // rendu le changement de page capricieux là où il compte le plus.
      await pumpZone(tester);

      final start = shell.raw.toDouble();
      final finger = await tester.startGesture(const Offset(400, 300));
      for (var step = 0; step < 10; step++) {
        await finger.moveBy(const Offset(-6, 0));
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(shell.pages.page, greaterThan(start));
      expect(mapWon, isEmpty, reason: 'c\'est un glissé, pas un appui');

      await finger.up();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('hors de la carte, les pages prennent leurs glissés',
      (tester) async {
    // La zone reste montée partout — c'est ce qui permet à un glissé de survivre
    // au changement de page — mais elle ne doit rien prendre ailleurs.
    await pumpZone(tester);
    await swipeLeft(tester);

    await tester.flingFrom(const Offset(400, 300), const Offset(-200, 0), 800);
    await tester.pumpAndSettle();

    expect(shell.page, mapPage + 2);
  });
}

/// La pile de `RideShellPage`, réduite à ce qui se dispute le doigt : la page
/// web au fond, la zone de glissé, le défilement par-dessus — et un enfant qui
/// va et vient au gré de la page, comme le font la page du menu et la page de
/// réveil radar.
class _ShellHarness extends StatefulWidget {
  const _ShellHarness({required this.mapWon});

  final Set<int> mapWon;

  @override
  State<_ShellHarness> createState() => _ShellHarnessState();
}

class _ShellHarnessState extends State<_ShellHarness> {
  static const count = 4;
  static const mapPage = 1;

  late final PageController pages;
  late int raw;

  int get page => pageOf(raw, count: count);
  bool get onMap => page == mapPage;

  @override
  void initState() {
    super.initState();
    raw = rawPageOriginFor(count) + mapPage;
    pages = PageController(initialPage: raw);
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // La page web : **membre de l'arène** comme l'est une vue de plateforme,
        // qui ne réclame jamais rien et ne gagne que ce qu'on ne lui a pas pris.
        // Un simple Listener ne dirait rien, puisqu'il reçoit tout de toute
        // façon.
        Positioned.fill(
          key: const ValueKey('web'),
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _WebViewStandIn:
                  GestureRecognizerFactoryWithHandlers<_WebViewStandIn>(
                () => _WebViewStandIn(widget.mapWon),
                (_) {},
              ),
            },
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(
          key: const ValueKey('glisse-carte'),
          child: MapSwipeZone(pages: pages, enabled: onMap),
        ),
        Positioned.fill(
          key: const ValueKey('pages'),
          child: IgnorePointer(
            ignoring: onMap,
            child: PageView.builder(
              controller: pages,
              onPageChanged: (value) => setState(() => raw = value),
              itemBuilder: (context, rawPage) => pageOf(rawPage, count: count)
                      == mapPage
                  ? const SizedBox.shrink()
                  : const ColoredBox(
                      color: Color(0xFF101214),
                      child: SizedBox.expand(),
                    ),
            ),
          ),
        ),
        // L'enfant qui va et vient, comme la page du menu ou le réveil radar.
        if (onMap)
          const Positioned.fill(
            key: ValueKey('va-et-vient'),
            child: IgnorePointer(child: SizedBox.expand()),
          ),
      ],
    );
  }
}

/// Ce que fait une vue de plateforme dans l'arène : elle suit le pointeur, ne
/// réclame jamais la victoire, et se contente de ce qui lui reste quand tous les
/// autres se sont retirés. C'est ce qui rend le test fidèle — un recognizer
/// ordinaire, lui, gagnerait de vitesse et ne prouverait rien.
class _WebViewStandIn extends OneSequenceGestureRecognizer {
  _WebViewStandIn(this.won);

  final Set<int> won;

  @override
  void addAllowedPointer(PointerDownEvent event) =>
      startTrackingPointer(event.pointer);

  @override
  void acceptGesture(int pointer) => won.add(pointer);

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'page web';
}
