import 'package:flutter/widgets.dart';

/// Le défilement des pages du tableau de bord.
///
/// **Les pages viennent du profil de sortie** (`dashboard/ride_preset.dart`), pas
/// d'une énumération : leur nombre, leur ordre et leur contenu sont décrits par
/// le site. Ce fichier ne connaît donc qu'un nombre de pages et des index — et
/// surtout plus de « page 0 = la carte », qui a longtemps été le même fait que
/// « la carte est en tête ». La carte se place où l'on veut, et un profil de
/// home-trainer n'en a pas du tout : c'est `RidePreset.mapPageIndex` qui le sait,
/// et lui seul.
///
/// Le défilement est **circulaire** : après la dernière page revient la première.
/// Un `PageView` ne sait pas boucler, donc la pile est parcourue par un index
/// *brut* qui monte et descend sans borne, et [pageOf] le ramène au catalogue.
///
/// [rawPageOriginFor] est le point de départ, choisi assez loin de zéro pour
/// qu'une sortie n'atteigne jamais le bout : il faudrait dix mille changements de
/// page dans le même sens. C'est un multiple du nombre de pages, pour que
/// l'origine tombe bien sur la première.
int rawPageOriginFor(int count) => (count > 0 ? count : 1) * 10000;

/// La page du catalogue qu'affiche un index brut.
///
/// Le `%` de Dart rend toujours un résultat positif pour un diviseur positif —
/// contrairement à C ou JavaScript : reculer sous l'origine n'a donc pas besoin
/// de rattrapage.
int pageOf(int raw, {required int count}) => raw % (count > 0 ? count : 1);

/// L'index brut le plus proche de [from] qui affiche la page [page].
///
/// Par le chemin court, jamais par le tour complet : revenir sur la carte depuis
/// la dernière page ne doit pas faire défiler tout le catalogue à l'envers sous
/// les yeux du cycliste.
int rawPageFor(int page, {required int from, required int count}) {
  final pages = count > 0 ? count : 1;
  var delta = (page - pageOf(from, count: pages)) % pages;
  if (delta > pages ~/ 2) delta -= pages;
  return from + delta;
}

/// Amplitude minimale d'un glissé, en pixels logiques, pour valoir changement
/// de page. Assez court pour un pouce ganté, assez long pour qu'un appui qui
/// ripe sur le bandeau ne fasse pas défiler.
const double swipeMinDistance = 40;

/// Vitesse à partir de laquelle un geste compte comme une chiquenaude, même
/// court. En pixels logiques par seconde.
const double swipeMinVelocity = 180;

/// Ce que dit un glissé horizontal : `1` vers la suite (le doigt part à
/// gauche), `-1` vers le précédent, `0` quand le geste ne dit rien de net.
///
/// Zéro plutôt qu'une supposition : sur un guidon, une main qui tremble ne doit
/// rien déclencher.
///
/// [dx] est le déplacement cumulé du geste (négatif vers la gauche) et
/// [velocity] sa vitesse à l'instant du relâchement. **La vitesse l'emporte sur
/// le déplacement** : partir à gauche puis renvoyer vers la droite est un
/// retour en arrière, pas une avancée — c'est la dernière intention qui compte.
int swipeDirection({required double dx, required double velocity}) {
  if (velocity.abs() >= swipeMinVelocity) return velocity < 0 ? 1 : -1;
  if (dx.abs() >= swipeMinDistance) return dx < 0 ? 1 : -1;
  return 0;
}

/// La physique du [PageView] selon que la carte est vivante ou non.
///
/// La carte a besoin du glissé horizontal pour se déplacer, et un `PageView` le
/// réclame pour lui. Tant que la carte est à l'écran et posée, le défilement est
/// donc coupé net : on la quitte par les bandes des deux bords ou par les
/// pastilles — jamais par un glissé en plein milieu de la carte, qui appartient
/// à MapLibre. Sur les pages de données, rien ne dispute le geste et toute la
/// surface fait défiler.
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
