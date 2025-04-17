# Installation de Docker Desktop sur Lubuntu 22.04 LTS (VM avec KVM sous VMware) #

Ce guide explique étape par étape comment installer Docker Desktop sur une machine virtuelle (VM) Lubuntu 22.04 LTS utilisant KVM, hébergée sur VMware Workstation 16.1 sous Windows 10. Il traite des problèmes courants, comme les conflits avec Hyper-V, et intègre des mesures de sécurité pour protéger les jetons d\'accès personnels (PAT) utilisés
pour l'authentification.

# Prérequis #

- OS Hôte : Windows 10 Professionnel (Build 19045 ou supérieur)
- Hyperviseur : VMware Workstation 16.1 ou version ultérieure
- OS VM : Lubuntu 22.04 LTS (Jammy Jellyfish, installation propre et jour)
- BIOS : Virtualisation activée (Intel VT-x/AMD-V)
- CPU Hôte : Intel64 Family 6 Model 58 (ou équivalent) avec support de la virtualisation
- Paramètres CPU VM : Activer "**Virtualize Intel VT-x/EPT** OU **AMD-V/RVI**" ET "**Virtualize IOMMU**" dans le fichier .vmx de la VM ou les paramètres VMware
- Mémoire VM : Minimum 4 Go (8 Go recommandés pour de meilleures performances)
- Stockage VM : Au moins 20 Go d'espace disque libre.
- Réseau : Connexion Internet stable pour les téléchargements de paquets et l'authentification Docker Hub.

**Note : Vérifiez que votre CPU supporte la virtualisation imbriquée et que celle-ci est activée dans le BIOS. Utilisez vmware -v ou consultez les journaux VMware si la VM ne démarre pas.**

# Étape 1 : Résoudre les conflits Hyper-V sous Windows #

Hyper-V peut bloquer la virtualisation imbriquée nécessaire à KVM.
Suivez ces étapes pour le désactiver complètement :

## 1.  Désactiver Hyper-V via l'interface graphique : ##

- Ouvrez **"Panneau de configuration"** -> **"Programmes et fonctionnalités"** -> **"Activer / désactiver des fonctionnalités Windows"**.
- Décochez toutes les options Hyper-V (y compris "Plateforme Hyper-V" et "Outils de gestion Hyper-V").
- Cliquez sur OK et redémarrez le système.

## 2.  Vérifier l'état d'Hyper-V : ##

- Exécutez systeminfo dans l'Invite de commandes et vérifiez la section "Exigences Hyper-V". Elle doit indiquer qu'aucun hyperviseur n'est détecté.
- Sinon, ouvrez msinfo32 et assurez-vous que \"Sécurité basée sur la virtualisation\" est Non actif.

## 3.  Désactiver le lancement de l'hyperviseur (CMD en mode administrateur) : ##   

```shell
bcdedit /set hypervisorlaunchtype off
```

## 4.  Supprimer les fonctionnalités Hyper-V (PowerShell en mode administrateur) : ##

```shell
Disable-WindowsOptionalFeature -Online -FeatureName
Microsoft-Hyper-V-All
```

## 5.  Redémarrer le système : ##

- Redémarrez Windows pour appliquer les modifications.

Dépannage : Si la VM ne démarre toujours pas avec **VT-x/AMD-V** activé, assurez-vous que VMware Workstation est à jour et vérifiez dans le fichier **.vmx** que ```svhv.enable = "TRUE"```.

# Étape 2 : Installer et configurer KVM dans la VM Lubuntu KVM est requis pour que Docker Desktop exécute sa propre VM interne. #

Suivez ces étapes pour l'installer :

## 1.  Vérifier le support de virtualisation du CPU : ##

```bash
sudo apt update
sudo apt install cpu-checker
kvm-ok
```

- Résultat attendu : ```INFO: /dev/kvm exists``` et ```KVM acceleration can be used```.

- Erreur possible : Si vous voyez ```Your CPU does not support KVM extensions```, Hyper-V est probablement encore actif. Revenez à l'étape 1 ou vérifiez les paramètres de virtualisation CPU dans VMware.

## 2.  Installer les modules KVM : ##

 - Pour les processeurs Intel :

```bash
sudo modprobe kvm_intel
```

- Pour les processeurs AMD :
```bash
sudo modprobe kvm_amd
```

## 3.  Vérifier l'installation de KVM : ##

```bash
kvm-ok
lsmod | grep kvm
```

- Cherchez kvm_intel ou kvm_amd dans la sortie de lsmod.

## 4.  Configurer les permissions utilisateur : ##

```bash
sudo usermod -aG kvm $USER
ls -al /dev/kvm
```   
- Assurez-vous que ```/dev/kvm``` existe avec des permissions comme ```crw-rw----+ 1 root kvm```.
- Déconnectez-vous et reconnectez-vous pour appliquer les changements de groupe.

Dépannage : Si ```/dev/kvm``` est absent ou inaccessible, vérifiez si le module kvm est chargé ```lsmod | grep kvm```. Rechargez le module si nécessaire ou réinstallez qemu-kvm avec ```sudo apt install qemu-kvm```.

# Étape 3 : Installer Docker Desktop sur Lubuntu #

Docker Desktop nécessite un OS basé sur Ubuntu 64 bits et certaines dépendances. Suivez ces étapes :

## 1.  Installer les prérequis : ##

```bash
sudo apt update
sudo apt install gnome-terminal
```
- gnome-terminal est requis pour les environnements de bureau non-GNOME comme LXQt de Lubuntu.

## 2.  Configurer le dépôt Docker : ##

```bash
sudo apt install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) igned-by=/etc/apt/keyrings/docker.gpg]
https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee
/etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
```
## 3.  Télécharger et installer Docker Desktop : ##

- Téléchargez le dernier paquet .deb (par exemple, version 4.26.1) :

```bash
wget https://desktop.docker.com/linux/main/amd64/docker-desktop-4.26.1-amd64.deb
```

- Installez le paquet :

```bash
sudo apt install ./docker-desktop-4.26.1-amd64.deb
```

## 4.  Vérifier l'installation : ##

```bash
docker -v
docker-credential-desktop version
docker-index version
```

- Résultats attendus :
- Docker version 25.0.0, build e758fe5 (ou plus récent)
- docker-credential-desktop v0.7.0
- docker-index v0.0.35

## 5.  Lancer Docker Desktop : ##

```bash
systemctl --user start docker-desktop
```
- Alternativement, utilisez le raccourci Docker Desktop dans le menu Programmation.

Dépannage :
- Si Docker Desktop échoue avec une erreur ```KVM virtualization support needed```, revérifiez la configuration de KVM (Étape 2).
- Si l'installation échoue, assurez-vous que le paquet .deb correspond à l'architecture amd64 et videz le cache APT avec ```sudo apt clean```.

# Étape 4 : Configurer l'authentification Docker Desktop #

Docker Desktop utilise le fichier ```~/.docker/config.json``` pour l'authentification avec Docker Hub ou d'autres registres. Un compte Docker Hub gratuit est limité à 5 jetons d'accès personnels (PAT), gérez-les avec soin.

Avertissement de sécurité : Si une version précédente de ce tutoriel ou un document connexe a inclus un PAT réel, révoquez-le immédiatement via [hub.docker.com](https://hub.docker.com/) ("**Paramètres**" -> "**Sécurité**" -> "**Jetons d'accès personnels**") pour éviter tout accès non autorisé à votre compte.

## 4.1. Sécurité des jetons d'accès personnels (PAT) ##

- Ne partagez jamais vos PAT dans des fichiers publics, dépôts GitHub, ou forums. Une fuite peut compromettre votre compte Docker Hub.

- Si un PAT est exposé, révoquez-le immédiatement via l'interface Docker Hub.

- Utilisez des PAT avec des permissions minimales (par exemple, lecture seule pour tirer des images) et configurez une expiration (par exemple, 30 jours).

- Protégez le fichier ```~/.docker/config.json``` avec des permissions restrictives :

```bash
chmod 600 \~/.docker/config.json
```
- Ne versionnez jamais ce fichier dans un dépôt public (ajoutez-le à .gitignore).

## 4.2. Configuration initiale ##

- Au premier lancement, Docker Desktop créé ```~/.docker/config.json``` et peut ouvrir un navigateur pour se connecter à Docker Hub.

- Sauvegardez la configuration par défaut :

```bash
cp ~/.docker/config.json ~/.docker/config.json.bak
```

- Exemple de configuration config.json par défaut :

```bash
cat ~/.docker/config.json
```

```json
{
"auths": {},
"credsStore": "desktop",
"currentContext\": "desktop-linux\"
}
```
- ```"credsStore": "desktop"``` déclenche l'authentification via navigateur / Dashboard local de l'application Docker-desktop.
- ```"currentContext": "desktop-linux"``` indique le contexte de Docker Desktop, distinct de Docker autonome.

Docker-Desktop peut utiliser le gestionaire de mot de passe nommé pass https://www.passwordstore.org/ basé sur gpg sous linux mais ce n'est pas obligatoire. Il existe d'autres méthodes (https://docs.docker.com/desktop/get-started/#credentials-management-for-linux-users)[https://docs.docker.com/desktop/get-started/#credentials-management-for-linux-users]. eexemple avec ```pass``` sous linux.

```bash
which pass
```bash

```#/usr/bin/pass```

Dans ce cas la config.json devra avoir la directive

```json 
config.json{
        "auths": {},
        "credsStore": "**pass**","desktop",
        "currentContext": "desktop-linux"
        }
```


## 4.3. Utiliser un jeton d'accès personnel (PAT) ##

Avertissement de sécurité : Le jeton ````dckr_pat_EXEMPLE_FICTIF_1234567890``` est fictif et utilisé à des fins d'illustration. Ne partagez jamais un PAT réel dans des documents, dépôts GitHub, ou forums publics, car cela pourrait compromettre votre compte Docker Hub.

### 1.  Générez un PAT sur Docker Hub : ###

- Connectez-vous à [hub.docker.com](https://hub.docker.com/), allez dans **Paramètres du compte** -> **Sécurité** -> **Jetons d'accès personnels**.
- Créez un jeton avec des permissions minimales (par exemple, lecture seule) et une expiration (par exemple, 30 jours). Exemple fictif : dckr_pat_EXEMPLE_FICTIF_1234567890.

### 2.  jeton en Base64 : ###

Utiliser un token (R/W) pregenere depuis / sur le site docker : **dckr_pat_xxxxxxxxxxxxx-xxxx-xxxxxx** et le convertir en base 64 :

```bash
echo -n 'dckr_pat_xxxxxxxxxxxxx-xxxx-xxxxxx' | base64
```
Generera notre token fictif base64 : 

```ZGtyX3BhdF9FWEVNUExFX0ZJQ1RJRl8xMjM0NTY3ODkw```


Utilisation d'un Jeton fictif base64 : ```ZGtyX3BhdF9FWEVNUExFX0ZJQ1RJRl8xMjM0NTY3ODkw```

### 3.  Mettez à jour config.json : ###

```json
       {
           "auths": {
               "https://index.docker.io/v1/": {
                   "auth": "ZGtyX3BhdF9FWEVNUExFX0ZJQ1RJRl8xMjM0NTY3ODkw"
               }
           },
           "credsStore": "desktop",
           "currentContext": "desktop-linux",
           "plugins": {
               "-x-cli-hints": {
                   "enabled": "true"
               }
           }
       }
```

## 5.  Protégez le fichier config.json : ##

```bash
chmod 600 \~/.docker/config.json
```
- Ajoutez ```~/.docker/config.json``` à **.gitignore** pour éviter son versionnement dans un dépôt public.

**Conseil : Si un PAT est accidentellement exposé, révoquez-le immédiatement via l'interface Docker Hub et générez un nouveau jeton.**

### 1. Utiliser un gestionnaire de mots de passe (facultatif) ###

Pour éviter d'inclure des PAT en clair, vous pouvez utiliser un gestionnaire de mots de passe comme pass ou stocker les identifiants dans des variables d'environnement sécurisées.

- Installez pass :

```bash
sudo apt install pass
```

- Mettez à jour config.json pour utiliser pass :

```json
  {
  "auths": {},
  "credsStore": "pass",
  "currentContext": "desktop-linux"
  }
```

- Initialisez pass avec votre nom d'utilisateur et mot de passe DockerHub (pas l'email) :

```bash
pass init
pass insert docker-credential-desktop
```

- **NOTE 1** : Chaque tentative d'authentification ajoute automatiquement un token sur le site web de docker (https://hub.docker.com/signup)[https://hub.docker.com/signup] sauf qu'on est limité à 5 token maximum !!! Cela implique de faire le menage régulierement à la main (voir onglet security du site).

- **NOTE 2** : ATTENTION pour pass et / ou via la commande login; il faut imperativement utiliser la même typo que le nickname utilisateur docker (sensible à la case) qui apparait lorsque l'on se connecte à l'interface web de docker mais ne pas utiliser votre Email pour vous connecter via pass et/ou login car votre email n'est pas votre nickname utilisateur docker !!!

- **NOTE 3** :  Pass ou login requier toujours un couple (nickname utilisateur docker ; mot de passe) ou ( <token> ; leTokenenBase64 )(https://docs.docker.com/engine/reference/commandline/login/)[https://docs.docker.com/engine/reference/commandline/login/]

- **NOTE 4** : Docker-Desktop peut aussi s'hautentifier à des dépots publics ou privés autre que celui par defaut de docker (privé local, github, amazon ...) en faisant varier les methodes ( Ce serait d'avoir une liste d'exemples clefs en main car c'est chronophage de chercher et tester chaque cas ...)

Exemples (non verifiés !!!) de ```.docker/config.json``` 

```json
{
        "auths": {
                "https://index.docker.io/v1/": {auth": "ZGtyX3BhdF9FWEVNUExFX0ZJQ1RJRl8xMjM0NTY3ODkw"}
        },
        "credsStore": "desktop",
        "currentContext": "desktop-linux",
        "plugins": {
                "-x-cli-hints": {
                        "enabled": "true"
                }
        }
}
```

```json
{
        "auths": {},
        "credsStore": "pass","desktop",
        "currentContext": "desktop-linux",
        "plugins": {
                "-x-cli-hints": {
                        "enabled": "true"
                }
        }
}
```



Autre provenant de https://dev.to/mattdark/docker-setting-up-a-credential-helper-4nbh

```json
{
        "auths": {},
        "currentContext": "desktop-linux",
        "auth": "ZGtyX3BhdF9FWEVNUExFX0ZJQ1RJRl8xMjM0NTY3ODkw"
        "plugins": {
                "-x-cli-hints": {
                        "enabled": "true"
                }
        }
}
```

Exemple sous windows :
```json
{
  "auths": {
    "https://index.docker.io/v1/": {}
  },
  "credsStore": "desktop.exe"
}
```


```json
{
        "auths": {
                "https://index.docker.io/v1/":{} },
        "credsStore": "desktop",
        "currentContext": "desktop-linux",
        "auth": "ZGtyX3BhdF9FWEVNUExFX0ZJQ1RJRl8xMjM0NTY3ODkw"
        "plugins": {
                "-x-cli-hints": {
                        "enabled": "true"
                }
        }
}
```

```json
{
       "auths": {
                "https://index.docker.io/v1/": {"auth": "ZGtyX3BhdF9FWEVNUExFX0ZJQ1RJRl8xMjM0NTY3ODkw"}
                },
        "credsStore": "desktop",
        "currentContext": "desktop-linux",
        "plugins": {
                "-x-cli-hints": {
                        "enabled": "true"
                }
        }
}
```

ect ...


-------


**Dépannage :**
- Erreurs d'authentification : Vérifiez que le PAT est valide et non expiré. Régénérez-le si nécessaire.
  
- Limite de jetons atteinte : Supprimez les anciens jetons via l'interface web de Docker Hub, en version gratuite vous avez droit au maximu à 5 tokens permanents voir sur votre nickname onglet **security** pour gerer vos tokens PAT.
  
- Problèmes de contexte : Si les commandes échouent, vérifiez le contexte avec docker context ls et définissez-le sur desktop-linux avec docker context use desktop-linux.

**Notes supplémentaires :**

- Docker vs Docker Desktop : Docker Desktop inclut son propre binaire Docker mais fonctionne dans un contexte distinct (desktop-linux).
  
- Docker autonome peut coexister mais nécessite une configuration séparée.

**Conseils de performance :**
- Allouez au moins 2 cœurs CPU et 8 Go de RAM à la VM pour des performances optimales.
  
- Activez l'accélération 3D de VMware pour les conteneurs avec interfaces graphiques.
  
- Mise à jour de Docker Desktop : Vérifiez périodiquement le [site officiel de Docker](https://docs.docker.com/desktop/install/ubuntu/) pour de nouveaux paquets .deb et répétez l'étape 3.3.
  
- Registres alternatifs : Pour utiliser des registres privés (par exemple, GitHub Container Registry), ajoutez leurs URL et identifiants dans auths de config.json.

**Problèmes courants et solutions :**
- La VM ne démarre pas : Assurez-vous que VT-x/AMD-V est activé dans le BIOS et les paramètres VMware. Vérifiez que ``` vhv.enable = \"TRUE\" ``` dans
  le fichier **.vmx**.
  
- KVM non détecté : Exécutez ``` sudo dmesg | grep kvm ``` pour diagnostiquer les problèmes de module. Réinstallez qemu-kvm si nécessaire.
  
- Docker Desktop plante : Consultez les journaux dans ``` ~/.docker/desktop/log ``` et assurez-vous d'avoir suffisamment d'espace disque.
  
- Problèmes de réseau : Vérifiez que l'adaptateur réseau de la VM est configuré en NAT ou Bridge dans VMware et que la résolution DNS fonctionne (ping hub.docker.com).

# Ressources #

- [Installation de Docker Desktop pour Linux](https://docs.docker.com/desktop/install/ubuntu/)
  
- [Support KVM pour Docker](https://docs.docker.com/desktop/install/linux-install/#kvm-virtualization-support)
  
- [Gestion des identifiants Docker](https://docs.docker.com/desktop/get-started/#credentials-management-for-linux-users)
  
- [Guide VMware sur la virtualisation imbriquée](https://docs.vmware.com/fr/VMware-Workstation-Pro/16.0/com.vmware.ws.using.doc/GUID-E6E4A6BE-800C-42F8-A05E-53F33F5D9C7D.html)
