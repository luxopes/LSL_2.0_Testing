# LSL List Library

function copy(lst):
    return lst + []
end

function extend(lst, other):
    return lst + other
end

function index_of(lst, item):
    return index(lst, item)
end

function contains_item(lst, item):
    if index(lst, item) >= 0:
        return true
    end
    return false
end

function __lsl_list_remove_at(lst, idx):
    out = []
    i = 0
    while i < len(lst):
        if i != idx:
            out = out + [lst[i]]
        end
        i = i + 1
    end
    return out
end

function slice(lst, start, end):
    if start < 0:
        start = 0
    end
    if end > len(lst):
        end = len(lst)
    end
    if end < start:
        return []
    end
    out = []
    i = start
    while i < end:
        out = out + [lst[i]]
        i = i + 1
    end
    return out
end

function unique(lst):
    out = []
    i = 0
    while i < len(lst):
        if not contains_item(out, lst[i]):
            out = out + [lst[i]]
        end
        i = i + 1
    end
    return out
end

function shuffle(lst):
    tmp = lst + []
    out = []
    while len(tmp) > 0:
        i = rand(0, len(tmp) - 1)
        out = out + [tmp[i]]
        tmp = __lsl_list_remove_at(tmp, i)
    end
    return out
end

function __lsl_list_insert_sorted(lst, value):
    out = []
    inserted = false
    i = 0
    while i < len(lst):
        if not inserted and value <= lst[i]:
            out = out + [value]
            inserted = true
        end
        out = out + [lst[i]]
        i = i + 1
    end
    if not inserted:
        out = out + [value]
    end
    return out
end

function sort(lst):
    out = []
    i = 0
    while i < len(lst):
        out = __lsl_list_insert_sorted(out, lst[i])
        i = i + 1
    end
    return out
end
