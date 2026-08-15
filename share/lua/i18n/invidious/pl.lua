--[[ pl.lua: the pl catalogue of the invidious extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {
  title_connect = "Invidious — Połączenie",
  title_search = "Invidious — Wyszukiwanie",
  title_video = "Invidious — Wideo",
  date_fmt = "%Y-%m-%d",
  col_instance = "Instancja",
  col_region = "Region",
  col_uptime = "Dostępność",
  col_title = "Tytuł",
  col_channel = "Kanał",
  col_date = "Opublikowano",
  col_subs = "Subskrybenci",
  col_videos = "Filmy",
  btn_list_instances = "Pokaż publiczne instancje",
  btn_use_selection = "Użyj wybranej instancji",
  lbl_instance = "Instancja:",
  chk_proxy = "Przekazuj strumienie przez instancję (zalecane)",
  btn_connect = "Połącz",
  msg_fetching_instances = "Pobieranie publicznych instancji…",
  msg_no_instances = "Nie znaleziono użytecznej instancji",
  msg_instances_count = "%d instancji — wybierz jedną, a potem „Użyj wybranej "
                      .. "instancji”",
  msg_select_first = "Najpierw wybierz instancję z listy",
  msg_enter_url = "Najpierw podaj adres instancji",
  msg_connecting = "Łączenie…",
  msg_connect_fail = "Połączenie nie powiodło się: ",
  msg_search_blocked = "Instancja odpowiada, ale blokuje anonimowe "
                     .. "wyszukiwanie przez API (ochrona przed botami) — "
                     .. "spróbuj innej lub własnej",
  mode_videos = "Filmy",
  mode_channels = "Kanały",
  mode_playlists = "Playlisty",
  btn_search = "Szukaj",
  btn_open = "Otwórz zaznaczone",
  btn_change_instance = "< Instancja",
  msg_enter_query = "Wpisz, czego szukać",
  msg_searching = "Wyszukiwanie…",
  msg_no_results = "Brak wyników",
  msg_results_count = "%d wyników (najnowsze na początku)",
  msg_channel_loading = "Pobieranie filmów kanału…",
  msg_playlist_loading = "Pobieranie playlisty…",
  msg_target_found = "Rozpoznano adres — otwieram go bezpośrednio",
  msg_search_fail = "Wyszukiwanie nie powiodło się: ",
  msg_select_result = "Najpierw wybierz wynik z listy",
  lbl_quality = "Jakość:",
  lbl_by = "—",
  audio_only = "Tylko dźwięk",
  combined = "dźwięk+obraz",
  video_only = "tylko obraz",
  live_hls = "Strumień HLS (na żywo)",
  btn_play = "Odtwórz",
  btn_copy = "Kopiuj adres strumienia",
  btn_back = "< Wstecz",
  msg_loading_video = "Pobieranie informacji o filmie…",
  msg_video_fail = "Nie udało się pobrać informacji o filmie: ",
  msg_fallback_formats = "Instancja blokuje API wideo — zamiast tego "
                       .. "sprawdzono standardowe strumienie",
  msg_trying_html = "API JSON zamknięte — próbuję stron HTML…",
  msg_html_mode = "Połączono w trybie HTML (API zamknięte na tej instancji)",
  dash_auto = "Jakość automatyczna (DASH)",
  msg_no_formats = "Nie znaleziono odtwarzalnego strumienia dla tego filmu",
  msg_playing = "Rozpoczęto odtwarzanie",
  msg_copied = "Adres strumienia skopiowany do schowka",
  msg_copy_fallback = "Automatyczne kopiowanie niedostępne — zaznacz adres "
                    .. "poniżej",

  btn_download = "Pobierz",
  btn_download_audio = "Pobierz sam dźwięk",
  msg_dl_busy = "Pobieranie już trwa — poczekaj na nie lub je anuluj",
  msg_no_audio_stream = "Ten film nie udostępnia osobnego strumienia dźwięku",
  btn_dl_cancel = "Anuluj pobieranie",
  msg_loading_thumb = "Pobieranie miniatury…",
  dl_preparing = "Przygotowywanie pobierania…",
  dl_progress = "%s %d %% — plik %d/%d — %s / %s",
  dl_done = "Pobieranie zakończone: %s — w %s",
  dl_done_pair = "Pobieranie zakończone: %s (obraz) i %s (dźwięk) — w %s. Ta jakość nie istnieje jako połączony strumień: oba pliki należą do siebie.",
  dl_error = "Pobieranie nie powiodło się: ",
  dl_cancelled = "Pobieranie anulowane",
  msg_dl_playlist = "Ta pozycja to lista strumieni, a nie plik: wybierz jakość z rozdzielczością, aby ją pobrać",
  msg_dl_unsupported = "Ta wersja nie potrafi pobierać: nie ma czasomierza rozszerzeń",
  msg_dl_no_dir = "Nie znaleziono folderu Pobrane",
  btn_combine = "Połącz oba pliki",
  msg_combine_gone = "Obu plików nie ma już tam, gdzie zostały pobrane",
  msg_combine_running = "Łączenie… %d %%",
  msg_combine_ok = "Łączenie zakończone: %s",
  msg_combine_failed = "Łączenie nie powiodło się — nic nie zapisano",
  msg_combine_unsupported = "Ta wersja nie potrafi połączyć obu plików",
  title_challenge = "Invidious — Kontrola antybotowa",
  lbl_challenge_1 = "Ta instancja chroni się kontrolą wymagającą JavaScriptu. "
                  .. "PowerVLC jej nie rozwiązuje: robi to twoja przeglądarka i "
                  .. "oddaje wynik.",
  lbl_challenge_2 = "1. Otwórz ten adres w przeglądarce (PowerFox, Firefox, "
                  .. "Safari…) i wykonaj trzy kroki ze strony:",
  lbl_region = "Wyniki dla:",
  btn_challenge_copy = "Kopiuj adres",
  btn_challenge_open = "Otwórz w przeglądarce",
  lbl_challenge_3 = "2. PowerVLC ruszy dalej sam, gdy przeglądarka skończy. "
                  .. "Ten przycisk jest tylko na wypadek, gdybyś nie chciał "
                  .. "czekać:",
  btn_challenge_done = "Przeszedłem kontrolę",
  btn_challenge_cancel = "< Wstecz",
  msg_challenge_copied = "Adres skopiowany — wklej go w przeglądarce",
  msg_challenge_opened = "Otwarto w przeglądarce — kontynuuj tam",
  msg_challenge_no_browser = "PowerVLC nie mógł otworzyć przeglądarki: skopiuj "
                           .. "adres ręcznie.",
  msg_challenge_waiting = "Jeszcze nic nie dotarło — dokończ kroki w "
                        .. "przeglądarce i naciśnij ponownie",
  msg_challenge_ok = "Sesja odebrana — ponawiam",
  msg_challenge_fail = "Nie udało się otworzyć lokalnej strony przekazania: ",
  msg_challenge_needed = "Ta instancja wymaga kontroli antybotowej",
  msg_challenge_incomplete = "Kontrola nie została zakończona: strona musi być "
                           .. "naprawdę widoczna, zanim klikniesz zakładkę. "
                           .. "Dokończ ją i kliknij ponownie.",
  msg_challenge_click = "Twoja karta otwiera ten film. Gdy tylko się pokaże, "
                      .. "kliknij zakładkę — nic więcej nie trzeba robić.",
  msg_challenge_no_session = "Ta instancja daje swojej przeglądarce dostęp do "
                           .. "jednej strony naraz i nie zachowuje niczego "
                           .. "wielokrotnego użytku, więc nie ma czego "
                           .. "przekazać PowerVLC. Spróbuj innej instancji.",
  web_title = "PowerVLC — kontrola antybotowa",
  web_intro = "Kontrolę tej instancji rozwiązuje twoja przeglądarka, dokładnie "
            .. "tak, jakbyś sam odwiedził stronę. PowerVLC czyta potem stronę "
            .. "przez tę kartę; sam nigdy niczego nie rozwiązuje.",
  web_step1 = "Przeciągnij ten odnośnik na pasek zakładek (raz na zawsze):",
  web_bookmark = "Wyślij do PowerVLC",
  web_step2 = "Otwórz instancję i przejdź pokazaną kontrolę:",
  web_step3 = "Gdy strona <strong>naprawdę się wyświetli</strong> — niektóre "
            .. "instancje proszą o dwie kontrole z rzędu — kliknij dodaną przed "
            .. "chwilą zakładkę <em>Wyślij do PowerVLC</em>.",
  web_note = "Zostaw to okno i kartę instancji otwarte podczas przeglądania: "
           .. "PowerVLC czyta przez nie każdą stronę. Zamknięcie któregokolwiek "
           .. "przerywa połączenie i zakładkę trzeba kliknąć ponownie.",
  web_done_title = "Gotowe",
  web_done = "PowerVLC ma to, czego potrzebuje. Zostaw to okno i kartę "
           .. "instancji otwarte i wróć do odtwarzacza.",
  web_empty = "Nie dotarło nic użytecznego. Upewnij się, że strona naprawdę "
            .. "się wyświetla — niektóre instancje proszą o dwie kontrole z "
            .. "rzędu — i kliknij zakładkę ponownie.",
  web_relay_on = "Połączono z PowerVLC. Zostaw to okno i kartę instancji "
               .. "otwarte podczas przeglądania.",
  web_relay_off = "Oczekiwanie na kartę instancji…",
  web_relay_busy = "Karta instancji wciąż przechodzi kontrolę — PowerVLC "
                 .. "czeka, zamiast czegokolwiek od niej żądać.",
  web_m_drag = "To jest zakładka, a nie odnośnik: przeciągnij ją na pasek "
             .. "zakładek, potem otwórz instancję i kliknij ją TAM, po "
             .. "przejściu kontroli.",
  web_m_ok = "PowerVLC jest połączony. Zostaw tę kartę otwartą podczas "
           .. "przeglądania.",
  web_m_popup = "PowerVLC nie mógł otworzyć swojego okna: zezwól na "
              .. "wyskakujące okna dla tej witryny i kliknij zakładkę ponownie.",
  web_m_wait = "PowerVLC: łączenie…",
  web_m_fail = "PowerVLC nie odpowiada. Sprawdź, czy jego strona (127.0.0.1) "
             .. "jest nadal otwarta, i kliknij zakładkę ponownie.",
  web_m_page = "Ta strona została przekazana PowerVLC.",
  web_m_nav = "Otwieram film, o który poprosił PowerVLC — kliknij zakładkę "
            .. "ponownie, gdy się pokaże.",
  web_m_taken = "PowerVLC ma tę stronę. Karta została opróżniona celowo: "
              .. "odtwarzanie filmu również tutaj kosztowałoby maszynę drugie "
              .. "dekodowanie i drugie pobieranie. Zostaw ją otwartą.",
  web_addon_title = "Starsze przeglądarki: zainstaluj rozszerzenie PowerVLC",
  web_addon = "TenFourFox, PowerFox i każda przeglądarka sprzed Firefoksa 69 "
            .. "odmawiają wykonania skryptu zakładki na stronie z polityką "
            .. "bezpieczeństwa, a ma ją każda instancja: tam kliknięcie "
            .. "zakładki nie robi zupełnie nic. W odtwarzaczu <strong>Pomoc "
            .. "&gt; Zainstaluj rozszerzenie PowerVLC</strong> umieszcza w "
            .. "przeglądarce małe rozszerzenie, które robi to samo — bez "
            .. "zakładki, bez klikania, na każdej stronie.",
}
