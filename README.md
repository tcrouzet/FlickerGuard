# FlickerGuard

Application de barre des menus pour atténuer par logiciel l’écran OLED interne du MacBook Pro, en Swift 6 et SwiftUI. Français et anglais, sélectionnés automatiquement selon la langue de l’application dans macOS ; l’anglais est la langue de repli. La version est définie dans `Sources/FlickerGuard/Resources/Version.txt`, affichée dans l’interface et reprise dans les métadonnées de l’application. Aucune dépendance externe. macOS 27 ou ultérieur, Apple Silicon. La compilation des sources nécessite les Command Line Tools de Xcode et Swift 6.

## Télécharger et installer

Télécharger `FlickerGuard.app.zip` dans les [releases GitHub](https://github.com/tcrouzet/FlickerGuard/releases), décompresser et déplacer `FlickerGuard.app` dans Applications. Aucun outil de développement n’est nécessaire pour utiliser l’app. Prototype limité à l’écran interne `Mac17,13`, `APP 0x0610 / 0xA068` ; l’absence de scintillement n’a pas été mesurée.

L’app est signée ad hoc, sans certificat Developer ID ni notarisation Apple. Après un premier lancement bloqué, ouvrir Réglages Système → Confidentialité et sécurité → Ouvrir quand même, selon la [procédure Apple](https://support.apple.com/fr-fr/102445). L’autorisation Accessibilité sera demandée à l’activation pour capturer les touches de luminosité.

English: download `FlickerGuard.app.zip` from [GitHub releases](https://github.com/tcrouzet/FlickerGuard/releases), unzip and move the app to Applications. Requires macOS 27+ and Apple Silicon; only the internal Mac17,13 display is recognized. The app is not notarized: after the first blocked launch, use System Settings → Privacy & Security → Open Anyway. Enable Accessibility when activating brightness key capture.

## Publier une release

Depuis un clone du dépôt, sur `main`, avec Git et GitHub CLI connectés au compte autorisé :

```sh
./release.sh
```

Comme pour les plugins Obsidian, le script vérifie les tests, conserve la version initiale si son tag n’existe pas, incrémente ensuite le patch, commite les sources et pousse `main` puis le tag. GitHub Actions vérifie le script, relance les tests sur macOS 27, construit l’app, atteste la provenance du ZIP et le publie en préversion. Une erreur arrête le processus ; aucun tag ni fichier publié n’est écrasé. `_doc/` et `.build/` restent exclus du dépôt.

`Package.swift` est le manifeste Swift Package Manager et reste à la racine du projet. Il décrit la compilation, les ressources et les tests ; il ne fait pas partie de l’app téléchargée.

La provenance de l’archive téléchargée peut être vérifiée avec GitHub CLI :

```sh
gh attestation verify FlickerGuard.app.zip --repo tcrouzet/FlickerGuard
```

## Lancement

Quitter l’ancienne instance avant de reconstruire ou de lancer l’application :

```sh
python3 scripts/build-app.py
open .build/FlickerGuard.app
```

Le script assemble une application optimisée sans symboles de débogage, signée ad hoc, avec son identifiant `com.tcrouzet.FlickerGuard`, ses traductions et sa version. Il ne l’installe pas dans Applications et ne la publie pas. Le lancement graphique et l’attribution de l’autorisation nécessitent la session macOS de l’utilisateur ; ils ne sont pas vérifiés par la session automatisée de développement. `swift run FlickerGuard` reste possible pour développer, mais l’application `.app` fournit une identité plus claire dans les réglages d’Accessibilité.

L’application démarre inactive. Cliquer sur le soleil dans la barre des menus, puis :

1. Choisir « Ajustement automatique » : activé pour suivre la lumière ambiante, désactivé pour conserver un niveau fixe.
2. Cliquer sur « Activer ». À la première activation, autoriser FlickerGuard dans Réglages Système → Confidentialité et sécurité → Accessibilité, puis réessayer. Le lien présent dans l’interface ouvre ces réglages. Avant toute modification, l’application vérifie l’écran, le capteur si nécessaire et la capture des touches, puis sauvegarde la table RGB, le niveau matériel et l’état de luminosité automatique de macOS.
3. FlickerGuard suspend l’automatisme matériel de macOS et règle la dalle à 100 %. Le curseur « Luminosité logicielle » permet de choisir un niveau manuel entre 10 et 100 % ; le déplacer désactive l’ajustement automatique. Les mises à jour sont regroupées avec un délai de 40 ms. En mode fixe, le niveau est mémorisé pendant la session et retrouvé à la réactivation ; le premier niveau est initialisé depuis la luminosité macOS, avec un plancher à 10 %. En mode automatique, le niveau initial est directement calculé depuis la mesure ambiante ; le niveau matériel à 100 % ne sert jamais de référence automatique.

Chaque table est calculée depuis la sauvegarde originale, avec le même facteur appliqué aux trois canaux pour conserver leur calibration. Le niveau 100 % correspond à la table sauvegardée : l’interface indique « Sans atténuation ». Le suivi automatique, si choisi, et la capture des touches restent actifs pour pouvoir reprendre une atténuation sous 100 %. Aucun overlay n’est créé. Le grand bouton « Désactiver » restaure la table, le niveau matériel et le réglage automatique macOS précédents avant de rendre les touches à macOS. La restauration de secours et la fermeture, présentes dans le menu « … », restaurent également ces réglages. Les changements de fenêtre, de focus ou d’application ne réappliquent aucune table.

Le niveau matériel apparaît directement sous le curseur et est relu toutes les 250 ms, y compris à l’arrêt. Le menu « … » regroupe l’actualisation, la copie du diagnostic, la restauration de secours, l’accès aux autorisations et la fermeture. Le diagnostic copié inclut les identifiants de l’écran, l’EDID disponible, la taille de la table RGB, les niveaux matériel et logiciel, le mode automatique, le statut et la version. Actualiser ces informations ne remplace jamais la sauvegarde originale. Quand le suivi automatique fonctionne, le diagnostic détaille aussi les lux mesurés, le calibrage, la luminosité logicielle demandée, la cible retenue après stabilisation, le seuil et la durée de confirmation, le palier logiciel calculé, le nombre et l’ancienneté des lectures, la raison d’une absence de changement et le dernier ajustement automatique. La cible et le dernier niveau logiciel vérifié sont affichés avec deux décimales. Copier le diagnostic ne lit pas le capteur et ne modifie aucun réglage : il expose les dernières valeurs utilisées par la boucle active.

Les retours depuis la session graphique confirment la reconnaissance OLED de l’écran interne `0x0610 / 0xA068` sur `Mac17,13`, la luminosité matérielle à 100 %, la lecture de sa table RGB de 1 024 points par canal et le fonctionnement du curseur. La session automatisée de développement ne voit aucun écran interne actif ; le rendu de l’interface, la capture effective des touches, le capteur ambiant et les écritures matérielles restent à valider dans l’application. Une lecture seule du capteur depuis cette session ne trouve aucun service ALS ; le mode automatique signale explicitement cette indisponibilité plutôt que d’inventer une mesure. Le mode fixe reste utilisable sans capteur.

## Restauration et arrêt

La sauvegarde est conservée en mémoire avant toute écriture. Chaque écriture de table est relue avec CoreGraphics ; une différence supérieure à 0,001 sur un canal ou une taille différente déclenche une erreur et une tentative de restauration. Une sauvegarde n’est libérée qu’après restauration vérifiée de la table, du niveau matériel et du réglage automatique macOS. Les écritures matérielles et l’état automatique sont également relus. La restauration de la table est terminée avant le rétablissement du niveau matériel, pour éviter de cumuler l’ancien niveau et l’atténuation. Si la restauration échoue, elle reste disponible pour une nouvelle tentative, l’activation est bloquée et une fermeture normale est refusée avec un message d’erreur. La restauration cible uniquement l’écran interne identifié ; aucune réinitialisation ColorSync globale des écrans n’est utilisée.

Une restauration est demandée avant les changements de configuration signalés par CoreGraphics, à la mise en veille et au réveil. L’atténuation reste ensuite inactive jusqu’à une nouvelle activation manuelle. La fermeture normale, `Ctrl+C` et `SIGTERM` passent par la restauration. Un crash, une coupure de courant ou un arrêt forcé avec `SIGKILL` peuvent perdre la sauvegarde en mémoire et ne permettent pas de garantir la restauration, y compris celle de l’option de luminosité automatique macOS. Cette option peut alors nécessiter une réactivation manuelle dans Réglages Système → Moniteurs.

## Ajustement automatique

L’interrupteur « Ajustement automatique » est indépendant du bouton « Activer / Désactiver ». Activé, il utilise le capteur ambiant pour régler uniquement l’atténuation logicielle ; désactivé, le niveau reste fixe. Le curseur et les touches restent disponibles dans les deux modes : toute commande manuelle désactive immédiatement l’ajustement automatique, même si le niveau demandé est déjà affiché. Le niveau choisi reste fixe et mémorisé jusqu’à une réactivation explicite de l’interrupteur automatique. Cette prise en main ne relit pas le capteur ambiant. Le choix du mode et le niveau logiciel courant restent en mémoire pendant la session, sans ajout de préférences sur disque. En automatique, chaque activation recalcule sa cible avec la lumière actuelle et la courbe automatique, sans réétalonner celle-ci sur le niveau matériel ni sur la dernière valeur automatique. Le passage du mode fixe au mode automatique rejoint cette cible progressivement.

Le capteur est lu avec `ALCALSCopyALSServiceClient` de BezelServices, puis `IOHIDServiceClientCopyEvent` et `IOHIDEventGetFloatValue` d’IOKit. Ces API privées sont chargées dynamiquement et chaque mesure doit être finie et positive ou nulle. Si le capteur est inaccessible, le mode automatique refuse de démarrer ; l’interface permet de choisir le mode fixe. Une perte du capteur en cours de fonctionnement déclenche une restauration et affiche une erreur.

La courbe est propre à FlickerGuard : elle reproduit le principe d’adaptation à la lumière ambiante, pas la courbe interne ni l’apprentissage non documentés de macOS. Sa référence par défaut est fixe : 100 lux correspondent à 80 % logiciel. Elle donne notamment une cible de 35,35 % à 35 lux et atteint 100 % à 200 lux. Un doublement de `(lux + 1)` ajoute trente points de luminosité, soit une réponse trois fois plus forte que dans la version 0.3.0. Les réglages manuels ne modifient pas cette courbe ; ils font passer en mode fixe. Les mises à jour automatiques gardent leur mode actif et mémorisent le niveau courant sans déplacer la référence.

Le niveau reste fixe tant que la nouvelle cible s’écarte de moins de huit points de la dernière cible retenue. Un écart d’au moins huit points doit persister dans le même sens pendant deux secondes avant d’être accepté. Les bornes 10 % et 100 % sont également rejointes après cette confirmation, même pour un écart plus petit, pour pouvoir supprimer entièrement l’atténuation à forte lumière. Un retour dans la zone stable ou un changement de sens annule la confirmation en cours. La transition rejoint ensuite la cible retenue par pas de deux points au maximum toutes les 250 ms, puis cesse toute écriture de table jusqu’à une nouvelle variation importante. Les petits écarts successifs sont comparés à la même cible retenue : une dérive lente finit donc par déclencher un ajustement si son amplitude cumulée devient suffisante. Le curseur et les touches répondent immédiatement, arrêtent le suivi automatique et abandonnent toute confirmation en cours. Seul un changement effectif de niveau écrit une table ; aucun changement de fenêtre ou de focus n’intervient.

Les API DisplayServices `DisplayServicesAmbientLightCompensationEnabled` et `DisplayServicesEnableAmbientLightCompensation` permettent de sauvegarder, suspendre puis restaurer l’automatisme matériel ; `DisplayServicesSetBrightness` règle et restaure le niveau matériel. Leurs signatures sont référencées dans l’[en-tête de Lunar](https://github.com/alin23/Lunar/blob/master/Lunar/DDC/Lunar-Bridging-Header.h). L’implémentation est indépendante et n’ajoute aucune dépendance.

## Touches de luminosité

Quand l’application est active, les touches natives de luminosité pilotent uniquement le niveau logiciel, par pas de 1/16, avec répétition et bornes de 10 à 100 %. Les appuis et relâchements sont supprimés du flux transmis à macOS. Les touches de volume, lecture et rétroéclairage clavier restent transmises normalement. Le curseur conserve son délai de 40 ms ; les touches appliquent directement chaque pas. Aucun HUD supplémentaire n’est affiché.

La capture utilise un filtre actif CoreGraphics `CGEventTap` au niveau HID et nécessite l’autorisation Accessibilité. Aucune permission n’est demandée avant une activation explicite. Si la permission est absente ou la capture ne peut pas démarrer, aucune table n’est modifiée. Si la capture est désactivée par macOS ou un événement de luminosité ne peut pas être interprété, l’application arrête l’atténuation, tente une restauration et affiche une erreur. Elle ne réactive pas silencieusement un filtre devenu inopérant. En cas de restauration échouée, une capture encore fonctionnelle reste en place jusqu’à restauration réussie, pour ne pas rendre les touches matérielles pendant que l’affichage nécessite une récupération.

La luminosité matérielle est réglée à 100 % à l’activation et surveillée ensuite. Une baisse matérielle, une réactivation externe de l’automatisme macOS ou une erreur de lecture arrête l’atténuation et déclenche une restauration. FlickerGuard ne combat pas en boucle les commandes matérielles d’un autre programme. Le lancement au démarrage reste à développer pour le MVP complet. L’absence de PWM ou de scintillement nécessite des mesures sur la dalle.

La signature locale ad hoc peut nécessiter de réautoriser l’application après une reconstruction. Le script ne supprime et ne réinitialise aucune autorisation macOS.

## Vérification

```sh
swift test
```

Avec les Command Line Tools Swift 6.4.2 installés sur cette machine, le moteur de compilation ne charge pas automatiquement les macros de test. La commande adaptée est :

```sh
swift test -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Dans une session d’exécution restreinte comme celle utilisée pour le développement, les caches doivent aussi rester dans le projet et le bac à sable imbriqué de SwiftPM doit être désactivé :

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift test --disable-sandbox --cache-path .build/cache --config-path .build/configuration --security-path .build/security -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Les tests couvrent la reconnaissance stricte des signatures, les conditions d’activation, le calcul des courbes, la validation des valeurs et de la relecture, les contrôleurs inactifs, le décodage des touches, la cohérence des traductions et un diagnostic local en lecture seule. Ils couvrent aussi la courbe ambiante, la mémoire du niveau et du mode, ainsi que la prise de contrôle et la restauration face aux erreurs de chaque étape, avec un substitut du service d’affichage propre au projet. Ils n’écrivent aucune table et aucun réglage matériel sur un écran réel et ne demandent pas d’autorisation Accessibilité. Un écran absent ou inaccessible est un résultat de diagnostic, pas une validation de compatibilité OLED ni une preuve de lecture réussie sur un écran réel.

Le constructeur de l’application accepte les options de `swift build`. Dans la session restreinte de développement :

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" python3 scripts/build-app.py --disable-sandbox --cache-path .build/cache --config-path .build/configuration --security-path .build/security
```

## Limites de cette étape

La liste blanche dans `Sources/FlickerGuard/OLEDSignatureDatabase.swift` reconnaît uniquement l’écran interne du `Mac17,13`, avec fabricant `APP`, vendor ID `0x0610` et product ID `0xA068`. Les identifiants de panneau proviennent du diagnostic matériel fourni pour ce projet. Le modèle `Mac17,13` est lu dans `IODeviceTree` via IOKit et correspond au MacBook Pro 14 pouces PROLED XDR selon la [page d’identification Apple](https://support.apple.com/en-us/108052) ; Apple décrit le [PROLED XDR comme un écran tandem OLED](https://www.apple.com/macbook-pro/proled-xdr-display/). Cette correspondance ne valide aucune autre combinaison de panneau et de Mac.

Une entrée exige le modèle matériel du Mac et les vendor ID et product ID exacts, avec fabricant et nom du panneau facultatifs pour restreindre davantage la correspondance. Les noms commerciaux seuls ne permettent jamais l’activation. Un modèle de Mac inaccessible ou inconnu entraîne un refus. La détection reste indépendante de l’écran principal : un écran externe principal n’est pas sélectionné.

Le statut distingue un écran interne détecté avec une signature OLED non validée d’une identification d’écran impossible. Le diagnostic signale aussi une base de signatures vide. Une signature non validée ne signifie pas que le panneau n’est pas OLED.

L’EDID est recherché dans `IODisplayConnect` avec correspondance unique des vendor ID et product ID. Certains Mac Apple Silicon n’exposent pas leur EDID par ce service ; le diagnostic affiche alors « indisponible ». L’UUID fourni par ColorSync est affiché comme identifiant matériel ; son absence est signalée. Aucune propriété manquante n’est inventée.

La luminosité est lue avec `DisplayServicesGetBrightness`, chargé dynamiquement depuis le framework système privé DisplayServices. Sa signature est également utilisée dans le [code de Hammerspoon](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/brightness/libbrightness.m). Le niveau normalisé entre 0 et 1 est validé, puis affiché en pourcentage arrondi. Après le réglage matériel à 100 %, l’activation et la surveillance exigent la valeur brute 1, car une valeur inférieure peut s’afficher à 100 % après arrondi. C’est le niveau rapporté par macOS, pas une mesure de luminance en nits ou du PWM. Si l’API est absente, renvoie une erreur ou une valeur invalide, le diagnostic affiche « indisponible » avec la cause et l’atténuation est refusée ou arrêtée.
