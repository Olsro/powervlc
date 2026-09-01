--[[ nl.lua: the nl catalogue of the invidious extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {

    title_connect = "Invidious — Verbinding",
    title_search = "Invidious — Zoeken",
    title_video = "Invidious — Video",
    date_fmt = "%Y-%m-%d",
    col_instance = "Instantie",
    col_region = "Regio",
    col_uptime = "Beschikbaarheid",
    col_title = "Titel",
    col_channel = "Kanaal",
    col_date = "Gepubliceerd",
    col_subs = "Abonnees",
    col_videos = "Video's",
    btn_list_instances = "Openbare instanties tonen",
    btn_use_selection = "Geselecteerde instantie gebruiken",
    lbl_instance = "Instantie:",
    chk_proxy = "Streams via de instantie leiden (aanbevolen)",
    btn_connect = "Verbinden",
    msg_fetching_instances = "Openbare instanties ophalen…",
    msg_no_instances = "Geen bruikbare instantie gevonden",
    msg_instances_count = "%d instanties — selecteer er een en klik dan "
                    .. "«Geselecteerde instantie gebruiken»",
    msg_select_first = "Selecteer eerst een instantie in de lijst",
    msg_enter_url = "Voer eerst het adres van een instantie in",
    msg_connecting = "Verbinden…",
    msg_connect_fail = "Verbinden mislukt: ",
    msg_search_blocked = "Instantie bereikbaar, maar blokkeert anoniem zoeken via "
                   .. "de API (bots) — probeer een andere of een eigen "
                   .. "instantie",
    mode_videos = "Video's",
    mode_channels = "Kanalen",
    mode_playlists = "Afspeellijsten",
    btn_search = "Zoeken",
    btn_open = "Selectie openen",
    btn_open_channel = "Kanaal van het geselecteerde item openen",
    btn_change_instance = "< Instantie",
    msg_enter_query = "Typ iets om te zoeken",
    msg_searching = "Bezig met zoeken…",
    msg_no_results = "Geen resultaat",
    msg_results_count = "%d resultaten (nieuwste eerst)",
    msg_channel_loading = "Video's van het kanaal ophalen…",
    msg_playlist_loading = "Afspeellijst ophalen…",
    msg_target_found = "Adres herkend — het wordt meteen geopend",
    msg_search_fail = "Zoeken mislukt: ",
    msg_select_result = "Selecteer eerst een resultaat in de lijst",
    msg_channel_unavailable = "Het kanaal dat aan deze selectie is gekoppeld, is niet beschikbaar",
    lbl_quality = "Kwaliteit:",
    lbl_audio_track = "Audiotrack:",
    audio_default = "Standaardaudio",
    audio_original = "origineel",
    lbl_subtitles = "Ondertitels:",
    subtitles_none = "Geen",
    lbl_by = "van",
    audio_only = "Alleen geluid",
    combined = "geluid+video",
    video_only = "alleen video",
    live_hls = "HLS-stream (live)",
    btn_play = "Afspelen",
    btn_copy = "Streamadres kopiëren",
    btn_back = "< Terug",
    msg_loading_video = "Video-informatie ophalen…",
    msg_video_fail = "Kon de video-informatie niet ophalen: ",
    msg_fallback_formats = "Video-API geblokkeerd door de instantie — in plaats "
                     .. "daarvan zijn de standaardstreams gepolst",
    msg_trying_html = "JSON-API gesloten — de HTML-pagina's worden geprobeerd…",
    msg_html_mode = "Verbonden in HTML-modus (API gesloten op deze instantie)",
    dash_auto = "Automatische kwaliteit (DASH)",
    msg_no_formats = "Geen afspeelbare stream gevonden voor deze video",
    msg_playing = "Afspelen gestart",
    msg_copied = "Streamadres naar het klembord gekopieerd",
    msg_copy_fallback = "Automatisch kopiëren niet beschikbaar — selecteer het "
                  .. "adres hieronder",

    btn_download = "Downloaden",
    btn_download_audio = "Alleen het geluid downloaden",
    msg_dl_busy = "Er loopt al een download — wacht die af of annuleer hem",
    msg_no_audio_stream = "Deze video biedt geen aparte geluidsstream",
    btn_dl_cancel = "Download annuleren",
    msg_loading_thumb = "Miniatuur ophalen…",
    dl_preparing = "Download voorbereiden…",
    dl_progress = "%s %d %% — bestand %d/%d — %s / %s",
    dl_done = "Download voltooid: %s — in %s",
    dl_done_pair = "Download voltooid: %s (beeld) en %s (geluid) — in %s. Deze kwaliteit bestaat niet als gecombineerde stream: de twee bestanden horen bij elkaar.",
    dl_error = "Download mislukt: ",
    dl_cancelled = "Download geannuleerd",
    msg_dl_playlist = "Dit item is een streamlijst, geen bestand: kies een kwaliteit met resolutie om het te downloaden",
    msg_dl_unsupported = "Deze versie kan niet downloaden: ze heeft geen extensietimer",
    msg_dl_no_dir = "Map Downloads niet gevonden",
    btn_combine = "De twee bestanden samenvoegen",
    msg_combine_gone = "De twee bestanden staan niet meer waar ze zijn gedownload",
    msg_combine_running = "Bezig met samenvoegen… %d %%",
    msg_combine_ok = "Samenvoegen voltooid: %s",
    msg_combine_failed = "Samenvoegen mislukt — er is niets geschreven",
    msg_combine_unsupported = "Deze build kan de twee bestanden niet samenvoegen",
    title_challenge = "Invidious — Botcontrole",
    lbl_challenge_1 = "Deze instantie beschermt zich met een controle die "
                .. "JavaScript moet uitvoeren. PowerVLC lost die niet op: uw "
                .. "browser doet dat en geeft het resultaat terug.",
    lbl_challenge_2 = "1. Open dit adres in uw browser (PowerFox, Firefox, "
                .. "Safari…) en volg de drie stappen op de pagina:",
    lbl_region = "Resultaten voor:",
    btn_challenge_copy = "Adres kopiëren",
    btn_challenge_open = "In de browser openen",
    lbl_challenge_3 = "2. PowerVLC gaat vanzelf verder zodra de browser klaar is. "
                .. "Deze knop is er alleen als u liever niet wacht:",
    btn_challenge_done = "Ik heb de controle doorstaan",
    btn_challenge_cancel = "< Terug",
    msg_challenge_copied = "Adres gekopieerd — plak het in uw browser",
    msg_challenge_opened = "Geopend in uw browser — ga daar verder",
    msg_challenge_no_browser = "PowerVLC kon geen browser openen: kopieer in "
                         .. "plaats daarvan het adres.",
    msg_challenge_waiting = "Nog niets ontvangen — maak de stappen in de browser "
                      .. "af en druk opnieuw",
    msg_challenge_ok = "Sessie ontvangen — nieuwe poging",
    msg_challenge_fail = "Kon de lokale overdrachtspagina niet openen: ",
    msg_challenge_needed = "Deze instantie vraagt om een botcontrole",
    msg_challenge_incomplete = "De controle is niet afgerond: de pagina moet echt "
                         .. "te zien zijn voordat u op de bladwijzer klikt. "
                         .. "Rond haar af en klik opnieuw.",
    msg_challenge_click = "Uw tabblad opent deze video. Zodra hij te zien is, "
                    .. "klikt u op de bladwijzer — meer is er niet te doen.",
    msg_challenge_no_session = "Deze instantie geeft haar browser telkens toegang "
                         .. "tot één pagina en bewaart niets herbruikbaars, dus "
                         .. "er valt PowerVLC niets te overhandigen. Probeer "
                         .. "een andere instantie.",
    web_title = "PowerVLC — botcontrole",
    web_intro = "De controle van deze instantie wordt door uw browser opgelost, "
          .. "net alsof u de site zelf bezoekt. PowerVLC leest de pagina daarna "
          .. "via dat tabblad; het lost nooit zelf iets op.",
    web_step1 = "Sleep deze koppeling naar uw bladwijzerbalk (eens en voor "
          .. "altijd):",
    web_bookmark = "Naar PowerVLC sturen",
    web_step2 = "Open de instantie en doorsta de controle die zij toont:",
    web_step3 = "Zodra de pagina <strong>echt te zien is</strong> — sommige "
          .. "instanties vragen twee controles achter elkaar — klikt u op de "
          .. "zojuist toegevoegde bladwijzer <em>Naar PowerVLC sturen</em>.",
    web_note = "Laat dit venster en het tabblad van de instantie open terwijl u "
         .. "surft: PowerVLC leest elke pagina via die twee. Sluit u er één, "
         .. "dan is de verbinding verbroken en moet de bladwijzer opnieuw "
         .. "worden aangeklikt.",
    web_done_title = "Klaar",
    web_done = "PowerVLC heeft wat het nodig heeft. Laat dit venster en het "
         .. "tabblad van de instantie open en ga terug naar de speler.",
    web_empty = "Er kwam niets bruikbaars binnen. Controleer of de pagina echt te "
          .. "zien is — sommige instanties vragen twee controles achter elkaar "
          .. "— en klik opnieuw op de bladwijzer.",
    web_relay_on = "Verbonden met PowerVLC. Laat dit venster en het tabblad van de "
             .. "instantie open terwijl u surft.",
    web_relay_off = "Wachten op het tabblad van de instantie…",
    web_relay_busy = "Het tabblad van de instantie werkt nog aan zijn controle — "
               .. "PowerVLC wacht in plaats van er iets van te vragen.",
    web_m_drag = "Dit is een bladwijzer, geen koppeling: sleep hem naar uw "
           .. "bladwijzerbalk, open daarna de instantie en klik hem DAAR aan, "
           .. "nadat de controle is doorstaan.",
    web_m_ok = "PowerVLC is verbonden. Laat dit tabblad open terwijl u surft.",
    web_m_popup = "PowerVLC kon zijn venster niet openen: sta pop-ups toe voor "
            .. "deze site en klik opnieuw op de bladwijzer.",
    web_m_wait = "PowerVLC: verbinden…",
    web_m_fail = "PowerVLC antwoordt niet. Controleer of zijn pagina (127.0.0.1) "
           .. "nog open is en klik opnieuw op de bladwijzer.",
    web_m_page = "Deze pagina is aan PowerVLC overhandigd.",
    web_m_nav = "De door PowerVLC gevraagde video wordt geopend — klik opnieuw op "
          .. "de bladwijzer zodra hij te zien is.",
    web_m_taken = "PowerVLC heeft deze pagina. Het tabblad is met opzet "
            .. "leeggemaakt: de video ook hier afspelen zou de machine een "
            .. "tweede decodering en een tweede download kosten. Laat het open.",
    web_addon_title = "Oudere browsers: installeer de PowerVLC-extensie",
    web_addon = "TenFourFox, PowerFox en elke browser van voor Firefox 69 weigeren "
          .. "het script van een bladwijzer uit te voeren op een pagina met een "
          .. "beveiligingsbeleid, en elke instantie heeft er een: daar doet "
          .. "klikken op de bladwijzer helemaal niets. In de speler zet "
          .. "<strong>Help &gt; PowerVLC-extensie installeren</strong> een "
          .. "kleine extensie in uw browser die dit vanzelf doet — geen "
          .. "bladwijzer, geen klikken, op elke pagina.",
    web_addon_lead = "Extensie geïnstalleerd? U hoeft niets te slepen en "
                  .. "nergens op te klikken: open gewoon de instantie "
                  .. "hieronder en doorsta de controle. Deze pagina laat "
                  .. "u weten wanneer de verbinding tot stand is gebracht.",
    web_steps_title = "Zonder de extensie: de bladwijzer",
    web_relay_on_addon = "Via de browserextensie verbonden met PowerVLC. "
                      .. "U hoeft nergens op te klikken: laat dit venster "
                      .. "en het tabblad van de instantie open.",
    web_m_taking = "PowerVLC speelt deze video af. Het tabblad is meteen "
                .. "met opzet leeggemaakt: de speler van de site hier "
                .. "verder laten laden zou de machine een tweede decodering "
                .. "en een tweede download kosten en de instantie voor "
                .. "niets belasten. Laat het open.",
}
