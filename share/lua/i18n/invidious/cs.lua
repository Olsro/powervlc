--[[ cs.lua: the cs catalogue of the invidious extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {
  title_connect = "Invidious — Připojení",
  title_search = "Invidious — Hledání",
  title_video = "Invidious — Video",
  date_fmt = "%Y-%m-%d",
  col_instance = "Instance",
  col_region = "Region",
  col_uptime = "Dostupnost",
  col_title = "Název",
  col_channel = "Kanál",
  col_date = "Zveřejněno",
  col_subs = "Odběratelé",
  col_videos = "Videa",
  btn_list_instances = "Vypsat veřejné instance",
  btn_use_selection = "Použít vybranou instanci",
  lbl_instance = "Instance:",
  chk_proxy = "Vést datové proudy přes instanci (doporučeno)",
  btn_connect = "Připojit",
  msg_fetching_instances = "Získávání veřejných instancí…",
  msg_no_instances = "Nebyla nalezena použitelná instance",
  msg_instances_count = "%d instancí — vyberte jednu a pak „Použít vybranou "
                      .. "instanci“",
  msg_select_first = "Nejprve vyberte instanci v seznamu",
  msg_enter_url = "Nejprve zadejte adresu instance",
  msg_connecting = "Připojování…",
  msg_connect_fail = "Připojení selhalo: ",
  msg_search_blocked = "Instance je dostupná, ale blokuje anonymní hledání "
                     .. "přes API (ochrana proti robotům) — zkuste jinou nebo "
                     .. "vlastní",
  mode_videos = "Videa",
  mode_channels = "Kanály",
  mode_playlists = "Seznamy stop",
  btn_search = "Hledat",
  btn_open = "Otevřít výběr",
  btn_change_instance = "< Instance",
  msg_enter_query = "Napište, co hledat",
  msg_searching = "Hledání…",
  msg_no_results = "Žádný výsledek",
  msg_results_count = "%d výsledků (nejnovější první)",
  msg_channel_loading = "Získávání videí kanálu…",
  msg_playlist_loading = "Získávání seznamu stop…",
  msg_target_found = "Adresa rozpoznána — otevírá se přímo",
  msg_search_fail = "Hledání selhalo: ",
  msg_select_result = "Nejprve vyberte výsledek v seznamu",
  lbl_quality = "Kvalita:",
  lbl_by = "—",
  audio_only = "Pouze zvuk",
  combined = "zvuk+obraz",
  video_only = "pouze obraz",
  live_hls = "Proud HLS (živě)",
  btn_play = "Přehrát",
  btn_copy = "Kopírovat adresu proudu",
  btn_back = "< Zpět",
  msg_loading_video = "Získávání informací o videu…",
  msg_video_fail = "Informace o videu se nepodařilo získat: ",
  msg_fallback_formats = "Instance blokuje video API — místo toho byly ověřeny "
                       .. "standardní proudy",
  msg_trying_html = "JSON API uzavřeno — zkoušejí se stránky HTML…",
  msg_html_mode = "Připojeno v režimu HTML (API je na této instanci uzavřeno)",
  dash_auto = "Automatická kvalita (DASH)",
  msg_no_formats = "Pro toto video nebyl nalezen přehratelný proud",
  msg_playing = "Přehrávání zahájeno",
  msg_copied = "Adresa proudu zkopírována do schránky",
  msg_copy_fallback = "Automatické kopírování není k dispozici — označte "
                    .. "adresu níže",
  title_challenge = "Invidious — Kontrola proti robotům",
  lbl_challenge_1 = "Tato instance se chrání kontrolou, která potřebuje "
                  .. "JavaScript. PowerVLC ji neřeší: řeší ji váš prohlížeč a "
                  .. "výsledek předá zpět.",
  lbl_challenge_2 = "1. Otevřete tuto adresu ve svém prohlížeči (PowerFox, "
                  .. "Firefox, Safari…) a projděte tři kroky na stránce:",
  lbl_region = "Výsledky pro:",
  btn_challenge_copy = "Kopírovat adresu",
  btn_challenge_open = "Otevřít v prohlížeči",
  lbl_challenge_3 = "2. PowerVLC pokračuje sám, jakmile prohlížeč skončí. Toto "
                  .. "tlačítko je tu jen pro případ, že nechcete čekat:",
  btn_challenge_done = "Kontrolu jsem prošel",
  btn_challenge_cancel = "< Zpět",
  msg_challenge_copied = "Adresa zkopírována — vložte ji do prohlížeče",
  msg_challenge_opened = "Otevřeno v prohlížeči — pokračujte tam",
  msg_challenge_no_browser = "PowerVLC nemohl otevřít prohlížeč: zkopírujte "
                           .. "adresu ručně.",
  msg_challenge_waiting = "Zatím nic nedorazilo — dokončete kroky v prohlížeči "
                        .. "a stiskněte znovu",
  msg_challenge_ok = "Relace přijata — nový pokus",
  msg_challenge_fail = "Místní předávací stránku se nepodařilo otevřít: ",
  msg_challenge_needed = "Tato instance vyžaduje kontrolu proti robotům",
  msg_challenge_incomplete = "Kontrola není dokončena: stránka musí být "
                           .. "skutečně vidět, než kliknete na záložku. "
                           .. "Dokončete ji a klikněte znovu.",
  msg_challenge_click = "Váš panel otevírá toto video. Jakmile bude vidět, "
                      .. "klikněte na záložku — nic dalšího není třeba.",
  msg_challenge_no_session = "Tato instance dává svému prohlížeči přístup vždy "
                           .. "jen k jedné stránce a neuchovává nic "
                           .. "znovupoužitelného, takže PowerVLC není co "
                           .. "předat. Zkuste jinou instanci.",
  web_title = "PowerVLC — kontrola proti robotům",
  web_intro = "Kontrolu této instance vyřeší váš prohlížeč, přesně jako byste "
            .. "stránku navštívili sami. PowerVLC pak čte stránku přes tento "
            .. "panel; sám nikdy nic neřeší.",
  web_step1 = "Přetáhněte tento odkaz na lištu záložek (jednou provždy):",
  web_bookmark = "Odeslat do PowerVLC",
  web_step2 = "Otevřete instanci a projděte kontrolu, kterou zobrazí:",
  web_step3 = "Jakmile je stránka <strong>skutečně vidět</strong> — některé "
            .. "instance žádají dvě kontroly po sobě — klikněte na právě "
            .. "přidanou záložku <em>Odeslat do PowerVLC</em>.",
  web_note = "Nechte toto okno i panel instance otevřené, dokud prohlížíte: "
           .. "PowerVLC přes ně čte každou stránku. Zavření kteréhokoli z nich "
           .. "spojení přeruší a na záložku je třeba kliknout znovu.",
  web_done_title = "Hotovo",
  web_done = "PowerVLC má, co potřebuje. Nechte toto okno i panel instance "
           .. "otevřené a vraťte se k přehrávači.",
  web_empty = "Nedorazilo nic použitelného. Ujistěte se, že je stránka "
            .. "skutečně vidět — některé instance žádají dvě kontroly po sobě — "
            .. "a klikněte na záložku znovu.",
  web_relay_on = "Připojeno k PowerVLC. Nechte toto okno i panel instance "
               .. "otevřené, dokud prohlížíte.",
  web_relay_off = "Čeká se na panel instance…",
  web_relay_busy = "Panel instance stále řeší svou kontrolu — PowerVLC čeká, "
                 .. "místo aby po něm cokoli chtěl.",
  web_m_drag = "Toto je záložka, nikoli odkaz: přetáhněte ji na lištu záložek, "
             .. "pak otevřete instanci a klikněte na ni TAM, až bude kontrola "
             .. "hotová.",
  web_m_ok = "PowerVLC je připojen. Nechte tento panel otevřený, dokud "
           .. "prohlížíte.",
  web_m_popup = "PowerVLC nemohl otevřít své okno: povolte pro tento web "
              .. "vyskakovací okna a klikněte na záložku znovu.",
  web_m_wait = "PowerVLC: připojování…",
  web_m_fail = "PowerVLC neodpovídá. Zkontrolujte, zda je jeho stránka "
             .. "(127.0.0.1) stále otevřená, a klikněte na záložku znovu.",
  web_m_page = "Tato stránka byla předána PowerVLC.",
  web_m_nav = "Otevírá se video, o které PowerVLC požádal — až bude vidět, "
            .. "klikněte na záložku znovu.",
  web_m_taken = "Tuto stránku má PowerVLC. Panel byl záměrně vyprázdněn: "
              .. "přehrávat video i zde by stroj stálo druhé dekódování a druhé "
              .. "stahování. Nechte jej otevřený.",
  web_addon_title = "Starší prohlížeče: nainstalujte rozšíření PowerVLC",
  web_addon = "TenFourFox, PowerFox a všechny prohlížeče před Firefoxem 69 "
            .. "odmítají spustit skript záložky na stránce s bezpečnostní "
            .. "politikou, a tu má každá instance: tam kliknutí na záložku "
            .. "neudělá vůbec nic. V přehrávači <strong>Nápověda &gt; "
            .. "Nainstalovat rozšíření PowerVLC</strong> umístí do prohlížeče "
            .. "malé rozšíření, které to zvládne samo — bez záložky, bez "
            .. "klikání, na každé stránce.",
}
