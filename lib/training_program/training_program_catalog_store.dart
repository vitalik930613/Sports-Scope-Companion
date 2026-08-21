import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'training_program_summary.dart';

/// Les programmes d'entraînement du compte, gardés sur disque.
///
/// Même raison de cache que `RouteCatalogStore`, et même besoin : choisir un
/// entraînement sur le point de partir (ou en pleine sortie, sac au dos) doit
/// marcher sans réseau. Même forme de fichier (JSON réécrit en entier, via un
/// temporaire renommé).
class TrainingProgramCatalogStore extends ChangeNotifier {
  TrainingProgramCatalogStore(this._file);

  /// À n'appeler qu'après `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<TrainingProgramCatalogStore> open() async {
    final directory = await getApplicationSupportDirectory();
    final store =
        TrainingProgramCatalogStore(File(p.join(directory.path, _fileName)));
    await store.load();
    return store;
  }

  static const _fileName = 'training_program_catalog.json';

  final File _file;

  List<TrainingProgramSummary> _programs = const [];
  DateTime? _updatedAt;

  List<TrainingProgramSummary> get programs => List.unmodifiable(_programs);

  DateTime? get updatedAt => _updatedAt;

  bool get isEmpty => _programs.isEmpty;

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        if (decoded is Map) {
          _programs = TrainingProgramSummary.listFromPayload(decoded['programs']);
          _updatedAt = DateTime.tryParse(decoded['updated_at'] as String? ?? '');
        }
      }
    } catch (e) {
      debugPrint('[entraînement] cache illisible, ignoré : $e');
    }
    notifyListeners();
  }

  /// Enregistre ce que le site vient de dire — une liste vide est enregistrée
  /// (même raison que `RouteCatalogStore.record` : « aucun programme » est une
  /// réponse, pas une absence de réponse).
  Future<void> record(List<TrainingProgramSummary> programs) async {
    _programs = List.of(programs);
    _updatedAt = DateTime.now();
    notifyListeners();
    await _write();
  }

  Future<void> _write() async {
    try {
      await _file.parent.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'programs': [for (final program in _programs) program.toJson()],
          'updated_at': _updatedAt?.toIso8601String(),
        }),
        flush: true,
      );
      await temporary.rename(_file.path);
    } catch (e) {
      debugPrint('[entraînement] écriture impossible : $e');
    }
  }
}
