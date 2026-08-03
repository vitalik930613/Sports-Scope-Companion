import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'training_budget.dart';

/// Le dernier budget de charge connu, gardé sur disque.
///
/// Même forme que [RiderProfileStore], et pour la même raison : c'est la page de
/// navigation qui le pousse, une fois chargée et une fois connectée. Sans cache,
/// une sortie démarrée hors ligne — le cas normal en montagne, et précisément
/// celle où l'on se demande jusqu'où pousser — n'aurait aucun budget à afficher.
///
/// La différence avec le profil tient en un mot : **il se périme**. Un seuil
/// cardiaque de la semaine dernière reste vrai ; un budget de la semaine dernière,
/// non. D'où la date portée par le document lui-même ([TrainingBudget.date]) — le
/// composant la compare au jour courant et le dit, plutôt que d'afficher un
/// plafond d'avant-hier comme s'il valait pour aujourd'hui.
class TrainingBudgetStore extends ChangeNotifier {
  TrainingBudgetStore(this._file);

  /// À n'appeler qu'après `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<TrainingBudgetStore> open() async {
    final directory = await getApplicationSupportDirectory();
    final store = TrainingBudgetStore(File(p.join(directory.path, _fileName)));
    await store.load();
    return store;
  }

  static const _fileName = 'training_budget.json';

  final File _file;

  TrainingBudget? _budget;

  /// `null` quand on n'a jamais rien reçu — compte tout neuf, ou personne ne
  /// s'est encore connecté depuis l'appli. Le composant l'annonce en toutes
  /// lettres au lieu d'afficher des zéros, qui se liraient « repos complet ».
  TrainingBudget? get budget => _budget;

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        _budget = TrainingBudget.fromJson(
          jsonDecode(await _file.readAsString()),
        );
      }
    } catch (e) {
      // Un budget illisible n'est pas un budget faux : on repart sur « inconnu »,
      // que la prochaine page du site corrigera.
      debugPrint('[budget] budget illisible, ignoré : $e');
    }
    notifyListeners();
  }

  /// Enregistre ce que la page vient de publier.
  ///
  /// Un budget indéchiffrable est ignoré plutôt qu'écrit : il veut dire « le site
  /// n'a rien pu dire » (compte sans une seule sortie, session expirée), et
  /// l'écraser ferait perdre un budget parfaitement valable reçu la veille — qui,
  /// daté, reste utilisable.
  Future<void> record(TrainingBudget? budget) async {
    if (budget == null) return;

    _budget = budget;
    notifyListeners();
    await _write();
  }

  Future<void> _write() async {
    try {
      await _file.parent.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode(_budget?.toJson()),
        flush: true,
      );
      await temporary.rename(_file.path);
    } catch (e) {
      // Perdre la persistance ne coûte qu'un budget absent au prochain départ
      // hors ligne : rien qui mérite de remonter à l'utilisateur.
      debugPrint('[budget] écriture impossible : $e');
    }
  }
}
