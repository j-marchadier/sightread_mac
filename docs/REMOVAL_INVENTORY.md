# Inventaire des éléments retirés du produit

Tout ce qui suit appartenait à l'application web d'origine, qui n'a servi que de spécification fonctionnelle.
Son code a été rangé en lecture seule dans `reference/web/` pendant la réécriture, puis **supprimé du dépôt en
Phase 9**. Aucun de ces éléments n'est repris dans Pianissimac.

Deux scripts servent de garde-fou avant chaque publication :

- `scripts/check-legacy-traces.sh` vérifie qu'aucun nom, domaine ou identifiant de suivi de l'ancien produit
  n'apparaît dans le dépôt, hors `ACKNOWLEDGEMENTS.md` (qui crédite l'inspiration GPL-3.0) ;
- `scripts/check-offline.sh` vérifie l'absence d'entitlement réseau, d'API réseau dans les sources et d'URL
  inattendue dans le binaire (voir `docs/RELEASE.md`).

Le nom, le domaine et la société de l'ancien produit ne sont cités que dans `ACKNOWLEDGEMENTS.md`.

## 1. Tracking et appels réseau à des services tiers

| Élément retiré | Remplacement dans Pianissimac |
|---|---|
| Google Analytics (script de suivi, mesure d'audience des pages et événements) | Aucun : aucune télémétrie |
| Variable d'environnement de l'identifiant de suivi | Aucune |
| Téléchargement des soundfonts depuis un dépôt GitHub au moment du build | Échantillons de piano embarqués dans le bundle |
| Chargement réseau des instruments, morceaux, images et effets sonores | Tout est embarqué ; aucun entitlement réseau |

## 2. Identité de l'ancien produit

| Élément retiré | Remplacement dans Pianissimac |
|---|---|
| Nom, titre, auteur, variables CSS au nom du produit | « Pianissimac », © Julien Marchadier |
| Logo, favicon, icônes PWA, manifest PWA | Icône macOS dédiée (`Assets.xcassets/AppIcon`) |
| Domaine web, `robots.txt`, `sitemap.txt`, balises Open Graph et Twitter, captures marketing | Aucun |
| Liens GitHub, YouTube, e-mail de contact, copyright de l'ancienne société | Fenêtres « À propos » et « Mentions » de l'app |
| Config d'hébergement, workflow CI, robot de mises à jour de dépendances | Supprimés (Phase 2) |
| Outillage web : Bun (`bun.lockb`), `package.json`, Vite, PostCSS, Tailwind, Prettier, TypeScript, React Router | Supprimés avec `reference/web/` (Phase 9) ; build Xcode + SwiftPM |

## 3. Discours marketing

| Élément retiré |
|---|
| Page d'accueil (accroches, « pourquoi ce produit », aperçu) |
| Pied de page marketing |
| Page À propos (présentation, « free and open-source », compatibilité navigateurs, roadmap, liens affiliés Amazon) |
| README et guide de contribution d'origine (« private development phase », « free forever », politique de contributions) |

## 4. Fonctionnalités purement web

| Élément | Remplacement dans Pianissimac |
|---|---|
| Wake lock navigateur | Assertion système pendant la lecture |
| File System Access API, IndexedDB, permissions | Dossier surveillé (bookmark security-scoped) |
| Partage par URL base64 | Aucun |
| Enregistrement du jeu, export MIDI/MP3 (encodeur WASM) | **Aucun (décision : pas d'enregistrement)** |
| Tactile mobile, détection iOS/Android, correctif AudioContext iOS, menu responsive | Trackpad/souris |
| 127 instruments General MIDI | **Piano seul (décision)** |
| Sortie MIDI matérielle | Aucune |

## 5. Assets écartés

| Asset | Raison |
|---|---|
| Phrases irlandaises (70 MIDI + 11 MP3) | Licence inconnue ; phrases remplacées par un générateur procédural |
| Effet sonore « mauvaise note » (MP3) | Licence inconnue ; son synthétisé par l'app |
| Images des touches noires (PNG) | Graphismes de l'ancien projet ; rendu vectoriel |
| *Swan Lake* (MIDI) | Provenance non vérifiable (URL source identique à celle du *Minuet in G*) — retiré (décision) |
| Polices Bravura et Gootville | Inutilisées (seule Leland est reprise) |
| Fiches de référence MuseScore des tests | Remplacées par nos propres attendus (`Packages/PianissimacKit/Tests`) |

## 6. Vérification (Phase 9)

- `reference/web/` supprimé ; plus aucun fichier Bun, Node, Vite, PostCSS ou Tailwind dans le dépôt.
- `scripts/check-legacy-traces.sh` : vert, seul `ACKNOWLEDGEMENTS.md` est autorisé.
- `scripts/check-offline.sh` : vert.
