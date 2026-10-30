# Création automatisée d'un template LXC Proxmox avec passthrough GPU (iGPU AMD / carte dédiée)



Date : 23 octobre 2026

OS : proxmox 9.2

Autheur : Yannick SUDRIE



## 📋 Table des matières

- À propos

- Fonctionnalités

- Prérequis

- Installation

- Utilisation

- Options

- Ce que fait le script

- Exemples

- Workflow recommandé

- Codes de sortie

- Dépannage

- Détails techniques

- Documentation associée

- Contribution

- Licence

---

## 🎯 À propos

Ce script Bash automatise la création d'un **conteneur LXC non privilégié** sur Proxmox VE, configuré avec le **passthrough GPU** (iGPU AMD Radeon ou carte dédiée) via `cgroup2` et bind mounts, puis converti en **template golden image** prêt à être cloné.

Il résout les problèmes récurrents rencontrés lors de la configuration manuelle :

| Problème                                          | Solution apportée                                              |
| ------------------------------------------------- | -------------------------------------------------------------- |
| Configuration GPU oubliée ou incorrecte           | Détection automatique des devices (`cardN`, `renderDN`, `kfd`) |
| Permissions udev manquantes pour LXC unprivileged | Règle udev `MODE="0666"` générée automatiquement               |
| Conflits `machine-id` entre clones                | Reset via `pct mount` (sans démarrer)                          |
| Clés SSH dupliquées (faille de sécurité)          | Suppression automatique avant templatisation                   |
| Search domain pollué (anomalie Proxmox)           | Paramètre `--searchdomain` jamais transmis                     |
| Warning systemd 257                               | `features: nesting=1` activé par défaut                        |

> ⚠️ **Ce script ne fait PAS** (volontairement) :
> 
> - Installation de Vulkan / llama.cpp / paquets applicatifs
> 
> - Test Go/NoGo du GPU (`vulkaninfo`)
> 
> - Sauvegarde `vzdump`
> 
> - Configuration DHCP statique côté pfSense ou autre (A faire à la mano)
> 
> - Supprimer les rules associées au template  ( note : A faire plus tard via un script de netoyage car suite à un `pct destroy 666`, le fichier` 99-lxc-gpu-666.rules` restera orphelin. Le trap actuel ne le supprime qu'en cas d'échec, pas en cas de succès (c'est correct — sur succès, le template existe). Il faudra un futur LXC_DESTROY_TEMPLATE.sh qui fasse le ménage (destroy + rm rule)).
> 
> Ces étapes sont documentées dans des guides dédiés (voir Documentation associée).

---

## ✨ Fonctionnalités

- ✅ **Détection automatique du GPU** via sysfs (`/sys/class/drm/*/dev`) — plus fiable que `ls -l`

- ✅ **Support iGPU AMD** (Radeon Lucienne, Renoir, etc.) et cartes dédiées

- ✅ **Support `/dev/kfd`** (ROCm, optionnel) si présent

- ✅ **Configuration `cgroup2`** avec les bons major:minor décimaux

- ✅ **Bind mounts** directs (`cardN`, `renderDN`, `kfd`) — jamais de `by-path`

- ✅ **Règle udev** auto-générée avec le bon subsystem (`kfd`, pas `drm`)

- ✅ **Reset machine-id + SSH** via `pct mount` (pas de start/shutdown)

- ✅ **Nesting activé** pour systemd 257+

- ✅ **Mode `--dry-run`** pour prévisualiser les actions

- ✅ **Trap de nettoyage** en cas d'échec (rollback partiel)

- ✅ **Codes de sortie nominaux** pour diagnostic précis

- ✅ **Logs colorés** avec contexte en cas d'erreur

---

## 📦 Prérequis

### Matériel

- **CPU/GPU** : AMD Ryzen avec iGPU Radeon (testé sur **Ryzen 7 5700U** — Lucienne/Renoir), ou carte AMD dédiée

- **Pilote** : `amdgpu` chargé sur l'hôte

- **Devices attendus** :
  
  - `/dev/dri/card0` (major 226, minor 0)
  
  - `/dev/dri/renderD128` (major 226, minor 128)
  
  - `/dev/kfd` (major 510, minor 0) — optionnel (ROCm)

### Logiciels

- **Proxmox VE** 8.x ou 9.x (testé sur **9.2.3**, kernel 7.0.14-23-pve)

- **Debian 13 (Trixie)** template disponible sur un storage `vztmpl`

- **Bash** 4.4+

- Droits **root** sur l'hôte Proxmox

### Vérifications préalables

bash

# 1. Pilote amdgpu chargé ?

```bash
lspci -nnk | grep -A 3 -iE 'vga|3d|display'

# Attendu : "Kernel driver in use: amdgpu"
```

# 2. Nœuds GPU présents ?

```bash
ls -l /dev/dri /dev/kfd
```

# 3. Groupes render/video existants ?

```bash
getent group render video
```

# 4. Template Debian 13 disponible ?

```bash
pveam list local | grep debian-13
```

# 5. Storage rootfs disponible ?

```bash
pvesm status
```

---

## 🚀 Installation

### Méthode 1 — Téléchargement direct

# Sur l'hôte Proxmox (en root)

```bash
cd /root
wget https://raw.githubusercontent.com/<votre-user>/<votre-repo>/main/LXC_TEMPLATE_GPU.sh
chmod +x LXC_TEMPLATE_GPU.sh
```

### Méthode 2 — Clone Git

```bash
cd /root
git clone https://github.com/<votre-user>/<votre-repo>.git lxc-template-gpu
cd lxc-template-gpu
chmod +x LXC_TEMPLATE_GPU.sh
```

### Vérification

```bash
./LXC_TEMPLATE_GPU.sh --help
```

---

## 🎮 Utilisation

### Syntaxe

```bash
./LXC_TEMPLATE_GPU.sh [options]
```

### Exécution minimale

```bash
# Création avec les valeurs par défaut (ID 999, DHCP, GPU auto-détecté)

./LXC_TEMPLATE_GPU.sh
```

### Exécution typique

```bash
# Template maître avec hostname explicite

./LXC_TEMPLATE_GPU.sh --id 999 --hostname master-r7-igpu

# Avec IP statique

./LXC_TEMPLATE_GPU.sh --id 999 --hostname master-r7-igpu \
  --ip 10.10.10.140/24 --gw 10.10.10.254

# Prévisualisation sans modification

./LXC_TEMPLATE_GPU.sh --dry-run --gpu
```

---

## ⚙️ Options

| Option            | Argument     | Défaut                  | Description                                         |
| ----------------- | ------------ | ----------------------- | --------------------------------------------------- |
| `--id`            | `N`          | `999`                   | ID du conteneur                                     |
| `--hostname`      | `NAME`       | `cont-<timestamp>`      | Hostname du conteneur                               |
| `--storage`       | `STOR`       | `local-zfs`             | Storage rootfs                                      |
| `--bridge`        | `BR`         | `vmbr0`                 | Bridge réseau                                       |
| `--cores`         | `N`          | `2`                     | Nombre de cores                                     |
| `--memory`        | `MiB`        | `2048`                  | RAM en MiB                                          |
| `--swap`          | `MiB`        | `512`                   | Swap en MiB                                         |
| `--disk`          | `SIZE`       | `10`                    | Taille disque en Go                                 |
| `--nameserver`    | `IP`         | `10.10.10.254`          | DNS                                                 |
| `--searchdomain`  | `DOM`        | *(vide)*                | Search domain (laisser vide — cf. anomalie Proxmox) |
| `--ip`            | `CIDR\|dhcp` | `dhcp`                  | IP statique (ex. `10.10.10.140/24`) ou `dhcp`       |
| `--gw`            | `IP`         | —                       | Gateway (**requis** si `--ip` statique)             |
| `--tags`          | `LIST`       | `template,gpu,igpu,lxc` | Tags Proxmox (séparés par virgule)                  |
| `--template-os`   | `VOLID`      | auto                    | Template OS (auto-détection Debian 13 si vide)      |
| `--root-password` | —            | non                     | Demander interactivement un mot de passe root       |
| `--gpu`           | —            | auto                    | Forcer l'activation du passthrough GPU              |
| `--no-gpu`        | —            | —                       | Désactiver le passthrough GPU                       |
| `--reset`         | —            | oui                     | Reset machine-id + SSH (défaut)                     |
| `--no-reset`      | —            | —                       | ⚠️ Ne PAS reset (clones impurs — déconseillé)       |
| `--force`         | —            | non                     | Écraser un conteneur existant avec le même ID       |
| `--dry-run`       | —            | non                     | Afficher les actions sans les exécuter              |
| `--debug`         | —            | non                     | Active `set -x` (trace de chaque commande)          |
| `-h`, `--help`    | —            | —                       | Affiche l'aide                                      |

---

## 🔧 Ce que fait le script

```text
┌──────────────────────────────────────────────────────────────────┐
│  1. PREFLIGHT                                                     │
│     • Vérifie root, pct, pveam, pvesm, /etc/pve                  │
│     • Valide storage, bridge, template OS                        │
│     • Vérifie que l'ID est libre (ou --force)                    │
│     • Vérifie la cohérence réseau (IP statique → gw requis)      │
├──────────────────────────────────────────────────────────────────┤
│  2. DÉTECTION GPU                                                 │
│     • Lit /sys/class/drm/*/dev (major:minor décimaux)            │
│     • Détecte cardN, renderDN, kfd                               │
│     • Fallback sur ls -l si sysfs indisponible                   │
├──────────────────────────────────────────────────────────────────┤
│  3. CRÉATION DU CONTENEUR                                         │
│     • pct create <id> <template> --start 0                       │
│     • Unprivileged, nesting=1, sans searchdomain                 │
├──────────────────────────────────────────────────────────────────┤
│  4. CONFIG GPU                                                    │
│     • Patch /etc/pve/lxc/<id>.conf :                             │
│         - lxc.cgroup2.devices.allow: c 226:0 rwm                 │
│         - lxc.cgroup2.devices.allow: c 226:128 rwm               │
│         - lxc.cgroup2.devices.allow: c 510:0 rwm                 │
│         - lxc.mount.entry: /dev/dri/card0 ...                    │
│         - lxc.mount.entry: /dev/dri/renderD128 ...               │
│         - lxc.mount.entry: /dev/kfd ...                          │
│     • Crée /etc/udev/rules.d/99-lxc-gpu-<id>.rules (MODE=0666)  │
│     • udevadm control --reload-rules && udevadm trigger          │
├──────────────────────────────────────────────────────────────────┤
│  5. RESET (via pct mount, SANS démarrer)                          │
│     • truncate /etc/machine-id → 0 octet                         │
│     • ln -sfn /etc/machine-id /var/lib/dbus/machine-id           │
│     • rm /etc/ssh/ssh_host_*                                     │
│     • pct unmount <id>                                           │
├──────────────────────────────────────────────────────────────────┤
│  6. TEMPLATISATION                                                │
│     • pct template <id>                                          │
│     • Affichage du récapitulatif                                 │
└──────────────────────────────────────────────────────────────────┘
```

---

## 📚 Exemples

### Création d'un template maître golden image

```bash
./LXC_TEMPLATE_GPU.sh \
  --id 999 \
  --hostname master-r7-igpu \
  --storage local-zfs \
  --disk 10 \
  --memory 2048 \
  --swap 512 \
  --cores 2 \
  --tags "template,gpu,igpu,lxc,debian13"
```

### Création avec IP statique

```bash
./LXC_TEMPLATE_GPU.sh \
  --id 205 \
  --hostname test-gpu-r7 \
  --ip 10.10.10.150/24 \
  --gw 10.10.10.254 \
  --tags "template,test,gpu"
```

### Mode dry-run (prévisualisation)

```bash
./LXC_TEMPLATE_GPU.sh --dry-run --gpu --id 999
```

### Sans GPU (conteneur CPU-only)

```bash
./LXC_TEMPLATE_GPU.sh --no-gpu --id 300 --hostname cont-cpu
```

### Avec mot de passe root interactif

```bash
./LXC_TEMPLATE_GPU.sh --root-password --id 999
```

### Forcer l'écrasement d'un conteneur existant

```bash
./LXC_TEMPLATE_GPU.sh --id 999 --force
```

---

## 🔄 Workflow recommandé

```textile
┌─────────────────────────────────────────────────────────────┐
│  1. Créer le template maître (ce script)                    │
│     ./LXC_TEMPLATE_GPU.sh --id 999 --hostname master-r7-igpu│
│                                                             │
│  2. Vérifier la config                                      │
│     pct config 999 | grep -E 'cgroup2|mount.entry|template' │
│                                                             │
│  3. Cloner (full clone)                                     │
│     pct clone 999 201 --hostname llama-r7 --full            │
│                                                             │
│  4. Ajuster ressources + IP statique (post-clone)           │
│     pct set 201 -cores 6 -memory 12288                      │
│     pct set 201 --net0 name=eth0,bridge=vmbr0,\              │
│         ip=10.10.10.140/24,gw=10.10.10.254,type=veth        │
│                                                             │
│  5. Ajouter bind mounts spécifiques (si besoin)             │
│     pct set 201 -mp0 /rpool/models,mp=/opt/models,ro=1      │
│                                                             │
│  6. Démarrer et configurer le service                       │
│     pct start 201 && pct enter 201                          │
│                                                             │
│  7. Sauvegarder le template maître                          │
│     vzdump 999 --storage local --mode snapshot --compress zstd│
└─────────────────────────────────────────────────────────────┘
```

### Vérification post-clone

# Dans le clone

```bash
hostname               # → hostname attendu
cat /etc/machine-id    # → UUID généré (pas vide)
ls /etc/ssh/ssh_host_* # → nouvelles clés régénérées
ls -l /dev/dri/ /dev/kfd  # → GPU accessible
```

> ⚠️ **Post-clone** : configurer le mappage DHCP statique dans pfSense, ou fixer l'IP statique via `pct set`.

---

## 🚦 Codes de sortie

| Code  | Signification                                         | Émetteur                         |
| ----- | ----------------------------------------------------- | -------------------------------- |
| `0`   | Succès                                                | `main`                           |
| `1`   | Erreur de préflight (validation)                      | `die_user`                       |
| `2`   | Erreur d'usage (arguments)                            | `die_usage`                      |
| `3`   | Dépendance manquante / storage / bridge / template OS | `die_env`                        |
| `4`   | `pct create` a échoué                                 | `die_create`                     |
| `5`   | Configuration GPU a échoué                            | `die_gpu`                        |
| `6`   | Reset machine-id a échoué                             | `die_reset`                      |
| `7`   | `pct template` a échoué                               | `die_template`                   |
| `255` | Réservé : erreur non gérée                            | *(ne devrait jamais apparaître)* |

---

## 🔍 Dépannage

### Le GPU n'est pas détecté dans le conteneur

```bash
# 1. Vérifier les nœuds dans le conteneur
pct enter 999
ls -l /dev/dri/ /dev/kfd

# 2. Si absents, vérifier les permissions sur l'hôte
ls -l /dev/dri/card0 /dev/dri/renderD128 /dev/kfd

# Attendu : crw-rw-rw-

# 3. Si permissions incorrectes, vérifier la règle udev
cat /etc/udev/rules.d/99-lxc-gpu-999.rules
udevadm control --reload-rules && udevadm trigger
```

### Erreur "ID 999 déjà utilisé"

```bash
# Option 1 : utiliser un autre ID
./LXC_TEMPLATE_GPU.sh --id 998

# Option 2 : forcer l'écrasement (destructif !)
./LXC_TEMPLATE_GPU.sh --id 999 --force
```

### Erreur "Aucun template Debian 13"

```bash
# Télécharger le template
pveam update
pveam available --section system | grep debian-13
pveam download local debian-13-standard_13.6-1_amd64.tar.zst

# Ou spécifier manuellement
./LXC_TEMPLATE_GPU.sh --template-os local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst
```

### Vulkan ne détecte pas le GPU

```bash
# Dans le conteneur
apt install -y vulkan-tools mesa-vulkan-drivers
vulkaninfo --summary | grep -E "deviceName|deviceType"

# Attendu : AMD Radeon Graphics (RADV RENOIR)
```

⚠️ **Piège `by-path`** : ne **jamais** utiliser les liens symboliques `by-path` pour le passthrough LXC. Le conteneur créerait un nœud au chemin littéral, et la découverte DRM/ROCm qui parcourt `/dev/dri/` ne trouverait rien. Le script utilise toujours les chemins directs `cardN` / `renderDN` / `kfd`.

### Warning systemd 257

Le script active `nesting=1` par défaut. Si vous voyez quand même le warning :

```bash
pct set <id> -features nesting=1
pct config <id> | grep features
```

### Debug approfondi

```bash
./LXC_TEMPLATE_GPU.sh --debug --dry-run
```

---

## 🛠 Détails techniques

### Détection GPU via sysfs

Le script utilise `/sys/class/drm/<nom>/dev` qui contient directement `major:minor` en **décimal** (plus fiable que parser `ls -l`, qui casse dès qu'un fichier a plusieurs nœuds ou un format de date inattendu) :

```bash
$ cat /sys/class/drm/card0/dev       # → 226:0
$ cat /sys/class/drm/renderD128/dev  # → 226:128
$ cat /sys/class/kfd/kfd/dev         # → 510:0
```

### Règle udev — le bon subsystem

Un conteneur unprivileged mappe `root` → UID 100000 sur l'hôte. Les nœuds `/dev/dri/*` et `/dev/kfd` sont créés `0660 root:video` ou `root:render`. L'UID 100000 n'appartient pas à ces groupes → pas d'accès.

`MODE="0666"` rend les nœuds accessibles à tous. Sur un hôte Proxmox mono-utilisateur, le compromis est acceptable.

> ⚠️ **Bug documenté** : `KERNEL=="kfd", SUBSYSTEM=="drm"` est **FAUX**. Le bon subsystem est `kfd` (vérifiable avec `udevadm info -q property -n /dev/kfd | grep SUBSYSTEM`). Le script génère la bonne règle.

### Reset machine-id via `pct mount`

Plutôt que `pct start` / reset / `pct shutdown`, le script utilise `pct mount` qui monte le rootfs **sans démarrer** le conteneur — plus propre et conforme à la philosophie "ne pas démarrer le template".

```bash
pct mount <id>
: > /var/lib/lxc/<id>/rootfs/etc/machine-id
rm -f /var/lib/lxc/<id>/rootfs/etc/ssh/ssh_host_*
pct unmount <id>
```

Un fichier `/etc/machine-id` **vide (0 octet)** est le signal pour systemd de **générer un nouvel identifiant** au prochain boot. Ne pas supprimer le fichier — le vider.

### Anomalie searchdomain Proxmox

Lors de la création via formulaire web, Proxmox peut renseigner `searchdomain: 10.10.10.254` (confusion entre DNS server et search domain). Un search domain doit être un **nom de domaine** (`home.arpa`, `intranet.toto.net`) ou vide, jamais une IP. Le script ne passe **jamais** `--searchdomain` à `pct create`.

---

## 📖 Documentation associée

Ce script est le point d'entrée d'une série de guides :

| Document                                 | Rôle                                                                                  |
| ---------------------------------------- | ------------------------------------------------------------------------------------- |
| **`INSTALL-LLAMA-CPP-LXC.md`**           | Workflow GPU + Vulkan + llama.cpp (détails du passthrough, compilation, performances) |
| **`CONTAINER-MAITRE-VIERGE-R7-IGPU.md`** | Template golden image, reset machine-id/SSH, workflow de clone, bonnes pratiques      |

Ces documents seront poussés dans le dépôt `docs` séparément.

---

## 🤝 Contribution

Les contributions sont les bienvenues ! Pour proposer une amélioration :

1. Forkez le dépôt

2. Créez une branche (`git checkout -b feature/amelioration`)

3. Commitez vos changements (`git commit -am 'Ajout fonctionnalité X'`)

4. Poussez (`git push origin feature/amelioration`)

5. Ouvrez une Pull Request

### Pistes d'amélioration

- Option `--gpu-pci <PCI>` pour forcer un GPU spécifique (multi-GPU)

- Option `--verbose` / `-v`

- Support des cartes NVIDIA (nouveau backend `nvidia-container-toolkit`)

- Tests automatisés (bats-core)

- Intégration dans un rôle Ansible

---

## 📄 Licence

Ce projet est distribué sous licence **MIT**. Voir le fichier [`LICENSE`](https://license/) pour plus de détails.

---

## ⚠️ Avertissement

Ce script modifie la configuration de votre hôte Proxmox (`/etc/pve/lxc/*.conf`, `/etc/udev/rules.d/*`). Il est **fortement recommandé** de :

- Tester d'abord avec `--dry-run`

- Sauvegarder votre configuration avant exécution

- Comprendre les implications de `MODE="0666"` sur les devices GPU (acceptable sur un hôte mono-utilisateur, à adapter en environnement multi-tenant)

Les auteurs ne sauraient être tenus responsables de tout dommage résultant de l'utilisation de ce script.

---

*Dernière mise à jour : 23 octobre 2026 — Version 1.0*
