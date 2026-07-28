import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/navigation/navigation_target.dart';

void main() {
  NavigationTarget? parse(String url) => NavigationTarget.parse(Uri.parse(url));

  group('liens propres à l\'appli', () {
    test('ouvre un itinéraire', () {
      final target = parse('sportsscope://navigate/abc123')!;

      expect(target.shareToken, 'abc123');
      expect(target.isFree, isFalse);
    });

    test('sans token, c\'est la navigation libre', () {
      expect(parse('sportsscope://navigate')!.isFree, isTrue);
      expect(parse('sportsscope://navigate/')!.isFree, isTrue);
    });

    test('un autre hôte n\'est pas de la navigation', () {
      expect(parse('sportsscope://reglages/abc'), isNull);
    });
  });

  group('liens web', () {
    test('reconnaît l\'URL de navigation d\'un itinéraire partagé', () {
      final target = parse('https://sports.logicraft.ch/routes/xyz789/navigate')!;

      expect(target.shareToken, 'xyz789');
    });

    test('tolère le préfixe de langue', () {
      expect(parse('https://sports.logicraft.ch/fr/routes/xyz/navigate')?.shareToken, 'xyz');
      expect(parse('https://sports.logicraft.ch/en/routes/xyz/navigate')?.shareToken, 'xyz');
    });

    test('reconnaît la navigation libre', () {
      expect(parse('https://sports.logicraft.ch/navigate')!.isFree, isTrue);
      expect(parse('https://sports.logicraft.ch/fr/navigate')!.isFree, isTrue);
    });

    test('ignore les pages qui ne sont pas de la navigation', () {
      // La page de partage d'un itinéraire n'est pas la navigation : l'ouvrir
      // dans l'appli enfermerait l'utilisateur dans un WebView pour rien.
      expect(parse('https://sports.logicraft.ch/routes/xyz'), isNull);
      expect(parse('https://sports.logicraft.ch/'), isNull);
      expect(parse('https://sports.logicraft.ch/activities/12'), isNull);
      expect(parse('mailto:antoine@example.com'), isNull);
    });

    test('accepte n\'importe quel domaine, y compris en développement', () {
      // L'App Link est filtré par Android sur le domaine de prod ; ici on ne
      // refait pas ce tri, sinon un lien collé depuis une instance de dev
      // serait rejeté sans raison.
      expect(parse('http://192.168.1.20:3000/routes/dev1/navigate')?.shareToken, 'dev1');
    });
  });

  group('URL construite', () {
    test('itinéraire', () {
      const target = NavigationTarget(shareToken: 'abc');

      expect(
        target.url(baseUrl: 'https://sports.logicraft.ch').toString(),
        'https://sports.logicraft.ch/routes/abc/navigate',
      );
    });

    test('navigation libre', () {
      expect(
        const NavigationTarget.free().url(baseUrl: 'https://sports.logicraft.ch').toString(),
        'https://sports.logicraft.ch/navigate',
      );
    });

    test('une base avec port et slash final reste correcte', () {
      expect(
        const NavigationTarget(shareToken: 'abc')
            .url(baseUrl: 'http://192.168.1.20:3000/')
            .toString(),
        'http://192.168.1.20:3000/routes/abc/navigate',
      );
    });
  });

  group('passage de session', () {
    test('le jeton est lu sur le lien propre à l\'appli', () {
      final target = parse('sportsscope://navigate/abc?handoff=jeton-1')!;

      expect(target.shareToken, 'abc');
      expect(target.handoffToken, 'jeton-1');
    });

    test('le jeton est lu sur l\'App Link', () {
      final target =
          parse('https://sports.logicraft.ch/routes/xyz/navigate?handoff=jeton-2')!;

      expect(target.handoffToken, 'jeton-2');
    });

    test('la navigation libre peut aussi porter un jeton', () {
      expect(parse('sportsscope://navigate?handoff=jeton-3')!.handoffToken, 'jeton-3');
    });

    test('un lien ordinaire n\'en porte pas', () {
      // Lien reçu par message, recopié à la main : la navigation reste publique
      // et s'ouvre en anonyme, sans que rien n'échoue.
      expect(parse('sportsscope://navigate/abc')!.handoffToken, isNull);
    });

    test('l\'URL ouvre la session avant la page demandée', () {
      // La navigation lit les préférences du compte au chargement : arriver
      // anonyme puis se connecter imposerait un rechargement.
      const target = NavigationTarget(shareToken: 'abc', handoffToken: 'jeton');
      final url = target.url(baseUrl: 'https://sports.logicraft.ch');

      expect(url.path, '/auth/handoff');
      expect(url.queryParameters['token'], 'jeton');
      expect(url.queryParameters['next'], '/routes/abc/navigate');
    });

    test('sans jeton, l\'URL reste celle de la page', () {
      final url = const NavigationTarget(shareToken: 'abc')
          .url(baseUrl: 'https://sports.logicraft.ch');

      expect(url.path, '/routes/abc/navigate');
      expect(url.queryParameters, isEmpty);
    });
  });
}
