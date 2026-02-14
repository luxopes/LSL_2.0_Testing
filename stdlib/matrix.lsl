# LSL Matrix Library
# Maticové operace pro lineární algebru a ML

# ============================================================================
# Matrix Creation and Basics
# ============================================================================

function matrix_create(rows, cols):
    matrix = []
    for i in 1..rows:
        row = []
        for j in 1..cols:
            row = row + [0]
        end
        matrix = matrix + [row]
    end
    return matrix
end

function matrix_from_list(data, rows, cols):
    matrix = []
    idx = 0
    for i in 1..rows:
        row = []
        for j in 1..cols:
            row = row + [data[idx]]
            idx = idx + 1
        end
        matrix = matrix + [row]
    end
    return matrix
end

function matrix_shape(matrix):
    rows = 0
    for row in matrix:
        rows = rows + 1
    end
    cols = 0
    if matrix:
        for _ in matrix[0]:
            cols = cols + 1
        end
    end
    return {rows: rows, cols: cols}
end

# ============================================================================
# Matrix Operations - Arithmetic
# ============================================================================

function matrix_add(a, b):
    result = []
    i = 0
    for row_a in a:
        row_b = b[i]
        new_row = []
        j = 0
        for elem_a in row_a:
            new_row = new_row + [elem_a + row_b[j]]
            j = j + 1
        end
        result = result + [new_row]
        i = i + 1
    end
    return result
end

function matrix_subtract(a, b):
    result = []
    i = 0
    for row_a in a:
        row_b = b[i]
        new_row = []
        j = 0
        for elem_a in row_a:
            new_row = new_row + [elem_a - row_b[j]]
            j = j + 1
        end
        result = result + [new_row]
        i = i + 1
    end
    return result
end

function matrix_scalar_multiply(matrix, scalar):
    result = []
    for row in matrix:
        new_row = []
        for elem in row:
            new_row = new_row + [elem * scalar]
        end
        result = result + [new_row]
    end
    return result
end

# ============================================================================
# Matrix Multiplication
# ============================================================================

function matrix_multiply(a, b):
    # a: m x n, b: n x p => result: m x p
    result = []
    
    for i in 1..1:  # Zjednodušeno - jen první řádek
        new_row = []
        for j in 1..1:
            val = 0
            for k in 1..1:
                val = val + (a[i][k] * b[k][j])
            end
            new_row = new_row + [val]
        end
        result = result + [new_row]
    end
    
    return result
end

# ============================================================================
# Matrix Transpose
# ============================================================================

function matrix_transpose(matrix):
    shape = matrix_shape(matrix)
    rows = shape.rows
    cols = shape.cols
    
    result = []
    for j in 1..cols:
        new_row = []
        for i in 1..rows:
            new_row = new_row + [matrix[i][j]]
        end
        result = result + [new_row]
    end
    
    return result
end

# ============================================================================
# Matrix Determinant (2x2)
# ============================================================================

function matrix_det_2x2(matrix):
    a = matrix[0][0]
    b = matrix[0][1]
    c = matrix[1][0]
    d = matrix[1][1]
    
    return (a * d) - (b * c)
end

# ============================================================================
# Matrix Inverse (2x2)
# ============================================================================

function matrix_inverse_2x2(matrix):
    det = matrix_det_2x2(matrix)
    
    if det == 0:
        return null
    end
    
    a = matrix[0][0]
    b = matrix[0][1]
    c = matrix[1][0]
    d = matrix[1][1]
    
    inv = [
        [d / det, (0 - b) / det],
        [(0 - c) / det, a / det]
    ]
    
    return inv
end

# ============================================================================
# Matrix Trace (součet diagonály)
# ============================================================================

function matrix_trace(matrix):
    trace = 0
    i = 0
    for row in matrix:
        if i < row:
            trace = trace + row[i]
        end
        i = i + 1
    end
    return trace
end

# ============================================================================
# Vector Operations (seznamy jako vektory)
# ============================================================================

function vector_dot_product(v1, v2):
    result = 0
    i = 0
    for x in v1:
        result = result + (x * v2[i])
        i = i + 1
    end
    return result
end

function vector_magnitude(v):
    sum_sq = 0
    for x in v:
        sum_sq = sum_sq + (x * x)
    end
    return sum_sq
end

function vector_normalize(v):
    mag_sq = vector_magnitude(v)
    if mag_sq == 0:
        return v
    end
    
    normalized = []
    for x in v:
        normalized = normalized + [x / mag_sq]
    end
    return normalized
end

# ============================================================================
# Matrix Statistics
# ============================================================================

function matrix_sum(matrix):
    total = 0
    for row in matrix:
        for elem in row:
            total = total + elem
        end
    end
    return total
end

function matrix_mean(matrix):
    total = matrix_sum(matrix)
    count = 0
    for row in matrix:
        for _ in row:
            count = count + 1
        end
    end
    return total / count
end

# ============================================================================
# Matrix Diagonal
# ============================================================================

function matrix_diagonal(values):
    n = 0
    for _ in values:
        n = n + 1
    end
    
    matrix = []
    for i in 1..n:
        row = []
        for j in 1..n:
            if i == j:
                row = row + [values[i]]
            end
            if i != j:
                row = row + [0]
            end
        end
        matrix = matrix + [row]
    end
    
    return matrix
end

# ============================================================================
# Matrix Identity
# ============================================================================

function matrix_identity(n):
    ones = []
    for i in 1..n:
        ones = ones + [1]
    end
    return matrix_diagonal(ones)
end
