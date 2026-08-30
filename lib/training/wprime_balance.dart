import 'package:flutter/foundation.dart';

import '../account/rider_profile_store.dart';
import '../ble/sensor_hub.dart';

/// Le W′ balance — la « réserve d'allumettes » — en temps réel, modèle
/// différentiel de Skiba / Clarke :
///
///   dW′bal/dt = −(P − CP)                        quand P > CP  (on puise)
///   dW′bal/dt = (CP − P) · (W′₀ − W′bal) / W′₀   quand P ≤ CP  (on recharge)
///
/// Forme différentielle et non intégrale : pas de convolution ni de série de
/// toute la sortie à garder, un seul état (le solde courant) mis à jour à
/// chaque échantillon de puissance.
///
/// Alimenté par [SensorHub.latestPower] — donc uniquement avec un capteur de
/// puissance connecté. Sans CP ni W′₀ (profil pas encore chargé, ou courbe
/// puissance-durée trop pauvre pour l'ajustement côté site), [balanceJ] reste
/// `null` : une réserve inventée sur une CP devinée induirait l'effort en
/// erreur, exactement comme une zone calculée sans seuil.
class WPrimeBalance extends ChangeNotifier {
  WPrimeBalance({required this.hub, required this.riderProfile}) {
    hub.latestPower.addListener(_onPower);
    riderProfile.addListener(_onProfile);
    _onProfile();
  }

  final SensorHub hub;
  final RiderProfileStore riderProfile;

  /// Repli quand le site ne renvoie pas de W′ (courbe trop pauvre pour
  /// l'ajustement CP) mais qu'on a au moins une CP/FTP : l'ordre de grandeur
  /// admis pour un cycliste entraîné, faute de mieux — le solde reste alors
  /// indicatif.
  static const _defaultWPrimeJ = 20000.0;

  /// Au-delà de cet écart entre deux trames, on ne crédite ni ne débite : un
  /// capteur qui décroche puis revient ne doit pas compter son absence comme
  /// un effort ou un repos — même garde que `RideStats` sur les kilojoules.
  static const _maxGapS = 10.0;

  double? _cp;
  double? _wPrime0;
  double? _balanceJ;
  DateTime? _lastAt;

  /// La réserve restante, en joules — `null` tant que CP/W′₀ sont inconnus ou
  /// qu'aucune puissance n'a encore été lue.
  double? get balanceJ => _balanceJ;

  /// W′₀ (J), la réserve pleine — `null` si inconnue.
  double? get wPrimeJ => _wPrime0;

  /// La réserve en fraction de W′₀ (0 → vidée, 1 → pleine), pour la jauge.
  double? get fraction {
    final balance = _balanceJ;
    final full = _wPrime0;
    if (balance == null || full == null || full <= 0) return null;
    return (balance / full).clamp(0.0, 1.0);
  }

  void _onProfile() {
    final profile = riderProfile.profile;
    final cp = profile.criticalPowerW?.toDouble() ?? profile.ftpWatts?.toDouble();
    final wPrime =
        profile.wPrimeJ?.toDouble() ?? (cp == null ? null : _defaultWPrimeJ);
    if (cp == _cp && wPrime == _wPrime0) return;

    _cp = cp;
    _wPrime0 = wPrime;
    // Un changement de seuil en cours de sortie (rare) repart d'une réserve
    // pleine plutôt que d'un solde calculé sur l'ancienne CP.
    _balanceJ = wPrime;
    _lastAt = null;
    notifyListeners();
  }

  void _onPower() {
    final cp = _cp;
    final full = _wPrime0;
    final power = hub.latestPower.value?.toDouble();
    if (cp == null || full == null || power == null) return;

    final now = DateTime.now();
    final last = _lastAt;
    _lastAt = now;
    _balanceJ ??= full;

    if (last != null) {
      final dt = now.difference(last).inMilliseconds / 1000;
      if (dt > 0 && dt <= _maxGapS) {
        final balance = _balanceJ!;
        final next = power > cp
            ? balance - (power - cp) * dt
            : balance + (cp - power) * (full - balance) / full * dt;
        _balanceJ = next.clamp(0.0, full);
      }
    }
    notifyListeners();
  }

  /// Remise à zéro (réserve pleine) au départ d'une nouvelle sortie.
  void reset() {
    _balanceJ = _wPrime0;
    _lastAt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    hub.latestPower.removeListener(_onPower);
    riderProfile.removeListener(_onProfile);
    super.dispose();
  }
}
