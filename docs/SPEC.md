# Pianissimac — Spécification fonctionnelle

> Document de référence pour la réécriture native macOS.
> Il décrit **ce que fait** l'application web existante (dossiers `src/` et `public/`), sans dépendre de son code.
> Les comportements sont décrits tels qu'ils sont observés dans le code, **bugs compris** : chaque écart volontaire
> à prévoir dans Pianissimac est signalé par **→ Pianissimac :** ou regroupé en §6.
>
> Conventions :
> - « temps morceau » = secondes dans la partition à vitesse 100 %. « temps réel » = secondes vécues par l'utilisateur.
> - `vitesse` = multiplicateur de tempo (1,0 = 100 %).
> - Les numéros de note sont des numéros MIDI (21 = La0, 60 = Do4 / C4, 108 = Do8).

---

## Sommaire

1. [Fonctionnalités, écran par écran](#1-fonctionnalités-écran-par-écran)
2. [Modèle de données](#2-modèle-de-données)
3. [Algorithmes clés (pseudo-code)](#3-algorithmes-clés-pseudo-code)
4. [Formats d'import et limites](#4-formats-dimport-et-limites)
5. [Ce qui relève de l'ancien produit et doit disparaître](#5-ce-qui-relève-de-lancien-produit-et-doit-disparaître)
6. [Points ambigus, bugs et recommandations](#6-points-ambigus-bugs-et-recommandations)
7. [Annexes : constantes, tables, raccourcis](#7-annexes)

---

## 1. Fonctionnalités, écran par écran

### 1.0 Vue d'ensemble et navigation

| Route web | Écran | Accessible depuis la navigation ? |
|---|---|---|
| `/` | Accueil (vitrine) | oui (logo) |
| `/songs` | Bibliothèque (« Learn a song ») | oui |
| `/play?source=…&id=…` | Lecture / apprentissage d'un morceau | depuis la bibliothèque |
| `/freeplay` | Jeu libre + enregistrement | oui |
| `/training/phrases` | Entraînement « phrases infinies » | non (lien commenté, « TODO: launch ») — accessible par URL |
| `/training/speed` | Entraînement de vitesse de lecture | **inaccessible** : la route est déclarée avec le chemin `phrases` en double (bug de `routes.ts`) |
| `/training` | Index des entraînements | page présente mais **non routée** |
| `/about` | À propos (marketing) | oui |

Éléments transverses présents sur plusieurs écrans :

- **Entrée clavier d'ordinateur** (lecture, jeu libre, phrases) : certaines touches jouent des notes (voir §7.3).
- **Fenêtre « MIDI Settings »** (lecture, jeu libre, phrases) : voir §1.4.
- **Clic souris sur le clavier dessiné** (mode notes qui tombent) : joue la note sous le pointeur.
- **Wake lock** du navigateur pendant la lecture et les entraînements (empêche la mise en veille de l'écran).

### 1.1 Accueil (`/`)

Page vitrine :
- Bandeau titre (« Your Piano Journey Begins Here », « … right in your browser ») avec deux boutons : **Learn a song** → bibliothèque, **Free play** → jeu libre.
- **Aperçu animé** : lecteur en notes qui tombent sur trois morceaux intégrés au choix (Ode to Joy par défaut, Canon in D, Gymnopédie No.1), bouton lecture/pause, barre d'espace = lecture/pause. Le son est joué.
- Trois cartes argumentaires (« Your Own Music », « Learn at Your Own Pace », « Multiple Modes »).
- Pied de page de copyright de l'ancien éditeur.

**→ Pianissimac :** supprimé (marketing). La fenêtre principale s'ouvre directement sur la bibliothèque (cf. §6).

### 1.2 Bibliothèque (`/songs`)

- Titre et sous-titre d'accueil.
- **Champ de recherche** (filtre « contient », insensible à la casse et aux accents) sur le **titre** uniquement. Focus automatique.
- **Tableau** à deux colonnes : **Titre**, **Durée** (mm:ss). Tri cliquable sur chaque colonne ; **tri par défaut : durée croissante**, égalités départagées par titre (comparaison « naturelle », numérique et insensible à la casse). Pied : « Showing N songs ». Squelette de chargement tant que les dossiers locaux ne sont pas scannés. État vide : « No results ».
- Le catalogue fusionne :
  1. les **17 morceaux intégrés** (manifeste statique, §2.6) ;
  2. les **fichiers MIDI de dossiers locaux** ajoutés par l'utilisateur (§1.2.2).
- Clic sur une ligne → **fenêtre d'aperçu** (§1.2.1).

#### 1.2.1 Aperçu d'un morceau (modale)

- Zone gauche : visualisation **notes qui tombent** du morceau (réglages par défaut, sans décompte ni métronome). Clic dans la zone = lecture/pause. Indicateur de chargement pendant le chargement des sons.
- Zone droite : titre, sous-titre « MIDI Preview », **barre de progression** cliquable/glissable (seek ; met en pause pendant le glissement puis reprend), info-bulle au survol indiquant **temps** et **numéro de mesure** sous le pointeur, temps courant / durée totale.
- Badges : **nombre de pistes**, **nombre total de notes**.
- Bouton **Play Now** → écran de lecture. Raccourcis : **Espace** = lecture/pause de l'aperçu, **Entrée** = Play Now, **Échap**/fermeture = arrêt.

#### 1.2.2 Gestion des dossiers locaux (« Folders »)

- Fonctionne uniquement avec la File System Access API (Chrome/Edge) ; sinon message « Browser Not Supported ».
- Liste des dossiers suivis (nom, nombre de morceaux trouvés), bouton **Add Folder** (sélecteur de dossier, démarre dans « Musique »), bouton **Scan Folders** (rescan, spinner affiché au moins 1 s), suppression d'un dossier (icône corbeille au survol), total « N songs across M folders ».
- Scan : **non récursif**, seuls les fichiers `.mid`/`.midi` (ou type MIME `audio/midi`, `audio/mid`) sont retenus ; chaque fichier est parsé pour obtenir sa durée ; titre = nom de fichier (extension comprise) ; les fichiers invalides sont ignorés silencieusement (log console).
- Les poignées de dossiers sont persistées (IndexedDB). Au redémarrage, si la permission de lecture n'est plus accordée → état « permission requise » (bandeau dans la modale ; écran dédié « Permission Required » si on ouvre un morceau local).
- Écran **« Song Not Found »** si le fichier local a disparu.

### 1.3 Lecture / apprentissage (`/play`)

Écran principal du produit. Disposition verticale : barre supérieure, zone de visualisation, frise des mesures, barre de transport. Panneau de réglages latéral droit (360 px) superposé, et fenêtre de statistiques flottante déplaçable.

#### 1.3.1 Barre supérieure

- **Retour** (arrête la lecture, revient à l'accueil).
- **Titre** du morceau.
- **Statistiques** (affiche/masque la fenêtre de stats).
- **Périphérique MIDI** (ouvre la fenêtre §1.4).
- **Réglages** (ouvre/ferme le panneau §1.3.5).

#### 1.3.2 Zone de visualisation

Deux modes (réglage « Visualizer ») :
- **Notes qui tombent** (défaut) — §3.8.
- **Partition simplifiée** (« Sheet Hero (beta) ») — §3.9.

Overlay de **décompte** centré pendant le décompte : chiffre restant + rangée de points (un par temps).

En mode notes qui tombent, **glisser verticalement** dans la zone (hors clavier) fait défiler le temps (met en pause, défilement inertiel, reprend la lecture à la fin de l'inertie, §3.11).

#### 1.3.3 Frise des mesures (TimelineStrip)

- Bandeau horizontal représentant tout le morceau ; zone parcourue teintée ; **tête de lecture** (trait + triangle).
- Repères de **numéros de mesure** espacés d'au moins 40 px, avec graduations intermédiaires (algorithme §3.12).
- **Clic/glisser** = seek (pause pendant le glissement, reprise ensuite si on jouait).
- Si la boucle est active : rectangle de **plage A-B** avec deux poignées glissables (début/fin) ; les bornes sont recalées sur les mesures (§3.6).

#### 1.3.4 Barre de transport

De gauche à droite :
- **Revenir au début** (« restart ») : si une boucle existe → pause + retour au début de la boucle + remise à zéro des stats ; sinon → arrêt complet (temps 0, stats à zéro).
- **Lecture / pause** (spinner tant que les sons ne sont pas chargés).
- **Volume** (curseur 0–1, défaut 1) — agit sur le son du morceau uniquement, pas sur le retour sonore des touches jouées par l'utilisateur.
- **Temps courant / durée** (mm:ss, en temps morceau) et **« Measure N »** (mesure courante).
- Bascules : **Métronome** (ON/OFF), **Wait** (mode attente), **Vitesse** (menu des préréglages, affiche le pourcentage, mis en évidence si ≠ 100 %), **Loop** (boucle).

#### 1.3.5 Panneau de réglages (par morceau, persistés)

Trois sections repliables (toutes repliées par défaut) + bouton **Reset to Defaults**.

**Lecture (Playback)**

| Réglage | Valeurs | Défaut | Notes |
|---|---|---|---|
| Vitesse | 25, 50, 75, 100, 125, 150, 175, 200 % (+ valeur courante si hors préréglage) | 100 % | Sous-titre « BPM n » = tempo courant × vitesse. **Non persistée** : conservée en mémoire pendant la session et partagée entre tous les morceaux. |
| Boucle (Loop Section) | on/off | off | Plage par défaut : tout le morceau. |
| Mode attente (Wait Mode) | on/off | off | §3.2. |
| Métronome | on/off | off | Sous-réglages visibles si activé : |
| ↳ Volume | faible 0,3 / moyen 0,6 / fort 0,85 | 0,6 | |
| ↳ Vitesse | ¼×, ½×, 1×, 2×, 4× (clics par temps) | 1× | |
| ↳ Accentuer le 1er temps | on/off | on | |
| Mains | les deux / gauche / droite | les deux | |
| Décompte (Countdown) | on/off | on | §3.5. |
| Transposition | −12 … +12 demi-tons | 0 | Transpose le son, l'affichage et la note attendue. |

**Affichage (Display)**

| Réglage | Valeurs | Défaut | Notes |
|---|---|---|---|
| Visualisation | Notes qui tombent / Partition (beta) | Notes qui tombent | |
| ↳ Notes colorées *(partition seulement)* | on/off | off | Une couleur par nom de note (§7.2). |
| ↳ Armure *(partition seulement)* | Inconnue + 15 armures (Cb … C#) | armure détectée du fichier, sinon « Inconnue » | Influence l'orthographe dièse/bémol des notes. |
| Noms des notes | Aucun / Alphabétique (C D E…) / Do fixe (Do Ré Mi…) | Aucun | Affichés dans les notes qui tombent et les têtes de notes. |

**Pistes (Tracks)** — badge = nombre de pistes. Pour chaque piste (« Track n ») :
- nombre de notes ;
- **écouter la piste seule** (lecture/pause d'un mini-lecteur indépendant qui ne joue que cette piste, depuis sa première note) ;
- **son activé/coupé** (défaut : activé) ;
- attribution **MG / MD** (main gauche / main droite ; recliquer désélectionne → « aucune ») ;
- **instrument** : liste de recherche parmi les 128 instruments General MIDI + « percussion ». Défaut : instrument du programme MIDI de la piste.

Une piste non attribuée à une main **n'est pas affichée** mais reste **audible**. Les deux mains ne peuvent pas désigner la même piste par construction de l'UI, mais plusieurs pistes peuvent porter la même main (seule la dernière est retenue par le moteur, §3.4).

**Reset to Defaults** : recalcule les réglages par défaut du morceau (y compris l'attribution automatique des mains, §3.4).

#### 1.3.6 Fenêtre de statistiques (« Session Stats »)

Fenêtre flottante déplaçable : **précision** (%), **série** (streak), compteurs **Parfait**, **Bien**, **Manqué**, **Erreur** (§3.3). Non persistées.

#### 1.3.7 Notifications (toasts)

Lors du déplacement des bornes de boucle au clavier : « Loop start from measure: N », « Loop end at measure: N ».

#### 1.3.8 Raccourcis clavier

Voir §7.4.

#### 1.3.9 Retour sonore

Chaque note jouée par l'utilisateur (MIDI, clavier d'ordinateur, clic) est jouée au **piano acoustique**, indépendamment de l'instrument des pistes, avec une vélocité proportionnelle. La pédale de sustain **n'est pas gérée**.

Le morceau joue **toutes** les pistes dont le son est activé, **y compris les notes de la main active** (l'utilisateur entend la note attendue en même temps qu'il la joue).

### 1.4 Fenêtre « MIDI Settings »

- **Entrées** : liste des ports d'entrée MIDI (nom, fabricant ou « USB Connection »), interrupteur par port. Au démarrage, **toutes les entrées sont activées automatiquement**, sauf celles dont le nom contient « through » (ports de bouclage). État vide : « No MIDI Input Devices Found ».
- **Sorties** : « This Device — Internal Synth » (active/coupe tout le son interne), puis chaque port de sortie MIDI matériel (désactivé par défaut). Activer une sortie y envoie les notes jouées (note on/off canal 1, vélocité = volume × 127).
- **Refresh Devices** : relit la liste des ports (pas de détection automatique à chaud).

### 1.5 Jeu libre (`/freeplay`)

- Barre : retour, **Enregistrer / Arrêter**, **MIDI** (§1.4), **choix d'instrument** (128 GM, défaut piano acoustique, indicateur de chargement/erreur).
- Visualisation : clavier **88 touches complet** ; chaque note jouée crée une barre qui **monte** depuis le clavier et s'allonge tant que la touche est tenue (couleur main droite). Clic sur le clavier = jouer.
- **Enregistrement** : capture des événements note on/off (horodatés, le premier événement à t = 0), conversion en fichier MIDI à une piste. À l'arrêt, **fenêtre d'aperçu de l'enregistrement** :
  - lecture en notes qui tombent + barre de progression ;
  - badges : nombre de notes, instrument ;
  - **Copier un lien de partage** (le MIDI encodé en base64 dans l'URL) ;
  - **Télécharger le MIDI** (`recording.mid`) ;
  - **Télécharger en MP3** (`recording.mp3`) : rendu hors ligne avec l'instrument choisi (§3.14), MP3 128 kb/s.

### 1.6 Entraînement « phrases » (`/training/phrases`)

Génère procéduralement de courtes partitions à lire en mode **partition** avec suivi du jeu.

| Réglage (paramètres d'URL) | Valeurs | Défaut |
|---|---|---|
| Générateur | Aléatoire / « Irish Folk in E Minor » / « Irish Folk in D Major » | E Minor |
| Niveau | 0, 1, 2, 3 | 0 |
| Clé | Sol (treble) / Fa (bass) / Grand-portée | Sol |
| Vitesse | ± 5 % par clic | 100 % |

- La clé détermine la main active : Sol → droite, Fa → gauche, Grand → les deux.
- Indicateurs : barre de **progression**, **précision**, **score** (§3.3), **série**.
- **N'importe quelle touche jouée lance la lecture.** Chaque erreur joue un **son d'erreur** (MP3 accéléré ×6, volume 0,08).
- **Rejouer** (revient au début) / **Suivant** (nouvelle phrase).
- Mode « jeu » de la partition : notes réussies et tenues en violet clair, notes manquées en gris (§3.9).
- Génération : §3.10.

### 1.7 Entraînement de vitesse (`/training/speed`) — inaccessible

- Titre « Random Notes ». 20 notes aléatoires (gamme de Do majeur) affichées en file sur une portée unique (clé de Sol : octaves 4–5 ; clé de Fa : octaves 2–3), espacées de 100 px.
- Jouer la bonne note → elle disparaît, son joué ; mauvaise note → son d'erreur, on avance **quand même**.
- À la fin : **notes/minute** et **précision**.
- Boutons **Restart** et **Next** (nouvelle série).
- Réglages (persistés sous `speedConfig`) : générateur aléatoire / extraits (non implémenté), clé Sol/Fa, afficher le nom des notes, armure (stockée mais ignorée). Le panneau de réglages n'est jamais ouvrable (aucun bouton).

### 1.8 À propos (`/about`)

Page marketing : présentation, conseils de démarrage, sélection musicale, compatibilité navigateurs, **roadmap**, contact/feedback (GitHub, e-mail), **recommandations de claviers avec liens affiliés**, **attributions** des morceaux (lien source + licence pour chacun).

**→ Pianissimac :** supprimée ; les attributions vont dans `ACKNOWLEDGEMENTS.md` et dans une fenêtre « Mentions » accessible depuis le menu Aide.

---

## 2. Modèle de données

### 2.1 Morceau (Song)

| Champ | Type | Description |
|---|---|---|
| `notes` | liste de Note, triée par `time` | Toutes les notes de toutes les pistes. |
| `measures` | liste de Measure, triée par `time` | Mesures du morceau. |
| `tracks` | dictionnaire `trackId (entier) → Track` | Métadonnées de piste. |
| `duration` | secondes | **Fin de la dernière note** (pas la fin de piste). |
| `bpms` | liste `{ time (s), bpm }` | Changements de tempo. Peut être vide (→ 120). |
| `timeSignature` | `{ numerator, denominator }` | Chiffrage « principal » : premier chiffrage dont le numérateur > 1, sinon le premier, sinon 4/4. |
| `timeSignatures` | liste `{ time, numerator, denominator }` | Tous les changements de chiffrage. |
| `keySignature` | une des 15 armures ou absente | Armure détectée (§4.1). Absente = inconnue. |
| `ppq` | entier | Résolution (ticks par noire). 480 pour les morceaux générés. |
| conversions | temps ↔ ticks | Fonctions tenant compte de la carte des tempos. |
| `items` | liste fusionnée notes + mesures triée par temps | Utilisée par le rendu. Dérivable. |

### 2.2 Note

| Champ | Type | Description |
|---|---|---|
| `midiNote` | 0–127 | Hauteur. |
| `track` | entier | Piste d'origine. |
| `time` | secondes (temps morceau) | Début. |
| `duration` | secondes | Durée. |
| `velocity` | 0–127, optionnel | Vélocité. |
| `measure` | entier ≥ 1 | Numéro de la mesure contenant le début de la note. |

L'identité d'une note est l'objet lui-même (les ensembles « réussies »/« manquées » contiennent des références). **→ Pianissimac :** donner un identifiant stable (index dans `notes`).

### 2.3 Mesure

`{ number (≥ 1), time (s), duration (s) }`. Les mesures sont contiguës.

### 2.4 Piste

`{ name?, instrument? (nom GM ou "percussion"), program? (0–127) }`. Canal 10 (index 9) ⇒ instrument « percussion ».

### 2.5 Hauteur / nom de note

- Octave d'une note : `floor((midi − 12) / 12)` (60 → 4).
- Le nom affiché dépend de l'**armure** (tables §7.1) : en Do et dans les tonalités à dièses, les touches noires sont nommées en dièses ; dans les tonalités à bémols, en bémols. Les tables contiennent aussi des **bécarres** (♮) pour les altérations accidentelles par rapport à l'armure.
- Notation « Do fixe » : C→Do, D→Ré (Re), E→Mi, F→Fa, G→Sol, A→La, B→Si, + altération.

### 2.6 Métadonnées de catalogue (SongMetadata)

| Champ | Description |
|---|---|
| `id` | Intégré : nom de fichier (`fur-elise.mid`). Dossier local : `idDossier/nomFichier`. Enregistrement : MIDI en base64. |
| `source` | `builtin`, `local`, `base64` (`generated` défini mais inutilisé). |
| `title` | Intégré : « Titre - Compositeur » (une seule chaîne). Local : nom de fichier. |
| `duration` | Secondes (arrondies pour l'intégré). |
| `difficulty` | Numérique, **jamais renseigné** (0). Libellés prévus : Easiest, Easier, Easy, Medium, Hard, Hardest, « - » (inconnu). |
| `url`, `license` | Intégré uniquement : page source et licence. |
| `file`, `lastModified`, `fileSize`, `handle` | Techniques. |

Manifeste intégré (17 morceaux) : voir §5.3 pour la liste et les licences.

### 2.7 Réglages par morceau (SongConfig) — persistés

| Champ | Type | Défaut |
|---|---|---|
| `left`, `right` | booléens (mains actives) | `true`, `true` |
| `waiting` | booléen | `false` |
| `countdownEnabled` | booléen | `true` |
| `transpose` | entier −12…12 | 0 |
| `loop` | `{ enabled, range { start, end } }` | `{ false, { 0, durée } }` |
| `metronome` | `{ enabled, volume, speed, emphasizeFirst }` | `{ false, 0,6, 1, true }` |
| `visualization` | `falling-notes` / `sheet` | `falling-notes` |
| `noteLabels` | `none` / `alphabetical` / `fixed-do` | `none` |
| `coloredNotes` | booléen | `false` |
| `skipMissedNotes` | booléen | `false` (jamais lu par le moteur, cf. §6) |
| `keySignature` | armure ou absente (= celle du fichier) | absente |
| `tracks` | `trackId → { track, hand (left/right/none), sound (bool), instrument }` | calculé (§3.4) |

Fusion au chargement : réglages persistés appliqués par-dessus les défauts (les sous-objets `loop`, `metronome`, `tracks` sont fusionnés clé par clé). Si rien n'est persisté, les défauts sont enregistrés.

**Non persistés** : vitesse, volume, état des périphériques MIDI, statistiques.

### 2.8 Progression

**Inexistante** dans l'original : aucune historique, aucun score sauvegardé, aucun favori, aucun « récent ». **→ Pianissimac :** nouveau modèle à concevoir en Phase 1 (proposition : par morceau, liste de sessions `{ date, durée jouée, vitesse, mains, mode attente, précision, parfait/bien/manqué/erreur, meilleure série, plage jouée }` + agrégats « meilleure précision », « dernière ouverture », « favori »).

### 2.9 Stockage

| Donnée | Emplacement web |
|---|---|
| Réglages par morceau | localStorage, clé `"<id>/settings"` (l'id seul, **sans la source** → collision possible entre un fichier local et un intégré de même nom) |
| Réglages de l'entraînement de vitesse | localStorage `speedConfig` |
| Dossiers suivis | IndexedDB `OBSERVED_DIRECTORIES` (`{ id, addedAt, handle }`) |
| Clés obsolètes nettoyées au démarrage | `SONG_DATA`, `UPLOADS/SONG_LIST` |

---

## 3. Algorithmes clés (pseudo-code)

### 3.1 Horloge de lecture

États : `CannotPlay` (chargement des sons) → `Paused` ⇄ `Playing`, avec l'état transitoire `CountingDown`.

```
état: tempsMorceau (s), indexCourant (prochaine note non traitée),
      enCours (notes en train de sonner), dernierTick (horodatage réel)

boucle de lecture (≈ toutes les 1 ms dans l'original) :
    précédent ← tempsMorceau
    si Playing :
        dt ← (maintenant − dernierTick) × vitesse
        dernierTick ← maintenant
        tempsMorceau += dt
    si tempsMorceau ≥ durée : seek(durée) ; pause() 
    si boucle [A,B] et précédent ≤ B ≤ tempsMorceau :
        si décompte requis à A : seek(A) ; pause() ; play()   // relance avec décompte
        sinon seek(A)
        terminer ce tick
    mettre à jour l'index de tempo courant
    arrêter le son des notes de `enCours` terminées (time + duration ≤ tempsMorceau)
    métronome (§3.7)
    purger les notes en retard devenues « manquées » (§3.3)
    score « durée tenue » += nombre de notes de `enCours` réussies ET encore enfoncées
    tant que notes[indexCourant].time < tempsMorceau :
        n ← notes[indexCourant]
        si n appartient à une main active :
            si modeAttente et n non réussie :
                tempsMorceau ← n.time ; terminer ce tick       // BLOQUE (§3.2)
            sinon si n non réussie et précédent < n.time :
                enRetard[hauteurTransposée(n)] ← n              // fenêtre « en retard »
        ajouter n à enCours
        jouer n (sauf option « ne jouer que les notes réussies », §6)
        indexCourant += 1

temps affiché (getTime) :
    si pas Playing → tempsMorceau
    si modeAttente et notes[indexCourant] non réussie → tempsMorceau (gel)
    sinon → tempsMorceau + (maintenant − dernierTick)   // interpolation entre ticks
```

```
seek(t):
    si boucle : t ← borner(t, A, B)
    couper tous les sons
    tempsMorceau ← t
    enCours ← notes telles que time < t < time + duration
    indexCourant ← première note avec time ≥ t
    recalculer l'index de tempo et le dernier tick de métronome
    vider réussies, manquées, enRetard        // les compteurs de score ne sont PAS remis à zéro
play():
    si Playing, CannotPlay ou CountingDown : rien
    si décompte requis : décompte (§3.5) puis démarrage
    sinon démarrage : si tempsMorceau ≥ durée → seek(0) ; état Playing ; relancer les notes de `enCours`
pause(): annule le décompte ; état Paused ; coupe les sons
stop():  pause ; tempsMorceau ← 0 ; index ← 0 ; boucle supprimée ; stats à zéro
```

Tempo affiché : `bpm(temps) × vitesse`, où `bpm(temps)` est le dernier changement de tempo dont `time ≤ temps` (120 si aucun).

Vitesse : préréglages 0,25…2,0 ; touches `+`/`−` : ± 0,05, arrondi à 2 décimales, **sans borne** (cf. §6).

Navigation par mesure :
```
mesureÀ(t)       = dernière mesure avec time ≤ t (si t avant la 1re → dernière mesure ! cf. §6)
mesurePrécédente(t) : si t est exactement le début d'une mesure n>1 → début de n−1, sinon début de la mesure courante
mesureSuivante(t)   : début de la mesure suivante, ou fin du morceau pour la dernière
```

**→ Pianissimac :** horloge dérivée de l'horloge audio (temps d'échantillon de l'engine) ; même sémantique.

### 3.2 Mode attente

Principe : le temps ne dépasse jamais une note **de la main active** tant qu'elle n'a pas été jouée. Chaque note d'un accord bloque individuellement : il faut donc jouer **toutes** les notes de l'accord (dans n'importe quel ordre, simultanément ou non) pour avancer.

```
dans la boucle de lecture (cf. §3.1) :
    si n est de la main active et non réussie → tempsMorceau ← n.time et on s'arrête

à l'appui d'une touche h (si Playing) :
    candidats ← notes à partir de indexCourant ayant le même time que notes[indexCourant]
    n ← premier candidat dont hauteurTransposée = h et non réussi
    si n existe et |n.time − tempsMorceau| (converti en temps réel) < 300 ms :
        n devient réussie (Parfait car l'écart vaut 0 quand on attend) ; série += 1
        → au tick suivant, la boucle repart
    sinon : erreur += 1 ; série ← 0
```

Remarques de comportement :
- En attente, le temps est **figé** sur le début de la note (pas d'avance progressive) ; les notes des pistes non actives situées avant continuent d'être jouées.
- Les notes non actives au même instant (autre main, accompagnement) **sont** des candidats valides : jouer une note de l'autre main la valide (cf. §6).
- Le relâchement des touches n'a aucun effet (pas d'exigence de tenue).

### 3.3 Tolérance de timing et score

Constantes : **Parfait < 50 ms**, **Bien < 300 ms** (écarts en **temps réel** : écart en temps morceau ÷ vitesse).

```
à l'appui d'une touche h (si Playing) :
    purgerManquées()
    // 1) note déjà passée (jouée en retard)
    si enRetard contient h :
        n ← enRetard[h] ; retirer
        écart ← (tempsMorceau − n.time) / vitesse
        si écart < 50 ms → parfait += 1 ; sinon si écart < 300 ms → bien += 1
        si écart < 300 ms : série += 1 ; n réussie ; terminer
    // 2) note à venir (jouée en avance)
    n ← premier des candidats (même time que notes[indexCourant]) de hauteur h
    si n et non réussie et (n.time − tempsMorceau)/vitesse < 300 ms :
        parfait ou bien selon l'écart ; série += 1 ; n réussie ; terminer
    // 3) sinon
    erreur += 1 ; série ← 0

purgerManquées() (à chaque tick et à chaque appui) :
    pour chaque n dans enRetard : si (tempsMorceau − n.time)/vitesse > 300 ms :
        retirer ; manquées += 1 ; n marquée manquée
    si au moins une : série ← 0

touché  = parfait + bien
précision = total = touché + manqué + erreur ; si total = 0 → 100 % sinon arrondi(100 × touché / total)
score combiné = parfait×100 + bien×50 − erreur×25 + duréeTenue    (affiché seulement dans « phrases »)
```

Notes :
- Une note n'entre dans `enRetard` que si elle est de la main active, non réussie, et que son début a été franchi pendant ce tick.
- `enRetard` est indexé par hauteur : deux notes de même hauteur rapprochées s'écrasent.
- `duréeTenue` augmente d'une unité **par tick** (dépend de la fréquence de la boucle) — à corriger (§6).
- L'appui n'est évalué que si l'état est Playing (pas pendant la pause ni le décompte).

### 3.4 Attribution des mains

Exécutée à la création des réglages par défaut d'un morceau.

```
inférerMains(morceau) -> (gauche, droite):
    noms ← noms des pistes
    gaucheProbable ← premier nom ∈ {"bass","left","lh","l.h."} (comparaison en minuscules)
    droiteProbable ← premier nom ∈ {"treble","lead","rh","right","r.h.","student"}
    si les deux trouvés → pistes correspondantes
    pianos ← pistes « piano » (nom ou instrument contient "piano", ou programme 0…6) ayant ≥ 1 note
    si |pianos| ≥ 2 : (t1, t2) ← deux premières pistes piano
    sinon            : (t1, t2) ← deux premières pistes du fichier (même vides)
    m1, m2 ← hauteur moyenne des notes de t1, t2
    si m1 < m2 → (gauche = t1, droite = t2) sinon (gauche = t2, droite = t1)
```

Conséquences :
- Fichier à **une seule piste** (4 des 17 morceaux intégrés) : `m2` indéfini ⇒ la piste unique devient la **main droite**, pas de main gauche. Les deux mains d'un piano sur une seule piste ne sont pas séparées.
- Les pistes vides (piste de tempo d'un SMF type 1) peuvent être choisies si moins de deux pistes piano.

Attribution des réglages de piste par défaut : `hand` = left/right/none selon le résultat, `sound` = vrai, `instrument` = nom GM du `program` (si ≥ 0), sinon `instrument`/`name` de la piste, sinon piano.

Main active (moteur) : `les deux` | `gauche` | `droite`. Une note est « active » si sa piste est la piste gauche ou droite **et** que la main correspondante est sélectionnée. Si plusieurs pistes portent la même main, seule la **dernière** (par id) compte pour le moteur, alors que le rendu les affiche toutes.

**→ Pianissimac :** (1) séparer automatiquement une piste unique en deux mains par point de partage (cf. §6) ; (2) permettre plusieurs pistes par main ; (3) MusicXML : main par portée (staff 1 = MD, staff 2 = MG).

### 3.5 Décompte

```
décompteRequis(t):
    si décompte désactivé → non
    si arrondi(t, ms) ≤ 0 → oui
    si boucle et |t − A| < 1 ms → oui
    sinon non

lancerDécompte():
    tRef ← t ; si la mesure courante est une anacrouse
             (durée < 0,75 × durée de la mesure suivante) → tRef ← début de la mesure suivante
    (num, den) ← chiffrage actif à tRef (num ≥ 1)
    bpm ← bpm(tRef) × vitesse
    intervalle ← (60 / bpm) × (4 / den) secondes
    restant ← num ; clic immédiat
    toutes les `intervalle` : restant −= 1 ; si restant > 0 → clic ; sinon → démarrage de la lecture
clic = note 75 du « woodblock » à la vélocité volumeMétronome × 127 (muet si volume 0)
```

Annulé par pause, seek par glisser, désactivation du décompte (la lecture démarre alors immédiatement).

### 3.6 Boucle A-B

```
définirBoucle(début, fin):
    A ← début de la mesure contenant `début`
    m ← mesure contenant `fin`
    B ← si fin ≤ m.time + 5 ms : m.time  sinon début de la mesure suivante (ou fin du morceau)
    si B > A : boucle ← [A, B] ; seek(tempsActuel) (borné à [A, B])
```
- Activation sans plage connue : plage = morceau entier.
- Quand la lecture franchit B → retour à A (avec décompte si activé).
- Seek borné dans [A, B] tant que la boucle est active.
- Clavier : ←/→ déplacent A d'une mesure ; Ctrl+←/→ déplacent B ; `P` active/désactive ; `O` retourne à A.
- Rendu : bandeau dans la frise (poignées) + crochet violet semi-transparent dans les notes qui tombent.

### 3.7 Métronome

```
temps (beat) en ticks = ppq × 4 / dénominateur(chiffrage principal)
intervalle de clic   = temps / vitesseMétronome        (¼× → un clic toutes les 4 noires … 4× → 4 clics par temps)
tickCourant          = arrondiInférieur(ticks(tempsMorceau) / intervalle) × intervalle
si métronome actif et tickCourant ≠ dernierTickJoué :
    dernierTickJoué ← tickCourant
    accent ← accentuerPremier et (tickCourant / temps) mod numérateur = 0
    jouer woodblock note (accent ? 90 : 75), vélocité volume × 127
```
- Le métronome suit le tempo **du fichier** (ticks) et donc la vitesse.
- Il utilise le chiffrage **principal** uniquement (ignore les changements de mesure).
- Un second son « agogo » pour l'accent est chargé mais inutilisé (l'accent = même son, note plus aiguë).

### 3.8 Rendu « notes qui tombent »

Géométrie du clavier (`largeur` = largeur de la vue) :
```
plage de touches (getSongRange) :
    min/max des hauteurs (transposées) du morceau ; défaut 21…108
    nbMin ← 36 en portrait ; en paysage selon la largeur :
            >800 px → 88 ; >600 → 72 ; >500 → 60 ; >400 → 40 ; >300 → 32
    si (max − min) < nbMin : élargir symétriquement
    min ← borner(min − 2, 21, 107) ; max ← borner(max + 2, min + 1, 108)
    si la touche juste à gauche (resp. droite) est noire, l'inclure
    ⇒ sur un écran de Mac, toujours 88 touches.
largeurBlanche = largeur / nbBlanches ; hauteurBlanche = min(5 × largeurBlanche, 250)
largeurNoire = largeurBlanche / 2 ; hauteurNoire = 2/3 × hauteurBlanche ; séparation = largeurBlanche / 20
couloir de la touche blanche k = [k × largeurBlanche, +largeurBlanche]
couloir d'une noire : centré sur la frontière entre blanches, décalé de ±(2/3 − 1/2) × largeurNoire
    selon sa position dans le groupe (C#,F# vers la gauche ; D#,A# vers la droite ; G# centré)
```

Disposition verticale (du bas vers le haut) : clavier, bande de feutre rouge (hauteur = barreGrise − 2), barre grise (`max(hauteurBlanche/30, 6)`), puis la zone de chute. **Ligne de frappe** = haut du feutre.

```
vitesse de défilement : 225 px par seconde de temps morceau
y_bas(note)  = ligneDeFrappe − (note.time − tempsCourant) × 225
hauteur      = max(note.duration × 225, hauteur minimale pour afficher le nom)
x, largeur   = couloir de la hauteur transposée (+1 px / −2 px de marge)
une note est « en train de jouer » si elle chevauche la ligne de frappe
```

Éléments dessinés :
- fond `#0f1014` ;
- lignes verticales de repère aux **Do** (très discrètes) et aux **Fa** ;
- lignes horizontales de **mesure** avec leur numéro (à gauche) ;
- notes : rectangles arrondis (rayon 10), couleur selon main et type de touche (§7.2), nom de note optionnel en bas de la barre (taille de police maximale qui tient dans la largeur) ;
- plage de boucle (crochet violet) ;
- clavier : touches blanches ivoire `rgb(255,253,240)` à coins inférieurs arrondis, étiquette « C4 » etc. sur chaque Do, touches noires (images PNG relevée/enfoncée) ;
- **touches actives** : enfoncée par l'utilisateur → gris ; note du morceau en train de jouer → couleur de la main (prioritaire) ; enfoncement visuel de 2 px.

Seules les notes des mains **affichées** (main sélectionnée ∩ pistes attribuées) sont dessinées.

### 3.9 Rendu « partition simplifiée » (Sheet Hero) et position des notes

Toujours en **grand-portée** : portée de Sol en haut, portée de Fa en bas, accolade, trait de liaison, clés, armure (si connue), chiffrage. Le temps défile **horizontalement** (225 px/s) vers une **ligne de jeu** verticale violette. Pas de barres de mesure, pas de figures de rythme, pas de ligatures, pas de silences : chaque note = **tête de note noire** + **traîne** horizontale (10 px d'épaisseur) dont la longueur représente la durée.

Constantes : hauteur des 5 lignes = 80 px ; interligne `s` = 20 px ; « rang » = demi-interligne = 10 px.

```
portée(note) = Sol si la piste est attribuée à la main droite, sinon Fa
// position verticale
nom ← nomDeNote(hauteurTransposée, armure)        // tables §7.1, ex. "F#", "Bb", "F♮"
étape ← index de nom[0] dans C=0, D=1, E=2, F=3, G=4, A=5, B=6
octave ← floor((midi − 12) / 12)
rang(note) = octave × 7 + étape
rangHaut(Sol) = rang(F5) ; rangHaut(Fa) = rang(A3)       // ligne supérieure de chaque portée
décalage = rangHaut(portée) − rang(note)                 // 0 = ligne du haut, 8 = ligne du bas
y = hautPortée + décalage × 10

hautPortéeSol = hauteurVue/2 − 50 − 80 ; hautPortéeFa = hauteurVue/2 + 50

// lignes supplémentaires
d ← décalage ; si d impair, le ramener vers la portée d'un rang
si 0 ≤ d < 10 → aucune
sinon tracer une ligne tous les 2 rangs entre la portée et d (au-dessus : de d à 0 ; en dessous : de 10 à d)

// position horizontale
xClé = 100 + s ; xArmure = xClé + 3s ; xChiffrage = xArmure + nbAltérations × s + s
xLigneDeJeu = xChiffrage + 4s
x(note) = xLigneDeJeu + 10 + (note.time − tempsCourant) × 225

// altérations
si nom a deux caractères : dessiner un dièse si nom[1] = "#", sinon un bémol (cf. bug §6 pour les bécarres),
    à gauche de la tête (x − s − 8)
// armure : altérations aux positions F5 C5 G5 D5 A4 E5 B4 (Sol) / F3 C3 G3 D3 A2 E3 B2 (Fa),
//          ordre des dièses F C G D A E B, des bémols B E A D G C F, espacées de s
// chiffrage : glyphes numériques SMuFL du numérateur (y = haut + s) et du dénominateur (y = haut + 3s)
```

Coloration :
- Les notes s'estompent en dégradé à l'approche de la ligne de jeu (transparentes 2 interlignes avant) ; une note dépassée n'affiche plus que sa traîne.
- Couleur de base noire, **violette** lorsqu'elle atteint la ligne de jeu ; option **notes colorées** : couleur par nom de note (§7.2).
- Mode jeu (entraînement) : réussie **et** encore enfoncée → violet clair ; manquée → gris.
- **Touches enfoncées** par l'utilisateur : tête de note **rouge** (ou couleur de la note si notes colorées) dessinée sur la ligne de jeu, à la hauteur de la note jouée, avec altération ; portée = celle de la note attendue de même hauteur si elle est visible, sinon Sol si ≥ Do4, Fa sinon.
- Noms de notes optionnels (petit texte blanc dans la tête).

Glyphes SMuFL utilisés (police Leland) : accolade U+E000, clé de Sol U+E050, clé de Fa U+E062, chiffres de mesure U+E080…E089, tête noire U+E0A4, dièse/bémol/bécarre (accidentals SMuFL).

### 3.10 Génération des exercices (« phrases »)

**Générateur aléatoire** :
```
durée ← 10 s ; duréeNote ← niveau 1 : 1 s ; niveau 2 : 0,5 s ; sinon (0 et 3) : 0,25 s
pour t de 0 à 10 par pas de duréeNote :
    note commune : time = t, duration = duréeNote − 0,05, measure = floor(t / 4)
    si Fa  : piste 1, hauteur = noteAléatoire(octaves 2…3, Do majeur)
    si Sol : piste 0, hauteur = noteAléatoire(octaves 4…5, Do majeur)
mesures : une par seconde (10), numérotées à partir de 0
chiffrage 4/4, pas de tempo (→ 120), armure inconnue

noteAléatoire(octMin, octMax, armure):
    gamme ← 7 degrés de la gamme majeure de l'armure (cycle des quintes)
    octave ← entier aléatoire [octMin, octMax]
    retourner 12 + 12 × octave + degré aléatoire     // ex. octave 4, degré 0 → 60
```

**Générateurs « folk irlandais »** : assemblage de mesures pré-écrites (fichiers MIDI d'une mesure par variante, rangés par accord, registre et niveau).
```
progression (32 mesures) :
  « E Minor » : 16 × alternance {Em, G} grave puis 16 × {Em, A, G} aigu
                (Em G Em G Em G G Em | Em G Em G Em G G Em | Em A Em G Em A G Em | Em A Em G Em A G Em)
  « D Major » : D Em D G D Em G D (×2, grave) puis la même chose en aigu (×2)
pour chaque accord de la progression :
    MD  : fichier "Right Hand/<Accord>_<High|Low>_Lvl_<niveau>.mid"
    MG  : fichier "Left Hand/<Accord>_Lvl_<min(niveau,2)>_LH.mid"
    découper chaque fichier en mesures ; recaler chaque mesure pour que sa 1re note soit à 0
    choisir une mesure au hasard dans chaque fichier ; fusionner (MG = piste 0, MD = piste 1)
    (les deux mesures doivent avoir la même durée, sinon erreur)
concaténer les 32 mesures bout à bout
chiffrage 6/8, pas de tempo (→ 120), armure inconnue, ppq 480
```
Inventaire des fichiers : MD — accords A, Am, C, D, Em, G en registres High/Low, niveaux 0–3 (quelques niveaux manquent pour Am) ; MG — A, Am, C, D, Em, G niveaux 0–2. Les noms d'UI sont inversés par rapport aux progressions (« E Minor » utilise la progression nommée `dMajor` dans le code et inversement).

Réglages de lecture forcés : visualisation partition, mode jeu, main selon la clé, `skipMissedNotes = true` (sans effet, §6).

### 3.11 Défilement par glisser (notes qui tombent)

```
appui hors du clavier : mémoriser si on jouait, pause (annule le décompte), accélération ← 0
déplacement : seek(temps + vitesseY_pointeur / 225) ; accélération ← vitesseY si |vitesseY| > 5 px sinon 0
relâchement : inertie à chaque image : seek(temps + accélération/225) ; accélération × 0,96
              jusqu'à |accélération/225| ≤ vitesse/60, puis reprise de la lecture si on jouait
```
**→ Pianissimac :** défilement au trackpad / molette (+ glisser), avec la même inertie native.

### 3.12 Graduations de la frise

```
labelsMax = max(1, floor(largeur / 40))
pas ← premier de [1, 5, 10, 20, 40, 80] tel que (pas = 1 ? nbMesures : 1 + floor(nbMesures/pas)) ≤ labelsMax ; sinon 80
labels = 1 (si pas = 1) ou pas, 2×pas, … ≤ nbMesures, + toujours la dernière mesure
graduations intermédiaires tous les pas/4, pas/5 ou pas/2 (premier diviseur entier), aucune si pas = 1
labels filtrés à l'affichage : ≥ 20 px des bords, ≥ 40 px entre deux labels
```

### 3.13 Calcul des mesures (MIDI)

```
événements de chiffrage triés (défaut [tick 0 : 4/4])
finTicks ← durée en ticks du fichier (si > 0) sinon max(fins de pistes)
pour chaque segment [chiffrage_i, chiffrage_{i+1} ou finTicks] :
    ticksParMesure = num / den × 4 × ppq
    nb = ceil(longueurSegment / ticksParMesure)
    créer nb mesures (time et duration convertis via la carte des tempos), numérotées à la suite
mesure(note) = recherche dichotomique du dernier début de mesure ≤ tick de la note
```
« Durée partition » (tests) = fin de la dernière mesure complète.

### 3.14 Rendu audio hors ligne (export)

```
pour chaque note de chaque piste :
    échantillon ← échantillon de la hauteur dans la soundfont de l'instrument
    début = note.time ; relâche = min(0,25, max(0,04, 0,25 × durée))
    fin = min(début + durée + relâche (≥ début + 0,05), début + longueurÉchantillon)
    gain = vélocité, rampe linéaire vers 0 pendant les 50 dernières ms
durée totale = durée du MIDI + 1 s ; stéréo ; fréquence de l'engine ; encodage MP3 128 kb/s
```

### 3.15 Enregistrement (jeu libre)

```
au démarrage : liste vide, t0 ← premier événement reçu
chaque appui/relâchement : { on|off, hauteur, vélocité (127 par défaut), t − t0 }
à l'arrêt : apparier chaque off avec le dernier on de même hauteur → note (début, durée, vélocité)
            les notes encore enfoncées à l'arrêt sont perdues ; fichier MIDI 1 piste
```

### 3.16 Synthèse sonore temps réel

- Une voix par note : échantillon de la soundfont (une note sur deux ou toutes selon la banque), gain = vélocité/127 × volume.
- Relâchement : rampe exponentielle sur 0,5 s puis arrêt.
- Rejouer une note déjà en cours remplace la référence (l'ancienne voix continue jusqu'à la fin de l'échantillon).
- Piano acoustique : banque « Salamander C5 Light » ; autres instruments : « FluidR3 GM » (au format MIDI.js, téléchargés à la demande).
- Si une sortie MIDI matérielle est activée, chaque note jouée par une voix (non métronome) est **aussi** envoyée en MIDI.

---

## 4. Formats d'import et limites

### 4.1 MIDI (`.mid`, `.midi`) — seul format réellement utilisé

Lecture via une bibliothèque tierce. Comportement attendu à reproduire :
- **SMF type 0 et 1** (type 2 non garanti). Division en ticks par noire (le timecode SMPTE n'est pas géré).
- Une piste du fichier = une piste du morceau (y compris la piste de tempo vide d'un type 1). **Type 0 : aucune séparation par canal** → toutes les notes sur une piste → une seule main.
- Tempos multiples supportés (conversion ticks ↔ secondes).
- Chiffrages multiples supportés pour les mesures ; un seul affiché (chiffrage principal).
- Armure : premier événement de tonalité (le dernier au tick minimal), tonalité majeure équivalente (le mode mineur est ignoré). **« Do majeur » est traité comme inconnu** (les logiciels écrivent souvent 0 par défaut), sauf si le morceau ne contient aucune touche noire, auquel cas Do est retenu.
- Vélocités converties en 0–127. Canal 10 ⇒ percussion.
- Ignorés : pédales (CC64 sustain, sostenuto, una corda), autres contrôleurs, pitch bend, paroles, marqueurs, titre/copyright, aftertouch.
- Durée = fin de la dernière note.
- Erreurs : un fichier invalide fait échouer le chargement (« Song Not Found » côté lecture, ignoré côté scan).

### 4.2 MusicXML — parser présent mais **non branché**

Un parser `.xml` existe (non utilisé par l'application, dépend du DOM du navigateur). Comportement implémenté :
- Parcours séquentiel de tous les éléments.
- Main par **clé** rencontrée : clé de Sol → piste 1 (MD), clé de Fa → piste 2 (MG) — l'élément `<staff>` est ignoré.
- `<divisions>` : **seule la première valeur** du document est utilisée.
- Tempo : `<sound tempo="…">` ; défaut 120.
- Notes : `<step>`, `<octave>`, `<alter>` (sinon `<accidental>` sharp/flat/natural), `<duration>` ; `<chord/>` ⇒ même début que la note précédente ; `<rest>` avance le temps ; `<backup>`/`<forward>`.
- **Liaisons** (`<tie>`) fusionnées en une seule note.
- **Reprises** : une reprise « backward » duplique les notes depuis la dernière reprise « forward » (une seule fois) ; pas de voltas, D.C., D.S., coda.
- Mesures dédupliquées entre parties ; temps arrondis à 0,01 s (perte de précision).
- Armure : `<fifths>` (Do = inconnue, sauf aucune touche noire) ; mode ignoré.
- Chiffrage : `<beats>`/`<beat-type>` (le dernier rencontré devient le chiffrage principal).
- **Non supporté** : `.mxl` compressé, notes d'agrément, ornements, nuances, multi-parties correctes, portées autres que Sol/Fa, divisions variables, doubles altérations via `<accidental>`.

**→ Pianissimac :** parser MusicXML complet à réécrire (`.musicxml`, `.xml`, `.mxl`), avec mains par `<staff>`, reprises/voltas, et conservation des informations de notation utiles à la partition (figures, ligatures, silences).

### 4.3 Sérialisation MIDI (tests uniquement)

Un sérialiseur reconstruit un SMF à partir d'un morceau (tempos, chiffrages, armure, une piste par piste, vélocités, canal 10 pour percussion). Utilisé seulement dans des tests d'aller-retour. **→ Pianissimac :** utile pour l'export des enregistrements.

### 4.4 Base64

Un morceau peut être passé directement en base64 dans l'URL (`source=base64`) : sert au partage des enregistrements. **→ Pianissimac :** supprimé (fichiers à la place).

### 4.5 Jeux de test existants

- `public/music/songs/` : **17 fichiers MIDI** (tous SMF type 1, ppq 480 ; 13 à deux pistes de notes, 4 à une seule : *La Cucaracha*, *Ode to Joy*, *Swan Lake*, *Twinkle Twinkle*).
- `tests/mscore-meta/*.json` : 16 fiches de référence générées par MuseScore (tous sauf *Twinkle*) : nombre de mesures, chiffrage, durée partition (± 0,5 s), armure.
- Tests existants : nombre de mesures, chiffrage, durée, armure (si ≠ Do), aller-retour sérialisation (notes, mesures, durée à 20 ms près). Tests de la frise (snapshots des graduations).

---

## 5. Ce qui relève de l'ancien produit et doit disparaître

### 5.1 Identité et présence web
- Nom et marque de l'original, logo (`src/icons/Logo.tsx`, `public/images/logo.png`), favicon, icônes PWA (`icon-192/512.png`), `src/pages/manifest.json` (manifest PWA), titre et balises meta auteur.
- Domaine web et URLs de l'original (site, dépôt GitHub, dépôt de soundfonts téléchargées au build), chaîne YouTube, e-mail de contact, copyright de la société éditrice.
- Balises **Open Graph / Twitter**, captures marketing (`public/images/mode_*.png`).
- `public/robots.txt`, `public/sitemap.txt`, config d'hébergement, config du robot de mises à jour de dépendances, `.github/workflows/validate.yml`, `CONTRIBUTING.md`, `README.md` actuel.

### 5.2 Tracking et réseau
- **Google Analytics** (`src/features/analytics`, script injecté dans `root.tsx`, variable d'environnement de l'identifiant de suivi).
- Téléchargements réseau : soundfonts (script `download-soundfonts.ts`, chargement à la demande des instruments), polices et fichiers servis par le web. **→ Pianissimac :** tout embarqué dans le bundle, zéro appel réseau.

### 5.3 Discours marketing
- Page d'accueil (accroches, cartes « pourquoi ce produit »), `MarketingFooter`, page **About** (roadmap, compatibilité navigateurs, feedback GitHub, liens **affiliés Amazon**, mentions « free and open-source »).
- README : annonces de « private development phase », « free forever », politique de contributions.

### 5.4 Fonctionnalités purement web
- Wake lock navigateur (**→** `ProcessInfo.beginActivity` / assertion IOKit pendant la lecture).
- File System Access API, permission « Grant Permission », IndexedDB (**→** dossier surveillé avec security-scoped bookmark, Phase 8).
- Partage par URL base64, téléchargements par lien `<a download>` (**→** panneaux d'enregistrement natifs).
- Gestion tactile mobile, détection iOS/Android, correctif AudioContext iOS, mise en page responsive mobile, menu « hamburger ».
- Encodeur MP3 WebAssembly (**→** export AAC/M4A natif, cf. §6).

### 5.5 Inventaire des assets et licences (à valider avant réutilisation)

| Asset | Usage | Licence connue | Statut pour Pianissimac |
|---|---|---|---|
| 17 MIDI `public/music/songs/` | Bibliothèque intégrée | Par morceau, d'après le manifeste : **CC BY 4.0** (Arabesques, Clair de Lune, Für Elise, Gymnopédie, Hall of the Mountain King, Moonlight Sonata), **Public Domain Mark** (Canon, Greensleeves, La Cucaracha, March in D, Minuet in G, Ode to Joy, Sonata 11, Rondo, Swan Lake, Entertainer), **CC BY-SA 4.0** (Twinkle) | Réutilisables commercialement avec attribution (BY) ; BY-SA impose de redistribuer ce fichier sous BY-SA. ⚠️ *Swan Lake* a la **même URL source que *Minuet in G*** (erreur du manifeste) → provenance non vérifiée. ⚠️ « Ode to Joy - Christian Petzold » : attribution erronée (Beethoven). |
| 70 MIDI `public/music/irish/` (phrases) | Entraînement phrases | **Inconnue** (aucune mention ; probablement créées pour l'ancien projet ⇒ GPL-3.0 par défaut) | ⚠️ À remplacer par des motifs créés pour Pianissimac. |
| 11 MP3 `public/music/irish/Backing Tracks/` | **Aucun** (non référencés) | **Inconnue** (« DB ») | À supprimer. |
| `public/effects/wrong-sound-effect.mp3` | Son d'erreur | **Inconnue** | ⚠️ À remplacer (son synthétisé ou créé). |
| `public/images/black-key-*.png` | Rendu des touches noires | Ancien projet (GPL-3.0) | À remplacer par un rendu vectoriel. |
| Police **Leland** (`src/styles/fonts/Leland`) | Glyphes de partition | SIL OFL 1.1 (MuseScore) | Réutilisable (OFL : embarquable, licence à joindre). |
| Polices **Bravura**, **Gootville** | **Aucun** (non chargées) | SIL OFL 1.1 | Bravura possible à la place de Leland ; Gootville à supprimer. |
| Soundfont piano « SalC5Light2 » (téléchargée) | Piano | Salamander Grand Piano : CC BY 3.0 (Alexander Holm) — version allégée redistribuée par l'ancien projet | Réutilisable avec attribution, mais à **reconstruire** en `.sf2` depuis la source officielle. |
| Soundfont « FluidR3 GM » (téléchargée) | 127 autres instruments | MIT (Frank Wen) | Réutilisable ; ~140 Mo en `.sf2` → voir §6. |
| Fixtures `tests/mscore-meta` | Tests | Ancien projet (GPL-3.0), données factuelles | Régénérer nos propres attendus. |

---

## 6. Points ambigus, bugs et recommandations

Légende : **Garder** (réimplémenter tel quel), **Adapter** (garder l'intention, changer le comportement), **Supprimer**, **Nouveau** (absent de l'original, demandé dans la mission).

### 6.1 Écrans et fonctionnalités

| # | Sujet | Constat | Reco |
|---|---|---|---|
| 1 | Accueil vitrine | Marketing pur. | **Supprimer** ; ouverture sur la bibliothèque, écran de bienvenue au 1er lancement (Phase 7). |
| 2 | Page About | Marketing, roadmap, liens affiliés. | **Supprimer** ; « À propos de Pianissimac » standard + fenêtre « Mentions » (attributions). |
| 3 | Aperçu de morceau (modale) | Utile (écoute, nb pistes/notes). | **Adapter** en panneau détail de la `NavigationSplitView` (aperçu animé, métadonnées, progression, bouton Jouer). |
| 4 | Entraînement de vitesse | Inaccessible (bug de route), minimal, avance même sur erreur, réglages inaccessibles. | **Adapter** en exercice « Lecture de notes » : séries de N notes, clé Sol/Fa/les deux, armure, tessiture, mode « attendre la bonne note », chrono et notes/min ; historique. |
| 5 | Phrases (folk irlandais) | Non lié dans la nav, assets de licence inconnue, noms E/D inversés, niveau 0 = niveau 3 en aléatoire, recalage sur la 1re note au lieu du début de mesure. | **Adapter** : générateur procédural réécrit (progressions d'accords + motifs rythmiques générés), assets propres. |
| 6 | Jeu libre | Utile. | **Garder** (clavier + notes montantes). |
| 7 | Enregistrement + aperçu | Utile. | **Garder** ; enregistrer dans la bibliothèque (« Mes enregistrements ») + export `.mid`. |
| 8 | Partage par URL base64 | Web. | **Supprimer** (remplacé par export de fichier / menu Partager natif). |
| 9 | Export MP3 | Encodeur WASM. | **Adapter** : export **M4A (AAC)** ou WAV via rendu hors ligne `AVAudioEngine` (pas d'encodeur MP3 natif sur macOS). *Question ouverte : garder cette fonctionnalité ?* |
| 10 | 128 instruments GM | Nécessite une soundfont GM complète (≈ 30–140 Mo). | **Adapter** : piano de qualité + une petite sélection (piano électrique, clavecin, orgue, cordes, …) via une GM compacte à licence permissive ; ou GM complète. *Décision Phase 1.* |
| 11 | Sortie MIDI matérielle | Fonctionne, mais renvoie aussi les notes de l'utilisateur (risque de boucle/double son). | **Adapter** : option « Jouer le morceau sur un instrument MIDI externe », ne renvoyer que les notes du morceau. |
| 12 | Interrupteur « This Device » | Coupe tout l'audio interne. | **Adapter** : réglage « Son interne » dans Réglages > Audio. |
| 13 | Clavier d'ordinateur → notes | Utile sans clavier MIDI mais conflit potentiel avec les raccourcis. | **Adapter** : option activable (« Utiliser le clavier du Mac comme piano »), désactivée par défaut si un clavier MIDI est connecté. |
| 14 | Clic sur le clavier dessiné | Utile. | **Garder**. |
| 15 | Glisser pour défiler | Pensé tactile. | **Adapter** : molette/trackpad + glisser. |
| 16 | Wake lock | Web. | **Adapter** (assertion système pendant la lecture). |
| 17 | Dossiers locaux | API Chromium, non récursif, titre = nom de fichier. | **Adapter** : dossier surveillé (bookmark), récursif optionnel, MIDI + MusicXML, métadonnées éditables (Phase 8). |
| 18 | Fenêtre de stats flottante | Utile mais éphémère. | **Adapter** : stats dans l'inspecteur + **bilan de fin de session** + historique persistant. |
| 19 | Score combiné | `durationHeld` incrémenté par tick (dépend de la machine), affiché seulement en phrases. | **Adapter** : durée tenue en secondes ; score affiché partout ou supprimé. *À trancher.* |
| 20 | Difficulté | Champ jamais renseigné. | **Adapter** : heuristique (notes/s, polyphonie, étendue, altérations) + édition manuelle. |
| 21 | Favoris, Récents, Importés, Progression | Absents. | **Nouveau** (Phase 7). |
| 22 | Mode « écoute » | Implicite (aucune main sélectionnée ⇒ morceau joué, rien à valider, mais aussi rien n'est affiché). | **Nouveau/Adapter** : mode explicite « Écouter » (toutes notes affichées, pas d'évaluation). |
| 23 | Option `skipMissedNotes` | Définie mais jamais appliquée (ligne commentée) : « ne faire sonner les notes de la main active que si l'utilisateur les a jouées ». | **Adapter** : réglage « Ne pas jouer ma partie » (couper la main active) — très demandé en pédagogie. |
| 24 | Pédale de sustain | Ignorée (entrée et fichiers). | **Nouveau** : CC64 sur le retour sonore et à la lecture des fichiers. |
| 25 | Latence | Aucune compensation (`outputLatency` commenté). | **Nouveau** : compensation automatique de la latence de sortie + réglage manuel de décalage. |
| 26 | Détection à chaud MIDI | Absente (bouton « Refresh »). | **Nouveau** (CoreMIDI notifications). |

### 6.2 Bugs et comportements discutables du moteur et du rendu

| # | Constat | Reco |
|---|---|---|
| B1 | Vitesse non bornée avec `+`/`−` (peut atteindre 0 ou négatif). | Borner 10 %–200 % (pas 5 %). |
| B2 | « Restart » sans boucle appelle `stop()` qui supprime la boucle côté moteur, alors que le réglage reste « activé » (désynchronisation). | Restart = retour au début (de la boucle si active) + stats à zéro, sans toucher à la boucle. |
| B3 | Mode attente : jouer une note d'une piste non active (autre main) au même instant la valide. | Ne valider que les notes de la main active. |
| B4 | `enRetard` indexé par hauteur : notes répétées rapides écrasées. | Indexer par note. |
| B5 | `mesureÀ(t)` avant la 1re mesure renvoie la **dernière** mesure. | Renvoyer la première. |
| B6 | Plusieurs pistes sur la même main : seule la dernière est évaluée, toutes sont affichées. | Ensemble de pistes par main. |
| B7 | Fichier à une piste : pas de main gauche ; la piste entière est « main droite ». | Proposer une séparation par point de partage (défaut Do4, ou algorithme de suivi de voix) ; choix manuel dans l'inspecteur. |
| B8 | Métronome : chiffrage principal uniquement ; son d'accent chargé mais inutilisé. | Suivre les changements de chiffrage ; son d'accent distinct. |
| B9 | Partition : toute altération autre que `#` est dessinée comme un bémol, donc un **bécarre** de la table d'orthographe s'affiche comme un **bémol** ; aucune altération n'est « annulée » dans la mesure. | Altérations correctes (♯, ♭, ♮), et gestion d'état d'altération par mesure. |
| B10 | Partition : chiffrage limité à des nombres d'un chiffre (12/8 impossible). | Composer les glyphes chiffre par chiffre. |
| B11 | Partition : pas de barres de mesure, de figures, de silences, de ligatures. | **Adapter** selon la mission (Phase 6) : barres de mesure, chiffrage, altérations, figures et ligatures de base à partir d'une **quantification** des notes MIDI (ou des données MusicXML). Garder le mode « traînes » comme variante simplifiée ? *À trancher.* |
| B12 | Rendu notes qui tombent : toujours 88 touches sur desktop. | Option « 88 touches / tessiture du morceau ». |
| B13 | Vitesse de défilement liée au temps morceau : à 50 % les notes tombent deux fois moins vite et paraissent plus serrées. | Garder (cohérent), proposer un réglage de zoom vertical. |
| B14 | Réglages persistés sous l'id seul (collision possible). | Clé = identifiant unique de morceau. |
| B15 | Vitesse non persistée et partagée entre morceaux. | Persister par morceau (avec la progression). |
| B16 | MusicXML : temps arrondis à 10 ms, divisions uniques, main par clé. | Réécriture (§4.2). |
| B17 | Retour sonore utilisateur toujours au piano, non affecté par le volume. | Instrument et volume du retour réglables. |
| B18 | Une note rejouée avant la fin de la précédente laisse l'ancienne voix sonner. | Gestion de voix correcte (`AVAudioUnitSampler` s'en charge). |
| B19 | Enregistrement : notes tenues à l'arrêt perdues. | Les clore à l'instant de l'arrêt. |
| B20 | Titres intégrés en une seule chaîne « Titre - Compositeur », attributions erronées (Ode to Joy). | Champs séparés titre / compositeur, corrigés. |

### 6.3 Questions à trancher en Phase 1

1. **Instruments** : piano seul, petite sélection, ou GM complet (taille du bundle) ?
2. **Export audio** (M4A/WAV) : garder ?
3. **Partition** : notation rythmique quantifiée (plus ambitieux) vs mode « traînes » amélioré, ou les deux ?
4. **Score** combiné : l'afficher, le redéfinir, ou ne garder que précision + série ?
5. **Exercices** : périmètre (Lecture de notes + Phrases procédurales) ; besoin d'autres types (gammes, accords, intervalles) ?
6. **Clavier du Mac comme piano** : à garder ?
7. **Langue des noms de notes par défaut** : Do-Ré-Mi en français, C-D-E en anglais ?

### 6.4 Décisions validées (après la Phase 0)

| Question | Décision |
|---|---|
| Instruments | **Piano seul.** Clavier de l'utilisateur : Arturia branché en MIDI. |
| Export audio | **Non** (pas d'export MP3/M4A). |
| Partition | **Les deux** : partition rythmique (vraie notation) **et** mode simplifié amélioré. |
| Score combiné | **Conservé** tel quel (parfait×100 + bien×50 − erreur×25 + durée tenue). |
| Exercices | **Lecture de notes** + **phrases générées** uniquement. |
| Clavier du Mac comme piano | **Conservé, en option.** |
| Noms de notes | **Do, Ré, Mi, Fa, Sol, La, Si** par défaut. |
| Mode Attendre | Tolérance réglable (0,25 s par défaut) ; une fois dépassée, le curseur revient en douceur juste avant la note attendue. |
| Visualisations | Notes qui tombent, partition simplifiée, partition rythmique, **partition complète** (page avec retours à la ligne et curseur). |
| Volume | Volume général de l'app + piano de l'utilisateur, morceau et métronome, réglables depuis le lecteur. |
| Doigtés | **Oui** : lire les doigtés présents dans les MusicXML, puis suggestions automatiques (calcul hors ligne, désactivable). |
| Banques de partitions | **Liens vers des sources libres** (Mutopia, piano-midi.de, OpenScore) ouverts dans le navigateur, puis import ; pas d'accès réseau dans l'app. |
| Système et design (après la Phase 9) | **macOS 26 Tahoe minimum**, interface **Liquid Glass** (barre de lecture flottante, barres d'outils en verre, icône en verre). |
| Partitions en PDF (après la Phase 9) | **Export PDF** (⇧⌘E) et **impression** (⌘P) de la partition d'un morceau, en notation rythmique sur A4. Sandbox : fichiers choisis en lecture-écriture, droit d'impression. |

---

## 7. Annexes

### 7.1 Orthographe des notes selon l'armure (index = hauteur mod 12, de Do à Si)

| Armure | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| C | C | C# | D | D# | E | F | F# | G | G# | A | A# | B |
| G | C | C# | D | D# | E | F♮ | F | G | G# | A | A# | B |
| D | C♮ | C | D | D# | E | F♮ | F | G | G# | A | A# | B |
| A | C♮ | C | D | D# | E | F♮ | F | G♮ | G | A | A# | B |
| E | C♮ | C | D♮ | D | E | F♮ | F | G♮ | G | A | A# | B |
| B | C♮ | C | D♮ | D | E | F♮ | F | G♮ | G | A♮ | A | B |
| F# | C♮ | C | D♮ | D | E♮ | E | F | G♮ | G | A♮ | A | B |
| C# | B | C | D♮ | D | E♮ | E | F | G♮ | G | A♮ | A | B♮ |
| F | C | D♭ | D | E♭ | E | F | G♭ | G | A♭ | A | B | B♮ |
| Bb, Eb, Ab, Db | C | D♭ | D | E♭ | E | F | G♭ | G | A♭ | A | B♭ | B |
| Gb, Cb | C♭ | D♭ | D | E♭ | E | F | G♭ | G | A♭ | A | B♭ | B |

Lecture : la convention est d'écrire **sans altération** une note déjà altérée par l'armure, et avec bécarre la note naturelle correspondante. Ex. en Sol, la touche noire « F#/Gb » s'écrit `F` (le dièse est porté par l'armure) et la touche blanche Fa s'écrit `F♮`. Seules les lignes C, tonalités à dièses et F suivent cette convention ; les lignes Bb à Cb écrivent les bémols explicitement (`B♭`, `E♭`…) et Gb/Cb nomment `C♭` la touche Do au lieu de la touche Si. **→ Pianissimac :** recalculer proprement l'orthographe à partir de l'armure (degrés + altérations), sans table figée.

Armures (altérations dans l'ordre) : dièses F C G D A E B (G=1 … C#=7) ; bémols B E A D G C F (F=1 … Cb=7). Correspondance « quintes » MIDI : −7 Cb … 0 C … +7 C#.

Transposition d'armure : décaler la classe de hauteur de la tonique, garder la préférence dièses/bémols de l'armure d'origine quand une variante existe (Db/C#, Gb/F#, Cb/B), sinon la variante par défaut (C, C#, D, Eb, E, F, F#, G, Ab, A, Bb, B). Transposition de note : bornée à 0…127.

### 7.2 Couleurs

| Usage | Valeur |
|---|---|
| Main droite (touche blanche / noire) | `#7b5ff0` / `#5b3ad6` |
| Main gauche (touche blanche / noire) | `#f08a5b` / `#d1642e` |
| Fond notes qui tombent | `#0f1014` |
| Feutre / barre grise | `#7f1d2f` / `#1b1d25` |
| Touches blanches | `rgb(255,253,240)` |
| Touche enfoncée par l'utilisateur | gris |
| Ligne de jeu (partition) | violet `rgba(110,40,251,0.43)` avec ombre |
| Notes colorées | C `251,113,133` · D `251,146,60` · E `250,204,21` · F `74,222,128` · G `56,189,248` · A `99,102,241` · B `168,85,247` |
| Partition : note atteinte / réussie / manquée | `121,74,227` / `185,154,244` / `100,100,100` |

**→ Pianissimac :** nouvelle palette propre (identité, contraste, mode clair/sombre, daltonisme) ; ces valeurs ne servent qu'à comprendre les rôles.

### 7.3 Clavier d'ordinateur → notes (vélocité 80)

| Touches | Notes |
|---|---|
| `Z X C V B N M` | Do3 Ré3 Mi3 Fa3 Sol3 La3 Si3 |
| `S D G H J` | Do♯3 Ré♯3 Fa♯3 Sol♯3 La♯3 |
| `Q W E R T Y U` | Do4 … Si4 |
| `2 3 5 6 7` | Do♯4 Ré♯4 Fa♯4 Sol♯4 La♯4 |
| `↑` / `↓` | décalage ± 2 octaves (borné −4…+4), relâche les notes en cours |

Positions physiques (codes de touche), indépendantes de la disposition AZERTY/QWERTY. Répétition automatique ignorée ; ignoré si ⌘, Ctrl ou Alt est enfoncé.

### 7.4 Raccourcis de l'écran de lecture

| Touche | Action |
|---|---|
| Espace | Lecture / pause |
| `,` / `.` | Reculer / avancer de 16 ms |
| ⇧`,` / ⇧`.` | Mesure précédente / suivante |
| `0` | Retour au début |
| `+` (`=`) / `−` | Vitesse ± 5 % |
| `[` / `]` | Main gauche / droite on-off |
| `;` | Mode attente on-off |
| ⇧`'` | Basculer notes qui tombent / partition |
| `/` | Afficher / masquer les stats |
| `P` | Boucle on-off |
| `O` | Aller au début de la boucle |
| `←` / `→` | Début de boucle − / + 1 mesure |
| Ctrl `←` / Ctrl `→` | Fin de boucle − / + 1 mesure |

**→ Pianissimac :** reprendre l'esprit, aligné sur les conventions macOS et exposé dans la barre de menus (Phase 7).

### 7.5 Constantes

| Constante | Valeur |
|---|---|
| Fenêtre « Parfait » | 50 ms (temps réel) |
| Fenêtre « Bien » / délai avant « Manqué » | 300 ms (temps réel) |
| Défilement | 225 px / s de temps morceau |
| Tempo par défaut | 120 BPM |
| Chiffrage par défaut | 4/4 |
| Pas de vitesse au clavier | 0,05 |
| Préréglages de vitesse | 0,25 · 0,5 · 0,75 · 1 · 1,25 · 1,5 · 1,75 · 2 |
| Métronome : volumes | 0,3 · 0,6 · 0,85 |
| Métronome : vitesses | 0,25 · 0,5 · 1 · 2 · 4 |
| Métronome : notes | 75 (temps), 90 (accent), woodblock GM |
| Seuil d'anacrouse (décompte) | mesure < 75 % de la suivante |
| Relâchement du synthé | 0,5 s (rampe exponentielle) |
| Portée | 80 px pour 5 lignes, interligne 20 px |
| Clavier | hauteur blanche = min(5 × largeur, 250 px), noire = 2/3 |
