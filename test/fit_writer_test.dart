import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/recording/fit_writer.dart';
import 'package:sports_scope_companion/recording/ride_session.dart';
import 'package:sports_scope_companion/recording/track_point.dart';

/// Le fichier produit est relu ici par un lecteur FIT minimal (voir plus bas) :
/// écrire des octets qu'on ne sait pas relire ne prouverait rien. La validation
/// sémantique — « est-ce que le site sait le lire ? » — se fait de son côté avec
/// `fit-file-parser`, voir `tool/fit_sample.dart` et HOWTO.md.
void main() {
  final start = DateTime.utc(2026, 7, 28, 12, 0, 0);
  final session = RideSession(
    id: RideSession.idFor(start),
    startedAt: start,
    endedAt: start.add(const Duration(seconds: 4)),
  );

  List<TrackPoint> ride() => [
        for (var i = 0; i < 5; i++)
          TrackPoint(
            at: start.add(Duration(seconds: i)),
            distanceM: i * 10.0,
            lat: 46.5 + i * 0.0001,
            lng: 6.6 + i * 0.0001,
            altitudeM: 400 + i * 2.0,
            speedMps: 10 + i.toDouble(),
            heartRate: 120 + i,
            power: 200 + i,
            cadence: 85 + i.toDouble(),
          ),
      ];

  test('en-tête, taille annoncée et CRC de fin', () {
    final bytes = FitWriter.build(session: session, points: ride());
    final view = ByteData.sublistView(bytes);

    expect(bytes[0], 14, reason: 'taille de l\'en-tête');
    expect(bytes[1], 0x20, reason: 'protocole 2.0');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), '.FIT');

    final dataSize = view.getUint32(4, Endian.little);
    expect(dataSize, bytes.length - 14 - 2,
        reason: 'le corps annoncé doit correspondre au fichier moins '
            'l\'en-tête et le CRC');

    // CRC de l'en-tête (12 premiers octets) et CRC du fichier entier.
    expect(view.getUint16(12, Endian.little), _crc16(bytes.sublist(0, 12)));
    expect(view.getUint16(bytes.length - 2, Endian.little),
        _crc16(bytes.sublist(0, bytes.length - 2)));
  });

  test('un record par point, avec les bonnes échelles', () {
    final points = ride();
    final messages = _parse(FitWriter.build(session: session, points: points));

    final records = messages.where((m) => m.global == 20).toList();
    expect(records, hasLength(points.length));

    final first = records.first;
    // Horodatage : secondes depuis le 31 décembre 1989 UTC.
    expect(first.uint32(253),
        start.difference(DateTime.utc(1989, 12, 31)).inSeconds);
    // Semicercles : 2³¹ pour 180°.
    expect(first.sint32(0), (46.5 * 2147483648 / 180).round());
    expect(first.sint32(1), (6.6 * 2147483648 / 180).round());
    // Altitude : échelle 5, décalage 500 m.
    expect(first.uint16(2), ((400 + 500) * 5).round());
    expect(first.uint8(3), 120);
    expect(first.uint8(4), 85);
    expect(first.uint32(5), 0, reason: 'distance en centimètres');
    expect(first.uint16(6), 10000, reason: 'vitesse en mm/s');
    expect(first.uint16(7), 200);

    expect(records.last.uint32(5), 4000, reason: '40 m → 4000 cm');
  });

  test('le résumé de session reprend les agrégats', () {
    final messages = _parse(FitWriter.build(session: session, points: ride()));
    final summary = messages.firstWhere((m) => m.global == 18);

    expect(summary.uint8(5), 2, reason: 'sport = cyclisme');
    expect(summary.uint32(9), 4000, reason: 'distance totale en cm');
    expect(summary.uint32(7), 4000, reason: 'temps écoulé en ms');
    expect(summary.uint32(8), 5000, reason: '5 points = 5 s de chronomètre');
    expect(summary.uint16(14), 12000, reason: 'vitesse moyenne (10..14 m/s)');
    expect(summary.uint16(15), 14000, reason: 'vitesse maxi');
    expect(summary.uint8(16), 122, reason: 'cardio moyen');
    expect(summary.uint8(17), 124, reason: 'cardio maxi');
    expect(summary.uint16(20), 202, reason: 'puissance moyenne');
    expect(summary.uint16(21), 204, reason: 'puissance maxi');
    expect(summary.uint16(22), 8, reason: '+2 m par point sur 4 intervalles');
    expect(summary.uint16(23), 0);
    expect(summary.uint16(26), 1, reason: 'un seul tour');
    expect(summary.uint32(59), 4000,
        reason: 'temps en mouvement en ms — la sortie roule de bout en bout');

    final lap = messages.firstWhere((m) => m.global == 19);
    expect(lap.uint32(52), 4000, reason: 'le tour porte le même temps en mouvement');

    // Un fichier d'activité doit se clore par un message `activity`.
    expect(messages.last.global, 34);
    expect(messages.where((m) => m.global == 0), hasLength(1));
  });

  test('un arrêt sépare le temps en mouvement du temps chronométré', () {
    // Sans `total_moving_time`, un lecteur retombe sur `total_timer_time` et
    // compte le feu rouge comme du roulage — vitesse moyenne fausse d'autant.
    final points = [
      for (var i = 0; i < 5; i++)
        TrackPoint(at: start.add(Duration(seconds: i)), distanceM: i * 10.0),
      // Dix secondes à l'arrêt, distance figée.
      for (var i = 5; i < 15; i++)
        TrackPoint(at: start.add(Duration(seconds: i)), distanceM: 40),
    ];

    final messages = _parse(FitWriter.build(session: session, points: points));
    final summary = messages.firstWhere((m) => m.global == 18);

    expect(summary.uint32(8), 15000, reason: '15 points = 15 s de chronomètre');
    expect(summary.uint32(59), 4000, reason: 'dont 4 s seulement à avancer');
  });

  test('une sortie sans capteur ne déclare pas leurs colonnes', () {
    final points = [
      for (var i = 0; i < 3; i++)
        TrackPoint(
          at: start.add(Duration(seconds: i)),
          distanceM: i * 5.0,
          lat: 46.5,
          lng: 6.6,
        ),
    ];

    final messages = _parse(FitWriter.build(session: session, points: points));
    final record = messages.firstWhere((m) => m.global == 20);

    // Sans cardio ni puissance dans la sortie, les champs n'existent pas dans
    // la définition — plutôt que d'écrire trois heures de « valeur invalide ».
    expect(record.fields.keys, containsAll(<int>[253, 0, 1, 5]));
    expect(record.fields.containsKey(3), isFalse);
    expect(record.fields.containsKey(7), isFalse);
    expect(record.fields.containsKey(2), isFalse, reason: 'pas d\'altitude');
  });

  test('les positions manquantes deviennent la valeur invalide', () {
    // Un point sous un tunnel : pas de position, mais du cardio. La colonne
    // existe (d'autres points l'ont), et ce point-là doit porter l'invalide,
    // pas une position à zéro au large du Ghana.
    final points = [
      TrackPoint(at: start, distanceM: 0, lat: 46.5, lng: 6.6, heartRate: 100),
      TrackPoint(
          at: start.add(const Duration(seconds: 1)),
          distanceM: 10,
          heartRate: 101),
    ];

    final records =
        _parse(FitWriter.build(session: session, points: points))
            .where((m) => m.global == 20)
            .toList();

    expect(records.last.sint32(0), 0x7FFFFFFF);
    expect(records.last.sint32(1), 0x7FFFFFFF);
    expect(records.last.uint8(3), 101);
  });

  test('une sortie vide est refusée', () {
    expect(() => FitWriter.build(session: session, points: const []),
        throwsA(isA<EmptyRide>()));
  });

  test('le nom de fichier porte la date locale', () {
    final local = DateTime(2026, 7, 28, 14, 3);
    final named = RideSession(id: 'x', startedAt: local);
    expect(FitWriter.fileName(named), 'sports-scope-2026-07-28-1403.fit');
  });
}

/// Un message relu dans le fichier.
class _Message {
  _Message(this.global, this.fields);

  final int global;
  final Map<int, Uint8List> fields;

  int uint8(int field) => fields[field]![0];
  int uint16(int field) =>
      ByteData.sublistView(fields[field]!).getUint16(0, Endian.little);
  int uint32(int field) =>
      ByteData.sublistView(fields[field]!).getUint32(0, Endian.little);
  int sint32(int field) =>
      ByteData.sublistView(fields[field]!).getInt32(0, Endian.little);
}

/// Lecteur FIT minimal : suit les définitions locales et découpe les messages
/// de données. Il ne connaît aucun champ par son nom — c'est justement ce qui
/// en fait un contrôle indépendant de l'écrivain.
List<_Message> _parse(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final headerSize = bytes[0];
  final end = headerSize + view.getUint32(4, Endian.little);

  final definitions = <int, List<(int, int)>>{}; // local → [(champ, taille)]
  final globals = <int, int>{};
  final messages = <_Message>[];

  var offset = headerSize;
  while (offset < end) {
    final header = bytes[offset++];
    final local = header & 0x0F;

    if (header & 0x40 != 0) {
      offset++; // réservé
      final littleEndian = bytes[offset++] == 0;
      globals[local] = view.getUint16(
          offset, littleEndian ? Endian.little : Endian.big);
      offset += 2;
      final count = bytes[offset++];
      final fields = <(int, int)>[];
      for (var i = 0; i < count; i++) {
        fields.add((bytes[offset], bytes[offset + 1]));
        offset += 3; // numéro, taille, type de base
      }
      definitions[local] = fields;
      continue;
    }

    final fields = <int, Uint8List>{};
    for (final (number, size) in definitions[local]!) {
      fields[number] = Uint8List.sublistView(bytes, offset, offset + size);
      offset += size;
    }
    messages.add(_Message(globals[local]!, fields));
  }

  return messages;
}

/// Le CRC du SDK Garmin, réécrit ici pour vérifier celui de l'écrivain.
int _crc16(List<int> bytes) {
  const table = [
    0x0000, 0xCC01, 0xD801, 0x1400, //
    0xF001, 0x3C00, 0x2800, 0xE401,
    0xA001, 0x6C00, 0x7800, 0xB401,
    0x5000, 0x9C01, 0x8801, 0x4400,
  ];

  var crc = 0;
  for (final byte in bytes) {
    for (final nibble in [byte & 0xF, (byte >> 4) & 0xF]) {
      final checksum = table[crc & 0xF];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ checksum ^ table[nibble];
    }
  }
  return crc;
}
