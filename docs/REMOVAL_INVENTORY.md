# Inventaire des éléments retirés du produit

Tout ce qui suit appartient à l'application web d'origine, désormais rangée en lecture seule dans `reference/web/`
(supprimée en Phase 9). Aucun de ces éléments n'est repris dans MyPiano. Le script
`scripts/check-legacy-traces.sh` vérifie automatiquement qu'aucune trace ne réapparaît hors des fichiers autorisés.

## 1. Tracking et appels réseau à des services tiers

| Élément | Emplacement (sous `reference/web/`) |
|---|---|
| Google Analytics (gtag.js, `googletagmanager.com`), fonctions `pageview`/`event` | `src/features/analytics/index.ts`, `src/pages/root.tsx`, `src/ambient-types.d.ts` |
| Variable d'environnement `VITE_PUBLIC_GA_ID` | `src/features/analytics/index.ts`, ancien workflow CI |
| Téléchargement des soundfonts depuis `github.com/sightread/soundfonts` | `scripts/download-soundfonts.ts`, `package.json` (`predev`, `prebuild`) |
| Chargement réseau des instruments (`/soundfonts/…`) | `src/features/synth/loadInstrument.ts` |
| Chargement réseau des morceaux, images et sons | `src/features/data/index.tsx`, `src/features/theory/procedural.ts`, `src/features/SongVisualization/images.ts`, `src/pages/training/sound-effects.ts` |

MyPiano n'a **aucun** entitlement réseau : tout est embarqué.

## 2. Identité de l'ancien produit

| Élément | Emplacement |
|---|---|
| Nom « Sightread » / « SIGHTREAD », titre, auteur | `src/pages/root.tsx`, `src/components/AppBar.tsx`, `package.json`, `src/styles/global.css` (variable CSS) |
| Logo | `src/icons/Logo.tsx`, `public/images/logo.png` |
| Favicon et icônes PWA | `public/favicon.ico`, `public/icon-192.png`, `public/icon-512.png` |
| Manifest PWA | `src/pages/manifest.json` |
| Domaine `sightread.dev` | `src/pages/root.tsx`, `public/robots.txt`, `public/sitemap.txt` |
| Balises Open Graph / Twitter, captures marketing | `src/pages/root.tsx`, `public/images/mode_falling_notes_screenshot.png`, `mode_sheet_hero_*.png` |
| `robots.txt`, `sitemap.txt` | `public/` |
| Liens GitHub, YouTube, e-mail de contact | `src/components/AppBar.tsx`, `src/pages/about/page.tsx`, `README.md`, `CONTRIBUTING.md` |
| Copyright « Sightread Studio, LLC » | `src/components/MarketingFooter.tsx` |
| Config Vercel (`.vercelignore`) | **supprimée** (Phase 2) |
| Workflow GitHub `validate.yml` | **supprimé** (Phase 2) |
| Renovate (`renovate.json`) | **supprimé** (Phase 2) |
| Prettier, Vite, PostCSS, Tailwind, TypeScript, Bun (`bun.lockb`, `package.json`) | déplacés dans `reference/web/` |

## 3. Discours marketing

| Élément | Emplacement |
|---|---|
| Page d'accueil (accroches, « Why Sightread », aperçu) | `src/pages/home/` |
| Pied de page marketing | `src/components/MarketingFooter.tsx` |
| Page À propos (présentation, « free and open-source », compatibilité navigateurs, roadmap, feedback, liens affiliés Amazon) | `src/pages/about/` |
| README : « private development phase », « free forever », politique de contributions | `README.md`, `CONTRIBUTING.md` |

## 4. Fonctionnalités purement web

| Élément | Emplacement | Remplacement dans MyPiano |
|---|---|---|
| Wake lock navigateur | `src/features/wakelock/`, `src/hooks/useWakeLock.tsx` | Assertion système pendant la lecture |
| File System Access API, IndexedDB, permissions | `src/features/persist/persistence.ts`, `src/pages/songs/components/AddFolderForm.tsx` | Dossier surveillé (bookmark security-scoped) |
| Partage par URL base64 | `src/pages/freeplay/components/RecordingModal.tsx`, `src/features/data/index.tsx` | Aucun |
| Enregistrement du jeu, export MIDI/MP3 (encodeur WASM) | `src/features/midi/index.tsx`, `src/features/audio/render-midi.ts`, `RecordingModal.tsx` | **Aucun (décision : pas d'enregistrement)** |
| Tactile mobile, détection iOS/Android, correctif AudioContext iOS, menu responsive | `src/components/Canvas.tsx`, `src/utils/index.tsx`, `src/features/synth/utils.ts`, `src/components/AppBar.tsx` | Trackpad/souris |
| 127 instruments General MIDI | `src/features/synth/instruments.ts`, `src/features/controls/PickInstrument.tsx` | **Piano seul (décision)** |
| Sortie MIDI matérielle | `src/features/midi/index.tsx` | Aucune |

## 5. Assets écartés

| Asset | Raison |
|---|---|
| `public/music/irish/` (70 MIDI + 11 MP3) | Licence inconnue ; phrases remplacées par un générateur procédural |
| `public/effects/wrong-sound-effect.mp3` | Licence inconnue ; son synthétisé par l'app |
| `public/images/black-key-*.png` | Graphismes de l'ancien projet ; rendu vectoriel |
| `public/music/songs/swan-lake.mid` | Provenance non vérifiable (URL source identique à celle du *Minuet in G*) — retiré (décision) |
| Polices Bravura et Gootville | Inutilisées (seule Leland est reprise) |
| Fixtures `tests/mscore-meta/` | Remplacées par nos propres attendus |
