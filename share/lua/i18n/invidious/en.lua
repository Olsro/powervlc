--[[ en.lua: the en catalogue of the invidious extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {

    title_connect = "Invidious — Connection",
    title_search = "Invidious — Search",
    title_video = "Invidious — Video",
    -- ISO on purpose: the column sort is lexicographic
    date_fmt = "%Y-%m-%d",
    col_instance = "Instance",
    col_region = "Region",
    col_uptime = "Uptime",
    col_title = "Title",
    col_channel = "Channel",
    col_date = "Published",
    col_subs = "Subscribers",
    col_videos = "Videos",

    btn_list_instances = "List public instances",
    btn_use_selection = "Use selected instance",
    lbl_instance = "Instance:",
    chk_proxy = "Proxy streams through the instance when direct playback fails (recommended)",
    btn_connect = "Connect",
    msg_fetching_instances = "Fetching public instances...",
    msg_no_instances = "No usable instance found",
    msg_instances_count = "%d instances — select one, then 'Use selected instance'",
    msg_select_first = "Select an instance in the list first",
    msg_enter_url = "Enter an instance URL first",
    msg_connecting = "Connecting...",
    msg_connect_fail = "Connection failed: ",
    msg_search_blocked = "Instance reachable, but it blocks anonymous API "
                      .. "search (anti-bot) — try another one or a "
                      .. "personal instance",

    mode_videos = "Videos",
    mode_channels = "Channels",
    mode_playlists = "Playlists",
    btn_search = "Search",
    btn_open = "Open selection",
    btn_change_instance = "< Instance",
    msg_enter_query = "Enter something to search for",
    msg_searching = "Searching...",
    msg_no_results = "No result",
    msg_results_count = "%d results (newest first)",
    msg_channel_loading = "Fetching channel videos...",
    msg_playlist_loading = "Fetching the playlist...",
    msg_target_found = "Address recognised — opening it directly",
    msg_search_fail = "Search failed: ",
    msg_select_result = "Select a result in the list first",

    lbl_quality = "Quality:",
    lbl_by = "by",
    audio_only = "Audio only",
    combined = "audio+video",
    video_only = "video only",
    live_hls = "HLS stream (live)",
    btn_play = "Play",
    btn_copy = "Copy stream URL",
    btn_back = "< Back",
    msg_loading_video = "Fetching video info...",
    msg_video_fail = "Could not fetch video info: ",
    msg_fallback_formats = "Video API blocked by the instance — standard streams probed instead",
    msg_trying_html = "JSON API closed — trying the HTML pages...",
    msg_html_mode = "Connected in HTML mode (API closed on this instance)",
    dash_auto = "Automatic quality (DASH)",
    msg_no_formats = "No playable stream found for this video",
    msg_playing = "Playback started",
    msg_copied = "Stream URL copied to the clipboard",
    msg_copy_fallback = "Auto-copy unavailable — select the URL below",

    btn_download = "Download",
    btn_download_audio = "Download the sound only",
    msg_dl_busy = "A download is already running — wait for it, or cancel it",
    msg_no_audio_stream = "This video offers no separate sound stream",
    btn_dl_cancel = "Cancel the download",
    msg_loading_thumb = "Fetching the thumbnail...",
    dl_preparing = "Preparing the download...",
    dl_progress = "%s %d %% — file %d/%d — %s / %s",
    dl_done = "Download finished: %s — in %s",
    dl_done_pair = "Download finished: %s (picture) and %s (sound) — in %s. This quality has no combined stream: the two files go together.",
    dl_error = "Download failed: ",
    dl_cancelled = "Download cancelled",
    msg_dl_playlist = "This entry is a stream list, not a file: pick a quality with a resolution to download it",
    msg_dl_unsupported = "This build cannot download: it has no extension timer",
    msg_dl_no_dir = "The Downloads folder could not be found",
    btn_combine = "Combine the two files",
    msg_combine_gone = "The two files are no longer where they were downloaded",
    msg_combine_running = "Combining… %d %%",
    msg_combine_ok = "Combining finished: %s",
    msg_combine_failed = "Combining failed — nothing was written",
    msg_combine_unsupported = "This build cannot combine the two files",

    title_challenge = "Invidious — Anti-bot check",
    lbl_challenge_1 = "This instance protects itself with a check that has "
                   .. "to run JavaScript. PowerVLC does not solve it: your "
                   .. "browser does, and hands the result back.",
    lbl_challenge_2 = "1. Open this address in your browser (PowerFox, "
                   .. "Firefox, Safari...), then follow the three steps "
                   .. "on the page:",
    lbl_region = "Results for:",
    btn_challenge_copy = "Copy the address",
    btn_challenge_open = "Open in the browser",
    lbl_challenge_3 = "2. PowerVLC carries on by itself as soon as the "
                   .. "browser is done. This button is only there if you "
                   .. "would rather not wait:",
    btn_challenge_done = "I have solved the check",
    btn_challenge_cancel = "< Back",
    msg_challenge_copied = "Address copied — paste it in your browser",
    msg_challenge_opened = "Opened in your browser — carry on there",
    msg_challenge_no_browser = "PowerVLC could not open a browser: copy the "
                            .. "address instead.",
    msg_challenge_waiting = "Nothing received yet — finish the steps in the "
                         .. "browser, then press the button again",
    msg_challenge_ok = "Session received — retrying",
    msg_challenge_fail = "Could not open the local handover page: ",
    msg_challenge_needed = "This instance asks for an anti-bot check",
    msg_challenge_incomplete = "The check is not finished: the page must "
                            .. "really be showing before you click the "
                            .. "bookmark. Finish it, then click again.",
    msg_challenge_click = "Your browser tab is opening this video. Once it "
                       .. "is showing, click the bookmark -- nothing else "
                       .. "to do.",
    msg_challenge_no_session = "This instance grants its browser a pass for "
                            .. "one page at a time and keeps nothing "
                            .. "reusable, so there is nothing PowerVLC can "
                            .. "be handed. Try another instance.",

    -- served to the browser
    web_title = "PowerVLC — anti-bot check",
    web_intro = "The check on this instance is solved by your browser, "
             .. "exactly as if you were visiting the site yourself. "
             .. "PowerVLC then reads the page through that tab; it never "
             .. "solves anything on its own.",
    web_step1 = "Drag this link onto your bookmarks bar (once and for all):",
    web_bookmark = "Send to PowerVLC",
    web_step2 = "Open the instance and solve the check it shows:",
    web_step3 = "Once the page is <strong>really showing</strong> -- some "
             .. "instances ask for two checks in a row -- click the "
             .. "<em>Send to PowerVLC</em> bookmark you just added.",
    web_note = "Leave this window and the instance tab open while you "
            .. "browse: PowerVLC reads each page through them. Closing "
            .. "either one cuts the link, and the bookmark has to be "
            .. "clicked again.",
    web_done_title = "Done",
    web_done = "PowerVLC has what it needs. Leave this window and the "
            .. "instance tab open, and go back to the player.",
    web_empty = "Nothing usable came through. Make sure the page is "
             .. "really showing -- some instances ask for two checks in a "
             .. "row -- then click the bookmark again.",
    web_relay_on = "Connected to PowerVLC. Leave this window and the "
                .. "instance tab open while you browse.",
    web_relay_off = "Waiting for the instance tab...",
    web_relay_busy = "The instance tab is still working through its check "
                  .. "-- PowerVLC is waiting rather than asking it for "
                  .. "anything.",
    web_m_drag = "This is a bookmark, not a link: drag it onto your "
              .. "bookmarks bar, then open the instance and click it THERE, "
              .. "once the check has been passed.",
    web_m_ok = "PowerVLC is connected. Leave this tab open while you browse.",
    web_m_popup = "PowerVLC could not open its window: allow pop-ups for "
               .. "this site, then click the bookmark again.",
    web_m_wait = "PowerVLC: connecting...",
    web_m_fail = "PowerVLC is not answering. Check that its page "
              .. "(127.0.0.1) is still open, then click the bookmark again.",
    web_m_page = "This page has been handed to PowerVLC.",
    web_m_nav = "Opening the video PowerVLC asked for -- click the bookmark "
             .. "again once it is showing.",
    web_m_taken = "PowerVLC has this page. The tab was emptied on purpose: "
               .. "playing the video here as well would cost the machine a "
               .. "second decode and a second download. Leave it open.",
    -- Until Firefox 69 a bookmarklet counted as inline script, so a page
    -- carrying a security policy -- every instance does -- refused to run
    -- it, silently. Every browser these machines can run is older than
    -- that, which makes the add-on the normal way in, not a fallback.
    web_addon_title = "Older browsers: install the PowerVLC add-on",
    web_addon = "TenFourFox, PowerFox and every browser before Firefox 69 "
             .. "refuse to run a bookmark's script on a page that carries "
             .. "a security policy, and every instance carries one: there, "
             .. "clicking the bookmark does nothing at all. In the player, "
             .. "<strong>Help &gt; Install the PowerVLC add-on</strong> "
             .. "puts a small add-on in your browser that does the same "
             .. "thing by itself -- no bookmark, no clicking, on every "
             .. "page.",
    web_addon_lead = "Add-on installed? There is nothing to drag and "
                  .. "nothing to click: just open the instance below and "
                  .. "pass its check. This page will tell you when the "
                  .. "link is up.",
    web_steps_title = "Without the add-on: the bookmark",
    web_relay_on_addon = "Connected to PowerVLC through the browser "
                      .. "add-on. Nothing to click: leave this window and "
                      .. "the instance tab open.",
    web_m_taking = "PowerVLC is playing this video. This tab was emptied "
                .. "straight away on purpose: letting the site's player "
                .. "finish loading here would cost a second decode and a "
                .. "second download, and pull on the instance for nothing. "
                .. "Leave it open.",
}
