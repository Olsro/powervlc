--[[ es.lua: the es catalogue of the invidious extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {

    title_connect = "Invidious — Conexión",
    title_search = "Invidious — Búsqueda",
    title_video = "Invidious — Vídeo",
    date_fmt = "%Y-%m-%d",
    col_instance = "Instancia",
    col_region = "Región",
    col_uptime = "Disponibilidad",
    col_title = "Título",
    col_channel = "Canal",
    col_date = "Publicado",
    col_subs = "Suscriptores",
    col_videos = "Vídeos",
    btn_list_instances = "Listar instancias públicas",
    btn_use_selection = "Usar la instancia seleccionada",
    lbl_instance = "Instancia:",
    chk_proxy = "Redirigir los flujos a través de la instancia (recomendado)",
    btn_connect = "Conectar",
    msg_fetching_instances = "Obteniendo las instancias públicas…",
    msg_no_instances = "No se encontró ninguna instancia utilizable",
    msg_instances_count = "%d instancias — seleccione una y pulse «Usar la "
                    .. "instancia seleccionada»",
    msg_select_first = "Seleccione antes una instancia en la lista",
    msg_enter_url = "Introduzca antes la dirección de una instancia",
    msg_connecting = "Conectando…",
    msg_connect_fail = "Error de conexión: ",
    msg_search_blocked = "La instancia responde, pero bloquea la búsqueda anónima "
                   .. "por API (antibots) — pruebe otra o una instancia propia",
    mode_videos = "Vídeos",
    mode_channels = "Canales",
    mode_playlists = "Listas de reproducción",
    btn_search = "Buscar",
    btn_open = "Abrir la selección",
    btn_change_instance = "< Instancia",
    msg_enter_query = "Escriba algo que buscar",
    msg_searching = "Buscando…",
    msg_no_results = "Sin resultados",
    msg_results_count = "%d resultados (los más recientes primero)",
    msg_channel_loading = "Obteniendo los vídeos del canal…",
    msg_playlist_loading = "Obteniendo la lista de reproducción…",
    msg_target_found = "Dirección reconocida — se abre directamente",
    msg_search_fail = "Error en la búsqueda: ",
    msg_select_result = "Seleccione antes un resultado en la lista",
    lbl_quality = "Calidad:",
    lbl_by = "de",
    audio_only = "Solo audio",
    combined = "audio+vídeo",
    video_only = "solo vídeo",
    live_hls = "Flujo HLS (en directo)",
    btn_play = "Reproducir",
    btn_copy = "Copiar la dirección del flujo",
    btn_back = "< Atrás",
    msg_loading_video = "Obteniendo la información del vídeo…",
    msg_video_fail = "No se pudo obtener la información del vídeo: ",
    msg_fallback_formats = "La instancia bloquea la API de vídeo — se han sondeado "
                     .. "los flujos estándar en su lugar",
    msg_trying_html = "API JSON cerrada — se intentan las páginas HTML…",
    msg_html_mode = "Conectado en modo HTML (API cerrada en esta instancia)",
    dash_auto = "Calidad automática (DASH)",
    msg_no_formats = "No se encontró ningún flujo reproducible para este vídeo",
    msg_playing = "Reproducción iniciada",
    msg_copied = "Dirección del flujo copiada al portapapeles",
    msg_copy_fallback = "Copia automática no disponible — seleccione la dirección "
                  .. "de abajo",

    btn_download = "Descargar",
    btn_download_audio = "Descargar solo el sonido",
    msg_dl_busy = "Ya hay una descarga en curso — espérela o cancélela",
    msg_no_audio_stream = "Este vídeo no ofrece ningún flujo de sonido separado",
    btn_dl_cancel = "Cancelar la descarga",
    msg_loading_thumb = "Obteniendo la miniatura…",
    dl_preparing = "Preparando la descarga…",
    dl_progress = "%s %d %% — archivo %d/%d — %s / %s",
    dl_done = "Descarga terminada: %s — en %s",
    dl_done_pair = "Descarga terminada: %s (imagen) y %s (sonido) — en %s. Esta calidad no existe como flujo combinado: los dos archivos van juntos.",
    dl_error = "La descarga ha fallado: ",
    dl_cancelled = "Descarga cancelada",
    msg_dl_playlist = "Esta entrada es una lista de flujos, no un archivo: elija una calidad con resolución para descargarla",
    msg_dl_unsupported = "Esta versión no puede descargar: no tiene temporizador de extensiones",
    msg_dl_no_dir = "No se ha encontrado la carpeta Descargas",
    btn_combine = "Combinar los dos archivos con ffmpeg",
    combine_banner = "PowerVLC: combinando imagen y sonido, sin recodificar.",
    combine_no_ffmpeg = "ffmpeg no está instalado, o no está en el PATH. Instálelo y vuelva a ejecutar este archivo.",
    combine_done = "Terminado:",
    msg_combine_launched = "ffmpeg iniciado en una ventana de terminal — allí se ve si ha funcionado",
    msg_combine_copied = "No se ha podido abrir ningún terminal — la orden ffmpeg se ha copiado al portapapeles",
    msg_combine_fallback = "No se ha podido abrir ningún terminal — la orden ffmpeg está en el campo de abajo",
    msg_combine_gone = "Los dos archivos ya no están donde se descargaron",
    title_challenge = "Invidious — Verificación antibots",
    lbl_challenge_1 = "Esta instancia se protege con una verificación que necesita "
                .. "ejecutar JavaScript. PowerVLC no la resuelve: lo hace su "
                .. "navegador, y devuelve el resultado.",
    lbl_challenge_2 = "1. Abra esta dirección en su navegador (PowerFox, Firefox, "
                .. "Safari…) y siga los tres pasos de la página:",
    lbl_region = "Resultados para:",
    btn_challenge_copy = "Copiar la dirección",
    btn_challenge_open = "Abrir en el navegador",
    lbl_challenge_3 = "2. PowerVLC continúa solo en cuanto el navegador termina. "
                .. "Este botón solo está aquí por si prefiere no esperar:",
    btn_challenge_done = "He superado la verificación",
    btn_challenge_cancel = "< Atrás",
    msg_challenge_copied = "Dirección copiada — péguela en su navegador",
    msg_challenge_opened = "Abierta en su navegador — continúe allí",
    msg_challenge_no_browser = "PowerVLC no pudo abrir un navegador: copie la "
                         .. "dirección en su lugar.",
    msg_challenge_waiting = "Todavía no se ha recibido nada — termine los pasos en "
                      .. "el navegador y pulse de nuevo",
    msg_challenge_ok = "Sesión recibida — reintentando",
    msg_challenge_fail = "No se pudo abrir la página local de entrega: ",
    msg_challenge_needed = "Esta instancia pide una verificación antibots",
    msg_challenge_incomplete = "La verificación no ha terminado: la página debe "
                         .. "estar realmente visible antes de pulsar el "
                         .. "marcador. Termínela y vuelva a pulsar.",
    msg_challenge_click = "Su pestaña está abriendo este vídeo. En cuanto se vea, "
                    .. "pulse el marcador — no hay nada más que hacer.",
    msg_challenge_no_session = "Esta instancia concede a su navegador un permiso "
                         .. "de una página cada vez y no guarda nada "
                         .. "reutilizable, así que no hay nada que entregar a "
                         .. "PowerVLC. Pruebe otra instancia.",
    web_title = "PowerVLC — verificación antibots",
    web_intro = "La verificación de esta instancia la resuelve su navegador, "
          .. "exactamente igual que si visitara el sitio usted mismo. PowerVLC "
          .. "lee después la página a través de esa pestaña; nunca resuelve "
          .. "nada por su cuenta.",
    web_step1 = "Arrastre este enlace a su barra de marcadores (una vez y para "
          .. "siempre):",
    web_bookmark = "Enviar a PowerVLC",
    web_step2 = "Abra la instancia y supere la verificación que muestre:",
    web_step3 = "Cuando la página <strong>se vea realmente</strong> — algunas "
          .. "instancias piden dos verificaciones seguidas — pulse el marcador "
          .. "<em>Enviar a PowerVLC</em> que acaba de añadir.",
    web_note = "Deje esta ventana y la pestaña de la instancia abiertas mientras "
         .. "navega: PowerVLC lee cada página a través de ellas. Cerrar "
         .. "cualquiera de las dos corta el enlace y hay que volver a pulsar el "
         .. "marcador.",
    web_done_title = "Listo",
    web_done = "PowerVLC ya tiene lo que necesita. Deje esta ventana y la pestaña "
         .. "de la instancia abiertas y vuelva al reproductor.",
    web_empty = "No llegó nada utilizable. Asegúrese de que la página se ve "
          .. "realmente — algunas instancias piden dos verificaciones seguidas "
          .. "— y pulse de nuevo el marcador.",
    web_relay_on = "Conectado a PowerVLC. Deje esta ventana y la pestaña de la "
             .. "instancia abiertas mientras navega.",
    web_relay_off = "Esperando la pestaña de la instancia…",
    web_relay_busy = "La pestaña de la instancia sigue con su verificación — "
               .. "PowerVLC espera en lugar de pedirle nada.",
    web_m_drag = "Esto es un marcador, no un enlace: arrástrelo a su barra de "
           .. "marcadores, abra después la instancia y púlselo ALLÍ, una vez "
           .. "superada la verificación.",
    web_m_ok = "PowerVLC está conectado. Deje esta pestaña abierta mientras "
         .. "navega.",
    web_m_popup = "PowerVLC no pudo abrir su ventana: permita las ventanas "
            .. "emergentes para este sitio y pulse de nuevo el marcador.",
    web_m_wait = "PowerVLC: conectando…",
    web_m_fail = "PowerVLC no responde. Compruebe que su página (127.0.0.1) sigue "
           .. "abierta y pulse de nuevo el marcador.",
    web_m_page = "Esta página se ha entregado a PowerVLC.",
    web_m_nav = "Abriendo el vídeo que PowerVLC ha pedido — pulse de nuevo el "
          .. "marcador cuando se vea.",
    web_m_taken = "PowerVLC tiene esta página. La pestaña se ha vaciado a "
            .. "propósito: reproducir aquí también el vídeo le costaría a la "
            .. "máquina una segunda descodificación y una segunda descarga. "
            .. "Déjela abierta.",
    web_addon_title = "Navegadores antiguos: instale la extensión PowerVLC",
    web_addon = "TenFourFox, PowerFox y todos los navegadores anteriores a Firefox "
          .. "69 se niegan a ejecutar el script de un marcador en una página "
          .. "con política de seguridad, y todas las instancias tienen una: "
          .. "allí, pulsar el marcador no hace absolutamente nada. En el "
          .. "reproductor, <strong>Ayuda &gt; Instalar la extensión "
          .. "PowerVLC</strong> coloca en su navegador una pequeña extensión "
          .. "que se encarga sola — sin marcador, sin clics, en todas las "
          .. "páginas.",
}
