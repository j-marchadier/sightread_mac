# MyPiano

**MyPiano** est une application macOS native pour apprendre le piano avec un clavier MIDI.
Branchez votre clavier, choisissez un morceau, et jouez en suivant les notes qui tombent ou la partition :
MyPiano écoute ce que vous jouez, vous attend si vous le souhaitez et mesure vos progrès.

> 🚧 Application en cours de développement. Captures d'écran à venir.

## Fonctionnalités

- **Notes qui tombent** synchronisées avec un clavier 88 touches (ou réduit à la tessiture du morceau), couleurs par main.
- **Partition** défilante : notation rythmique ou mode simplifié, armure, chiffrage, altérations, coloration des notes réussies et manquées.
- **Mode attente** : le morceau s'arrête jusqu'à ce que vous jouiez la bonne note.
- **Mode écoute**, **vitesse** réglable (10–200 %), **boucle A-B** sur des mesures, **métronome**, **décompte**, **transposition**.
- **Main gauche, main droite ou les deux**, avec attribution automatique des pistes.
- **Statistiques** de précision et historique de progression par morceau.
- **Exercices** : lecture de notes et phrases générées à l'infini.
- **Jeu libre** au clavier.
- **Bibliothèque** intégrée et import de vos fichiers **MIDI** (`.mid`, `.midi`) et **MusicXML** (`.musicxml`, `.xml`, `.mxl`) : menu, glisser-déposer, « Ouvrir avec », dossier surveillé.
- Détection automatique du clavier MIDI (branchement à chaud), pédale de sustain, faible latence.
- Interface macOS native : barre latérale, barre d'outils, inspecteur, plein écran, mode clair/sombre, VoiceOver, français et anglais.
- **100 % hors ligne**, aucune collecte de données.

## Configuration requise

- macOS 14 Sonoma ou plus récent.
- Un clavier MIDI USB (testé avec un Arturia KeyLab Essential 61). Le clavier du Mac peut servir de piano en option.

## Compilation

Prérequis : Xcode 16 ou plus récent, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
scripts/generate-project.sh      # (re)génère MyPiano.xcodeproj à partir de project.yml
open MyPiano.xcodeproj           # puis ⌘R
xcodebuild test -scheme MyPiano  # tests
```

Le cœur de l'application (`Packages/MyPianoKit`, module `MyPianoCore`) se compile et se teste aussi hors de Xcode :
`swift test --package-path Packages/MyPianoKit` (ou `scripts/test-core-linux.sh` sous Linux).

## Documentation

- [`docs/SPEC.md`](docs/SPEC.md) — spécification fonctionnelle
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — architecture technique
- [`docs/PLAN.md`](docs/PLAN.md) — plan de réalisation

## Licence et mentions

Voir [`LICENSE`](LICENSE) et [`ACKNOWLEDGEMENTS.md`](ACKNOWLEDGEMENTS.md).
