# LSL String Library

function contains(text, substring):
    if substring == "":
        return true
    end
    i = 0
    while i <= len(text) - len(substring):
        j = 0
        match = true
        while j < len(substring):
            if text[i + j] != substring[j]:
                match = false
                break
            end
            j = j + 1
        end
        if match:
            return true
        end
        i = i + 1
    end
    return false
end

function startswith(text, prefix):
    if len(prefix) > len(text):
        return false
    end
    i = 0
    while i < len(prefix):
        if text[i] != prefix[i]:
            return false
        end
        i = i + 1
    end
    return true
end

function endswith(text, suffix):
    if len(suffix) > len(text):
        return false
    end
    start = len(text) - len(suffix)
    i = 0
    while i < len(suffix):
        if text[start + i] != suffix[i]:
            return false
        end
        i = i + 1
    end
    return true
end

function replace_all(text, old, replacement):
    return replace(text, old, replacement)
end

function to_upper(text):
    return upper(text)
end

function to_lower(text):
    return lower(text)
end

function trim_all(text):
    return trim(text)
end

function split_by(text, sep):
    return split(text, sep)
end

function repeat(text, n):
    result = ""
    i = 0
    while i < n:
        result = result + text
        i = i + 1
    end
    return result
end
