J'ai réguliérement besoin de recuperer diverses données (principalement des PDF), faire des mirroirs des sites webs, ect ... de Jean-Pierre PETIT alias JPP.

- [http://www.savoir-sans-frontieres.com/](http://www.savoir-sans-frontieres.com/)

- [https://www.jp-petit.org/](https://www.jp-petit.org/)

Vous trouverez ici des scripts en relation avec ces sites. 

[DL_PDF_SSF.sh](https://github.com/sudtek/Pot_Pourri_Tech/blob/0755d18ea3cd01184fbd6c81ca49249ecf85681d/Savoir_Sans_Fronti%C3%A8res_JPP/S_S_F/DL_PDF_SSF.sh) télécharger automatiquement l'ensemble des bandes dessinées éducatives de *Savoir Sans Frontières* par langue - Outil open source pour la préservation du savoir multilingue.

Note : Pour télécharger uniquement la page des documents téléchargables du site SSF :

```bash
wget --mirror --convert-links --adjust-extension --page-requisites http://www.savoir-sans-frontieres.com/JPP/telechargeables/Francais/
```

