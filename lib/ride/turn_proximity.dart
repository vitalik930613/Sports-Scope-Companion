import '../recording/gps_fix.dart';
import 'nav_state.dart';

/// Le chien de garde : juger l'approche d'un virage quand la page ne parle
/// plus.
///
/// Le retour automatique repose entièrement sur ce que la page publie. Si elle
/// se tait — rechargée, ralentie, GPS perdu le temps d'un tunnel — le cycliste
/// resterait sur sa page de données jusqu'au virage suivant, et c'est
/// précisément le moment où il aurait eu besoin de la carte. D'où cette
/// deuxième opinion, tirée du GPS de l'appli et de la position du virage que la
/// page avait eu le temps d'annoncer.
///
/// **Elle ne parle que par défaut** : tant que l'état du pont est frais, c'est
/// lui qui fait autorité. Il sait où en est le tracé ; ici on ne sait que
/// compter des mètres à vol d'oiseau.
class TurnProximity {
  const TurnProximity({
    this.staleAfter = const Duration(seconds: 5),
    this.nearM = 110,
    this.fixTtl = const Duration(seconds: 10),
  });

  /// Au-delà, l'état du pont est considéré muet et le chien de garde prend la
  /// main.
  final Duration staleAfter;

  /// Seuil d'approche, **plus court** que celui de la page (150 m). La page
  /// mesure une distance *le long du tracé* ; ici c'est du vol d'oiseau, qui
  /// sous-estime d'autant plus que la route tourne. Dans un lacet, 110 m à vol
  /// d'oiseau valent bien davantage sur le bitume.
  final double nearM;

  /// Âge au-delà duquel une position n'est plus la position du cycliste. Même
  /// ordre de grandeur que le `fixTtl` de l'enregistreur, et pour la même
  /// raison.
  final Duration fixTtl;

  bool imminent({
    required NavState? state,
    required GpsFix? fix,
    required DateTime now,
  }) {
    // En navigation libre il n'y a pas de virage à annoncer, donc rien à
    // surveiller.
    if (state == null || !state.onRoute) return false;
    if (!state.isStale(now, after: staleAfter)) return false;

    final turn = state.turn;
    if (turn == null || !turn.hasPosition) return false;
    if (fix == null || now.difference(fix.at) > fixTtl) return false;

    return GpsFix.haversineM(fix.lat, fix.lng, turn.lat!, turn.lng!) <= nearM;
  }
}
