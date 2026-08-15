--[[ it.lua: the it catalogue of the invidious extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {

    title_connect = "Invidious — Connessione",
    title_search = "Invidious — Ricerca",
    title_video = "Invidious — Video",
    date_fmt = "%Y-%m-%d",
    col_instance = "Istanza",
    col_region = "Regione",
    col_uptime = "Disponibilità",
    col_title = "Titolo",
    col_channel = "Canale",
    col_date = "Pubblicato",
    col_subs = "Iscritti",
    col_videos = "Video",
    btn_list_instances = "Elenca le istanze pubbliche",
    btn_use_selection = "Usa l'istanza selezionata",
    lbl_instance = "Istanza:",
    chk_proxy = "Instrada i flussi attraverso l'istanza (consigliato)",
    btn_connect = "Connetti",
    msg_fetching_instances = "Recupero delle istanze pubbliche…",
    msg_no_instances = "Nessuna istanza utilizzabile trovata",
    msg_instances_count = "%d istanze — selezionane una, poi «Usa l'istanza "
                    .. "selezionata»",
    msg_select_first = "Seleziona prima un'istanza nell'elenco",
    msg_enter_url = "Inserisci prima l'indirizzo di un'istanza",
    msg_connecting = "Connessione…",
    msg_connect_fail = "Connessione non riuscita: ",
    msg_search_blocked = "Istanza raggiungibile, ma blocca la ricerca anonima via "
                   .. "API (anti-bot) — provane un'altra o una istanza "
                   .. "personale",
    mode_videos = "Video",
    mode_channels = "Canali",
    mode_playlists = "Playlist",
    btn_search = "Cerca",
    btn_open = "Apri la selezione",
    btn_change_instance = "< Istanza",
    msg_enter_query = "Scrivi qualcosa da cercare",
    msg_searching = "Ricerca in corso…",
    msg_no_results = "Nessun risultato",
    msg_results_count = "%d risultati (prima i più recenti)",
    msg_channel_loading = "Recupero dei video del canale…",
    msg_playlist_loading = "Recupero della playlist…",
    msg_target_found = "Indirizzo riconosciuto — viene aperto direttamente",
    msg_search_fail = "Ricerca non riuscita: ",
    msg_select_result = "Seleziona prima un risultato nell'elenco",
    lbl_quality = "Qualità:",
    lbl_by = "di",
    audio_only = "Solo audio",
    combined = "audio+video",
    video_only = "solo video",
    live_hls = "Flusso HLS (in diretta)",
    btn_play = "Riproduci",
    btn_copy = "Copia l'indirizzo del flusso",
    btn_back = "< Indietro",
    msg_loading_video = "Recupero delle informazioni del video…",
    msg_video_fail = "Impossibile recuperare le informazioni del video: ",
    msg_fallback_formats = "API video bloccata dall'istanza — sono stati sondati i "
                     .. "flussi standard",
    msg_trying_html = "API JSON chiusa — si provano le pagine HTML…",
    msg_html_mode = "Connesso in modalità HTML (API chiusa su questa istanza)",
    dash_auto = "Qualità automatica (DASH)",
    msg_no_formats = "Nessun flusso riproducibile trovato per questo video",
    msg_playing = "Riproduzione avviata",
    msg_copied = "Indirizzo del flusso copiato negli appunti",
    msg_copy_fallback = "Copia automatica non disponibile — seleziona l'indirizzo "
                  .. "qui sotto",

    btn_download = "Scarica",
    btn_download_audio = "Scarica solo l'audio",
    msg_dl_busy = "Uno scaricamento è già in corso — attendilo, o annullalo",
    msg_no_audio_stream = "Questo video non offre alcun flusso audio separato",
    btn_dl_cancel = "Annulla lo scaricamento",
    msg_loading_thumb = "Recupero della miniatura…",
    dl_preparing = "Preparazione dello scaricamento…",
    dl_progress = "%s %d %% — file %d/%d — %s / %s",
    dl_done = "Scaricamento completato: %s — in %s",
    dl_done_pair = "Scaricamento completato: %s (immagine) e %s (audio) — in %s. Questa qualità non esiste come flusso combinato: i due file vanno insieme.",
    dl_error = "Scaricamento non riuscito: ",
    dl_cancelled = "Scaricamento annullato",
    msg_dl_playlist = "Questa voce è un elenco di flussi, non un file: scegli una qualità con risoluzione per scaricarla",
    msg_dl_unsupported = "Questa versione non sa scaricare: non ha il timer delle estensioni",
    msg_dl_no_dir = "Cartella Scaricati non trovata",
    btn_combine = "Unire i due file",
    msg_combine_gone = "I due file non sono più dove sono stati scaricati",
    msg_combine_running = "Unione in corso… %d %%",
    msg_combine_ok = "Unione completata: %s",
    msg_combine_failed = "Unione non riuscita — non è stato scritto nulla",
    msg_combine_unsupported = "Questa versione non può unire i due file",
    title_challenge = "Invidious — Verifica anti-bot",
    lbl_challenge_1 = "Questa istanza si protegge con una verifica che deve "
                .. "eseguire JavaScript. PowerVLC non la risolve: lo fa il tuo "
                .. "browser, che ne restituisce il risultato.",
    lbl_challenge_2 = "1. Apri questo indirizzo nel tuo browser (PowerFox, "
                .. "Firefox, Safari…), poi segui i tre passaggi sulla pagina:",
    lbl_region = "Risultati per:",
    btn_challenge_copy = "Copia l'indirizzo",
    btn_challenge_open = "Apri nel browser",
    lbl_challenge_3 = "2. PowerVLC riparte da solo appena il browser ha finito. "
                .. "Questo pulsante è qui solo se preferisci non aspettare:",
    btn_challenge_done = "Ho superato la verifica",
    btn_challenge_cancel = "< Indietro",
    msg_challenge_copied = "Indirizzo copiato — incollalo nel tuo browser",
    msg_challenge_opened = "Aperto nel tuo browser — prosegui lì",
    msg_challenge_no_browser = "PowerVLC non è riuscito ad aprire un browser: "
                         .. "copia invece l'indirizzo.",
    msg_challenge_waiting = "Non è ancora arrivato nulla — completa i passaggi nel "
                      .. "browser, poi premi di nuovo",
    msg_challenge_ok = "Sessione ricevuta — nuovo tentativo",
    msg_challenge_fail = "Impossibile aprire la pagina locale di consegna: ",
    msg_challenge_needed = "Questa istanza richiede una verifica anti-bot",
    msg_challenge_incomplete = "La verifica non è terminata: la pagina deve essere "
                         .. "davvero visibile prima di fare clic sul "
                         .. "segnalibro. Completala, poi riprova.",
    msg_challenge_click = "La tua scheda sta aprendo questo video. Appena si vede, "
                    .. "fai clic sul segnalibro — non serve altro.",
    msg_challenge_no_session = "Questa istanza concede al suo browser il permesso "
                         .. "per una pagina alla volta e non conserva nulla di "
                         .. "riutilizzabile, quindi non c'è nulla da consegnare "
                         .. "a PowerVLC. Prova un'altra istanza.",
    web_title = "PowerVLC — verifica anti-bot",
    web_intro = "La verifica di questa istanza la risolve il tuo browser, "
          .. "esattamente come se visitassi il sito di persona. PowerVLC legge "
          .. "poi la pagina attraverso quella scheda; non risolve mai nulla da "
          .. "sé.",
    web_step1 = "Trascina questo collegamento nella barra dei segnalibri (una "
          .. "volta per tutte):",
    web_bookmark = "Invia a PowerVLC",
    web_step2 = "Apri l'istanza e supera la verifica che mostra:",
    web_step3 = "Quando la pagina <strong>si vede davvero</strong> — alcune "
          .. "istanze chiedono due verifiche di seguito — fai clic sul "
          .. "segnalibro <em>Invia a PowerVLC</em> appena aggiunto.",
    web_note = "Lascia aperte questa finestra e la scheda dell'istanza mentre "
         .. "navighi: PowerVLC legge ogni pagina attraverso di esse. Chiuderne "
         .. "una interrompe il collegamento e il segnalibro va ricliccato.",
    web_done_title = "Fatto",
    web_done = "PowerVLC ha ciò che gli serve. Lascia aperte questa finestra e la "
         .. "scheda dell'istanza e torna al lettore.",
    web_empty = "Non è arrivato nulla di utilizzabile. Assicurati che la pagina si "
          .. "veda davvero — alcune istanze chiedono due verifiche di seguito — "
          .. "poi fai di nuovo clic sul segnalibro.",
    web_relay_on = "Collegato a PowerVLC. Lascia aperte questa finestra e la "
             .. "scheda dell'istanza mentre navighi.",
    web_relay_off = "In attesa della scheda dell'istanza…",
    web_relay_busy = "La scheda dell'istanza sta ancora svolgendo la verifica — "
               .. "PowerVLC aspetta invece di chiederle qualcosa.",
    web_m_drag = "Questo è un segnalibro, non un collegamento: trascinalo nella "
           .. "barra dei segnalibri, poi apri l'istanza e fai clic LÌ, una "
           .. "volta superata la verifica.",
    web_m_ok = "PowerVLC è collegato. Lascia aperta questa scheda mentre navighi.",
    web_m_popup = "PowerVLC non è riuscito ad aprire la sua finestra: consenti le "
            .. "finestre pop-up per questo sito, poi fai di nuovo clic sul "
            .. "segnalibro.",
    web_m_wait = "PowerVLC: connessione…",
    web_m_fail = "PowerVLC non risponde. Verifica che la sua pagina (127.0.0.1) "
           .. "sia ancora aperta, poi fai di nuovo clic sul segnalibro.",
    web_m_page = "Questa pagina è stata consegnata a PowerVLC.",
    web_m_nav = "Apertura del video richiesto da PowerVLC — fai di nuovo clic sul "
          .. "segnalibro appena si vede.",
    web_m_taken = "PowerVLC ha questa pagina. La scheda è stata svuotata di "
            .. "proposito: riprodurre il video anche qui costerebbe alla "
            .. "macchina una seconda decodifica e un secondo scaricamento. "
            .. "Lasciala aperta.",
    web_addon_title = "Browser meno recenti: installa l'estensione PowerVLC",
    web_addon = "TenFourFox, PowerFox e tutti i browser precedenti a Firefox 69 si "
          .. "rifiutano di eseguire lo script di un segnalibro su una pagina "
          .. "dotata di una politica di sicurezza, e ogni istanza ne ha una: "
          .. "lì, fare clic sul segnalibro non produce alcun effetto. Nel "
          .. "lettore, <strong>Aiuto &gt; Installa l'estensione "
          .. "PowerVLC</strong> mette nel tuo browser una piccola estensione "
          .. "che se ne occupa da sola — niente segnalibro, niente clic, su "
          .. "ogni pagina.",
}
