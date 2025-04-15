# Mini-Tutoriel : Étendre le stockage en Ajoutant une disque à UmbrelOS

## Introduction

Ce tutoriel vous guide pour ajouter un disque dur (DD) supplémentaire à votre système **Umbrel OS**, optimiser son utilisation, et résoudre des problèmes courants. Il inclut des spécificités pour la virtualisation avec VMware et des références communautaires. Conçu comme un aide-mémoire, il est destiné aux utilisateurs d'Umbrel OS et publié sur GitHub pour la communauté.

## Prérequis

Avant de commencer, configurez votre environnement pour éviter des frustrations courantes, notamment avec le clavier ou la virtualisation.

1. **Virtualisation (VMware)** :
   - Configurez votre machine virtuelle avec le **BIOS UEFI**. L'installation à partir d'une ISO échoue avec un BIOS standard.
   - Installez les outils VMware pour activer le copier-coller et améliorer l'intégration :
     ```bash
     sudo apt update
     sudo apt install open-vm-tools
     ```

2. **Disposition du clavier (important pour les utilisateurs français)** :
   - En console, le clavier par défaut est en **QWERTY**, ce qui peut causer des erreurs de saisie, notamment pour le mot de passe (ex. : `a` devient `q` sur un clavier AZERTY). Corrigez ceci immédiatement :
     - **Changement temporaire** (avant connexion si possible) :
       ```bash
       sudo loadkeys fr
       ```
     - **Changement permanent** (après connexion) :
       ```bash
       sudo apt-get update
       sudo apt-get install console-data
       sudo localectl set-keymap fr
       ```
       Vérifiez la configuration :
       ```bash
       sudo localectl status
       ```

> **Note** : Appliquez ces prérequis dès que possible pour éviter des erreurs de connexion ou des saisies fastidieuses dans une VM sans copier-coller.

## Étape 1 : Préparation du nouveau disque dur

1. **Connexion du disque** :
   - Connectez votre nouveau disque dur. Dans une VM, ajoutez-le via les paramètres de la machine virtuelle.

2. **Identification du disque** :
   - Identifiez le disque avec :
     ```bash
     lsblk
     ```
   - Remplacez `/dev/sdX` par l'identifiant correct dans les commandes suivantes.

3. **Partitionnement** :
   - Créez une table de partition GPT avec une seule partition :
     ```bash
     echo -e "o\ny\nn\n1\n\n\n\nw\ny" | sudo gdisk /dev/sdX
     ```

4. **Formatage** :
   - Formatez la partition en ext4 :
     ```bash
     sudo mkfs.ext4 /dev/sdX1
     ```

## Étape 2 : Montage automatique du disque

1. **Identification de l'UUID** :
   - Trouvez le `PARTUUID` de la partition :
     ```bash
     sudo blkid /dev/sdX1
     ```
   - Exemple : `a0294ff5-c2f2-4a1f-a8fd-5f5c0435629a`.

2. **Modification de /etc/fstab** :
   - Ajoutez une entrée pour monter le disque automatiquement :
     ```bash
     sudo nano /etc/fstab
     ```
   - Ajoutez (remplacez `<PARTUUID>` et `/mnt/harddrive1` par votre point de montage, ex. : `/media/Disk_D2_2to`) :
     ```
     /dev/disk/by-partuuid/<PARTUUID>    /mnt/harddrive1    auto    rw,user,auto    0    0
     ```
   - Enregistrez (`Ctrl+O`, `Enter`, `Ctrl+X`).

3. **Montage immédiat** :
   - Appliquez les modifications :
     ```bash
     sudo mount -a
     ```
   - Vérifiez avec :
     ```bash
     df -h
     ```

## Étape 3 : Déplacement des applications vers le nouveau disque

1. **Copie des données** :
   - Copiez le répertoire des applications (`~/umbrel/app-data`) vers le nouveau disque :
     ```bash
     sudo rsync -cva ~/umbrel/app-data /mnt/harddrive1
     ```
   - Remplacez `/mnt/harddrive1` par votre point de montage (ex. : `/media/Disk_D2_2to`).

2. **Renommage de l'ancien répertoire** :
   - Conservez l'ancien comme sauvegarde :
     ```bash
     sudo mv ~/umbrel/app-data ~/umbrel/SAVapp-data
     ```

3. **Création d'un lien symbolique** :
   - Liez le nouveau répertoire au chemin attendu :
     ```bash
     sudo ln -s /mnt/harddrive1/app-data ~/umbrel/app-data
     ```
   - Vérifiez :
     ```bash
     ls -l ~/umbrel
     ```

> **Note** : `~/umbrel/app-data` contient toutes les données des applications. Sauvegardez-le régulièrement.

## Étape 4 : Gestion des mises à jour d'Umbrel OS

> **Attention** : Après une mise à jour ou un upgrade majeur de l'OS, le fichier `/etc/fstab` peut être écrasé, désactivant le montage du disque secondaire et cassant les liens symboliques. Vérifiez et restaurez vos modifications après chaque mise à jour.

Pour automatiser, créez un script shell (ex. : `restore_fstab.sh`) :

```bash
#!/bin/bash
# Script pour vérifier/restaurer fstab
echo "Vérification de /etc/fstab..."
if ! grep -q "<PARTUUID>" /etc/fstab; then
  echo "Ajout de l'entrée pour le disque..."
  echo "/dev/disk/by-partuuid/<PARTUUID> /mnt/harddrive1 auto rw,user,auto 0 0" | sudo tee -a /etc/fstab
fi
sudo mount -a
# Restaurer le lien symbolique si nécessaire
if [ ! -L ~/umbrel/app-data ]; then
  sudo ln -s /mnt/harddrive1/app-data ~/umbrel/app-data
fi
```
Rendez-le exécutable :
bash

```chmod +x restore_fstab.sh```

Exécutez-le après les mises à jour :
```bash
./restore_fstab.sh```

## Étape 5 : Informations sur le réseau
Vérifiez les interfaces réseau, adresses IP, routes, et DNS :

```bash
sudo nmcli
```

Pour plus de détails :
Appareils : ```nmcli device show```

Connexions : ```nmcli connection show```

Exemple de configuration :
Interface ens192 : IP 10.10.10.213/24, passerelle 10.10.10.254, DNS 10.10.10.254, 1.1.1.1, 1.0.0.1.

Interface docker0 : IP 172.17.0.1/16.

Emplacement des fichiers et des applications
Fichiers système : Umbrel OS sur /dev/sda1 (monté sur /).

Données des applications : Par défaut dans ~/umbrel/app-data, déplacé vers le nouveau disque (ex. : /mnt/harddrive1/app-data).

Fichier de configuration : /etc/fstab pour les montages.

Journaux et Docker : Montages bind pour /var/log, /var/lib/docker, etc., dans /etc/fstab.

**Liens communautaires**
Approfondissez ou résolvez des problèmes avec ces ressources :

- [Guide non officiel pour ajouter du stockage](https://community.umbrel.com/t/unofficial-guide-how-to-add-more-storage/18397)

- [Déplacer les applications vers un disque externe](https://community.umbrel.com/t/how-to-run-umbrel-apps-from-an-external-disk/12787)

Ce tutoriel vous permet d'étendre le stockage d'Umbrel OS, d'optimiser son fonctionnement, et de gérer les mises à jour ou la virtualisation. Sauvegardez régulièrement ~/umbrel/app-data et vérifiez /etc/fstab après les mises à jour.

