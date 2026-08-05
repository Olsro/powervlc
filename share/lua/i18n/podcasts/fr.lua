--[[ fr.lua: the fr catalogue of the podcasts extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {

    title_subs = "Abonnements",
    ext_description = "Cherchez dans l'annuaire de podcasts d'Apple, lisez "
                   .. "la présentation d'une émission et abonnez-vous sans "
                   .. "quitter PowerVLC.",

    lbl_term = "Rechercher :",
    btn_search = "Rechercher",
    lbl_kind = "Chercher :",
    kind_podcasts = "Des podcasts",
    kind_episodes = "Des épisodes",
    lbl_store = "Boutique :",
    lbl_limit = "Résultats :",
    lbl_genre = "Genre :",
    all_genres = "Tous les genres",
    lbl_filter = "Filtrer :",
    chk_explicit = "Masquer le contenu explicite",

    col_rank = "N°",
    col_name = "Nom",
    col_author = "Auteur",
    col_genre = "Genre",
    col_episodes = "Épisodes",
    col_latest = "Dernier",
    col_episode = "Épisode",
    col_podcast = "Podcast",
    col_date = "Date",
    col_duration = "Durée",
    col_feed = "Flux",

    btn_details = "Plus d'informations",
    btn_play = "Lire",
    btn_subscribe = "S'abonner",
    btn_unsubscribe = "Se désabonner",
    btn_subs = "Mes abonnements",
    btn_back_search = "< Recherche",
    btn_copy_feed = "Copier le flux",
    btn_play_podcast = "Lire le podcast",
    btn_play_episode = "Lire l'épisode",
    btn_enqueue_episode = "Ajouter à la liste",

    lbl_feed = "Flux :",
    lbl_episodes = "Derniers épisodes",
    lbl_by = "Par %s",
    lbl_explicit = "contenu explicite",
    lbl_count = "%d épisodes",
    lbl_count_one = "%d épisode",
    msg_count_one = "%d / %d résultat — double-cliquez pour ouvrir",
    msg_subs_count_one = "%d abonnement",
    lbl_latest = "dernier épisode le %s",
    lbl_store_of = "boutique %s",
    no_description = "Ce flux ne fournit aucune description.",

    msg_hint = "Saisissez ce que vous cherchez, puis Rechercher.",
    msg_searching = "Recherche en cours...",
    msg_count = "%d / %d résultats — double-cliquez pour ouvrir",
    msg_no_result = "Aucun résultat",
    msg_net_fail = "L'annuaire est injoignable",
    msg_bad_answer = "L'annuaire a répondu quelque chose d'illisible",
    msg_enter_term = "Saisissez d'abord ce que vous cherchez",
    msg_select_first = "Sélectionnez d'abord une entrée dans la liste",
    msg_loading = "Chargement du podcast...",
    msg_loading_feed = "Lecture du flux...",
    msg_finding_feed = "L'annuaire masque ce flux : recherche sur la fiche "
                    .. "du podcast...",
    msg_no_feed = "Cette entrée ne porte aucune adresse de flux",
    msg_feed_hidden = "Ni l'annuaire ni la fiche du podcast ne donnent ce "
                   .. "flux : impossible de s'y abonner depuis ici. Les "
                   .. "podcasts hébergés par Apple ne sont jamais "
                   .. "diffusés.",
    msg_no_episodes = "L'annuaire ne liste aucun épisode pour ce podcast",
    msg_subscribed = "Abonné — le podcast est dans Podcasts, "
                  .. "dans la barre latérale",
    msg_already = "Déjà abonné",
    msg_unsubscribed = "Désabonné",
    msg_sub_failed = "L'abonnement n'a pas pu être enregistré",
    msg_no_subs = "Aucun abonnement pour l'instant",
    msg_subs_count = "%d abonnements",
    msg_copied = "Adresse du flux copiée",
    msg_copy_failed = "La copie n'est pas disponible ici : l'adresse reste "
                   .. "sélectionnable dans le champ",
    msg_playing = "Lecture",
    msg_queued = "Ajouté à la liste de lecture",

    countries = {
      AR = "Argentine", AU = "Australie", AT = "Autriche", BE = "Belgique",
      BR = "Brésil", CA = "Canada", CL = "Chili", CN = "Chine",
      CZ = "Tchéquie", DK = "Danemark", FI = "Finlande", FR = "France",
      DE = "Allemagne", GR = "Grèce", HU = "Hongrie", IN = "Inde",
      IE = "Irlande", IL = "Israël", IT = "Italie", JP = "Japon",
      KR = "Corée du Sud", MX = "Mexique", NL = "Pays-Bas",
      NZ = "Nouvelle-Zélande", NO = "Norvège", PL = "Pologne",
      PT = "Portugal", RO = "Roumanie", RU = "Russie",
      ZA = "Afrique du Sud", ES = "Espagne", SE = "Suède",
      CH = "Suisse", TR = "Turquie", UA = "Ukraine",
      GB = "Royaume-Uni", US = "États-Unis",
    },
}
