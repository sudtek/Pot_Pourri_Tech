# Tutoriel Mise à jour d'un PROXMOX (faire un un SNAPSHOT ZFS)

Date  : 30 octobre 2026

OS  : proxmox 9.2

Autheur : Yannick SUDRIE

### Un système à jour vous garantit :

- **Les correctifs de sécurité** et de stabilité du noyau et des paquets de base.

- **La cohérence des dépôts** : installer de nouveaux paquets (comme ceux nécessaires à Vulkan) sur un système obsolète peut mener à des conflits de dépendances difficiles à résoudre.

- **Un environnement sain** pour la compilation : les outils comme `cmake` ou `gcc` seront dans leur version la plus récente et la plus compatible.

### ### ⚠️ La précaution indispensable : le snapshot ZFS

Avant de lancer la mise à jour, **il est indispensable de créer un snapshot de votre système de fichiers racine**. Comme votre hôte est installé sur ZFS, c'est une opération très rapide et réversible qui vous permettra de revenir en arrière en cas de problème[](https://ayinedjimi-consultants.fr/articles/mise-a-jour-proxmox-ve-9-guide-complet#2).

Depuis un shell sur l'hôte Proxmox, exécutez :

`zfs snapshot rpool/ROOT/JJ_MM_AAAA_pve-1@pre-update`

Cette commande crée un instantané de votre système actuel. Si la mise à jour échoue ou rend le système instable, vous pourrez redémarrer sur l'ISO Proxmox, importer le pool ZFS et exécuter un rollback pour retrouver votre système dans son état initial.

### La procédure complète, étape par étape

1. **Snapshot de sécurité (sur l'hôte) :**
   
   ```bash
   zfs snapshot rpool/ROOT/JJ_MM_AAAA_pve-1@pre-update
   ```

2. **Mise à jour des sources et des paquets (sur l'hôte) :**
   
   ```bash
   apt update
   apt dist-upgrade
   ```

3. **Redémarrage de l'hôte :**
   
   ```bash
   reboot
   ```

4. **Vérification post-redémarrage :**  
   Une fois reconnecté, vérifiez que tout est en ordre :
   
   ```bash
   pveversion
   uname -r
   zpool status
   ```
   
   Cela confirmera que la nouvelle version est bien active et que le pool ZFS est sain[](https://ayinedjimi-consultants.fr/articles/mise-a-jour-proxmox-ve-9-guide-complet#2).
