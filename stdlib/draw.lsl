use "font"

function abs_val(n):
    if n < 0:
        return 0 - n
    end
    return n
end

function draw_line(surface, x1, y1, x2, y2, color):
    dx = abs_val(x2 - x1)
    sx = -1
    if x1 < x2:
        sx = 1
    end
    dy = 0 - abs_val(y2 - y1)
    sy = -1
    if y1 < y2:
        sy = 1
    end
    err = dx + dy
    while true:
        surface.set_pixel(x1, y1, color)
        if x1 == x2 and y1 == y2:
            break
        end
        e2 = err * 2
        if e2 >= dy:
            err = err + dy
            x1 = x1 + sx
        end
        if e2 <= dx:
            err = err + dx
            y1 = y1 + sy
        end
    end
end

function draw_rect(surface, x, y, w, h, color):
    xi = 0
    while xi < w:
        surface.set_pixel(x + xi, y, color)
        surface.set_pixel(x + xi, y + h - 1, color)
        xi = xi + 1
    end
    yi = 0
    while yi < h:
        surface.set_pixel(x, y + yi, color)
        surface.set_pixel(x + w - 1, y + yi, color)
        yi = yi + 1
    end
end

function fill_rect(surface, x, y, w, h, color):
    yi = 0
    while yi < h:
        xi = 0
        while xi < w:
            surface.set_pixel(x + xi, y + yi, color)
            xi = xi + 1
        end
        yi = yi + 1
    end
end

function draw_circle(surface, cx, cy, r, color):
    x = r
    y = 0
    err = 1 - r
    while x >= y:
        surface.set_pixel(cx + x, cy + y, color)
        surface.set_pixel(cx + y, cy + x, color)
        surface.set_pixel(cx - y, cy + x, color)
        surface.set_pixel(cx - x, cy + y, color)
        surface.set_pixel(cx - x, cy - y, color)
        surface.set_pixel(cx - y, cy - x, color)
        surface.set_pixel(cx + y, cy - x, color)
        surface.set_pixel(cx + x, cy - y, color)
        y = y + 1
        if err < 0:
            err = err + (2 * y) + 1
        else:
            x = x - 1
            err = err + (2 * (y - x)) + 1
        end
    end
end

function draw_text(surface, x, y, text, color):
    ti = 0
    while ti < len(text):
        draw_char(surface, x + (ti * FONT_WIDTH), y, text[ti], color)
        ti = ti + 1
    end
end
