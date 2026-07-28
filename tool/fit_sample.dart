// Génère un `.fit` d'exemple à partir d'une sortie synthétique.
//
// Sert à vérifier l'export avec un lecteur tiers — en particulier
// `fit-file-parser`, celui qu'utilise la page d'import de sports-scope. Les
// tests Dart vérifient la disposition des octets ; ce script vérifie qu'un
// lecteur qui ne vient pas de nous en tire les bonnes valeurs.
//
//   dart run tool/fit_sample.dart /tmp/sortie.fit
//
// Voir HOWTO.md pour la ligne de commande de relecture.
import 'dart:io';
import 'dart:math' as math;

import 'package:sports_scope_companion/recording/fit_writer.dart';
import 'package:sports_scope_companion/recording/ride_session.dart';
import 'package:sports_scope_companion/recording/track_point.dart';

void main(List<String> arguments) {
  final path = arguments.isEmpty ? 'sortie.fit' : arguments.first;

  // Dix minutes de vélo au bord du Léman : on monte, on accélère, le cardio
  // suit. Rien d'aléatoire — deux exécutions doivent donner le même fichier.
  final start = DateTime.utc(2026, 7, 28, 6, 30);
  const seconds = 600;

  var distance = 0.0;
  var lat = 46.5100;
  const lng = 6.6100;

  final points = <TrackPoint>[];
  for (var i = 0; i < seconds; i++) {
    final speed = 7 + 3 * math.sin(i / 60); // 4 à 10 m/s
    distance += speed;
    lat += speed / 111195; // plein nord, ça suffit pour une trace de contrôle

    points.add(TrackPoint(
      at: start.add(Duration(seconds: i)),
      distanceM: distance,
      lat: lat,
      lng: lng,
      altitudeM: 375 + i * 0.15,
      speedMps: speed,
      accuracyM: 5,
      heartRate: (140 + 12 * math.sin(i / 90)).round(),
      power: (210 + 60 * math.sin(i / 45)).round(),
      cadence: 88 + 4 * math.sin(i / 30),
      gearFront: 2,
      gearRear: 6 + (i ~/ 120),
    ));
  }

  final session = RideSession(
    id: RideSession.idFor(start),
    startedAt: start,
    endedAt: start.add(const Duration(seconds: seconds)),
    pointCount: points.length,
    distanceM: distance,
    movingSeconds: seconds,
  );

  final bytes = FitWriter.build(session: session, points: points);
  File(path).writeAsBytesSync(bytes);

  stdout.writeln('${bytes.length} octets écrits dans $path '
      '(${points.length} points, ${(distance / 1000).toStringAsFixed(2)} km)');
}
