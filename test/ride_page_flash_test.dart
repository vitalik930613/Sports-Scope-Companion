import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/widgets/ride_page_flash.dart';

/// Le repère de page, depuis qu'il a remplacé les pastilles du bandeau.
///
/// Ce qui se vérifie ici tient en trois choses : il se tait au montage, il
/// paraît quand la page change, et il s'efface tout seul. Les trois se
/// constatent mal sur la route — c'est une seconde d'affichage — et la première
/// ne se constate pas du tout, puisqu'elle consiste à ne rien voir.
void main() {
  /// Une coquille minimale : le repère et un bouton pour changer de page, comme
  /// le fait le défilement de la vraie.
  Future<void> pumpFlash(WidgetTester tester, {required int count}) {
    var page = 0;
    return tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Column(
              children: [
                RidePageFlash(page: page, count: count),
                TextButton(
                  onPressed: () => setState(() => page = (page + 1) % count),
                  child: const Text('suivante'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// L'opacité effectivement peinte. `findsOneWidget` ne suffirait pas : le
  /// repère reste dans l'arbre une fois éteint, c'est son opacité qui tombe.
  double opacityOf(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
      .opacity;

  testWidgets('rien au montage : la première page n\'est pas un changement',
      (tester) async {
    await pumpFlash(tester, count: 4);

    expect(find.text('1 / 4'), findsOneWidget);
    // Présent mais transparent — un chiffre qui s'allume tout seul au départ
    // d'une sortie se lit comme une notification qu'on n'a pas demandée.
    expect(opacityOf(tester), 0);
  });

  testWidgets('la page change : le numéro paraît, puis s\'efface',
      (tester) async {
    await pumpFlash(tester, count: 4);

    await tester.tap(find.text('suivante'));
    await tester.pump();

    expect(find.text('2 / 4'), findsOneWidget);
    expect(opacityOf(tester), 1);

    // Toujours là juste avant l'échéance : une demi-seconde d'affichage ne
    // laisserait pas le temps de lire deux caractères en roulant.
    await tester.pump(RidePageFlash.hold - const Duration(milliseconds: 50));
    expect(opacityOf(tester), 1);

    await tester.pump(const Duration(milliseconds: 100));
    expect(opacityOf(tester), 0);

    await tester.pumpAndSettle();
  });

  testWidgets('deux glissés rapides : le second garde sa seconde pleine',
      (tester) async {
    await pumpFlash(tester, count: 3);

    await tester.tap(find.text('suivante'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    await tester.tap(find.text('suivante'));
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);

    // Le reliquat du premier compte serait tombé ici. C'est le second qui
    // commande : à deux glissés enchaînés, c'est la page d'arrivée qu'on veut
    // lire, pas celle qu'on a traversée.
    await tester.pump(const Duration(milliseconds: 400));
    expect(opacityOf(tester), 1);

    await tester.pump(RidePageFlash.hold);
    expect(opacityOf(tester), 0);

    await tester.pumpAndSettle();
  });

  testWidgets('une page unique ne réserve rien à l\'écran', (tester) async {
    await pumpFlash(tester, count: 1);

    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(find.textContaining('/'), findsNothing);
  });
}
