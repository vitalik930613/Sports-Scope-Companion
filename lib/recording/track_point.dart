/// Un instant de la sortie : position, vitesse et capteurs réunis.
///
/// C'est la ligne de base de l'enregistrement — un point par seconde, écrit tel
/// quel dans le `.jsonl` de la session. Tous les champs sont nullables : rouler
/// sous un tunnel prive de position sans priver du cardio, et un capteur peut
/// tomber en cours de route sans que le reste s'arrête.
///
/// Les clés JSON sont courtes parce qu'elles sont répétées ~11 000 fois pour
/// trois heures de vélo ; la correspondance est tenue ici, à un seul endroit.
class TrackPoint {
  const TrackPoint({
    required this.at,
    required this.distanceM,
    this.lat,
    this.lng,
    this.altitudeM,
    this.accuracyM,
    this.speedMps,
    this.heartRate,
    this.power,
    this.cadence,
    this.wheelSpeedMps,
    this.gearFront,
    this.gearRear,
  });

  final DateTime at;

  /// Distance cumulée depuis le départ, en mètres. Cumulée et pas incrémentale :
  /// c'est ce qu'attend le `.fit`, et une ligne perdue ne décale alors pas tout
  /// le reste de la sortie.
  final double distanceM;

  final double? lat;
  final double? lng;
  final double? altitudeM;
  final double? accuracyM;
  final double? speedMps;

  final int? heartRate;
  final int? power;
  final double? cadence;

  /// Vitesse issue du capteur de roue, quand il y en a un. Gardée à côté de la
  /// vitesse GPS plutôt qu'à sa place : elle dépend d'une circonférence de roue
  /// configurée, alors que le GPS ne dépend de rien.
  final double? wheelSpeedMps;

  /// Positions Di2 au moment du point. Le format `.fit` n'a pas de champ de
  /// braquet dans ses `record` — on les conserve donc dans le JSONL, où ils
  /// restent exploitables (et ré-exportables le jour où on écrira les
  /// événements `gear_change`).
  final int? gearFront;
  final int? gearRear;

  bool get hasPosition => lat != null && lng != null;

  Map<String, dynamic> toJson() => {
        't': at.toUtc().toIso8601String(),
        'd': _round(distanceM, 2),
        if (lat != null) 'lat': _round(lat!, 7),
        if (lng != null) 'lng': _round(lng!, 7),
        if (altitudeM != null) 'alt': _round(altitudeM!, 2),
        if (accuracyM != null) 'acc': _round(accuracyM!, 1),
        if (speedMps != null) 'spd': _round(speedMps!, 3),
        if (heartRate != null) 'hr': heartRate,
        if (power != null) 'pw': power,
        if (cadence != null) 'cad': _round(cadence!, 1),
        if (wheelSpeedMps != null) 'wspd': _round(wheelSpeedMps!, 3),
        if (gearFront != null) 'gf': gearFront,
        if (gearRear != null) 'gr': gearRear,
      };

  /// Renvoie `null` sur une ligne inexploitable au lieu de lever.
  ///
  /// Le fichier est écrit en continu pendant la sortie : une coupure de batterie
  /// laisse forcément une dernière ligne tronquée. Perdre cette seconde-là est
  /// sans importance, perdre la sortie entière serait inacceptable.
  static TrackPoint? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['t'];
    if (at is! String) return null;
    final parsed = DateTime.tryParse(at);
    if (parsed == null) return null;

    return TrackPoint(
      at: parsed.toUtc(),
      distanceM: _double(json['d']) ?? 0,
      lat: _double(json['lat']),
      lng: _double(json['lng']),
      altitudeM: _double(json['alt']),
      accuracyM: _double(json['acc']),
      speedMps: _double(json['spd']),
      heartRate: _int(json['hr']),
      power: _int(json['pw']),
      cadence: _double(json['cad']),
      wheelSpeedMps: _double(json['wspd']),
      gearFront: _int(json['gf']),
      gearRear: _int(json['gr']),
    );
  }

  static double? _double(Object? value) =>
      value is num ? value.toDouble() : null;

  static int? _int(Object? value) => value is num ? value.round() : null;

  /// Arrondi d'écriture : sept décimales de degré valent le centimètre, bien
  /// au-delà de ce que mesure un téléphone. Au-delà on n'écrirait que du bruit,
  /// multiplié par le nombre de secondes de la sortie.
  static num _round(double value, int decimals) {
    final factor = _pow10[decimals]!;
    final rounded = (value * factor).round() / factor;
    return rounded == rounded.roundToDouble() && decimals == 0
        ? rounded.round()
        : rounded;
  }

  static const _pow10 = <int, double>{
    0: 1,
    1: 10,
    2: 100,
    3: 1000,
    7: 10000000,
  };
}
