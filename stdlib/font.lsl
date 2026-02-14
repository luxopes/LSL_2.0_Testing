FONT_WIDTH = 8
FONT_HEIGHT = 8

function font_init():
    return null
end

function draw_char(surface, x, y, ch, color):
    if ch == " " or ch == 32:
        return null
    end
    yi = 0
    while yi < FONT_HEIGHT:
        xi = 0
        while xi < FONT_WIDTH - 2:
            surface.set_pixel(x + xi + 1, y + yi, color)
            xi = xi + 1
        end
        yi = yi + 1
    end
    return null
end

function text_width(text):
    return len(text) * FONT_WIDTH
end

function text_height():
    return FONT_HEIGHT
end
