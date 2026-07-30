import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/recording/gps_fix.dart';
import 'package:sports_scope_companion/ride/nav_state.dart';
import 'package:sports_scope_companion/ride/turn_proximity.dart';

/// Le chien de garde ne sert qu'une fois la page muette — c'est-à-dire au pire
/// moment de la sortie. Il doit donc être juste sans rien pouvoir essayer.
void main() {
  const proximity = TurnProximity();
  final now = DateTime.utc(2026, 7, 30, 10);

  /// Un virage à Lausanne, et une position à quelques dizaines de mètres au
  /// nord. Un degré de latitude vaut ~111 km : 0,0009° ≈ 100 m.
  const turnLat = 46.5200;
  const turnLng = 6.6300;

  NavState state({
    required Duration age,
    bool onRoute = true,
    bool withTurn = true,
    bool withPosition = true,
  }) =>
      NavState(
        at: now.subtract(age),
        onRoute: onRoute,
        offRoute: false,
        arrived: false,
        turn: withTurn
            ? NavTurn(
                phase: NavTurnPhase.far,
                distM: 400,
                lat: withPosition ? turnLat : null,
                lng: withPosition ? turnLng : null,
              )
            : null,
      );

  GpsFix fixAt(double lat, {Duration age = Duration.zero}) =>
      GpsFix(at: now.subtract(age), lat: lat, lng: turnLng);

  test('tant que la page parle, elle fait autorité', () {
    // Elle mesure le long du tracé ; nous ne savons compter que des mètres à vol
    // d'oiseau. Doubler son avis ne pourrait que le contredire.
    expect(
      proximity.imminent(
        state: state(age: const Duration(seconds: 2)),
        fix: fixAt(turnLat),
        now: now,
      ),
      isFalse,
    );
  });

  test('page muette et virage sous le seuil : alerte', () {
    expect(
      proximity.imminent(
        state: state(age: const Duration(seconds: 30)),
        // ~78 m au nord du virage, sous les 110 m du seuil.
        fix: fixAt(turnLat + 0.0007),
        now: now,
      ),
      isTrue,
    );
  });

  test('page muette mais virage encore loin : rien', () {
    expect(
      proximity.imminent(
        state: state(age: const Duration(seconds: 30)),
        // ~222 m : bien au-delà du seuil.
        fix: fixAt(turnLat + 0.002),
        now: now,
      ),
      isFalse,
    );
  });

  test('une position périmée ne vaut pas une position', () {
    // Elle dirait où le cycliste était il y a une minute, ce qui à 30 km/h fait
    // un demi-kilomètre d'écart — de quoi annoncer un virage déjà passé.
    expect(
      proximity.imminent(
        state: state(age: const Duration(seconds: 30)),
        fix: fixAt(turnLat, age: const Duration(seconds: 40)),
        now: now,
      ),
      isFalse,
    );
  });

  test('sans position de virage, rien à mesurer', () {
    expect(
      proximity.imminent(
        state: state(age: const Duration(seconds: 30), withPosition: false),
        fix: fixAt(turnLat),
        now: now,
      ),
      isFalse,
    );
  });

  test('en navigation libre, il n\'y a pas de virage à manquer', () {
    expect(
      proximity.imminent(
        state: state(age: const Duration(seconds: 30), onRoute: false),
        fix: fixAt(turnLat),
        now: now,
      ),
      isFalse,
    );
  });

  test('sans état ni position, il se tait', () {
    expect(proximity.imminent(state: null, fix: fixAt(turnLat), now: now),
        isFalse);
    expect(
      proximity.imminent(
        state: state(age: const Duration(seconds: 30)),
        fix: null,
        now: now,
      ),
      isFalse,
    );
  });
}
