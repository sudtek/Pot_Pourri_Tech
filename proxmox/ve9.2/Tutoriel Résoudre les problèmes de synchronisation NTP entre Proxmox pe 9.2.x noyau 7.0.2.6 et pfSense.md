# Tutoriel : Résoudre les problèmes de synchronisation NTP entre Proxmox pe 9.2.x noyau 7.0.2.6 et pfSense

## Contexte

Lors de la mise en place d'un cluster Proxmox, la synchronisation NTP est un prérequis essentiel. Ce tutoriel documente les problèmes rencontrés et leurs solutions lors de la synchronisation de nœuds Proxmox avec un serveur NTP hébergé sur pfSense.

### Problèmes identifiés

1. **IPv6 vs IPv4** : Proxmox (via chrony) tente de résoudre les noms DNS en IPv6 par défaut, nécessitant des règles firewall dédiées.

2. **Firewall pfSense** : Le trafic NTP (UDP 123) doit être explicitement autorisé sur l'interface LAN.

3. **KOD (Kiss-of-Death)** : Mécanisme de protection activé par défaut sur pfSense qui bloque les requêtes NTP jugées trop fréquentes.

---

## Prérequis

- pfSense installé et configuré comme serveur NTP avec resolution de nom activé pour et une resolution de nom fonctionelle pour les leasing du serveur dhcp (se reporter à ce tutoriel  [Configurer son DNS personnel avec pfSense](https://www.arsouyes.org/articles/2019/23_DNS_Personnel/))

- Un ou plusieurs nœuds Proxmox VE (version 7+ avec chrony)

---

## 1. Configuration du serveur NTP sur pfSense

### 1.1 Ajout des serveurs NTP

1. Connectez-vous à l'interface web de pfSense

2. Allez dans **Services > NTP**

3. Dans la section **NTP Servers**, ajoutez plusieurs sources les pbs d'arbitrage :

0.fr.pool.ntp.org (avec option "Is a Pool" cochée)
1.fr.pool.ntp.org (avec option "Is a Pool" cochée)
2.fr.pool.ntp.org (avec option "Is a Pool" cochée)
time.google.com

**Note: Ne surtout pas ajouter uniqument 2 sources pour resoudre. Vous pouvez en ajouter une seul si c'est un pool : time.google.com **

4. **Important** : Dans le champ **Interface**, sélectionnez **`All (recommended)`** pour que le service écoute sur toutes les interfaces.

![](https://github.com/sudtek/Pot_Pourri_Tech/blob/dc0006d2f1a470af3d5201bc76cc135566bcf63a/proxmox/ve9.2/png/configuration_globale_NTP.png)

### 1.2 Désactivation du KOD (Kiss-of-Death)

1. Dans **Services > NTP**, cliquez sur l'onglet **Access Restrictions**

2. Dans la section **Default Access Restrictions**, **décochez** la case **`Enable Kiss-o'-death packets`**

3. Cliquez sur **Save** puis **Restart** en bas de la page

![](https://github.com/sudtek/Pot_Pourri_Tech/blob/dc0006d2f1a470af3d5201bc76cc135566bcf63a/proxmox/ve9.2/png/configuration_globale_NTP_ACLs.png)



### 1.3 Règle de pare-feu pour autoriser le trafic NTP

1. Allez dans **Firewall > Rules**

2. Sélectionnez l'onglet de votre interface LAN

3. Ajoutez une règle (bouton **Add** en haut) :

| Paramètre        | Valeur                           |
| ---------------- | -------------------------------- |
| Action           | `Pass`                           |
| Protocol         | `UDP`                            |
| Source           | `LAN net` (ou votre sous-réseau) |
| Destination      | `This Firewall`                  |
| Destination Port | `123` (NTP)                      |
| Description      | `Allow NTP to pfSense`           |

4. Sauvegardez et appliquez les changements

![](https://github.com/sudtek/Pot_Pourri_Tech/blob/dc0006d2f1a470af3d5201bc76cc135566bcf63a/proxmox/ve9.2/png/pare-feu_Regles_LAN.png)


Vérifier que votre ntp a un pair actif actif sur pfsense :

![](https://github.com/sudtek/Pot_Pourri_Tech/blob/dc0006d2f1a470af3d5201bc76cc135566bcf63a/proxmox/ve9.2/png/NTP_Etat.png)
---

## 2. Configuration de chrony sur Proxmox (IPv4 uniquement)

### 2.1 Forcer chrony à n'utiliser que l'IPv4



Éditer le fichier de configuration

```bash
nano /etc/default/chrony
```

Modifiez la ligne `DAEMON_OPTS` comme suit :

```bash
DAEMON_OPTS="-F 1 -4"
```

Sauvegardez (`Ctrl+O`, `Entrée`) et quittez (`Ctrl+X`).

### 2.2 Configurer les sources NTP de proxmox

Éditer le fichier principal de chrony

```bash
nano /etc/chrony/chrony.conf
```

Commentez ou supprimez les lignes existantes et ajoutez Sources NTP (pfSense local et serveurs publics en secours) :

```
# serveur privé intranet pfsense
server 10.10.10.254 iburst
server pfsense.monintranet.net iburst

# serveurs publics en secours
server time.google.com iburst
server 0.fr.pool.ntp.org iburst
server 1.fr.pool.ntp.org iburst

```



> **Note** : 
> 
> - Remplacez `10.10.10.254` par l'IP de votre pfSense.
> 
> - Remplacez `pfsense.monintranet.net`  par votre FQDN si votre resolution DNS est fonctionelle sinon effacé le !



### 2.3 Redémarrer et vérifier

Redémarrer le service :

```bash
systemctl restart chrony
```

Vérifier le statut

```
systemctl status chrony
```

Vérifier les sources NTP disponibles

```
chronyc sources -v
```

Vérifier la synchronisation

```
timedatectl
```

Si tout est OK vous devriez avoir un équivalent  :

```
root@pve-proxmox-R7:~# systemctl status chrony
● chrony.service - chrony, an NTP client/server
     Loaded: loaded (/usr/lib/systemd/system/chrony.service; enabled; preset: enabled)
     Active: active (running) since Wed 2026-06-24 05:47:24 CEST; 48min ago
 Invocation: 682916968da442c4b5a060de7389cdaa
       Docs: man:chronyd(8)
             man:chronyc(1)
             man:chrony.conf(5)
    Process: 819 ExecStart=/usr/sbin/chronyd $DAEMON_OPTS (code=exited, status=0/SUCCESS)
   Main PID: 923 (chronyd)
      Tasks: 2 (limit: 34365)
     Memory: 6.1M (peak: 6.8M)
        CPU: 59ms
     CGroup: /system.slice/chrony.service
             ├─923 /usr/sbin/chronyd -F 1 -4
             └─929 /usr/sbin/chronyd -F 1 -4

Jun 24 05:47:24 pve-proxmox-R7 chronyd[923]: chronyd version 4.6.1 starting (+CMDMON +NTP +REFCLOCK +RTC +PRIVDROP +SCFILTER +SIGND +ASYNCDNS +NTS +SECHASH +IPV6 -DEBUG)
Jun 24 05:47:24 pve-proxmox-R7 chronyd[923]: Loaded 0 symmetric keys
Jun 24 05:47:24 pve-proxmox-R7 chronyd[923]: Using leap second list /usr/share/zoneinfo/leap-seconds.list
Jun 24 05:47:24 pve-proxmox-R7 chronyd[923]: Frequency -63.315 +/- 26.140 ppm read from /var/lib/chrony/chrony.drift
Jun 24 05:47:24 pve-proxmox-R7 chronyd[923]: Loaded seccomp filter (level 1)
Jun 24 05:47:24 pve-proxmox-R7 systemd[1]: Started chrony.service - chrony, an NTP client/server.
Jun 24 05:47:33 pve-proxmox-R7 chronyd[923]: Selected source 10.10.10.254 (pfsense.intranet.XXXXX.XXX)
Jun 24 05:47:33 pve-proxmox-R7 chronyd[923]: System clock TAI offset set to 37 seconds
Jun 24 06:26:26 pve-proxmox-R7 chronyd[923]: Can't synchronise: no selectable sources
Jun 24 06:32:52 pve-proxmox-R7 chronyd[923]: Selected source 10.10.10.254 (pfsense.intranet.XXXXXX.XXX)


root@pve-proxmox-R7:~# chronyc sources -v

  .-- Source mode  '^' = server, '=' = peer, '#' = local clock.
 / .- Source state '*' = current best, '+' = combined, '-' = not combined,
| /             'x' = may be in error, '~' = too variable, '?' = unusable.
||                                                 .- xxxx [ yyyy ] +/- zzzz
||      Reachability register (octal) -.           |  xxxx = adjusted offset,
||      Log2(Polling interval) --.      |          |  yyyy = measured offset,
||                                \     |          |  zzzz = estimated error.
||                                 |    |           \
MS Name/IP address         Stratum Poll Reach LastRx Last sample               
===============================================================================
^* pfsense.intranet.XXXX.XX>    12   6     7    43   -978ns[+2460ns] +/-  124us

root@pve-proxmox-R7:~# timedatectl
               Local time: Wed 2026-06-24 06:35:48 CEST
           Universal time: Wed 2026-06-24 04:35:48 UTC
                 RTC time: Wed 2026-06-24 04:35:48
                Time zone: Europe/Paris (CEST, +0200)
System clock synchronized: yes
              NTP service: active
          RTC in local TZ: no
```

Les 3 points importants  :

- ^* = server current best

- System clock synchronized: yes

- NTP service: active

---

## 3. Commandes de vérification

### 3.1 Depuis pfSense (ligne de commande)

Vérifier la synchronisation du serveur NTP

```bash
ntpq -p
```

Tester la résolution DNS

```bash
host time.google.com
```

Tester la connexion vers un serveur NTP externe

```bash
ntpdate -q time.google.com
```

Tester le serveur NTP local (doit répondre)

```bash
ntpdate -q 127.0.0.1
```



### 3.2 Depuis un nœud Proxmox

Voir les sources NTP et leur état

```
chronyc sources -v
```

Afficher les statistiques détaillées

```
chronyc tracking
```

Vérifier la synchronisation système

```
timedatectl
```

Voir les logs de chrony

```
journalctl -u chrony -n 50
```

### 3.3 Interprétation des résultats

Dans `chronyc sources -v`, le symbole devant la source indique :

| Symbole | Signification                                   |
| ------- | ----------------------------------------------- |
| `^*`    | Source actuellement sélectionnée (synchronisée) |
| `^+`    | Source combinée (bonne, mais pas la meilleure)  |
| `^-`    | Source non combinée (trop éloignée)             |
| `^?`    | Source inutilisable (problème de connexion)     |

La colonne `Reach` doit tendre vers `377` (valeur octale signifiant 100% de paquets reçus).

---

## 4. Résumé des problèmes et solutions

| Problème                | Symptôme                             | Solution                                      |
| ----------------------- | ------------------------------------ | --------------------------------------------- |
| IPv6 non routé          | `^?` sur la source, `Reach` = 0      | Ajouter `-4` dans `/etc/default/chrony`       |
| Pare-feu bloquant       | `^?` sur la source                   | Ajouter règle UDP 123 dans pfSense            |
| KOD activé              | Source marquée `^?` avec message KOD | Désactiver KOD dans NTP > Access Restrictions |
| pfSense non synchronisé | `ntpdate -q 127.0.0.1` échoue        | Vérifier les serveurs NTP dans Services > NTP |

---

## 5. Vérification finale avant création du cluster

Sur **chaque** nœud Proxmox, exécutez :



```bash
chronyc sources -v
```

Vous devez voir une **étoile (`^*`)** devant votre source NTP et la colonne `Reach` avec une valeur > 0 (idéalement 377).



```bash
timedatectl
```

Le champ `System clock synchronized` doit indiquer `yes`.

---

## 6. Notes additionnelles

### Pourquoi ces problèmes ?

1. **IPv6** : chrony résout les noms DNS en priorité en IPv6. Si votre réseau ne gère pas l'IPv6, les requêtes échouent.

2. **KOD** : Mécanisme de protection contre les attaques DDoS, trop sensible sur un réseau local.

3. **Interfaces NTP sur pfSense** : Par défaut, pfSense n'écoute pas sur toutes les interfaces si une sélection est faite. L'option `All` résout ce problème.

### Bonnes pratiques

- Utilisez **au moins 3 serveurs NTP** pour une redondance optimale

- Si possible, synchronisez pfSense via **GPS ou serveur local** pour une Stratum plus bas

- Pour un cluster Proxmox à 2 nœuds, pensez à ajouter un **QDevice** pour le quorum

---

## 7. Références

- [Documentation officielle chrony](https://chrony.tuxfamily.org/)

- [Documentation pfSense NTP](https://docs.netgate.com/pfsense/en/latest/services/ntp.html)
  
- [Mise en oeuvre de pfSense NTP](https://doc.netwaze.fr/books/pfsense/page/cree-un-serveur-ntp-avec-pfsense)

- [Proxmox Cluster Requirements](https://pve.proxmox.com/wiki/Cluster_Manager)

---

**Auteur** : Yannick Sudrie  
**Date** : 24 juin 2026  
**Version** : 1.0


