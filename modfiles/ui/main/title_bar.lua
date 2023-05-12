title_bar = {}

-- ** LOCAL UTIL **
local function configure_pause_button_style(button, pause_on_interface)
    button.style = (pause_on_interface) and "fp_button_frame_tool_active" or "fp_button_frame_tool"
end

local function toggle_paused_state(player, _, _)
    if not game.is_multiplayer() then
        local preferences = data_util.get("preferences", player)
        preferences.pause_on_interface = not preferences.pause_on_interface

        local main_elements = data_util.get("main_elements", player)
        local button_pause = main_elements.title_bar.pause_button
        configure_pause_button_style(button_pause, preferences.pause_on_interface)

        main_dialog.set_pause_state(player, main_elements.main_frame)
    end
end


-- ** TOP LEVEL **
function title_bar.build(player)
    local main_elements = data_util.get("main_elements", player)
    main_elements.title_bar = {}

    local flow_title_bar = main_elements.main_frame.add{type="flow", direction="horizontal",
        tags={mod="fp", on_gui_click="re-center_main_dialog"}}
    flow_title_bar.style.horizontal_spacing = 8
    flow_title_bar.drag_target = main_elements.main_frame
    -- The separator line causes the height to increase for some inexplicable reason, so we must hardcode it here
    flow_title_bar.style.height = TITLE_BAR_HEIGHT

    local button_switch = flow_title_bar.add{type="sprite-button", style="frame_action_button",
        tags={mod="fp", on_gui_click="switch_to_compact_view"}, tooltip={"fp.switch_to_compact_view"},
        sprite="fp_sprite_arrow_left_light", hovered_sprite="fp_sprite_arrow_left_dark",
        clicked_sprite="fp_sprite_arrow_left_dark", mouse_button_filter={"left"}}
    button_switch.style.padding = 2
    main_elements.title_bar["switch_button"] = button_switch

    flow_title_bar.add{type="label", caption={"mod-name.factoryplanner"}, style="frame_title",
        ignored_by_interaction=true}

    local label_hint = flow_title_bar.add{type="label", ignored_by_interaction=true}
    label_hint.style.font = "heading-2"
    label_hint.style.margin = {0, 0, 0, 8}
    label_hint.style.horizontally_squashable = true
    main_elements.title_bar["hint_label"] = label_hint

    local drag_handle = flow_title_bar.add{type="empty-widget", style="flib_titlebar_drag_handle",
        ignored_by_interaction=true}
    drag_handle.style.minimal_width = 80

    flow_title_bar.add{type="button", caption={"fp.tutorial"}, style="fp_button_frame_tool",
        tags={mod="fp", on_gui_click="title_bar_open_dialog", type="tutorial"}, mouse_button_filter={"left"}}
    flow_title_bar.add{type="button", caption={"fp.preferences"}, style="fp_button_frame_tool",
        tags={mod="fp", on_gui_click="title_bar_open_dialog", type="preferences"}, mouse_button_filter={"left"}}

    local separation = flow_title_bar.add{type="line", direction="vertical"}
    separation.style.height = 24

    local button_pause = flow_title_bar.add{type="button", caption={"fp.pause"}, tooltip={"fp.pause_on_interface"},
        tags={mod="fp", on_gui_click="toggle_pause_game"}, enabled=(not game.is_multiplayer()),
        style="fp_button_frame_tool", mouse_button_filter={"left"}}
    main_elements.title_bar["pause_button"] = button_pause

    local preferences = data_util.get("preferences", player)
    configure_pause_button_style(button_pause, preferences.pause_on_interface)

    local button_close = flow_title_bar.add{type="sprite-button", tags={mod="fp", on_gui_click="close_main_dialog"},
        sprite="utility/close_white", hovered_sprite="utility/close_black", clicked_sprite="utility/close_black",
        tooltip={"fp.close_interface"}, style="frame_action_button", mouse_button_filter={"left"}}
    button_close.style.padding = 1
end

function title_bar.refresh(player)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory
    local title_bar_elements = ui_state.main_elements.title_bar
    -- Disallow switching to compact view if the selected subfactory is nil or invalid
    title_bar_elements.switch_button.enabled = subfactory and subfactory.valid
end


-- Enqueues the given message into the message queue; Possible types: error, warning, hint
function title_bar.enqueue_message(player, message, type, lifetime, instant_refresh)
    local message_queue = data_util.get("ui_state", player).message_queue
    table.insert(message_queue, {text=message, type=type, lifetime=lifetime})

    if instant_refresh then title_bar.refresh_message(player) end
end

-- Refreshes the current message, taking into account priotities and lifetimes
-- The messages are displayed in enqueued order, displaying higher priorities first
-- The lifetime is decreased for every message on every refresh
-- (The algorithm(s) could be more efficient, but it doesn't matter for the small dataset)
function title_bar.refresh_message(player)
    local ui_state = data_util.get("ui_state", player)
    local message_queue = ui_state.message_queue

    local title_bar_elements = ui_state.main_elements.title_bar
    if not title_bar_elements then return end

    -- The message types are ordered by priority
    local types = {"error", "warning", "hint"}

    -- TODO this is not the proper way to do this probably, but it works
    local subfactory = ui_state.context.subfactory
    if subfactory and subfactory.valid and subfactory.linearly_dependant then
        title_bar.enqueue_message(player, {"fp.error_linearly_dependant_recipes"}, "error", 1, false)
    end

    local new_message = nil
    -- Go over the all types and messages, trying to find one that should be shown
    for _, type in ipairs(types) do
        -- All messages will have lifetime > 0 at this point
        for _, message in pairs(message_queue) do
            -- Find first message of this type, then break
            if message.type == type then
                new_message = message
                break
            end
        end
        -- If a message is found, break because no messages of lower ranked type should be considered
        if new_message ~= nil then break end
    end

    -- Set caption and hide if no message is shown so that the margins work out
    title_bar_elements.hint_label.caption = (new_message)
        and {"fp." .. new_message.type .. "_message", new_message.text} or ""
    title_bar_elements.hint_label.visible = (new_message)

    -- Decrease the lifetime of every queued message
    for index, message in pairs(message_queue) do
        message.lifetime = message.lifetime - 1
        if message.lifetime <= 0 then message_queue[index] = nil end
    end
end


-- ** EVENTS **
title_bar.gui_events = {
    on_gui_click = {
        {
            name = "re-center_main_dialog",
            handler = (function(player, _, event)
                if event.button == defines.mouse_button_type.middle then
                    local ui_state = data_util.get("ui_state", player)
                    local main_frame = ui_state.main_elements.main_frame
                    ui_util.properly_center_frame(player, main_frame, ui_state.main_dialog_dimensions)
                end
            end)
        },
        {
            name = "switch_to_compact_view",
            handler = (function(player, _, _)
                main_dialog.toggle(player)
                data_util.get("flags", player).compact_view = true

                compact_dialog.toggle(player)
            end)
        },
        {
            name = "close_main_dialog",
            handler = (function(player, _, _)
                main_dialog.toggle(player)
            end)
        },
        {
            name = "toggle_pause_game",
            handler = toggle_paused_state
        },
        {
            name = "title_bar_open_dialog",
            handler = (function(player, tags, _)
                modal_dialog.enter(player, {type=tags.type})
            end)
        }
    }
}

title_bar.misc_events = {
    fp_toggle_pause = (function(player, _)
        if main_dialog.is_in_focus(player) then toggle_paused_state(player) end
    end)
}