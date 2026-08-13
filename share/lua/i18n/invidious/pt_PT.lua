--[[ pt_PT.lua: the pt_PT catalogue of the invidious extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {

    title_connect = "Invidious — Ligação",
    title_search = "Invidious — Pesquisa",
    title_video = "Invidious — Vídeo",
    date_fmt = "%Y-%m-%d",
    col_instance = "Instância",
    col_region = "Região",
    col_uptime = "Disponibilidade",
    col_title = "Título",
    col_channel = "Canal",
    col_date = "Publicado",
    col_subs = "Subscritores",
    col_videos = "Vídeos",
    btn_list_instances = "Listar instâncias públicas",
    btn_use_selection = "Utilizar a instância selecionada",
    lbl_instance = "Instância:",
    chk_proxy = "Encaminhar os fluxos pela instância (recomendado)",
    btn_connect = "Ligar",
    msg_fetching_instances = "A obter as instâncias públicas…",
    msg_no_instances = "Não foi encontrada nenhuma instância utilizável",
    msg_instances_count = "%d instâncias — selecione uma e depois «Utilizar a "
                    .. "instância selecionada»",
    msg_select_first = "Selecione primeiro uma instância na lista",
    msg_enter_url = "Introduza primeiro o endereço de uma instância",
    msg_connecting = "A ligar…",
    msg_connect_fail = "A ligação falhou: ",
    msg_search_blocked = "Instância acessível, mas bloqueia a pesquisa anónima "
                   .. "pela API (antirrobô) — experimente outra ou uma "
                   .. "instância pessoal",
    mode_videos = "Vídeos",
    mode_channels = "Canais",
    mode_playlists = "Listas de reprodução",
    btn_search = "Pesquisar",
    btn_open = "Abrir a seleção",
    btn_change_instance = "< Instância",
    msg_enter_query = "Escreva algo para pesquisar",
    msg_searching = "A pesquisar…",
    msg_no_results = "Sem resultados",
    msg_results_count = "%d resultados (mais recentes primeiro)",
    msg_channel_loading = "A obter os vídeos do canal…",
    msg_playlist_loading = "A obter a lista de reprodução…",
    msg_target_found = "Endereço reconhecido — a abrir diretamente",
    msg_search_fail = "A pesquisa falhou: ",
    msg_select_result = "Selecione primeiro um resultado na lista",
    lbl_quality = "Qualidade:",
    lbl_by = "de",
    audio_only = "Apenas áudio",
    combined = "áudio+vídeo",
    video_only = "apenas vídeo",
    live_hls = "Fluxo HLS (em direto)",
    btn_play = "Reproduzir",
    btn_copy = "Copiar o endereço do fluxo",
    btn_back = "< Voltar",
    msg_loading_video = "A obter as informações do vídeo…",
    msg_video_fail = "Não foi possível obter as informações do vídeo: ",
    msg_fallback_formats = "API de vídeo bloqueada pela instância — foram sondados "
                     .. "os fluxos padrão",
    msg_trying_html = "API JSON fechada — a tentar as páginas HTML…",
    msg_html_mode = "Ligado em modo HTML (API fechada nesta instância)",
    dash_auto = "Qualidade automática (DASH)",
    msg_no_formats = "Não foi encontrado nenhum fluxo reproduzível para este vídeo",
    msg_playing = "Reprodução iniciada",
    msg_copied = "Endereço do fluxo copiado para a área de transferência",
    msg_copy_fallback = "Cópia automática indisponível — selecione o endereço "
                  .. "abaixo",

    btn_download = "Transferir",
    btn_download_audio = "Transferir apenas o som",
    msg_dl_busy = "Já está uma transferência em curso — aguarde ou cancele",
    msg_no_audio_stream = "Este vídeo não oferece qualquer fluxo de som separado",
    btn_dl_cancel = "Cancelar a transferência",
    msg_loading_thumb = "A obter a miniatura…",
    dl_preparing = "A preparar a transferência…",
    dl_progress = "%s %d %% — ficheiro %d/%d — %s / %s",
    dl_done = "Transferência concluída: %s — em %s",
    dl_done_pair = "Transferência concluída: %s (imagem) e %s (som) — em %s. Esta qualidade não existe como fluxo combinado: os dois ficheiros vão juntos.",
    dl_error = "Falha na transferência: ",
    dl_cancelled = "Transferência cancelada",
    msg_dl_playlist = "Esta entrada é uma lista de fluxos, não um ficheiro: escolha uma qualidade com resolução para a transferir",
    msg_dl_unsupported = "Esta versão não sabe transferir: não tem o temporizador de extensões",
    msg_dl_no_dir = "Pasta Transferências não encontrada",
    btn_combine = "Combinar os dois ficheiros com o ffmpeg",
    combine_banner = "PowerVLC: a combinar imagem e som, sem recodificar.",
    combine_no_ffmpeg = "O ffmpeg não está instalado, ou não está no PATH. Instale-o e execute este ficheiro novamente.",
    combine_done = "Concluído:",
    msg_combine_launched = "ffmpeg iniciado numa janela de terminal — é aí que se vê se resultou",
    msg_combine_copied = "Não foi possível abrir um terminal — o comando ffmpeg foi copiado para a área de transferência",
    msg_combine_fallback = "Não foi possível abrir um terminal — o comando ffmpeg está no campo abaixo",
    msg_combine_gone = "Os dois ficheiros já não estão onde foram transferidos",
    title_challenge = "Invidious — Verificação antirrobô",
    lbl_challenge_1 = "Esta instância protege-se com uma verificação que precisa "
                .. "de executar JavaScript. O PowerVLC não a resolve: é o seu "
                .. "navegador que o faz e devolve o resultado.",
    lbl_challenge_2 = "1. Abra este endereço no seu navegador (PowerFox, Firefox, "
                .. "Safari…) e siga os três passos da página:",
    lbl_region = "Resultados para:",
    btn_challenge_copy = "Copiar o endereço",
    btn_challenge_open = "Abrir no navegador",
    lbl_challenge_3 = "2. O PowerVLC prossegue sozinho assim que o navegador "
                .. "terminar. Este botão só existe caso prefira não esperar:",
    btn_challenge_done = "Passei na verificação",
    btn_challenge_cancel = "< Voltar",
    msg_challenge_copied = "Endereço copiado — cole-o no seu navegador",
    msg_challenge_opened = "Aberto no seu navegador — continue por lá",
    msg_challenge_no_browser = "O PowerVLC não conseguiu abrir um navegador: copie "
                         .. "o endereço.",
    msg_challenge_waiting = "Ainda não chegou nada — conclua os passos no "
                      .. "navegador e prima novamente",
    msg_challenge_ok = "Sessão recebida — a tentar de novo",
    msg_challenge_fail = "Não foi possível abrir a página local de entrega: ",
    msg_challenge_needed = "Esta instância pede uma verificação antirrobô",
    msg_challenge_incomplete = "A verificação não terminou: a página tem de estar "
                         .. "mesmo visível antes de clicar no marcador. "
                         .. "Conclua-a e clique novamente.",
    msg_challenge_click = "O seu separador está a abrir este vídeo. Assim que "
                    .. "aparecer, clique no marcador — não há mais nada a "
                    .. "fazer.",
    msg_challenge_no_session = "Esta instância dá ao navegador permissão para uma "
                         .. "página de cada vez e não guarda nada reutilizável, "
                         .. "pelo que não há nada para entregar ao PowerVLC. "
                         .. "Experimente outra instância.",
    web_title = "PowerVLC — verificação antirrobô",
    web_intro = "A verificação desta instância é resolvida pelo seu navegador, tal "
          .. "como se fosse você a visitar o site. Depois o PowerVLC lê a "
          .. "página através desse separador; nunca resolve nada sozinho.",
    web_step1 = "Arraste esta ligação para a barra de marcadores (de uma vez por "
          .. "todas):",
    web_bookmark = "Enviar para o PowerVLC",
    web_step2 = "Abra a instância e passe na verificação que ela mostrar:",
    web_step3 = "Quando a página <strong>estiver mesmo visível</strong> — algumas "
          .. "instâncias pedem duas verificações seguidas — clique no marcador "
          .. "<em>Enviar para o PowerVLC</em> que acabou de adicionar.",
    web_note = "Deixe esta janela e o separador da instância abertos enquanto "
         .. "navega: o PowerVLC lê cada página através deles. Fechar qualquer "
         .. "um corta a ligação e é preciso clicar novamente no marcador.",
    web_done_title = "Concluído",
    web_done = "O PowerVLC já tem o que precisa. Deixe esta janela e o separador "
         .. "da instância abertos e volte ao leitor.",
    web_empty = "Não chegou nada de útil. Confirme que a página está mesmo visível "
          .. "— algumas instâncias pedem duas verificações seguidas — e clique "
          .. "novamente no marcador.",
    web_relay_on = "Ligado ao PowerVLC. Deixe esta janela e o separador da "
             .. "instância abertos enquanto navega.",
    web_relay_off = "À espera do separador da instância…",
    web_relay_busy = "O separador da instância ainda está a resolver a verificação "
               .. "— o PowerVLC espera em vez de lhe pedir seja o que for.",
    web_m_drag = "Isto é um marcador, não uma ligação: arraste-o para a barra de "
           .. "marcadores, abra depois a instância e clique nele LÁ, depois de "
           .. "passar na verificação.",
    web_m_ok = "O PowerVLC está ligado. Deixe este separador aberto enquanto "
         .. "navega.",
    web_m_popup = "O PowerVLC não conseguiu abrir a sua janela: permita as janelas "
            .. "pop-up para este sítio e clique novamente no marcador.",
    web_m_wait = "PowerVLC: a ligar…",
    web_m_fail = "O PowerVLC não responde. Verifique se a página dele (127.0.0.1) "
           .. "continua aberta e clique novamente no marcador.",
    web_m_page = "Esta página foi entregue ao PowerVLC.",
    web_m_nav = "A abrir o vídeo pedido pelo PowerVLC — clique novamente no "
          .. "marcador assim que aparecer.",
    web_m_taken = "O PowerVLC tem esta página. O separador foi esvaziado de "
            .. "propósito: reproduzir aqui também o vídeo custaria à máquina "
            .. "uma segunda descodificação e uma segunda transferência. Deixe-o "
            .. "aberto.",
    web_addon_title = "Navegadores antigos: instale a extensão PowerVLC",
    web_addon = "O TenFourFox, o PowerFox e todos os navegadores anteriores ao "
          .. "Firefox 69 recusam executar o script de um marcador numa página "
          .. "com política de segurança, e todas as instâncias têm uma: aí, "
          .. "clicar no marcador não faz nada. No leitor, <strong>Ajuda &gt; "
          .. "Instalar a extensão PowerVLC</strong> coloca no seu navegador uma "
          .. "pequena extensão que trata disso sozinha — sem marcador, sem "
          .. "cliques, em todas as páginas.",
}
