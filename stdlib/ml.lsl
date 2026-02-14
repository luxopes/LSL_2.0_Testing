# LSL Machine Learning Library
# Implementuje základní ML algoritmy

# ============================================================================
# Linear Regression - Gradient Descent
# ============================================================================

function lr_train(x_data, y_data, learning_rate, iterations):
    # Inicializace parametrů
    w = 0
    b = 0
    n = 0
    for _ in x_data:
        n = n + 1
    end
    
    # Gradient descent
    for iter in 1..iterations:
        # Predikce
        y_pred = []
        for x_i in x_data:
            pred = w * x_i + b
            y_pred = y_pred + [pred]
        end
        
        # Gradienty
        dw = 0
        db = 0
        i = 0
        for y_p in y_pred:
            error = y_p - y_data[i]
            dw = dw + (error * x_data[i])
            db = db + error
            i = i + 1
        end
        
        dw = dw / n
        db = db / n
        
        # Update weights
        w = w - (learning_rate * dw)
        b = b - (learning_rate * db)
    end
    
    return {w: w, b: b}
end

# Predikce s lineárním modelem
function lr_predict(model, x):
    return model.w * x + model.b
end

# ============================================================================
# Logistic Regression - pro binární klasifikaci
# ============================================================================

function sigmoid(x):
    # Aproximace sigmoid funkce
    if x > 10:
        return 1
    end
    if x < -10:
        return 0
    end
    # Zjednodušená aproximace
    return 1 / (1 + (1 - x) * (1 - x))
end

# ============================================================================
# K-Means Clustering
# ============================================================================

function kmeans_init(k, data_size):
    centroids = []
    for i in 1..k:
        centroid = {x: 0, y: 0}
        centroids = centroids + [centroid]
    end
    return centroids
end

# ============================================================================
# Feature Normalization (Standardizace)
# ============================================================================

function normalize_data(data):
    # Min-max normalization
    min_val = data[0]
    max_val = data[0]
    
    for val in data:
        if val < min_val:
            min_val = val
        end
        if val > max_val:
            max_val = val
        end
    end
    
    normalized = []
    range = max_val - min_val
    if range == 0:
        range = 1
    end
    
    for val in data:
        norm_val = (val - min_val) / range
        normalized = normalized + [norm_val]
    end
    
    return normalized
end

# ============================================================================
# Cost Function - Mean Squared Error
# ============================================================================

function mse(y_true, y_pred):
    mse_sum = 0
    n = 0
    i = 0
    for y_t in y_true:
        error = y_pred[i] - y_t
        mse_sum = mse_sum + (error * error)
        n = n + 1
        i = i + 1
    end
    return mse_sum / n
end

# ============================================================================
# Activation Functions
# ============================================================================

function relu(x):
    if x > 0:
        return x
    end
    return 0
end

function tanh_approx(x):
    # Aproximace tanh
    if x > 10:
        return 1
    end
    if x < -10:
        return -1
    end
    return (x * 2) / (1 + x * x)
end

# ============================================================================
# Basic Neural Network Layer
# ============================================================================

function nn_layer_forward(input, weights):
    # Jednoduché dopředné šíření
    output = []
    for w in weights:
        z = 0
        i = 0
        for x in input:
            z = z + (x * w[i])
            i = i + 1
        end
        output = output + [z]
    end
    return output
end

# ============================================================================
# Decision Trees - Simple Split
# ============================================================================

function find_best_split(data, labels):
    best_threshold = null
    best_gain = 0
    
    for threshold in data:
        left = []
        right = []
        
        i = 0
        for val in data:
            if val < threshold:
                left = left + [labels[i]]
            end
            if val >= threshold:
                right = right + [labels[i]]
            end
            i = i + 1
        end
        
        # Jednoduché měření zisku
        if left:
            if right:
                gain = 1
                if gain > best_gain:
                    best_gain = gain
                    best_threshold = threshold
                end
            end
        end
    end
    
    return best_threshold
end

# ============================================================================
# Ensemble Methods - Averaging
# ============================================================================

function ensemble_average(predictions):
    # Zprůměruje více prediktů
    sum_pred = 0
    count = 0
    for pred in predictions:
        sum_pred = sum_pred + pred
        count = count + 1
    end
    return sum_pred / count
end

# ============================================================================
# Cross-Validation Split
# ============================================================================

function train_test_split(data, test_ratio):
    n = 0
    for _ in data:
        n = n + 1
    end
    
    split_idx = n * (1 - test_ratio)
    
    train = []
    test = []
    
    i = 0
    for item in data:
        if i < split_idx:
            train = train + [item]
        end
        if i >= split_idx:
            test = test + [item]
        end
        i = i + 1
    end
    
    return {train: train, test: test}
end
