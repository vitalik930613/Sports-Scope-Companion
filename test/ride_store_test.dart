import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/recording/ride_store.dart';
import 'package:sports_scope_companion/recording/track_point.dart';

void main() {
  late Directory root;
  late RideStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rides_test');
    store = RideStore(Directory(p.join(root.path, 'rides')));
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> writePoints(String id, List<TrackPoint> points) async {
    final sink = await store.openPoints(id);
    for (final point in points) {
      sink.writeln(jsonEncode(point.toJson()));
    }
    await sink.flush();
    await sink.close();
  }

  List<TrackPoint> ride(DateTime start, int count) => [
        for (var i = 0; i < count; i++)
          TrackPoint(
            at: start.add(Duration(seconds: i)),
            distanceM: i * 7.5,
            lat: 46.5,
            lng: 6.6,
            heartRate: 130 + i,
          ),
      ];

  test('une sortie créée est immédiatement listée', () async {
    final session = await store.create(at: DateTime.utc(2026, 7, 28, 12));

    expect(session.id, '2026-07-28T12-00-00Z');
    expect(session.isFinished, isFalse);

    final listed = await store.list();
    expect(listed, hasLength(1));
    expect(listed.single.id, session.id);
  });

  test('les points se relisent dans l\'ordre écrit', () async {
    final session = await store.create(at: DateTime.utc(2026, 7, 28, 12));
    await writePoints(session.id, ride(session.startedAt, 4));

    final points = await store.points(session.id);
    expect(points, hasLength(4));
    expect(points.first.heartRate, 130);
    expect(points.last.distanceM, 22.5);
    expect(points.last.at, DateTime.utc(2026, 7, 28, 12, 0, 3));
  });

  test('une dernière ligne tronquée ne coûte que sa seconde', () async {
    final session = await store.create(at: DateTime.utc(2026, 7, 28, 12));
    await writePoints(session.id, ride(session.startedAt, 3));
    // Ce que laisse une batterie qui lâche en pleine écriture.
    await store
        .pointsFileFor(session.id)
        .writeAsString('{"t":"2026-07-28T12:00:03', mode: FileMode.append);

    final points = await store.points(session.id);
    expect(points, hasLength(3));
  });

  test('une sortie interrompue retrouve ses compteurs', () async {
    final session = await store.create(at: DateTime.utc(2026, 7, 28, 12));
    // Résumé volontairement en retard : c'est l'état après une coupure, le
    // fichier de points ayant continué au-delà du dernier enregistrement.
    await store.save(session.copyWith(pointCount: 1, distanceM: 7.5));
    await writePoints(session.id, ride(session.startedAt, 10));

    final listed = await store.list();
    expect(listed.single.pointCount, 10);
    expect(listed.single.distanceM, closeTo(67.5, 0.001));
    expect(listed.single.movingSeconds, 10);
    expect(listed.single.isFinished, isFalse);
  });

  test('une sortie terminée garde le résumé écrit à l\'arrêt', () async {
    final session = await store.create(at: DateTime.utc(2026, 7, 28, 12));
    await writePoints(session.id, ride(session.startedAt, 10));
    await store.save(session.copyWith(
      endedAt: DateTime.utc(2026, 7, 28, 13),
      pointCount: 10,
      distanceM: 67.5,
      movingSeconds: 10,
    ));

    final listed = await store.list();
    expect(listed.single.isFinished, isTrue);
    expect(listed.single.distanceM, 67.5);
  });

  test('les sorties sortent de la plus récente à la plus ancienne', () async {
    await store.create(at: DateTime.utc(2026, 7, 26, 8));
    await store.create(at: DateTime.utc(2026, 7, 28, 12));
    await store.create(at: DateTime.utc(2026, 7, 27, 18));

    final listed = await store.list();
    expect([for (final s in listed) s.startedAt.day], [28, 27, 26]);
  });

  test('supprimer une sortie emporte ses points', () async {
    final session = await store.create(at: DateTime.utc(2026, 7, 28, 12));
    await writePoints(session.id, ride(session.startedAt, 3));

    await store.delete(session.id);

    expect(await store.list(), isEmpty);
    expect(await store.pointsFileFor(session.id).exists(), isFalse);
  });

  test('un dossier sans résumé lisible est ignoré, pas fatal', () async {
    final session = await store.create(at: DateTime.utc(2026, 7, 28, 12));
    await File(p.join(store.directoryFor(session.id).path, 'session.json'))
        .writeAsString('{ ceci n\'est pas du JSON');
    await store.create(at: DateTime.utc(2026, 7, 28, 13));

    final listed = await store.list();
    expect(listed, hasLength(1));
    expect(listed.single.startedAt.hour, 13);
  });
}
