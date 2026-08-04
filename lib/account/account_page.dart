import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../navigation/navigation_target.dart';
import 'site_session.dart';

/// L'écran de connexion au site — le site lui-même, dans un WebView.
///
/// On ne réimplémente pas la connexion : Keycloak s'ouvre dans la page, avec
/// son « se souvenir de moi » et son éventuelle double authentification. Le
/// cookie qu'il en résulte est celui du pot partagé par tous les WebViews de
/// l'appli — la navigation devient donc authentifiée sans transiter par le
/// code Dart. C'est aussi la seule façon honnête de faire : l'appli ne voit ni
/// mot de passe ni jeton.
///
/// Une session ratée n'est pas une panne de l'appli mais une navigation
/// anonyme : itinéraires sauvegardés invisibles, fond de carte par défaut à la
/// place du sien, POI muets (leur API demande une session).
///
/// **L'écran se referme tout seul dès que la connexion aboutit**, en rendant
/// `true`. Sans ça, le cycliste restait devant la page d'accueil du site après
/// s'être connecté, et devait remonter à la main tout l'historique de Keycloak —
/// une dizaine d'appuis, dont plusieurs qui rejouaient des étapes de l'auth. La
/// connexion est un moyen, pas une destination : une fois faite, on n'a plus rien
/// à faire ici.
class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.session,
    this.baseUrl = sportsScopeBaseUrl,
  });

  final SiteSession session;
  final String baseUrl;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late final WebViewController _controller;

  int _progress = 0;
  String? _error;

  /// Ce qui décide de refermer l'écran. Pur et testé — voir [SignInWatcher].
  final _watcher = SignInWatcher();

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        // Chaque page chargée est une occasion de vérifier : la page d'accueil
        // au départ, puis le retour de Keycloak une fois le mot de passe donné.
        onPageFinished: (_) => _check(),
        onWebResourceError: (error) {
          if (!error.isForMainFrame!) return;
          if (mounted) setState(() => _error = error.description);
        },
      ));

    final platform = _controller.platform;
    if (platform is AndroidWebViewController && kDebugMode) {
      AndroidWebViewController.enableDebugging(true);
    }

    _load();
  }

  void _load() {
    setState(() => _error = null);
    _controller.loadRequest(Uri.parse(widget.baseUrl));
  }

  Future<void> _check() async {
    final signedIn = await probeSignedIn(_controller);
    await widget.session.record(signedIn);
    if (!mounted) return;

    if (_watcher.read(signedIn)) {
      // `true` : l'appelant sait que la session vient de s'ouvrir, et qu'il y a
      // donc du neuf à aller chercher sur le site (itinéraires, profils).
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) => _screen(context);

  Widget _screen(BuildContext context) {
    return PopScope(
      // La connexion Keycloak est une suite de pages : le bouton retour doit
      // d'abord défaire l'étape en cours, pas quitter l'écran.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          // La flèche de la barre du haut **quitte l'écran**, elle ne remonte
          // pas l'historique — `Navigator.pop` ne passe pas par le `PopScope`
          // ci-dessus, contrairement au `maybePop` de la flèche par défaut.
          //
          // C'est la convention d'Android, et surtout la seule sortie sûre quand
          // la connexion n'aboutit pas : le retour système, lui, reste ce qu'il
          // doit être — défaire l'étape d'authentification en cours, et pas
          // abandonner au premier appui.
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Revenir à l\'accueil',
          ),
          title: const Text('Compte'),
          actions: [
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Recharger',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: _progress < 100
                ? LinearProgressIndicator(value: _progress / 100)
                : const SizedBox(height: 4),
          ),
        ),
        body: Column(
          children: [
            _statusBanner(),
            Expanded(
              child: _error != null
                  ? _errorView()
                  : WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBanner() {
    final signedIn = widget.session.signedIn;
    final (color, icon, text) = switch (signedIn) {
      true => (
          Colors.teal,
          Icons.check_circle,
          'Connecté — la navigation retrouvera tes itinéraires, ton fond de '
              'carte et tes POI.'
        ),
      false => (
          Colors.orange,
          Icons.person_off,
          'Non connecté — utilise « Se connecter » ci-dessous, une seule fois : '
              'la session est ensuite gardée sur le téléphone.'
        ),
      null => (Colors.grey, Icons.help_outline, 'État de la session inconnu.'),
    };

    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 16),
            const Text('Site injoignable', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            const Text(
              'Se connecter demande du réseau. Une fois la session ouverte, '
              'elle tient sans lui.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
