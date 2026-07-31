import 'package:flutter/foundation.dart';

import 'rider_profile.dart';

/// Ce qui manque aux seuils du cycliste, et ce qu'il peut y faire.
///
/// Une classe pure et pas une suite de `if` dans l'écran, parce que le seul
/// intérêt du message est une distinction qui ne se voit pas à l'écran : « le
/// site n'a jamais parlé » et « le site a parlé, il ne connaît pas la LTHR »
/// donnent tous les deux un bandeau sans zone, mais le geste à faire n'est pas
/// le même — ouvrir une navigation connecté d'un côté, saisir un chiffre sur le
/// site de l'autre. Cette différence-là se teste sans widget.
@immutable
class ThresholdGap {
  const ThresholdGap({required this.title, required this.detail});

  final String title;
  final String detail;

  /// Ce qui manque, `null` quand les deux zones sont calculables.
  ///
  /// Le test porte sur les **zones** et pas sur les seuils : c'est la liste vide
  /// qui fait le tiret dans le bandeau, et c'est donc elle qu'il faut expliquer.
  ///
  /// [everReceived] dit si le site a déjà poussé un profil un jour
  /// ([RiderProfileStore.updatedAt]). Sans ça, un compte parfaitement réglé mais
  /// jamais encore lu par l'appli recevrait le conseil de saisir des chiffres
  /// qu'il a déjà saisis.
  static ThresholdGap? of(RiderProfile profile, {required bool everReceived}) {
    if (!everReceived) {
      return const ThresholdGap(
        title: 'Seuils inconnus',
        detail: 'L\'appli n\'a encore rien reçu du site. Ouvre une navigation '
            'en étant connecté : les zones du bandeau suivront, et resteront '
            'connues hors ligne.',
      );
    }

    final noHr = !profile.hasHrZones;
    final noPower = !profile.hasPowerZones;

    if (noHr && noPower) {
      return const ThresholdGap(
        title: 'LTHR et FTP inconnues',
        detail: 'Aucune zone dans le bandeau de sortie. Renseigne-les sur le '
            'site, panneau Performances.',
      );
    }
    if (noHr) {
      return const ThresholdGap(
        title: 'LTHR non renseignée',
        detail: 'Pas de zone cardio dans le bandeau. Seule une LTHR saisie à '
            'la main sur le site compte : celle estimée depuis tes sorties ne '
            'crée aucune zone.',
      );
    }
    if (noPower) {
      return const ThresholdGap(
        title: 'FTP inconnue',
        detail: 'Pas de zone de puissance dans le bandeau. Le site l\'estime '
            'après une sortie avec capteur de puissance, ou tu peux la saisir.',
      );
    }
    return null;
  }
}
