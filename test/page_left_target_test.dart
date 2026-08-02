import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/navigation_web_view.dart';

/// Ce que décide le bouton retour quand la carte est à l'écran : reculer dans
/// la page, ou quitter la sortie. Le mauvais choix ne se voit pas comme un bug
/// — il rouvre l'itinéraire précédent, ce qui ressemble à une navigation qui
/// change d'avis toute seule.
void main() {
  final navigate = Uri.parse('https://sports.logicraft.ch/navigate');

  test('sur le tracé ouvert, il n\'y a rien à défaire', () {
    expect(
      pageLeftTarget(
        current: 'https://sports.logicraft.ch/navigate',
        target: navigate,
      ),
      isFalse,
    );
  });

  test('les paramètres ne comptent pas', () {
    // Le départ à neuf demande `fresh=1`, que la page efface de son URL une
    // fois sa session vidée. Comparer les URL entières ferait reculer dans
    // l'historique à chaque sortie, donc rouvrir le tracé d'avant.
    expect(
      pageLeftTarget(
        current: 'https://sports.logicraft.ch/navigate',
        target: Uri.parse('https://sports.logicraft.ch/navigate?fresh=1'),
      ),
      isFalse,
    );
  });

  test('un tracé chargé en pleine sortie reste chez lui', () {
    expect(
      pageLeftTarget(
        current: 'https://sports.logicraft.ch/routes/abc123/navigate',
        target: Uri.parse('https://sports.logicraft.ch/routes/abc123/navigate'),
      ),
      isFalse,
    );
  });

  test('une page ouverte par-dessus l\'itinéraire, elle, se défait', () {
    expect(
      pageLeftTarget(
        current: 'https://sports.logicraft.ch/routes',
        target: navigate,
      ),
      isTrue,
    );
  });

  test('sans URL lisible, on considère la page chez elle', () {
    // Prudence assumée : au pire un appui de trop pour rentrer, jamais un tracé
    // rouvert par surprise.
    expect(pageLeftTarget(current: null, target: navigate), isFalse);
    expect(pageLeftTarget(current: '::pas une url::', target: navigate), isFalse);
  });
}
