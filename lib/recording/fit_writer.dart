import 'dart:typed_data';

import 'ride_session.dart';
import 'track_point.dart';

/// Encode une sortie enregistrée en fichier `.fit`.
///
/// Écrit à la main, sans dépendance : le format est stable depuis quinze ans et
/// on n'en utilise qu'une poignée de messages (`file_id`, `event`, `record`,
/// `lap`, `session`, `activity`). Une bibliothèque apporterait le profil complet
/// — deux mille types de messages dont aucun ne nous sert — et son propre
/// générateur de code.
///
/// Le résultat vise le parcours normal : déposer le fichier dans la page
/// d'import de sports-scope, qui le lit avec `fit-file-parser`. Il est aussi
/// accepté tel quel par Strava et Garmin Connect, qui attendent les mêmes
/// messages.
///
/// Structure d'un `.fit` :
/// ```
/// [en-tête 14 o][messages de définition et de données][CRC 2 o]
/// ```
/// Chaque message de données référence une définition posée plus haut dans le
/// fichier, par un « numéro local » de 0 à 15 ; c'est ce qui évite de répéter le
/// nom des champs à chacune des onze mille secondes enregistrées.
class FitWriter {
  const FitWriter._();

  /// Origine des horodatages FIT : 31 décembre 1989, minuit UTC.
  static final _fitEpoch = DateTime.utc(1989, 12, 31);

  /// 255 = « development », le fabricant réservé aux appareils qui ne sont pas
  /// des produits commerciaux. Annoncer un numéro Garmin serait faux, et
  /// certains services vérifient la cohérence fabricant/produit.
  static const _manufacturerDevelopment = 255;

  static const _sportCycling = 2;
  static const _subSportGeneric = 0;

  /// Le fichier `.fit` d'une sortie.
  ///
  /// Lève [EmptyRide] si la sortie ne contient aucun point : un `.fit` sans
  /// `record` passe les parsers mais n'affiche rien nulle part, mieux vaut le
  /// dire au moment de l'export.
  static Uint8List build({
    required RideSession session,
    required List<TrackPoint> points,
  }) {
    if (points.isEmpty) throw const EmptyRide();

    final file = _FitFile();
    final start = points.first.at.toUtc();
    final end = points.last.at.toUtc();
    final summary = _Summary.of(points);

    // — file_id : ce que le fichier est. Premier message obligatoire.
    file.define(_Local.fileId, _Mesg.fileId, const [
      _FieldDef(0, _BaseType.fitEnum), // type : 4 = activity
      _FieldDef(1, _BaseType.uint16), // manufacturer
      _FieldDef(2, _BaseType.uint16), // product
      _FieldDef(3, _BaseType.uint32z), // serial_number
      _FieldDef(4, _BaseType.uint32), // time_created
    ]);
    file.data(_Local.fileId, {
      0: 4,
      1: _manufacturerDevelopment,
      2: 1,
      // Un numéro de série stable pour un même départ : c'est ce qui permet à un
      // service de reconnaître un doublon si le fichier est envoyé deux fois.
      3: _serialFor(session),
      4: _timestamp(session.startedAt),
    });

    // — event : début et fin de chronomètre. Facultatif au sens du format, mais
    // c'est lui qui distingue une pause d'un trou de données pour les lecteurs
    // qui recalculent le temps en mouvement.
    file.define(_Local.event, _Mesg.event, const [
      _FieldDef(253, _BaseType.uint32), // timestamp
      _FieldDef(0, _BaseType.fitEnum), // event : 0 = timer
      _FieldDef(1, _BaseType.fitEnum), // event_type : 0 = start, 4 = stop_all
      _FieldDef(4, _BaseType.uint8), // event_group
    ]);
    file.data(_Local.event, {253: _timestamp(start), 0: 0, 1: 0, 4: 0});

    // — record : la trace elle-même.
    file.define(_Local.record, _Mesg.record, _recordFields(summary));
    for (final point in points) {
      file.data(_Local.record, _recordValues(point, summary));
    }

    file.data(_Local.event, {253: _timestamp(end), 0: 0, 1: 4, 4: 0});

    // — lap : un seul tour, la sortie entière. Les tours manuels n'existent pas
    // encore côté appli ; le jour où ils existeront, cette liste en aura
    // plusieurs et le reste ne bougera pas.
    final elapsed = end.difference(start);
    final timer = Duration(seconds: points.length);

    file.define(_Local.lap, _Mesg.lap, const [
      _FieldDef(254, _BaseType.uint16), // message_index
      _FieldDef(253, _BaseType.uint32), // timestamp
      _FieldDef(0, _BaseType.fitEnum), // event : 9 = lap
      _FieldDef(1, _BaseType.fitEnum), // event_type : 1 = stop
      _FieldDef(2, _BaseType.uint32), // start_time
      _FieldDef(3, _BaseType.sint32), // start_position_lat
      _FieldDef(4, _BaseType.sint32), // start_position_long
      _FieldDef(5, _BaseType.sint32), // end_position_lat
      _FieldDef(6, _BaseType.sint32), // end_position_long
      _FieldDef(7, _BaseType.uint32), // total_elapsed_time
      _FieldDef(8, _BaseType.uint32), // total_timer_time
      _FieldDef(9, _BaseType.uint32), // total_distance
      _FieldDef(13, _BaseType.uint16), // avg_speed
      _FieldDef(14, _BaseType.uint16), // max_speed
      _FieldDef(15, _BaseType.uint8), // avg_heart_rate
      _FieldDef(16, _BaseType.uint8), // max_heart_rate
      _FieldDef(17, _BaseType.uint8), // avg_cadence
      _FieldDef(18, _BaseType.uint8), // max_cadence
      _FieldDef(19, _BaseType.uint16), // avg_power
      _FieldDef(20, _BaseType.uint16), // max_power
      _FieldDef(21, _BaseType.uint16), // total_ascent
      _FieldDef(22, _BaseType.uint16), // total_descent
    ]);
    file.data(_Local.lap, {
      254: 0,
      253: _timestamp(end),
      0: 9,
      1: 1,
      2: _timestamp(start),
      3: _semicircles(summary.firstLat),
      4: _semicircles(summary.firstLng),
      5: _semicircles(summary.lastLat),
      6: _semicircles(summary.lastLng),
      7: _milliseconds(elapsed),
      8: _milliseconds(timer),
      9: _centimetres(summary.distanceM),
      13: _millimetresPerSecond(summary.avgSpeedMps),
      14: _millimetresPerSecond(summary.maxSpeedMps),
      15: summary.avgHeartRate,
      16: summary.maxHeartRate,
      17: summary.avgCadence,
      18: summary.maxCadence,
      19: summary.avgPower,
      20: summary.maxPower,
      21: summary.ascentM.round(),
      22: summary.descentM.round(),
    });

    // — session : le résumé que lisent les sites d'analyse.
    file.define(_Local.session, _Mesg.session, const [
      _FieldDef(254, _BaseType.uint16), // message_index
      _FieldDef(253, _BaseType.uint32), // timestamp
      _FieldDef(0, _BaseType.fitEnum), // event : 8 = session
      _FieldDef(1, _BaseType.fitEnum), // event_type : 1 = stop
      _FieldDef(2, _BaseType.uint32), // start_time
      _FieldDef(3, _BaseType.sint32), // start_position_lat
      _FieldDef(4, _BaseType.sint32), // start_position_long
      _FieldDef(5, _BaseType.fitEnum), // sport
      _FieldDef(6, _BaseType.fitEnum), // sub_sport
      _FieldDef(7, _BaseType.uint32), // total_elapsed_time
      _FieldDef(8, _BaseType.uint32), // total_timer_time
      _FieldDef(9, _BaseType.uint32), // total_distance
      _FieldDef(14, _BaseType.uint16), // avg_speed
      _FieldDef(15, _BaseType.uint16), // max_speed
      _FieldDef(16, _BaseType.uint8), // avg_heart_rate
      _FieldDef(17, _BaseType.uint8), // max_heart_rate
      _FieldDef(18, _BaseType.uint8), // avg_cadence
      _FieldDef(19, _BaseType.uint8), // max_cadence
      _FieldDef(20, _BaseType.uint16), // avg_power
      _FieldDef(21, _BaseType.uint16), // max_power
      _FieldDef(22, _BaseType.uint16), // total_ascent
      _FieldDef(23, _BaseType.uint16), // total_descent
      _FieldDef(25, _BaseType.uint16), // first_lap_index
      _FieldDef(26, _BaseType.uint16), // num_laps
    ]);
    file.data(_Local.session, {
      254: 0,
      253: _timestamp(end),
      0: 8,
      1: 1,
      2: _timestamp(start),
      3: _semicircles(summary.firstLat),
      4: _semicircles(summary.firstLng),
      5: _sportCycling,
      6: _subSportGeneric,
      7: _milliseconds(elapsed),
      8: _milliseconds(timer),
      9: _centimetres(summary.distanceM),
      14: _millimetresPerSecond(summary.avgSpeedMps),
      15: _millimetresPerSecond(summary.maxSpeedMps),
      16: summary.avgHeartRate,
      17: summary.maxHeartRate,
      18: summary.avgCadence,
      19: summary.maxCadence,
      20: summary.avgPower,
      21: summary.maxPower,
      22: summary.ascentM.round(),
      23: summary.descentM.round(),
      25: 0,
      26: 1,
    });

    // — activity : le message de clôture, obligatoire pour un fichier
    // d'activité. `local_timestamp` porte l'heure locale du départ : sans lui,
    // un lecteur affiche la sortie en UTC.
    file.define(_Local.activity, _Mesg.activity, const [
      _FieldDef(253, _BaseType.uint32), // timestamp
      _FieldDef(0, _BaseType.uint32), // total_timer_time
      _FieldDef(1, _BaseType.uint16), // num_sessions
      _FieldDef(2, _BaseType.fitEnum), // type : 0 = manual
      _FieldDef(3, _BaseType.fitEnum), // event : 26 = activity
      _FieldDef(4, _BaseType.fitEnum), // event_type : 1 = stop
      _FieldDef(5, _BaseType.uint32), // local_timestamp
    ]);
    final offset = session.startedAt.toLocal().timeZoneOffset;
    file.data(_Local.activity, {
      253: _timestamp(end),
      0: _milliseconds(timer),
      1: 1,
      2: 0,
      3: 26,
      4: 1,
      5: _timestamp(end) + offset.inSeconds,
    });

    return file.finish();
  }

  /// Nom de fichier proposé à l'export : lisible, trié par date, sans espace.
  static String fileName(RideSession session) {
    final local = session.startedAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'sports-scope-${local.year}-${two(local.month)}-${two(local.day)}'
        '-${two(local.hour)}${two(local.minute)}.fit';
  }

  /// Les champs d'un `record`, restreints à ce que la sortie contient vraiment.
  ///
  /// Une définition est valable pour tout le fichier : impossible d'ajouter le
  /// cardio au bout d'une heure. On regarde donc l'ensemble des points avant
  /// d'écrire — un capteur qui a répondu une seule fois garde sa colonne, une
  /// sortie sans capteur n'en traîne aucune.
  static List<_FieldDef> _recordFields(_Summary summary) => [
        const _FieldDef(253, _BaseType.uint32), // timestamp
        if (summary.hasPosition) ...const [
          _FieldDef(0, _BaseType.sint32), // position_lat
          _FieldDef(1, _BaseType.sint32), // position_long
        ],
        if (summary.hasAltitude) const _FieldDef(2, _BaseType.uint16),
        if (summary.hasHeartRate) const _FieldDef(3, _BaseType.uint8),
        if (summary.hasCadence) const _FieldDef(4, _BaseType.uint8),
        const _FieldDef(5, _BaseType.uint32), // distance
        if (summary.hasSpeed) const _FieldDef(6, _BaseType.uint16),
        if (summary.hasPower) const _FieldDef(7, _BaseType.uint16),
      ];

  static Map<int, int?> _recordValues(TrackPoint point, _Summary summary) => {
        253: _timestamp(point.at),
        if (summary.hasPosition) ...{
          0: _semicircles(point.lat),
          1: _semicircles(point.lng),
        },
        if (summary.hasAltitude) 2: _altitude(point.altitudeM),
        if (summary.hasHeartRate) 3: point.heartRate,
        if (summary.hasCadence) 4: point.cadence?.round(),
        5: _centimetres(point.distanceM),
        if (summary.hasSpeed) 6: _millimetresPerSecond(_Summary.speedOf(point)),
        if (summary.hasPower) 7: point.power,
      };

  static int _timestamp(DateTime at) =>
      at.toUtc().difference(_fitEpoch).inSeconds;

  /// Un numéro de série tiré de l'instant de départ (secondes depuis l'époque
  /// FIT). `uint32z` : la valeur 0 y est l'invalide, d'où le `| 1`.
  static int _serialFor(RideSession session) =>
      (_timestamp(session.startedAt) & 0xFFFFFFFF) | 1;

  /// Degrés → semicercles, l'unité d'angle du format (2³¹ semicercles = 180°).
  static int? _semicircles(double? degrees) {
    if (degrees == null) return null;
    return (degrees * 2147483648 / 180).round();
  }

  /// Mètres → unité d'altitude FIT (échelle 5, décalage 500 m), bornée au
  /// domaine du `uint16` : de −500 m à +12 606 m.
  static int? _altitude(double? metres) {
    if (metres == null) return null;
    final raw = ((metres + 500) * 5).round();
    return raw.clamp(0, 0xFFFE).toInt();
  }

  static int? _centimetres(double? metres) =>
      metres == null ? null : (metres * 100).round().clamp(0, 0xFFFFFFFE).toInt();

  static int? _millimetresPerSecond(double? mps) =>
      mps == null ? null : (mps * 1000).round().clamp(0, 0xFFFE).toInt();

  static int _milliseconds(Duration duration) => duration.inMilliseconds;
}

/// Une sortie sans le moindre point ne fait pas un `.fit`.
class EmptyRide implements Exception {
  const EmptyRide();

  @override
  String toString() => 'Sortie vide : aucun point enregistré.';
}

/// Ce qu'on peut dire d'une sortie en une passe sur ses points.
class _Summary {
  _Summary._();

  double distanceM = 0;
  double ascentM = 0;
  double descentM = 0;

  double? firstLat;
  double? firstLng;
  double? lastLat;
  double? lastLng;

  bool hasPosition = false;
  bool hasAltitude = false;
  bool hasHeartRate = false;
  bool hasCadence = false;
  bool hasPower = false;
  bool hasSpeed = false;

  int? avgHeartRate;
  int? maxHeartRate;
  int? avgCadence;
  int? maxCadence;
  int? avgPower;
  int? maxPower;
  double? avgSpeedMps;
  double? maxSpeedMps;

  /// La vitesse d'un point : celle du GPS, ou à défaut celle du capteur de roue.
  ///
  /// Le GPS d'abord parce qu'il ne dépend d'aucun réglage ; le capteur de roue
  /// en secours parce qu'il continue de mesurer là où le GPS ne voit plus rien
  /// (tunnel, forêt dense).
  static double? speedOf(TrackPoint point) =>
      point.speedMps ?? point.wheelSpeedMps;

  /// Seuil de bruit du dénivelé : l'altitude GPS oscille de quelques mètres à
  /// l'arrêt. Sans hystérésis, une pause de dix minutes « gravit » cent mètres.
  static const _altitudeNoiseM = 1.0;

  static _Summary of(List<TrackPoint> points) {
    final summary = _Summary._();

    var hrSum = 0, hrCount = 0;
    var cadenceSum = 0.0, cadenceCount = 0;
    var powerSum = 0, powerCount = 0;
    var speedSum = 0.0, speedCount = 0;
    double? altitudeReference;

    for (final point in points) {
      summary.distanceM = point.distanceM;

      if (point.hasPosition) {
        summary.hasPosition = true;
        summary.firstLat ??= point.lat;
        summary.firstLng ??= point.lng;
        summary.lastLat = point.lat;
        summary.lastLng = point.lng;
      }

      final altitude = point.altitudeM;
      if (altitude != null) {
        summary.hasAltitude = true;
        altitudeReference ??= altitude;
        if (altitude - altitudeReference > _altitudeNoiseM) {
          summary.ascentM += altitude - altitudeReference;
          altitudeReference = altitude;
        } else if (altitudeReference - altitude > _altitudeNoiseM) {
          summary.descentM += altitudeReference - altitude;
          altitudeReference = altitude;
        }
      }

      final heartRate = point.heartRate;
      if (heartRate != null) {
        summary.hasHeartRate = true;
        hrSum += heartRate;
        hrCount++;
        summary.maxHeartRate = _max(summary.maxHeartRate, heartRate);
      }

      final cadence = point.cadence;
      if (cadence != null) {
        summary.hasCadence = true;
        cadenceSum += cadence;
        cadenceCount++;
        summary.maxCadence = _max(summary.maxCadence, cadence.round());
      }

      final power = point.power;
      if (power != null) {
        summary.hasPower = true;
        powerSum += power;
        powerCount++;
        summary.maxPower = _max(summary.maxPower, power);
      }

      final speed = speedOf(point);
      if (speed != null) {
        summary.hasSpeed = true;
        speedSum += speed;
        speedCount++;
        summary.maxSpeedMps =
            summary.maxSpeedMps == null || speed > summary.maxSpeedMps!
                ? speed
                : summary.maxSpeedMps;
      }
    }

    if (hrCount > 0) summary.avgHeartRate = (hrSum / hrCount).round();
    if (cadenceCount > 0) {
      summary.avgCadence = (cadenceSum / cadenceCount).round();
    }
    if (powerCount > 0) summary.avgPower = (powerSum / powerCount).round();
    if (speedCount > 0) summary.avgSpeedMps = speedSum / speedCount;

    return summary;
  }

  static int _max(int? current, int value) =>
      current == null || value > current ? value : current;
}

/// Types de base du format, avec leur code, leur taille et leur valeur
/// « invalide » — celle qui signifie « ce champ n'a pas de valeur ici ».
///
/// Seuls les types effectivement écrits figurent ici ; le format en compte une
/// quinzaine (`sint8`, `float32`, `string`…) dont aucun ne sert à une trace.
enum _BaseType {
  fitEnum(0x00, 1, 0xFF, signed: false),
  uint8(0x02, 1, 0xFF, signed: false),
  uint16(0x84, 2, 0xFFFF, signed: false),
  sint32(0x85, 4, 0x7FFFFFFF, signed: true),
  uint32(0x86, 4, 0xFFFFFFFF, signed: false),
  uint32z(0x8C, 4, 0, signed: false);

  const _BaseType(this.code, this.size, this.invalid, {required this.signed});

  final int code;
  final int size;
  final int invalid;
  final bool signed;
}

class _FieldDef {
  const _FieldDef(this.num, this.type);

  final int num;
  final _BaseType type;
}

/// Numéros de messages globaux, tels que définis par le profil FIT.
class _Mesg {
  static const fileId = 0;
  static const session = 18;
  static const lap = 19;
  static const record = 20;
  static const event = 21;
  static const activity = 34;
}

/// Numéros locaux, propres à ce fichier. Quinze au maximum ; on en utilise six,
/// un par type de message, posés une fois pour toutes.
class _Local {
  static const fileId = 0;
  static const event = 1;
  static const record = 2;
  static const lap = 3;
  static const session = 4;
  static const activity = 5;
}

/// Le fichier en cours d'écriture : en-tête, corps, CRC.
class _FitFile {
  final _body = BytesBuilder();
  final _definitions = <int, List<_FieldDef>>{};

  /// Pose la définition d'un type de message sous un numéro local.
  void define(int localNum, int globalNum, List<_FieldDef> fields) {
    _definitions[localNum] = fields;

    _body.addByte(0x40 | localNum); // en-tête d'enregistrement : définition
    _body.addByte(0); // réservé
    _body.addByte(0); // architecture : petit-boutiste
    _body.add(_uint16(globalNum));
    _body.addByte(fields.length);
    for (final field in fields) {
      _body.addByte(field.num);
      _body.addByte(field.type.size);
      _body.addByte(field.type.code);
    }
  }

  /// Écrit un message de données. Les champs absents de [values] — ou à `null` —
  /// prennent la valeur invalide de leur type.
  void data(int localNum, Map<int, int?> values) {
    final fields = _definitions[localNum];
    if (fields == null) {
      throw StateError('message $localNum utilisé avant sa définition');
    }

    _body.addByte(localNum); // en-tête d'enregistrement : données
    for (final field in fields) {
      _write(field.type, values[field.num]);
    }
  }

  void _write(_BaseType type, int? value) {
    final raw = value ?? type.invalid;
    final bytes = ByteData(type.size);
    switch (type.size) {
      case 1:
        if (type.signed) {
          bytes.setInt8(0, raw);
        } else {
          bytes.setUint8(0, raw);
        }
      case 2:
        if (type.signed) {
          bytes.setInt16(0, raw, Endian.little);
        } else {
          bytes.setUint16(0, raw, Endian.little);
        }
      default:
        if (type.signed) {
          bytes.setInt32(0, raw, Endian.little);
        } else {
          bytes.setUint32(0, raw, Endian.little);
        }
    }
    _body.add(bytes.buffer.asUint8List());
  }

  /// Assemble le fichier complet.
  ///
  /// L'en-tête porte la taille du corps, donc ne peut être écrit qu'à la fin ;
  /// il porte aussi son propre CRC (sur ses douze premiers octets), et le
  /// fichier se termine par le CRC de tout ce qui précède.
  Uint8List finish() {
    final body = _body.toBytes();

    final header = BytesBuilder()
      ..addByte(14) // taille de l'en-tête
      ..addByte(0x20) // version du protocole : 2.0
      ..add(_uint16(2140)) // version du profil : 21.40
      ..add(_uint32(body.length))
      ..add(const [0x2E, 0x46, 0x49, 0x54]); // « .FIT »
    final headerBytes = header.toBytes();
    final headerCrc = _crc16(headerBytes);

    final file = BytesBuilder()
      ..add(headerBytes)
      ..add(_uint16(headerCrc))
      ..add(body);
    final fileBytes = file.toBytes();

    return Uint8List.fromList([...fileBytes, ..._uint16(_crc16(fileBytes))]);
  }

  static List<int> _uint16(int value) =>
      [value & 0xFF, (value >> 8) & 0xFF];

  static List<int> _uint32(int value) => [
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ];

  /// Le CRC du format FIT : un CRC-16 par demi-octet, table de seize entrées
  /// telle que la publie le SDK Garmin.
  static int _crc16(List<int> bytes) {
    const table = [
      0x0000, 0xCC01, 0xD801, 0x1400, //
      0xF001, 0x3C00, 0x2800, 0xE401,
      0xA001, 0x6C00, 0x7800, 0xB401,
      0x5000, 0x9C01, 0x8801, 0x4400,
    ];

    var crc = 0;
    for (final byte in bytes) {
      var checksum = table[crc & 0xF];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ checksum ^ table[byte & 0xF];

      checksum = table[crc & 0xF];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ checksum ^ table[(byte >> 4) & 0xF];
    }
    return crc & 0xFFFF;
  }
}
