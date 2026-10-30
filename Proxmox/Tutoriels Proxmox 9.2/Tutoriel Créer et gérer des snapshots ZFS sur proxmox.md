# Tutoriel Créer et gérer des snapshots ZFS sur proxmox



Date : 30 octobre 2026

OS : proxmox 9.2

Autheur : Yannick SUDRIE



### Lister tous les snapshots ZFS

**Commande de base :**

```bash
zfs list -t snapshot
```

Cette commande liste **tous** les snapshots de **tous** les datasets de votre pool. 

La sortie ressemble à :

```text
NAME                                    USED  AVAIL  REFER  MOUNTPOINT
rpool/ROOT/pve-1@pre-update-llama.cpp   128K      -  2.18G  -
rpool/ROOT/pve-1@autre-snapshot         256K      -  2.50G  -
```

**Colonnes importantes :**

| Colonne | Signification                                                              |
| ------- | -------------------------------------------------------------------------- |
| `NAME`  | Nom du snapshot (format `dataset@nom`)                                     |
| `USED`  | Espace **exclusif** au snapshot (ce qui serait libéré si on le supprimait) |
| `REFER` | Espace **référencé** par le snapshot (taille logique)                      |

⚠️ **Attention** : `USED` ne représente pas la taille totale du snapshot. Comme ZFS est un système copy-on-write, un snapshot ne consomme que ce qui **<u>diffère du dataset parent depuis sa création</u>**.

### 🎯 Filtrer par dataset précis

Pour ne voir que les snapshots d'un dataset spécifique :

```bash
zfs list -t snapshot -r rpool/ROOT/pve-1
```

Ou pour un conteneur précis (les conteneurs LXC ont leurs propres datasets) :

```
zfs list -t snapshot -r rpool/data/subvol-100-disk-0
```

### 🕐 Ajouter des informations utiles

**Avec la date de création :**

```bash
zfs list -t snapshot -o name,creation,used,refer
```

Vous verrez la date et l'heure exactes de chaque snapshot — très utile pour s'y retrouver.

**Avec tri par date (plus récent en dernier) :**

```bash
zfs list -t snapshot -o name,creation -s creation
```

**Format lisible avec tailles en unités humaines :**

```bash
zfs list -t snapshot -o name,creation,used -H -p | awk '{print $1, strftime("%Y-%m-%d %H:%M", $2), $3/1024/1024" Mo"}'
```

### 📸 Exemple : le snapshot `pre-update-llama.cpp`

Une fois créé, vérifiez que le snapshot existe bien :

```bash
zfs list -t snapshot | grep pre-update
```

Vous devriez voir :

```text
rpool/ROOT/pve-1@pre-update-llama.cpp   128K      -  2.18G  -
```

### 🔧 Commandes ZFS utiles complémentaires

| Action                            | Commande                                       |
| --------------------------------- | ---------------------------------------------- |
| Lister tous les snapshots         | `zfs list -t snapshot`                         |
| Lister les snapshots d'un dataset | `zfs list -t snapshot -r <dataset>`            |
| Créer un snapshot                 | `zfs snapshot <dataset>@<nom>`                 |
| Supprimer un snapshot             | `zfs destroy <dataset>@<nom>`                  |
| Restaurer un snapshot             | `zfs rollback <dataset>@<nom>`                 |
| Voir les propriétés d'un snapshot | `zfs get all <dataset>@<nom>`                  |
| Comparer deux snapshots           | `zfs diff <dataset>@<snap1> <dataset>@<snap2>` |

### 💡 Astuce : alias pratique

Ajoutez cet alias à votre `~/.bashrc` sur l'hôte pour lister rapidement les snapshots avec leur date :



```bash
echo 'alias zsnaps="zfs list -t snapshot -o name,creation,used -s creation"' >> ~/.bashrc
source ~/.bashrc
```

Puis, tapez simplement `zsnaps` pour voir tous vos snapshots triés chronologiquement.

### 📌 Une fois le snapshot créé

Après avoir vérifié que votre snapshot `pre-update-llama.cpp` existe, vous pouvez lancer la mise à jour en toute sérénité :

```bash
apt update
apt dist-upgrade
reboot
```

Si quoi que ce soit se passe mal, vous pourrez revenir à l'état initial grâce à :

```bash
zfs rollback rpool/ROOT/pve-1@pre-update-llama.cpp
```

Vérifiez d'abord la liste de vos snapshots existants avec `zfs list -t snapshot`, puis créez celui pour la mise à jour. 
