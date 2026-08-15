import '../recording/gps_fix.dart';

/// Accumule les positions acceptées par l'enregistreur et décide, à chaque
/// tic du pont, ce qu'il reste à envoyer à la page.
///
/// Pur et testé, comme `AutoReturnPolicy` ou `RadarWakePolicy` : aucune trace
/// Bluetooth ni JavaScript ici, seulement la décision. `SensorBridge` lui
/// pousse `recorder.lastFix` et transmet le résultat de [drain] tel quel.
class TraveledPathTracker {
  final List<_Point> _points = [];

  /// Datation du dernier point retenu, pour ignorer un `lastFix` qui n'a pas
  /// changé depuis le tic précédent — l'enregistreur écrit une fois par
  /// seconde, mais le pont peut le lire plus souvent (envoi forcé).
  DateTime? _lastAt;

  /// Combien de [_points] la page connaît déjà. Ce qui suit cet index est ce
  /// qu'un envoi normal doit transmettre — jamais tout l'historique, sous
  /// peine de réexpédier une sortie de plusieurs heures à chaque tic.
  int _sent = 0;

  /// Arrondi à 6 décimales (~11 cm) : cette ligne n'est jamais mesurée au
  /// centimètre, et une décimale de moins limite sensiblement la taille du
  /// message sur une sortie de plusieurs heures.
  static double _round(double value) => (value * 1e6).roundToDouble() / 1e6;

  /// Prend en compte un nouveau relevé, s'il est vraiment nouveau.
  ///
  /// `fix` peut être `null` (GPS coupé ou pas encore de position) : rien à
  /// faire. Un `fix` déjà vu (même horodatage que le précédent) est ignoré
  /// plutôt que dédoublonné après coup.
  void addFix(GpsFix? fix) {
    if (fix == null || fix.at == _lastAt) return;
    _lastAt = fix.at;
    _points.add(_Point(_round(fix.lat), _round(fix.lng)));
  }

  /// Vide ce qu'il y a à envoyer, ou `null` s'il n'y a rien de neuf.
  ///
  /// `forceFull` renvoie tout l'historique accumulé avec `reset: true` : la
  /// page vient de perdre son état (rechargement, message `ready`) et doit
  /// redessiner la ligne à neuf plutôt que de l'allonger sur du vide. Sinon,
  /// seuls les points arrivés depuis le dernier envoi partent — la page les
  /// ajoute à ce qu'elle a déjà.
  Map<String, dynamic>? drain({required bool forceFull}) {
    if (forceFull) {
      _sent = _points.length;
      return {
        'points': [for (final point in _points) point.toJson()],
        'reset': true,
      };
    }

    if (_sent >= _points.length) return null;
    final pending = _points.sublist(_sent);
    _sent = _points.length;
    return {'points': [for (final point in pending) point.toJson()]};
  }

  /// Efface tout : une nouvelle sortie démarre, l'ancien trajet ne la
  /// concerne plus.
  void reset() {
    _points.clear();
    _lastAt = null;
    _sent = 0;
  }
}

class _Point {
  const _Point(this.lat, this.lng);

  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}
