function idiv(n, d):
    return (n - (n % d)) / d
end

function layout_horizontal(widgets, x, y, width, height, spacing):
    count = len(widgets)
    if count == 0:
        return null
    end
    total_spacing = spacing * (count - 1)
    cell_width = idiv(width - total_spacing, count)
    cx = x
    i = 0
    while i < count:
        w = widgets[i]
        w.x = cx
        w.y = y
        w.width = cell_width
        w.height = height
        cx = cx + cell_width + spacing
        i = i + 1
    end
    return null
end

function layout_vertical(widgets, x, y, width, height, spacing):
    count = len(widgets)
    if count == 0:
        return null
    end
    total_spacing = spacing * (count - 1)
    cell_height = idiv(height - total_spacing, count)
    cy = y
    i = 0
    while i < count:
        w = widgets[i]
        w.x = x
        w.y = cy
        w.width = width
        w.height = cell_height
        cy = cy + cell_height + spacing
        i = i + 1
    end
    return null
end
