-- PowerVLSub: OpenSubtitles.com search and download for PowerVLC.
-- Copyright (C) 2026 the PowerVLC team. GPL-2.0-or-later.
-- Replaces the legacy OpenSubtitles.org XML-RPC client.
local service, json, lang, client, picker
local dlg, ui = nil, {}
local settings = {
    languages = "en", directory = "", username = "", remember = false,
    download_mode = "save_load", use_guessit = false,
    hide_ai = false, hide_machine = true, sort_mode = "best",
}
local password, key_override = "", ""
local source, rows, visible_rows, search_params, pagination = nil, {}, {}, nil, nil
local config_path, cache_dir, language_cache_path, guess_cache_path
local view, key_advanced, search_advanced = "search", false, false
local downloaded, bodies, pending_save_as = {}, {}, nil
local catalog, catalog_fresh, catalog_checked = {}, false, false
local language_choices, guess_cache = {}, {}
local search_form = { query = "", method = 1, year = "", season = "", episode = "", imdb = "" }
local KEYSTORE = "https://api.opensubtitles.com/powervlc"
local LANGUAGE_CACHE_SECONDS = 30 * 24 * 60 * 60
local GUESS_CACHE_SECONDS = 7 * 24 * 60 * 60

function descriptor()
    return { title = "PowerVLSub — OpenSubtitles.com", version = "1.0",
        author = "PowerVLC", shortdesc = "PowerVLSub",
        url = "https://www.opensubtitles.com/",
        description = "Find, download and activate subtitles for the current video.",
        capabilities = { "menu", "input-listener" } }
end

local function message(text)
    if ui.message then ui.message:set_text(text or ""); dlg:update() end
end

local function failure(err, detail)
    local text = lang[err or "network"] or lang.network
    if type(detail) == "table" and type(detail.remaining) == "number" then
        text = text .. " " .. string.format(lang.remaining, detail.remaining)
    end
    message(text)
end

local function reset_dialog(title)
    if dlg then dlg:delete() end
    dlg, ui = vlc.dialog(title), {}
end

local function read_json(path, limit)
    local file = vlc.io.open(path, "rb")
    if not file then return nil end
    local value = json.decode(file:read(limit or 262144) or "")
    file:close()
    return type(value) == "table" and value or nil
end

local function write_json(path, value)
    local file = vlc.io.open(path, "wb")
    local ok = file and file:write(json.encode(value))
    if file then ok = file:close() and ok end
    return ok == true
end

local function read_settings()
    local locale = vlc.config.language():lower():gsub("_", "-")
    settings.languages = locale:match("^%a%a") or "en"
    if locale:match("^pt%-br") then settings.languages = "pt-br"
    elseif locale:match("^pt") then settings.languages = "pt-pt" end
    if locale:match("^zh%-tw") or locale:match("^zh%-hk") then settings.languages = "zh-tw"
    elseif locale:match("^zh") then settings.languages = "zh-cn" end
    local obj = read_json(config_path, 65536)
    if obj then
        if service.languages(obj.languages) then settings.languages = obj.languages end
        if type(obj.directory) == "string" then settings.directory = obj.directory end
        if type(obj.username) == "string" then settings.username = obj.username end
        settings.remember = obj.remember == true
        settings.download_mode = obj.download_mode == "temporary" and "temporary" or "save_load"
        settings.use_guessit = obj.use_guessit == true
        settings.hide_ai = obj.hide_ai == true
        settings.hide_machine = obj.hide_machine ~= false
        if obj.sort_mode == "downloads" or obj.sort_mode == "rating" then
            settings.sort_mode = obj.sort_mode
        end
    end
    if vlc.keystore then
        key_override = vlc.keystore.find(KEYSTORE, "api-key") or ""
        if settings.remember and settings.username ~= "" then
            password = vlc.keystore.find(KEYSTORE, "user:" .. settings.username) or ""
        end
    end
end

local function new_client()
    client = service.new(key_override ~= "" and key_override or service.application_key,
        vlc.misc.product_version and vlc.misc.product_version() or "3.0")
end

local function current_media()
    local item = vlc.input.item()
    if not item then return nil end
    local uri = item:uri()
    local path = uri:match("^file://") and vlc.strings.make_path(uri) or nil
    local name = path and path:match("[^/\\]+$") or item:name()
    name = service.searchable_name(name)
    if not path and name == "" then
        local meta = item:metas() or {}
        name = service.searchable_name(meta.title)
    end
    return { uri = uri, path = path, name = name or "", id = vlc.playlist.current() }
end

local function still_current(expected)
    return source and vlc.playlist.current() == (expected or source.id)
end

local function preferred_languages()
    return service.languages(settings.languages) or {"en"}
end

local function language_params()
    local list = preferred_languages()
    table.sort(list)
    return table.concat(list, ",")
end

local function clean_number(value, minimum, maximum)
    value = service.trim(value)
    if value == "" then return nil end
    if not value:match("^%d+$") then return false end
    local number = tonumber(value)
    if not number or number < minimum or number > maximum then return false end
    return number
end

local function capture_search_form()
    if not ui.query then return end
    search_form.query = ui.query:get_text()
    search_form.method = ui.method:get_value()
    if ui.year then search_form.year = ui.year:get_text() end
    if ui.season then search_form.season = ui.season:get_text() end
    if ui.episode then search_form.episode = ui.episode:get_text() end
    if ui.imdb then search_form.imdb = ui.imdb:get_text() end
    if ui.sort then
        local value = ui.sort:get_value()
        settings.sort_mode = value == 2 and "downloads" or value == 3 and "rating" or "best"
    end
    if ui.hide_ai then settings.hide_ai = ui.hide_ai:get_checked() end
    if ui.hide_machine then settings.hide_machine = ui.hide_machine:get_checked() end
end

local function result_details(row)
    if not row then return lang.select_for_details end
    local details = {}
    if row.rating > 0 then details[#details + 1] = string.format(lang.rating, row.rating) end
    if row.votes > 0 then details[#details + 1] = string.format(lang.votes, row.votes) end
    if row.downloads > 0 then details[#details + 1] = string.format(lang.downloads, row.downloads) end
    if row.fps and row.fps > 0 then details[#details + 1] = string.format(lang.fps, row.fps) end
    if row.uploader ~= "" then details[#details + 1] = string.format(lang.uploader, row.uploader) end
    if row.upload_date ~= "" then details[#details + 1] = string.format(lang.uploaded, row.upload_date) end
    return #details > 0 and table.concat(details, " | ") or lang.no_details
end

function select_result()
    local index = ui.results and next(ui.results:get_selection())
    if ui.details then ui.details:set_text(result_details(index and visible_rows[index])) end
    if dlg then dlg:update() end
end

local function display_results()
    if not ui.results then return end
    ui.results:clear()
    visible_rows = {}
    for _, row in ipairs(rows) do
        if not (settings.hide_ai and row.ai_translated)
           and not (settings.hide_machine and row.machine_translated) then
            visible_rows[#visible_rows + 1] = row
        end
    end
    service.sort(visible_rows, preferred_languages(), settings.sort_mode)
    for i, row in ipairs(visible_rows) do
        local flags = {}
        if row.hash_match then flags[#flags + 1] = lang.hash_match end
        if row.trusted then flags[#flags + 1] = lang.trusted end
        if row.hd then flags[#flags + 1] = lang.hd end
        if row.ai_translated then flags[#flags + 1] = lang.ai_translated end
        if row.machine_translated then flags[#flags + 1] = lang.machine_translated end
        if row.hearing_impaired then flags[#flags + 1] = lang.hearing_impaired end
        if row.foreign_only then flags[#flags + 1] = lang.foreign_only end
        local title = row.language .. " | " .. row.release:gsub("[%c]", " ")
        if row.rating > 0 then title = title .. string.format(" | %.1f/10", row.rating) end
        if #flags > 0 then title = title .. " | " .. table.concat(flags, ", ") end
        ui.results:add_value(title, i)
    end
    if ui.details then ui.details:set_text(lang.select_for_details) end
    if #visible_rows == 0 and #rows > 0 then
        message(lang.no_results_after_filters)
    else
        message(#visible_rows == 0 and lang.no_results
            or string.format(lang.found, #visible_rows))
    end
end

function apply_result_options()
    capture_search_form()
    display_results()
end

local function initial_search_form(media)
    local form = { query = media and media.name or "", method = 1,
                   year = "", season = "", episode = "", imdb = "" }
    if media and media.name ~= "" then
        local info = service.identify(media.name)
        form.year = info.year and tostring(info.year) or ""
        form.season = info.season_number and tostring(info.season_number) or ""
        form.episode = info.episode_number and tostring(info.episode_number) or ""
    end
    return form
end

function show_search(preserve)
    if preserve then capture_search_form() end
    view = "search"
    local current = current_media()
    if not preserve or not source or not current or source.id ~= current.id then
        source, rows, visible_rows, search_params, pagination = current, {}, {}, nil, nil
        search_form = initial_search_form(source)
    end
    reset_dialog(lang.title)
    ui.query = dlg:add_text_input(search_form.query, 1, 1, 3, 1, search)
    ui.method = dlg:add_dropdown(4, 1, 1, 1)
    ui.method:add_value(lang.automatic, 1)
    ui.method:add_value(lang.by_name, 2)
    ui.method:add_value(lang.by_hash, 3)
    ui.method:set_value(search_form.method)
    dlg:add_button(lang.search, search, 5, 1, 1, 1)

    dlg:add_label(string.format(lang.languages_label, settings.languages), 1, 2, 2, 1)
    ui.sort = dlg:add_dropdown(3, 2, 1, 1)
    ui.sort:add_value(lang.sort_best, 1)
    ui.sort:add_value(lang.sort_downloads, 2)
    ui.sort:add_value(lang.sort_rating, 3)
    ui.sort:set_value(settings.sort_mode == "downloads" and 2
                      or settings.sort_mode == "rating" and 3 or 1)
    dlg:add_button(search_advanced and lang.simple_search or lang.advanced_search,
                   toggle_advanced_search, 4, 2, 1, 1)
    dlg:add_button(lang.settings_button, show_settings, 5, 2, 1, 1)

    local row = 3
    if search_advanced then
        dlg:add_label(lang.year, 1, row, 1, 1)
        ui.year = dlg:add_text_input(search_form.year, 2, row, 1, 1)
        dlg:add_label(lang.season, 3, row, 1, 1)
        ui.season = dlg:add_text_input(search_form.season, 4, row, 1, 1)
        dlg:add_label(lang.episode, 5, row, 1, 1)
        ui.episode = dlg:add_text_input(search_form.episode, 6, row, 1, 1)
        row = row + 1
        dlg:add_label(lang.imdb, 1, row, 1, 1)
        ui.imdb = dlg:add_text_input(search_form.imdb, 2, row, 2, 1, search)
        dlg:add_label(lang.imdb_help, 4, row, 3, 1)
        row = row + 1
    end
    ui.hide_ai = dlg:add_check_box(lang.hide_ai, settings.hide_ai, 1, row, 2, 1)
    ui.hide_machine = dlg:add_check_box(lang.hide_machine, settings.hide_machine, 3, row, 2, 1)
    dlg:add_button(lang.apply_filters, apply_result_options, 5, row, 1, 1)
    row = row + 1
    ui.results = dlg:add_list(1, row, 6, 5, download, select_result)
    row = row + 5
    ui.details = dlg:add_label(lang.select_for_details, 1, row, 6, 1)
    row = row + 1
    ui.message = dlg:add_label(source and lang.ready or lang.no_video, 1, row, 6, 2)
    row = row + 2
    dlg:add_button(lang.more, more_results, 1, row, 1, 1)
    dlg:add_button(settings.download_mode == "temporary" and lang.load_temporary or lang.download,
                   download, 2, row, 2, 1)
    dlg:add_button(lang.save_as, save_as, 4, row, 1, 1)
    dlg:add_button(lang.close, close, 5, row, 1, 1)
    dlg:show()
    if preserve and #rows > 0 then display_results() end
end

function toggle_advanced_search()
    search_advanced = not search_advanced
    show_search(true)
end

local function add_result_filters(params)
    if settings.hide_ai then params.ai_translated = "exclude" end
    if settings.hide_machine then params.machine_translated = "exclude" end
    return params
end

local function guessed_metadata(name)
    local now = os.time()
    local cached = guess_cache[name]
    if type(cached) == "table" and tonumber(cached.timestamp)
       and now - tonumber(cached.timestamp) < GUESS_CACHE_SECONDS
       and type(cached.data) == "table" then
        return cached.data
    end
    local guessed = client:guess(name)
    if guessed then
        guess_cache[name] = { timestamp = now, data = guessed }
        write_json(guess_cache_path, guess_cache)
    end
    return guessed
end

function search()
    capture_search_form()
    local query = service.trim(search_form.query)
    local method = search_form.method
    source, rows, visible_rows, pagination = current_media(), {}, {}, nil
    ui.results:clear()
    if not source then message(lang.no_video); return end
    local imdb = search_advanced and service.trim(search_form.imdb) or ""
    if query == "" and method ~= 3 and imdb == "" then message(lang.enter_query); return end
    local year = search_advanced and clean_number(search_form.year, 1900, 2099) or nil
    local season = search_advanced and clean_number(search_form.season, 0, 999) or nil
    local episode = search_advanced and clean_number(search_form.episode, 0, 9999) or nil
    if year == false or season == false or episode == false then message(lang.bad_numbers); return end
    local imdb_id
    if search_advanced and imdb ~= "" then
        imdb_id = service.imdb_id(imdb)
        if not imdb_id then message(lang.bad_imdb); return end
    end
    message(lang.searching)
    local params = { languages = language_params() }
    if imdb_id then
        params.imdb_id, params.season_number, params.episode_number = imdb_id, season, episode
    elseif method == 3 or (method == 1 and query == source.name) then
        params.moviehash = service.hash(source.uri)
        if method == 3 and not params.moviehash then message(lang.no_hash); return end
    end
    if params.moviehash then
        params.moviehash_match = "only"
    elseif not imdb_id then
        local info = service.identify(query)
        params.query = info.query
        params.year = year or info.year
        params.season_number = season or info.season_number
        params.episode_number = episode or info.episode_number
    end
    add_result_filters(params)
    local result, err, page = client:search(params)
    if result and #result == 0 and params.moviehash and method == 1 then
        params = service.identify(query)
        params.languages = language_params()
        params.year = year or params.year
        params.season_number = season or params.season_number
        params.episode_number = episode or params.episode_number
        add_result_filters(params)
        result, err, page = client:search(params)
    end
    if result and #result == 0 and settings.use_guessit and method == 1
       and query == source.name and not imdb_id then
        message(lang.guessit_searching)
        local guessed = guessed_metadata(source.name)
        if guessed then
            params = { languages = language_params(), query = guessed.query,
                       year = year or guessed.year,
                       season_number = season or guessed.season_number,
                       episode_number = episode or guessed.episode_number }
            add_result_filters(params)
            result, err, page = client:search(params)
        end
    end
    if not still_current() then message(lang.media_changed); return end
    if not result then failure(err, page); return end
    rows, search_params, pagination = result, params, page
    write_json(config_path, settings)
    display_results()
end

function more_results()
    if not pagination or pagination.page >= pagination.pages then message(lang.no_more); return end
    if not still_current() then message(lang.media_changed); return end
    message(lang.searching)
    search_params.page = pagination.page + 1
    local result, err, page = client:search(search_params)
    if not still_current() then message(lang.media_changed); return end
    if not result then failure(err, page); return end
    local seen = {}
    for _, row in ipairs(rows) do seen[row.id] = true end
    for _, row in ipairs(result) do
        if not seen[row.id] then rows[#rows + 1] = row; seen[row.id] = true end
    end
    pagination = page
    display_results()
end

local function selected_row()
    local index = ui.results and next(ui.results:get_selection())
    return index and visible_rows[index] or nil
end

local function readable_file(path)
    if not path then return false end
    local file = vlc.io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

local function perform_download(row, directory_override, activate_subtitle, temporary)
    if not row then message(lang.choose_result); return end
    if not still_current() then message(lang.media_changed); return end
    local base_key = source.uri .. "\n" .. row.id
    local storage = temporary and "temporary"
                    or (directory_override and directory_override ~= "" and directory_override
                        or settings.directory ~= "" and settings.directory or "sidecar")
    local path_key = base_key .. "\n" .. storage
    local path = downloaded[path_key]
    if not readable_file(path) then path = nil end
    local quota, body
    if not path then
        body = bodies[base_key]
        if not body then
            message(lang.downloading)
            local err, detail
            body, err, detail = client:download(row.id, settings.username, password)
            if not still_current() then message(lang.media_changed); return end
            if not body then failure(err, detail); return end
            quota = detail.remaining
            bodies[base_key] = body
        end
        local directories = {}
        if directory_override and directory_override ~= "" then
            directories[#directories + 1] = directory_override
        elseif temporary then
            directories[#directories + 1] = cache_dir
        elseif settings.directory ~= "" then
            directories[#directories + 1] = settings.directory
        elseif source.path then
            directories[#directories + 1] = source.path:match("^(.*)[/\\][^/\\]+$")
        end
        if not directory_override and not temporary then directories[#directories + 1] = cache_dir end
        local stem = source.name:gsub("%.[%w]+$", "")
        local save_err
        path, save_err = service.save(body, directories, stem, row)
        if not path then failure(save_err); return end
        downloaded[path_key] = path
    end
    if not still_current() then message(lang.media_changed); return end
    local text
    if activate_subtitle then
        local ok = vlc.input.add_subtitle(path, true, source.id)
        if not ok then message(lang.load_failed .. " " .. path); return end
        text = (temporary and lang.loaded_temporary or lang.loaded) .. " " .. path
    else
        text = lang.saved .. " " .. path
    end
    if type(quota) == "number" then text = text .. "\n" .. string.format(lang.remaining, quota) end
    message(text)
end

function download()
    perform_download(selected_row(), nil, true, settings.download_mode == "temporary")
end

function save_as()
    local row = selected_row()
    if not row then message(lang.choose_result); return end
    if picker:busy() then return end
    pending_save_as = { row = row, source_id = source.id }
    local current = settings.directory
    if current == "" and source.path then current = source.path:match("^(.*)[/\\][^/\\]+$") or "" end
    local started = picker:open(lang.save_as_prompt, current)
    if started then vlc.timer(100, "poll_picker")
    else pending_save_as = nil end
end

local function selected_language_codes()
    local selected, seen = {}, {}
    for i = 1, 3 do
        local widget, choices = ui["language" .. i], language_choices[i]
        local value = widget and widget:get_value()
        local code = choices and choices[value]
        if code and code ~= "" and not seen[code] then
            selected[#selected + 1], seen[code] = code, true
        end
    end
    return selected
end

local function populate_language_widget(widget, slot, selected, optional)
    widget:clear()
    language_choices[slot] = {}
    local index = 0
    if optional then
        index = 1
        widget:add_value(lang.none, index)
        language_choices[slot][index] = ""
    end
    local selected_index
    for _, entry in ipairs(catalog) do
        index = index + 1
        widget:add_value(entry.name .. " [" .. entry.code .. "]", index)
        language_choices[slot][index] = entry.code
        if entry.code == selected then selected_index = index end
    end
    if selected ~= "" and not selected_index then
        index = index + 1
        widget:add_value(selected .. " [" .. selected .. "]", index)
        language_choices[slot][index] = selected
        selected_index = index
    end
    widget:set_value(selected_index or (optional and 1 or 1))
end

local function populate_language_widgets(codes)
    codes = codes or preferred_languages()
    for i = 1, 3 do
        populate_language_widget(ui["language" .. i], i, codes[i] or "", i > 1)
    end
    if dlg then dlg:update() end
end

local function refresh_language_catalog()
    if catalog_checked or catalog_fresh then return end
    catalog_checked = true
    local codes = selected_language_codes()
    message(lang.loading_languages)
    local remote = client:language_catalog()
    if remote and #remote > 0 then
        catalog = remote
        write_json(language_cache_path, { timestamp = os.time(), data = remote })
        populate_language_widgets(codes)
        message(lang.languages_updated)
    else
        message(lang.languages_fallback)
    end
end

function show_settings()
    view = "settings"
    reset_dialog(lang.settings)
    local codes = preferred_languages()
    for i = 1, 3 do
        dlg:add_label(string.format(lang.language_number, i), 1, i, 1, 1)
        ui["language" .. i] = dlg:add_dropdown(2, i, 3, 1)
    end
    populate_language_widgets(codes)
    dlg:add_label(lang.download_behavior, 1, 4, 1, 1)
    ui.download_mode = dlg:add_dropdown(2, 4, 3, 1)
    ui.download_mode:add_value(lang.save_and_load, 1)
    ui.download_mode:add_value(lang.temporary, 2)
    ui.download_mode:set_value(settings.download_mode == "temporary" and 2 or 1)
    ui.use_guessit = dlg:add_check_box(lang.use_guessit, settings.use_guessit, 1, 5, 5, 1)
    dlg:add_label(lang.guessit_help, 1, 6, 5, 1)
    ui.hide_ai = dlg:add_check_box(lang.hide_ai_default, settings.hide_ai, 1, 7, 2, 1)
    ui.hide_machine = dlg:add_check_box(lang.hide_machine_default, settings.hide_machine, 3, 7, 3, 1)
    dlg:add_label(lang.directory, 1, 8, 1, 1)
    ui.directory = dlg:add_text_input(settings.directory, 2, 8, 3, 1)
    dlg:add_button(lang.browse, choose_directory, 5, 8, 1, 1)
    dlg:add_label(lang.username, 1, 9, 1, 1)
    ui.username = dlg:add_text_input(settings.username, 2, 9, 2, 1)
    dlg:add_label(lang.password, 4, 9, 1, 1)
    ui.password = dlg:add_password(password, 5, 9, 2, 1)
    ui.remember = dlg:add_check_box(lang.remember, settings.remember, 1, 10, 3, 1)
    dlg:add_button(lang.test_account, test_account, 4, 10, 2, 1)
    if key_advanced or service.application_key == "" or key_override ~= "" then
        dlg:add_label(lang.api_key, 1, 11, 1, 1)
        ui.api_key = dlg:add_password(key_override, 2, 11, 3, 1)
    else
        ui.personal_key = dlg:add_button(lang.personal_key, show_key_advanced, 1, 11, 4, 1)
    end
    ui.message = dlg:add_label(lang.account_help, 1, 12, 6, 2)
    dlg:add_button(lang.save, save_settings, 1, 14, 2, 1)
    dlg:add_button(lang.back, back_to_search, 3, 14, 2, 1)
    dlg:show()
    refresh_language_catalog()
end

local function capture_settings()
    local codes = selected_language_codes()
    settings.languages = table.concat(codes, ",")
    settings.username = service.trim(ui.username:get_text())
    settings.directory = service.trim(ui.directory:get_text())
    settings.remember = ui.remember:get_checked()
    settings.download_mode = ui.download_mode:get_value() == 2 and "temporary" or "save_load"
    settings.use_guessit = ui.use_guessit:get_checked()
    settings.hide_ai = ui.hide_ai:get_checked()
    settings.hide_machine = ui.hide_machine:get_checked()
    password = ui.password:get_text()
    if ui.api_key then key_override = service.trim(ui.api_key:get_text()) end
end

function show_key_advanced()
    key_advanced = true
    if ui.personal_key then dlg:del_widget(ui.personal_key); ui.personal_key = nil end
    dlg:add_label(lang.api_key, 1, 11, 1, 1)
    ui.api_key = dlg:add_password(key_override, 2, 11, 3, 1)
    dlg:update()
end

function test_account()
    local user = service.trim(ui.username:get_text())
    local pass = ui.password:get_text()
    if user == "" or pass == "" then message(lang.missing_credentials); return end
    local key = ui.api_key and service.trim(ui.api_key:get_text()) or key_override
    if key == "" then key = service.application_key end
    message(lang.testing_account)
    local probe = service.new(key, vlc.misc.product_version and vlc.misc.product_version() or "3.0")
    local account, err, detail = probe:account(user, pass)
    if not account then failure(err, detail); return end
    local quota = account.remaining and string.format(lang.account_remaining, account.remaining)
               or account.allowed and account.used
                  and string.format(lang.account_usage, account.used, account.allowed) or lang.account_quota_unknown
    local level = account.level ~= "" and account.level or lang.account_level_unknown
    local reset = account.reset_time ~= "" and string.format(lang.account_reset, account.reset_time) or ""
    message(string.format(lang.account_ok, account.username, level, quota) .. reset)
end

function save_settings()
    local codes = selected_language_codes()
    if #codes == 0 then message(lang.bad_languages); return end
    if ui.api_key and service.trim(ui.api_key:get_text()):find("[%c]") then message(lang.bad_key); return end
    local previous_user = settings.username
    capture_settings()
    local remembered, key_saved = false, key_override == ""
    if vlc.keystore then
        if previous_user ~= "" and (previous_user ~= settings.username or not settings.remember or password == "") then
            vlc.keystore.remove(KEYSTORE, "user:" .. previous_user)
        end
        if settings.remember and settings.username ~= "" and password ~= "" then
            remembered = vlc.keystore.store(KEYSTORE, "user:" .. settings.username,
                                           password, "PowerVLC OpenSubtitles") == true
        end
        if key_override ~= "" then
            key_saved = vlc.keystore.store(KEYSTORE, "api-key", key_override, "PowerVLC OpenSubtitles API") == true
        else
            vlc.keystore.remove(KEYSTORE, "api-key")
        end
    end
    local ok = write_json(config_path, settings)
    new_client()
    if not ok then message(lang.settings_failed); return end
    if not key_saved or (settings.remember and password ~= "" and not remembered) then
        message(lang.session_only); return
    end
    show_search()
    if source then search() end
end

function choose_directory()
    if picker:busy() then return end
    local started = picker:open(lang.directory, ui.directory:get_text())
    if started then vlc.timer(100, "poll_picker") end
end

function poll_picker()
    if picker and picker:poll() then vlc.timer(100, "poll_picker") end
end

function back_to_search()
    show_search()
end

function activate()
    service, json = require("pvlc_opensubtitles"), require("dkjson")
    lang = require("pvlc_i18n").load("opensubtitles")
    local directory = vlc.config.userdatadir()
    vlc.io.mkdir(directory, "0700")
    config_path = directory .. "/opensubtitles.json"
    language_cache_path = directory .. "/opensubtitles-languages.json"
    guess_cache_path = directory .. "/opensubtitles-guessit.json"
    local cache = vlc.config.cachedir()
    vlc.io.mkdir(cache, "0700")
    cache_dir = cache .. "/subtitles"
    vlc.io.mkdir(cache_dir, "0700")
    read_settings()
    new_client()
    local language_cache = read_json(language_cache_path)
    catalog = service.language_catalog(language_cache and language_cache.data)
    catalog_fresh = language_cache and tonumber(language_cache.timestamp)
                    and os.time() - tonumber(language_cache.timestamp) < LANGUAGE_CACHE_SECONDS or false
    guess_cache = read_json(guess_cache_path) or {}
    picker = require("pvlc_folder_picker").new("opensubtitles", {
        done = function(path, reason)
            if pending_save_as then
                local pending = pending_save_as
                pending_save_as = nil
                if path and path ~= "" and still_current(pending.source_id) then
                    perform_download(pending.row, path, false, false)
                elseif reason ~= "cancelled" then message(lang.folder_failed) end
            elseif view == "settings" then
                if path and path ~= "" then ui.directory:set_text(path)
                elseif reason ~= "cancelled" then message(lang.folder_failed) end
            end
        end })
    show_search()
    if client.key == "" then show_settings(); message(lang.missing_key)
    elseif source then vlc.timer(1, "search") end
end

function menu()
    return { lang.title, lang.settings }
end

function trigger_menu(id)
    if id == 2 then show_settings()
    elseif view == "search" and still_current() then dlg:show()
    else show_search(); if source then search() end end
end

function input_changed()
    local current = current_media()
    if source and current and source.id == current.id and source.uri == current.uri then return end
    if view == "search" then show_search() end
end

function close()
    vlc.deactivate()
end

function deactivate()
    if picker then picker:close() end
    vlc.timer(0)
    if dlg then dlg:delete(); dlg = nil end
    password, key_override, client = "", "", nil
    bodies, downloaded, pending_save_as = {}, {}, nil
end
