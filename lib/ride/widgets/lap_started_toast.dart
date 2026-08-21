import 'package:flutter/material.dart';

/// Le toast qui annonce l'ouverture d'un tour — voir
/// `RideShellPage._onLapStarted`, qui l'affiche 2-3 s puis l'efface, et
/// `LapSettings.toast` (`lib/dashboard/ride_preset.dart`) pour le réglage qui
/// le coupe.
///
/// Un bandeau, pas une boîte à fermer : même raisonnement que
/// `BatteryAlertBanner` — sur la route, une confirmation à traverser coûterait
/// plus cher que l'information qu'elle protège. En bas de l'écran plutôt qu'en
/// haut ou au centre : c'est là qu'on marque un tour (bandeau du bas, encoche),
/// l'annonce paraît donc au plus près du geste qui vient de la déclencher, et
/// ne recouvre ni la pastille de batterie ni le popup de changement de
/// tronçon, tous deux ailleurs sur l'écran.
class LapStartedToast extends StatelessWidget {
  const LapStartedToast({super.key, required this.label});

  /// Le nom du tour qui vient de s'ouvrir — déjà résolu (libellé posé à
  /// l'ouverture, ou « Tour N ») par `RideShellPage._onLapStarted`.
  final String label;

  @override
  Widget build(BuildContext context) {
    // Pure information : rien à voler au bandeau ni au glissé de page qui
    // vivent sous ce toast.
    return IgnorePointer(
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flag_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Tour « $label » démarré',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
