```
# Ajouter un Stockage Externe USB pour Steam sous Lubuntu

**Date : 05 février 2026**  
**Dernière mise à jour : février 2026**

Ce tutoriel explique comment ajouter un disque ou une clé USB externe comme stockage supplémentaire pour installer des jeux Steam sous **Lubuntu 22.04** (ou distributions similaires), lorsque l’interface Steam refuse de reconnaître le disque via les paramètres.

C’est particulièrement utile pour les mini-PC avec un petit SSD (ex. : 512 Go) en dual-boot Windows / Linux.

## Pourquoi ce tutoriel ?

Steam (surtout via Flatpak) ne détecte souvent pas les disques montés automatiquement par l’interface graphique.  
La solution consiste à :

- Monter le disque de façon permanente via `/etc/fstab`
- Ajouter manuellement la bibliothèque dans les fichiers de configuration de Steam

**Recommandation importante** : Installez Steam via **Flatpak** (pas via le paquet Debian officiel).

## Prérequis

- Lubuntu 22.04 (ou distribution Ubuntu-based récente)
- Une clé USB ou disque externe (1 To par exemple)
- Format recommandé : **ext4** (idéal pour Linux) ou **exFAT** (si besoin de compatibilité Windows)
- Accès administrateur (sudo)
- Steam installé via Flatpak

## Étape 1 – Préparer le disque / la clé USB

1. **Installer GParted** (si besoin pour formater)  
   ```bash
   sudo apt update && sudo apt install gparted -y
```

2. **Identifier les disques avant branchement**
   
   Bash
   
   ```
   lsblk -f
   ```

3. **Brancher la clé USB et relister** Notez le device (ex. /dev/sdb1) et surtout l’**UUID** :
   
   Bash
   
   ```
   lsblk -f
   ```
   
   Exemple de sortie :
   
   text
   
   ```
   sdb
   └─sdb1  ext4         d0d46435-1d41-4c83-b235-7a7f3629e3c5  916G   0%
   ```

4. **Formater si nécessaire** (via GParted)
   → ext4 recommandé
   → exFAT possible (moins performant sous Linux mais compatible Windows)

5. **Tester le montage** Montez via l’interface graphique, vérifiez lecture/écriture, puis démontez.

## Étape 2 – Montage permanent via fstab

1. **Vérifier le fstab actuel**
   
   Bash
   
   ```
   cat /etc/fstab
   ```

2. **Éditer fstab**
   
   Bash
   
   ```
   sudo nano /etc/fstab
   ```
   
   Ajoutez à la fin (adaptez UUID, utilisateur et point de montage) :
   
   Bash
   
   ```
   # Stockage USB pour jeux Steam
   UUID=d0d46435-1d41-4c83-b235-7a7f3629e3c5  /media/votreUtilisateur/GAMES  ext4  defaults,exec,user,nofail,noatime,nodiratime,x-systemd.device-timeout=8  0  2
   ```
   
   Pour **exFAT**, exemple alternatif :
   
   Bash
   
   ```
   UUID=XXXX-XXXX  /media/votreUtilisateur/GAMES  exfat  uid=1000,gid=1000,umask=0022,nofail  0  0
   ```

3. **Tester et appliquer**
   
   Bash
   
   ```
   sudo mount -a               # Vérifie les erreurs
   sudo systemctl daemon-reload
   ```

4. **Redémarrer et vérifier**
   
   Bash
   
   ```
   sudo reboot
   ```
   
   Après redémarrage :
   
   Bash
   
   ```
   mount | grep GAMES
   ```

5. **Corriger les permissions**
   
   Bash
   
   ```
   sudo chown -R votreUtilisateur:votreUtilisateur /media/votreUtilisateur/GAMES
   sudo chmod -R 775 /media/votreUtilisateur/GAMES
   ```

## Étape 3 – Installer Steam (Flatpak recommandé)

Bash

```
# Installer Flatpak si besoin
sudo apt install flatpak -y

# Ajouter le repo Flathub
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Installer Steam
flatpak install flathub com.valvesoftware.Steam -y
```

Optionnel : Flatseal pour gérer les permissions Flatpak

Bash

```
flatpak install flathub com.github.tchx84.Flatseal -y
```

## Étape 4 – Ajouter manuellement le dossier bibliothèque Steam

1. **Créer le dossier**
   
   Bash
   
   ```
   mkdir -p /media/votreUtilisateur/GAMES/STEAM/SteamLibrary
   ```

2. **Trouver les fichiers libraryfolders.vdf**
   
   Bash
   
   ```
   find ~ -name "libraryfolders.vdf"
   ```
   
   Chemins typiques avec Flatpak :
   
   text
   
   ```
   ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/libraryfolders.vdf
   ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/config/libraryfolders.vdf
   ```

3. **Éditer les deux fichiers** (avec nano ou votre éditeur préféré)
   
   Ajoutez ce bloc **avant la dernière accolade }** :
   
   JSON
   
   ```
   "1"
      {
          "path"          "/media/votreUtilisateur/GAMES/STEAM/SteamLibrary",
          "label"         "",
          "contentid"     "",
          "totalsize"     "",
          "update_clean_bytes_tally"   "",
          "time_last_update_verified"  "",
          "apps"
          {
          }
      }
   ```

4. **Enregistrer et quitter**

## Étape 5 – Vérification finale

- Lancez Steam :
  
  Bash
  
  ```
  flatpak run com.valvesoftware.Steam
  ```

- Allez dans **Steam → Paramètres → Stockage** Vous devriez maintenant voir le nouveau stockage

- Lors de l’installation d’un jeu, choisissez ce nouvel emplacement

## Astuces & dépannage

- Si le disque n’apparaît toujours pas → utilisez **Flatseal** pour ajouter l’accès au dossier :
  → Filesystems supplémentaires : /media/votreUtilisateur/GAMES

- Pour exFAT, vérifiez que le paquet exfat-fuse ou exfatprogs est installé

- Sauvegardez toujours /etc/fstab avant modification :
  
  Bash
  
  ```
  sudo cp /etc/fstab /etc/fstab.bak
  ```

Bonne installation et bon jeu ! 🎮

N’hésitez pas à ouvrir une **issue** si quelque chose ne fonctionne pas sur votre configuration.
