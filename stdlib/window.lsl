use "hardware"
use "surface"
use "draw"

windows = []
root_surface = null
cursor_x = 0
cursor_y = 0
screen_width = 0
screen_height = 0
focused_window = null
TITLE_HEIGHT = 20

function wm_init(width, height):
    screen_width = width
    screen_height = height
    root_surface = new Surface(width, height)
    fb_init(width, height, 32)
end

function wm_create_window(x, y, width, height, title):
    content_height = height - TITLE_HEIGHT
    if content_height < 1:
        content_height = 1
    end
    content_width = width - 2
    if content_width < 1:
        content_width = 1
    end
    win = {id: rand(), x: x, y: y, width: width, height: height, title: title, surface: new Surface(content_width, content_height), visible: true, focused: false, widgets: []}
    windows = windows + [win]
    return win
end

function wm_window_at(x, y):
    i = len(windows) - 1
    while i >= 0:
        win = windows[i]
        if win["visible"] and x >= win["x"] and y >= win["y"] and x < win["x"] + win["width"] and y < win["y"] + win["height"]:
            return win
        end
        i = i - 1
    end
    return null
end

function wm_focus_window(win):
    i = 0
    while i < len(windows):
        w = windows[i]
        w["focused"] = false
        windows[i] = w
        i = i + 1
    end
    if win != null:
        win["focused"] = true
    end
    focused_window = win
end

function wm_add_widget(win, widget):
    widgets = win["widgets"]
    widgets = widgets + [widget]
    win["widgets"] = widgets
    widget.parent = win
end

function wm_handle_event(evt):
    if evt["type"] == "mouse":
        cursor_x = clamp(cursor_x + evt["dx"], 0, screen_width - 1)
        cursor_y = clamp(cursor_y + evt["dy"], 0, screen_height - 1)
        if evt["buttons"] != 0:
            target = wm_window_at(cursor_x, cursor_y)
            if target != null:
                wm_focus_window(target)
            end
        end
        if focused_window != null:
            local_x = cursor_x - focused_window["x"] - 1
            local_y = cursor_y - focused_window["y"] - TITLE_HEIGHT
            widgets = focused_window["widgets"]
            wi = 0
            while wi < len(widgets):
                w = widgets[wi]
                if w.visible:
                    evt_local = {type: "mouse", x: local_x - w.x, y: local_y - w.y, buttons: evt["buttons"]}
                    w.handle_event(evt_local)
                end
                wi = wi + 1
            end
        end
    elif evt["type"] == "key":
        if focused_window != null:
            widgets = focused_window["widgets"]
            wi = 0
            while wi < len(widgets):
                w = widgets[wi]
                if w.visible:
                    w.handle_event(evt)
                end
                wi = wi + 1
            end
        end
    end
end

function wm_composite():
    if root_surface == null:
        return null
    end
    root_surface.clear(3355443)
    wi = 0
    while wi < len(windows):
        win = windows[wi]
        if win["visible"]:
            win["surface"].clear(15132390)
            widgets = win["widgets"]
            wj = 0
            while wj < len(widgets):
                widget = widgets[wj]
                if widget.visible:
                    widget.draw(win["surface"])
                end
                wj = wj + 1
            end
            title_color = 5592405
            if win["focused"]:
                title_color = 3368601
            end
            fill_rect(root_surface, win["x"], win["y"], win["width"], win["height"], 10526880)
            fill_rect(root_surface, win["x"], win["y"], win["width"], TITLE_HEIGHT, title_color)
            draw_rect(root_surface, win["x"], win["y"], win["width"], win["height"], 0)
            draw_text(root_surface, win["x"] + 4, win["y"] + 4, win["title"], 16777215)
            win["surface"].blit_to(root_surface, win["x"] + 1, win["y"] + TITLE_HEIGHT)
        end
        wi = wi + 1
    end
    fill_rect(root_surface, cursor_x, cursor_y, 2, 2, 16711680)
    fb_blit(0, 0, root_surface.width, root_surface.height, root_surface.pixels)
end
