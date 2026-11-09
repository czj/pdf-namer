# PDF Namer

Renomme vos PDF, scans, photos et captures d'écran d'après leur contenu, entièrement
sur votre Mac : modèle Apple sur l'appareil (FoundationModels) et OCR Vision. Rien ne
quitte la machine.

    Scan 20261109-140943.pdf  →  2026-11-09 - Reçu de paiement Le Petit Café - Repas - 45.80 EUR.pdf
    IMG_0877.jpeg             →  2026-11-03 - Photo - Couverture du livre L'océan d'amour.jpeg

Format : `DATE - Type Émetteur - Détail - MONTANT`. Le montant n'apparaît que pour les
factures, reçus, devis, avoirs, quittances et notes de frais. Photos et captures d'écran
prennent la date de prise de vue. Noms et prompts sont en français.

**Prérequis :** macOS 27 ou plus récent, Apple Intelligence activé
(Réglages → Apple Intelligence et Siri), Xcode 27 (Swift 6.4) pour compiler.

Écrit en Swift 6.4 en mode de langage Swift 6 (concurrence vérifiée par le compilateur),
avec Approachable Concurrency : l'app et la commande vivent sur l'acteur principal, le
rendu et l'OCR passent en `@concurrent`.

## L'app de barre de menus

- Déposez des fichiers (ou un dossier) sur le panneau, choisissez-les, ou collez-les avec ⌘V.
- Ajoutez des **dossiers surveillés** (Scans, Téléchargements…) : chaque nouveau PDF ou
  image qui y arrive est renommé tout seul, avec une notification.
- Chaque renommage peut être modifié ou annulé. L'option « Valider avant de renommer »
  attend votre accord pour les fichiers déposés.
- Les fichiers déjà nommés `AAAA-MM-JJ - …` ne sont jamais touchés.

## La commande `pdf-namer`

    pdf-namer facture.pdf                  # affiche le nom proposé
    pdf-namer facture.pdf --json
    pdf-namer --rename *.pdf               # renomme (avec sauvegarde)
    pdf-namer --rename --dry-run *.pdf     # simulation
    pdf-namer --rename --force *.pdf       # renomme aussi les fichiers déjà nommés
    pdf-namer --text scan.pdf              # ce que lit le modèle : texte, dates et montants candidats

## Sauvegardes et configuration

Avant chaque renommage, l'original est copié sous `RENAME BACKUP <date> - <nom>`
dans le dossier de sauvegarde, puis supprimé au bout de 6 mois.

L'app et la commande lisent deux fichiers dans `~/.config/pdf-namer/` (ou
`$XDG_CONFIG_HOME/pdf-namer/`) :

- **`config.json`** : la configuration commune, écrite à la main, à versionner avec ses
  dotfiles (chezmoi, stow…). L'app ne la modifie jamais, donc un `chezmoi apply` n'écrase
  rien.
- **`config.local.json`** : ce qui est propre à ce Mac. La fenêtre de réglages y écrit
  seulement les réglages qui diffèrent de `config.json`. À ne pas versionner.

Les clés de `config.local.json` remplacent celles de `config.json`, une par une. L'app
recharge toute seule quand l'un des deux change. Toutes les clés sont facultatives :

```json
{
  "backupDir": "~/Documents/Archives",
  "backupMaxAgeDays": 180,
  "expireMaxAgeDays": 548,
  "watchedFolders": [
    { "path": "~/Documents/Scans", "enabled": true },
    { "path": "~/Downloads", "enabled": false }
  ],
  "confirmBeforeRename": false
}
```

| Clé | Défaut | Rôle |
|---|---|---|
| `backupDir` | `~/Documents/PDF Namer/Originaux` | où sont copiés les originaux |
| `backupMaxAgeDays` | `180` | âge au-delà duquel les sauvegardes sont supprimées (`0` = jamais) |
| `expireMaxAgeDays` | `0` | met à la corbeille les **autres** fichiers du dossier de sauvegarde ajoutés depuis plus longtemps : pratique si ce dossier sert aussi de « à jeter plus tard » (`0` = jamais) |
| `watchedFolders` | `[]` | dossiers surveillés par l'app |
| `confirmBeforeRename` | `false` | fichiers déposés : attendre « Renommer » |

## Compiler

    scripts/build-app.sh               # build release, signe ad hoc, installe dans ~/Applications
                                       # et la commande dans ~/.local/bin
    scripts/build-app.sh --no-install  # seulement build/PDF Namer.app
    swift test

`DEVELOPER_DIR` pointe par défaut sur `/Applications/Xcode.app`. On peut aussi ouvrir
`Package.swift` dans Xcode.

## Origine

Portage d'un script Python personnel. `swift test` vérifie que les règles de nommage
(casse, nettoyage, montants, dates candidates, nom final) donnent exactement les mêmes
résultats que le script sur ~2 500 cas, enregistrés dans
`Tests/PDFNamerCoreTests/Fixtures/parity.json` par `tools/gen_parity.py`.
Seul écart voulu : l'OCR Vision tourne en mode précis.

## Licence

MIT
