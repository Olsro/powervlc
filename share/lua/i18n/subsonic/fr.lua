--[[ fr.lua: the fr catalogue of the subsonic extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {

    title_connect = "Subsonic — Connexion",
    title_browse = "Subsonic — Bibliothèque",

    sec_server = "<b>Serveur</b>",
    lbl_server = "Adresse :",
    hint_server = "Adresse de votre serveur, chemin de base compris s'il "
               .. "y en a un — ex. https://navidrome.exemple.com",
    sec_account = "<b>Compte</b>",
    lbl_username = "Utilisateur :",
    lbl_password = "Mot de passe :",
    chk_remember = "Se souvenir de cette connexion",
    btn_forget = "Oublier les informations de connexion",
    btn_connect = "Se connecter",
    msg_forgotten = "Informations de connexion effacées",
    msg_keystore_denied = "Le trousseau du système a refusé de rendre le "
                       .. "mot de passe enregistré — saisissez-le à nouveau",
    msg_secret_plain = "Le trousseau du système n'a pas gardé le mot de "
                    .. "passe : il est enregistré en clair dans %s",
    msg_enter_server = "Saisissez d'abord l'adresse du serveur",
    msg_enter_account = "Saisissez un utilisateur et un mot de passe",
    msg_pinging = "Contact du serveur...",
    msg_ping_fail = "Serveur injoignable : ",
    msg_found_base = "Serveur trouvé sur %s",
    msg_bad_credentials = "Utilisateur ou mot de passe incorrect",
    msg_login_fail = "Échec de la connexion : ",

    view_albums = "Par albums",
    view_artists = "Par artistes d'album",
    view_random = "Albums au hasard",
    view_shuffle = "Titres au hasard",
    view_decades = "Par décennie",
    view_radios = "Radios Internet",
    col_station = "Station",
    col_stream = "Flux",
    msg_loading_radios = "Chargement des radios...",
    view_newest = "Récemment ajoutés",
    view_recent = "Récemment joués",
    view_frequent = "Plus joués",
    view_genres = "Par genres",
    view_playlists = "Par listes de lecture",
    view_songs = "Par titres (recherche)",
    chk_starred = "Favoris seulement",
    lbl_search = "Recherche :",
    btn_back = "< Retour",
    btn_connection = "< Connexion",
    btn_refresh = "Actualiser",
    btn_open = "Ouvrir",
    btn_play = "Lire",
    btn_enqueue = "Ajouter à la file",
    btn_download = "Télécharger",

    col_album = "Album",
    col_artist = "Artiste",
    col_year = "Année",
    col_songs = "Titres",
    col_added = "Ajouté le",
    col_played = "Écouté le",
    col_plays = "Lectures",
    col_decade = "Décennie",
    decade_fmt = "Années %d",
    menu_open_songs = "Ouvrir les titres",
    lbl_start_at = "Démarrer à :",
    hint_start_at = "mm:ss — s'applique à la lecture d'un seul titre, "
                 .. "en flux transcodé",
    col_star = "★",
    col_albums = "Albums",
    col_genre = "Genre",
    col_playlist = "Liste",
    col_duration = "Durée",
    col_track = "N°",
    col_title = "Titre",

    menu_play = "Lire",
    menu_enqueue = "Ajouter à la file",
    menu_download = "Télécharger dans le dossier Téléchargements",
    menu_star = "Ajouter aux favoris",
    menu_unstar = "Retirer des favoris",
    menu_open = "Ouvrir",

    msg_loading_albums = "Chargement des albums... (%d)",
    msg_loading_artists = "Chargement des artistes...",
    msg_loading_genres = "Chargement des genres...",
    msg_loading_playlists = "Chargement des listes de lecture...",
    msg_loading_songs = "Récupération des titres... (%d/%d)",
    msg_loading_album = "Ouverture de l'album...",
    msg_loading_art = "Récupération de la pochette...",
    msg_searching = "Recherche...",
    msg_search_hint = "Tapez au moins 2 caractères pour chercher dans "
                   .. "toute la bibliothèque par titre",
    msg_pick_view = "Choisissez une vue, ou appuyez sur Actualiser, pour la "
                 .. "charger — rien n'est récupéré avant votre demande",
    msg_count = "%d / %d — double-cliquez pour ouvrir, clic droit pour "
             .. "les actions",
    msg_count_songs = "%d / %d titres — double-clic pour lire, clic droit "
                   .. "pour les actions ; glissez vers un dossier pour "
                   .. "télécharger",
    msg_select_first = "Sélectionnez d'abord un élément dans la liste",
    msg_no_content = "Rien trouvé",
    msg_api_fail = "Le serveur a répondu par une erreur : ",
    msg_playing = "Lecture lancée (%d titres)",
    msg_queued = "%d titres ajoutés à la file",
    msg_starred = "Ajouté aux favoris",
    msg_unstarred = "Retiré des favoris",
    msg_star_fail = "Le serveur a refusé : ",
    msg_no_genre_download = "Ouvrez le genre et choisissez des albums à "
                         .. "télécharger",

    sec_transcode = "Transcodage serveur (lecture en continu)",
    lbl_format = "Format :",
    fmt_raw = "Original (aucun transcodage)",
    lbl_maxrate = "Bitrate max :",
    hint_transcode = "S'applique aux prochains titres envoyés à la "
                  .. "lecture. Les téléchargements récupèrent toujours "
                  .. "les fichiers d'origine.",

    dl_progress = "%s %d %% — %s — fichier %d/%d — %s / %s",
    dl_done = "Téléchargement terminé : %d fichiers dans %s",
    dl_done_errors = "Téléchargement terminé : %d fichiers, %d en ÉCHEC, "
                  .. "dans %s",
    dl_cancelled = "Téléchargement annulé",
    dl_busy = "Un téléchargement est déjà en cours — attendez ou annulez-le",
    btn_dl_cancel = "Annuler le téléchargement",
    dl_preparing = "Préparation du téléchargement...",
}
