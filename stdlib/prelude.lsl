# LSL Prelude (selfhost runtime helpers)

# Prelude globals are avoided because functions do not share main scope variables.

function __lsl_num_to_str(n):
    if n == 0:
        return "0"
    end
    neg = false
    if n < 0:
        neg = true
        n = 0 - n
    end
    out = ""
    while n > 0:
        d = n % 10
        out = chr(d + 48) + out
        n = n / 10
    end
    if neg:
        out = "-" + out
    end
    return out
end

function type(x):
    if is_number(x):
        return "number"
    end
    if is_string(x):
        return "string"
    end
    if is_list(x):
        return "list"
    end
    if x == true or x == false:
        return "bool"
    end
    if x == null:
        return "null"
    end
    return "null"
end

function str(x):
    t = type(x)
    if t == "string":
        return x
    end
    if t == "number":
        return __lsl_num_to_str(x)
    end
    if t == "bool":
        if x:
            return "true"
        end
        return "false"
    end
    if t == "null":
        return "null"
    end
    if t == "list":
        out = "["
        i = 0
        while i < len(x):
            if i > 0:
                out = out + ", "
            end
            out = out + str(x[i])
            i = i + 1
        end
        out = out + "]"
        return out
    end
    return ""
end

function int(x):
    if is_number(x):
        return x
    end
    return num(str(x))
end

function bytes(x):
    t = type(x)
    if t == "string":
        return x
    end
    if t == "number":
        return chr(x)
    end
    if t == "bool":
        if x:
            return chr(1)
        end
        return chr(0)
    end
    if t == "list":
        out = ""
        i = 0
        while i < len(x):
            v = x[i]
            vt = type(v)
            if vt == "string":
                if len(v) > 0:
                    out = out + v[0]
                else:
                    out = out + chr(0)
                end
            elif vt == "number":
                out = out + chr(v)
            elif vt == "bool":
                if v:
                    out = out + chr(1)
                else:
                    out = out + chr(0)
                end
            else:
                out = out + chr(0)
            end
            i = i + 1
        end
        return out
    end
    return ""
end

function abs(x):
    if x < 0:
        return 0 - x
    end
    return x
end

function min(a, b):
    if a < b:
        return a
    end
    return b
end

function max(a, b):
    if a > b:
        return a
    end
    return b
end

function round(x):
    return int(x)
end

function floor(x):
    return int(x)
end

function ceil(x):
    return int(x)
end

function count(lst, value):
    i = 0
    c = 0
    while i < len(lst):
        if lst[i] == value:
            c = c + 1
        end
        i = i + 1
    end
    return c
end

function insert(lst, index, value):
    if index < 0:
        return null
    end
    if index > len(lst):
        return null
    end
    out = []
    i = 0
    while i < index and i < len(lst):
        out = out + [lst[i]]
        i = i + 1
    end
    out = out + [value]
    while i < len(lst):
        out = out + [lst[i]]
        i = i + 1
    end
    return out
end

function index(lst, value):
    i = 0
    while i < len(lst):
        if lst[i] == value:
            return i
        end
        i = i + 1
    end
    return -1
end

function pop(lst):
    if len(lst) == 0:
        return null
    end
    return lst[len(lst) - 1]
end

function clear(lst):
    return null
end

function sum(lst):
    total = 0
    i = 0
    while i < len(lst):
        if is_number(lst[i]):
            total = total + lst[i]
        end
        i = i + 1
    end
    return total
end

function average(lst):
    if len(lst) == 0:
        return 0
    end
    total = 0
    count_n = 0
    i = 0
    while i < len(lst):
        if is_number(lst[i]):
            total = total + lst[i]
            count_n = count_n + 1
        end
        i = i + 1
    end
    if count_n == 0:
        return 0
    end
    return total / count_n
end

function reverse(lst):
    out = []
    i = len(lst) - 1
    while i >= 0:
        out = out + [lst[i]]
        i = i - 1
    end
    return out
end

function join(lst, sep):
    out = ""
    i = 0
    while i < len(lst):
        if i > 0:
            out = out + sep
        end
        out = out + str(lst[i])
        i = i + 1
    end
    return out
end

function __lsl_is_space(c):
    if c == " ":
        return true
    end
    if c == "\n":
        return true
    end
    if c == "\r":
        return true
    end
    if c == "\t":
        return true
    end
    return false
end

function upper(s):
    lower_map = "abcdefghijklmnopqrstuvwxyz"
    upper_map = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    out = ""
    i = 0
    while i < len(s):
        c = s[i]
        j = 0
        replaced = false
        while j < len(lower_map):
            if c == lower_map[j]:
                out = out + upper_map[j]
                replaced = true
                break
            end
            j = j + 1
        end
        if not replaced:
            out = out + c
        end
        i = i + 1
    end
    return out
end

function lower(s):
    lower_map = "abcdefghijklmnopqrstuvwxyz"
    upper_map = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    out = ""
    i = 0
    while i < len(s):
        c = s[i]
        j = 0
        replaced = false
        while j < len(upper_map):
            if c == upper_map[j]:
                out = out + lower_map[j]
                replaced = true
                break
            end
            j = j + 1
        end
        if not replaced:
            out = out + c
        end
        i = i + 1
    end
    return out
end

function substring(s, start, length):
    if start < 0:
        return ""
    end
    if length < 0:
        return ""
    end
    if start >= len(s):
        return ""
    end
    out = ""
    i = 0
    while i < length and (start + i) < len(s):
        out = out + s[start + i]
        i = i + 1
    end
    return out
end

function replace(text, old, replacement):
    if old == "":
        return text
    end
    parts = split(text, old)
    return join(parts, replacement)
end

function trim(s):
    if len(s) == 0:
        return ""
    end
    start = 0
    while start < len(s) and __lsl_is_space(s[start]):
        start = start + 1
    end
    if start >= len(s):
        return ""
    end
    stop = len(s) - 1
    while stop >= start and __lsl_is_space(s[stop]):
        stop = stop - 1
    end
    out = ""
    i = start
    while i <= stop:
        out = out + s[i]
        i = i + 1
    end
    return out
end

function split(s, sep):
    out = []
    if sep == "" or sep == null:
        i = 0
        while i < len(s):
            while i < len(s) and __lsl_is_space(s[i]):
                i = i + 1
            end
            if i >= len(s):
                break
            end
            token = ""
            while i < len(s) and not __lsl_is_space(s[i]):
                token = token + s[i]
                i = i + 1
            end
            out = out + [token]
        end
        return out
    end
    seplen = len(sep)
    i = 0
    cur = ""
    while i < len(s):
        j = 0
        match = true
        while j < seplen:
            if (i + j) >= len(s) or s[i + j] != sep[j]:
                match = false
                break
            end
            j = j + 1
        end
        if match:
            out = out + [cur]
            cur = ""
            i = i + seplen
        else:
            cur = cur + s[i]
            i = i + 1
        end
    end
    out = out + [cur]
    return out
end

function rand(min_val, max_val):
    if max_val < min_val:
        return 0
    end
    # use uptime as a changing seed source
    seed_txt = readfile("/proc/uptime")
    seed = num(seed_txt)
    mix = (seed * 1103515245 + 12345) % 2147483648
    range = max_val - min_val + 1
    if range <= 0:
        return min_val
    end
    return min_val + (mix % range)
end

function sleep(seconds):
    wait seconds
    return null
end

function __lsl_call1(name, a0):
    return null
end

function __lsl_call2(name, a0, a1):
    return null
end

function readline():
    s = readfile("/dev/stdin")
    if s == null:
        return ""
    end
    parts = split(s, "\n")
    if len(parts) == 0:
        return ""
    end
    return parts[0]
end

function input(prompt):
    if prompt != "":
        print prompt
    end
    return readline()
end

function readnum(prompt):
    s = input(prompt)
    return num(s)
end

function map(fn, lst):
    out = []
    i = 0
    while i < len(lst):
        out = out + [__lsl_call1(fn, lst[i])]
        i = i + 1
    end
    return out
end

function filter(fn, lst):
    out = []
    i = 0
    while i < len(lst):
        if __lsl_call1(fn, lst[i]):
            out = out + [lst[i]]
        end
        i = i + 1
    end
    return out
end

function reduce(fn, lst):
    if len(lst) == 0:
        return null
    end
    acc = lst[0]
    i = 1
    while i < len(lst):
        acc = __lsl_call2(fn, acc, lst[i])
        i = i + 1
    end
    return acc
end
