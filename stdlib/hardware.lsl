function VGA_WIDTH():
    return 640
end

function VGA_HEIGHT():
    return 480
end

function COLOR(r, g, b):
    return r * 65536 + g * 256 + b
end

function clamp(value, min_value, max_value):
    if value < min_value:
        return min_value
    end
    if value > max_value:
        return max_value
    end
    return value
end

function fb_blit(x, y, width, height, data):
    yi = 0
    while yi < height:
        row = data[yi]
        xi = 0
        while xi < width:
            fb_pixel(x + xi, y + yi, row[xi])
            xi = xi + 1
        end
        yi = yi + 1
    end
end

function fb_blit_surface(x, y, surface):
    fb_blit(x, y, surface.width, surface.height, surface.pixels)
end

function kb_poll():
    return keyboard_poll()
end

function mouse_state():
    return mouse_poll()
end
