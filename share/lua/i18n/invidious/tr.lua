--[[ tr.lua: the tr catalogue of the invidious extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {
  title_connect = "Invidious — Bağlantı",
  title_search = "Invidious — Arama",
  title_video = "Invidious — Video",
  date_fmt = "%Y-%m-%d",
  col_instance = "Örnek",
  col_region = "Bölge",
  col_uptime = "Çalışma süresi",
  col_title = "Başlık",
  col_channel = "Kanal",
  col_date = "Yayımlandı",
  col_subs = "Abone",
  col_videos = "Video",
  btn_list_instances = "Herkese açık örnekleri listele",
  btn_use_selection = "Seçili örneği kullan",
  lbl_instance = "Örnek:",
  chk_proxy = "Akışları örnek üzerinden geçir (önerilir)",
  btn_connect = "Bağlan",
  msg_fetching_instances = "Herkese açık örnekler alınıyor…",
  msg_no_instances = "Kullanılabilir örnek bulunamadı",
  msg_instances_count = "%d örnek — birini seçip «Seçili örneği kullan» "
                      .. "düğmesine basın",
  msg_select_first = "Önce listeden bir örnek seçin",
  msg_enter_url = "Önce bir örnek adresi girin",
  msg_connecting = "Bağlanılıyor…",
  msg_connect_fail = "Bağlantı başarısız: ",
  msg_search_blocked = "Örneğe erişiliyor ama API üzerinden anonim aramayı "
                     .. "engelliyor (bot koruması) — başka bir örneği ya da "
                     .. "kendi örneğinizi deneyin",
  mode_videos = "Videolar",
  mode_channels = "Kanallar",
  mode_playlists = "Oynatma listeleri",
  btn_search = "Ara",
  btn_open = "Seçileni aç",
  btn_open_channel = "Seçili öğenin kanalını aç",
  btn_change_instance = "< Örnek",
  msg_enter_query = "Aranacak bir şey yazın",
  msg_searching = "Aranıyor…",
  msg_no_results = "Sonuç yok",
  msg_results_count = "%d sonuç (en yeniler önce)",
  msg_channel_loading = "Kanalın videoları alınıyor…",
  msg_playlist_loading = "Oynatma listesi alınıyor…",
  msg_target_found = "Adres tanındı — doğrudan açılıyor",
  msg_search_fail = "Arama başarısız: ",
  msg_select_result = "Önce listeden bir sonuç seçin",
  msg_channel_unavailable = "Bu seçimle bağlantılı kanal kullanılamıyor",
  lbl_quality = "Kalite:",
  lbl_audio_track = "Ses izi:",
  audio_default = "Varsayılan ses",
  audio_original = "özgün",
  lbl_subtitles = "Altyazılar:",
  subtitles_none = "Yok",
  lbl_by = "—",
  audio_only = "Yalnızca ses",
  combined = "ses+video",
  video_only = "yalnızca video",
  live_hls = "HLS akışı (canlı)",
  btn_play = "Oynat",
  btn_copy = "Akış adresini kopyala",
  btn_back = "< Geri",
  msg_loading_video = "Video bilgileri alınıyor…",
  msg_video_fail = "Video bilgileri alınamadı: ",
  msg_fallback_formats = "Video API'si örnek tarafından engellendi — bunun "
                       .. "yerine standart akışlar yoklandı",
  msg_trying_html = "JSON API'si kapalı — HTML sayfaları deneniyor…",
  msg_html_mode = "HTML kipinde bağlanıldı (bu örnekte API kapalı)",
  dash_auto = "Otomatik kalite (DASH)",
  msg_no_formats = "Bu video için oynatılabilir akış bulunamadı",
  msg_playing = "Oynatma başladı",
  msg_copied = "Akış adresi panoya kopyalandı",
  msg_copy_fallback = "Otomatik kopyalama kullanılamıyor — aşağıdaki adresi "
                    .. "seçin",

  btn_download = "İndir",
  btn_download_audio = "Yalnızca sesi indir",
  msg_dl_busy = "Zaten bir indirme sürüyor — bitmesini bekleyin veya iptal edin",
  msg_no_audio_stream = "Bu videonun ayrı bir ses akışı yok",
  btn_dl_cancel = "İndirmeyi iptal et",
  msg_loading_thumb = "Küçük resim alınıyor…",
  dl_preparing = "İndirme hazırlanıyor…",
  dl_progress = "%s %d %% — dosya %d/%d — %s / %s",
  dl_done = "İndirme tamamlandı: %s — %s içinde",
  dl_done_pair = "İndirme tamamlandı: %s (görüntü) ve %s (ses) — %s içinde. Bu kalitenin birleşik akışı yok: iki dosya birlikte gider.",
  dl_error = "İndirme başarısız: ",
  dl_cancelled = "İndirme iptal edildi",
  msg_dl_playlist = "Bu öğe bir akış listesi, dosya değil: indirmek için çözünürlüklü bir kalite seçin",
  msg_dl_unsupported = "Bu sürüm indirme yapamıyor: eklenti zamanlayıcısı yok",
  msg_dl_no_dir = "İndirilenler klasörü bulunamadı",
  btn_combine = "İki dosyayı birleştir",
  msg_combine_gone = "İki dosya indirildikleri yerde değil artık",
  msg_combine_running = "Birleştiriliyor… %d %%",
  msg_combine_ok = "Birleştirme tamamlandı: %s",
  msg_combine_failed = "Birleştirme başarısız oldu — hiçbir şey yazılmadı",
  msg_combine_unsupported = "Bu sürüm iki dosyayı birleştiremez",
  title_challenge = "Invidious — Bot denetimi",
  lbl_challenge_1 = "Bu örnek, JavaScript çalıştırması gereken bir denetimle "
                  .. "korunuyor. PowerVLC onu çözmez: tarayıcınız çözer ve "
                  .. "sonucu geri verir.",
  lbl_challenge_2 = "1. Bu adresi tarayıcınızda açın (PowerFox, Firefox, "
                  .. "Safari…) ve sayfadaki üç adımı izleyin:",
  lbl_region = "Şunun için sonuçlar:",
  btn_challenge_copy = "Adresi kopyala",
  btn_challenge_open = "Tarayıcıda aç",
  lbl_challenge_3 = "2. Tarayıcı işini bitirir bitirmez PowerVLC kendiliğinden "
                  .. "devam eder. Bu düğme yalnızca beklemek istemezseniz diye "
                  .. "var:",
  btn_challenge_done = "Denetimi geçtim",
  btn_challenge_cancel = "< Geri",
  msg_challenge_copied = "Adres kopyalandı — tarayıcınıza yapıştırın",
  msg_challenge_opened = "Tarayıcınızda açıldı — oradan devam edin",
  msg_challenge_no_browser = "PowerVLC bir tarayıcı açamadı: bunun yerine "
                           .. "adresi kopyalayın.",
  msg_challenge_waiting = "Henüz bir şey gelmedi — tarayıcıdaki adımları "
                        .. "tamamlayıp yeniden basın",
  msg_challenge_ok = "Oturum alındı — yeniden deneniyor",
  msg_challenge_fail = "Yerel devir sayfası açılamadı: ",
  msg_challenge_needed = "Bu örnek bir bot denetimi istiyor",
  msg_challenge_incomplete = "Denetim tamamlanmadı: yer imine tıklamadan önce "
                           .. "sayfanın gerçekten görünüyor olması gerekir. "
                           .. "Tamamlayıp yeniden tıklayın.",
  msg_challenge_click = "Sekmeniz bu videoyu açıyor. Göründüğü anda yer imine "
                      .. "tıklayın — başka bir şey gerekmez.",
  msg_challenge_no_session = "Bu örnek tarayıcısına her seferinde tek bir "
                           .. "sayfa izni verir ve yeniden kullanılabilir "
                           .. "hiçbir şey saklamaz; dolayısıyla PowerVLC'ye "
                           .. "verilecek bir şey yok. Başka bir örnek deneyin.",
  web_title = "PowerVLC — bot denetimi",
  web_intro = "Bu örneğin denetimini tarayıcınız çözer, tıpkı siteyi kendiniz "
            .. "ziyaret ediyormuşsunuz gibi. PowerVLC sayfayı sonra o sekme "
            .. "üzerinden okur; kendi başına hiçbir şey çözmez.",
  web_step1 = "Bu bağlantıyı yer imi çubuğunuza sürükleyin (bir kez ve "
            .. "temelli):",
  web_bookmark = "PowerVLC'ye gönder",
  web_step2 = "Örneği açın ve gösterdiği denetimi geçin:",
  web_step3 = "Sayfa <strong>gerçekten göründüğünde</strong> — bazı örnekler "
            .. "art arda iki denetim ister — az önce eklediğiniz "
            .. "<em>PowerVLC'ye gönder</em> yer imine tıklayın.",
  web_note = "Gezinirken bu pencereyi ve örneğin sekmesini açık bırakın: "
           .. "PowerVLC her sayfayı bunlar üzerinden okur. Birini kapatmak "
           .. "bağlantıyı keser ve yer imine yeniden tıklamak gerekir.",
  web_done_title = "Tamam",
  web_done = "PowerVLC gerekeni aldı. Bu pencereyi ve örneğin sekmesini açık "
           .. "bırakıp oynatıcıya dönün.",
  web_empty = "Kullanılabilir bir şey gelmedi. Sayfanın gerçekten "
            .. "göründüğünden emin olun — bazı örnekler art arda iki denetim "
            .. "ister — ve yer imine yeniden tıklayın.",
  web_relay_on = "PowerVLC'ye bağlanıldı. Gezinirken bu pencereyi ve örneğin "
               .. "sekmesini açık bırakın.",
  web_relay_off = "Örneğin sekmesi bekleniyor…",
  web_relay_busy = "Örneğin sekmesi hâlâ denetimiyle uğraşıyor — PowerVLC "
                 .. "ondan bir şey istemek yerine bekliyor.",
  web_m_drag = "Bu bir yer imi, bağlantı değil: yer imi çubuğunuza sürükleyin, "
             .. "sonra örneği açıp denetimi geçtikten sonra ORADA tıklayın.",
  web_m_ok = "PowerVLC bağlı. Gezinirken bu sekmeyi açık bırakın.",
  web_m_popup = "PowerVLC penceresini açamadı: bu site için açılır pencerelere "
              .. "izin verip yer imine yeniden tıklayın.",
  web_m_wait = "PowerVLC: bağlanılıyor…",
  web_m_fail = "PowerVLC yanıt vermiyor. Sayfasının (127.0.0.1) hâlâ açık "
             .. "olduğunu doğrulayıp yer imine yeniden tıklayın.",
  web_m_page = "Bu sayfa PowerVLC'ye devredildi.",
  web_m_nav = "PowerVLC'nin istediği video açılıyor — göründüğü anda yer imine "
            .. "yeniden tıklayın.",
  web_m_taken = "Bu sayfa artık PowerVLC'de. Sekme bilerek boşaltıldı: videoyu "
              .. "burada da oynatmak makineye ikinci bir çözme ve ikinci bir "
              .. "indirme yükü bindirirdi. Açık bırakın.",
  web_addon_title = "Eski tarayıcılar: PowerVLC eklentisini kurun",
  web_addon = "TenFourFox, PowerFox ve Firefox 69 öncesi her tarayıcı, "
            .. "güvenlik ilkesi taşıyan bir sayfada yer iminin betiğini "
            .. "çalıştırmayı reddeder; her örnekte de böyle bir ilke vardır: "
            .. "orada yer imine tıklamak hiçbir şey yapmaz. Oynatıcıda "
            .. "<strong>Yardım &gt; PowerVLC eklentisini kur</strong>, "
            .. "tarayıcınıza bunu kendi başına yapan küçük bir eklenti "
            .. "yerleştirir — yer imi yok, tıklama yok, her sayfada.",
  web_addon_lead = "Eklenti kurulu mu? Sürüklenecek ve tıklanacak hiçbir şey "
                 .. "yok: aşağıdaki örneği açıp denetimini geçmeniz yeterli. "
                 .. "Bu sayfa bağlantının ne zaman kurulduğunu size bildirir.",
  web_steps_title = "Eklenti olmadan: yer imi",
  web_relay_on_addon = "PowerVLC'ye tarayıcı eklentisi üzerinden bağlanıldı. "
                     .. "Tıklanacak bir şey yok: bu pencereyi ve örneğin "
                     .. "sekmesini açık bırakın.",
  web_m_taking = "PowerVLC bu videoyu oynatıyor. Sekme bilerek hemen "
               .. "boşaltıldı: sitenin oynatıcısının burada yüklenmesini "
               .. "tamamlamasına izin vermek, makineye ikinci bir kod çözme "
               .. "ve ikinci bir indirme yükü bindirir, örneği de boş yere "
               .. "yorar. Sekmeyi açık bırakın.",
}
