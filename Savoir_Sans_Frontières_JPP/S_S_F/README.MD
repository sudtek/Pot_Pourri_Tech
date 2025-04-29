# DL_PDF_SSF : Téléchargeur automatisé de PDFs éducatifs

[🇫🇷] Script bash pour télécharger automatiquement toutes les bandes dessinées scientifiques de *Savoir Sans Frontières* dans une langue spécifique.  
[🇬🇧] Bash script to automatically download all educational PDFs from *Savoir Sans Frontières* for a chosen language.

---

## 📝 Description
Ce script permet de :
1. Lister toutes les langues disponibles
2. Sélectionner une langue (français par défaut)
3. Récupérer automatiquement tous les PDFs disponibles pour cette langue
4. Organiser les fichiers dans des répertoires par langue

## ✨ Fonctionnalités
- Interface interactive pour choisir la langue
- Détection automatique des URLs PDF
- Téléchargement parallèle avec limitation de débit (200ko/s)
- Nettoyage optionnel des fichiers temporaires
- Gestion robuste des erreurs

## 📋 Prérequis
- `wget` (pour les téléchargements)
- `grep` avec support Perl (`-P`)
- Bash 4.0+

## 🛠 Installation
```bash
git clone https://github.com/votre-utilisateur/DL_PDF_SSF.git
cd DL_PDF_SSF
chmod +x DL_PDF_SSF.sh
```
# Lancer le script
```bash
./DL_PDF_SSF.sh
```

## 🚀 Utilisation
Options implicites :
- Téléchargement avec reprise (-c)
- Limitation de bande passante (--limit-rate=200k)
- Journalisation des erreurs automatique

## 📂 Structure des fichiers
```
├── fre/               # Répertoire des PDFs (langue)
├── langues.htm        # Liste brute des langues
├── liste_langues.txt  # Langues disponibles
└── liste_urls_PDF.txt # URLs des PDFs détectés
```

## 🧹 Nettoyage
Le script propose de supprimer automatiquement :
- Fichiers HTML temporaires
- Listes intermédiaires
- Fichiers de log

## 💡 Notes
Langue par defaut : Francais -> fre
Langues disponibles : arabe (ara), ukrainien (ukr), vietnamien (vie), etc.

Les PDFs sont hébergés sur (http://savoir-sans-frontieres.com/JPP/telechargeables/)[http://savoir-sans-frontieres.com/JPP/telechargeables/]
