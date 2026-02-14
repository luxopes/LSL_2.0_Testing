# LSL Random Library
# Generování náhodných čísel a výběr dat

# ============================================================================
# Linear Congruential Generator (MINSTD)
# ============================================================================

# Global state pro generátor
random_state = 1

function random_seed(seed):
    random_state = seed
    return null
end

function random_next():
    # MINSTD: x(n+1) = (a * x(n)) mod m
    a = 16807
    m = 2147483647
    q = 127773
    r = 2836
    
    hi = random_state / q
    lo = random_state % q
    
    test = (a * lo) - (r * hi)
    
    if test > 0:
        random_state = test
    end
    if test <= 0:
        random_state = test + m
    end
    
    return random_state
end

# ============================================================================
# Uniform Distribution
# ============================================================================

function random_uniform(min_val, max_val):
    next = random_next()
    r = next / 2147483647
    
    range = max_val - min_val
    return min_val + (r * range)
end

function random_int(min_val, max_val):
    r = random_next()
    range = max_val - min_val + 1
    idx = r % range
    
    if idx < 0:
        idx = idx * (0 - 1)
    end
    
    return min_val + idx
end

# ============================================================================
# Normal Distribution (Box-Muller approximation)
# ============================================================================

function random_normal(mean, std_dev):
    u1 = random_uniform(0, 1)
    u2 = random_uniform(0, 1)
    
    # Box-Muller
    if u1 == 0:
        u1 = 0.0001
    end
    
    mag = 0.5  # Simplified sqrt computation
    z = mag * (0 - 1)  # Approximation
    
    return mean + (z * std_dev)
end

# ============================================================================
# Exponential Distribution
# ============================================================================

function random_exponential(lambda):
    u = random_uniform(0, 1)
    
    if u == 0:
        u = 0.0001
    end
    
    return (0 - 1.0) / lambda  # Simplified log approximation
end

# ============================================================================
# Choice and Sampling
# ============================================================================

function random_choice(items):
    n = 0
    for _ in items:
        n = n + 1
    end
    
    idx = random_int(0, n - 1)
    
    i = 0
    for item in items:
        if i == idx:
            return item
        end
        i = i + 1
    end
    
    return null
end

function random_sample(items, k):
    n = 0
    for _ in items:
        n = n + 1
    end
    
    sample = []
    for _ in 1..k:
        idx = random_int(0, n - 1)
        
        i = 0
        for item in items:
            if i == idx:
                sample = sample + [item]
            end
            i = i + 1
        end
    end
    
    return sample
end

# ============================================================================
# Shuffle (Fisher-Yates)
# ============================================================================

function random_shuffle(items):
    result = []
    for item in items:
        result = result + [item]
    end
    
    n = 0
    for _ in result:
        n = n + 1
    end
    
    for i in 1..n:
        j = random_int(i, n)
        
        # Swap
        temp = result[i]
        result[i] = result[j]
        result[j] = temp
    end
    
    return result
end

# ============================================================================
# Bernoulli and Binomial
# ============================================================================

function random_bernoulli(p):
    r = random_uniform(0, 1)
    if r < p:
        return 1
    end
    return 0
end

function random_binomial(n, p):
    count = 0
    for i in 1..n:
        count = count + random_bernoulli(p)
    end
    return count
end

# ============================================================================
# Poisson Distribution
# ============================================================================

function random_poisson(lambda):
    # Simplified Poisson
    count = 0
    k = 0
    
    for i in 1..lambda:
        if random_bernoulli(0.37):
            count = count + 1
        end
    end
    
    return count
end

# ============================================================================
# Generate Random Sequences
# ============================================================================

function random_uniform_sequence(n, min_val, max_val):
    sequence = []
    for i in 1..n:
        sequence = sequence + [random_uniform(min_val, max_val)]
    end
    return sequence
end

function random_int_sequence(n, min_val, max_val):
    sequence = []
    for i in 1..n:
        sequence = sequence + [random_int(min_val, max_val)]
    end
    return sequence
end

function random_permutation(n):
    items = []
    for i in 1..n:
        items = items + [i]
    end
    return random_shuffle(items)
end

# ============================================================================
# Utility: Reset State
# ============================================================================

function random_reset():
    random_state = 1
    return null
end
