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
      final target = parse('https://app.logicraft.ch/routes/xyz789/navigate')!;

      expect(target.shareToken, 'xyz789');
    });

    test('tolère le préfixe de langue', () {
      expect(parse('https://app.logicraft.ch/fr/routes/xyz/navigate')?.shareToken, 'xyz');
      expect(parse('https://app.logicraft.ch/en/routes/xyz/navigate')?.shareToken, 'xyz');
    });

    test('reconnaît la navigation libre', () {
      expect(parse('https://app.logicraft.ch/navigate')!.isFree, isTrue);
      expect(parse('https://app.logicraft.ch/fr/navigate')!.isFree, isTrue);
    });

    test('ignore les pages qui ne sont pas de la navigation', () {
      // La page de partage d'un itinéraire n'est pas la navigation : l'ouvrir
      // dans l'appli enfermerait l'utilisateur dans un WebView pour rien.
      expect(parse('https://app.logicraft.ch/routes/xyz'), isNull);
      expect(parse('https://app.logicraft.ch/'), isNull);
      expect(parse('https://app.logicraft.ch/activities/12'), isNull);
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
        target.url(baseUrl: 'https://app.logicraft.ch').toString(),
        'https://app.logicraft.ch/routes/abc/navigate',
      );
    });

    test('navigation libre', () {
      expect(
        const NavigationTarget.free().url(baseUrl: 'https://app.logicraft.ch').toString(),
        'https://app.logicraft.ch/navigate',
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
}
