# HowTo: Sauvegarder une page web en HTML autonome avec Chromium en mode headless (snap) + Monolith (snap) + Firejail

18/juin/2025
J'ai voulu scraper les élements d'un site en mode headless grace à chromium, je voulais uniqument certains éléments (images et texte afférents) sans récuperer tout le javascript, vidéos ...  mais je me suis heurté à des hordes d'erreurs liées à la configuratin de ma station de travail Lubuntu integrant Firejail.
Dans le passé j'avais déja réalisé des tests de scraping headless mais il avait été obligatoire de passer par une VM autonome sans firejail, sans utiliser des paquets installé via snap direct via les sources  ... c'était fonctionel mais long et pénible j'avais été direct à la solution sans trop me poser de questions ...
En 2025 il devient de plus en plus "compliqué" d'esquiver SNAP et puis c'est pas franchement judicieux de s'en priver vu la qualité et les possiblités du produit ... j'ai donc décidé de consacrer quelques heures à comprendre comment mieux faire communiquer les différents environnements de mes paquets Snap avec Firejail sur mon hote Lubuntu et d'en faire un mini howto.
Le but de ce howto et de capitaliser pour que la prochaine fois même si c'est dans un environement diférent (docker, VM ...) le but est depouvoir  opter pour la meuileure stratégie selon le contexte.


## Contexte & environnement de travail et tests :
- Station Lubuntu :
  ```
  NAME="Ubuntu"
  VERSION="20.04.6 LTS (Focal Fossa)"
  ID=ubuntu
  ID_LIKE=debian
  PRETTY_NAME="Ubuntu 20.04.6 LTS"
  VERSION_ID="20.04"
  HOME_URL="https://www.ubuntu.com/"
  SUPPORT_URL="https://help.ubuntu.com/"
  BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
  PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
  VERSION_CODENAME=focal
  UBUNTU_CODENAME=focal
  ```
- Linux lenovo2 5.4.0-212-generic #232-Ubuntu SMP Sat Mar 15 15:34:35 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux
- Informations du package Snap installé via apt intall  :
  ```Version: 2013-11-29-9
  Priority: extra
  Section: universe/science
  Origin: Ubuntu
  Maintainer: Ubuntu Developers <ubuntu-devel-discuss@lists.ubuntu.com>
  Original-Maintainer: Debian Med Packaging Team <debian-med-packaging@lists.alioth.debian.org>
  Bugs: https://bugs.launchpad.net/ubuntu/+filebug
  Installed-Size: 2 714 kB
  Depends: libc6 (>= 2.14)
  Homepage: https://www.psc.edu/index.php/user-resources/software/snap
  Download-Size: 376 kB
  APT-Sources: http://archive.ubuntu.com/ubuntu focal/universe amd64 Packages
  Description: location of genes from DNA sequence with hidden markov model
  SNAP is a general purpose gene finding program suitable for both eukaryotic and prokaryot
  ```
- Packages
- chromium           137.0.7151.103                   3169      latest/stable    canonical✓  Snaps :
- monolith           v2.10.1                          791       latest/stable    popey✪           -


# Problèmes résolus :
N°1 Conflits Firejail avec le snap Chromium
N°2 Erreurs GPU/libva en mode headless
N°3 Permissions insuffisantes pour Monolith
N°4 Syntaxe complexe de la ligne de commande


## 1. Installation des composants

```
sudo snap install chromium
sudo snap install monolith
```

## 2. Configuration des permissions Monolith

```
sudo snap connect monolith:removable-media
sudo snap connect monolith:home
```

## 3. Commandes de test

### Option 1: Utilisation directe de Monolith (pour pages statiques):

```
monolith https://www.jp-petit.org/science/scientific_summary.htm \
  -I -b "www.jp-petit.org" \
  -o scientific_summary.html
```

### Option 2: Combo Chromium + Monolith (pour pages dynamiques):

```
chromium --headless --dump-dom "https://www.jp-petit.org/science/scientific_summary.htm" \
  --no-sandbox \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-features=UseOzonePlatform,UseSkiaRenderer,VaapiVideoDecoder \
  --use-gl=disabled \
  --disable-dev-shm-usage \
  --virtual-time-budget=20000 | \
monolith - -I -b "www.jp-petit.org" -o scientific_summary.html
```

## 4. Script d'automatisation (save_web_page.sh)

```
#!/bin/bash

# Usage: ./save_web_page.sh <URL> <output-file.html>

set -e

URL="$1"
OUTPUT="$2"

if [ -z "$URL" ] || [ -z "$OUTPUT" ]; then
  echo "Usage: $0 <URL> <output-file.html>" >&2
  exit 1
fi

# Extraire le domaine de base
DOMAIN=$(echo "$URL" | awk -F/ '{print $3}')

echo "Processing $URL..." >&2
chromium --headless --dump-dom "$URL" \
  --no-sandbox \
  --disable-gpu \
  --virtual-time-budget=30000 \
  --disable-software-rasterizer \
  --disable-features=UseOzonePlatform,UseSkiaRenderer,VaapiVideoDecoder \
  --use-gl=disabled \
  --disable-dev-shm-usage | \
monolith - -I -b "$DOMAIN" -o "$OUTPUT"

echo "Saved to $OUTPUT" >&2
```

Rendre le script exécutable: ```chmod +x save_web_page.sh```

Exemple d'utilisation:  ``` ./save_web_page.sh "https://www.jp-petit.org/science/scientific_summary.htm" "page_sauvegardee.html" ```

## 5. Paramètres clés expliqués

Paramètre (Chromium)	Description
--headless	Mode sans interface
--dump-dom	Récupère le DOM après rendu
--no-sandbox	Désactive le sandbox (nécessaire en headless)
--disable-gpu	Évite les erreurs liées au GPU
--virtual-time-budget	Temps d'attente pour le rendu (ms)
--disable-features	Désactive les fonctionnalités problématiques

Paramètre (Monolith)	Description
-	Lit depuis l'entrée standard
-I	Intègre les images en base64
-b	Définit l'URL de base pour les ressources
-o	Fichier de sortie


## 6. Dépannage rapide

Problème: Erreurs de permission Monolith

```sudo snap connections monolith

# Doit montrer home et removable-media:connected :
# [sudo] Mot de passe de (votre login) : 
# Interface        Connecteur                Prise             Notes
# home             monolith:home             :home             -
# network          monolith:network          :network          -
# removable-media  monolith:removable-media  :removable-media  manual
```

## 7. En cas d'érreurs GPU persistantes, ajoutez ces flags supplémentaires à Chromium:

```
  --disable-accelerated-2d-canvas \
  --disable-gpu-compositing \
  --disable-webgl \
```

## 8. Alternative: Génération PDF (sans Monolith) permet de confirmer que le headless de chromium fonctione corectement

```
/snap/bin/chromium --headless --print-to-pdf "https://www.example.com" --no-sandbox --disable-gpu
```

Pourquoi cette solution fonctionne :
1. Contournement de Firejail en utilisant directement ```/snap/bin/chromium```
2. Désactivation complète des fonctionnalités GPU problématiques
3. Permissions étendues pour Monolith via les interfaces snap
4. Flux de données propre entre Chromium et Monolith via les pipes

----

Cette méthode permet de sauvegarder fidèlement des pages web complexes avec tout le contenu filtré par monolith dans un seul fichier HTML, idéal pour l'archivage ou la consultation hors ligne.
