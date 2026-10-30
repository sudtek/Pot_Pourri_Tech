# Tutoriel Comportement du SWAP (swappiness) et conteneurs LXC llama.cpp sur proxmox.

Date : 30 octobre 2026

Vm : `Container LXC + debian + llama.cpp` 

OS hyperviseur : `proxmox 9.2`

Hardware : `R7 nuke 32GB , SSD 4To, IGPU AMD  Renoir <u>à mémoire partagée`

Autheur : Yannick SUDRIE

---



### Le conteneur LXC llama.cpp  va-t-il « swapper » ?

**Oui, c'est possible, mais le comportement par défaut dans Proxmox est fait pour l'éviter au maximum.**

Voici comment cela fonctionne concrètement :

- **Le piège du `swappiness`** : Par défaut, les conteneurs LXC héritent du paramètre `vm.swappiness` de l'hôte Proxmox (souvent à 60). Cela signifie qu'ils peuvent être agressifs dans l'utilisation du swap.

- **La solution** : Pour éviter que le conteneur n'utilise le swap prématurément, il est recommandé de réduire ce paramètre sur l'hôte. Une valeur de **10** ou **1** est souvent conseillée pour forcer le système à n'utiliser le swap qu'en dernier recours, lorsque la RAM est vraiment saturée.

Vous pouvez vérifier et ajuster ce paramètre sur votre hôte Proxmox :

```bash
#Vérifier la valeur actuelle
cat /proc/sys/vm/swappiness

#Pour la réduire temporairement (perdra au redémarrage)
sysctl vm.swappiness=10

#Pour la rendre permanente
echo "vm.swappiness=10" >> /etc/sysctl.d/99-swappiness.conf
```

**Conclusion** : En ajustant ce paramètre, vous vous assurez que votre conteneur LXC privilégie la RAM et ne touche au swap que si c'est absolument nécessaire. C'est une configuration saine pour votre SSD.



### ⚙️ Le `mmap` : Le comportement par défaut de `llama.cpp` en containeur LXC

Par défaut, `llama.cpp` utilise le **`mmap` (memory-mapped file)** pour charger les modèles.[](https://github.com/ggml-org/llama.cpp/discussions/19163?sort=new#1)

Voici ce que cela implique pour un IGPU AMD Renoir à RAM partagée :

- Sur un iGPU, ce mécanisme est **contre-productif**. Le `mmap` va charger le modèle en RAM, puis le copier vers la mémoire partagée du GPU, ce qui **double temporairement l'utilisation de la RAM** et ralentit le chargement.[](https://app.semanticdiff.com/gh/ggerganov/llama.cpp/pull/26081/overview#1)

- C'est pour cette raison que les développeurs de `llama.cpp` ont introduit un mode `load-mode auto` qui **désactive le `mmap` pour les iGPU** (Vulkan, CUDA, ROCm), afin d'optimiser le chargement et d'éviter la duplication en mémoire.[](https://app.semanticdiff.com/gh/ggerganov/llama.cpp/pull/26081/overview#1)

**Conclusion** : Lorsque vous lancerez `llama-server`, vous n'aurez probablement rien à faire. Le mode automatique détectera votre iGPU et désactivera le `mmap` tout seul. Si vous voulez forcer le comportement, vous pouvez utiliser l'option `--no-mmap` en ligne de commande.

### Le Ramdisk : Est-ce vraiment utile ou contre productif ?

L'idée du **ramdisk** est de placer le fichier `.gguf` du modèle dans un espace mémoire ultra-rapide (la RAM) pour accélérer son chargement.

Cependant son utilité est très limitée, voire contre-productive sur certaines machines , pour plusieurs raisons :

1. **Le chargement se fait déjà en RAM** : Que ce soit via `mmap` ou un chargement direct, le modèle finit de toute façon en RAM. Le gain d'un ramdisk serait de quelques secondes sur un chargement initial SSD, un gain négligeable.

2. **La duplication en mémoire** : Avec le mode `auto` de `llama.cpp` (qui désactive le `mmap` pour un iGPU), le modèle est chargé **une seule fois** en RAM, puis copié vers la mémoire partagée du GPU. Un ramdisk ajouterait une copie supplémentaire inutile, consommant de la RAM précieuse.[](https://app.semanticdiff.com/gh/ggerganov/llama.cpp/pull/26081/overview#1)

3. **Le coût en RAM** : Pour un conteneur qui dispose de 12 Go. Un ramdisk pour un modèle 7B (≈4,4 Go) consommerait une grande partie de cette RAM, laissant peu de place pour le système, le cache du GPU et le contexte de conversation.

4. **L'usure du SSD n'est pas un problème** : Le `mmap` est justement conçu pour éviter l'usure du SSD. Il lit les poids du modèle depuis le disque sans jamais y écrire, contrairement au swap qui, lui, écrit sur le disque.[](https://github.com/ggml-org/llama.cpp/discussions/19163?sort=new#1)

**Conclusion** : Dans cette configuration un ramdisk n'apporterait **aucun gain de performance significatif** et consommerait de la RAM précieuse. C'est une fausse bonne idée. Le `mmap` (ou son mode `auto` qui le désactive pour l'iGPU) est déjà la solution optimale pour éviter l'usure du SSD.

### 💎 En résumé

| Question                               | Réponse courte                                               | Action recommandée                            |
| -------------------------------------- | ------------------------------------------------------------ | --------------------------------------------- |
| **Le conteneur LXC va-t-il swapper ?** | Oui, c'est possible par défaut.                              | Réglez `vm.swappiness=10` sur l'hôte Proxmox. |
| **Le `mmap` est-il un problème ?**     | Oui, pour un iGPU, mais `llama.cpp` le gère automatiquement. | Laissez le mode `auto` faire son travail.     |
| **Un ramdisk est-il utile ?**          | Non, aucun gain significatif et consommation de RAM inutile. | À éviter.                                     |

Votre SSD est protégé par le fonctionnement même de `llama.cpp`. Concentrez-vous sur l'ajustement du `swappiness` de votre hôte, et tout devrait bien se passer.

Il ya deux scénarios distincts, et il faut les séparer pour bien comprendre.

### ✅ Le scénario : le modèle ne tient pas en mémoire.

Imaginons le cas où **le modèle ne tient pas en mémoire** et où les couches seraient chargées/déchargées **à la volée** pendant l'inférence. Ce scénario existe bel et bien, mais **pas dans llama.cpp**.

**llama.cpp charge tout le modèle une fois au démarrage**, puis le garde en RAM/VRAM. Il ne décharge jamais de couches en cours d'inférence. Donc pour llama.cpp :

- Soit le modèle **rentre** en RAM → tout va bien, aucune lecture disque après le chargement.

- Soit il **ne rentre pas** → llama.cpp refuse de démarrer ou utilise le swap (catastrophique en performance).

**Le vrai cas du chargement à la volée existe dans d'autres frameworks**, notamment :

| Framework                             | Fonctionnement                                                                                                                  |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| **AirLLM**                            | Charge couche par couche depuis le disque pendant l'inférence. Permet de faire tourner un 70B sur 4 Go de VRAM... à ~0,1 tok/s. |
| **llama.cpp avec offloading partiel** | Charge une partie sur GPU, le reste sur CPU. Mais tout reste en RAM, rien n'est rechargé depuis le disque.                      |
| **Certains runtimes MoE**             | Chargent les experts à la demande. Mais là encore, souvent tout est préchargé.                                                  |

C'est dans **ces cas-là** qu'un ramdisk serait utile : si le framework relit constamment les mêmes blocs depuis le disque, un ramdisk éliminerait ces lectures répétées.

### ⚠️ Mais un ramdisk ne résout pas le problème de fond

Voici le paradoxe : Sur une même machine **si le modèle ne tient pas en RAM, il ne tiendra pas non plus dans un ramdisk**. Le ramdisk consomme de la RAM système, exactement comme le cache du modèle.

Donc dans le scénario "modèle trop gros pour la RAM" :

- **Ramdisk** : impossible, pas assez de RAM pour héberger le fichier.

- **mmap** : les pages sont évincées du cache quand la RAM est saturée, puis relues depuis le SSD à chaque accès → usure SSD réelle.

**La vraie solution** dans ce cas n'est pas le ramdisk, mais :

1. **Réduire le modèle** (quantification plus agressive, modèle plus petit).

2. **Passer à un SSD NVMe** plutôt que SATA : meilleure endurance (TBW plus élevé), IOPS bien supérieurs.

3. **Accepter la lenteur** si c'est du batch nocturne (AirLLM sur un 70B, c'est 1 nuit pour 1000 tokens).

### 🎯 Quand un ramdisk est réellement utile

Un ramdisk a du sens dans des cas **très précis** :

| Scénario                                                         | Ramdisk utile ?                                     |
| ---------------------------------------------------------------- | --------------------------------------------------- |
| Modèle qui tient en RAM, chargé plusieurs fois par jour          | ⚠️ Gain marginal (le cache OS fait déjà le travail) |
| Modèle qui ne tient pas en RAM, chargé couche par couche         | ❌ Impossible (pas assez de RAM pour le ramdisk)     |
| Modèle partagé entre plusieurs processus qui le lisent en boucle | ✅ Oui, gain réel                                    |
| Base de données en lecture intensive                             | ✅ Oui, cas classique                                |
| Compilation de code (fichiers temporaires)                       | ✅ Oui, gain notable                                 |
| Modèle chargé une fois par session                               | ❌ Non, gain négligeable                             |

### 💡 Ce qui protège vraiment votre SSD

Dans votre configuration, ce qui protège votre SSD n'est **pas** un ramdisk, mais :

1. **Le `mmap` en mode `auto`** de llama.cpp : il lit le modèle depuis le disque sans jamais y écrire. La lecture pure n'use quasiment pas un SSD (l'usure vient des cycles écriture/effacement).

2. **Le `swappiness` bas** : évite les écritures de swap inutiles.

3. **Le modèle reste en RAM une fois chargé** : aucune relecture disque pendant l'inférence.

4. **L'absence de logs verbeux** : évite les écritures continues dans `/var/log`.

### 📊 En résumé

| Propostion                                                           | Verdict                                                                                                       |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| « Le ramdisk est inutile pour un container llama.cpp »               | ✅ **Exact**                                                                                                   |
| « Il serait utile sur une config qui charge les couches à la volée » | ⚠️ **Partiellement vrai** — uniquement si le framework relit les mêmes blocs, ET si la RAM le permet          |
| « Eviter de fumer le SSD »                                           | ✅ **Vrai dans le cas d'AirLLM ou frameworks similaires** — mais la vraie solution est un NVMe, pas un ramdisk |

**L'utilisation d'un ramdisk est correct** dans le cas très spécifique d'un framework comme AirLLM qui recharge constamment des couches depuis le disque, **et** si le fichier de modèle tient dans la RAM disponible. Mais dans 95 % des cas, un ramdisk est soit inutile, soit impossible, soit redondant avec le cache du système d'exploitation.

Pour un containeur avec llama.cpp, **le ramdisk est inutile**. Votre SSD est protégé par la nature même du `mmap` (lecture seule) et par un swappiness bas.
