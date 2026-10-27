Artwork de NSRT AutoReminders.

Format : TGA. Le RLE est accepte (tous les fichiers livres le sont) ; 24 bits
suffit, 32 bits uniquement si de la transparence est necessaire.

  Boss/<EncounterID>.tga          128x128   24 bits   vignette du boss
  Boss/Wide/<EncounterID>.tga     1024x256  24 bits   bandeau du panneau
  Raid/<nom-normalise>.tga        128x128   24 bits   ex: the-voidspire.tga
  Backgrounds/default.tga         512x288   24 bits   fond si rien n'est choisi
  Icons/{raid,boss,timeline}.tga  128x128   32 bits
  icon.tga                        64x64     32 bits   icone de l'addon

Sources/ a ete SUPPRIME : le selecteur de source montre desormais la
pastille de couleur (UI/swatch.tga, teintee a l'execution) et non plus le
logo de la source, dans la liste deroulante comme sur le bouton ferme. A
14 px un logo n'etait de toute facon pas lisible, et la couleur est deja le
repere employe partout ailleurs pour designer la source.

Habillage de l'interface, dans UI/ : toutes les pieces sont en 32 bits non
compresse, car elles sont assemblees et doivent se raccorder au pixel pres.

  btn_{left,mid,right}.tga        bouton secondaire, 3 tranches, 16/8/16 x 32
  btnprimary_{...}.tga            bouton principal (aplat bleu #2870bd)
  btndanger_{...}.tga             bouton destructeur
  fill_<coin>.tga       32x32     quarts de disque pleins des surfaces arrondies
  ring_<coin>.tga        5x5      arcs du lisere de selection
  cut_<coin>.tga        32x32     l'INVERSE de fill_ : decoupe au lieu de remplir
  search / warning / chevron / answers.tga   32x32   pictogrammes au trait
  thumb.tga             26x12     pastille du curseur d'echelle (blanche, teintee)
  swatch.tga            14x14     pastille de couleur de la source (blanche, teintee)
  sizer.tga             64x64     poignee de redimensionnement

  <icone>.tga           ~16x16    pictogrammes : bell, check, clock, globe...

TOUT ce qui est arrondi dans l'interface sort des quatre fill_<coin> : la
fenetre (rayon 14), une carte (10), un menu deroulant ou la piste (6), un
bouton ou un badge (4), une ligne de menu selectionnee (5). Ils font 32 px
pour cela : un quart de disque se reduit proprement a n'importe quel rayon,
alors qu'une piece de 5 px agrandie baverait.

Une bordure n'a pas d'images a elle : RoundedBox superpose deux aplats, le
second pose 1 px en retrait, et la bordure naît de leur difference. Elle vaut
donc pour n'importe quel rayon et n'importe quelle couleur.

A SAVOIR AVANT DE REGENERER UNE TEXTURE A CANAL ALPHA : les pixels
INVISIBLES doivent quand meme porter la couleur de leurs voisins visibles.
Le jeu filtre une texture en melangeant chaque pixel a ses voisins AVANT de
regarder l'alpha ; si le transparent est noir, ce noir est tire dans les bords
et dessine un lisere sale — un petit triangle sombre dans chaque coin arrondi.
Les outils de dessin laissent du noir ou du gris par defaut, donc la
propagation (alpha bleed) doit etre faite apres coup, sans toucher a l'alpha.
Controle rapide : la moyenne RVB des pixels d'alpha < 40 doit valoir la
couleur du motif, jamais du noir.

fill_* et ring_* sont traces sur le meme cercle, un aplat et son contour se
superposent donc exactement. Les deux sont blancs et recoivent leur couleur a
l'execution (SetVertexColor), d'ou un seul jeu d'images pour toutes les
teintes. Voir RoundedFill, RoundedBox et SelectionRing dans Core/UI.lua.

A NE PAS REFAIRE : poser une image de coin PAR-DESSUS un SetBackdrop. Ce
dernier ne dessine que des rectangles a angles droits ; le coin repose alors
la meme couleur au meme endroit et ne decoupe rien. C'est ce que faisaient
win_*, menu_* et badge_*, retires de l'addon.

Rien n'a besoin d'etre declare dans le .toc : les textures sont chargees par
leur chemin, construit depuis l'EncounterID (voir ApplyBossTexture et
ApplyBossWideTexture dans Core/UI.lua).

Replis, dans l'ordre :
  Boss/Wide/<id>.tga -> Boss/<id>.tga -> Boss/<nom-normalise>.tga -> placeholder
Un boss sans image s'affiche donc en gris desature, jamais en erreur.

Normalisation d'un nom (raid ou boss) : minuscules, apostrophes supprimees,
"&" remplace par "and", toute autre suite de caracteres par un tiret unique.
  "March on Quel'Danas" -> march-on-queldanas
  "Kith'ix"             -> kithix

Boss/Wide/ a ete SUPPRIME : le bandeau large a ete remplace par un fond
uni dans l'en-tete de boss, et c'est la vignette Boss/<id>.tga qui montre
desormais le boss. Ces images pesaient 14 Mo, soit l'essentiel du poids
de l'archive.


Polices, dans Fonts/ : Noto Sans en deux graisses et un Noto Sans Mono reduit
aux chiffres (SIL OFL 1.1, texte complet dans Fonts/OFL.txt).

La police du jeu n'a qu'un poids : FRIZQT__.TTF n'existe pas en gras. Toute
hierarchie devait donc reposer sur la seule taille — c'est ce que fait
ExwindTools. On embarque Noto Sans pour retrouver le demi-gras, et le mono
pour que la colonne des temps s'aligne vraiment.

Les trois fichiers sont des sous-ensembles : latin, latin etendu, grec et
cyrillique pour les deux graisses ; chiffres et deux-points pour le mono.
136 Ko en tout. Les locales koKR / zhCN / zhTW gardent la police du jeu, qui
couvre leurs glyphes ; la hierarchie y tient sur la taille seule.

Pour changer de police : remplacer les .ttf en gardant les noms, ou editer la
table `file` dans le bloc Polices de Core/UI.lua. Le code teste le fichier au
chargement et retombe sur celle du jeu s'il est illisible.
