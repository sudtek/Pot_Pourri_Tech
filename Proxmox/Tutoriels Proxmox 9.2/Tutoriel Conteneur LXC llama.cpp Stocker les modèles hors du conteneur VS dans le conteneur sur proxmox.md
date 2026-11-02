# Tutoriel Conteneur LXC llama.cpp :  Stocker les modèles hors du conteneur VS dans le conteneur sur proxmox.

Date : 30 octobre 2026

Vm : `Container LXC + debian + llama.cpp`

OS hyperviseur : `proxmox 9.2`

Hardware : `R7 nuke 32GB , SSD 4To, IGPU AMD Renoir <u>à mémoire partagée`

Autheur : Yannick SUDRIE

Lorsqu’on crée un conteneur **LXC** pour faire tourner **llama.cpp** sur **Proxmox**, celui-ci est généralement dédié à l’hébergement de modèles de langage tels que **DeepSeek**, **Qwen**, etc. L’objectif est de tester plusieurs modèles afin d’exploiter au maximum les ressources de sa machine locale.

Très vite, on se rend compte que télécharger et tester des dizaines de modèles — qui pèsent chacun plusieurs Go — directement dans le conteneur **llama.cpp** n’est **pas viable à long terme**.

Pour un premier test rapide, on peut raisonnablement déposer un modèle de quelques Go à l’intérieur du conteneur afin de vérifier que le fonctionnement est correct. Mais on constate rapidement que :

- le conteneur **LXC** gonfle ;

- les **snapshots ZFS** (points de restauration) grossissent à vue d’œil au fil des tests.

**Conclusion :** dès le départ, il faut prévoir un stockage des modèles **en dehors** du conteneur **LXC**.

C'est même **recommandé** pour plusieurs raisons :

| Avantage                     | Explication                                                                                    |
| ---------------------------- | ---------------------------------------------------------------------------------------------- |
| **Économie d'espace**        | Le modèle n'est pas dupliqué dans le disque du conteneur (20 Go).                              |
| **Mise à jour facile**       | Télécharger un nouveau GGUF sur l'hôte, le conteneur le voit immédiatement.                    |
| **Sauvegarde indépendante**  | Les modèles peuvent être sauvegardés séparément du conteneur.                                  |
| **Partage entre conteneurs** | Un même modèle peut être monté dans plusieurs conteneurs (mais attention à la contention GPU). |

### 

### 1. Stocker les modèles hors du conteneur — via un bind mount

Sur l'hôte Proxmox, créez un dossier pour vos modèles (hors du conteneur) :

```bash
mkdir -p /mnt/models
# Placez-y vos fichiers .gguf
# Exemple : /mnt/models/qwen2.5-coder-7b-instruct-q4_k_m.gguf
```

Puis montez-le dans le conteneur exemple N° ID 102 pour mon `llama.cpp`  :

```bash
pct set 102 -mp0 /mnt/models,mp=/opt/models,ro=1
```

**Explication des options** :

- `-mp0` : point de montage n°0 (on peut en avoir plusieurs : `mp1`, `mp2`…).

- `/mnt/models` : chemin **sur l'hôte**.

- `mp=/opt/models` : chemin **dans le conteneur**.

- `ro=1` : **lecture seule** (recommandé pour les modèles, qui ne sont jamais modifiés par le conteneur).

Après cette commande, le contenu de `/mnt/models` sur l'hôte est **immédiatement visible** dans `/opt/models` du conteneur.

#### Méthode 2 (manuelle) — `lxc.mount.entry`

Éditez `/etc/pve/lxc/102.conf` et ajoutez :

`lxc.mount.entry: /mnt/models opt/models none bind,ro,create=dir 0 0`

Puis redémarrez le conteneur (`pct reboot 102`).

La méthode `pct set` est préférable car elle est gérée nativement par Proxmox (visible dans l'interface web, compatible avec les sauvegardes).

### 2. Point critique : les permissions en conteneur non privilégié

Votre conteneur est **unprivileged**. Cela signifie que :

- Les fichiers de `/mnt/models` sur l'hôte appartiennent à `root` (UID 0).

- Dans le conteneur, ils apparaissent comme appartenant à **UID 100000** (ou `nobody`).

Avec `ro=1` (lecture seule), cela ne pose aucun problème : le conteneur peut lire les fichiers même s'il n'en est pas propriétaire. C'est la configuration recommandée pour des modèles.

Si vous aviez besoin d'**écrire** dans ce dossier (ce qui n'est pas le cas pour des GGUF), il faudrait créer un groupe partagé avec le bon GID sur l'hôte et dans le conteneur, et ajuster les permissions.

---

## Exemple concret : de bout en bout

**Sur l'hôte Proxmox** :

```bash
# 1. Créer le dossier des modèles sur l'hôte
mkdir -p /mnt/models

# 2. Y placer le modèle (via scp, pct push ne sert plus à rien puisqu'il est déjà sur l'hôte)

# Supposons que le fichier soit déjà dans /mnt/models/

# 3. Vérifier
ls -lh /mnt/models/qwen2.5-coder-7b-instruct-q4_k_m.gguf

# 4. Monter dans le conteneur 102 en lecture seule
pct set 102 -mp0 /mnt/models,mp=/opt/models,ro=1

# 5. Redémarrer le conteneur pour que le mount soit pris en compte
pct reboot 102
```

**Dans le conteneur 102** :

bash

```bash
#Vérifier que le mount est actif
ls -lh /opt/models/

#Le fichier doit apparaître

#Lancer llama-server avec un chemin absolu

/opt/llama.cpp/build/bin/llama-server \
  -m /opt/models/qwen2.5-coder-7b-instruct-q4_k_m.gguf \
  -ngl 99 -c 8192 --host 0.0.0.0 --port 8080
```

### 6. Où placer les modèles sur l'hôte ?

Sur votre hôte un `rpool` (ZFS) vous pouvez créer un **dataset dédié** pour les modèles, ce qui facilite les snapshots et la gestion :

```bash
zfs create rpool/models

# Utiliser /rpool/models comme chemin
pct set 102 -mp0 /rpool/models,mp=/opt/models,ro=1
```

Ou plus simplement, utilisez `/mnt/models` si vous préférez un dossier classique.

### Résumé

| Question                                        | Réponse                                                |
| ----------------------------------------------- | ------------------------------------------------------ |
| Peut-on stocker les modèles hors du conteneur ? | ✅ **Oui**, via un bind mount LXC                       |
| Méthode recommandée                             | `pct set 102 -mp0 /mnt/models,mp=/opt/models,ro=1`     |
| Permissions en non-privilégié                   | ✅ OK si `ro=1` (lecture seule)                         |
| Où placer les modèles sur l'hôte                | `/mnt/models` ou un dataset ZFS dédié (`rpool/models`) |

Cette architecture est **plus propre** que de stocker les modèles dans le conteneur : Elle sépare les données (modèles) du système (conteneur), ce qui simplifie les sauvegardes et les mises à jour.
