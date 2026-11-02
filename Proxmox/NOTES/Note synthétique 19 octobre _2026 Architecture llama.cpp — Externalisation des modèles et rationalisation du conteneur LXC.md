# Note synthétique 19 octobre _2026_ : Architecture llama.cpp — Externalisation des modèles et rationalisation du conteneur LXC

> **Environnement** : Proxmox VE 9.2.3 sur AMD Ryzen 7 5700U (iGPU Radeon Lucienne), 30 Go RAM, 4 To SSD ZFS.
> **Conteneur** : LXC 102 `llama-cpp`, unprivileged, Debian 13.
> 
> **Objectif** : Documenter les choix d'architecture validés par les tests, servir de référentiel pour les évolutions futures.

---

## 1. Contexte et décisions structurantes

Ce document consolide **trois décisions d'architecture** prises après validation empirique :

| #   | Décision                                                    | Statut   |
| --- | ----------------------------------------------------------- | -------- |
| 1   | **Externaliser les modèles** hors du conteneur (bind mount) | ✅ Validé |
| 2   | **Rationaliser les ressources** du conteneur (right-sizing) | ✅ Validé |
| 3   | **Optimiser llama-server** (`--parallel 1`, `-t 4`)         | ✅ Validé |

Chaque décision est justifiée par des mesures ou des contraintes techniques documentées ci-dessous.

---

## 2. Décision 1 — Externaliser les modèles hors du conteneur

### 2.1 Principe

Les fichiers `.gguf` ne sont **pas stockés dans le disque du conteneur** (`subvol-102-disk-0`, 20 Go), mais sur l'**hôte Proxmox**, puis montés dans le conteneur via un **bind mount** en lecture seule.

### 2.2 Pourquoi externaliser ?

| Avantage                       | Explication                                                                                                                                   |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **Économie d'espace**          | Le modèle n'est pas dupliqué dans le disque du conteneur (20 Go). Un 7B Q4 = 4,4 Go, un 14B = 8,5 Go. Sur 3-4 modèles, on économise 20-30 Go. |
| **Mise à jour facile**         | Télécharger un nouveau GGUF sur l'hôte → le conteneur le voit immédiatement, sans `pct push` ni redémarrage.                                  |
| **Sauvegarde indépendante**    | Les modèles peuvent être sauvegardés séparément du conteneur (snapshot ZFS dédié, `rsync` vers NAS).                                          |
| **Partage entre conteneurs**   | Un même modèle peut être monté dans plusieurs conteneurs (attention à la contention GPU).                                                     |
| **Découplage système/données** | Mettre à jour ou recréer le conteneur ne touche pas aux modèles.                                                                              |

### 2.3 Méthode recommandée : `pct set -mp0`

**Sur l'hôte Proxmox** :

```bash
# 1. Créer le dossier des modèles sur l'hôte
mkdir -p /mnt/models

# 2. Y placer les fichiers .gguf (via scp, ou déplacement)

# Exemple : /mnt/models/qwen2.5-coder-7b-instruct-q4_k_m.gguf

# 3. Monter dans le conteneur 102 en lecture seule
pct set 102 -mp0 /mnt/models,mp=/opt/models,ro=1

# 4. Redémarrer le conteneur pour prise en compte
pct reboot 102
```

| Option           | Rôle                                                                               |
| ---------------- | ---------------------------------------------------------------------------------- |
| `-mp0`           | Point de montage n°0 (on peut en avoir plusieurs : `mp1`, `mp2`…)                  |
| `/mnt/models`    | Chemin **sur l'hôte**                                                              |
| `mp=/opt/models` | Chemin **dans le conteneur**                                                       |
| `ro=1`           | **Lecture seule** — recommandé pour les modèles (jamais modifiés par le conteneur) |

**Vérification dans le conteneur** :

bash

```bash
pct exec 102 -- ls -lh /opt/models/

# Le fichier doit apparaître
```

### 2.4 Méthode alternative : `lxc.mount.entry`

Éditer `/etc/pve/lxc/102.conf` et ajouter :

`lxc.mount.entry: /mnt/models opt/models none bind,ro,create=dir 0 0`

Puis `pct reboot 102`.

⚠️ **Préférer `pct set -mp0`** : géré nativement par Proxmox (visible dans l'interface web, compatible avec les sauvegardes, plus lisible).

### 2.5 Point critique — Permissions en conteneur non privilégié

Le conteneur 102 est **unprivileged** (root interne mappé vers UID 100000 sur l'hôte). Conséquences :

- Les fichiers de `/mnt/models` sur l'hôte appartiennent à `root` (UID 0).

- Dans le conteneur, ils apparaissent comme appartenant à **UID 100000** (ou `nobody`).

**Avec `ro=1` (lecture seule), aucun problème** : le conteneur peut lire les fichiers même s'il n'en est pas propriétaire.

Si un jour vous aviez besoin d'**écrire** dans ce dossier (upload de modèles depuis le conteneur, par exemple), il faudrait :

1. Créer un groupe partagé avec le même GID sur l'hôte et dans le conteneur.

2. Ajuster les permissions (`chmod g+w`, `chgrp`).

Mais pour des GGUF, la lecture seule c'est la bonne configuration.

### 2.6 Performances : identiques au stockage interne

**Résultat mesuré** : aucune différence de performance entre un modèle dans `/opt/models/` (interne) et un modèle bind-monté depuis l'hôte.

**Pourquoi ?**

1. llama-server lit le fichier **une seule fois au démarrage** (chargement en RAM).

2. Avec Vulkan, le `mmap` est désactivé automatiquement pour l'iGPU (chargement direct en RAM).

3. Une fois le modèle chargé, **aucun accès disque** n'a lieu pendant l'inférence.

Le stockage physique du fichier n'influence donc en rien la vitesse de génération. La différence est organisationnelle, pas performative.

---

## 3. Décision 2 — Rationaliser les ressources du conteneur

### 3.1 Principe fondamental : LXC ≠ VM (piège VMware)

C'est **la** distinction à intégrer quand on vient de VMware :

| Aspect            | **VMware (VM)**                     | **Proxmox (LXC)**                                                   |
| ----------------- | ----------------------------------- | ------------------------------------------------------------------- |
| **RAM allouée**   | **Réservée** au démarrage           | **Limite haute** — la RAM non utilisée reste disponible pour l'hôte |
| **CPU alloué**    | **Réservé** (vCPU pinning possible) | **Quota** (cfs) — les cycles non utilisés sont redistribués         |
| **Disque alloué** | Réservé (thin ou thick)             | **Limite** — sparse sur ZFS, seule l'utilisation réelle compte      |

**Conséquence** : allouer 12 Go de RAM et 6 cores à un conteneur LXC ne prive pas les autres conteneurs. Mais c'est une déclaration inexacte du besoin réel, qui nuit à la lisibilité de l'architecture.

### 3.2 Observation empirique : le conteneur est massivement surdimensionné

**Mesures relevées** (conteneur au repos, llama-server arrêté) :

| Ressource | Mesuré    | Alloué  | Taux   |
| --------- | --------- | ------- | ------ |
| CPU       | 0,00 %    | 6 cores | 0 %    |
| RAM       | 90,90 Mio | 12 Go   | 0,74 % |
| Swap      | 0 octet   | 2 Go    | 0 %    |
| Disque    | 1,04 Gio  | 20 Go   | 5,21 % |

**Pendant l'inférence** (7B Q4_K_M, `-ngl 99`) :

| Ressource              | Utilisation                          | Goulot ?      |
| ---------------------- | ------------------------------------ | ------------- |
| CPU                    | ~5-10 % d'un cœur                    | ❌ Non         |
| **iGPU**               | **~100 %**                           | ✅ **OUI**     |
| Bande passante mémoire | ~51 Go/s (partagée)                  | ✅ **OUI**     |
| RAM conteneur          | Modèle + KV cache + système ≈ 6-7 Go | ⚠️ Suffisante |
| Disque                 | Lecture unique au chargement         | ❌ Non         |

**Conclusion** : le workload est **GPU-bound et memory-bandwidth-bound**, pas CPU-bound.

### 3.3 Right-sizing validé

| Ressource  | Avant   | Après                  | Justification                                                      |
| ---------- | ------- | ---------------------- | ------------------------------------------------------------------ |
| **CPU**    | 6 cores | **4 cores**            | GPU-bound, 4 suffit largement (5-10 % d'un cœur utilisé)           |
| **RAM**    | 12 Go   | **10 Go**              | 7B Q4 (4,4 Go) + KV cache (1,5 Go) + système (1 Go) + marge (3 Go) |
| **Swap**   | 2 Go    | **2 Go**               | Minimal, garder pour sécurité (swappiness=10 sur l'hôte)           |
| **Disque** | 20 Go   | **15 Go** (recommandé) | Système + build (~5 Go), modèles externes via bind mount           |

**Commandes** mise à jour du container ID 102 `llama.cpp` :

```bash
pct set 102 -cores 4 -memory 10240
pct reboot 102
```

### 3.4 Quand augmenter les ressources ?

| Scénario                                   | Action                                                |
| ------------------------------------------ | ----------------------------------------------------- |
| **Modèle 13B-14B Q4** (batch nocturne)     | Passer à `-memory 16384` (16 Go)                      |
| **Contexte très long** (32k tokens)        | Augmenter RAM + ajuster `-c`                          |
| **Multi-modèles simultanés** (llama-swap)  | Augmenter RAM + disque                                |
| **Ajout d'un workload GPU** (YOLO, OCR...) | **Ne pas augmenter** — un seul workload GPU à la fois |

---

## 4. Décision 3 — Optimiser llama-server

### 4.1 Paramètres validés

```bash
/opt/llama.cpp/build/bin/llama-server \
  -m /opt/models/qwen2.5-coder-7b-instruct-q4_k_m.gguf \
  -ngl 99 \
  -c 8192 \
  --parallel 1 \
  -t 4 \
  --host 0.0.0.0 \
  --port 8080
```

| Paramètre      | Valeur             | Justification                                          |
| -------------- | ------------------ | ------------------------------------------------------ |
| `-ngl 99`      | Toutes couches GPU | Vulkan, iGPU Radeon                                    |
| `-c 8192`      | 8k contexte        | Suffisant pour du code, KV cache raisonnable (~1,5 Go) |
| `--parallel 1` | 1 slot             | Un seul workload GPU à la fois (vs 4 slots par défaut) |
| `-t 4`         | 4 threads CPU      | Tokenization + sampling, GPU-bound                     |

### 4.2 Résultats mesurés (7B Q4_K_M, iGPU RADV RENOIR)

| Configuration               | Génération      | Prompt eval | Observations              |
| --------------------------- | --------------- | ----------- | ------------------------- |
| Défaut (4 slots, 8 threads) | 8,1 tok/s       | 97 tok/s    | KV cache 4× plus grand    |
| `--parallel 1` (8 threads)  | 8,08-8,10 tok/s | 89-97 tok/s | Gain marginal             |
| `--parallel 1 -t 4`         | 8,08-8,30 tok/s | 90 tok/s    | **Configuration retenue** |
| `--parallel 1 -t 6`         | 8,08-8,23 tok/s | 90 tok/s    | Identique à `-t 4`        |

**Écart entre `-t 4` et `-t 6` : < 0,3 %** — bruit de mesure. Le CPU n'est **jamais** le facteur limitant.

### 4.3 Pourquoi `--parallel 1` ?

Par défaut, llama-server crée **4 slots** de 8192 tokens = **32k de contexte total**. Conséquences :

- Les 4 slots se **partagent** la bande passante mémoire du GPU.

- Le KV cache alloué est 4× plus grand que nécessaire.

- En usage mono-utilisateur, 3 slots sur 4 sont **inutilisés** mais consomment quand même.

Avec `--parallel 1`, un seul slot de 8192 tokens = KV cache minimal, performances optimales.

### 4.4 Le débat `-t` : 4, 6 ou 8 ?

| Nombre de threads      | Usage                                                                    |
| ---------------------- | ------------------------------------------------------------------------ |
| **8** (détection auto) | llama.cpp lit `/sys/devices/system/cpu/` (voit l'hôte, pas le conteneur) |
| **6** (cores alloués)  | Cohérent avec `-cores 6`                                                 |
| **4** (recommandé)     | Cohérent avec `-cores 4`, libère 2 threads pour le système               |

**En pratique** : aucune différence mesurable. `-t 4` est le choix d'**hygiène** — il documente le besoin réel et évite les threads en attente.

### 4.5 Warning `</s>` — bénin

```textile
control-looking token: 128247 '</s>' was not control-type; this is probably a bug in the model
```

**Origine** : le token de fin de séquence (`</s>`) est mal typé dans le GGUF du dépôt Hugging Face (`bartowski/...`).

**Impact** : aucun. llama.cpp le corrige automatiquement au chargement. Warning cosmétique.

---

## 5. Architecture de stockage — État actuel et cible

### 5.1 État actuel (validé, fonctionnel)

```text
Hôte Proxmox (rpool ZFS, 4 To)
└── /mnt/models/                    ← dossier simple, bind-monté
    └── qwen2.5-coder-7b-instruct-q4_k_m.gguf
                │
                │  pct set 102 -mp0 /mnt/models,mp=/opt/models,ro=1
                ▼
Conteneur 102 (llama-cpp)
└── /opt/models/                    ← montage lecture seule
    └── qwen2.5-coder-7b-instruct-q4_k_m.gguf
```

**Statut** : ✅ Fonctionnel, performances validées (8 tok/s).

**Inconvénient** : `/mnt/models` n'est pas un dataset ZFS dédié. Snapshots moins granulaires, pas de quotas séparés.

### 5.2 Cible à terme : dataset ZFS dédié

```text
Hôte Proxmox (rpool ZFS, 4 To)
└── rpool/models/                   ← dataset ZFS dédié
    ├── qwen2.5-coder-7b-instruct-q4_k_m.gguf
    ├── qwen2.5-coder-14b-instruct-q4_k_m.gguf  (futur)
    └── deepseek-r1-distill-1.5b-q4_k_m.gguf     (test)
                │
                │  pct set 102 -mp0 /rpool/models,mp=/opt/models,ro=1
                ▼
Conteneur 102 (llama-cpp)
└── /opt/models/                    ← montage lecture seule
```

**Avantages du dataset ZFS dédié** :

| Avantage                   | Explication                                                                                    |
| -------------------------- | ---------------------------------------------------------------------------------------------- |
| **Snapshots indépendants** | `zfs snapshot rpool/models@avant-nouveau-modele`                                               |
| **Quotas**                 | Limiter la taille allouée aux modèles (`zfs set quota=200G rpool/models`)                      |
| **Compression**            | `zfs set compression=zstd rpool/models` (gain ~10-15 % sur les GGUF)                           |
| **Sauvegarde ciblée**      | `zfs send rpool/models@snap \| ssh backup ...`                                                 |
| **Découplage clair**       | Séparation nette : système (`rpool/ROOT`), conteneurs (`rpool/data`), modèles (`rpool/models`) |

**Migration** (simple, sans interruption de service significative) :

```bash
#1. Créer le dataset
zfs create -o compression=zstd -o quota=200G rpool/models

#2. Déplacer les modèles
mv /mnt/models/*.gguf /rpool/models/

#3. Mettre à jour le montage du conteneur
pct set 102 -mp0 /rpool/models,mp=/opt/models,ro=1

#4. Redémarrer le conteneur
pct reboot 102

#5. Nettoyer l'ancien dossier
rmdir /mnt/models
```

### 5.3 Évolution future : machine dédiée aux modèles

**Scénario envisagé** : à terme, les modèles pourraient être hébergés sur une **machine dédiée** (NAS, serveur de stockage), et non plus sur l'hôte Proxmox.

**Architecture cible** :

```text
┌─────────────────────────┐         ┌─────────────────────────┐
│  pve-proxmox-R7 (.50)   │         │  Machine dédiée modèles │
│  Conteneur 102          │         │  (NAS, serveur)         │
│  llama-server           │◀────────│  /export/models/        │
│  /opt/models/ (NFS)     │  NFS/   │  (stockage centralisé)  │
│                         │  SMB    │                         │
└─────────────────────────┘         └─────────────────────────┘
```

**Avantages** :

- Stockage centralisé (un seul point de mise à jour).

- Découplage matériel (le R7 peut être remplacé sans perdre les modèles).

- Sauvegardes centralisées.

**Inconvénients** :

- **Latence réseau** au chargement initial (~5-10 s supplémentaires pour 4,4 Go sur Gigabit).

- **Point de défaillance** (si le NAS tombe, plus de modèles).

- **Complexité** (NFS/SMB, montages, permissions).

**Recommandation** : à considérer **quand vous aurez plusieurs machines** capables de faire tourner des LLM (quand `.51` sera réparé). Pour l'instant, le stockage local est optimal.

---

## 6. Le RAM disk — Quand et pourquoi ?

### 6.1 Le problème : usure du SSD par rechargement répété

**Scénario à risque** : un framework qui **charge et décharge dynamiquement** des modèles (ou des couches de modèles) parce que la RAM est insuffisante.

| Framework                 | Comportement                                          | Lecture disque             |
| ------------------------- | ----------------------------------------------------- | -------------------------- |
| **llama.cpp** (votre cas) | Charge le modèle **une fois**, garde en RAM           | 1 lecture au démarrage     |
| **AirLLM**                | Charge les **couches à la volée** pendant l'inférence | **Relecture continue**     |
| **llama-swap**            | Alterne entre **plusieurs modèles** à la demande      | Relecture à chaque bascule |
| **vLLM (offload)**        | Décharge les couches inactives sur disque             | Relecture fréquente        |

Dans les 3 derniers cas, le SSD subit des **lectures répétées** des mêmes blocs. Les lectures n'usent pas directement un SSD (contrairement aux écritures), mais **saturent le contrôleur** et **ralentissent** le système.

### 6.2 La solution RAM disk — Conditions d'efficacité

Un RAM disk (`tmpfs`) place le fichier **entièrement en RAM**. Pour que ce soit utile :

| Condition                            | Explication                                                                                                           |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| **Le modèle doit tenir en RAM**      | Un 7B (4,4 Go) + KV cache (1,5 Go) + système (1 Go) = ~7 Go. Sur 10 Go, c'est jouable. Un 14B (8,5 Go) ne rentre pas. |
| **Le modèle doit être relu souvent** | Si chargé une fois (llama.cpp), gain nul. Si rechargé en boucle (AirLLM), gain réel.                                  |
| **Assez de RAM disponible**          | Le RAM disk consomme la RAM de l'hôte. Sur 30 Go, 8 Go pour un RAM disk laisse 22 Go pour le reste.                   |

### 6.3 Ce que le RAM disk **ne résout pas**

⚠️ **Paradoxe** : si le modèle **ne tient pas en RAM** (cas typique de "manque de ressources"), il **ne tiendra pas non plus** dans un RAM disk. Le RAM disk consomme de la RAM, exactement comme le cache du modèle.

**Donc dans le scénario "modèle trop gros pour la RAM"** :

- **RAM disk** : impossible, pas assez de RAM pour héberger le fichier.

- **mmap** : les pages sont évincées du cache quand la RAM est saturée, puis relues depuis le SSD à chaque accès → usure SSD réelle.

**La vraie solution** dans ce cas n'est **pas** le RAM disk, mais :

1. **Réduire le modèle** (quantification plus agressive, modèle plus petit).

2. **Passer à un SSD NVMe** plutôt que SATA : meilleure endurance (TBW plus élevé), IOPS bien supérieurs.

3. **Accepter la lenteur** si c'est du batch nocturne.

### 6.4 Quand le RAM disk est réellement pertinent

| Scénario                                          | RAM disk utile ? | Alternative                               |
| ------------------------------------------------- | ---------------- | ----------------------------------------- |
| **llama.cpp mono-modèle** (votre cas actuel)      | ❌ Non            | Le modèle reste en RAM, zéro relecture    |
| **llama-swap** (2-3 modèles alternés fréquemment) | ✅ **Oui**        | RAM disk pour les modèles actifs          |
| **AirLLM** (couches à la volée, modèle trop gros) | ❌ Impossible     | NVMe haute endurance, accepter la lenteur |
| **Base de données en lecture intensive**          | ✅ Oui            | Cas classique                             |
| **Compilation de code**                           | ✅ Oui            | Fichiers temporaires                      |

### 6.5 Implémentation d'un RAM disk (si besoin futur)

**Sur l'hôte Proxmox** :

```bash
# Créer un RAM disk de 8 Go
mkdir -p /mnt/ramdisk
mount -t tmpfs -o size=8G,mode=0755 tmpfs /mnt/ramdisk

# Copier le modèle dedans
cp /rpool/models/qwen2.5-coder-7b-instruct-q4_k_m.gguf /mnt/ramdisk/

# Monter dans le conteneur
pct set 102 -mp0 /mnt/ramdisk,mp=/opt/models-ram,ro=1
pct reboot 102
```

**Attention** : le RAM disk est **volatile** (perdu au redémarrage). Il faut le recréer et re-copier le modèle à chaque démarrage. Script à mettre dans `/etc/rc.local` ou un service systemd.

### 6.6 Recommandation pour ce  cas

**Aujourd'hui (llama.cpp mono-modèle)** : ❌ **RAM disk inutile**. Le modèle est chargé une fois, aucune relecture. Votre SSD est protégé par la nature même de `mmap` (lecture seule).

**Futur (machine dédiée, plusieurs modèles alternés)** : ⚠️ **À évaluer**. Si vous adoptez `llama-swap` ou un orchestrateur qui alterne entre 3-4 modèles, un RAM disk pour les modèles **actifs** peut protéger le SSD. Mais il faudra :

- Assez de RAM (16-24 Go dédiés au RAM disk).

- Accepter la volatilité (recréation au démarrage).

- Accepter la complexité (scripts de gestion).

**Alternative plus simple** : un **NVMe dédié** aux modèles (lecture intensive, TBW élevé). Un Samsung 990 Pro 2 To (~150 €) offre ~1200 TBW — largement suffisant pour des années de rechargement intensif.

---

## 7. Bilan des décisions

| #   | Décision                                  | Gain                                   | Complexité | Recommandation   |
| --- | ----------------------------------------- | -------------------------------------- | ---------- | ---------------- |
| 1   | **Externaliser les modèles** (bind mount) | Économie disque, souplesse, sauvegarde | ⭐          | ✅ **Appliqué**   |
| 2   | **Right-sizing** (4 cores, 10 Go)         | Hygiène, lisibilité                    | ⭐          | ✅ **Appliqué**   |
| 3   | **`--parallel 1 -t 4`**                   | KV cache minimal, threads cohérents    | ⭐          | ✅ **Appliqué**   |
| 4   | **Dataset ZFS dédié** (`rpool/models`)    | Snapshots, quotas, compression         | ⭐⭐         | 🔄 **À faire**   |
| 5   | **RAM disk** (si llama-swap futur)        | Protection SSD                         | ⭐⭐⭐        | 🔮 **Plus tard** |
| 6   | **Machine dédiée** (NFS/SMB)              | Centralisation                         | ⭐⭐⭐⭐       | 🔮 **Plus tard** |

---

## 8. Commandes de référence

### Sur l'hôte Proxmox

| Action                   | Commande                                                    |
| ------------------------ | ----------------------------------------------------------- |
| Créer le dossier modèles | `mkdir -p /mnt/models`                                      |
| Créer le dataset ZFS     | `zfs create -o compression=zstd -o quota=200G rpool/models` |
| Monter dans le conteneur | `pct set 102 -mp0 /rpool/models,mp=/opt/models,ro=1`        |
| Vérifier le montage      | `pct config 102 \| grep mp0`                                |
| Right-sizing CPU         | `pct set 102 -cores 4`                                      |
| Right-sizing RAM         | `pct set 102 -memory 10240`                                 |
| Redémarrer               | `pct reboot 102`                                            |

### Dans le conteneur

| Action                 | Commande                                                                                                                |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Vérifier le montage    | `ls -lh /opt/models/`                                                                                                   |
| Vérifier Vulkan        | `vulkaninfo --summary`                                                                                                  |
| Lancer llama-server    | `/opt/llama.cpp/build/bin/llama-server -m /opt/models/... -ngl 99 -c 8192 --parallel 1 -t 4 --host 0.0.0.0 --port 8080` |
| Vérifier l'utilisation | `nproc` (doit afficher 4)                                                                                               |

### Monitoring

| Action                 | Commande                              |
| ---------------------- | ------------------------------------- |
| Utilisation GPU (hôte) | `radeontop` ou `amdgpu_top`           |
| Logs llama-server      | Sortie standard (screen ou systemd)   |
| Utilisation conteneur  | Interface web Proxmox (onglet Résumé) |

---

## 9. Configuration finale retenue

### Conteneur 102

| Paramètre  | Valeur                                              |
| ---------- | --------------------------------------------------- |
| Type       | Unprivileged                                        |
| OS         | Debian 13                                           |
| CPU        | **4 cores**                                         |
| RAM        | **10240 MiB (10 Go)**                               |
| Swap       | 2048 MiB                                            |
| Disque     | 20 Go (réduire à 15 Go possible)                    |
| IP         | `10.10.10.132/24`                                   |
| Gateway    | `10.10.10.254` (pfSense)                            |
| Features   | `nesting=1`                                         |
| Bind mount | `/rpool/models` → `/opt/models` (ro)                |
| GPU        | `/dev/dri/card0`, `/dev/dri/renderD128`, `/dev/kfd` |

### llama-server

```bash
/opt/llama.cpp/build/bin/llama-server \
  -m /opt/models/qwen2.5-coder-7b-instruct-q4_k_m.gguf \
  -ngl 99 \
  -c 8192 \
  --parallel 1 \
  -t 4 \
  --host 0.0.0.0 \
  --port 8080
```

| Métrique                  | Valeur                           |
| ------------------------- | -------------------------------- |
| Modèle                    | Qwen2.5-Coder-7B-Instruct Q4_K_M |
| Génération                | **8,1 tok/s**                    |
| Prompt eval (1er tour)    | ~90 tok/s                        |
| Prompt eval (cache chaud) | ~300 tok/s                       |
| Latence perçue            | Fluide (~10 tok/s ≈ lecture)     |

---

*Document généré le 2026-octobre-19 — Architecture llama.cpp sur pve-proxmox-R7 (CT 102).*  
*Validé par mesures empiriques : 8,1 tok/s stables, indépendant de `-t 4` ou `-t 6` (GPU-bound).*
