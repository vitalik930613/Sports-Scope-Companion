package ch.logicraft.sports.companion

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.BatteryManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Les capteurs du téléphone lui-même — baromètre, luminosité, boussole, batterie
 * — offerts à Dart en flux.
 *
 * Pourquoi du natif plutôt qu'un paquet : `sensors_plus` ne couvre que la
 * centrale inertielle (ni pression, ni lumière), et les greffons qui exposent
 * les autres sont peu maintenus. Ce fichier est la totalité du code de
 * plateforme — trois abonnements à `SensorManager` plus un à la batterie —
 * pour une dépendance de moins au cœur de l'enregistrement.
 *
 * Un flux par capteur, et non un canal unique porteur d'un type : chacun a sa
 * cadence propre (la boussole doit suivre un guidon qui tourne, la pression
 * change en dizaines de secondes) et surtout **son propre abonnement**. C'est ce
 * qui permet de n'allumer le magnétomètre qu'en navigation, sans réveiller le
 * baromètre.
 */
class PhoneSensors(private val context: Context, private val messenger: BinaryMessenger) {

    private val sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    /**
     * Déclinaison magnétique locale, en degrés, ou `null` tant qu'aucune position
     * n'a été fournie. C'est ce qui sépare le nord magnétique — le seul que
     * mesure le magnétomètre — du nord géographique, celui de la carte. En Suisse
     * l'écart est de 2 à 3°, invisible ; il dépasse 15° en Alaska et change de
     * signe d'un continent à l'autre. Une flèche fausse de 15° sur un carrefour
     * désigne la mauvaise rue.
     */
    private var declinationDeg: Float? = null

    init {
        MethodChannel(messenger, "$NAMESPACE/control").setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(
                    mapOf(
                        "pressure" to has(Sensor.TYPE_PRESSURE),
                        "light" to has(Sensor.TYPE_LIGHT),
                        // Le vecteur de rotation est un capteur *fusionné*
                        // (magnétomètre + accéléromètre + gyroscope). On le
                        // préfère au magnétomètre brut : lui seul reste stable
                        // quand le téléphone est incliné sur une potence, et il
                        // absorbe les perturbations d'un cadre en acier.
                        "heading" to has(Sensor.TYPE_ROTATION_VECTOR),
                        // Toujours vrai : même un appareil sans batterie amovible
                        // (branché en continu) répond à l'intent collant avec une
                        // charge simulée à 100 %. Gardé dans la carte quand même,
                        // par symétrie avec les trois autres — jamais supposé côté
                        // Dart.
                        "battery" to true,
                    )
                )
                "setLocation" -> {
                    setLocation(
                        (call.argument<Double>("lat")),
                        (call.argument<Double>("lng")),
                        (call.argument<Double>("altitudeM")) ?: 0.0,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Pression atmosphérique en hPa. Cadence lente : la pression ne bouge pas
        // en un dixième de seconde, et chaque trame réveille le moteur Dart.
        stream("$NAMESPACE/pressure", Sensor.TYPE_PRESSURE, SensorManager.SENSOR_DELAY_NORMAL,
            minGapMs = 1000, minDelta = 0.01f) { it.values[0].toDouble() }

        // Luminosité ambiante en lux. Même cadence : on cherche « tunnel ou plein
        // jour », pas les scintillements d'un feuillage.
        stream("$NAMESPACE/light", Sensor.TYPE_LIGHT, SensorManager.SENSOR_DELAY_NORMAL,
            minGapMs = 1000, minDelta = 1f) { it.values[0].toDouble() }

        // Cap en degrés depuis le nord GÉOGRAPHIQUE (0 = nord, 90 = est).
        // SENSOR_DELAY_UI et non GAME : la flèche doit suivre un guidon qui
        // tourne, pas animer un jeu — à 20 ms on ne ferait que payer des
        // franchissements de canal en pure perte.
        stream("$NAMESPACE/heading", Sensor.TYPE_ROTATION_VECTOR, SensorManager.SENSOR_DELAY_UI,
            minGapMs = 100, minDelta = 0.5f) { azimuthOf(it) }

        batteryStream()
    }

    private fun has(type: Int): Boolean = sensors.getDefaultSensor(type) != null

    private fun setLocation(lat: Double?, lng: Double?, altitudeM: Double) {
        if (lat == null || lng == null) return
        declinationDeg = GeomagneticField(
            lat.toFloat(), lng.toFloat(), altitudeM.toFloat(), System.currentTimeMillis(),
        ).declination
    }

    /**
     * Cap du téléphone, déclinaison comprise, ramené dans [0, 360[.
     *
     * Modèle simple et unique : **le téléphone est une boussole tenue à plat**.
     * `getOrientation` rend l'azimut du haut de l'appareil (axe +y) projeté à
     * l'horizontale ; posé ou peu incliné sur une potence, c'est la direction
     * vers laquelle regarde le cycliste. Tenu franchement redressé, la mesure
     * perd son sens — on demande donc à l'utilisateur de le mettre à plat, comme
     * une vraie boussole.
     *
     * Tant qu'on n'a pas de position, on rend le cap MAGNÉTIQUE plutôt que rien :
     * quelques degrés d'erreur valent mieux qu'une flèche qui ne tourne pas.
     */
    private fun azimuthOf(event: SensorEvent): Double {
        val matrix = FloatArray(9)
        // Certains capteurs rendent 5 composantes ; passer plus de 4 valeurs à
        // getRotationMatrixFromVector plante sur d'anciens Samsung.
        val rv = if (event.values.size > 4) event.values.copyOf(4) else event.values
        SensorManager.getRotationMatrixFromVector(matrix, rv)
        val orientation = FloatArray(3)
        SensorManager.getOrientation(matrix, orientation)
        val magnetic = Math.toDegrees(orientation[0].toDouble())
        val trueNorth = magnetic + (declinationDeg ?: 0f)
        return ((trueNorth % 360) + 360) % 360
    }

    /**
     * Branche un capteur sur un `EventChannel`.
     *
     * L'écouteur n'est enregistré qu'à l'abonnement et **désenregistré à
     * l'annulation** : un capteur laissé branché continue de réveiller le
     * processeur des heures après la sortie. C'est le seul point de ce fichier
     * qui coûte de la batterie si on le rate.
     *
     * `minGapMs` et `minDelta` sont un filtre d'ÉMISSION, pas de mesure : le
     * capteur échantillonne à sa cadence, on ne traverse le canal que lorsque la
     * valeur a bougé de quelque chose de visible. Une boussole immobile ne coûte
     * alors rien du tout.
     */
    private fun stream(
        name: String,
        type: Int,
        delay: Int,
        minGapMs: Long,
        minDelta: Float,
        read: (SensorEvent) -> Double,
    ) {
        EventChannel(messenger, name).setStreamHandler(object : EventChannel.StreamHandler {
            private var listener: SensorEventListener? = null

            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val sensor = sensors.getDefaultSensor(type)
                if (sensor == null) {
                    // Pas de baromètre sur cet appareil : on ferme le flux au lieu
                    // de le laisser muet. Dart distingue ainsi « pas de capteur »
                    // de « capteur qui n'a pas encore parlé ».
                    events?.endOfStream()
                    return
                }
                var lastAt = 0L
                var lastValue = Double.NaN
                val handler = object : SensorEventListener {
                    override fun onSensorChanged(event: SensorEvent) {
                        val value = read(event)
                        val now = System.currentTimeMillis()
                        val moved = lastValue.isNaN() || kotlin.math.abs(value - lastValue) >= minDelta
                        if (now - lastAt < minGapMs || !moved) return
                        lastAt = now
                        lastValue = value
                        events?.success(value)
                    }

                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
                }
                listener = handler
                sensors.registerListener(handler, sensor, delay)
            }

            override fun onCancel(arguments: Any?) {
                listener?.let { sensors.unregisterListener(it) }
                listener = null
            }
        })
    }

    /**
     * Le pourcentage de charge du téléphone (0-100). Pas un capteur
     * `SensorManager` : on écoute l'intent COLLANT `ACTION_BATTERY_CHANGED`, qui
     * rend sa dernière valeur connue dès l'enregistrement — pas d'attente pour
     * la première lecture, contrairement aux trois flux ci-dessus.
     *
     * Utile en particulier pendant une sortie : l'appli passe l'écran en plein
     * immersif (barres système masquées), donc la pastille de batterie
     * d'Android disparaît avec elles.
     */
    private fun batteryStream() {
        EventChannel(messenger, "$NAMESPACE/battery").setStreamHandler(object : EventChannel.StreamHandler {
            private var receiver: BroadcastReceiver? = null

            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val handler = object : BroadcastReceiver() {
                    override fun onReceive(receiverContext: Context?, intent: Intent?) {
                        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                        if (level < 0 || scale <= 0) return
                        events?.success((level * 100) / scale)
                    }
                }
                receiver = handler
                val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                // Android 13+ (API 33) refuse un `registerReceiver` dynamique sans
                // préciser s'il est exporté, sous peine de `SecurityException` au
                // lancement. Non exporté : rien d'extérieur à l'appli n'a besoin
                // d'émettre cet intent, seul le système le fait.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    context.registerReceiver(handler, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    context.registerReceiver(handler, filter)
                }
            }

            override fun onCancel(arguments: Any?) {
                receiver?.let { context.unregisterReceiver(it) }
                receiver = null
            }
        })
    }

    companion object {
        private const val NAMESPACE = "sports_scope/phone_sensors"
    }
}
