--[[
    PowerVLC CRT Display Controller

    Derived from the CRT Scanline Controller by Jules Lazaro, distributed
    with VLC-CRT-Filter-Effect under the GNU LGPL 2.1 or later.

    The controller adds or removes the native filter on the current video and
    changes its parameters live. Video subtitles are composed after the native
    video filter and therefore retain their clean edges.
--]]

function descriptor()
    return {
        title = "CRT Display Controller",
        version = "2.0",
        author = "Jules Lazaro and PowerVLC contributors",
        description = "Live scanline, phosphor, halation, and diffusion controls.",
        capabilities = {}
    }
end

local values = {
    darkness = 35,
    spacing = 2,
    blend = true,
    phosphor = 0,
    mask_strength = 20,
    halation = 0,
    diffusion = 0
}

local defaults = {
    darkness = 35,
    spacing = 2,
    blend = true,
    phosphor = 0,
    mask_strength = 20,
    halation = 0,
    diffusion = 0
}

local dialog = nil
local labels = {}
local filter_name = "crtscanline"
local retroarch_dropdown = nil
local retroarch_raster_dropdown = nil
local retroarch_presets = {}
local retroarch_selection = 1
local retroarch_raster_selection = 1
local retroarch_rasters = {
    { label = "Auto (source SD)", value = "auto" },
    { label = "Native", value = "native" },
    { label = "240p", value = "240p" },
    { label = "480p", value = "480p" }
}

local function get_config(name, fallback)
    local value = vlc.config.get("crtscanline-" .. name)
    if value == nil then return fallback end
    return value
end

local function set_config(name, value)
    vlc.config.set("crtscanline-" .. name, value)
end

local function read_object_filter_chain(object)
    if not object then return nil end
    local ok, value = pcall(vlc.var.get, object, "video-filter")
    if ok and type(value) == "string" then return value end
    return nil
end

local function change_filter_chain(chain, enabled)
    local modules = {}
    local found = false

    for entry in string.gmatch(chain or "", "[^:]+") do
        local name = string.match(entry, "^%s*([^%s{]+)")
        if name == filter_name then
            found = true
            if enabled then table.insert(modules, entry) end
        else
            table.insert(modules, entry)
        end
    end

    if enabled and not found then table.insert(modules, filter_name) end
    return table.concat(modules, ":")
end

local function set_object_filter_chain(object, chain)
    if not object then return end
    if read_object_filter_chain(object) ~= chain then
        pcall(vlc.var.set, object, "video-filter", chain)
    end
end

local function set_filter_enabled(enabled)
    local playlist = vlc.object.playlist()
    local chain = read_object_filter_chain(playlist)
    if chain == nil then
        local ok, value = pcall(vlc.config.get, "video-filter")
        chain = ok and type(value) == "string" and value or ""
    end

    local updated = change_filter_chain(chain, enabled)
    if updated ~= chain then pcall(vlc.config.set, "video-filter", updated) end
    set_object_filter_chain(playlist, updated)
    set_object_filter_chain(vlc.object.vout(), updated)
end

local function runtime_get(name)
    local object = vlc.object.libvlc()
    local ok, value = pcall(vlc.var.get, object, name)
    if ok then return value end
    return nil
end

local function runtime_set(name, value)
    pcall(vlc.var.set, vlc.object.libvlc(), name, value)
end

local function set_gpu_enabled(enabled)
    vlc.config.set("crt-retroarch-enabled", enabled)
    runtime_set("crt-retroarch-enabled", enabled)
end

local function load_compatible_retroarch_presets()
    retroarch_presets = {}
    local available = runtime_get("crt-retroarch-available")
    if type(available) ~= "string" then return end
    for name in string.gmatch(available, "[^;]+") do
        table.insert(retroarch_presets, name)
    end
end

local function phosphor_name(value)
    local names = { "Off", "Aperture", "Slot", "Shadow" }
    return names[value + 1] or "Off"
end

local function refresh_labels()
    if labels.darkness then labels.darkness:set_text("<b>" .. values.darkness .. "</b>") end
    if labels.spacing then labels.spacing:set_text("<b>" .. values.spacing .. "</b>") end
    if labels.blend then labels.blend:set_text(values.blend and "<b>Smooth</b>" or "<b>Hard</b>") end
    if labels.phosphor then labels.phosphor:set_text("<b>" .. phosphor_name(values.phosphor) .. "</b>") end
    if labels.mask_strength then labels.mask_strength:set_text("<b>" .. values.mask_strength .. "</b>") end
    if labels.halation then labels.halation:set_text("<b>" .. values.halation .. "</b>") end
    if labels.diffusion then labels.diffusion:set_text("<b>" .. values.diffusion .. "</b>") end
end

local function apply(name)
    local key = string.gsub(name, "-", "_")
    set_config(name, values[key])
    set_gpu_enabled(false)
    set_filter_enabled(true)
    refresh_labels()
end

local function apply_all()
    set_config("darkness", values.darkness)
    set_config("spacing", values.spacing)
    set_config("blend", values.blend)
    set_config("phosphor", values.phosphor)
    set_config("mask-strength", values.mask_strength)
    set_config("halation", values.halation)
    set_config("diffusion", values.diffusion)
    set_gpu_enabled(false)
    set_filter_enabled(true)
    refresh_labels()
end

local function adjust(name, delta, minimum, maximum)
    values[name] = math.max(minimum, math.min(maximum, values[name] + delta))
    apply(name == "mask_strength" and "mask-strength" or name)
end

local function set_preset(darkness, spacing, blend, phosphor,
                          mask_strength, halation, diffusion)
    values.darkness = darkness
    values.spacing = spacing
    values.blend = blend
    values.phosphor = phosphor
    values.mask_strength = mask_strength
    values.halation = halation
    values.diffusion = diffusion
    apply_all()
end

local function apply_retroarch_preset()
    if not retroarch_dropdown or not retroarch_raster_dropdown then return end
    local index = retroarch_dropdown:get_value()
    local name = retroarch_presets[index]
    if not name then return end
    retroarch_selection = index
    local raster_index = retroarch_raster_dropdown:get_value()
    local raster = retroarch_rasters[raster_index]
    if not raster then return end
    retroarch_raster_selection = raster_index
    vlc.config.set("crt-retroarch-preset", name)
    runtime_set("crt-retroarch-preset", name)
    vlc.config.set("crt-retroarch-raster", raster.value)
    runtime_set("crt-retroarch-raster", raster.value)
    set_filter_enabled(false)
    set_gpu_enabled(true)
end

local function enable_effect()
    if #retroarch_presets > 0 and vlc.config.get("crt-retroarch-enabled") then
        set_gpu_enabled(true)
    else
        set_filter_enabled(true)
    end
end

local function disable_effect()
    set_filter_enabled(false)
    set_gpu_enabled(false)
end

local function cycle_phosphor()
    values.phosphor = (values.phosphor + 1) % 4
    apply("phosphor")
end

local function toggle_blend()
    values.blend = not values.blend
    apply("blend")
end

local function create_dialog()
    if dialog then dialog:delete() end
    dialog = vlc.dialog("CRT Display Controller")

    dialog:add_label("<b>CRT display</b>", 1, 1, 2, 1)
    dialog:add_button("On", enable_effect, 3, 1, 1, 1)
    dialog:add_button("Off", disable_effect, 4, 1, 1, 1)

    dialog:add_label("Scanlines", 1, 2, 1, 1)
    dialog:add_button(" - ", function() adjust("darkness", -5, 0, 100) end, 2, 2, 1, 1)
    dialog:add_button(" + ", function() adjust("darkness", 5, 0, 100) end, 3, 2, 1, 1)
    labels.darkness = dialog:add_label("", 4, 2, 1, 1)

    dialog:add_label("Spacing", 1, 3, 1, 1)
    dialog:add_button(" - ", function() adjust("spacing", -1, 1, 20) end, 2, 3, 1, 1)
    dialog:add_button(" + ", function() adjust("spacing", 1, 1, 20) end, 3, 3, 1, 1)
    labels.spacing = dialog:add_label("", 4, 3, 1, 1)

    dialog:add_label("Beam", 1, 4, 1, 1)
    dialog:add_button("Toggle", toggle_blend, 2, 4, 2, 1)
    labels.blend = dialog:add_label("", 4, 4, 1, 1)

    dialog:add_label("Phosphor", 1, 5, 1, 1)
    dialog:add_button("Next", cycle_phosphor, 2, 5, 2, 1)
    labels.phosphor = dialog:add_label("", 4, 5, 1, 1)

    dialog:add_label("Mask", 1, 6, 1, 1)
    dialog:add_button(" - ", function() adjust("mask_strength", -5, 0, 100) end, 2, 6, 1, 1)
    dialog:add_button(" + ", function() adjust("mask_strength", 5, 0, 100) end, 3, 6, 1, 1)
    labels.mask_strength = dialog:add_label("", 4, 6, 1, 1)

    dialog:add_label("Halation", 1, 7, 1, 1)
    dialog:add_button(" - ", function() adjust("halation", -5, 0, 100) end, 2, 7, 1, 1)
    dialog:add_button(" + ", function() adjust("halation", 5, 0, 100) end, 3, 7, 1, 1)
    labels.halation = dialog:add_label("", 4, 7, 1, 1)

    dialog:add_label("Diffusion", 1, 8, 1, 1)
    dialog:add_button(" - ", function() adjust("diffusion", -5, 0, 100) end, 2, 8, 1, 1)
    dialog:add_button(" + ", function() adjust("diffusion", 5, 0, 100) end, 3, 8, 1, 1)
    labels.diffusion = dialog:add_label("", 4, 8, 1, 1)

    dialog:add_label("<b>Presets</b>", 1, 9, 1, 1)
    dialog:add_button("Subtle", function() set_preset(18, 2, true, 0, 20, 0, 5) end, 2, 9, 1, 1)
    dialog:add_button("Vintage anime", function() set_preset(26, 2, true, 1, 15, 10, 10) end, 3, 9, 1, 1)
    dialog:add_button("Broadcast", function() set_preset(35, 2, true, 2, 20, 15, 10) end, 4, 9, 1, 1)
    if #retroarch_presets > 0 then
        dialog:add_label("<b>Presets RetroArch exacts</b>", 1, 10, 1, 1)
        retroarch_dropdown = dialog:add_dropdown(2, 10, 2, 1)
        for index, name in ipairs(retroarch_presets) do
            retroarch_dropdown:add_value(name, index)
        end
        retroarch_dropdown:set_value(retroarch_selection)
        dialog:add_button("Apply", apply_retroarch_preset, 4, 10, 1, 1)
        dialog:add_label("Raster source", 1, 11, 1, 1)
        retroarch_raster_dropdown = dialog:add_dropdown(2, 11, 2, 1)
        for index, raster in ipairs(retroarch_rasters) do
            retroarch_raster_dropdown:add_value(raster.label, index)
        end
        retroarch_raster_dropdown:set_value(retroarch_raster_selection)
        dialog:add_label("<i>Original GLSL; unsupported presets are hidden for this GPU.</i>",
                         1, 12, 4, 1)
    else
        dialog:add_label("<i>RetroArch shaders unavailable on this video output.</i>",
                         1, 10, 4, 1)
    end
    dialog:add_label("<i>Subtitles stay sharp. CPU mode remains available for legacy hardware.</i>",
                     1, 13, 4, 1)
    dialog:add_label("Based on VLC-CRT-Filter-Effect by Jules Lazaro", 1, 14, 4, 1)
    refresh_labels()
end

function activate()
    values.darkness = get_config("darkness", defaults.darkness)
    values.spacing = get_config("spacing", defaults.spacing)
    values.blend = get_config("blend", defaults.blend)
    values.phosphor = get_config("phosphor", defaults.phosphor)
    values.mask_strength = get_config("mask-strength", defaults.mask_strength)
    values.halation = get_config("halation", defaults.halation)
    values.diffusion = get_config("diffusion", defaults.diffusion)
    load_compatible_retroarch_presets()
    local saved_preset = vlc.config.get("crt-retroarch-preset") or "crt-easymode"
    for index, name in ipairs(retroarch_presets) do
        if name == saved_preset then
            retroarch_selection = index
            break
        end
    end
    local saved_raster = vlc.config.get("crt-retroarch-raster") or "auto"
    for index, raster in ipairs(retroarch_rasters) do
        if raster.value == saved_raster then
            retroarch_raster_selection = index
            break
        end
    end
    create_dialog()
end

function deactivate()
    if dialog then
        dialog:delete()
        dialog = nil
    end
    labels = {}
    retroarch_dropdown = nil
    retroarch_raster_dropdown = nil
end

function close()
    -- The dialog provider has already closed the native window. Mark the
    -- extension inactive as well, otherwise the next menu click only toggles
    -- the stale active state off and appears to do nothing.
    dialog = nil
    labels = {}
    retroarch_dropdown = nil
    retroarch_raster_dropdown = nil
    vlc.deactivate()
end
