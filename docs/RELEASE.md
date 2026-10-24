# Publier MyPiano

MyPiano est distribué hors Mac App Store, sous forme d'image disque (`.dmg`) signée avec un certificat
**Developer ID Application**, notarisée par Apple et agrafée. Les étapes de signature et de notarisation se
font sur ton Mac, avec ton compte Apple Developer ; aucun secret n'est stocké dans le dépôt.

## Prérequis (une seule fois)

1. **Xcode** (15 ou plus récent) et **XcodeGen** (`brew install xcodegen`).
2. Un certificat **Developer ID Application** dans le trousseau
   (Xcode → Réglages → Comptes → Gérer les certificats → « + » → Developer ID Application).
   Vérification :

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

3. Ton **Team ID** (10 caractères, visible sur developer.apple.com → Membership).
4. Un **mot de passe d'app** (appleid.apple.com → Connexion et sécurité → Mots de passe d'app), enregistré une
   fois pour `notarytool` dans le trousseau :

   ```bash
   xcrun notarytool store-credentials MyPiano-notary --apple-id "ton@email" --team-id ABCDE12345
   ```

## 1. Préparer la version

- Mettre à jour `MARKETING_VERSION` (ex. `1.0.0`) et incrémenter `CURRENT_PROJECT_VERSION` dans `project.yml`,
  puis régénérer le projet : `scripts/generate-project.sh`.
- Vérifier que les garde-fous passent :

  ```bash
  scripts/check-legacy-traces.sh
  xcodebuild test -scheme MyPiano -destination 'platform=macOS'
  ```

## 2. Construire l'app signée

```bash
TEAM_ID=ABCDE12345 scripts/build-release.sh
```

Le script archive le schéma `MyPiano` en Release (`build/release/MyPiano.xcarchive`), signe avec
« Developer ID Application », runtime renforcé et horodatage, puis exporte `dist/MyPiano.app`.
Sans `TEAM_ID`, il produit une app signée *ad hoc* : utile pour tester localement, **pas pour la distribuer**.

Puis le contrôle hors ligne, sur l'app construite :

```bash
scripts/check-offline.sh dist/MyPiano.app
```

Il vérifie l'absence d'entitlement réseau (projet et app signée), l'absence d'API réseau dans les sources et
qu'aucune URL autre que les trois sources de partitions de `ScoreSourcesView.swift` n'est présente dans le binaire.

## 3. Créer l'image disque

```bash
SIGN_IDENTITY="Developer ID Application: Julien Marchadier (ABCDE12345)" scripts/make-dmg.sh
```

Résultat : `dist/MyPiano-<version>.dmg`, avec `MyPiano.app` et un lien vers `/Applications` pour l'installation
par glisser-déposer. `SIGN_IDENTITY` est facultatif mais recommandé (Gatekeeper vérifie alors aussi l'image).

## 4. Notariser

```bash
xcrun notarytool submit dist/MyPiano-1.0.0.dmg --keychain-profile MyPiano-notary --wait
```

La notarisation couvre l'image et l'app qu'elle contient. En cas de statut `Invalid`, lire le journal :

```bash
xcrun notarytool log <submission-id> --keychain-profile MyPiano-notary
```

Causes fréquentes : signature *ad hoc* (pas de `TEAM_ID`), runtime renforcé désactivé, horodatage absent.

## 5. Agrafer et vérifier

```bash
xcrun stapler staple dist/MyPiano-1.0.0.dmg
xcrun stapler validate dist/MyPiano-1.0.0.dmg
spctl --assess --type open --context context:primary-signature --verbose dist/MyPiano-1.0.0.dmg
```

L'agrafage joint le ticket de notarisation à l'image : Gatekeeper l'accepte même hors ligne. Après avoir
monté l'image et copié l'app dans `/Applications` :

```bash
spctl --assess --type execute --verbose /Applications/MyPiano.app
```

doit afficher `accepted` et `source=Notarized Developer ID`.

## 6. Publier

Joindre `dist/MyPiano-<version>.dmg` à une release GitHub (étiquette `v<version>`). `dist/`, `build/` et
`*.dmg` sont ignorés par git.

## Récapitulatif

| Étape | Commande | Qui |
|---|---|---|
| Tests | `xcodebuild test -scheme MyPiano -destination 'platform=macOS'` | script |
| Garde-fous | `scripts/check-legacy-traces.sh`, `scripts/check-offline.sh` | script |
| Build signé | `TEAM_ID=… scripts/build-release.sh` | toi (certificat) |
| Image disque | `SIGN_IDENTITY=… scripts/make-dmg.sh` | toi (certificat) |
| Notarisation | `xcrun notarytool submit … --wait` | toi (compte Apple) |
| Agrafage | `xcrun stapler staple …` | toi |
