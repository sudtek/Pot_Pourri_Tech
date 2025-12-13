# Installation d'OCRmyPDF sous Windows 11 : Guide pas à pas anti-frustration pour ex-Linuxiens (PowerShell edition)

Ce tuto intègre les derniers pièges : **TESSDATA_PREFIX obligatoire pour Tesseract** (sinon crash langue), renommage `jbig2.exe` pour compat, et warning sur Tagged PDF. Basé sur nos galères + docs 2025 (Stack Overflow, GitHub). Full DL direct via aria2, zéro choco. Si WSL up, saute dedans pour du pur Linux.

**Durée :** 20-35 min. **PowerShell only** (Tab + historique). Admin pour EXE. **Pourquoi aria2 > winget pour DL ?** Multi-threads rapide ; winget pour installs système only.

Note 13 décembre 2025 : J'ai stocké dans github les biblis pour la compression des images couleurs et Noir & Blanc, l'executable ghostscript.exe et le fichier fra (Francais) pour que tesseract puisse oceriser les docs Français. Vous devez toujours utiliser les dernieres version de ces softs mais au cas ou ... j'ai gardé une archive. Le tuto a fonctionné et doit être perfectible ; j'utilise pas windows au quotidien il doit pouvoir être perfectionné mais bon vous avez le canavas global pas à pas pour pouvoir installer Tesseract sous windows 11 x64 ... 

Testé sur un mni pc  : 

Nom de l'appareil	MLLSE
Processeur	Intel(R) N100 (800 MHz)
Mémoire RAM installée	16,0 Go (15,8 Go utilisable)
Type du système	Système d’exploitation 64 bits, processeur x64
Édition	Windows 11 Professionnel
Version	24H2
Installé le	16/sept/2025
Build du système d’exploitation	26100.7171
Fonctionnalité	Pack d’expérience de fonctionnalités Windows 1000.26100.265.0



## 1. Prérequis et Téléchargements (aria2 boost)

### Étape 1.1 : Installe aria2
- `winget install aria2.aria2` (admin PS).
- Ou DL : `aria2c -x 16 -s 16 https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip`
- Extrais dans `C:\Users\$env:USERNAME\Desktop\aria2-1.37.0-win-64bit-build1` ; ajoute au PATH (section 3).

### Étape 1.2 : Outils à télécharger (aria2 everywhere)
- Python 3.14 embed : `aria2c -x 8 https://www.python.org/ftp/python/3.14.2/python-3.14.2-embed-amd64.zip`
- Tesseract : `winget install UB-Mannheim.TesseractOCR`
- Ghostscript : `aria2c https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10011/gs10011w64.exe`
- Français : `aria2c https://github.com/tesseract-ocr/tessdata/raw/main/fra.traineddata`
- **Pour compression :**
  - pngquant : `aria2c https://pngquant.org/pngquant-windows.zip` (v3.0.3, 64-bit).
  - jbig2enc : `aria2c https://altushost-swe.dl.sourceforge.net/project/jbig2enc/win/jbig2enc-0.29-win32.zip` (v0.29, 32-bit mais OK sur 64-bit).

## 2. Installation des Dépendances (PowerShell only)

### Étape 2.1 : Installe Python (fix embed + pip)
Extrais ZIP dans `C:\Users\$env:USERNAME\AppData\Local\Python\pythoncore-3.14-64\`.  
DL get-pip : `aria2c https://bootstrap.pypa.io/get-pip.py` (dans le dossier).  
`.\python.exe get-pip.py`.  
Édite `python314._pth` (notepad) : Ajoute `import site` à la fin.  
Vérif : `python --version` ; `pip --version`.

### Étape 2.2 : Installe Tesseract
`winget install UB-Mannheim.TesseractOCR` ; `tesseract --version`.

### Étape 2.3 : Installe Ghostscript
Double-clic sur l'EXE DL ; `gs -v`.

### Étape 2.4 : Optionnels pour Images & Compression PDF (DL direct !)
Extrait les ZIP et ajoute au PATH.

#### 2.4.1 : Installe pngquant (pour PNG couleur, -50-70% taille)
1. Extrais `pngquant-windows.zip` dans `C:\Program Files\pngquant\` (crée le dossier).
2. Binaire : `pngquant.exe` (64-bit, v3.0.3).
3. Vérif : `cd "C:\Program Files\pngquant\" ; .\pngquant.exe --version`.
4. Ajoute au PATH : `C:\Program Files\pngquant\` (section 3).

#### 2.4.2 : Installe jbig2enc (pour N&B, x10 compression)
1. Extrais `jbig2enc-0.29-win32.zip` dans `C:\Program Files\jbig2enc\` (crée le dossier).
2. Binaire : `jbig2.exe` (32-bit v0.29 ; renomme si c'est `jbig2enc.exe` pour compat OCRmyPDF).
3. Vérif : `cd "C:\Program Files\jbig2enc\" ; .\jbig2.exe -h` (help s'affiche).
4. Ajoute au PATH : `C:\Program Files\jbig2enc\` (section 3).

**Option compile 64-bit :** DL source `aria2c https://github.com/agl/jbig2enc/archive/refs/heads/master.zip` ; VS Build Tools (`winget install Microsoft.VisualStudio.2022.BuildTools`) ; `nmake /f Makefile.vc` (Developer PS).

## 3. Configuration des Variables d'Environnement (PATH + TESSDATA_PREFIX anti-crash !)
**Nouveau : Ajoute TESSDATA_PREFIX pour Tesseract** (sinon crash langue même si fichier copié).

- GUI : `Win + S` > "Variables d'environnement" > "Modifier" > **Path** (utilisateur) :
  - Python/Script : `C:\Users\$env:USERNAME\AppData\Local\Python\pythoncore-3.14-64\` et `\Scripts\`
  - Tesseract : `C:\Program Files\Tesseract-OCR\`
  - Ghostscript : `C:\Program Files\Ghostscript\gs10.01.1\bin`
  - Aria2 : `C:\Users\$env:USERNAME\Desktop\aria2-1.37.0-win-64bit-build1`
  - pngquant : `C:\Program Files\pngquant\`
  - jbig2enc : `C:\Program Files\jbig2enc\`

- **TESSDATA_PREFIX (système)** : Clique "Nouveau" sous "Variables système" :
  - Nom : `TESSDATA_PREFIX`
  - Valeur : `C:\Program Files\Tesseract-OCR\tessdata`
- Ou PS : `[Environment]::SetEnvironmentVariable("TESSDATA_PREFIX", "C:\Program Files\Tesseract-OCR\tessdata", "Machine")` (admin).

Valide > **Redémarre PowerShell/PC** ; vérif : `echo $env:PATH` (ajouts) + `echo $env:TESSDATA_PREFIX` (chemin tessdata) + `tesseract --list-langs` ("fra" listé).

## 4. Installation d'OCRmyPDF via pip
`pip install ocrmypdf` ; `ocrmypdf --version`.  
Vérif optionnels : `ocrmypdf --help` (cherche "pngquant" / "jbig2").

## 5. Ajout de la Langue Française
`aria2c https://github.com/tesseract-ocr/tessdata/raw/main/fra.traineddata` ; `Copy-Item fra.traineddata 'C:\Program Files\Tesseract-OCR\tessdata\'`.  
Vérif post-TESSDATA_PREFIX : `tesseract --list-langs` → "fra".

## 6. Test et Utilisation
**Warning Tagged PDF** : Si ton PDF est déjà "tagged" (texte existant), évite --redo-ocr pour préserver le tagging ; utilise juste pour ajouter calque.

`New-Item -ItemType Directory -Path C:\test-ocr; Set-Location C:\test-ocr` ; place `input.pdf`.  
Test basique : `ocrmypdf --language fra --optimize 1 input.pdf output.pdf` (sans redo pour start).  
Avancé : `ocrmypdf --language fra --redo-ocr --optimize 3 --verbose 2 input.pdf output.pdf` (max compression si jbig2 OK).  
Vérif : Taille réduite + Ctrl+F (texte français copiable).

## 7. Dépannage Barbu

| Problème | Cause | Fix |
|----------|-------|-----|
| TESSDATA_PREFIX manquant | Crash langue fra | Ajoute var (section 3) ; redémarre PS ; vérif `tesseract --list-langs`. |
| jbig2 non trouvé | PATH miss ou nom faux | Ajoute dossier ; renomme en `jbig2.exe` ; test `--help`. Skip avec --optimize 1. |
| Tagged PDF warning | PDF déjà OCRisé | Retire --redo-ocr ; ou ignore si tu veux refaire. |
| OCR bloqué 0% | Tesseract fail | Vérif TESSDATA_PREFIX + fichier fra ; `--jobs 1` pour debug. |
| DL lent | Pas multi | `-x 16` sur aria2 ; manuel navigateur. |


## Ressources

- [OCRmyPDF Documentation Officielle](https://ocrmypdf.readthedocs.io/en/latest/)
- [Tesseract sous Windows](https://github.com/UB-Mannheim/tesseract/wiki)
- [Stack Overflow pour TESSDATA_PREFIX](https://stackoverflow.com/questions/tagged/tesseract+windows)

*Mis à jour : Décembre 2025. TESSDATA_PREFIX + jbig2 fix.* 