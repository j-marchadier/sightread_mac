# Pianissimac

**Pianissimac** est une application macOS native pour apprendre le piano avec un clavier MIDI.
Branchez votre clavier, choisissez un morceau, et jouez en suivant les notes qui tombent ou la partition :
Pianissimac écoute ce que vous jouez, vous attend si vous le souhaitez et mesure vos progrès. Tout fonctionne
**hors ligne** : aucune connexion réseau, aucune collecte de données.

Écrite en Swift 6 et SwiftUI pour macOS 26 Tahoe et plus récent, avec le design **Liquid Glass**.

## Fonctionnalités

### Quatre visualisations

- **Notes qui tombent** vers un clavier de 88 touches (ou réduit à la tessiture du morceau), une couleur par main.
- **Partition simplifiée** : portées défilantes où la longueur des notes est proportionnelle à leur durée.
- **Partition rythmique** : vraie notation (quantification, ligatures, silences, liaisons, altérations) avec la
  police SMuFL Leland.
- **Partition complète** : la page entière, avec retours à la ligne et curseur de lecture.

Noms des notes (Do Ré Mi ou C D E), clavier complet ou réduit, coloration des notes réussies et manquées.

### Trois modes de pratique

- **Apprendre** : le morceau avance et chaque note des mains actives est jugée (Parfait, Bien, Manqué, Erreur).
- **Attendre** : le morceau s'arrête sur chaque note jusqu'à ce que vous la jouiez. Une **tolérance** réglable
  (0,25 s par défaut) laisse jouer légèrement en avance ou en retard ; au-delà, le curseur **revient en douceur**
  juste avant la note attendue.
- **Écouter** : le morceau est joué pour vous, sans jugement.

Main gauche, main droite ou les deux (attribution automatique des pistes, modifiable), **vitesse** de 10 à 200 %,
**boucle** sur des mesures, **métronome**, **décompte**, **transposition**. Bilan de fin de session (précision,
série, score) et historique de progression par morceau.

### Doigtés

- **Doigtés écrits** lus dans les fichiers MusicXML et affichés sur la partition et les notes qui tombent.
- **Doigtés suggérés** calculés hors ligne pour chaque main quand le fichier n'en contient pas, distingués
  visuellement des doigtés écrits. Affichage au choix : masqués, écrits seulement, écrits et suggérés.

### Bibliothèque et import

- **Pochettes** façon album : chaque morceau a une pochette colorée générée par l'app (dégradé propre au
  compositeur, motif musical, titre), remplaçable par votre propre image dans « Modifier… ». La bibliothèque
  s'affiche en **grille de pochettes** (triable par titre, compositeur, difficulté ou dernière séance) ou en
  **liste** ; la fiche du morceau prend les couleurs de sa pochette.
- **16 morceaux intégrés** (Bach, Beethoven, Debussy, Mozart, Satie, Joplin…), disponibles hors ligne.
- Import de fichiers **MIDI** (`.mid`, `.midi`) et **MusicXML** (`.musicxml`, `.xml`, `.mxl`) :
  **Fichier › Importer… (⌘O)**, **glisser-déposer** sur la fenêtre, sur l'**icône du Dock**, **Ouvrir avec**
  depuis le Finder, ou **dossier surveillé** (les fichiers ajoutés apparaissent en quelques secondes).
- Édition des métadonnées (titre, compositeur, difficulté) et du choix des pistes par main ; difficulté estimée
  automatiquement.
- **Trouver des partitions…** (menu Aide) : sources libres (Mutopia, piano-midi.de, OpenScore) ouvertes dans le
  navigateur.

### Modifier les notes sur la partition

Tous les morceaux, intégrés comme importés, se corrigent directement sur la portée (**Modifier les notes…**, depuis la
fiche du morceau ou le menu contextuel) :

- **Sélection** : clic sur une tête de note (⇧ ou ⌘ pour en ajouter), ⌘A pour tout sélectionner ; glisser une note
  la déplace dans le temps et sur la portée.
- **Saisie** (N) : choisissez une valeur (ronde à triple croche, pointée) dans la palette, puis cliquez sur la portée,
  tapez une lettre A à G ou jouez au clavier MIDI (les touches jouées ensemble forment un accord). Un double-clic
  ajoute aussi une note.
- **Modifier** : ↑ ↓ demi-ton, ⌥↑ ⌥↓ degré de la gamme, ⌘↑ ⌘↓ octave, ← → déplacer d'une valeur, ♭ ♮ ♯, durée,
  main (L, R), doigté (1 à 5, 0 pour l'effacer), ⌫ supprimer ; silences, ligatures et altérations se recalculent.
- **Annuler** (⌘Z) et **rétablir** (⇧⌘Z) ; les modifications sont enregistrées automatiquement, à côté du fichier
  d'origine qui reste intact : **Rétablir l'original** revient aux notes du morceau.

### Partitions en PDF

- **Fichier › Exporter la partition en PDF… (⇧⌘E)** : la partition du morceau ouvert (lecteur ou fiche du
  morceau) en notation rythmique, sur pages A4, avec titre, compositeur, numéros de page, doigtés et noms des notes
  selon vos options d'affichage, et la transposition et les mains du morceau.
- **Fichier › Imprimer la partition… (⌘P)** : fenêtre d'impression du système, qui propose aussi « Enregistrer
  au format PDF ».

### Exercices et jeu libre

- **Lecture de notes** : des notes isolées s'affichent sur la portée (clé de sol, clé de fa ou les deux) ; la
  lecture attend chaque note.
- **Phrases** : de courtes pièces générées à l'infini sur une suite d'accords, en quatre niveaux rythmiques.
- **Jeu libre** (⇧⌘J) : jouez librement, avec les notes qui montent au-dessus du clavier.

### Son et clavier

- Piano de la banque General MIDI de macOS, faible latence, pédale de sustain.
- **Volumes** séparés : général, votre piano, le morceau et le métronome, réglables depuis le lecteur.
- Détection automatique du clavier MIDI (branchement à chaud) et diagnostic de l'entrée ; le **clavier du Mac**
  peut servir de piano en option.
- Interface macOS native en **Liquid Glass** : barre latérale et barres d'outils en verre, barre de lecture flottante
  (transport, frise des mesures, position), décompte en bulle de verre, fiches de morceau à bandeau dégradé, inspecteur,
  plein écran, mode clair/sombre, VoiceOver, français et anglais.

### Raccourcis

| Action | Raccourci |
|---|---|
| Lecture / pause | Espace |
| Mesure précédente / suivante | ← / → |
| Revenir au début | ⌘← |
| Plus rapide / plus lent / vitesse normale | ⌘+ / ⌘- / ⌘0 |
| Main gauche / main droite | ⌥⌘L / ⌥⌘R |
| Boucle | ⌘B |
| Métronome | ⌥⌘M |
| Noms des notes | ⌥⌘K |
| Réglages du morceau (inspecteur) | ⌥⌘I |
| Nouvelle série (exercices) | ⌥⌘N |
| Importer | ⌘O |
| Exporter la partition en PDF | ⇧⌘E |
| Imprimer la partition | ⌘P |
| Éditeur : mode saisie, valeur pointée | N, . |
| Éditeur : transposer (demi-ton, degré, octave) | ↑ ↓, ⌥↑ ⌥↓, ⌘↑ ⌘↓ |
| Éditeur : doigté, main, supprimer | 1–5 (0), L R, ⌫ |
| Jeu libre | ⇧⌘J |
| Réglages | ⌘, |

## Configuration requise

- macOS 26 Tahoe ou plus récent.
- Un clavier MIDI USB (testé avec un Arturia KeyLab Essential 61). Le clavier du Mac peut servir de piano en option.

## Compilation et tests

Prérequis : Xcode 26 ou plus récent, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
scripts/generate-project.sh                               # (re)génère Pianissimac.xcodeproj à partir de project.yml
open -a Xcode Pianissimac.xcodeproj                           # puis ⌘R
xcodebuild test -scheme Pianissimac -destination 'platform=macOS'
```

Xcode réécrit `Pianissimac/Resources/Localizable.xcstrings` à chaque build ; pour revenir à la version suivie :
`git checkout -- Pianissimac/Resources/Localizable.xcstrings`.

Le cœur de l'application (`Packages/PianissimacKit`, module `PianissimacCore`, Foundation seul) se teste aussi sous Linux :
`scripts/test-core-linux.sh` (Docker, image `swift:6.1-noble`).

## Publication

```sh
TEAM_ID=ABCDE12345 scripts/build-release.sh   # archive Release, export signé Developer ID → dist/Pianissimac.app
scripts/check-offline.sh                      # aucun entitlement ni API réseau, aucune URL inattendue
scripts/make-dmg.sh                           # dist/Pianissimac-<version>.dmg avec un lien vers /Applications
```

Signature, notarisation (`notarytool`) et agrafage (`stapler`) : voir [`docs/RELEASE.md`](docs/RELEASE.md).
Sans `TEAM_ID`, `build-release.sh` produit une app signée *ad hoc*, utile pour un essai local.

## Documentation

- [`docs/SPEC.md`](docs/SPEC.md) — spécification fonctionnelle (§6.4 : décisions validées)
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — architecture technique
- [`docs/PLAN.md`](docs/PLAN.md) — plan de réalisation (phases 0 à 9)
- [`docs/RELEASE.md`](docs/RELEASE.md) — publication
- [`docs/REMOVAL_INVENTORY.md`](docs/REMOVAL_INVENTORY.md) — ce qui a été retiré de l'application d'origine

## Licence et mentions

© Julien Marchadier. Voir [`LICENSE`](LICENSE) et [`ACKNOWLEDGEMENTS.md`](ACKNOWLEDGEMENTS.md), également affichés
dans l'application (Pianissimac › À propos de Pianissimac › Mentions et licences).
