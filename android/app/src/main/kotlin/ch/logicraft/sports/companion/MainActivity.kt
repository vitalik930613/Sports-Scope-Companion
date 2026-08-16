package ch.logicraft.sports.companion

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Baromètre, luminosité et boussole. Rien ne s'allume ici : chaque capteur
        // ne démarre qu'au premier abonné, côté Dart.
        PhoneSensors(applicationContext, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setBrightness" -> {
                        setBrightness(call.arguments as? Double)
                        result.success(null)
                    }
                    "setKeepScreenOn" -> {
                        setKeepScreenOn(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Règle le rétroéclairage pour cette fenêtre seulement — pas le réglage
     * système. Android le rend donc à sa valeur habituelle dès que l'appli
     * passe en arrière-plan, et l'utilisateur ne retrouve pas son téléphone
     * assombri si l'appli meurt en pleine veille de navigation.
     *
     * `BRIGHTNESS_OVERRIDE_NONE` (-1) rend la main au réglage système ; c'est
     * aussi le repli quand l'argument n'est pas un nombre exploitable.
     */
    private fun setBrightness(level: Double?) {
        val value = level?.toFloat() ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE

        // Le canal arrive déjà sur le thread principal, mais la navigation peut
        // rappeler cette méthode depuis un rechargement de page : on ne fait pas
        // reposer une écriture sur la fenêtre sur cette hypothèse.
        runOnUiThread {
            window.attributes = window.attributes.apply { screenBrightness = value }
        }
    }

    /**
     * Empêche (ou laisse) l'écran s'éteindre tout seul, pour cette fenêtre
     * seulement — même portée que [setBrightness], donc pas de veille oubliée
     * allumée si l'appli meurt en pleine page. Sert au banc de sniff GATT
     * (`GattSniffPage`) : un test de geste bouton se joue sur plusieurs
     * dizaines de secondes, largement au-delà du délai de veille du
     * téléphone, et une capture coupée par l'écran qui s'éteint perdrait la
     * trame qu'on attendait.
     */
    private fun setKeepScreenOn(keepOn: Boolean) {
        runOnUiThread {
            if (keepOn) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    companion object {
        private const val SCREEN_CHANNEL = "sports_scope/screen"
    }
}
