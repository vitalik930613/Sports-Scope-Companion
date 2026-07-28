import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Ce que l'appli sait de la session du site.
///
/// L'appli ne détient aucun identifiant et n'en veut pas : la session est le
/// cookie posé par une vraie connexion Keycloak dans un WebView. Tous les
/// WebViews d'une même appli Android partagent un seul pot de cookies — se
/// connecter une fois depuis l'écran Compte suffit donc à authentifier la
/// navigation, sans rien avoir à lui transmettre. Le cookie de Rails dure
/// 30 jours (`config/initializers/session_store.rb`) et Android le garde sur le
/// disque : la connexion survit au redémarrage de l'appli.
///
/// Cette classe ne fait que *retenir ce qu'on a observé*, pour pouvoir l'afficher
/// sans ouvrir de page. La vérité reste le cookie, et [record] la corrige dès
/// qu'un WebView charge une page du site.
class SiteSession extends ChangeNotifier {
  SiteSession(this._file);

  /// À n'appeler qu'après `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<SiteSession> open() async {
    final directory = await getApplicationSupportDirectory();
    final session = SiteSession(File(p.join(directory.path, _fileName)));
    await session.load();
    return session;
  }

  static const _fileName = 'site_session.json';

  final File _file;

  bool? _signedIn;
  DateTime? _checkedAt;

  /// `null` tant qu'aucune page du site n'a été observée — l'appli vient d'être
  /// installée, ou son fichier d'état a disparu.
  bool? get signedIn => _signedIn;

  /// Quand cet état a été constaté. Il peut avoir vieilli : une déconnexion
  /// faite depuis un navigateur ne se voit qu'au prochain chargement de page.
  DateTime? get checkedAt => _checkedAt;

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        if (decoded is Map) {
          _signedIn = decoded['signed_in'] as bool?;
          _checkedAt = DateTime.tryParse(decoded['checked_at'] as String? ?? '');
        }
      }
    } catch (e) {
      // Un état illisible n'est pas un état faux : on repart sur « inconnu »,
      // que la première page du site corrigera.
      debugPrint('[session] état illisible, ignoré : $e');
    }
    notifyListeners();
  }

  /// Enregistre ce qu'une page vient de révéler.
  ///
  /// [signedIn] à `null` veut dire « la page ne permet pas de conclure » (page
  /// de Keycloak, écran d'erreur hors ligne) : on garde alors l'état précédent
  /// plutôt que d'annoncer une déconnexion qui n'a pas eu lieu.
  Future<void> record(bool? signedIn) async {
    if (signedIn == null) return;
    if (_signedIn == signedIn) {
      _checkedAt = DateTime.now();
      return;
    }

    _signedIn = signedIn;
    _checkedAt = DateTime.now();
    notifyListeners();
    await _write();
  }

  Future<void> _write() async {
    try {
      await _file.parent.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'signed_in': _signedIn,
          'checked_at': _checkedAt?.toIso8601String(),
        }),
        flush: true,
      );
      await temporary.rename(_file.path);
    } catch (e) {
      // Perdre la persistance ne coûte qu'un « état inconnu » au prochain
      // démarrage : rien qui mérite de remonter à l'utilisateur.
      debugPrint('[session] écriture impossible : $e');
    }
  }
}

/// Demande à une page du site si elle est rendue pour un utilisateur connecté.
///
/// Deux balises du gabarit Rails (`app/views/layouts/application.html.erb`)
/// suffisent :
///  - `i18n-locale` est sur *toutes* les pages du site — son absence signale
///    qu'on regarde autre chose (Keycloak, page d'erreur du WebView) et qu'il
///    n'y a rien à conclure ;
///  - `user-preferences` n'est rendue que pour un utilisateur connecté. C'est
///    déjà le marqueur dont se sert le front lui-même (`isLoggedIn()`,
///    `app/javascript/userPreferences.ts`) : une seule définition de « connecté »
///    des deux côtés.
///
/// Renvoie `null` quand la page ne permet pas de conclure.
Future<bool?> probeSignedIn(WebViewController controller) async {
  const script = '''
    document.querySelector('meta[name="i18n-locale"]')
      ? (document.querySelector('meta[name="user-preferences"]') ? "yes" : "no")
      : "unknown"
  ''';

  try {
    // Android renvoie la valeur encodée en JSON (guillemets compris) : on teste
    // donc l'occurrence du mot plutôt que l'égalité.
    final result = (await controller.runJavaScriptReturningResult(script)).toString();
    if (result.contains('yes')) return true;
    if (result.contains('no')) return false;
    return null;
  } catch (e) {
    debugPrint('[session] sonde impossible : $e');
    return null;
  }
}
