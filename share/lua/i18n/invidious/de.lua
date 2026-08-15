--[[ de.lua: the de catalogue of the invidious extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {

    title_connect = "Invidious — Verbindung",
    title_search = "Invidious — Suche",
    title_video = "Invidious — Video",
    date_fmt = "%Y-%m-%d",
    col_instance = "Instanz",
    col_region = "Region",
    col_uptime = "Verfügbarkeit",
    col_title = "Titel",
    col_channel = "Kanal",
    col_date = "Veröffentlicht",
    col_subs = "Abonnenten",
    col_videos = "Videos",
    btn_list_instances = "Öffentliche Instanzen auflisten",
    btn_use_selection = "Ausgewählte Instanz verwenden",
    lbl_instance = "Instanz:",
    chk_proxy = "Streams über die Instanz leiten (empfohlen)",
    btn_connect = "Verbinden",
    msg_fetching_instances = "Öffentliche Instanzen werden abgerufen …",
    msg_no_instances = "Keine brauchbare Instanz gefunden",
    msg_instances_count = "%d Instanzen — wählen Sie eine aus und dann "
                    .. "„Ausgewählte Instanz verwenden“",
    msg_select_first = "Wählen Sie zuerst eine Instanz in der Liste aus",
    msg_enter_url = "Geben Sie zuerst die Adresse einer Instanz ein",
    msg_connecting = "Verbindung wird hergestellt …",
    msg_connect_fail = "Verbindung fehlgeschlagen: ",
    msg_search_blocked = "Instanz erreichbar, blockiert aber die anonyme API-Suche "
                   .. "(Bot-Schutz) — versuchen Sie eine andere oder eine "
                   .. "eigene Instanz",
    mode_videos = "Videos",
    mode_channels = "Kanäle",
    mode_playlists = "Wiedergabelisten",
    btn_search = "Suchen",
    btn_open = "Auswahl öffnen",
    btn_change_instance = "< Instanz",
    msg_enter_query = "Geben Sie einen Suchbegriff ein",
    msg_searching = "Suche läuft …",
    msg_no_results = "Kein Ergebnis",
    msg_results_count = "%d Ergebnisse (neueste zuerst)",
    msg_channel_loading = "Videos des Kanals werden abgerufen …",
    msg_playlist_loading = "Wiedergabeliste wird abgerufen …",
    msg_target_found = "Adresse erkannt — sie wird direkt geöffnet",
    msg_search_fail = "Suche fehlgeschlagen: ",
    msg_select_result = "Wählen Sie zuerst ein Ergebnis in der Liste aus",
    lbl_quality = "Qualität:",
    lbl_by = "von",
    audio_only = "Nur Ton",
    combined = "Ton+Video",
    video_only = "Nur Video",
    live_hls = "HLS-Stream (live)",
    btn_play = "Wiedergabe",
    btn_copy = "Stream-Adresse kopieren",
    btn_back = "< Zurück",
    msg_loading_video = "Videoinformationen werden abgerufen …",
    msg_video_fail = "Videoinformationen konnten nicht abgerufen werden: ",
    msg_fallback_formats = "Video-API von der Instanz blockiert — stattdessen "
                     .. "wurden Standard-Streams geprüft",
    msg_trying_html = "JSON-API geschlossen — die HTML-Seiten werden versucht …",
    msg_html_mode = "Im HTML-Modus verbunden (API auf dieser Instanz geschlossen)",
    dash_auto = "Automatische Qualität (DASH)",
    msg_no_formats = "Für dieses Video wurde kein abspielbarer Stream gefunden",
    msg_playing = "Wiedergabe gestartet",
    msg_copied = "Stream-Adresse in die Zwischenablage kopiert",
    msg_copy_fallback = "Automatisches Kopieren nicht verfügbar — markieren Sie "
                  .. "die Adresse unten",

    btn_download = "Herunterladen",
    btn_download_audio = "Nur den Ton herunterladen",
    msg_dl_busy = "Ein Download läuft bereits — warten Sie ihn ab oder brechen Sie ihn ab",
    msg_no_audio_stream = "Dieses Video bietet keinen getrennten Tonstream",
    btn_dl_cancel = "Download abbrechen",
    msg_loading_thumb = "Vorschaubild wird abgerufen …",
    dl_preparing = "Download wird vorbereitet …",
    dl_progress = "%s %d %% — Datei %d/%d — %s / %s",
    dl_done = "Download abgeschlossen: %s — in %s",
    dl_done_pair = "Download abgeschlossen: %s (Bild) und %s (Ton) — in %s. Diese Qualität gibt es nicht als kombinierten Stream: die beiden Dateien gehören zusammen.",
    dl_error = "Download fehlgeschlagen: ",
    dl_cancelled = "Download abgebrochen",
    msg_dl_playlist = "Dieser Eintrag ist eine Streamliste, keine Datei: Wählen Sie zum Herunterladen eine Qualität mit Auflösung",
    msg_dl_unsupported = "Diese Version kann nicht herunterladen: ihr fehlt der Erweiterungs-Timer",
    msg_dl_no_dir = "Der Ordner „Downloads“ wurde nicht gefunden",
    btn_combine = "Die beiden Dateien zusammenfügen",
    msg_combine_gone = "Die beiden Dateien liegen nicht mehr dort, wo sie heruntergeladen wurden",
    msg_combine_running = "Wird zusammengefügt… %d %%",
    msg_combine_ok = "Zusammenfügen abgeschlossen: %s",
    msg_combine_failed = "Das Zusammenfügen ist fehlgeschlagen — es wurde nichts geschrieben",
    msg_combine_unsupported = "Diese Version kann die beiden Dateien nicht zusammenfügen",
    title_challenge = "Invidious — Bot-Prüfung",
    lbl_challenge_1 = "Diese Instanz schützt sich mit einer Prüfung, die "
                .. "JavaScript ausführen muss. PowerVLC löst sie nicht: Ihr "
                .. "Browser tut es und gibt das Ergebnis zurück.",
    lbl_challenge_2 = "1. Öffnen Sie diese Adresse in Ihrem Browser (PowerFox, "
                .. "Firefox, Safari …) und folgen Sie den drei Schritten auf "
                .. "der Seite:",
    lbl_region = "Ergebnisse für:",
    btn_challenge_copy = "Adresse kopieren",
    btn_challenge_open = "Im Browser öffnen",
    lbl_challenge_3 = "2. PowerVLC macht von selbst weiter, sobald der Browser "
                .. "fertig ist. Diese Schaltfläche gibt es nur, falls Sie nicht "
                .. "warten möchten:",
    btn_challenge_done = "Ich habe die Prüfung bestanden",
    btn_challenge_cancel = "< Zurück",
    msg_challenge_copied = "Adresse kopiert — fügen Sie sie in Ihrem Browser ein",
    msg_challenge_opened = "In Ihrem Browser geöffnet — machen Sie dort weiter",
    msg_challenge_no_browser = "PowerVLC konnte keinen Browser öffnen: Kopieren "
                         .. "Sie stattdessen die Adresse.",
    msg_challenge_waiting = "Noch nichts erhalten — führen Sie die Schritte im "
                      .. "Browser zu Ende und drücken Sie erneut",
    msg_challenge_ok = "Sitzung erhalten — neuer Versuch",
    msg_challenge_fail = "Die lokale Übergabeseite konnte nicht geöffnet werden: ",
    msg_challenge_needed = "Diese Instanz verlangt eine Bot-Prüfung",
    msg_challenge_incomplete = "Die Prüfung ist nicht abgeschlossen: Die Seite "
                         .. "muss wirklich zu sehen sein, bevor Sie das "
                         .. "Lesezeichen anklicken. Beenden Sie sie und klicken "
                         .. "Sie erneut.",
    msg_challenge_click = "Ihr Browser-Tab öffnet dieses Video. Sobald es zu sehen "
                    .. "ist, klicken Sie das Lesezeichen an — mehr ist nicht zu "
                    .. "tun.",
    msg_challenge_no_session = "Diese Instanz gewährt ihrem Browser jeweils nur "
                         .. "eine Seite und behält nichts Wiederverwendbares, "
                         .. "es gibt also nichts, was PowerVLC übergeben werden "
                         .. "könnte. Versuchen Sie eine andere Instanz.",
    web_title = "PowerVLC — Bot-Prüfung",
    web_intro = "Die Prüfung dieser Instanz löst Ihr Browser, genau so, als würden "
          .. "Sie die Seite selbst besuchen. PowerVLC liest die Seite "
          .. "anschließend durch diesen Tab; es löst nie selbst etwas.",
    web_step1 = "Ziehen Sie diesen Link auf Ihre Lesezeichenleiste (ein für alle "
          .. "Mal):",
    web_bookmark = "An PowerVLC senden",
    web_step2 = "Öffnen Sie die Instanz und bestehen Sie die angezeigte Prüfung:",
    web_step3 = "Sobald die Seite <strong>wirklich zu sehen</strong> ist — manche "
          .. "Instanzen verlangen zwei Prüfungen nacheinander — klicken Sie das "
          .. "gerade angelegte Lesezeichen <em>An PowerVLC senden</em> an.",
    web_note = "Lassen Sie dieses Fenster und den Tab der Instanz beim Surfen "
         .. "geöffnet: PowerVLC liest jede Seite durch sie. Wird eines von "
         .. "beiden geschlossen, ist die Verbindung unterbrochen und das "
         .. "Lesezeichen muss erneut angeklickt werden.",
    web_done_title = "Fertig",
    web_done = "PowerVLC hat, was es braucht. Lassen Sie dieses Fenster und den "
         .. "Tab der Instanz geöffnet und kehren Sie zum Player zurück.",
    web_empty = "Es kam nichts Brauchbares an. Vergewissern Sie sich, dass die "
          .. "Seite wirklich zu sehen ist — manche Instanzen verlangen zwei "
          .. "Prüfungen nacheinander — und klicken Sie das Lesezeichen erneut "
          .. "an.",
    web_relay_on = "Mit PowerVLC verbunden. Lassen Sie dieses Fenster und den Tab "
             .. "der Instanz beim Surfen geöffnet.",
    web_relay_off = "Warten auf den Tab der Instanz …",
    web_relay_busy = "Der Tab der Instanz arbeitet noch an seiner Prüfung — "
               .. "PowerVLC wartet, statt etwas von ihm zu verlangen.",
    web_m_drag = "Das ist ein Lesezeichen, kein Link: Ziehen Sie es auf Ihre "
           .. "Lesezeichenleiste, öffnen Sie dann die Instanz und klicken Sie "
           .. "es DORT an, nachdem die Prüfung bestanden ist.",
    web_m_ok = "PowerVLC ist verbunden. Lassen Sie diesen Tab beim Surfen "
         .. "geöffnet.",
    web_m_popup = "PowerVLC konnte sein Fenster nicht öffnen: Erlauben Sie Pop-ups "
            .. "für diese Seite und klicken Sie das Lesezeichen erneut an.",
    web_m_wait = "PowerVLC: Verbindung …",
    web_m_fail = "PowerVLC antwortet nicht. Prüfen Sie, ob seine Seite (127.0.0.1) "
           .. "noch geöffnet ist, und klicken Sie das Lesezeichen erneut an.",
    web_m_page = "Diese Seite wurde an PowerVLC übergeben.",
    web_m_nav = "Das von PowerVLC angeforderte Video wird geöffnet — klicken Sie "
          .. "das Lesezeichen erneut an, sobald es zu sehen ist.",
    web_m_taken = "PowerVLC hat diese Seite. Der Tab wurde absichtlich geleert: "
            .. "das Video auch hier abzuspielen würde die Maschine ein zweites "
            .. "Dekodieren und einen zweiten Download kosten. Lassen Sie ihn "
            .. "geöffnet.",
    web_addon_title = "Ältere Browser: die PowerVLC-Erweiterung installieren",
    web_addon = "TenFourFox, PowerFox und jeder Browser vor Firefox 69 führen das "
          .. "Skript eines Lesezeichens auf einer Seite mit "
          .. "Sicherheitsrichtlinie nicht aus, und jede Instanz hat eine: dort "
          .. "bewirkt ein Klick auf das Lesezeichen gar nichts. Im Player setzt "
          .. "<strong>Hilfe &gt; PowerVLC-Erweiterung installieren</strong> "
          .. "eine kleine Erweiterung in Ihren Browser, die dasselbe von allein "
          .. "erledigt — kein Lesezeichen, kein Klicken, auf jeder Seite.",
}
