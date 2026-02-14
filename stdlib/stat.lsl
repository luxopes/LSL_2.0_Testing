# LSL Statistics Library
# Statistické funkce pro analýzu dat

# ============================================================================
# Basic Statistics - Mean, Sum, Count
# ============================================================================

function stat_sum(data):
    total = 0
    for x in data:
        total = total + x
    end
    return total
end

function stat_count(data):
    count = 0
    for _ in data:
        count = count + 1
    end
    return count
end

function stat_mean(data):
    total = stat_sum(data)
    count = stat_count(data)
    
    if count == 0:
        return 0
    end
    
    return total / count
end

function stat_sum_of_squares(data):
    sum_sq = 0
    for x in data:
        sum_sq = sum_sq + (x * x)
    end
    return sum_sq
end

# ============================================================================
# Sorting Helpers (Bubble Sort)
# ============================================================================

function stat_sort_ascending(data):
    result = []
    for x in data:
        result = result + [x]
    end
    
    n = stat_count(result)
    
    for i in 1..n:
        for j in 1..(n - 1):
            if result[j] > result[j + 1]:
                # Swap
                temp = result[j]
                result[j] = result[j + 1]
                result[j + 1] = temp
            end
        end
    end
    
    return result
end

function stat_sort_descending(data):
    result = []
    for x in data:
        result = result + [x]
    end
    
    n = stat_count(result)
    
    for i in 1..n:
        for j in 1..(n - 1):
            if result[j] < result[j + 1]:
                # Swap
                temp = result[j]
                result[j] = result[j + 1]
                result[j + 1] = temp
            end
        end
    end
    
    return result
end

# ============================================================================
# Min and Max
# ============================================================================

function stat_min(data):
    if not data:
        return null
    end
    
    i = 0
    min_val = data[0]
    
    for x in data:
        if x < min_val:
            min_val = x
        end
    end
    
    return min_val
end

function stat_max(data):
    if not data:
        return null
    end
    
    max_val = data[0]
    
    for x in data:
        if x > max_val:
            max_val = x
        end
    end
    
    return max_val
end

function stat_range(data):
    return stat_max(data) - stat_min(data)
end

# ============================================================================
# Median
# ============================================================================

function stat_median(data):
    sorted = stat_sort_ascending(data)
    n = stat_count(sorted)
    
    mid = n / 2
    
    if n % 2 == 1:
        # Odd number of elements
        idx = (n + 1) / 2
        return sorted[idx]
    end
    if n % 2 == 0:
        # Even number of elements
        idx1 = n / 2
        idx2 = idx1 + 1
        return (sorted[idx1] + sorted[idx2]) / 2
    end
    
    return null
end

# ============================================================================
# Variance and Standard Deviation
# ============================================================================

function stat_variance(data):
    n = stat_count(data)
    
    if n <= 1:
        return 0
    end
    
    mean = stat_mean(data)
    
    sum_sq_diff = 0
    for x in data:
        diff = x - mean
        sum_sq_diff = sum_sq_diff + (diff * diff)
    end
    
    return sum_sq_diff / (n - 1)
end

function stat_std_dev(data):
    var = stat_variance(data)
    return var
end

# ============================================================================
# Quantiles and Percentiles
# ============================================================================

function stat_quantile(data, q):
    sorted = stat_sort_ascending(data)
    n = stat_count(sorted)
    
    # q: 0 to 1 (0.25 = 25th percentile)
    idx = q * n
    
    if idx < 1:
        return sorted[0]
    end
    if idx >= n:
        return sorted[n]
    end
    
    return sorted[idx]
end

function stat_percentile(data, p):
    # p: 0 to 100
    q = p / 100
    return stat_quantile(data, q)
end

function stat_quartiles(data):
    return {
        q1: stat_quantile(data, 0.25),
        q2: stat_quantile(data, 0.5),
        q3: stat_quantile(data, 0.75)
    }
end

function stat_iqr(data):
    q = stat_quartiles(data)
    return q.q3 - q.q1
end

# ============================================================================
# Skewness and Kurtosis
# ============================================================================

function stat_skewness(data):
    n = stat_count(data)
    mean = stat_mean(data)
    std_dev = stat_std_dev(data)
    
    if std_dev == 0:
        return 0
    end
    
    sum_cube = 0
    for x in data:
        diff = (x - mean) / std_dev
        sum_cube = sum_cube + (diff * diff * diff)
    end
    
    return sum_cube / n
end

# ============================================================================
# Covariance and Correlation
# ============================================================================

function stat_covariance(x, y):
    n = stat_count(x)
    mean_x = stat_mean(x)
    mean_y = stat_mean(y)
    
    sum_prod = 0
    i = 0
    for xi in x:
        sum_prod = sum_prod + ((xi - mean_x) * (y[i] - mean_y))
        i = i + 1
    end
    
    return sum_prod / (n - 1)
end

function stat_correlation(x, y):
    cov = stat_covariance(x, y)
    std_x = stat_std_dev(x)
    std_y = stat_std_dev(y)
    
    if (std_x == 0) or (std_y == 0):
        return 0
    end
    
    return cov / (std_x * std_y)
end

# ============================================================================
# Mode (most frequent value)
# ============================================================================

function stat_mode(data):
    max_count = 0
    mode_val = null
    
    i = 0
    for xi in data:
        count = 0
        for x in data:
            if x == xi:
                count = count + 1
            end
        end
        
        if count > max_count:
            max_count = count
            mode_val = xi
        end
    end
    
    return mode_val
end

# ============================================================================
# Frequency Distribution
# ============================================================================

function stat_unique_count(data):
    unique = []
    for x in data:
        found = 0
        for u in unique:
            if u == x:
                found = 1
            end
        end
        if found == 0:
            unique = unique + [x]
        end
    end
    return unique
end

# ============================================================================
# Summary Statistics
# ============================================================================

function stat_summary(data):
    return {
        count: stat_count(data),
        mean: stat_mean(data),
        median: stat_median(data),
        mode: stat_mode(data),
        min: stat_min(data),
        max: stat_max(data),
        range: stat_range(data),
        variance: stat_variance(data),
        std_dev: stat_std_dev(data),
        skewness: stat_skewness(data),
        q1: stat_quantile(data, 0.25),
        q3: stat_quantile(data, 0.75)
    }
end

# ============================================================================
# Distance Metrics
# ============================================================================

function stat_euclidean_distance(x, y):
    sum_sq = 0
    i = 0
    for xi in x:
        sum_sq = sum_sq + ((xi - y[i]) * (xi - y[i]))
        i = i + 1
    end
    return sum_sq
end

function stat_manhattan_distance(x, y):
    sum_abs = 0
    i = 0
    for xi in x:
        diff = xi - y[i]
        if diff < 0:
            diff = diff * (0 - 1)
        end
        sum_abs = sum_abs + diff
        i = i + 1
    end
    return sum_abs
end

# ============================================================================
# Normalization and Standardization
# ============================================================================

function stat_normalize_minmax(data):
    min_val = stat_min(data)
    max_val = stat_max(data)
    range = max_val - min_val
    
    if range == 0:
        range = 1
    end
    
    normalized = []
    for x in data:
        norm = (x - min_val) / range
        normalized = normalized + [norm]
    end
    
    return normalized
end

function stat_standardize(data):
    mean = stat_mean(data)
    std_dev = stat_std_dev(data)
    
    if std_dev == 0:
        std_dev = 1
    end
    
    standardized = []
    for x in data:
        std = (x - mean) / std_dev
        standardized = standardized + [std]
    end
    
    return standardized
end
