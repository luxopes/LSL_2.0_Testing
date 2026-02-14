# LSL Math Library (fixed-point approximations)

function __fp_scale():
    return 1000000
end

function __fp_pi():
    return 3141592
end

function __fp_two_pi():
    return 6283184
end

function __fp_ln2():
    return 693147
end

function __fp_mul(a, b):
    return (a * b) / __fp_scale()
end

function __fp_div(a, b):
    if b == 0:
        return 0
    end
    sign = 1
    if a < 0:
        a = 0 - a
        sign = 0 - sign
    end
    if b < 0:
        b = 0 - b
        sign = 0 - sign
    end
    out = (a * __fp_scale()) / b
    if sign < 0:
        out = 0 - out
    end
    return out
end

function __fp_round(x):
    if x >= 0:
        return (x + (__fp_scale() / 2)) / __fp_scale()
    end
    x = 0 - x
    return 0 - ((x + (__fp_scale() / 2)) / __fp_scale())
end

function __fp_norm_angle(x):
    two_pi = __fp_two_pi()
    pi = __fp_pi()
    while x > pi:
        x = x - two_pi
    end
    while x < 0 - pi:
        x = x + two_pi
    end
    return x
end

function sqrt(n):
    if n <= 0:
        return 0
    end
    x = n
    y = (x + 1) / 2
    while y < x:
        x = y
        y = (x + n / x) / 2
    end
    return x
end

function pow(a, b):
    if b < 0:
        return 0
    end
    result = 1
    i = 0
    while i < b:
        result = result * a
        i = i + 1
    end
    return result
end

function sin(deg):
    rad = (deg * __fp_pi()) / 180
    x = __fp_norm_angle(rad)
    x2 = __fp_mul(x, x)
    term = x
    result = x
    term = __fp_mul(term, x2)
    result = result - (term / 6)
    term = __fp_mul(term, x2)
    result = result + (term / 120)
    term = __fp_mul(term, x2)
    result = result - (term / 5040)
    return __fp_round(result)
end

function cos(deg):
    rad = (deg * __fp_pi()) / 180
    x = __fp_norm_angle(rad)
    x2 = __fp_mul(x, x)
    result = __fp_scale()
    term = x2
    result = result - (term / 2)
    term = __fp_mul(term, x2)
    result = result + (term / 24)
    term = __fp_mul(term, x2)
    result = result - (term / 720)
    return __fp_round(result)
end

function tan(deg):
    c = cos(deg)
    if c == 0:
        return 0
    end
    s = sin(deg)
    return __fp_round(__fp_div(s, c))
end

function exp(x):
    # integer exp via fixed-point series
    fp_x = x * __fp_scale()
    term = __fp_scale()
    result = __fp_scale()
    i = 1
    while i <= 10:
        term = __fp_mul(term, fp_x)
        term = term / i
        result = result + term
        i = i + 1
    end
    return __fp_round(result)
end

function log(x):
    if x <= 0:
        return 0
    end
    fp_x = x * __fp_scale()
    scale = __fp_scale()
    two = scale * 2
    k = 0
    while fp_x > two:
        fp_x = fp_x / 2
        k = k + 1
    end
    while fp_x < (scale / 2):
        fp_x = fp_x * 2
        k = k - 1
    end
    t = __fp_div(fp_x - scale, fp_x + scale)
    t2 = __fp_mul(t, t)
    term = t
    sum = term
    term = __fp_mul(term, t2)
    sum = sum + (term / 3)
    term = __fp_mul(term, t2)
    sum = sum + (term / 5)
    ln = sum * 2
    ln = ln + (k * __fp_ln2())
    return __fp_round(ln)
end

function factorial(n):
    if n < 0:
        return 0
    end
    result = 1
    i = 2
    while i <= n:
        result = result * i
        i = i + 1
    end
    return result
end
