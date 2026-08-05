--[[ en.lua: the en catalogue of the podcasts extension.
     Loaded on its own by share/lua/modules/pvlc_i18n.lua: only
     the language in use is ever parsed or kept in memory. ]]

return {

    title_subs = "Subscriptions",
    ext_description = "Search the Apple podcast directory, read what a "
                   .. "show is about and subscribe to it without leaving "
                   .. "PowerVLC.",

    lbl_term = "Search:",
    btn_search = "Search",
    lbl_kind = "Look for:",
    kind_podcasts = "Podcasts",
    kind_episodes = "Episodes",
    lbl_store = "Store:",
    lbl_limit = "Results:",
    lbl_genre = "Genre:",
    all_genres = "All genres",
    lbl_filter = "Filter:",
    chk_explicit = "Hide explicit content",

    col_rank = "#",
    col_name = "Name",
    col_author = "Author",
    col_genre = "Genre",
    col_episodes = "Episodes",
    col_latest = "Latest",
    col_episode = "Episode",
    col_podcast = "Podcast",
    col_date = "Date",
    col_duration = "Length",
    col_feed = "Feed",

    btn_details = "More information",
    btn_play = "Play",
    btn_subscribe = "Subscribe",
    btn_unsubscribe = "Unsubscribe",
    btn_subs = "My subscriptions",
    btn_back_search = "< Search",
    btn_copy_feed = "Copy the feed",
    btn_play_podcast = "Play the podcast",
    btn_play_episode = "Play the episode",
    btn_enqueue_episode = "Add to the playlist",

    lbl_feed = "Feed:",
    lbl_episodes = "Latest episodes",
    lbl_by = "By %s",
    lbl_explicit = "explicit content",
    lbl_count = "%d episodes",
    lbl_count_one = "%d episode",
    msg_count_one = "%d / %d result — double-click it to open it",
    msg_subs_count_one = "%d subscription",
    lbl_latest = "latest episode %s",
    lbl_store_of = "%s store",
    no_description = "This feed carries no description.",

    msg_hint = "Type what you are looking for, then press Search.",
    msg_searching = "Searching...",
    msg_count = "%d / %d results — double-click one to open it",
    msg_no_result = "Nothing found",
    msg_net_fail = "The directory could not be reached",
    msg_bad_answer = "The directory answered something unreadable",
    msg_enter_term = "Type something to search for first",
    msg_select_first = "Select an entry in the list first",
    msg_loading = "Loading the podcast...",
    msg_loading_feed = "Reading the feed...",
    msg_finding_feed = "The directory hides this feed: looking it up on "
                    .. "the show's page...",
    msg_no_feed = "This entry carries no feed address",
    msg_feed_hidden = "Neither the directory nor the show's page gives "
                   .. "out this feed: it cannot be subscribed to from "
                   .. "here. Podcasts hosted by Apple are never given "
                   .. "out at all.",
    msg_no_episodes = "The directory lists no episode for this podcast",
    msg_subscribed = "Subscribed — the show is in Podcasts, in the sidebar",
    msg_already = "Already subscribed",
    msg_unsubscribed = "Unsubscribed",
    msg_sub_failed = "The subscription could not be written",
    msg_no_subs = "No subscription yet",
    msg_subs_count = "%d subscriptions",
    msg_copied = "Feed address copied",
    msg_copy_failed = "Copying is not available here: the address stays "
                   .. "selectable in the field",
    msg_playing = "Playing",
    msg_queued = "Added to the playlist",

    countries = {
      AR = "Argentina", AU = "Australia", AT = "Austria", BE = "Belgium",
      BR = "Brazil", CA = "Canada", CL = "Chile", CN = "China",
      CZ = "Czechia", DK = "Denmark", FI = "Finland", FR = "France",
      DE = "Germany", GR = "Greece", HU = "Hungary", IN = "India",
      IE = "Ireland", IL = "Israel", IT = "Italy", JP = "Japan",
      KR = "South Korea", MX = "Mexico", NL = "Netherlands",
      NZ = "New Zealand", NO = "Norway", PL = "Poland", PT = "Portugal",
      RO = "Romania", RU = "Russia", ZA = "South Africa", ES = "Spain",
      SE = "Sweden", CH = "Switzerland", TR = "Türkiye", UA = "Ukraine",
      GB = "United Kingdom", US = "United States",
    },
}
