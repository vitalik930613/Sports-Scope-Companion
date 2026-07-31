import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/account/rider_profile.dart';
import 'package:sports_scope_companion/account/threshold_gap.dart';

/// Le message d'accueil est la seule occasion de combler un seuil manquant : le
/// geste se fait sur le site, et une fois parti le cycliste a les mains prises.
/// Ce qu'il dit — et surtout à qui il ne dit rien — se vérifie ici.
void main() {
  const zone = TrainingZone(key: 'z1', lo: 0);
  const complete = RiderProfile(
    ftpWatts: 250,
    lthr: 160,
    powerZones: [zone],
    hrZones: [zone],
  );

  test('rien reçu du site : on demande une navigation connectée, pas un chiffre',
      () {
    final gap = ThresholdGap.of(complete, everReceived: false);

    // Le profil est pourtant complet : tant que l'appli ne l'a jamais reçu, lui
    // conseiller de saisir sa LTHR l'enverrait corriger ce qui est déjà bon.
    expect(gap, isNotNull);
    expect(gap!.title, 'Seuils inconnus');
    expect(gap.detail, contains('navigation'));
  });

  test('profil complet : aucun bandeau', () {
    expect(ThresholdGap.of(complete, everReceived: true), isNull);
  });

  test('la LTHR manque : on dit que l\'estimée ne compte pas', () {
    final gap = ThresholdGap.of(
      const RiderProfile(ftpWatts: 250, powerZones: [zone]),
      everReceived: true,
    );

    expect(gap!.title, 'LTHR non renseignée');
    // Le piège du site : seule `lthr_manual` produit des zones, la LTHR estimée
    // depuis les sorties n'en crée aucune. Sans cette phrase, le cycliste voit
    // sa LTHR affichée sur le site et ne comprend pas le bandeau vide.
    expect(gap.detail, contains('main'));
  });

  test('la FTP manque : le cardio connu ne fait pas taire le message', () {
    final gap = ThresholdGap.of(
      const RiderProfile(lthr: 160, hrZones: [zone]),
      everReceived: true,
    );

    expect(gap!.title, 'FTP inconnue');
  });

  test('les deux manquent : un seul message, pas deux', () {
    final gap = ThresholdGap.of(RiderProfile.empty, everReceived: true);

    expect(gap!.title, 'LTHR et FTP inconnues');
  });

  test('le seuil sans ses zones ne suffit pas', () {
    // Ce sont les zones qui font le tiret dans le bandeau. Un seuil connu dont
    // le site n'aurait pas envoyé les bornes laisse donc le bandeau muet : le
    // message doit suivre ce que le bandeau montre, pas ce que le profil dit.
    final gap = ThresholdGap.of(
      const RiderProfile(ftpWatts: 250, lthr: 160),
      everReceived: true,
    );

    expect(gap!.title, 'LTHR et FTP inconnues');
  });
}
