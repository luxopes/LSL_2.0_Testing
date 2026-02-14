class Surface:
    function __init__(width, height):
        self.width = width
        self.height = height
        self.pixels = []
        y = 0
        while y < height:
            row = []
            x = 0
            while x < width:
                row = row + [0]
                x = x + 1
            end
            self.pixels = self.pixels + [row]
            y = y + 1
        end
    end

    function clear(color):
        y = 0
        while y < self.height:
            row = self.pixels[y]
            x = 0
            while x < self.width:
                row[x] = color
                x = x + 1
            end
            self.pixels[y] = row
            y = y + 1
        end
    end

    function set_pixel(x, y, color):
        if x >= 0 and y >= 0 and x < self.width and y < self.height:
            row = self.pixels[y]
            row[x] = color
            self.pixels[y] = row
        end
    end

    function get_pixel(x, y):
        if x >= 0 and y >= 0 and x < self.width and y < self.height:
            return self.pixels[y][x]
        end
        return 0
    end

    function blit_to(dest, x, y):
        yi = 0
        while yi < self.height:
            xi = 0
            while xi < self.width:
                dest.set_pixel(x + xi, y + yi, self.pixels[yi][xi])
                xi = xi + 1
            end
            yi = yi + 1
        end
    end
end
