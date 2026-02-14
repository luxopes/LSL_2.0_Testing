use "draw"

function widget_defaults(widget):
    widget.x = 0
    widget.y = 0
    widget.width = 100
    widget.height = 30
    widget.visible = true
    widget.parent = null
end

function string_sub(text, start, count):
    out = ""
    i = 0
    while i < count:
        out = out + text[start + i]
        i = i + 1
    end
    return out
end

class Widget:
    function __init__():
        widget_defaults(self)
    end

    function draw(surface):
        return null
    end

    function handle_event(evt):
        return null
    end
end

class Button:
    function __init__(text):
        widget_defaults(self)
        self.text = text
        self.pressed = false
        self.on_click = ""
    end

    function draw(surface):
        bg = 12632256
        if self.pressed:
            bg = 8421504
        end
        fill_rect(surface, self.x, self.y, self.width, self.height, bg)
        draw_rect(surface, self.x, self.y, self.width, self.height, 0)
        tx = self.x + (self.width - text_width(self.text)) / 2
        ty = self.y + (self.height - text_height()) / 2
        draw_text(surface, tx, ty, self.text, 0)
    end

    function handle_event(evt):
        if evt["type"] == "mouse":
            if evt["x"] >= 0 and evt["y"] >= 0 and evt["x"] < self.width and evt["y"] < self.height:
                if evt["buttons"] != 0:
                    self.pressed = true
                else:
                    if self.pressed:
                        self.pressed = false
                        if self.on_click != "":
                            __lsl_call1(self.on_click, self)
                        end
                    end
                end
            else:
                if evt["buttons"] == 0:
                    self.pressed = false
                end
            end
        end
        return null
    end
end

class Label:
    function __init__(text):
        widget_defaults(self)
        self.text = text
    end

    function draw(surface):
        draw_text(surface, self.x, self.y, self.text, 0)
    end
end

class TextInput:
    function __init__():
        widget_defaults(self)
        self.text = ""
        self.cursor = 0
        self.focused = false
    end

    function draw(surface):
        fill_rect(surface, self.x, self.y, self.width, self.height, 16777215)
        draw_rect(surface, self.x, self.y, self.width, self.height, 0)
        draw_text(surface, self.x + 4, self.y + 4, self.text, 0)
    end

    function handle_event(evt):
        if evt["type"] == "mouse":
            if evt["buttons"] != 0 and evt["x"] >= 0 and evt["y"] >= 0 and evt["x"] < self.width and evt["y"] < self.height:
                self.focused = true
            elif evt["buttons"] != 0:
                self.focused = false
            end
        end
        if evt["type"] == "key" and self.focused:
            if evt["code"] == 8:
                if len(self.text) > 0:
                    self.text = string_sub(self.text, 0, len(self.text) - 1)
                end
            else:
                self.text = self.text + chr(evt["code"])
            end
        end
        return null
    end
end
