# LSL Algorithms Library
# Základní algoritmy - řazení, vyhledávání, manipulace seznamy

# ============================================================================
# Sorting - Bubble Sort
# ============================================================================

function algo_bubble_sort(data):
    result = []
    for x in data:
        result = result + [x]
    end
    
    n = 0
    for _ in result:
        n = n + 1
    end
    
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

# ============================================================================
# Sorting - Selection Sort
# ============================================================================

function algo_selection_sort(data):
    result = []
    for x in data:
        result = result + [x]
    end
    
    n = 0
    for _ in result:
        n = n + 1
    end
    
    for i in 1..(n - 1):
        min_idx = i
        
        for j in (i + 1)..n:
            if result[j] < result[min_idx]:
                min_idx = j
            end
        end
        
        if min_idx != i:
            temp = result[i]
            result[i] = result[min_idx]
            result[min_idx] = temp
        end
    end
    
    return result
end

# ============================================================================
# Sorting - Insertion Sort
# ============================================================================

function algo_insertion_sort(data):
    result = []
    for x in data:
        result = result + [x]
    end
    
    n = 0
    for _ in result:
        n = n + 1
    end
    
    for i in 2..n:
        key = result[i]
        j = i - 1
        
        for _j in 1..j:
            if result[j] > key:
                result[j + 1] = result[j]
                j = j - 1
            end
        end
        
        result[j + 1] = key
    end
    
    return result
end

# ============================================================================
# Searching - Linear Search
# ============================================================================

function algo_linear_search(data, target):
    i = 0
    for x in data:
        if x == target:
            return i
        end
        i = i + 1
    end
    return -1
end

# ============================================================================
# Searching - Binary Search
# ============================================================================

function algo_binary_search(sorted_data, target):
    left = 0
    n = 0
    for _ in sorted_data:
        n = n + 1
    end
    right = n - 1
    
    for _ in 1..(n + 1):
        if left > right:
            return -1
        end
        
        mid = (left + right) / 2
        mid_val = sorted_data[mid]
        
        if mid_val == target:
            return mid
        end
        if mid_val < target:
            left = mid + 1
        end
        if mid_val > target:
            right = mid - 1
        end
    end
    
    return -1
end

# ============================================================================
# Unique Elements
# ============================================================================

function algo_unique(data):
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
# Remove Duplicates (in-place modification)
# ============================================================================

function algo_remove_duplicates(data):
    result = []
    
    for x in data:
        found = 0
        for r in result:
            if r == x:
                found = 1
            end
        end
        
        if found == 0:
            result = result + [x]
        end
    end
    
    return result
end

# ============================================================================
# Reverse
# ============================================================================

function algo_reverse(data):
    result = []
    n = 0
    for _ in data:
        n = n + 1
    end
    
    for i in 1..n:
        result = result + [data[n - i + 1]]
    end
    
    return result
end

# ============================================================================
# Rotate
# ============================================================================

function algo_rotate_left(data, k):
    n = 0
    for _ in data:
        n = n + 1
    end
    
    k = k % n
    
    result = []
    for i in 1..n:
        new_idx = ((i - 1 + k) % n) + 1
        result = result + [data[new_idx]]
    end
    
    return result
end

function algo_rotate_right(data, k):
    return algo_rotate_left(data, (0 - k))
end

# ============================================================================
# Chunk/Batch
# ============================================================================

function algo_chunk(data, chunk_size):
    chunks = []
    chunk = []
    
    for x in data:
        chunk = chunk + [x]
        
        count = 0
        for _ in chunk:
            count = count + 1
        end
        
        if count == chunk_size:
            chunks = chunks + [chunk]
            chunk = []
        end
    end
    
    if chunk:
        chunks = chunks + [chunk]
    end
    
    return chunks
end

# ============================================================================
# Flatten
# ============================================================================

function algo_flatten(data):
    result = []
    
    for item in data:
        if item:
            for sub_item in item:
                result = result + [sub_item]
            end
        end
    end
    
    return result
end

# ============================================================================
# Map, Filter, Reduce operations
# ============================================================================

function algo_sum(data):
    total = 0
    for x in data:
        total = total + x
    end
    return total
end

function algo_product(data):
    prod = 1
    for x in data:
        prod = prod * x
    end
    return prod
end

function algo_count(data):
    count = 0
    for _ in data:
        count = count + 1
    end
    return count
end

# ============================================================================
# Subarray operations
# ============================================================================

function algo_subarray(data, start, end):
    result = []
    
    i = 0
    for x in data:
        if (i >= start) and (i < end):
            result = result + [x]
        end
        i = i + 1
    end
    
    return result
end

function algo_slice(data, start, length):
    return algo_subarray(data, start, start + length)
end

# ============================================================================
# Merge two sorted arrays
# ============================================================================

function algo_merge_sorted(a, b):
    result = []
    i = 0
    j = 0
    
    n_a = 0
    for _ in a:
        n_a = n_a + 1
    end
    
    n_b = 0
    for _ in b:
        n_b = n_b + 1
    end
    
    for _ in 1..(n_a + n_b):
        if i >= n_a:
            result = result + [b[j]]
            j = j + 1
        end
        if j >= n_b:
            result = result + [a[i]]
            i = i + 1
        end
        if (i < n_a) and (j < n_b):
            if a[i] <= b[j]:
                result = result + [a[i]]
                i = i + 1
            end
            if a[i] > b[j]:
                result = result + [b[j]]
                j = j + 1
            end
        end
    end
    
    return result
end

# ============================================================================
# All, Any operations
# ============================================================================

function algo_all_true(conditions):
    for c in conditions:
        if not c:
            return 0
        end
    end
    return 1
end

function algo_any_true(conditions):
    for c in conditions:
        if c:
            return 1
        end
    end
    return 0
end

# ============================================================================
# Zip (combine two arrays)
# ============================================================================

function algo_zip(a, b):
    result = []
    i = 0
    
    for x in a:
        result = result + [[x, b[i]]]
        i = i + 1
    end
    
    return result
end

# ============================================================================
# Range generator
# ============================================================================

function algo_range(start, end):
    result = []
    
    for i in start..end:
        result = result + [i]
    end
    
    return result
end

function algo_range_step(start, end, step):
    result = []
    i = start
    
    for _ in 1..(end - start):
        result = result + [i]
        i = i + step
    end
    
    return result
end

# ============================================================================
# Group By (simplified)
# ============================================================================

function algo_group_by_mod(data, n):
    groups = []
    
    for _ in 1..n:
        group = []
        groups = groups + [group]
    end
    
    i = 0
    for x in data:
        mod = x % n
        if mod < 0:
            mod = mod + n
        end
        groups[mod] = groups[mod] + [x]
        i = i + 1
    end
    
    return groups
end

# ============================================================================
# Find operations
# ============================================================================

function algo_find_first(data, predicate_val):
    for x in data:
        if x == predicate_val:
            return x
        end
    end
    return null
end

function algo_find_last(data, predicate_val):
    last = null
    for x in data:
        if x == predicate_val:
            last = x
        end
    end
    return last
end

function algo_find_all(data, predicate_val):
    result = []
    for x in data:
        if x == predicate_val:
            result = result + [x]
        end
    end
    return result
end
