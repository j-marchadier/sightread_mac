# MyPiano — Architecture technique

> Choix techniques pour la réécriture native macOS, établis à partir de `docs/SPEC.md` et des décisions validées
> (§6.4 de la spec). Chaque écart par rapport à la proposition initiale est justifié dans la section **Arbitrages**.

---

## 1. Résumé des choix

| Besoin | Choix retenu | Écart vs proposition |
|---|---|---|
| Langage / UI | Swift 6 (mode de langage 6, concurrence stricte), **SwiftUI**, AppKit ponctuellement (ouverture de fichiers par le Dock, curseur, assertions de veille) ; cible **macOS 14+** | = |
| Organisation | **Un** paquet Swift local `MyPianoKit` exposant 5 bibliothèques (`MyPianoCore`, `MyPianoMIDI`, `MyPianoAudio`, `MyPianoRendering`, `MyPianoLibrary`) + cible App. MVVM avec `@Observable` | 1 paquet multi-cibles au lieu de 4 paquets ; ajout de `MyPianoLibrary` (persistance/import) |
| Projet Xcode | `project.yml` (**XcodeGen**) versionné ; `MyPiano.xcodeproj` généré **et** versionné | ajout |
| Entrée MIDI | **CoreMIDI** (API UMP/MIDI 1.0, notifications de branchement), horodatage des paquets conservé | = |
| Son | **AVAudioEngine + AVAudioUnitSampler**, piano seul. Banque par défaut : **banque General MIDI intégrée à macOS** (aucun fichier à redistribuer) ; banque `.sf2` CC0 embarquée en option | soundfont embarquée devient optionnelle |
| Horloge | **Horloge hôte** (`mach_absolute_time`, base de temps commune à CoreAudio et CoreMIDI) corrigée de la latence de sortie | précisé (cf. Arbitrage A2) |
| Rendu | SwiftUI `Canvas` + `TimelineView(.animation)` ; glyphes SMuFL convertis en `Path` via CoreText et mis en cache | = (Metal non prévu) |
| Partition | Moteur maison, police **Leland** (OFL, déjà présente) ; deux modes : **Simplifiée** (traînes) et **Rythmique** (quantification) | = |
| Parsing | MIDI SMF 0/1 maison ; MusicXML via `XMLParser` ; `.mxl` via un décompresseur ZIP/DEFLATE maison en Swift pur | = (+ ZIP maison) |
| Persistance | **SwiftData** (bibliothèque, réglages par morceau, sessions) derrière un protocole ; `@AppStorage` pour les préférences globales ; fichiers copiés dans Application Support | = |
| Tests | **Swift Testing** ; le Core compile et se teste sous **Linux** (conteneur Swift 6.1) et sous macOS (`xcodebuild test`) | ajout : double cible Linux/macOS |
| CI | Aucune (décision) : Core testé sous Linux par moi, app complète compilée et testée sur ton Mac | — |

---

## 2. Arbitrages

**A1 — Un paquet, plusieurs cibles.** Un seul `Package.swift` garde un graphe de dépendances explicite (chaque cible
déclare ses dépendances, le compilateur interdit les imports non déclarés) sans multiplier les manifestes ni les
versions. Les modules restent séparés et testables.

**A2 — Horloge hôte plutôt que « temps d'échantillon » de l'engine.** Le temps d'échantillon d'`AVAudioEngine`
se réinitialise quand l'engine est arrêté ou reconfiguré (changement de sortie audio, casque branché). L'horloge hôte
est continue et c'est elle qui horodate **à la fois** les paquets CoreMIDI et les tampons audio (`AVAudioTime.hostTime`).
On obtient ainsi une seule base de temps pour : la position de lecture, l'instant exact de chaque touche jouée
(horodatage matériel du paquet MIDI, pas l'instant de traitement) et l'image affichée. La latence de sortie
(`outputNode.presentationLatency` + taille du tampon) est soustraite pour que ce qu'on voit corresponde à ce qu'on entend.

**A3 — Banque de sons système (décision : retenue).** Pour un piano seul, `AVAudioUnitSampler` peut charger la banque
General MIDI fournie par macOS : qualité correcte, **aucun fichier à redistribuer, aucun risque de licence**,
zéro octet dans l'app. Si tu veux un piano plus riche, on embarque une banque `.sf2` sous licence CC0 (ex. *Upright
Piano KW*) ou CC BY (*Salamander*), à fournir car les sites d'hébergement ne sont pas accessibles depuis mon
environnement. Le code est identique (on charge l'une ou l'autre).

**A4 — Pas de Metal.** Quelques centaines de rectangles et de glyphes par image tiennent largement dans `Canvas` à
120 Hz si : la géométrie est précalculée hors du rendu, les glyphes sont des `Path` en cache, le texte est résolu une
fois, et on ne dessine que la fenêtre visible (recherche dichotomique). Metal reste une option si les mesures de la
Phase 6 le justifient.

**A5 — Core indépendant d'Apple.** `MyPianoCore` n'importe que Foundation (et `FoundationXML` sous Linux). Cela
permet de compiler et tester le Core dans mon environnement (Linux, Swift 6.1 en conteneur), donc de livrer un Core
vérifié avant même qu'il passe par Xcode. Les modules qui touchent au matériel ou à l'UI ne compilent que sur macOS
(ta machine).

**A6 — SwiftData derrière un protocole.** SwiftData sur macOS 14 a encore des angles vifs (migrations, requêtes
complexes). Les vues ne parlent qu'à un `LibraryStore` ; les réglages par morceau sont stockés comme un `Codable`
sérialisé (pas de migration de schéma à chaque nouveau réglage). Si SwiftData pose problème, on peut le remplacer sans
toucher aux vues.

**A7 — Notation rythmique : espacement proportionnel au temps.** La partition rythmique défile horizontalement avec
une abscisse proportionnelle au temps (comme le mode simplifié). Avantages : le curseur de lecture avance à vitesse
constante, les deux modes partagent la même géométrie et la même synchronisation. Contrepartie : passages denses plus
serrés → réglage de zoom horizontal et espacement minimal entre têtes de notes.

---

## 3. Arborescence du dépôt (cible, après Phase 3)

```
MyPiano/                          Cible App (SwiftUI)
  App/                            MyPianoApp, AppDelegate (Dock, Ouvrir avec), commandes de menu
  Features/
    Library/                      Barre latérale, liste/grille, détail, recherche, import
    Player/                       Fenêtre de jeu, barre d'outils, inspecteur, bilan de session
    FreePlay/
    Exercises/                    Lecture de notes, Phrases
    Settings/                     Scène Réglages (MIDI, Audio, Affichage, Pratique)
    Onboarding/                   Bienvenue au premier lancement
  Resources/
    Assets.xcassets               Icône, couleurs nommées (clair/sombre)
    Localizable.xcstrings         FR + EN
    BuiltinSongs/                 Fichiers MIDI intégrés + catalog.json
    Fonts/Leland.otf, OFL.txt
  Info.plist, MyPiano.entitlements
Packages/MyPianoKit/
  Package.swift
  Sources/
    MyPianoCore/
      Model/                      Song, Note, Track, Measure, TempoMap, TimeSignature, KeySignature, Hand
      Theory/                     Pitch, orthographe, armures, transposition, noms de notes (Do fixe / alphabétique)
      Parsing/MIDI/               Lecteur SMF, écriture SMF (enregistrements, tests)
      Parsing/MusicXML/           Parser MusicXML, lecteur .mxl
      Parsing/Zip/                Lecteur ZIP + décompresseur DEFLATE
      Hands/                      Inférence des mains, séparation d'une piste unique
      Notation/                   Quantification, voix, silences, liaisons, ligatures, altérations
      Layout/                     Géométrie : clavier, notes qui tombent, portées (unités abstraites)
      Playback/                   Transport, mode attente, boucle, décompte, métronome
      Scoring/                    Jugement des notes, statistiques, score combiné
      Exercises/                  Générateurs « Lecture de notes » et « Phrases »
      Library/                    Métadonnées, heuristique de difficulté, catalogue intégré
      Platform/                   Horloge, verrou, abstractions des sorties (ports)
    MyPianoMIDI/                  CoreMIDI : sources, connexion, décodage, horodatage
    MyPianoAudio/                 AVAudioEngine : samplers, métronome, latence
    MyPianoRendering/             Canvas : notes qui tombent, clavier, partitions, glyphes SMuFL
    MyPianoLibrary/               SwiftData, import, dossiers surveillés, bookmarks
  Tests/
    MyPianoCoreTests/             + Fixtures/ (17 MIDI, MusicXML de test, attendus)
    MyPianoLibraryTests/          (macOS)
project.yml                       Spécification XcodeGen
MyPiano.xcodeproj                 Généré par XcodeGen (versionné)
scripts/                          test-core-linux.sh, generate-project.sh, build-release.sh, make-dmg.sh
docs/                             SPEC, ARCHITECTURE, PLAN, RELEASE
```

### Graphe de dépendances

```
               MyPianoCore  (Foundation seulement — Linux + macOS)
              /     |      \          \
     MyPianoMIDI MyPianoAudio MyPianoRendering MyPianoLibrary
     (CoreMIDI)  (AVFAudio)   (SwiftUI, CoreText) (SwiftData)
              \     |      /          /
                    App (SwiftUI)
```
Aucun module de deuxième niveau ne dépend d'un autre : ils communiquent par les **protocoles** définis dans le Core
(`NoteInputSource`, `NoteOutput`, `HostClock`), et c'est l'App qui les assemble.

---

## 4. Modèle de données (Core)

Types valeur immuables, `Sendable`, `Codable` quand utile.

```swift
struct Song {
    var tracks: [Track]                  // id = index
    var notes: [Note]                    // triées par (tick, pitch)
    var measures: [Measure]
    var tempoMap: TempoMap               // ticks ↔ secondes, changements de tempo
    var timeSignatures: [TimeSignatureChange]
    var keySignatures: [KeySignatureChange]   // la 1re sert d'armure principale ; absente = inconnue
    var ticksPerQuarter: Int
    var notation: NotationHints?         // présent pour MusicXML (figures, portée, voix, ligatures explicites)
    var duration: TimeInterval           // fin de la dernière note
}
struct Note { let id: Int; let pitch: UInt8; let track: Int; let startTick: Int; let durationTicks: Int
              let start: TimeInterval; let duration: TimeInterval; let velocity: UInt8; let measureIndex: Int
              var staffHint: Staff? }    // MusicXML : portée explicite
struct Track { var name: String?; var program: UInt8?; var channel: UInt8?; var isPercussion: Bool }
```

Différences volontaires avec l'original (cf. SPEC §6) : **ticks conservés** à côté des secondes (indispensable pour
quantifier proprement), identifiant stable par note, armure avec changements, plusieurs pistes par main.

Réglages par morceau (`SongSettings`, `Codable`) : mains actives, attribution piste → main (ensemble de pistes par
main, ou séparation à un point de partage), mode (Apprendre / Attendre / Écouter), vitesse, boucle, métronome,
décompte, transposition, visualisation (Notes qui tombent / Partition simplifiée / Partition rythmique), noms de
notes, notes colorées, armure forcée, plage du clavier (88 touches / tessiture), « ne pas jouer ma partie », sons de
piste.

Préférences globales (`@AppStorage`) : source MIDI préférée, nommage des notes (défaut **Do Ré Mi**, aussi en anglais
si l'utilisateur le choisit), clavier du Mac comme piano (désactivé par défaut), décalage de latence, volume du
morceau, volume du retour sonore, fenêtres de jugement.

---

## 5. Moteur de lecture

### 5.1 Découpage

```
                      ┌───────────────────────────────┐
  CoreMIDI ──events──▶│  PracticeEngine (Core)        │──NoteOutput──▶ AudioEngine (samplers)
  clavier Mac/souris ▶│  • TransportCore (pur)        │──métronome───▶
                      │  • Judge (scoring)            │
                      │  driver : thread QoS élevé,   │──snapshot────▶ Rendu (TimelineView/Canvas)
                      │  tick 1 ms, verrou            │──état agrégé─▶ PlayerViewModel (@MainActor, ~30 Hz)
                      └───────────────────────────────┘
```

- **`TransportCore`** : machine à états **pure et déterministe** (`struct`). Entrées : `advance(to: hostTime)`,
  `noteOn(pitch, at: hostTime)`, `noteOff`, `seek`, `play`, `pause`, changements de réglages. Sorties : liste
  d'événements (`play(note)`, `stop(note)`, `click(accent)`, `judged(note, grade)`, `missed(note)`, `wrongKey`,
  `loopWrapped`, `countdownTick`, `ended`). Aucune dépendance au temps réel → testable exhaustivement avec une horloge
  simulée. Reprend toute la sémantique de SPEC §3.1–3.7, avec les corrections B1–B8.
- **`PracticeEngine`** : enveloppe thread-safe. Un thread dédié (QoS `userInteractive`) appelle `advance` toutes les
  ~1 ms et transmet les événements au son ; les entrées MIDI y sont injectées avec leur **horodatage matériel**.
  L'état publié pour le rendu est un instantané copié sous verrou (`NSLock`, disponible Linux/macOS).
- **`PlayerViewModel`** (`@Observable @MainActor`) : expose à SwiftUI l'état agrégé (lecture, mesure, statistiques,
  décompte) à fréquence réduite ; les vues de rendu lisent directement l'instantané à chaque image.

### 5.2 Temps

```
tempsMorceau(h) = ancreMorceau + (h − ancreHôte − latenceSortie) × vitesse        (pendant la lecture)
```
L'ancre est reposée à chaque play/seek/changement de vitesse. En mode attente, l'avance est bornée au début de la
prochaine note non jouée de la main active. La même fonction sert au rendu (instant de présentation de l'image) et au
jugement (instant du paquet MIDI) → le jugement ne dépend plus de la fréquence de la boucle.

### 5.3 Modes

- **Apprendre** : le morceau avance ; les notes jouées sont jugées (Parfait < 50 ms, Bien < 300 ms en temps réel).
- **Attendre** : le morceau s'arrête sur chaque note de la main active jusqu'à ce qu'elle soit jouée (tous les sons
  d'un accord requis, notes des autres mains non acceptées).
- **Écouter** : toutes les mains affichées, rien n'est jugé.
- Option **« Ne pas jouer ma partie »** (ancien `skipMissedNotes`) : les notes de la main active ne sonnent que si
  l'utilisateur les joue.
- Score combiné conservé (SPEC §3.3), avec la durée tenue comptée **en dixièmes de seconde** au lieu de « par tick ».

---

## 6. MIDI (`MyPianoMIDI`)

- `MIDIClientCreateWithBlock` : notifications d'ajout/retrait de sources → liste observable, **reconnexion
  automatique** à la source mémorisée (identifiée par `kMIDIPropertyUniqueID`, nom en secours).
- `MIDIInputPortCreateWithProtocol(.1_0)` : réception en UMP ; décodage note on/off (vélocité 0 = off), **CC64
  sustain**, horodatages convertis en temps hôte (0 = « maintenant »).
- Par défaut : écoute de toutes les sources **sauf** les ports de bouclage et les ports de contrôle DAW. Les claviers
  **Arturia KeyLab Essential 61** expose deux ports (`KeyLab Essential 61 MIDI` et `KeyLab Essential 61 DAW`) : seul le port MIDI est retenu. Choix manuel
  possible dans Réglages > Clavier MIDI.
- État de connexion (`déconnecté`, `connecté : <nom>`, `plusieurs sources`) affiché dans la barre d'outils et la
  barre latérale.
- Sortie MIDI vers un instrument externe : hors périmètre (piano seul, son interne) — à rouvrir si besoin.
- Pas d'entitlement particulier : CoreMIDI fonctionne dans le sandbox (le serveur MIDI système gère l'USB).

## 7. Audio (`MyPianoAudio`)

- Graphe : `samplerMorceau` + `samplerUtilisateur` (piano) + `métronome` (`AVAudioSourceNode` qui synthétise un clic,
  aucun fichier) + son d'erreur synthétisé → `mainMixer` → sortie.
- Deux samplers pour que la même note jouée par le morceau et par l'utilisateur ne se coupent pas mutuellement ;
  volumes indépendants. Sustain appliqué au sampler utilisateur (et aux CC64 du fichier pour le morceau).
- Latence : tampon de sortie demandé à **128 trames** (≈ 2,7 ms à 48 kHz) ; la note est déclenchée depuis le
  thread de réception MIDI. Budget visé : USB (~1 ms) + traitement (< 1 ms) + tampon (2,7 ms) + latence du
  périphérique (2–5 ms) **< 10 ms**. Mesure : horodatage du paquet MIDI vs horodatage de rendu, journalisé avec
  `os_signpost`, valeur affichée dans Réglages > Audio.
- Reconfiguration automatique sur changement de périphérique de sortie (`AVAudioEngineConfigurationChange`).

## 8. Rendu (`MyPianoRendering`)

- `TimelineView(.animation)` cadencée par l'écran (60/120 Hz ProMotion) ; `Canvas` en mode
  `rendersAsynchronously`. Géométrie calculée dans `MyPianoCore/Layout` (pure, testée) : couloirs du clavier,
  positions des notes, géométrie des portées en **unités d'interligne**.
- **Notes qui tombent** : clavier 88 touches ou tessiture du morceau, couleurs par main (palette nommée, clair/sombre,
  variante daltonisme), touches jouées mises en évidence, **erreurs signalées** (touche rouge brève), noms de notes
  optionnels, barres de mesure, boucle.
- **Partition simplifiée** : version améliorée du mode traînes (barres de mesure, altérations correctes avec bécarres,
  portée par main, chiffrage multi-chiffres, coloration réussies/manquées).
- **Partition rythmique** : têtes (ronde, blanche, noire), hampes, crochets, ligatures de base, points, silences,
  liaisons de prolongation, altérations avec état par mesure, barres de mesure, armure, chiffrage, curseur, coloration
  réussies/manquées. Glyphes Leland convertis en `CGPath` via CoreText (ancrages de hampe déduits des boîtes
  englobantes des glyphes), mis en cache par taille.
- Objectif : 120 images/s sur un écran ProMotion, mesuré avec Instruments ; budget < 4 ms CPU par image.

### Pipeline de notation (Core/Notation)

```
MusicXML ──(figures, voix, portées explicites)──────────────┐
                                                             ▼
MIDI ─▶ Mains/portées ─▶ Quantification ─▶ Voix & accords ─▶ Mesures : silences, découpage aux barres et aux temps
        (piste ou        (grille par temps :  (1 voix/portée,   (liaisons), figures + points ─▶ Ligatures par temps
         point de        1/4…1/32 + triolets,  chevauchements    (6/8 : par noire pointée) ─▶ Orthographe et
         partage)        erreur minimale,     tronqués)          altérations par mesure ─▶ ScoreModel ─▶ ScoreLayout
                         en ticks)
```
La quantification n'altère pas le jugement (il se fait toujours sur les temps réels des notes) : elle ne sert qu'à
l'affichage.

## 9. Bibliothèque et persistance (`MyPianoLibrary`)

- SwiftData : `SongRecord` (id, titre, compositeur, difficulté, source intégré/importé/surveillé, chemin relatif,
  empreinte SHA-256, durée, nb pistes, date d'ajout, dernière ouverture, favori, réglages `Data`),
  `PracticeSessionRecord` (date, durée, mode, vitesse, mains, précision, compteurs, meilleure série, plage),
  `WatchedFolderRecord` (bookmark security-scoped).
- Morceaux intégrés : dans le bundle + `catalog.json` (titre, compositeur, licence, source), insérés au premier
  lancement avec des identifiants stables.
- Import : copie dans `~/Library/Containers/<bundle>/Data/Library/Application Support/MyPiano/Songs/<uuid>.<ext>`,
  dédoublonnage par empreinte, parsing de validation, erreurs explicites.
- Dossier surveillé : bookmark security-scoped, `FSEvents`/`DispatchSource`, import automatique des nouveaux fichiers.

## 10. Outillage et tests

- **Génération du projet** : `scripts/generate-project.sh` (XcodeGen). Je peux générer le projet depuis mon
  environnement Linux (XcodeGen y compile), toi depuis ton Mac (`brew install xcodegen`).
- **Tests Core sous Linux** : `scripts/test-core-linux.sh` lance `swift test` dans le conteneur officiel Swift 6.1.
- **Tests complets sous macOS** : `xcodebuild test -scheme MyPiano`.
- **Pas de CI** (décision) : à chaque phase, je fournis la commande à lancer sur ton Mac (`xcodebuild test -scheme MyPiano`) ; le code dépendant d'Apple est gardé mince pour limiter les surprises.
- Couverture : objectif ≥ 90 % des lignes sur `Playback`, `Scoring`, `Parsing` ; tests de géométrie pour `Layout`.

## 11. Sécurité, confidentialité, distribution

- App Sandbox : `app-sandbox`, `files.user-selected.read-only`, `files.bookmarks.app-scope`. **Aucun entitlement
  réseau** : l'app est techniquement incapable d'appeler un service externe.
- Hardened Runtime activé ; signature et notarisation par toi (procédure dans `docs/RELEASE.md`, Phase 9).
- Types de documents déclarés : `.mid`, `.midi` (`public.midi-audio`), `.musicxml`, `.xml` (MusicXML),
  `.mxl` (UTI déclaré `com.recordare.musicxml.compressed`, importé).
- Localisation : String Catalog FR (langue de développement) + EN.

## 12. Ce qui n'est pas repris

Voir SPEC §5 : tout le marketing, le tracking, les fonctions web, l'export audio, le partage par URL, les instruments
autres que le piano, les phrases « folk irlandais » d'origine (remplacées par des générateurs procéduraux), le son
d'erreur et les images de touches d'origine (remplacés par du son synthétisé et du dessin vectoriel).
