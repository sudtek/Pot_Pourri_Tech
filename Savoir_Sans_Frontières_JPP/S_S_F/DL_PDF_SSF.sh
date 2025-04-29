#!/bin/bash

# 28_04_2025
# version  0.2
# yannick SUDRIE
#
# But : Script interactif pour Télécharger toutes les BD au format PDF de jean-pierre Petit pdf de Savoir Sans Frontières pour une langue donnée exemple fre
# http://www.savoir-sans-frontieres.com 
#
# invocation :
# ./DL_PDF_SSF.sh


URL_SSF="http://www.savoir-sans-frontieres.com"
DOWNLOAD_PATH="download"
FICHIER_HTM_LANGUES="langues.htm"
FICHIER_LISTE_LANGUES="liste_langues.txt"
LANGUE_DEFAUT="fre"
LANGUE_SELECT=""
FICHIER_HTM_LIVRES="livres.htm"
FICHIER_LISTE_LIVRES="liste_noms_livres.txt"
FICHIER_URL_PDF="liste_urls_PDF.txt"



# Téléchargement de la liste des langues
echo "Téléchargement de la liste des langues..."
wget -q "$URL_SSF/$DOWNLOAD_PATH/" -O "$FICHIER_HTM_LANGUES" || {
    echo "Échec du téléchargement de la liste des langues"
    exit 1
}

# Extraction des codes de langue (3 lettres)
echo "Extraction des langues disponibles..."
grep "folder.gif" "$FICHIER_HTM_LANGUES" | grep -oP 'href="\K[a-z]{3}(?=/")' | sort -u > "$FICHIER_LISTE_LANGUES"

# Affichage des langues disponibles
echo -e "\nLangues disponibles :"
column "$FICHIER_LISTE_LANGUES"

# Sélection de la langue
while true; do
    echo -ne "\nChoisir une langue [$LANGUE_DEFAUT] : "
    read -r CHOIX

    [ -z "$CHOIX" ] && CHOIX="$LANGUE_DEFAUT"

    if grep -qx "$CHOIX" "$FICHIER_LISTE_LANGUES"; then
        LANGUE_SELECT="$CHOIX"
        break
    else
        echo "ERREUR : '$CHOIX' non valide. Langues disponibles :"
        column "$FICHIER_LISTE_LANGUES"
    fi
done

echo -e "\nLangue sélectionnée : $LANGUE_SELECT"

# Téléchargement de la liste des livres
echo "Téléchargement de la liste des livres..."
wget -q "$URL_SSF/$DOWNLOAD_PATH/$LANGUE_SELECT/" -O "$FICHIER_HTM_LIVRES" || {
    echo "Échec du téléchargement de la liste des livres"
    exit 2
}

# Extraction des noms de fichiers .htm(l)
echo "Extraction des livres disponibles..."
grep -oP 'href="\K[^"/]+\.html?(?=")' "$FICHIER_HTM_LIVRES" | sort -u > "$FICHIER_LISTE_LIVRES"

echo -e "\nLivres disponibles pour $LANGUE_SELECT :"
column "$FICHIER_LISTE_LIVRES"

# On fait un wget de chacun des fichiers html pour en extraire l'url de telechargement du pdf correspondant 


FICHIER_URL_PDF="liste_urls_PDF.txt"

# Initialisation du fichier PDF
> "$FICHIER_URL_PDF"

echo -e "\nTéléchargement des pages HTML des livres et extraction des URLs PDF..."
while IFS= read -r livre_html; do
    # Télécharger la page HTML du livre
    wget -q "$URL_SSF/$DOWNLOAD_PATH/$LANGUE_SELECT/$livre_html" -O "temp_$livre_html"

    # Extraire l'URL PDF avec regex améliorée
    pdf_url=$(grep -i 'meta http-equiv="refresh"' "temp_$livre_html" | \
	      grep -oP 'url=\K[^"]+')

    if [ -n "$pdf_url" ]; then
        echo "$pdf_url" >> "$FICHIER_URL_PDF"
        echo "[SUCCÈS] $livre_html → PDF trouvé"
    else
        echo "[ERREUR] Aucun PDF détecté dans $livre_html"
    fi

    # Nettoyer le fichier temporaire
    rm -f "temp_$livre_html"
done < "$FICHIER_LISTE_LIVRES"

# Affichage final
echo -e "\nURLs PDF extraites :"
column "$FICHIER_URL_PDF"

# Verif presence d'url de pdf ?
if [ ! -s "$FICHIER_URL_PDF" ]; then
    echo "Aucune URL PDF trouvée ! Vérifiez le contenu des fichiers HTML."
    exit 3
fi

# Telechargement des pdfs dasn le repertoire de leur langues respectives
echo -e "\nTéléchargement des PDFs dans le répertoire '$LANGUE_SELECT'..."
mkdir -p "$LANGUE_SELECT"  # Création du répertoire si inexistant
wget -c --limit-rate=200k \
     --no-clobber \
     --continue \
     -i "$FICHIER_URL_PDF" \
     -P "$LANGUE_SELECT" \
     --show-progress \
     --wait=1 \
     --random-wait

# Nettoyage optionnel
echo -e "\nNettoyage optionnel :"
read -p "Supprimer les fichiers temporaires (htm/listes) ? [y/N] " yn
case $yn in
    [Yy]* ) 
        rm -f "$FICHIER_HTM_LANGUES" "$FICHIER_HTM_LIVRES" "temp_"* 
        echo "Fichiers temporaires supprimés";;
    * ) 
        echo "Conservation des fichiers :"
        echo "- $FICHIER_LISTE_LANGUES"
        echo "- $FICHIER_LISTE_LIVRES"
        echo "- $FICHIER_URL_PDF";;
esac
