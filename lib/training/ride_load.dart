import '../account/rider_profile.dart';
import '../recording/ride_stats.dart';

/// Ce que la sortie en cours coûte, en TSS.
///
/// Le site ne peut pas le savoir : la sortie n'est téléversée qu'une fois rentré.
/// C'est donc le téléphone qui l'ajoute à ce qui est déjà enregistré aujourd'hui
/// (`TrainingBudget.day.done`) pour remplir la jauge.
///
/// **La même cascade que le site** (`TrainingLoad.activity_tss`), et dans le même
/// ordre — puissance, cardio, estimation — pour que la barre du guidon annonce ce
/// que la page Performances comptera le soir venu :
///
///   TSS = heures × IF² × 100,  IF = NP / FTP  puis  FC moyenne / LTHR
///
/// L'estimation de dernier recours (IF 0,70, celui du vélo) n'est pas un luxe :
/// sans elle, un cycliste sans capteur verrait une jauge qui ne bouge jamais, alors
/// que sa sortie sera bel et bien comptée — environ 49 TSS de l'heure — dès qu'elle
/// remontera sur le site.
enum RideLoadSource {
  /// Puissance normalisée sur FTP : la mesure, quand elle existe.
  power,

  /// Cardio moyen sur seuil : le repli, un cran moins fidèle sur les efforts
  /// courts (le cœur met une minute à monter, les watts sont immédiats).
  heartRate,

  /// Ni l'un ni l'autre : l'intensité par défaut du vélo. Un ordre de grandeur,
  /// et l'appli le dit plutôt que de le faire passer pour une mesure.
  estimated,
}

/// L'intensité qu'on prête à une sortie vélo sans capteur. Miroir de
/// `TrainingLoad::ESTIMATED_IF['cycling']`.
const estimatedIntensityFactor = 0.70;

/// Borne l'IF pour éviter des TSS absurdes sur des données bancales — une FTP
/// saisie à 50 W, un cardiofréquencemètre qui s'emballe. Miroir de
/// `TrainingLoad::INTENSITY_CAP`.
const maxIntensityFactor = 1.5;

/// Le TSS de la sortie en cours, et d'où il sort.
///
/// `null` tant qu'il n'y a rien à compter : pas de temps en mouvement, donc pas de
/// charge. Zéro serait un chiffre, et un chiffre se lit comme une mesure.
({double tss, RideLoadSource source})? rideTss(
  RideStats stats,
  RiderProfile profile,
) {
  final hours = stats.movingTime.inMilliseconds / 3600000;
  if (hours <= 0) return null;

  final np = stats.normalizedPowerW;
  final ftp = profile.ftpWatts;
  if (np != null && np > 0 && ftp != null && ftp > 0) {
    return (tss: _tss(hours, np / ftp), source: RideLoadSource.power);
  }

  final hr = stats.avgHeartRate;
  final lthr = profile.lthr;
  if (hr != null && hr > 0 && lthr != null && lthr > 0) {
    return (tss: _tss(hours, hr / lthr), source: RideLoadSource.heartRate);
  }

  return (
    tss: _tss(hours, estimatedIntensityFactor),
    source: RideLoadSource.estimated,
  );
}

double _tss(double hours, double intensity) {
  final capped = intensity.clamp(0.0, maxIntensityFactor);
  return hours * capped * capped * 100;
}
