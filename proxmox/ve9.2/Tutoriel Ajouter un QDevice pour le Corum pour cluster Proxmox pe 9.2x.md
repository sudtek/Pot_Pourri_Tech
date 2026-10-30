# Tutoriel : Ajouter un QDevice pour le corum Proxmox via machines tiers (RPI) !

Le **QDevice** (avec le service **QNetd**) sert à fournir une voix supplémentaire au système de quorum d'un cluster Proxmox (particulièrement utile pour les clusters à 2 nœuds). Il s'installe sur une machine tierce indépendante (un Raspberry Pi, un petit serveur Debian/Ubuntu, un routeur compatible ou un VPS) (

Note ! hormis pour un test il faut éviter de l'installer sur un autre hyperviseur type proxmox, vmware ... 

### 1. Préparer votre Raspberry Pi

Avant toute chose, assurez-vous que votre RPi est opérationnel avec une distribution Linux. La plus simple et recommandée est **Raspbian / Raspberry Pi OS**, car il est basé sur Debian[](https://pve.proxmox.com/mediawiki/index.php?oldid=10663&title=Raspberry_Pi_as_third_node)[](https://pve.proxmox.com/mediawiki/index.php?title=Raspberry_Pi_as_third_node&direction=prev&oldid=10663).

- Le système doit avoir un accès réseau stable et une **IP fixe** (ou une réservation DHCP) sur votre réseau.

### 2. Installer le service QDevice

Une fois connecté en SSH à votre Raspberry Pi, exécutez ces commandes pour installer le service `corosync-qnetd`:

```bash
sudo apt update
sudo apt install corosync-qnetd -y
```

### 3. Configurer le cluster Proxmox

La configuration se fait depuis l'un de vos nœuds Proxmox (par exemple, depuis R7).



1. **Installer le paquet client** sur **chaque nœud** de votre cluster (R7, PC01, PC02, VM-01 ...) :
   
   ```bash
   apt update && apt install corosync-qdevice -y
   ```
   
   

2. **Ajouter le QDevice au cluster** :  
   Depuis un seul nœud (par exemple, le R7), exécutez la commande suivante en remplaçant `<IP_DU_RASPBERRY>` par l'adresse IP de votre RPi :
   
   ```bash
   pvecm qdevice setup <IP_DU_RASPBERRY>
   ```
   
   Le système va vous demander le mot de passe root de votre Raspberry Pi pour finaliser la connexion SSH. C'est une étape normale qui permet d'établir la communication.
   
   

### ✅ 4. Vérifier que tout fonctionne

Pour confirmer que votre QDevice est bien intégré et qu'il vote, tapez la commande suivante sur n'importe quel nœud :



```bash
pvecm status
```

Vous devriez voir apparaître une ligne concernant le `Qdevice` dans les informations du quorum[](https://blog.jenningsga.com/proxmox-keeping-quorum-with-qdevices/).
