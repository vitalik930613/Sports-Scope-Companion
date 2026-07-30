import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/radar_alert_sound.dart';
import 'package:sports_scope_companion/ride/radar_severity.dart';

/// Un son de trop et le cycliste finit par ne plus l'entendre ; un son de moins
/// et il ne saura pas qu'une voiture arrive. C'est ce compte-là qui se vérifie
/// ici — le reste (le timbre, le volume) ne se juge que sur la route.
void main() {
  test('entrer en portée puis se rapprocher : deux sons, dans cet ordre', () {
    final voice = RadarAlertVoice();

    expect(voice.read(RadarSeverity.clear), isNull);
    expect(voice.read(RadarSeverity.approaching), RadarCue.approach);
    expect(voice.read(RadarSeverity.close), RadarCue.close);
  });

  test('une voiture qui reste derrière ne redit rien', () {
    final voice = RadarAlertVoice();

    voice.read(RadarSeverity.clear);
    expect(voice.read(RadarSeverity.approaching), RadarCue.approach);
    expect(voice.read(RadarSeverity.approaching), isNull);
    expect(voice.read(RadarSeverity.approaching), isNull);
  });

  test('une voiture qui s\'éloigne d\'un cran ne dit rien non plus', () {
    // Elle est toujours là : ce n'est pas un dégagement, et ce serait le pire
    // moment pour laisser croire le contraire.
    final voice = RadarAlertVoice();

    voice.read(RadarSeverity.clear);
    voice.read(RadarSeverity.close);

    expect(voice.read(RadarSeverity.approaching), isNull);
  });

  test('une voiture qui apparaît déjà proche va droit au son urgent', () {
    // Enchaîner les deux sons ferait perdre une demi-seconde à celui qui
    // compte.
    final voice = RadarAlertVoice();

    voice.read(RadarSeverity.clear);

    expect(voice.read(RadarSeverity.close), RadarCue.close);
  });

  test('la route redevenue libre a son propre son', () {
    final voice = RadarAlertVoice();

    voice.read(RadarSeverity.clear);
    voice.read(RadarSeverity.close);

    expect(voice.read(RadarSeverity.clear), RadarCue.clear);
  });

  test('perdre le radar ne s\'annonce pas comme une voie libre', () {
    // LA règle à ne pas casser : le son du dégagement dirait « c'est bon,
    // déporte-toi » pour une route que plus personne ne regarde.
    final voice = RadarAlertVoice();

    voice.read(RadarSeverity.clear);
    voice.read(RadarSeverity.close);

    expect(voice.read(RadarSeverity.absent), isNull);
  });

  test('le radar qui se connecte sur une route vide reste muet', () {
    final voice = RadarAlertVoice();

    expect(voice.read(RadarSeverity.clear), isNull);
  });

  test('chaque son a son fichier', () {
    for (final cue in RadarCue.values) {
      expect(cue.asset, startsWith('sounds/'));
      expect(cue.asset, endsWith('.wav'));
    }
  });
}
