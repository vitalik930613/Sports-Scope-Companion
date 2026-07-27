# Connexion au téléphone
- Sur le téléphone deboggage sans fil -> associer l'appareil avec un code d'association
- dans WSL: adb pair <ip téléphone>:<port de l'association>
- ensuite adb connect <ip téléphone>:<port de debug> (pas le même port, le port est dans la page principale du telephone pas dans l'association
- l'appairage n'est pas à refaire il faut juste se reconnecter

#Pour lancer l'application (debug)
- cd ~/dev/sports-scope-companion
- flutter run

