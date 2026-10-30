# Configuration d'un node Proxmox

### Configuration d'un node

Si votre machine proxmox manque de resources physique exemple : 8GB RAM,1 ssd et/ou quelques disque durs sata de récup ... il va falloir  :

- Limiter la mémoire ram reservée par ZFS en fixant un quota.

- Toujours choisir ZFS pour les systémes de pool sinon on ne peut pas faire de cluster ! Si un seul SSD ou DD -> ZFS 0; Si 4 DD sata -> RAID10
  
  

<u>**Note : Ne jamais utiliser le raid intel integré des vielles cartes méres pour créer un pool ZFS  -> désactiver l'option au BIOS !**</u>



Limitation de la mémoire RAM consommée à 3Go pour ZFS (important pour les vieux PC)

```bash
echo "options zfs zfs_arc_max=2000000000" >> /etc/modprobe.d/zfs.conf


update-initramfs -u


reboot
```

8Go ram -> 2000000000  ou 3000000000 ca va monopoliser entre 2Go et 3Go de la ram de la machine !



**Note : ATTENTION CEPH est totalement hors de porté des vielles machines ou d'un parc trop hétérogène.**

---



### Interface reseau principal

Verifier que 'interface réseau porte **réellement** l'IP exemple  exemple : `10.10.10.50`.

```bash
ip a | grep 10.10.10.50
```

Si ce n'est pas le cas, éditer `/etc/network/interfaces` pour y mettre cette IP statique avant de continuer.

---



### Les PAQUET

Désactiver **les paquets proxmox car ils nécessitent une licence payante** pour choisir la version contribution et faire direct un ajout des paquets communeautaires puis lancer une mise à jour !

![](C:\Users\yannick%20sudrie\AppData\Roaming\marktext\images\2026-10-30-01-59-59-image.png)

```bash
 apt-get update
```

 ou en cas d'erreur de mise à jour 

```bash
apt-get update --fix-missing
```

---



### CHRONY

- Ajouter les pools NTP :

```bash
cat /etc/chrony/chrony.conf

# Use Debian vendor zone.
# pool 2.debian.pool.ntp.org iburst
# Mon serveur de temps local
server 10.10.10.254 iburst
server pfsense.{votreDomaine}.net iburst
# serveurs publics en secours
server time.google.com iburst
server 0.fr.pool.ntp.org iburst
server 1.fr.pool.ntp.org
```

- Interdire à chrony d'utiliser IPV6 et favoriser IPV4 pour NTP :

```bash
cat /etc/default/chrony 
# This is a configuration file for /etc/init.d/chrony and
# /lib/systemd/system/chrony.service; it allows you to pass various options to
# the chrony daemon without editing the init script or service file.

# Options to pass to chrony.
# DAEMON_OPTS="-F 1" # chrony utilise le protocole ipv6 pour requeter le serveur NTP local 
# Chrony utilise uniquement le protocole ipv4 pour requeter le serveur NTP 
DAEMON_OPTS="-F 1 -4"
```

---



### Resolution de noms local via le fichiers hosts

On ne peut pas s'appuyer / compter sur la resolution de nom du pfsense; s'il tombe on perd la resolution de nom dans le réseaux local ... donc il faut coder en dur les membres du cluster dans le fichier hosts  respectifs de chaque machine (exemple de host du node pve-proxmox-R7 ) :

```bash
cat /etc/hosts

127.0.0.1 localhost.localdomain localhost
# ---- PROXMOX PVE ----
10.10.10.50 pve-proxmox-R7.{votreDomaine}.net pve-proxmox-R7
10.10.10.51 pve-proxmox-01.{votreDomaine}.net pve-proxmox-01
10.10.10.52 pve-proxmox-02.{votreDomaine}.net pve-proxmox-02
# 10.10.10.53 (reservation)
# 10.10.10.54 (reservation)
10.10.10.55 pve-proxmox-VM-01.{votreDomaine}.net pve-proxmox-VM-01
# 
# ---- PROXMOX DATA BACKUP ----
10.10.10.60 backup-proxmox-01.{votreDomaine}.net backup-proxmox-01
#
10.10.10.65 backup-proxmox-VM-01.{votreDomaine}.net backup-proxmox-VM-01
#
#
# ---- PROXMOX DATA MANAGER ----
10.10.10.70 manager-proxmox-VM-01.{votreDomaine}.net manager-proxmox-VM-01
# PROXMOX MAIL MANAGER
10.10.10.75 mail-proxmox-VM-01.{votreDomaine}.net mail-proxmox-VM-01
#

# The following lines are desirable for IPv6 capable hosts

::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
```
