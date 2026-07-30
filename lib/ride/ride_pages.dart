import 'package:flutter/widgets.dart';

/// Les pages du tableau de bord, dans l'ordre où on les fait défiler.
///
/// La carte est en tête et le restera : c'est la page par défaut, celle où le
/// retour automatique ramène, et celle que le bouton retour vise avant de
/// quitter la sortie.
enum RidePage {
  navigation('Carte'),
  effort('Effort');

  const RidePage(this.label);

  final String label;

  static int get count => RidePage.values.length;
}

/// Amplitude minimale d'un glissé, en pixels logiques, pour valoir changement
/// de page. Assez court pour un pouce ganté, assez long pour qu'un appui qui
/// ripe sur le bandeau ne fasse pas défiler.
const double swipeMinDistance = 40;

/// Vitesse à partir de laquelle un geste compte comme une chiquenaude, même
/// court. En pixels logiques par seconde.
const double swipeMinVelocity = 180;

/// La page où mène un glissé horizontal sur le bandeau.
///
/// Rend [current] quand le geste ne dit rien de net : sur un guidon, une main
/// qui tremble ne doit pas changer de page.
///
/// [dx] est le déplacement cumulé du geste (négatif vers la gauche) et
/// [velocity] sa vitesse à l'instant du relâchement. **La vitesse l'emporte sur
/// le déplacement** : partir à gauche puis renvoyer vers la droite est un
/// retour en arrière, pas une avancée — c'est la dernière intention qui compte.
int pageAfterSwipe({
  required int current,
  required double dx,
  required double velocity,
  int count = 0,
}) {
  final pages = count > 0 ? count : RidePage.count;

  final int direction;
  if (velocity.abs() >= swipeMinVelocity) {
    direction = velocity < 0 ? 1 : -1;
  } else if (dx.abs() >= swipeMinDistance) {
    direction = dx < 0 ? 1 : -1;
  } else {
    return current;
  }

  return (current + direction).clamp(0, pages - 1);
}

/// La physique du [PageView] selon que la carte est vivante ou non.
///
/// La carte a besoin du glissé horizontal pour se déplacer, et un `PageView` le
/// réclame pour lui. Tant que la carte est à l'écran et posée, le défilement est
/// donc coupé net : on quitte la carte par le bandeau, les pastilles ou la bande
/// du bord droit — jamais par un glissé sur la carte elle-même. Sur les pages de
/// données, rien ne dispute le geste et toute la surface ramène à la carte.
///
/// Volontairement piloté par « la carte est-elle vivante » et non par l'index :
/// bascule à mi-glissé, la physique changerait au milieu du geste et
/// l'annulerait.
ScrollPhysics physicsForMap({required bool mapLive}) => mapLive
    ? const NeverScrollableScrollPhysics()
    : const PageScrollPhysics();

/// Ce que la page web doit savoir de son cadre une fois le bandeau posé.
///
/// Le bas disparaît : la zone système est sous le bandeau natif, hors du
/// WebView, et laisser la page décaler ses bandeaux du bas creuserait un trou.
/// Le haut, lui, garde tout son sens — la carte commence à y=0 et l'encoche la
/// surplombe toujours.
EdgeInsets webInsetsFor(EdgeInsets viewPadding) =>
    viewPadding.copyWith(bottom: 0);
