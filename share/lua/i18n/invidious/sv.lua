--[[ sv.lua: the sv catalogue of the invidious extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {
  title_connect = "Invidious — Anslutning",
  title_search = "Invidious — Sökning",
  title_video = "Invidious — Video",
  date_fmt = "%Y-%m-%d",
  col_instance = "Instans",
  col_region = "Region",
  col_uptime = "Tillgänglighet",
  col_title = "Titel",
  col_channel = "Kanal",
  col_date = "Publicerad",
  col_subs = "Prenumeranter",
  col_videos = "Videor",
  btn_list_instances = "Lista publika instanser",
  btn_use_selection = "Använd vald instans",
  lbl_instance = "Instans:",
  chk_proxy = "Skicka strömmarna via instansen (rekommenderas)",
  btn_connect = "Anslut",
  msg_fetching_instances = "Hämtar publika instanser…",
  msg_no_instances = "Ingen användbar instans hittades",
  msg_instances_count = "%d instanser — välj en och sedan ”Använd vald "
                      .. "instans”",
  msg_select_first = "Välj först en instans i listan",
  msg_enter_url = "Ange först adressen till en instans",
  msg_connecting = "Ansluter…",
  msg_connect_fail = "Anslutningen misslyckades: ",
  msg_search_blocked = "Instansen svarar men blockerar anonym sökning via API "
                     .. "(robotskydd) — prova en annan eller en egen instans",
  mode_videos = "Videor",
  mode_channels = "Kanaler",
  mode_playlists = "Spellistor",
  btn_search = "Sök",
  btn_open = "Öppna markerat",
  btn_change_instance = "< Instans",
  msg_enter_query = "Skriv något att söka efter",
  msg_searching = "Söker…",
  msg_no_results = "Inget resultat",
  msg_results_count = "%d resultat (nyaste först)",
  msg_channel_loading = "Hämtar kanalens videor…",
  msg_playlist_loading = "Hämtar spellistan…",
  msg_target_found = "Adressen känns igen — den öppnas direkt",
  msg_search_fail = "Sökningen misslyckades: ",
  msg_select_result = "Välj först ett resultat i listan",
  lbl_quality = "Kvalitet:",
  lbl_by = "av",
  audio_only = "Endast ljud",
  combined = "ljud+video",
  video_only = "endast video",
  live_hls = "HLS-ström (direkt)",
  btn_play = "Spela upp",
  btn_copy = "Kopiera strömmens adress",
  btn_back = "< Tillbaka",
  msg_loading_video = "Hämtar videoinformation…",
  msg_video_fail = "Kunde inte hämta videoinformationen: ",
  msg_fallback_formats = "Video-API:t blockeras av instansen — "
                       .. "standardströmmarna avsöktes i stället",
  msg_trying_html = "JSON-API:t är stängt — HTML-sidorna provas…",
  msg_html_mode = "Ansluten i HTML-läge (API:t är stängt på den här instansen)",
  dash_auto = "Automatisk kvalitet (DASH)",
  msg_no_formats = "Ingen spelbar ström hittades för den här videon",
  msg_playing = "Uppspelningen har startat",
  msg_copied = "Strömmens adress kopierad till urklipp",
  msg_copy_fallback = "Automatisk kopiering är inte tillgänglig — markera "
                    .. "adressen nedan",

  btn_download = "Hämta",
  btn_download_audio = "Hämta bara ljudet",
  msg_dl_busy = "En hämtning pågår redan — vänta på den eller avbryt den",
  msg_no_audio_stream = "Den här videon erbjuder ingen separat ljudström",
  btn_dl_cancel = "Avbryt hämtningen",
  msg_loading_thumb = "Hämtar miniatyrbilden…",
  dl_preparing = "Förbereder hämtningen…",
  dl_progress = "%s %d %% — fil %d/%d — %s / %s",
  dl_done = "Hämtningen klar: %s — i %s",
  dl_done_pair = "Hämtningen klar: %s (bild) och %s (ljud) — i %s. Den här kvaliteten finns inte som en kombinerad ström: de två filerna hör ihop.",
  dl_error = "Hämtningen misslyckades: ",
  dl_cancelled = "Hämtningen avbröts",
  msg_dl_playlist = "Den här posten är en strömlista, inte en fil: välj en kvalitet med upplösning för att hämta den",
  msg_dl_unsupported = "Den här versionen kan inte hämta: den saknar tilläggstimern",
  msg_dl_no_dir = "Mappen Hämtade filer hittades inte",
  btn_combine = "Slå ihop de två filerna",
  msg_combine_gone = "De två filerna finns inte längre där de hämtades",
  msg_combine_running = "Slår ihop… %d %%",
  msg_combine_ok = "Sammanslagningen klar: %s",
  msg_combine_failed = "Sammanslagningen misslyckades — ingenting skrevs",
  msg_combine_unsupported = "Det här bygget kan inte slå ihop de två filerna",
  title_challenge = "Invidious — Robotkontroll",
  lbl_challenge_1 = "Den här instansen skyddar sig med en kontroll som måste "
                  .. "köra JavaScript. PowerVLC löser den inte: det gör din "
                  .. "webbläsare, som lämnar tillbaka resultatet.",
  lbl_challenge_2 = "1. Öppna den här adressen i din webbläsare (PowerFox, "
                  .. "Firefox, Safari…) och följ de tre stegen på sidan:",
  lbl_region = "Resultat för:",
  btn_challenge_copy = "Kopiera adressen",
  btn_challenge_open = "Öppna i webbläsaren",
  lbl_challenge_3 = "2. PowerVLC fortsätter av sig självt så snart webbläsaren "
                  .. "är klar. Knappen finns bara om du hellre slipper vänta:",
  btn_challenge_done = "Jag har klarat kontrollen",
  btn_challenge_cancel = "< Tillbaka",
  msg_challenge_copied = "Adressen kopierad — klistra in den i webbläsaren",
  msg_challenge_opened = "Öppnad i webbläsaren — fortsätt där",
  msg_challenge_no_browser = "PowerVLC kunde inte öppna någon webbläsare: "
                           .. "kopiera adressen i stället.",
  msg_challenge_waiting = "Inget har kommit ännu — slutför stegen i "
                        .. "webbläsaren och tryck igen",
  msg_challenge_ok = "Session mottagen — nytt försök",
  msg_challenge_fail = "Kunde inte öppna den lokala överlämningssidan: ",
  msg_challenge_needed = "Den här instansen kräver en robotkontroll",
  msg_challenge_incomplete = "Kontrollen är inte klar: sidan måste verkligen "
                           .. "visas innan du klickar på bokmärket. Slutför den "
                           .. "och klicka igen.",
  msg_challenge_click = "Din flik öppnar den här videon. Så snart den visas "
                      .. "klickar du på bokmärket — inget mer behövs.",
  msg_challenge_no_session = "Den här instansen ger sin webbläsare tillgång "
                           .. "till en sida i taget och sparar inget "
                           .. "återanvändbart, så det finns inget att lämna "
                           .. "över till PowerVLC. Prova en annan instans.",
  web_title = "PowerVLC — robotkontroll",
  web_intro = "Kontrollen på den här instansen löses av din webbläsare, precis "
            .. "som om du besökte webbplatsen själv. PowerVLC läser sedan sidan "
            .. "genom den fliken; det löser aldrig något på egen hand.",
  web_step1 = "Dra den här länken till bokmärkesfältet (en gång för alla):",
  web_bookmark = "Skicka till PowerVLC",
  web_step2 = "Öppna instansen och klara kontrollen den visar:",
  web_step3 = "När sidan <strong>verkligen visas</strong> — vissa instanser "
            .. "begär två kontroller i rad — klickar du på bokmärket <em>Skicka "
            .. "till PowerVLC</em> som du nyss lade till.",
  web_note = "Låt det här fönstret och instansens flik vara öppna medan du "
           .. "surfar: PowerVLC läser varje sida genom dem. Stänger du någon av "
           .. "dem bryts förbindelsen och bokmärket måste klickas igen.",
  web_done_title = "Klart",
  web_done = "PowerVLC har det som behövs. Låt det här fönstret och instansens "
           .. "flik vara öppna och gå tillbaka till spelaren.",
  web_empty = "Inget användbart kom fram. Kontrollera att sidan verkligen "
            .. "visas — vissa instanser begär två kontroller i rad — och klicka "
            .. "på bokmärket igen.",
  web_relay_on = "Ansluten till PowerVLC. Låt det här fönstret och instansens "
               .. "flik vara öppna medan du surfar.",
  web_relay_off = "Väntar på instansens flik…",
  web_relay_busy = "Instansens flik håller fortfarande på med sin kontroll — "
                 .. "PowerVLC väntar i stället för att begära något av den.",
  web_m_drag = "Det här är ett bokmärke, inte en länk: dra det till "
             .. "bokmärkesfältet, öppna sedan instansen och klicka på det DÄR, "
             .. "när kontrollen är klarad.",
  web_m_ok = "PowerVLC är anslutet. Låt den här fliken vara öppen medan du "
           .. "surfar.",
  web_m_popup = "PowerVLC kunde inte öppna sitt fönster: tillåt popup-fönster "
              .. "för den här webbplatsen och klicka på bokmärket igen.",
  web_m_wait = "PowerVLC: ansluter…",
  web_m_fail = "PowerVLC svarar inte. Kontrollera att dess sida (127.0.0.1) "
             .. "fortfarande är öppen och klicka på bokmärket igen.",
  web_m_page = "Den här sidan har lämnats över till PowerVLC.",
  web_m_nav = "Öppnar videon som PowerVLC bad om — klicka på bokmärket igen så "
            .. "snart den visas.",
  web_m_taken = "PowerVLC har den här sidan. Fliken tömdes med flit: att spela "
              .. "videon även här skulle kosta maskinen en andra avkodning och "
              .. "en andra nedladdning. Låt den vara öppen.",
  web_addon_title = "Äldre webbläsare: installera PowerVLC-tillägget",
  web_addon = "TenFourFox, PowerFox och alla webbläsare före Firefox 69 vägrar "
            .. "köra ett bokmärkes skript på en sida med säkerhetspolicy, och "
            .. "varje instans har en: där gör ett klick på bokmärket ingenting "
            .. "alls. I spelaren lägger <strong>Hjälp &gt; Installera "
            .. "PowerVLC-tillägget</strong> in ett litet tillägg i webbläsaren "
            .. "som sköter det själv — inget bokmärke, inga klick, på varje "
            .. "sida.",
}
