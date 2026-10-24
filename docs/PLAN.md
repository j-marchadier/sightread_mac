# MyPiano — Plan de réalisation (phases 0 à 9)

> Chaque tâche liste les fichiers créés ou modifiés, un critère « terminé » vérifiable et les risques.
> Un commit (Conventional Commits, en anglais) par étape logique ; résumé à la fin de chaque phase.
>
> Légende de vérification : 🐧 vérifiable dans mon environnement (Linux, Swift 6.1) · 🍎 nécessite macOS
> (ton Mac) · 👤 vérification manuelle par toi (clavier Arturia, écoute, visuel).

## État d'avancement

| Phase | Contenu | État |
|---|---|---|
| 0 | Spécification fonctionnelle de l'application d'origine (`docs/SPEC.md`) | ✅ Terminée |
| 1 | Architecture technique (`docs/ARCHITECTURE.md`) et décisions (SPEC §6.4) | ✅ Terminée |
| 2 | Nettoyage du dépôt | ✅ Terminée |
| 3 | Projet Xcode et Core | ✅ Terminée |
| 4 | MIDI et audio | ✅ Terminée |
| 5 | Moteur de lecture | ✅ Terminée |
| 6 | Rendu | ✅ Terminée |
| 7 | Interface Apple | ✅ Terminée |
| 8 | Import de partitions | ✅ Terminée |
| 9 | Finitions et distribution | ✅ Terminée |

---

## Phase 2 — Nettoyage du dépôt

| # | Tâche | Fichiers | Terminé quand | Risques |
|---|---|---|---|---|
| 2.1 | Déplacer l'app web dans `reference/web/` (lecture seule) | `src/`, `public/`, `scripts/`, `tests/`, `package.json`, `bun.lockb`, configs → `reference/web/` | `git mv` effectué, plus rien de l'app web à la racine ; historique conservé | Aucun |
| 2.2 | Retirer les fichiers propres à l'ancien produit à la racine | supprimer `.github/workflows/validate.yml`, config du robot de dépendances, config d'hébergement, `CONTRIBUTING.md`, `.prettierrc`, `postcss.config.js`, `.gitattributes` si inutile ; `.gitignore` réécrit pour Xcode/SwiftPM | `ls` racine = `LICENSE`, `README.md`, `ACKNOWLEDGEMENTS.md`, `docs/`, `reference/` | Aucun |
| 2.3 | Inventaire de ce qui sera retiré du produit final (tracking, identité, marketing, web) | `docs/REMOVAL_INVENTORY.md` (repris de SPEC §5, avec chemins) | Liste exhaustive vérifiée par recherche (`scripts/check-legacy-traces.sh`) | Oubli d'une occurrence → recherche automatisée réutilisée en Phase 9 |
| 2.4 | Nouveau `README.md` (MyPiano, description, fonctionnalités, build, captures à venir) | `README.md` | Aucune mention de l'ancien produit | — |
| 2.5 | `ACKNOWLEDGEMENTS.md` : inspiration de l'original (GPL-3.0), Leland (OFL 1.1, texte joint), morceaux intégrés (licence + source + auteur par morceau), banque de sons retenue | `ACKNOWLEDGEMENTS.md`, `LICENSE` conservé | Chaque asset réutilisé y figure avec sa licence ; assets à risque signalés | Licence de *Swan Lake* non vérifiable (URL dupliquée) → je propose de l'**écarter** de la bibliothèque intégrée sauf si tu retrouves la source |

**Livrable :** dépôt propre, documentation d'identité MyPiano. 🐧

---

## Phase 3 — Projet Xcode et Core

| # | Tâche | Fichiers | Terminé quand | Risques |
|---|---|---|---|---|
| 3.1 | Paquet `MyPianoKit` (5 bibliothèques + tests), réglages Swift 6 stricts | `Packages/MyPianoKit/Package.swift`, squelettes de modules | `swift build` OK 🐧 ; build macOS OK 🍎 | Différences Foundation Linux/macOS → `#if canImport` limités au Core |
| 3.2 | Projet Xcode via XcodeGen : app `MyPiano`, bundle id `fr.jmarchadier.MyPiano`, sandbox + hardened runtime, entitlements, Info.plist (types de documents), schéma avec tests | `project.yml`, `MyPiano.xcodeproj`, `MyPiano/Info.plist`, `MyPiano/MyPiano.entitlements`, `MyPiano/App/MyPianoApp.swift` | Le projet s'ouvre et l'app vide se lance 🍎👤 | Projet généré sous Linux : à valider sur ton Mac au premier lancement |
| 3.3 | Scripts | `scripts/test-core-linux.sh`, `scripts/generate-project.sh` | Un seul appel lance les tests du Core 🐧 | — |
| 3.4 | ~~CI macOS~~ — **abandonnée (décision)** : la partie Apple est compilée et testée sur ton Mac | — | — | Erreurs de compilation Apple découvertes plus tard → je limite le code Apple au strict nécessaire et je te donne à chaque phase la commande de vérification |
| 3.5 | Modèle : `Song`, `Note`, `Track`, `Measure`, `TempoMap`, `TimeSignature`, `KeySignature` | `MyPianoCore/Model/*` | Tests de conversion ticks ↔ secondes avec changements de tempo 🐧 | — |
| 3.6 | Théorie : hauteurs, octaves, orthographe calculée à partir de l'armure (dièses, bémols, bécarres, doubles), transposition d'armure, noms Do fixe / alphabétique, FR/EN | `MyPianoCore/Theory/*` | Tests sur les 15 armures, transpositions −12…+12 🐧 | Cas limites (Mi♯, Do♭, armures à 7 altérations) |
| 3.7 | Lecteur MIDI SMF 0/1 : en-têtes, VLQ, running status, méta (tempo, chiffrage, armure, nom de piste), note on/off, CC64, programme, canal ; type 0 éclaté par canal ; erreurs typées | `MyPianoCore/Parsing/MIDI/MIDIFileReader.swift`, `MIDIError.swift` | Les 17 fichiers se lisent ; nombre de notes par piste = référence (cf. ci-dessous) 🐧 | Fichiers malformés réels (longueurs fausses) → mode tolérant + tests de fichiers corrompus |
| 3.8 | Mesures, armure principale (règle « Do = inconnu »), chiffrage principal, durée | `MyPianoCore/Parsing/MIDI/SongBuilder.swift` | Pour les 16 fichiers à fiche de référence : nb de mesures et chiffrage exacts, durée partition ± 0,5 s, armure si ≠ Do 🐧 | Les attendus d'origine viennent de MuseScore : je les **régénère** comme fixtures à nous (valeurs factuelles) |
| 3.9 | Écriture SMF (aller-retour, futurs enregistrements) | `MyPianoCore/Parsing/MIDI/MIDIFileWriter.swift` | Aller-retour sur les 17 fichiers : mêmes notes à 1 tick près 🐧 | — |
| 3.10 | Lecteur ZIP + DEFLATE (pour `.mxl`), `META-INF/container.xml` | `MyPianoCore/Parsing/Zip/*` | Tests sur archives générées (stockées et compressées) et vecteurs DEFLATE connus 🐧 | Implémentation DEFLATE : tests exhaustifs (blocs stockés, Huffman fixe/dynamique) |
| 3.11 | Parser MusicXML (partwise ; timewise en option) : divisions variables, `<staff>`, voix, accords, `<backup>/<forward>`, liaisons, reprises + voltas, tempo, armures, chiffrages, figures/points/ligatures conservées dans `NotationHints` | `MyPianoCore/Parsing/MusicXML/*` | Tests sur un jeu de fichiers MusicXML **écrits pour le projet** (échelles, accords, reprises, liaisons, triolets, deux portées, changement de mesure) + `.mxl` 🐧 | Aucun MusicXML dans le dépôt d'origine → je crée les fixtures ; tu pourras ajouter des exports MuseScore réels |
| 3.12 | Attribution des mains : règle par noms, pistes piano, hauteur moyenne ; séparation d'une piste unique au point de partage (Do4 par défaut) ; MusicXML par portée | `MyPianoCore/Hands/*` | Tests : 13 fichiers → MG/MD attendues ; 4 fichiers mono-piste → séparation 🐧 | Séparation heuristique imparfaite → modifiable dans l'UI (Phase 8) |
| 3.13 | Catalogue intégré : `catalog.json` (titre, compositeur, licence, source) + copie des MIDI retenus | `MyPiano/Resources/BuiltinSongs/*` | Chaque entrée se parse ; titres/compositeurs corrigés 🐧 | — |

**Livrable :** projet Xcode ouvrable, Core testé (parsers, modèle, théorie, mains). 🐧 + 🍎

---

## Phase 4 — MIDI et audio

| # | Tâche | Fichiers | Terminé quand | Risques |
|---|---|---|---|---|
| 4.1 | Protocoles Core : `NoteInputSource`, `NoteOutput`, `HostClock` ; événement `InputEvent { noteOn/noteOff/sustain, pitch, velocity, hostTime }` | `MyPianoCore/Platform/*` | Compilé et utilisé par un faux en test 🐧 | — |
| 4.2 | Service CoreMIDI : liste observable des sources, filtre (bouclage, port DAW du KeyLab Essential 61), connexion, notifications de branchement, reconnexion à la source mémorisée, décodage UMP, horodatage | `MyPianoMIDI/MIDIService.swift`, `MIDISource.swift`, `UMPDecoder.swift` | Décodeur testé 🍎 ; avec l'Arturia : détection au lancement, débranchement/rebranchement sans relancer, notes et pédale reçues 👤 | Noms de ports du KeyLab Essential 61 à confirmer sur ta machine (fenêtre de diagnostic 4.6) |
| 4.3 | Moteur audio : engine, sampler morceau + sampler utilisateur, banque piano (système par défaut, `.sf2` optionnelle), volumes, sustain, reconfiguration sur changement de sortie | `MyPianoAudio/AudioEngine.swift`, `PianoSampler.swift` | Son du piano à l'appui d'une touche 👤 ; changement de casque sans coupure définitive 👤 | Qualité de la banque système jugée insuffisante → `.sf2` CC0 à fournir |
| 4.4 | Métronome et son d'erreur synthétisés (`AVAudioSourceNode`), accent distinct | `MyPianoAudio/ClickSynth.swift` | Clic audible, accent différent 👤 ; générateur testé (enveloppe) 🍎 | — |
| 4.5 | Latence : tampon 128 trames, déclenchement depuis le thread MIDI, mesure `os_signpost`, affichage de l'estimation | `MyPianoAudio/LatencyMonitor.swift` | Latence mesurée **< 10 ms** sur ton Mac avec l'Arturia (journal) 👤 | Périphérique Bluetooth ou sortie HDMI : latence matérielle hors de notre contrôle → affichée et compensée visuellement |
| 4.6 | Mini-app de diagnostic (fenêtre temporaire « Clavier ») : état de connexion, dernières notes, latence | `MyPiano/Features/Settings/MIDIDiagnosticsView.swift` | Utilisable avant le moteur de lecture 👤 | — |

**Livrable :** clavier détecté automatiquement, son du piano au toucher, latence mesurée. 🍎👤

---

## Phase 5 — Moteur de lecture

| # | Tâche | Fichiers | Terminé quand | Risques |
|---|---|---|---|---|
| 5.1 | `TransportCore` : états, play/pause/stop/seek, temps morceau, vitesse bornée 10–200 %, navigation par mesure, fin de morceau | `MyPianoCore/Playback/TransportCore.swift` | Tests avec horloge simulée (avance, pause, seek, fin, changement de vitesse en cours) 🐧 | — |
| 5.2 | Boucle A-B (recalage aux mesures, retour avec décompte), décompte (anacrouse, chiffrage actif), métronome (changements de chiffrage) | `Playback/Loop.swift`, `Countdown.swift`, `Metronome.swift` | Tests reprenant SPEC §3.5–3.7 + corrections B2, B8 🐧 | — |
| 5.3 | Mains actives, plusieurs pistes par main, modes Apprendre / Attendre / Écouter, « Ne pas jouer ma partie », transposition | `Playback/HandFilter.swift`, `PracticeMode.swift` | Tests : accords en mode attente, refus de l'autre main (B3), notes répétées (B4) 🐧 | — |
| 5.4 | Jugement et statistiques : Parfait/Bien/Manqué/Erreur, série, précision, score combiné (durée tenue en temps), jugement sur l'horodatage matériel | `MyPianoCore/Scoring/*` | Tests de fenêtres aux bornes (49/50/299/300 ms, à 50 % et 200 % de vitesse) 🐧 | — |
| 5.5 | `PracticeEngine` (thread 1 ms, verrou, instantanés) + bilan de session | `Playback/PracticeEngine.swift`, `SessionSummary.swift` | Test de concurrence (entrées simultanées pendant l'avance) 🐧 ; compile en Swift 6 strict 🍎 | Thread temps réel : pas d'allocation dans la boucle chaude → revue + Instruments |
| 5.6 | `PlayerViewModel` (`@Observable @MainActor`) branché sur MIDI + audio | `MyPiano/Features/Player/PlayerViewModel.swift` | Lecture d'un morceau intégré avec son + clavier, sans UI finale 👤 | — |

**Livrable :** moteur complet, couverture ≥ 90 % sur Playback/Scoring. 🐧

---

## Phase 6 — Rendu

| # | Tâche | Fichiers | Terminé quand | Risques |
|---|---|---|---|---|
| 6.1 | Géométrie du clavier (88 touches / tessiture), couloirs, notes qui tombent (fenêtre visible par dichotomie) | `MyPianoCore/Layout/KeyboardLayout.swift`, `FallingNotesLayout.swift` | Tests de géométrie (positions des noires, bornes) 🐧 | — |
| 6.2 | Vue notes qui tombent + clavier : couleurs par main, touches jouées, erreurs, noms de notes, mesures, boucle, clic souris sur le clavier, défilement trackpad avec inertie | `MyPianoRendering/FallingNotes/*`, `Keyboard/*` | 120 images/s sur ProMotion (Instruments), < 4 ms CPU/image sur Clair de Lune 👤🍎 | Coût du texte dans `Canvas` → texte résolu et mis en cache |
| 6.3 | Glyphes SMuFL : chargement de Leland, conversion en `Path`, cache, ancrages déduits des boîtes | `MyPianoRendering/Glyphs/*` | Planche de test de tous les glyphes utilisés (capture) 👤 | Sans le fichier de métadonnées SMuFL, ancrages approximés → ajustés à l'œil |
| 6.4 | Partition simplifiée améliorée : grand-portée, clés, armure, chiffrage multi-chiffres, barres de mesure, altérations (♯ ♭ ♮) avec état par mesure, traînes, ligne de jeu, réussies/manquées, touches jouées | `MyPianoCore/Layout/StaffLayout.swift`, `MyPianoRendering/Sheet/SimplifiedSheetView.swift` | Tests de positions verticales (toutes les notes 21…108 sur les deux clés, 15 armures) 🐧 ; rendu validé 👤 | — |
| 6.5 | Pipeline de notation : quantification (grille + triolets, en ticks), voix/accords, silences, découpage aux barres et aux temps, figures et points, ligatures par temps, orthographe | `MyPianoCore/Notation/*` | Tests sur motifs connus (gammes en croches, rythmes pointés, 6/8, triolets, liaisons de barre) ; MusicXML rendu sans quantification 🐧 | **Risque principal du projet** : la quantification de MIDI joués « à la main » peut produire des rythmes illisibles → réglage de grille, repli automatique sur le mode simplifié si l'erreur de quantification dépasse un seuil |
| 6.6 | Partition rythmique : têtes, hampes (sens par position), crochets, ligatures, points, silences, liaisons, curseur, coloration | `MyPianoCore/Layout/ScoreLayout.swift`, `MyPianoRendering/Sheet/RhythmicSheetView.swift` | Rendu des 17 morceaux intégrés sans chevauchement grossier (captures) 👤 ; 60 images/s minimum 🍎 | Collisions dans les passages denses → zoom horizontal, espacement minimal |

**Livrable :** trois visualisations synchronisées avec le moteur. 🐧🍎👤

---

## Phase 7 — Interface Apple

| # | Tâche | Fichiers | Terminé quand | Risques |
|---|---|---|---|---|
| 7.1 | Fenêtre principale `NavigationSplitView` : barre latérale (Bibliothèque, Récents, Favoris, Importés, Exercices, Jeu libre), liste/grille, détail (aperçu animé, métadonnées, progression, Jouer) | `MyPiano/Features/Library/*` | Navigation complète au clavier et à la souris 👤 | — |
| 7.2 | Recherche (`.searchable` sur titre et compositeur), tri (titre, compositeur, durée, difficulté, dernière ouverture), favoris, progression par morceau | idem + `MyPianoLibrary/Queries.swift` | Tests de requêtes 🍎 | — |
| 7.3 | Fenêtre de jeu : barre d'outils native (lecture, vitesse, mains, mode, boucle, visualisation, métronome), inspecteur repliable (réglages + stats), frise des mesures avec plage A-B, plein écran natif, bilan de fin de session | `MyPiano/Features/Player/*` | Toutes les fonctions SPEC §1.3 (hors celles supprimées) accessibles 👤 | Densité de la barre d'outils → personnalisable (`.toolbar(id:)`) |
| 7.4 | Barre de menus complète (Fichier, Édition, Lecture, Présentation, Fenêtre, Aide) et raccourcis : espace, ⌘O, ⌘,, ⌘←/⌘→ (mesure), ⌘L (boucle), ⌘W, ⌃⌘F, etc. | `MyPiano/App/Commands/*` | Chaque action du lecteur a un élément de menu et un raccourci 👤 | Conflits avec le clavier du Mac comme piano → raccourcis sans modificateur désactivés quand l'option est active |
| 7.5 | Scène Réglages : Clavier MIDI (source, état, test), Audio (volumes, latence, banque), Affichage (noms de notes Do Ré Mi / C D E, couleurs, clavier 88/tessiture), Pratique (fenêtres de jugement, décompte, mode attente par défaut, clavier du Mac) | `MyPiano/Features/Settings/*` | Réglages persistés et appliqués à chaud 👤 | — |
| 7.6 | Jeu libre : clavier, notes montantes (pas d'enregistrement, décision) | `MyPiano/Features/FreePlay/*` | Jeu libre fonctionnel 👤 | — |
| 7.7 | Exercices : **Lecture de notes** (clé, armure, tessiture, nombre de notes, attente, chrono, notes/min, historique) et **Phrases** (générateur procédural : progressions d'accords, motifs rythmiques par niveau 0–3, clé Sol/Fa/grand-portée) | `MyPianoCore/Exercises/*`, `MyPiano/Features/Exercises/*` | Générateurs testés (tessiture, gamme, durées) 🐧 ; exercices jouables 👤 | — |
| 7.8 | Apparence : clair/sombre, matériaux, SF Symbols, couleurs nommées, accessibilité (VoiceOver sur toutes les commandes, résumé vocal de la position de lecture, Dynamic Type dans la bibliothèque, contraste augmenté) | transversal | Audit VoiceOver et Accessibility Inspector sans erreur bloquante 👤 | `Canvas` n'est pas accessible nativement → éléments d'accessibilité dédiés |
| 7.9 | Écran de bienvenue (premier lancement) : brancher le clavier (détection en direct), essayer une note, importer un premier morceau ou choisir un morceau intégré | `MyPiano/Features/Onboarding/*` | Affiché une seule fois, relançable depuis l'Aide 👤 | — |
| 7.10 | Localisation FR + EN (String Catalog) | `Localizable.xcstrings`, `InfoPlist.xcstrings` | Aucune chaîne en dur ; app entièrement en anglais si le système est en anglais 👤 | — |

**Livrable :** application complète d'aspect Apple. 🍎👤

---

## Phase 8 — Import de partitions

| # | Tâche | Fichiers | Terminé quand | Risques |
|---|---|---|---|---|
| 8.1 | Bibliothèque intégrée installée au premier lancement (identifiants stables, non supprimable, masquable) | `MyPianoLibrary/BuiltinCatalog.swift` | 16–17 morceaux présents hors ligne 👤 | — |
| 8.2 | Import par menu (⌘O), glisser-déposer sur la fenêtre, sur l'icône du Dock, « Ouvrir avec » ; copie dans Application Support ; dédoublonnage | `MyPianoLibrary/Importer.swift`, `MyPiano/App/AppDelegate.swift` | Les quatre chemins importent `.mid/.midi/.musicxml/.xml/.mxl` 👤 ; importeur testé 🍎 | `.xml` générique non-MusicXML → détection par la racine `<score-partwise>`/`<score-timewise>` |
| 8.3 | Édition des métadonnées après import (titre, compositeur, difficulté, mains) et choix des pistes MG/MD ou du point de partage, avec aperçu | `MyPiano/Features/Library/SongEditor.swift` | Modifications persistées et appliquées à la lecture 👤 | — |
| 8.4 | Heuristique de difficulté (notes/s, polyphonie, étendue, altérations), modifiable | `MyPianoCore/Library/DifficultyEstimator.swift` | Tests : classement cohérent des 17 morceaux (Twinkle < Für Elise < Rondo) 🐧 | — |
| 8.5 | Dossier surveillé (option) : bookmark security-scoped, surveillance, import automatique, suppression/renommage gérés | `MyPianoLibrary/FolderWatcher.swift` | Un fichier déposé dans le dossier apparaît dans la bibliothèque en < 5 s, y compris après redémarrage 👤 | Accès perdu (bookmark périmé) → demande de réautorisation |
| 8.6 | Erreurs claires : fichier corrompu, format non supporté, MusicXML sans notes, piste vide ; rapport d'import multi-fichiers | `MyPianoLibrary/ImportError.swift` + localisation | Chaque cas testé avec un fichier de test et un message localisé 🍎 | — |
| 8.7 | Doigtés écrits : lecture de `<fingering>` dans le MusicXML (note, main, doigt 1–5), affichage au-dessus/au-dessous des têtes de note et sur les notes qui tombent, option d'affichage | `MyPianoCore/Parsing/MusicXML/MusicXMLImporter.swift`, `MyPianoCore/Model/Song.swift`, `MyPianoRendering/*` | Tests : doigtés d'un fichier de test lus et rattachés aux bonnes notes 🐧 ; affichés dans les trois vues 👤 | Doigtés multiples ou de substitution sur une même note → on garde le premier |
| 8.8 | Doigtés suggérés : calcul par main du doigté de moindre coût (écarts entre doigts, passages du pouce, touches noires, accords), utilisé quand le fichier n'en contient pas ; distingués visuellement des doigtés écrits ; désactivable | `MyPianoCore/Fingering/FingeringSuggester.swift` | Tests : gammes de Do et Sol majeur, arpèges et accords simples → doigtés classiques 🐧 ; rapide (< 100 ms) sur les 16 morceaux 🐧 | Polyphonie dense moins fiable → présenté comme suggestion |
| 8.9 | « Trouver des partitions… » (menu Aide et bibliothèque vide) : liste de sources libres (Mutopia, piano-midi.de, OpenScore) avec licence, ouverte dans le navigateur ; les fichiers téléchargés s'importent par glisser-déposer, « Ouvrir avec » ou le dossier surveillé | `MyPiano/Features/Library/ScoreSourcesView.swift` | Liens ouverts dans le navigateur, aucune connexion réseau depuis l'app 👤 | Sites qui changent d'adresse → liens regroupés dans un seul fichier |

**Livrable :** import complet et robuste, doigtés écrits et suggérés, accès guidé aux banques de partitions libres. 🍎👤

---

## Phase 9 — Finitions et distribution

| # | Tâche | Fichiers | Terminé quand | Risques |
|---|---|---|---|---|
| 9.1 | Icône macOS (touche de piano stylisée sur dégradé indigo → violet), toutes les tailles ; fenêtre « À propos de MyPiano » (version, build, ©) et fenêtre « Mentions » qui affiche `ACKNOWLEDGEMENTS.md` embarqué | `scripts/render-app-icon.swift`, `Assets.xcassets/AppIcon.appiconset`, `MyPiano/Features/About/*`, `MyPianoApp.swift`, `Commands.swift`, `project.yml` | Icône visible dans le Dock et le Finder ; menus MyPiano › À propos et Aide › Mentions et licences 👤 | Rendu des petites tailles → icône dessinée en vectoriel à chaque taille |
| 9.2 | Suppression de `reference/web/` et de tout l'outillage Bun/Node/Vite/PostCSS/Tailwind ; `LICENSE` conservé (morceaux MIDI et Leland) ; docs nettoyées | `reference/` (supprimé), `scripts/check-legacy-traces.sh`, `docs/REMOVAL_INVENTORY.md` | `check-legacy-traces.sh` vert, seul `ACKNOWLEDGEMENTS.md` nomme l'ancien produit 🐧 ; tests du Core verts sans `reference/` 🐧🍎 | — |
| 9.3 | Scripts de release : archive Release + export `.app` (Developer ID si `TEAM_ID`, *ad hoc* sinon), `.dmg` avec lien vers /Applications ; procédure de signature, notarisation et agrafage | `scripts/build-release.sh`, `scripts/make-dmg.sh`, `docs/RELEASE.md` | `.app` et `.dmg` produits 🍎 ; notarisation acceptée 👤 | Certificat Developer ID et compte Apple nécessaires (étapes faites par toi) |
| 9.4 | Garde-fou hors ligne : aucun entitlement réseau ni exception ATS, aucune API réseau dans les sources, aucune URL dans le binaire hors des sources de partitions | `scripts/check-offline.sh` | Vert sur les sources 🐧 et sur l'app construite 🍎 | — |
| 9.5 | Documentation du produit livré : visualisations, modes, doigtés, import, exercices, jeu libre, volumes, raccourcis, build, tests, publication | `README.md`, `docs/ARCHITECTURE.md`, `docs/PLAN.md` | README à jour, phases 0 à 9 terminées | — |

**Livrable :** application prête à distribuer (`.dmg` signé et notarisé), documentation à jour. 🐧🍎👤

---

## Décisions prises avant la Phase 2

1. **Pas d'enregistrement** du jeu (ni MIDI, ni audio).
2. **Pas de CI GitHub** : compilation et tests Apple sur ton Mac ; le Core est testé dans mon environnement.
3. Identifiant d'app : **`fr.jmarchadier.MyPiano`** ; © « Julien Marchadier ».
4. Clavier : **Arturia KeyLab Essential 61** (clavier de commande, sans son interne : le son vient du Mac).
5. Son : **piano intégré à macOS** (banque General MIDI système).
6. **Swan Lake retiré** de la bibliothèque intégrée.
