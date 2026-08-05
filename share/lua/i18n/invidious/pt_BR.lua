--[[ pt_BR.lua: the pt_BR catalogue of the invidious extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {

    title_connect = "Invidious — Conexão",
    title_search = "Invidious — Busca",
    title_video = "Invidious — Vídeo",
    date_fmt = "%Y-%m-%d",
    col_instance = "Instância",
    col_region = "Região",
    col_uptime = "Disponibilidade",
    col_title = "Título",
    col_channel = "Canal",
    col_date = "Publicado",
    col_subs = "Inscritos",
    col_videos = "Vídeos",
    btn_list_instances = "Listar instâncias públicas",
    btn_use_selection = "Usar a instância selecionada",
    lbl_instance = "Instância:",
    chk_proxy = "Encaminhar os fluxos pela instância (recomendado)",
    btn_connect = "Conectar",
    msg_fetching_instances = "Obtendo as instâncias públicas…",
    msg_no_instances = "Nenhuma instância utilizável encontrada",
    msg_instances_count = "%d instâncias — selecione uma e use «Usar a instância "
                    .. "selecionada»",
    msg_select_first = "Selecione antes uma instância na lista",
    msg_enter_url = "Informe antes o endereço de uma instância",
    msg_connecting = "Conectando…",
    msg_connect_fail = "Falha na conexão: ",
    msg_search_blocked = "Instância acessível, mas bloqueia a busca anônima pela "
                   .. "API (antirrobô) — tente outra ou uma instância própria",
    mode_videos = "Vídeos",
    mode_channels = "Canais",
    mode_playlists = "Listas de reprodução",
    btn_search = "Buscar",
    btn_open = "Abrir a seleção",
    btn_change_instance = "< Instância",
    msg_enter_query = "Digite algo para buscar",
    msg_searching = "Buscando…",
    msg_no_results = "Nenhum resultado",
    msg_results_count = "%d resultados (mais recentes primeiro)",
    msg_channel_loading = "Obtendo os vídeos do canal…",
    msg_playlist_loading = "Obtendo a lista de reprodução…",
    msg_target_found = "Endereço reconhecido — abrindo diretamente",
    msg_search_fail = "Falha na busca: ",
    msg_select_result = "Selecione antes um resultado na lista",
    lbl_quality = "Qualidade:",
    lbl_by = "de",
    audio_only = "Somente áudio",
    combined = "áudio+vídeo",
    video_only = "somente vídeo",
    live_hls = "Fluxo HLS (ao vivo)",
    btn_play = "Reproduzir",
    btn_copy = "Copiar o endereço do fluxo",
    btn_back = "< Voltar",
    msg_loading_video = "Obtendo as informações do vídeo…",
    msg_video_fail = "Não foi possível obter as informações do vídeo: ",
    msg_fallback_formats = "API de vídeo bloqueada pela instância — os fluxos "
                     .. "padrão foram testados no lugar",
    msg_trying_html = "API JSON fechada — tentando as páginas HTML…",
    msg_html_mode = "Conectado no modo HTML (API fechada nesta instância)",
    dash_auto = "Qualidade automática (DASH)",
    msg_no_formats = "Nenhum fluxo reproduzível encontrado para este vídeo",
    msg_playing = "Reprodução iniciada",
    msg_copied = "Endereço do fluxo copiado para a área de transferência",
    msg_copy_fallback = "Cópia automática indisponível — selecione o endereço "
                  .. "abaixo",
    title_challenge = "Invidious — Verificação antirrobô",
    lbl_challenge_1 = "Esta instância se protege com uma verificação que precisa "
                .. "executar JavaScript. O PowerVLC não a resolve: quem resolve "
                .. "é o seu navegador, que devolve o resultado.",
    lbl_challenge_2 = "1. Abra este endereço no seu navegador (PowerFox, Firefox, "
                .. "Safari…) e siga os três passos da página:",
    lbl_region = "Resultados para:",
    btn_challenge_copy = "Copiar o endereço",
    btn_challenge_open = "Abrir no navegador",
    lbl_challenge_3 = "2. O PowerVLC continua sozinho assim que o navegador "
                .. "terminar. Este botão só existe caso você prefira não "
                .. "esperar:",
    btn_challenge_done = "Passei na verificação",
    btn_challenge_cancel = "< Voltar",
    msg_challenge_copied = "Endereço copiado — cole-o no seu navegador",
    msg_challenge_opened = "Aberto no seu navegador — continue por lá",
    msg_challenge_no_browser = "O PowerVLC não conseguiu abrir um navegador: copie "
                         .. "o endereço.",
    msg_challenge_waiting = "Nada recebido ainda — conclua os passos no navegador "
                      .. "e pressione de novo",
    msg_challenge_ok = "Sessão recebida — tentando de novo",
    msg_challenge_fail = "Não foi possível abrir a página local de entrega: ",
    msg_challenge_needed = "Esta instância pede uma verificação antirrobô",
    msg_challenge_incomplete = "A verificação não terminou: a página precisa estar "
                         .. "realmente visível antes de você clicar no "
                         .. "favorito. Conclua-a e clique de novo.",
    msg_challenge_click = "Sua aba está abrindo este vídeo. Assim que ele "
                    .. "aparecer, clique no favorito — não há mais nada a "
                    .. "fazer.",
    msg_challenge_no_session = "Esta instância concede ao navegador uma permissão "
                         .. "para uma página de cada vez e não guarda nada "
                         .. "reutilizável, então não há o que entregar ao "
                         .. "PowerVLC. Tente outra instância.",
    web_title = "PowerVLC — verificação antirrobô",
    web_intro = "A verificação desta instância é resolvida pelo seu navegador, "
          .. "exatamente como se você visitasse o site. Depois o PowerVLC lê a "
          .. "página por essa aba; ele nunca resolve nada sozinho.",
    web_step1 = "Arraste este link para a sua barra de favoritos (de uma vez por "
          .. "todas):",
    web_bookmark = "Enviar ao PowerVLC",
    web_step2 = "Abra a instância e passe na verificação que ela mostrar:",
    web_step3 = "Quando a página <strong>estiver realmente visível</strong> — "
          .. "algumas instâncias pedem duas verificações seguidas — clique no "
          .. "favorito <em>Enviar ao PowerVLC</em> que você acabou de "
          .. "adicionar.",
    web_note = "Deixe esta janela e a aba da instância abertas enquanto navega: o "
         .. "PowerVLC lê cada página por elas. Fechar qualquer uma corta a "
         .. "ligação, e o favorito precisa ser clicado de novo.",
    web_done_title = "Pronto",
    web_done = "O PowerVLC já tem o que precisa. Deixe esta janela e a aba da "
         .. "instância abertas e volte ao reprodutor.",
    web_empty = "Nada de útil chegou. Verifique se a página está realmente visível "
          .. "— algumas instâncias pedem duas verificações seguidas — e clique "
          .. "de novo no favorito.",
    web_relay_on = "Conectado ao PowerVLC. Deixe esta janela e a aba da instância "
             .. "abertas enquanto navega.",
    web_relay_off = "Aguardando a aba da instância…",
    web_relay_busy = "A aba da instância ainda está resolvendo a verificação — o "
               .. "PowerVLC aguarda em vez de pedir qualquer coisa a ela.",
    web_m_drag = "Isto é um favorito, não um link: arraste-o para a barra de "
           .. "favoritos, depois abra a instância e clique nele LÁ, depois de "
           .. "passar na verificação.",
    web_m_ok = "O PowerVLC está conectado. Deixe esta aba aberta enquanto navega.",
    web_m_popup = "O PowerVLC não conseguiu abrir a janela dele: permita janelas "
            .. "pop-up para este site e clique de novo no favorito.",
    web_m_wait = "PowerVLC: conectando…",
    web_m_fail = "O PowerVLC não responde. Verifique se a página dele (127.0.0.1) "
           .. "continua aberta e clique de novo no favorito.",
    web_m_page = "Esta página foi entregue ao PowerVLC.",
    web_m_nav = "Abrindo o vídeo pedido pelo PowerVLC — clique de novo no favorito "
          .. "assim que ele aparecer.",
    web_m_taken = "O PowerVLC está com esta página. A aba foi esvaziada de "
            .. "propósito: reproduzir o vídeo aqui também custaria à máquina "
            .. "uma segunda decodificação e um segundo download. Deixe-a "
            .. "aberta.",
    web_addon_title = "Navegadores antigos: instale a extensão PowerVLC",
    web_addon = "TenFourFox, PowerFox e todos os navegadores anteriores ao Firefox "
          .. "69 se recusam a executar o script de um favorito em uma página "
          .. "com política de segurança, e todas as instâncias têm uma: ali, "
          .. "clicar no favorito não faz nada. No reprodutor, <strong>Ajuda "
          .. "&gt; Instalar a extensão PowerVLC</strong> coloca no seu "
          .. "navegador uma pequena extensão que faz isso sozinha — sem "
          .. "favorito, sem cliques, em todas as páginas.",
}
