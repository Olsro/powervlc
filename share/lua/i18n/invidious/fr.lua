--[[ fr.lua: the fr catalogue of the invidious extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {

    title_connect = "Invidious — Connexion",
    title_search = "Invidious — Recherche",
    title_video = "Invidious — Vidéo",
    -- ISO à dessein : le tri des colonnes est lexicographique
    date_fmt = "%Y-%m-%d",
    col_instance = "Instance",
    col_region = "Région",
    col_uptime = "Dispo.",
    col_title = "Titre",
    col_channel = "Chaîne",
    col_date = "Publiée",
    col_subs = "Abonnés",
    col_videos = "Vidéos",

    btn_list_instances = "Lister les instances publiques",
    btn_use_selection = "Utiliser l'instance sélectionnée",
    lbl_instance = "Instance :",
    chk_proxy = "Relayer les flux par l'instance si la lecture directe échoue (recommandé)",
    btn_connect = "Connexion",
    msg_fetching_instances = "Récupération des instances publiques...",
    msg_no_instances = "Aucune instance utilisable trouvée",
    msg_instances_count = "%d instances — sélectionnez-en une puis « Utiliser l'instance sélectionnée »",
    msg_select_first = "Sélectionnez d'abord une instance dans la liste",
    msg_enter_url = "Saisissez d'abord l'URL d'une instance",
    msg_connecting = "Connexion...",
    msg_connect_fail = "Échec de la connexion : ",
    msg_search_blocked = "L'instance répond mais bloque la recherche "
                      .. "anonyme (anti-bot) — essayez-en une autre ou "
                      .. "une instance personnelle",

    mode_videos = "Vidéos",
    mode_channels = "Chaînes",
    mode_playlists = "Playlists",
    btn_search = "Chercher",
    btn_open = "Ouvrir la sélection",
    btn_change_instance = "< Instance",
    msg_enter_query = "Saisissez un terme à chercher",
    msg_searching = "Recherche...",
    msg_no_results = "Aucun résultat",
    msg_results_count = "%d résultats (plus récents d'abord)",
    msg_channel_loading = "Récupération des vidéos de la chaîne...",
    msg_playlist_loading = "Récupération de la playlist...",
    msg_target_found = "Adresse reconnue — ouverture directe",
    msg_search_fail = "Échec de la recherche : ",
    msg_select_result = "Sélectionnez d'abord un résultat dans la liste",

    lbl_quality = "Qualité :",
    lbl_by = "par",
    audio_only = "Audio seul",
    combined = "audio+vidéo",
    video_only = "vidéo seule",
    live_hls = "Flux HLS (direct)",
    btn_play = "Lire",
    btn_copy = "Copier le lien du flux",
    btn_back = "< Retour",
    msg_loading_video = "Récupération des informations de la vidéo...",
    msg_video_fail = "Impossible de récupérer la vidéo : ",
    msg_fallback_formats = "API vidéos bloquée par l'instance — flux standards sondés à la place",
    msg_trying_html = "API JSON fermée — essai par les pages HTML...",
    msg_html_mode = "Connecté en mode HTML (API fermée sur cette instance)",
    dash_auto = "Qualité automatique (DASH)",
    msg_no_formats = "Aucun flux lisible trouvé pour cette vidéo",
    msg_playing = "Lecture lancée",
    msg_copied = "Lien du flux copié dans le presse-papiers",
    msg_copy_fallback = "Copie auto indisponible — sélectionnez le lien ci-dessous",

    btn_download = "Télécharger",
    btn_download_audio = "Télécharger le son seul",
    msg_dl_busy = "Un téléchargement est déjà en cours — attendez-le, ou annulez-le",
    msg_no_audio_stream = "Cette vidéo ne propose aucun flux audio séparé",
    btn_dl_cancel = "Annuler le téléchargement",
    msg_loading_thumb = "Récupération de la miniature...",
    dl_preparing = "Préparation du téléchargement...",
    dl_progress = "%s %d %% — fichier %d/%d — %s / %s",
    dl_done = "Téléchargement terminé : %s — dans %s",
    dl_done_pair = "Téléchargement terminé : %s (image) et %s (son) — dans %s. Cette qualité n'existe pas en flux combiné : les deux fichiers vont ensemble.",
    dl_error = "Échec du téléchargement : ",
    dl_cancelled = "Téléchargement annulé",
    msg_dl_playlist = "Cette entrée est une liste de flux, pas un fichier : choisissez une qualité avec une résolution pour la télécharger",
    msg_dl_unsupported = "Cette version ne sait pas télécharger : elle n'a pas de minuteur d'extension",
    msg_dl_no_dir = "Dossier Téléchargements introuvable",
    btn_combine = "Combiner les deux fichiers avec ffmpeg",
    combine_banner = "PowerVLC : combinaison de l'image et du son, sans réencodage.",
    combine_no_ffmpeg = "ffmpeg n'est pas installé, ou pas dans le PATH. Installez-le, puis relancez ce fichier.",
    combine_done = "Terminé :",
    msg_combine_launched = "ffmpeg lancé dans une fenêtre de terminal — c'est elle qui dira si ça a marché",
    msg_combine_copied = "Aucun terminal n'a pu être ouvert — la commande ffmpeg est dans le presse-papiers",
    msg_combine_fallback = "Aucun terminal n'a pu être ouvert — la commande ffmpeg est dans le champ ci-dessous",
    msg_combine_gone = "Les deux fichiers ne sont plus là où ils ont été téléchargés",

    title_challenge = "Invidious — Vérification anti-bot",
    lbl_challenge_1 = "Cette instance se protège par une vérification qui "
                   .. "exige JavaScript. PowerVLC ne la contourne pas : "
                   .. "c'est votre navigateur qui la résout et qui rend le "
                   .. "résultat.",
    lbl_challenge_2 = "1. Ouvrez cette adresse dans votre navigateur "
                   .. "(PowerFox, Firefox, Safari...), puis suivez les "
                   .. "trois étapes de la page :",
    lbl_region = "Résultats pour :",
    btn_challenge_copy = "Copier l'adresse",
    btn_challenge_open = "Ouvrir dans le navigateur",
    lbl_challenge_3 = "2. PowerVLC repart tout seul dès que le navigateur a "
                   .. "terminé. Ce bouton n'est là que si vous préférez ne "
                   .. "pas attendre :",
    btn_challenge_done = "J'ai passé la vérification",
    btn_challenge_cancel = "< Retour",
    msg_challenge_copied = "Adresse copiée — collez-la dans votre navigateur",
    msg_challenge_opened = "Ouverte dans votre navigateur — la suite s'y "
                        .. "passe",
    msg_challenge_no_browser = "PowerVLC n'a pas pu ouvrir de navigateur : "
                            .. "copiez l'adresse à la place.",
    msg_challenge_waiting = "Rien reçu pour l'instant — terminez les étapes "
                         .. "dans le navigateur puis réappuyez",
    msg_challenge_ok = "Session reçue — nouvel essai",
    msg_challenge_fail = "Impossible d'ouvrir la page locale de reprise : ",
    msg_challenge_needed = "Cette instance demande une vérification anti-bot",
    msg_challenge_incomplete = "La vérification n'est pas terminée : la page "
                            .. "doit vraiment s'afficher avant que vous "
                            .. "cliquiez le favori. Terminez-la, puis "
                            .. "recliquez.",
    msg_challenge_click = "Votre onglet ouvre cette vidéo. Dès qu'elle "
                       .. "s'affiche, cliquez le favori — rien d'autre à "
                       .. "faire.",
    msg_challenge_no_session = "Cette instance n'autorise son navigateur "
                            .. "qu'une page à la fois et ne conserve rien de "
                            .. "réutilisable : il n'y a rien à transmettre à "
                            .. "PowerVLC. Essayez une autre instance.",

    -- pages servies au navigateur
    web_title = "PowerVLC — vérification anti-bot",
    web_intro = "La vérification de cette instance est résolue par votre "
             .. "navigateur, exactement comme si vous consultiez le site "
             .. "vous-même. PowerVLC lit ensuite la page à travers cet "
             .. "onglet ; il ne résout jamais rien de lui-même.",
    web_step1 = "Glissez ce lien dans votre barre de favoris (une fois "
             .. "pour toutes) :",
    web_bookmark = "Envoyer à PowerVLC",
    web_step2 = "Ouvrez l'instance et résolvez la vérification qu'elle "
             .. "affiche :",
    web_step3 = "Une fois que la page s'affiche <strong>vraiment</strong> "
             .. "— certaines instances demandent deux contrôles à la suite "
             .. "— cliquez le favori <em>Envoyer à PowerVLC</em> que vous "
             .. "venez d'ajouter.",
    web_note = "Laissez cette fenêtre et l'onglet de l'instance ouverts "
            .. "pendant votre navigation : PowerVLC lit chaque page à "
            .. "travers eux. Fermer l'un des deux coupe le lien, et il "
            .. "faut recliquer le favori.",
    web_done_title = "C'est fait",
    web_done = "PowerVLC a ce qu'il lui faut. Laissez cette fenêtre et "
            .. "l'onglet de l'instance ouverts, et revenez au lecteur.",
    web_empty = "Rien d'exploitable n'est arrivé. Vérifiez que la page "
             .. "s'affiche vraiment — certaines instances demandent deux "
             .. "contrôles à la suite — puis recliquez le favori.",
    web_relay_on = "Relié à PowerVLC. Laissez cette fenêtre et l'onglet de "
                .. "l'instance ouverts pendant votre navigation.",
    web_relay_off = "En attente de l'onglet de l'instance...",
    web_relay_busy = "L'onglet de l'instance est encore dans sa "
                  .. "vérification — PowerVLC attend au lieu de lui "
                  .. "demander quoi que ce soit.",
    web_m_drag = "Ceci est un favori, pas un lien : glissez-le dans votre "
              .. "barre de favoris, puis ouvrez l'instance et cliquez-le "
              .. "LÀ-BAS, une fois la vérification passée.",
    web_m_ok = "PowerVLC est relié. Laissez cet onglet ouvert pendant votre "
            .. "navigation.",
    web_m_popup = "PowerVLC n'a pas pu ouvrir sa fenêtre : autorisez les "
               .. "fenêtres surgissantes pour ce site, puis recliquez le "
               .. "favori.",
    web_m_wait = "PowerVLC : connexion...",
    web_m_fail = "PowerVLC ne répond pas. Vérifiez que sa page (127.0.0.1) "
              .. "est toujours ouverte, puis recliquez le favori.",
    web_m_page = "Cette page a été transmise à PowerVLC.",
    web_m_nav = "Ouverture de la vidéo demandée par PowerVLC — recliquez le "
             .. "favori une fois qu'elle s'affiche.",
    web_m_taken = "PowerVLC a cette page. L'onglet a été vidé à dessein : "
               .. "lire la vidéo ici aussi coûterait à la machine un second "
               .. "décodage et un second téléchargement. Laissez-le ouvert.",
    web_addon_title = "Navigateurs anciens : installez l'extension PowerVLC",
    web_addon = "TenFourFox, PowerFox et tous les navigateurs antérieurs à "
             .. "Firefox 69 refusent d'exécuter le script d'un favori sur "
             .. "une page munie d'une politique de sécurité, et toutes les "
             .. "instances en ont une : le favori n'y fait alors rien du "
             .. "tout. Dans le lecteur, <strong>Aide &gt; Installer "
             .. "l'extension PowerVLC</strong> pose dans votre navigateur "
             .. "une petite extension qui s'en charge toute seule — plus "
             .. "de favori, plus de clic, sur toutes les pages.",
    web_addon_lead = "Extension installée ? Il n'y a rien à glisser et "
                  .. "rien à cliquer : ouvrez simplement l'instance "
                  .. "ci-dessous et passez sa vérification. Cette page "
                  .. "vous dira elle-même quand le lien est établi.",
    web_steps_title = "Sans l'extension : le favori",
    web_relay_on_addon = "Relié à PowerVLC par l'extension du navigateur. "
                      .. "Rien à cliquer : laissez cette fenêtre et "
                      .. "l'onglet de l'instance ouverts.",
    web_m_taking = "PowerVLC lit cette vidéo. L'onglet a été vidé tout de "
                .. "suite à dessein : laisser le lecteur du site se charger "
                .. "ici coûterait un second décodage et un second "
                .. "téléchargement, et solliciterait l'instance pour rien. "
                .. "Laissez-le ouvert.",
}
