use "surface"

function idiv(n, d):
    return (n - (n % d)) / d
end

function u16le(n):
    return chr(n % 256) + chr(idiv(n, 256) % 256)
end

function u32le(n):
    return chr(n % 256) + chr(idiv(n, 256) % 256) + chr(idiv(n, 65536) % 256) + chr(idiv(n, 16777216) % 256)
end

function byte_match(value, ascii):
    if value == ascii:
        return true
    end
    if value == chr(ascii):
        return true
    end
    return false
end

function read_u16(data, offset):
    return data[offset] + data[offset + 1] * 256
end

function read_u32(data, offset):
    return data[offset] + data[offset + 1] * 256 + data[offset + 2] * 65536 + data[offset + 3] * 16777216
end

function load_bmp(path):
    data = readfile(path)
    if data == "":
        return null
    end
    if len(data) < 54:
        return null
    end
    if not byte_match(data[0], 66) or not byte_match(data[1], 77):
        return null
    end
    offset = read_u32(data, 10)
    width = read_u32(data, 18)
    height = read_u32(data, 22)
    bpp = read_u16(data, 28)
    if width <= 0 or height <= 0:
        return null
    end
    if bpp != 24 and bpp != 32:
        return null
    end
    bytes_per_pixel = idiv(bpp, 8)
    row_bytes = idiv((width * bpp + 31), 32) * 4
    surface = new Surface(width, height)
    y = 0
    while y < height:
        src_y = height - 1 - y
        row_start = offset + (src_y * row_bytes)
        x = 0
        while x < width:
            px = row_start + (x * bytes_per_pixel)
            b = data[px]
            g = data[px + 1]
            r = data[px + 2]
            surface.set_pixel(x, y, (r * 65536) + (g * 256) + b)
            x = x + 1
        end
        y = y + 1
    end
    return surface
end

function save_bmp(surface, path):
    width = surface.width
    height = surface.height
    bpp = 24
    row_bytes = idiv((width * bpp + 31), 32) * 4
    pixel_bytes = row_bytes * height
    file_size = 54 + pixel_bytes
    header = "BM"
    header = header + u32le(file_size) + u16le(0) + u16le(0) + u32le(54)
    header = header + u32le(40) + u32le(width) + u32le(height)
    header = header + u16le(1) + u16le(bpp) + u32le(0) + u32le(pixel_bytes)
    header = header + u32le(0) + u32le(0) + u32le(0) + u32le(0)
    data = header
    y = height - 1
    while y >= 0:
        row = ""
        x = 0
        while x < width:
            color = surface.pixels[y][x]
            r = idiv(color, 65536) % 256
            g = idiv(color, 256) % 256
            b = color % 256
            row = row + chr(b) + chr(g) + chr(r)
            x = x + 1
        end
        pad = row_bytes - (width * 3)
        p = 0
        while p < pad:
            row = row + chr(0)
            p = p + 1
        end
        data = data + row
        y = y - 1
    end
    writefile(path, data)
    return null
end
