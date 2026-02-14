# LSL Advanced Library

function range(start, end):
    return __lsl_range(start, end)
end

function zip(a, b):
    out = []
    n = len(a)
    if len(b) < n:
        n = len(b)
    end
    i = 0
    while i < n:
        out = out + [[a[i], b[i]]]
        i = i + 1
    end
    return out
end

function enumerate(lst):
    out = []
    i = 0
    while i < len(lst):
        out = out + [[i, lst[i]]]
        i = i + 1
    end
    return out
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
