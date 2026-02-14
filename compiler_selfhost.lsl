# =============================================================================
# LSL Self-Hosting Compiler (Stage 3)
# =============================================================================
# 
# A complete self-hosted LSL (Little Scripting Language) compiler that targets
# x86-64 ELF binaries for Linux and LuxOS baremetal LXB format.
#
# FEATURES:
# - Complete LSL language parser with expression evaluation
# - Code generation for x86-64 with tagged value system
# - Low-level OS/GUI builtins for system programming
# - CLI argument parsing with request-file fallback mechanism
# - Module system with 'use' statements and standard library support
# - Error reporting with source location and helpful messages
#
# ARCHITECTURE:
# - Frontend: Tokenizer → Parser → AST
# - Backend: AST → x86-64 code generation
# - Runtime: Tagged value system with garbage collection
#
# TAGGED VALUE SYSTEM:
# - All values are 64-bit tagged pointers/constants
# - TAG_INT=1, TAG_BOOL=2, TAG_NULL=3, TAG_STR=4, TAG_LIST=5
# - Pointers have lower 3 bits cleared, constants have tag in lower bits
#
# USAGE:
#   lsl compiler_selfhost.lsl program.lsl -o output
#
# =============================================================================
# Runtime code generation globals
rt_code = ""
rt_fixups = []
rt_labels = []
rt_var_map = []
rt_var_names = []
rt_strings = []
rt_label_counter = 0
__argc = 0
__args = []
# Tagged value layout
TAG_INT = 1
TAG_BOOL = 2
TAG_NULL = 3
TAG_STR = 4
TAG_LIST = 5
LABEL_ALPH = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Integer division with truncation (handles negative numbers correctly)
function idiv(n, d):
    return (n - (n % d)) / d
end

# Convert integer to unsigned 8-bit value (0-255)
function u8(n):
    return chr(n)
end

# Convert integer to unsigned 16-bit little-endian bytes
function u16le(n):
    u16_b0 = n % 256
    u16_b1 = idiv(n, 256) % 256
    return chr(u16_b0) + chr(u16_b1)
end

# Convert integer to unsigned 32-bit little-endian bytes
function u32le(n):
    u32_b0 = n % 256
    u32_b1 = idiv(n, 256) % 256
    u32_b2 = idiv(n, 65536) % 256
    u32_b3 = idiv(n, 16777216) % 256
    return chr(u32_b0) + chr(u32_b1) + chr(u32_b2) + chr(u32_b3)
end

# Convert integer to unsigned 64-bit little-endian bytes
function u64le(n):
    u64_lo = n % 4294967296
    u64_hi = idiv(n, 4294967296)
    return u32le(u64_lo) + u32le(u64_hi)
end
function bb_new():
    return [lb_new(), [], 0]
end
function bb_add(bb, s):
    BB_BLOCK = 256
    blocks = bb[0]
    block = bb[1]
    total = bb[2] + len(s)
    block = block + [s]
    if len(block) >= BB_BLOCK:
        blocks = lb_add(blocks, block)
        block = []
    end
    return [blocks, block, total]
end
function bb_len(bb):
    return bb[2]
end
function bb_join_list(parts):
    if len(parts) == 0:
        return ""
    end
    cur = parts
    while len(cur) > 1:
        next = lb_new()
        i = 0
        while i < len(cur):
            if i + 1 < len(cur):
                next = lb_add(next, cur[i] + cur[i + 1])
                i = i + 2
            else:
                next = lb_add(next, cur[i])
                i = i + 1
            end
        end
        cur = lb_to_list(next)
    end
    return cur[0]
end
function list_join_list(parts):
    if len(parts) == 0:
        return []
    end
    cur = parts
    while len(cur) > 1:
        next = lb_new()
        i = 0
        while i < len(cur):
            if i + 1 < len(cur):
                next = lb_add(next, cur[i] + cur[i + 1])
                i = i + 2
            else:
                next = lb_add(next, cur[i])
                i = i + 1
            end
        end
        cur = lb_to_list(next)
    end
    return cur[0]
end
function bb_to_string(bb):
    blocks = lb_to_list(bb[0])
    if len(bb[1]) > 0:
        blocks = blocks + [bb[1]]
    end
    if len(blocks) == 0:
        return ""
    end
    block_strings = lb_new()
    bi = 0
    loop len(blocks):
        block_strings = lb_add(block_strings, bb_join_list(blocks[bi]))
        bi = bi + 1
    end
    return bb_join_list(lb_to_list(block_strings))
end
function hex_val(ch):
    v = find_char("0123456789", ch, 0)
    if v >= 0:
        return v
    end
    v = find_char("abcdef", ch, 0)
    if v >= 0:
        return 10 + v
    end
    v = find_char("ABCDEF", ch, 0)
    if v >= 0:
        return 10 + v
    end
    return 0
end
function hex_to_bytes(hex):
    hb = bb_new()
    hi = 0
    hn = len(hex)
    while hi + 1 < hn:
        v = hex_val(hex[hi]) * 16 + hex_val(hex[hi + 1])
        hb = bb_add(hb, u8(v))
        hi = hi + 2
    end
    return bb_to_string(hb)
end
function lb_new():
    return [[], [], 0]
end
function lb_add(lb, value):
    LB_BLOCK = 1024
    blocks = lb[0]
    block = lb[1]
    count = lb[2] + 1
    block = block + [value]
    if len(block) >= LB_BLOCK:
        blocks = blocks + [block]
        block = []
    end
    return [blocks, block, count]
end
function lb_len(lb):
    return lb[2]
end
function lb_to_list(lb):
    blocks = lb[0]
    if len(lb[1]) > 0:
        blocks = blocks + [lb[1]]
    end
    if len(blocks) == 0:
        return []
    end
    return list_join_list(blocks)
end
function substr(s, start, count):
    if count <= 0:
        return ""
    end
    if count <= 64:
        sub_i = 0
        sub_out = ""
        loop count:
            sub_out = sub_out + s[start + sub_i]
            sub_i = sub_i + 1
        end
        return sub_out
    end
    sub_i = 0
    sub_out = bb_new()
    loop count:
        sub_out = bb_add(sub_out, s[start + sub_i])
        sub_i = sub_i + 1
    end
    return bb_to_string(sub_out)
end
function find_char(s, ch, start):
    fc_i = start
    fc_n = len(s)
    while fc_i < fc_n:
        if s[fc_i] == ch:
            return fc_i
        end
        fc_i = fc_i + 1
    end
    return -1
end
function find_substring(s, sub, start):
    fs_n = len(s)
    fs_m = len(sub)
    fs_i = start
    while fs_i + fs_m <= fs_n:
        fs_j = 0
        fs_ok = true
        loop fs_m:
            if s[fs_i + fs_j] != sub[fs_j]:
                fs_ok = false
            end
            fs_j = fs_j + 1
        end
        if fs_ok:
            return fs_i
        end
        fs_i = fs_i + 1
    end
    return -1
end
function is_space(ch):
    return find_char(" \t\r", ch, 0) >= 0
end
function is_digit(ch):
    return find_char("0123456789", ch, 0) >= 0
end
function is_letter(ch):
    return find_char("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_", ch, 0) >= 0
end
function is_alnum(ch):
    return find_char("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", ch, 0) >= 0
end
function parse_identifier_from(line, start):
    pid_n = len(line)
    if start < 0 or start >= pid_n:
        return ["", start, false]
    end
    if not is_letter(line[start]):
        return ["", start, false]
    end
    pid_i = start
    pid_out = ""
    while pid_i < pid_n and is_alnum(line[pid_i]):
        pid_out = pid_out + line[pid_i]
        pid_i = pid_i + 1
    end
    return [pid_out, pid_i, true]
end
function env_get(env_list, name):
    if len(env_list) > 0 and env_list[0][0] == "__bucket_env__!":
        return env_bucket_get(env_list, name)
    end
    eg_i = 0
    loop len(env_list):
        eg_pair = env_list[eg_i]
        if eg_pair[0] == name:
            return eg_pair[1]
        end
        eg_i = eg_i + 1
    end
    return ["missing", ""]
end
function env_set(env_list, name, value):
    if len(env_list) > 0 and env_list[0][0] == "__bucket_env__!":
        return env_bucket_set(env_list, name, value)
    end
    return [[name, value]] + env_list
end
function env_has(env_list, name):
    ev = env_get(env_list, name)
    return ev[0] != "missing"
end
function list_set(lst, idx, value):
    ls_out = lb_new()
    ls_i = 0
    loop len(lst):
        if ls_i == idx:
            ls_out = lb_add(ls_out, value)
        else:
            ls_out = lb_add(ls_out, lst[ls_i])
        end
        ls_i = ls_i + 1
    end
    return lb_to_list(ls_out)
end
function env_bucket_index(name):
    ALPH = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
    nlen = len(name)
    if nlen == 0:
        return 0
    end
    bi = find_char(ALPH, name[0], 0)
    if bi < 0:
        bi = 0
    end
    if nlen > 1:
        bi2 = find_char(ALPH, name[1], 0)
        if bi2 < 0:
            bi2 = 0
        end
        return (bi * 3 + bi2 + nlen) % len(ALPH)
    end
    return (bi + nlen) % len(ALPH)
end
function env_bucket_new():
    ALPH = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
    buckets = []
    bi = 0
    loop len(ALPH):
        buckets = buckets + [[]]
        bi = bi + 1
    end
    return [["__bucket_env__!", buckets]]
end
function env_bucket_get(env_list, name):
    buckets = env_list[0][1]
    idx = env_bucket_index(name)
    bucket = buckets[idx]
    bi = 0
    loop len(bucket):
        if bucket[bi][0] == name:
            return bucket[bi][1]
        end
        bi = bi + 1
    end
    return ["missing", ""]
end
function env_bucket_set(env_list, name, value):
    buckets = env_list[0][1]
    idx = env_bucket_index(name)
    bucket = buckets[idx]
    bucket = [[name, value]] + bucket
    buckets = list_set(buckets, idx, bucket)
    return [["__bucket_env__!", buckets]]
end
function label_bucket_index(name):
    LABEL_ALPH = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
    lb_n = len(name)
    if lb_n == 0:
        return 0
    end
    lb_i = find_char(LABEL_ALPH, name[0], 0)
    if lb_i < 0:
        lb_i = 0
    end
    if lb_n > 1:
        lb_i2 = find_char(LABEL_ALPH, name[1], 0)
        if lb_i2 < 0:
            lb_i2 = 0
        end
        return (lb_i * 3 + lb_i2 + lb_n) % len(LABEL_ALPH)
    end
    return (lb_i + lb_n) % len(LABEL_ALPH)
end
function labels_build_buckets(labels):
    LABEL_ALPH = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
    buckets = []
    bi = 0
    loop len(LABEL_ALPH):
        buckets = buckets + [[]]
        bi = bi + 1
    end
    li = 0
    loop len(labels):
        lb = labels[li]
        idx = label_bucket_index(lb[0])
        bucket = buckets[idx]
        bucket = [lb] + bucket
        buckets = list_set(buckets, idx, bucket)
        li = li + 1
    end
    return buckets
end
function label_get(buckets, name):
    idx = label_bucket_index(name)
    bucket = buckets[idx]
    bi = 0
    loop len(bucket):
        if bucket[bi][0] == name:
            return bucket[bi][1]
        end
        bi = bi + 1
    end
    return ["missing", ""]
end
function list_set(lst, idx, value):
    ls_out = lb_new()
    ls_i = 0
    loop len(lst):
        if ls_i == idx:
            ls_out = lb_add(ls_out, value)
        else:
            ls_out = lb_add(ls_out, lst[ls_i])
        end
        ls_i = ls_i + 1
    end
    return lb_to_list(ls_out)
end
function list_pop(lst):
    lp_n = len(lst)
    if lp_n == 0:
        return [lst, ["null"], false]
    end
    lp_val = lst[lp_n - 1]
    lp_out = lb_new()
    lp_i = 0
    loop lp_n - 1:
        lp_out = lb_add(lp_out, lst[lp_i])
        lp_i = lp_i + 1
    end
    return [lb_to_list(lp_out), lp_val, true]
end
function int_to_string(n):
    if n == 0:
        return "0"
    end
    its_neg = false
    if n < 0:
        its_neg = true
        n = 0 - n
    end
    its_out = ""
    while n > 0:
        its_digit = n % 10
        its_out = chr(48 + its_digit) + its_out
        n = idiv(n, 10)
    end
    if its_neg:
        its_out = "-" + its_out
    end
    return its_out
end
function repeat_char(ch, count):
    rc_out = ""
    rc_i = 0
    while rc_i < count:
        rc_out = rc_out + ch
        rc_i = rc_i + 1
    end
    return rc_out
end
function tok_line(tok):
    if len(tok) >= 4:
        return tok[2]
    end
    return 0
end
function tok_col(tok):
    if len(tok) >= 4:
        return tok[3]
    end
    return 0
end
function line_meta(tokens):
    if len(tokens) > 0:
        m = tokens[0]
        if len(m) >= 4 and m[0] == "__line":
            return [m[1], m[2], m[3]]
        end
    end
    return ["", "", ""]
end
function pad_left(s, width):
    if len(s) >= width:
        return s
    end
    return repeat_char(" ", width - len(s)) + s
end
function format_error_block(code, title, path, line_no, col, line_text, prev_text, detail, hint, caret_len):
    if code == "":
        code = "E001"
    end
    if title == "":
        title = "Syntax Error"
    end
    if line_no < 1:
        line_no = 1
    end
    if col < 1:
        col = 1
    end
    if caret_len < 1:
        caret_len = 1
    end
    if path == "":
        path = "<input>"
    end
    sep = repeat_char("-", 57)
    out = "[ ERROR " + code + " ] " + title + "\n" + sep + "\n"
    out = out + "File: " + path + ":" + int_to_string(line_no) + ":" + int_to_string(col) + "\n\n"
    ln_width = len(int_to_string(line_no))
    prev_no = line_no - 1
    if prev_text != "" and prev_no > 0:
        if len(int_to_string(prev_no)) > ln_width:
            ln_width = len(int_to_string(prev_no))
        end
    end
    if prev_text != "" and prev_no > 0:
        out = out + pad_left(int_to_string(prev_no), ln_width) + " |  " + prev_text + "\n"
    end
    if line_text != "":
        out = out + pad_left(int_to_string(line_no), ln_width) + " |  " + line_text + "\n"
        out = out + repeat_char(" ", ln_width) + " |  " + repeat_char(" ", col - 1) + repeat_char("^", caret_len) + "\n"
        if detail != "":
            out = out + repeat_char(" ", ln_width) + " |  " + repeat_char(" ", col - 1) + detail + "\n"
        end
    end
    if hint != "":
        out = out + "\nHint: " + hint + "\n"
    end
    out = out + sep
    return out
end
function format_token_error(tokens, pos, msg):
    tok = tok_get(tokens, pos)
    line = tok_line(tok)
    col = tok_col(tok)
    meta = line_meta(tokens)
    line_text = meta[0]
    prev_text = meta[1]
    path = meta[2]
    return format_error_block("E001", "Syntax Error", path, line, col, line_text, prev_text, msg, "", 1)
end
function format_error_line(source, start, limit, line_no, col, msg):
    line_text = substr(source, start, limit - start)
    return format_error_block("E001", "Syntax Error", "", line_no, col, line_text, "", msg, "", 1)
end
function err_at(tokens, pos, msg):
    return format_token_error(tokens, pos, msg)
end
function progress(pct, msg):
    if pct < 0:
        pct = 0
    end
    if pct > 100:
        pct = 100
    end
    print "[" + int_to_string(pct) + "%] " + msg
end
function ltrim(s):
    lt_i = 0
    lt_n = len(s)
    while lt_i < lt_n and is_space(s[lt_i]):
        lt_i = lt_i + 1
    end
    return substr(s, lt_i, lt_n - lt_i)
end
function rtrim(s):
    rt_n = len(s)
    if rt_n == 0:
        return s
    end
    rt_i = rt_n - 1
    while rt_i >= 0:
        if is_space(s[rt_i]):
            rt_i = rt_i - 1
        else:
            break
        end
    end
    if rt_i < 0:
        return ""
    end
    return substr(s, 0, rt_i + 1)
end
function trim(s):
    return rtrim(ltrim(s))
end
function starts_with(s, prefix):
    if len(prefix) > len(s):
        return false
    end
    sw_i = 0
    loop len(prefix):
        if s[sw_i] != prefix[sw_i]:
            return false
        end
        sw_i = sw_i + 1
    end
    return true
end
function ends_with(s, suffix):
    if len(suffix) > len(s):
        return false
    end
    ew_i = 0
    ew_start = len(s) - len(suffix)
    loop len(suffix):
        if s[ew_start + ew_i] != suffix[ew_i]:
            return false
        end
        ew_i = ew_i + 1
    end
    return true
end
function strip_comment(line):
    sc_i = 0
    sc_n = len(line)
    sc_quote = ""
    while sc_i < sc_n:
        sc_c = line[sc_i]
        if sc_quote != "":
            if sc_c == "\\":
                sc_i = sc_i + 2
                continue
            end
            if sc_c == sc_quote:
                sc_quote = ""
            end
            sc_i = sc_i + 1
            continue
        end
        if sc_c == "\"" or sc_c == "'":
            sc_quote = sc_c
            sc_i = sc_i + 1
            continue
        end
        if sc_c == "#":
            return substr(line, 0, sc_i)
        end
        sc_i = sc_i + 1
    end
    return line
end
function parse_string_literal_range(source, start, limit):
    ps_n = limit
    if start < 0 or start >= ps_n:
        return ["", start, false, "invalid_start"]
    end
    ps_quote = source[start]
    if ps_quote != "\"" and ps_quote != "'":
        return ["", start, false, "invalid_start"]
    end
    ps_i = start + 1
    ps_out = ""
    ps_bb = bb_new()
    ps_use_bb = false
    ps_len = 0
    while ps_i < ps_n:
        ps_c = source[ps_i]
        if ps_c == "\\":
            ps_i = ps_i + 1
            if ps_i >= ps_n:
                return ["", ps_i, false, "incomplete_escape"]
            end
            ps_esc = source[ps_i]
            ps_ch = ps_esc
            if ps_esc == "n":
                ps_ch = "\n"
            elif ps_esc == "t":
                ps_ch = "\t"
            elif ps_esc == "r":
                ps_ch = "\r"
            elif ps_esc == "\"":
                ps_ch = "\""
            elif ps_esc == "'":
                ps_ch = "'"
            elif ps_esc == "\\":
                ps_ch = "\\"
            end
            if not ps_use_bb:
                ps_out = ps_out + ps_ch
                ps_len = ps_len + 1
                if ps_len > 64:
                    ps_bb = bb_add(ps_bb, ps_out)
                    ps_out = ""
                    ps_use_bb = true
                end
            else:
                ps_bb = bb_add(ps_bb, ps_ch)
                ps_len = ps_len + 1
            end
            ps_i = ps_i + 1
            continue
        end
        if ps_c == ps_quote:
            if ps_use_bb:
                if ps_out != "":
                    ps_bb = bb_add(ps_bb, ps_out)
                end
                return [bb_to_string(ps_bb), ps_i + 1, true, ""]
            end
            return [ps_out, ps_i + 1, true, ""]
        end
        if not ps_use_bb:
            ps_out = ps_out + ps_c
            ps_len = ps_len + 1
            if ps_len > 64:
                ps_bb = bb_add(ps_bb, ps_out)
                ps_out = ""
                ps_use_bb = true
            end
        else:
            ps_bb = bb_add(ps_bb, ps_c)
            ps_len = ps_len + 1
        end
        ps_i = ps_i + 1
    end
    return ["", ps_i, false, "unclosed_string"]
end
function parse_string_literal_from(line, start):
    return parse_string_literal_range(line, start, len(line))
end
function tok_make(type, value, line, col):
    return [type, value, line, col]
end
function tok_push(chunks, chunk, chunk_n, tok, chunk_size):
    chunk = chunk + [tok]
    chunk_n = chunk_n + 1
    if chunk_n >= chunk_size:
        chunks = chunks + [chunk]
        chunk = []
        chunk_n = 0
    end
    return [chunks, chunk, chunk_n]
end
function tokenize_range(source, start, limit, line_no, line_text, prev_text, path):
    tok_chunks = []
    tok_chunk = []
    tok_chunk_n = 0
    tok_chunk_size = 64
    tok_i = start
    tok_n = limit
    while tok_i < tok_n:
        tok_c = source[tok_i]
        if tok_c == " " or tok_c == "\t" or tok_c == "\r":
            tok_i = tok_i + 1
            continue
        end
        if tok_c == "\n":
            tok_col = (tok_i - start) + 1
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("newline", "\n", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == "#":
            tok_i = tok_i + 1
            while tok_i < tok_n and source[tok_i] != "\n":
                tok_i = tok_i + 1
            end
            continue
        end
        if tok_c == "\"" or tok_c == "'":
            tok_start = tok_i
            tok_col = (tok_start - start) + 1
            tok_res = parse_string_literal_range(source, tok_i, tok_n)
            tok_text = tok_res[0]
            tok_j = tok_res[1]
            tok_ok = tok_res[2]
            tok_reason = tok_res[3]
            if not tok_ok:
                if tok_reason == "unclosed_string":
                    caret_len = 3
                    if len(line_text) < caret_len:
                        caret_len = len(line_text)
                    end
                    if caret_len < 1:
                        caret_len = 1
                    end
                    err_col = len(line_text) - caret_len + 1
                    if err_col < 1:
                        err_col = 1
                    end
                    return [[], format_error_block("E002", "Unclosed String", path, line_no, err_col, line_text, prev_text, "Missing closing quote in string literal.", "To fix this error add closing quote.", caret_len)]
                end
                return [[], format_error_block("E003", "Invalid String", path, line_no, tok_col, line_text, prev_text, "Invalid escape or unterminated string.", "", 1)]
            end
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("str", tok_text, line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_j
            continue
        end
        if is_digit(tok_c):
            tok_start = tok_i
            tok_col = (tok_start - start) + 1
            tok_val = find_char("0123456789", tok_c, 0)
            tok_has_dot = false
            tok_i = tok_i + 1
            while tok_i < tok_n:
                tok_c2 = source[tok_i]
                if is_digit(tok_c2):
                    if not tok_has_dot:
                        tok_val = tok_val * 10 + find_char("0123456789", tok_c2, 0)
                    end
                    tok_i = tok_i + 1
                    continue
                end
                if tok_c2 == "." and not tok_has_dot:
                    if tok_i + 1 < tok_n and source[tok_i + 1] == ".":
                        break
                    end
                    tok_has_dot = true
                    tok_i = tok_i + 1
                    continue
                end
                break
            end
            if tok_has_dot:
                tok_num = substr(source, tok_start, tok_i - tok_start)
                tok_val = num(tok_num)
            end
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("num", tok_val, line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            continue
        end
        if is_letter(tok_c):
            tok_start = tok_i
            tok_col = (tok_start - start) + 1
            tok_i = tok_i + 1
            while tok_i < tok_n and is_alnum(source[tok_i]):
                tok_i = tok_i + 1
            end
            tok_id = substr(source, tok_start, tok_i - tok_start)
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("id", tok_id, line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            continue
        end
        if tok_c == "+":
            tok_col = (tok_i - start) + 1
            if tok_i + 1 < tok_n and source[tok_i + 1] == "=":
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("pluseq", "+=", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 2
                continue
            end
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("plus", "+", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == "-":
            tok_col = (tok_i - start) + 1
            if tok_i + 1 < tok_n and source[tok_i + 1] == "=":
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("minuseq", "-=", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 2
                continue
            end
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("minus", "-", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == "*":
            tok_col = (tok_i - start) + 1
            if tok_i + 1 < tok_n and source[tok_i + 1] == "=":
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("stareq", "*=", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 2
                continue
            end
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("star", "*", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == "/":
            tok_col = (tok_i - start) + 1
            if tok_i + 1 < tok_n and source[tok_i + 1] == "=":
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("slasheq", "/=", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 2
                continue
            end
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("slash", "/", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == "%":
            tok_col = (tok_i - start) + 1
            if tok_i + 1 < tok_n and source[tok_i + 1] == "=":
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("percenteq", "%=", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 2
                continue
            end
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("percent", "%", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == "=":
            if tok_i + 1 < tok_n and source[tok_i + 1] == "=":
                tok_col = (tok_i - start) + 1
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("eqeq", "==", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 2
            else:
                tok_col = (tok_i - start) + 1
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("eq", "=", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 1
            end
            continue
        end
        if tok_c == "!":
            if tok_i + 1 < tok_n and source[tok_i + 1] == "=":
                tok_col = (tok_i - start) + 1
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("neq", "!=", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 2
                continue
            end
            tok_col = (tok_i - start) + 1
            return [[], format_error_block("E004", "Unexpected Character", path, line_no, tok_col, line_text, prev_text, "Unexpected character: !", "", 1)]
        end
        if tok_c == "<":
            if tok_i + 1 < tok_n and source[tok_i + 1] == "=":
                tok_col = (tok_i - start) + 1
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("lte", "<=", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 2
            else:
                tok_col = (tok_i - start) + 1
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("lt", "<", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 1
            end
            continue
        end
        if tok_c == ">":
            if tok_i + 1 < tok_n and source[tok_i + 1] == "=":
                tok_col = (tok_i - start) + 1
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("gte", ">=", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 2
            else:
                tok_col = (tok_i - start) + 1
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("gt", ">", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 1
            end
            continue
        end
        if tok_c == ":":
            tok_col = (tok_i - start) + 1
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("colon", ":", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == ".":
            tok_col = (tok_i - start) + 1
            if tok_i + 1 < tok_n and source[tok_i + 1] == ".":
                tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("dotdot", "..", line_no, tok_col), tok_chunk_size)
                tok_chunks = tok_push_res[0]
                tok_chunk = tok_push_res[1]
                tok_chunk_n = tok_push_res[2]
                tok_i = tok_i + 2
                continue
            end
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("dot", ".", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == ",":
            tok_col = (tok_i - start) + 1
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("comma", ",", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == "(":
            tok_col = (tok_i - start) + 1
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("lparen", "(", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == ")":
            tok_col = (tok_i - start) + 1
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("rparen", ")", line_no, tok_col, line_text, prev_text, path), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == "[":
            tok_col = (tok_i - start) + 1
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("lbrack", "[", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == "]":
            tok_col = (tok_i - start) + 1
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("rbrack", "]", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == "{":
            tok_col = (tok_i - start) + 1
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("lbrace", "{", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        if tok_c == "}":
            tok_col = (tok_i - start) + 1
            tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("rbrace", "}", line_no, tok_col), tok_chunk_size)
            tok_chunks = tok_push_res[0]
            tok_chunk = tok_push_res[1]
            tok_chunk_n = tok_push_res[2]
            tok_i = tok_i + 1
            continue
        end
        tok_col = (tok_i - start) + 1
        return [[], format_error_block("E004", "Unexpected Character", path, line_no, tok_col, line_text, prev_text, "Unexpected character: " + tok_c, "", 1)]
    end
    tok_col = (limit - start) + 1
    if tok_col < 1:
        tok_col = 1
    end
    tok_push_res = tok_push(tok_chunks, tok_chunk, tok_chunk_n, tok_make("eof", "", line_no, tok_col), tok_chunk_size)
    tok_chunks = tok_push_res[0]
    tok_chunk = tok_push_res[1]
    tok_chunk_n = tok_push_res[2]
    if tok_chunk_n > 0:
        tok_chunks = tok_chunks + [tok_chunk]
    end
    if len(tok_chunks) == 0:
        return [[], ""]
    end
    return [list_join_list(tok_chunks), ""]
end
function tok_get(tokens, pos):
    offset = 0
    if len(tokens) > 0:
        head = tokens[0]
        if len(head) >= 1 and head[0] == "__line":
            offset = 1
        end
    end
    real_pos = pos + offset
    if real_pos >= len(tokens):
        if len(tokens) > offset:
            last = tokens[len(tokens) - 1]
            return ["eof", "", tok_line(last), tok_col(last)]
        end
        return ["eof", "", 0, 0]
    end
    return tokens[real_pos]
end
function split_line_ranges(source):
    sr_chunks = []
    sr_chunk = []
    sr_chunk_n = 0
    sr_chunk_size = 512
    sr_start = 0
    sr_i = 0
    sr_n = len(source)
    while sr_i < sr_n:
        if source[sr_i] == "\n":
            sr_chunk = sr_chunk + [[sr_start, sr_i]]
            sr_chunk_n = sr_chunk_n + 1
            if sr_chunk_n >= sr_chunk_size:
                sr_chunks = sr_chunks + [sr_chunk]
                sr_chunk = []
                sr_chunk_n = 0
            end
            sr_start = sr_i + 1
        end
        sr_i = sr_i + 1
    end
    if sr_start <= sr_n:
        sr_chunk = sr_chunk + [[sr_start, sr_n]]
        sr_chunk_n = sr_chunk_n + 1
    end
    if sr_chunk_n > 0:
        sr_chunks = sr_chunks + [sr_chunk]
    end
    if len(sr_chunks) == 0:
        return []
    end
    return list_join_list(sr_chunks)
end
function tokenize_ranges(source, ranges, source_path):
    tr_chunks = []
    tr_chunk = []
    tr_chunk_n = 0
    tr_chunk_size = 256
    line_no = 1
    prev_text = ""
    ti = 0
    loop len(ranges):
        r = ranges[ti]
        line_text = substr(source, r[0], r[1] - r[0])
        tok_res = tokenize_range(source, r[0], r[1], line_no, line_text, prev_text, source_path)
        if tok_res[1] != "":
            return [[], tok_res[1]]
        end
        line_tokens = [["__line", line_text, prev_text, source_path]] + tok_res[0]
        tr_chunk = tr_chunk + [line_tokens]
        tr_chunk_n = tr_chunk_n + 1
        if tr_chunk_n >= tr_chunk_size:
            tr_chunks = tr_chunks + [tr_chunk]
            tr_chunk = []
            tr_chunk_n = 0
        end
        prev_text = line_text
        ti = ti + 1
        line_no = line_no + 1
    end
    if tr_chunk_n > 0:
        tr_chunks = tr_chunks + [tr_chunk]
    end
    if len(tr_chunks) == 0:
        return [[], ""]
    end
    return [list_join_list(tr_chunks), ""]
end
function parse_program_stream(source, source_path):
    pps_ranges = split_line_ranges(source)
    tl = tokenize_ranges(source, pps_ranges, source_path)
    if tl[1] != "":
        return [[], tl[1]]
    end
    pps_res = parse_block_lines(tl[0], 0, ["<eof>"])
    if pps_res[2] != "":
        return [[], pps_res[2]]
    end
    return [pps_res[0], ""]
end
function path_is_abs(path):
    return len(path) > 0 and path[0] == "/"
end
function path_dirname(path):
    if path == "":
        return "."
    end
    i = len(path) - 1
    while i >= 0 and path[i] != "/":
        i = i - 1
    end
    if i < 0:
        return "."
    end
    if i == 0:
        return "/"
    end
    return substr(path, 0, i)
end
function path_join(base, rel):
    if rel == "":
        return base
    end
    if path_is_abs(rel):
        return rel
    end
    if base == "" or base == ".":
        return rel
    end
    if base[len(base) - 1] == "/":
        return base + rel
    end
    return base + "/" + rel
end
function parse_program_with_use(source, source_path, seen):
    pr = parse_program_stream(source, source_path)
    if pr[1] != "":
        if starts_with(pr[1], "[ ERROR"):
            return [[], seen, pr[1]]
        end
        if source_path != "":
            return [[], seen, source_path + ": " + pr[1]]
        end
        return [[], seen, pr[1]]
    end
    base_dir = path_dirname(source_path)
    exp = expand_use_stmts(pr[0], base_dir, source_path, seen)
    if not exp[0]:
        return [[], exp[2], exp[3]]
    end
    return [exp[1], exp[2], ""]
end
function expand_use_stmts(stmts, base_dir, cur_path, seen):
    out = lb_new()
    si = 0
    loop len(stmts):
        st = stmts[si]
        if st[0] == "use":
            use_path = st[1]
            full = use_path
            if not path_is_abs(use_path):
                full = path_join(base_dir, use_path)
            end
            if env_has(seen, full):
                si = si + 1
                continue
            end
            seen = env_set(seen, full, 1)
            src = readfile(full)
            if src == "" and full != use_path:
                src_try = readfile(use_path)
                if src_try != "":
                    full = use_path
                    src = src_try
                    seen = env_set(seen, full, 1)
                end
            end
            if src == "":
                # stdlib fallback for bare library names (e.g., use "math")
                has_sep = false
                if find_char(use_path, "/", 0) >= 0:
                    has_sep = true
                end
                if find_char(use_path, "\\", 0) >= 0:
                    has_sep = true
                end
                has_ext = false
                if len(use_path) >= 4:
                    if substr(use_path, len(use_path) - 4, 4) == ".lsl":
                        has_ext = true
                    end
                end
                if not has_sep and not has_ext:
                    lib_path = "stdlib/" + use_path + ".lsl"
                    lib_src = readfile(lib_path)
                    if lib_src != "":
                        full = lib_path
                        src = lib_src
                        seen = env_set(seen, full, 1)
                    end
                end
            end
            if src == "":
                err_line = 0
                err_col = 0
                if len(st) >= 5:
                    err_line = st[3]
                    err_col = st[4]
                end
                err_path = cur_path
                msg = "Cannot read file: " + full
                return [false, lb_to_list(out), seen, format_error_block("E005", "Use Error", err_path, err_line, err_col, "", "", msg, "Check that the file exists and the path is correct.", 1)]
            end
            pr = parse_program_with_use(src, full, seen)
            if pr[2] != "":
                return [false, lb_to_list(out), pr[1], pr[2]]
            end
            seen = pr[1]
            pi = 0
            loop len(pr[0]):
                out = lb_add(out, pr[0][pi])
                pi = pi + 1
            end
        else:
            out = lb_add(out, st)
        end
        si = si + 1
    end
    return [true, lb_to_list(out), seen, ""]
end
function parse_block_lines(lines, pos, terminators):
    pbl_i = pos
    pbl_stmts = lb_new()
    while pbl_i < len(lines):
        pbl_tokens = lines[pbl_i]
        # terminator check by first token
        tok0 = tok_get(pbl_tokens, 0)
        if tok0[0] == "eof":
            pbl_i = pbl_i + 1
            continue
        end
        if tok0[0] == "id":
            ti = 0
            loop len(terminators):
                if tok0[1] == terminators[ti]:
                    return [lb_to_list(pbl_stmts), pbl_i, ""]
                end
                ti = ti + 1
            end
        end
        # compound statements
        if tok0[0] == "id" and tok0[1] == "if":
            pe = parse_expr(pbl_tokens, 1)
            if not pe[0]:
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, pe[2], pe[3])]
            end
            ppos = pe[2]
            tok1 = tok_get(pbl_tokens, ppos)
            if tok1[0] == "colon":
                ppos = ppos + 1
            end
            tok1 = tok_get(pbl_tokens, ppos)
            if tok1[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, ppos, "unexpected tokens after if condition")]
            end
            pbl_then = parse_block_lines(lines, pbl_i + 1, ["elif", "else", "end"])
            if pbl_then[2] != "":
                return [lb_to_list(pbl_stmts), pbl_i, pbl_then[2]]
            end
            then_body = pbl_then[0]
            pbl_i = pbl_then[1]
            elif_parts = []
            else_body = []
            while pbl_i < len(lines):
                pbl_tokens2 = lines[pbl_i]
                tok2 = tok_get(pbl_tokens2, 0)
                if tok2[0] == "id" and tok2[1] == "elif":
                    pe2 = parse_expr(pbl_tokens2, 1)
                    if not pe2[0]:
                        return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens2, pe2[2], pe2[3])]
                    end
                    ppos2 = pe2[2]
                    tok3 = tok_get(pbl_tokens2, ppos2)
                    if tok3[0] == "colon":
                        ppos2 = ppos2 + 1
                    end
                    tok3 = tok_get(pbl_tokens2, ppos2)
                    if tok3[0] != "eof":
                        return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens2, ppos2, "unexpected tokens after elif condition")]
                    end
                    pbl_elif = parse_block_lines(lines, pbl_i + 1, ["elif", "else", "end"])
                    if pbl_elif[2] != "":
                        return [lb_to_list(pbl_stmts), pbl_i, pbl_elif[2]]
                    end
                    elif_parts = elif_parts + [[pe2[1], pbl_elif[0]]]
                    pbl_i = pbl_elif[1]
                    continue
                end
                if tok2[0] == "id" and tok2[1] == "else":
                    tok3 = tok_get(pbl_tokens2, 1)
                    pos_err = 1
                    if tok3[0] == "colon":
                        tok3 = tok_get(pbl_tokens2, 2)
                        pos_err = 2
                    end
                    if tok3[0] != "eof":
                        return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens2, pos_err, "unexpected tokens after else")]
                    end
                    pbl_else = parse_block_lines(lines, pbl_i + 1, ["end"])
                    if pbl_else[2] != "":
                        return [lb_to_list(pbl_stmts), pbl_i, pbl_else[2]]
                    end
                    else_body = pbl_else[0]
                    pbl_i = pbl_else[1]
                end
                break
            end
            if pbl_i >= len(lines):
                last_i = len(lines) - 1
                if last_i >= 0:
                    return [lb_to_list(pbl_stmts), pbl_i, err_at(lines[last_i], 0, "expected end")]
                end
                return [lb_to_list(pbl_stmts), pbl_i, "expected end"]
            end
            pbl_end_tokens = lines[pbl_i]
            tok_end = tok_get(pbl_end_tokens, 0)
            if not (tok_end[0] == "id" and tok_end[1] == "end"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "expected end")]
            end
            # lower elif to nested if in else_body
            eb = else_body
            ei = len(elif_parts) - 1
            while ei >= 0:
                ep = elif_parts[ei]
                eb = [["if", ep[0], ep[1], eb]]
                ei = ei - 1
            end
            pbl_stmts = lb_add(pbl_stmts, ["if", pe[1], then_body, eb])
            pbl_i = pbl_i + 1
            continue
        end
        if tok0[0] == "id" and tok0[1] == "while":
            pe = parse_expr(pbl_tokens, 1)
            if not pe[0]:
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, pe[2], pe[3])]
            end
            ppos = pe[2]
            tok1 = tok_get(pbl_tokens, ppos)
            if tok1[0] == "colon":
                ppos = ppos + 1
            end
            tok1 = tok_get(pbl_tokens, ppos)
            if tok1[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, ppos, "unexpected tokens after while condition")]
            end
            pbl_body = parse_block_lines(lines, pbl_i + 1, ["end"])
            if pbl_body[2] != "":
                return [lb_to_list(pbl_stmts), pbl_i, pbl_body[2]]
            end
            pbl_i = pbl_body[1]
            pbl_end_tokens = lines[pbl_i]
            tok_end = tok_get(pbl_end_tokens, 0)
            if not (tok_end[0] == "id" and tok_end[1] == "end"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "expected end")]
            end
            pbl_stmts = lb_add(pbl_stmts, ["while", pe[1], pbl_body[0]])
            pbl_i = pbl_i + 1
            continue
        end
        if tok0[0] == "id" and tok0[1] == "for":
            name_tok = tok_get(pbl_tokens, 1)
            if name_tok[0] != "id":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, 1, "expected loop variable name")]
            end
            tok1 = tok_get(pbl_tokens, 2)
            idx_name = ""
            pos_in = 2
            if tok1[0] == "comma":
                tok2 = tok_get(pbl_tokens, 3)
                if tok2[0] != "id":
                    return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, 3, "expected index variable name")]
                end
                idx_name = tok2[1]
                tok1 = tok_get(pbl_tokens, 4)
                pos_in = 4
            end
            if not (tok1[0] == "id" and tok1[1] == "in"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, pos_in, "expected 'in' in for loop")]
            end
            pe = parse_expr(pbl_tokens, pos_in + 1)
            if not pe[0]:
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, pe[2], pe[3])]
            end
            ppos = pe[2]
            tok2 = tok_get(pbl_tokens, ppos)
            if pe[1][0] == "range":
                if idx_name != "":
                    return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, pos_in, "index variable not allowed in range for")]
                end
                step_expr = ["num", 1]
                if tok2[0] == "comma":
                    pe3 = parse_expr(pbl_tokens, ppos + 1)
                    if not pe3[0]:
                        return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, pe3[2], pe3[3])]
                    end
                    step_expr = pe3[1]
                    ppos = pe3[2]
                    tok2 = tok_get(pbl_tokens, ppos)
                end
                if tok2[0] == "colon":
                    ppos = ppos + 1
                end
                tok2 = tok_get(pbl_tokens, ppos)
                if tok2[0] != "eof":
                    return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, ppos, "unexpected tokens after for range")]
                end
                pbl_body = parse_block_lines(lines, pbl_i + 1, ["end"])
                if pbl_body[2] != "":
                    return [lb_to_list(pbl_stmts), pbl_i, pbl_body[2]]
                end
                pbl_i = pbl_body[1]
                pbl_end_tokens = lines[pbl_i]
                tok_end = tok_get(pbl_end_tokens, 0)
                if not (tok_end[0] == "id" and tok_end[1] == "end"):
                    return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "expected end")]
                end
                pbl_stmts = lb_add(pbl_stmts, ["forrange", name_tok[1], pe[1][1], pe[1][2], step_expr, pbl_body[0]])
                pbl_i = pbl_i + 1
                continue
            end
            if tok2[0] == "dotdot":
                if idx_name != "":
                    return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, ppos, "index variable not allowed in range for")]
                end
                pe2 = parse_expr(pbl_tokens, ppos + 1)
                if not pe2[0]:
                    return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, pe2[2], pe2[3])]
                end
                ppos = pe2[2]
                step_expr = ["num", 1]
                tok3 = tok_get(pbl_tokens, ppos)
                if tok3[0] == "comma":
                    pe3 = parse_expr(pbl_tokens, ppos + 1)
                    if not pe3[0]:
                        return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, pe3[2], pe3[3])]
                    end
                    step_expr = pe3[1]
                    ppos = pe3[2]
                end
                tok2 = tok_get(pbl_tokens, ppos)
                if tok2[0] == "colon":
                    ppos = ppos + 1
                end
                tok2 = tok_get(pbl_tokens, ppos)
                if tok2[0] != "eof":
                    return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, ppos, "unexpected tokens after for range")]
                end
                pbl_body = parse_block_lines(lines, pbl_i + 1, ["end"])
                if pbl_body[2] != "":
                    return [lb_to_list(pbl_stmts), pbl_i, pbl_body[2]]
                end
                pbl_i = pbl_body[1]
                pbl_end_tokens = lines[pbl_i]
                tok_end = tok_get(pbl_end_tokens, 0)
                if not (tok_end[0] == "id" and tok_end[1] == "end"):
                    return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "expected end")]
                end
                pbl_stmts = lb_add(pbl_stmts, ["forrange", name_tok[1], pe[1], pe2[1], step_expr, pbl_body[0]])
                pbl_i = pbl_i + 1
                continue
            end
            if tok2[0] == "colon":
                ppos = ppos + 1
            end
            tok2 = tok_get(pbl_tokens, ppos)
            if tok2[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, ppos, "unexpected tokens after for-in")]
            end
            pbl_body = parse_block_lines(lines, pbl_i + 1, ["end"])
            if pbl_body[2] != "":
                return [lb_to_list(pbl_stmts), pbl_i, pbl_body[2]]
            end
            pbl_i = pbl_body[1]
            pbl_end_tokens = lines[pbl_i]
            tok_end = tok_get(pbl_end_tokens, 0)
            if not (tok_end[0] == "id" and tok_end[1] == "end"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "expected end")]
            end
            if idx_name == "":
                pbl_stmts = lb_add(pbl_stmts, ["forin", name_tok[1], pe[1], pbl_body[0]])
            else:
                pbl_stmts = lb_add(pbl_stmts, ["forin2", name_tok[1], idx_name, pe[1], pbl_body[0]])
            end
            pbl_i = pbl_i + 1
            continue
        end
        if tok0[0] == "id" and tok0[1] == "do":
            tok1 = tok_get(pbl_tokens, 1)
            if tok1[0] == "colon":
                tok1 = tok_get(pbl_tokens, 2)
            end
            if tok1[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, 1, "unexpected tokens after do")]
            end
            pbl_body = parse_block_lines(lines, pbl_i + 1, ["while"])
            if pbl_body[2] != "":
                return [lb_to_list(pbl_stmts), pbl_i, pbl_body[2]]
            end
            pbl_i = pbl_body[1]
            if pbl_i >= len(lines):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(lines[len(lines) - 1], 0, "expected while")]
            end
            pbl_while_tokens = lines[pbl_i]
            tokw = tok_get(pbl_while_tokens, 0)
            if not (tokw[0] == "id" and tokw[1] == "while"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_while_tokens, 0, "expected while")]
            end
            pe = parse_expr(pbl_while_tokens, 1)
            if not pe[0]:
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_while_tokens, pe[2], pe[3])]
            end
            ppos = pe[2]
            tok2 = tok_get(pbl_while_tokens, ppos)
            if tok2[0] == "colon":
                ppos = ppos + 1
            end
            tok2 = tok_get(pbl_while_tokens, ppos)
            if tok2[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_while_tokens, ppos, "unexpected tokens after while condition")]
            end
            pbl_i = pbl_i + 1
            if pbl_i < len(lines):
                pbl_end_tokens = lines[pbl_i]
                tok_end = tok_get(pbl_end_tokens, 0)
                if tok_end[0] == "id" and tok_end[1] == "end":
                    pbl_i = pbl_i + 1
                end
            end
            pbl_stmts = lb_add(pbl_stmts, ["do", pe[1], pbl_body[0]])
            continue
        end
        if tok0[0] == "id" and tok0[1] == "try":
            tok1 = tok_get(pbl_tokens, 1)
            if tok1[0] == "colon":
                tok1 = tok_get(pbl_tokens, 2)
            end
            if tok1[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, 1, "unexpected tokens after try")]
            end
            pbl_body = parse_block_lines(lines, pbl_i + 1, ["catch", "end"])
            if pbl_body[2] != "":
                return [lb_to_list(pbl_stmts), pbl_i, pbl_body[2]]
            end
            pbl_i = pbl_body[1]
            catch_body = []
            if pbl_i < len(lines):
                pbl_catch_tokens = lines[pbl_i]
                tokc = tok_get(pbl_catch_tokens, 0)
                if tokc[0] == "id" and tokc[1] == "catch":
                    tok3 = tok_get(pbl_catch_tokens, 1)
                    if tok3[0] == "colon":
                        tok3 = tok_get(pbl_catch_tokens, 2)
                    end
                    if tok3[0] != "eof":
                        return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_catch_tokens, 1, "unexpected tokens after catch")]
                    end
                    pbl_catch = parse_block_lines(lines, pbl_i + 1, ["end"])
                    if pbl_catch[2] != "":
                        return [lb_to_list(pbl_stmts), pbl_i, pbl_catch[2]]
                    end
                    catch_body = pbl_catch[0]
                    pbl_i = pbl_catch[1]
                end
            end
            if pbl_i >= len(lines):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(lines[len(lines) - 1], 0, "expected end")]
            end
            pbl_end_tokens = lines[pbl_i]
            tok_end = tok_get(pbl_end_tokens, 0)
            if not (tok_end[0] == "id" and tok_end[1] == "end"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "expected end")]
            end
            pbl_stmts = lb_add(pbl_stmts, ["safe", pbl_body[0], catch_body])
            pbl_i = pbl_i + 1
            continue
        end
        if tok0[0] == "id" and tok0[1] == "repeat":
            tok1 = tok_get(pbl_tokens, 1)
            if tok1[0] == "colon":
                tok1 = tok_get(pbl_tokens, 2)
            end
            if tok1[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, 1, "unexpected tokens after repeat")]
            end
            pbl_body = parse_block_lines(lines, pbl_i + 1, ["until", "end"])
            if pbl_body[2] != "":
                return [lb_to_list(pbl_stmts), pbl_i, pbl_body[2]]
            end
            pbl_i = pbl_body[1]
            if pbl_i >= len(lines):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(lines[len(lines) - 1], 0, "expected until")]
            end
            pbl_until_tokens = lines[pbl_i]
            tok_until = tok_get(pbl_until_tokens, 0)
            if not (tok_until[0] == "id" and tok_until[1] == "until"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_until_tokens, 0, "expected until")]
            end
            pe = parse_expr(pbl_until_tokens, 1)
            if not pe[0]:
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_until_tokens, pe[2], pe[3])]
            end
            ppos = pe[2]
            tok2 = tok_get(pbl_until_tokens, ppos)
            if tok2[0] == "colon":
                ppos = ppos + 1
            end
            tok2 = tok_get(pbl_until_tokens, ppos)
            if tok2[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_until_tokens, ppos, "unexpected tokens after until condition")]
            end
            pbl_i = pbl_i + 1
            if pbl_i >= len(lines):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(lines[len(lines) - 1], 0, "expected end")]
            end
            pbl_end_tokens = lines[pbl_i]
            tok_end = tok_get(pbl_end_tokens, 0)
            if not (tok_end[0] == "id" and tok_end[1] == "end"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "expected end")]
            end
            pbl_stmts = lb_add(pbl_stmts, ["repeat", pe[1], pbl_body[0]])
            pbl_i = pbl_i + 1
            continue
        end
        if tok0[0] == "id" and tok0[1] == "safe":
            tok1 = tok_get(pbl_tokens, 1)
            if tok1[0] == "colon":
                tok1 = tok_get(pbl_tokens, 2)
            end
            if tok1[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, 1, "unexpected tokens after safe")]
            end
            pbl_body = parse_block_lines(lines, pbl_i + 1, ["else", "end"])
            if pbl_body[2] != "":
                return [lb_to_list(pbl_stmts), pbl_i, pbl_body[2]]
            end
            pbl_i = pbl_body[1]
            else_body = []
            if pbl_i < len(lines):
                pbl_else_tokens = lines[pbl_i]
                tok_else = tok_get(pbl_else_tokens, 0)
                if tok_else[0] == "id" and tok_else[1] == "else":
                    tok3 = tok_get(pbl_else_tokens, 1)
                    if tok3[0] == "colon":
                        tok3 = tok_get(pbl_else_tokens, 2)
                    end
                    if tok3[0] != "eof":
                        return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_else_tokens, 1, "unexpected tokens after else")]
                    end
                    pbl_else = parse_block_lines(lines, pbl_i + 1, ["end"])
                    if pbl_else[2] != "":
                        return [lb_to_list(pbl_stmts), pbl_i, pbl_else[2]]
                    end
                    else_body = pbl_else[0]
                    pbl_i = pbl_else[1]
                end
            end
            if pbl_i >= len(lines):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(lines[len(lines) - 1], 0, "expected end")]
            end
            pbl_end_tokens = lines[pbl_i]
            tok_end = tok_get(pbl_end_tokens, 0)
            if not (tok_end[0] == "id" and tok_end[1] == "end"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "expected end")]
            end
            pbl_stmts = lb_add(pbl_stmts, ["safe", pbl_body[0], else_body])
            pbl_i = pbl_i + 1
            continue
        end
        if tok0[0] == "id" and tok0[1] == "switch":
            pe = parse_expr(pbl_tokens, 1)
            if not pe[0]:
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, pe[2], pe[3])]
            end
            ppos = pe[2]
            tok1 = tok_get(pbl_tokens, ppos)
            if tok1[0] == "colon":
                ppos = ppos + 1
            end
            tok1 = tok_get(pbl_tokens, ppos)
            if tok1[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, ppos, "unexpected tokens after switch")]
            end
            cases = []
            default_body = []
            pbl_i = pbl_i + 1
            while pbl_i < len(lines):
                pbl_tokens2 = lines[pbl_i]
                tok2 = tok_get(pbl_tokens2, 0)
                if tok2[0] == "id" and tok2[1] == "case":
                    pe2 = parse_expr(pbl_tokens2, 1)
                    if not pe2[0]:
                        return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens2, pe2[2], pe2[3])]
                    end
                    ppos2 = pe2[2]
                    tok3 = tok_get(pbl_tokens2, ppos2)
                    if tok3[0] == "colon":
                        ppos2 = ppos2 + 1
                    end
                    tok3 = tok_get(pbl_tokens2, ppos2)
                    if tok3[0] != "eof":
                        return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens2, ppos2, "unexpected tokens after case")]
                    end
                    pbl_case = parse_block_lines(lines, pbl_i + 1, ["case", "default", "end"])
                    if pbl_case[2] != "":
                        return [lb_to_list(pbl_stmts), pbl_i, pbl_case[2]]
                    end
                    cases = cases + [[pe2[1], pbl_case[0]]]
                    pbl_i = pbl_case[1]
                    continue
                end
                if tok2[0] == "id" and tok2[1] == "default":
                    tok3 = tok_get(pbl_tokens2, 1)
                    if tok3[0] == "colon":
                        tok3 = tok_get(pbl_tokens2, 2)
                    end
                    if tok3[0] != "eof":
                        return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens2, 1, "unexpected tokens after default")]
                    end
                    pbl_def = parse_block_lines(lines, pbl_i + 1, ["end"])
                    if pbl_def[2] != "":
                        return [lb_to_list(pbl_stmts), pbl_i, pbl_def[2]]
                    end
                    default_body = pbl_def[0]
                    pbl_i = pbl_def[1]
                end
                break
            end
            if pbl_i >= len(lines):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(lines[len(lines) - 1], 0, "expected end")]
            end
            pbl_end_tokens = lines[pbl_i]
            tok_end = tok_get(pbl_end_tokens, 0)
            if not (tok_end[0] == "id" and tok_end[1] == "end"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "expected end")]
            end
            pbl_stmts = lb_add(pbl_stmts, ["switch", pe[1], cases, default_body])
            pbl_i = pbl_i + 1
            continue
        end
        if tok0[0] == "id" and tok0[1] == "loop":
            tok1 = tok_get(pbl_tokens, 1)
            if tok1[0] == "colon" or tok1[0] == "eof":
                pe_expr = ["num", 1]
                ppos = 1
            else:
                pe = parse_expr(pbl_tokens, 1)
                if not pe[0]:
                    return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, pe[2], pe[3])]
                end
                pe_expr = pe[1]
                ppos = pe[2]
            end
            tok2 = tok_get(pbl_tokens, ppos)
            if tok2[0] == "colon":
                ppos = ppos + 1
            end
            tok2 = tok_get(pbl_tokens, ppos)
            if tok2[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, ppos, "unexpected tokens after loop")]
            end
            pbl_body = parse_block_lines(lines, pbl_i + 1, ["end"])
            if pbl_body[2] != "":
                return [lb_to_list(pbl_stmts), pbl_i, pbl_body[2]]
            end
            pbl_i = pbl_body[1]
            pbl_end_tokens = lines[pbl_i]
            tok_end = tok_get(pbl_end_tokens, 0)
            if not (tok_end[0] == "id" and tok_end[1] == "end"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "expected end")]
            end
            pbl_stmts = lb_add(pbl_stmts, ["loop", pe_expr, pbl_body[0]])
            pbl_i = pbl_i + 1
            continue
        end
        if tok0[0] == "id" and tok0[1] == "class":
            name_tok = tok_get(pbl_tokens, 1)
            if name_tok[0] != "id":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, 1, "expected class name")]
            end
            tok1 = tok_get(pbl_tokens, 2)
            if tok1[0] == "colon":
                tok1 = tok_get(pbl_tokens, 3)
            end
            if tok1[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, 2, "unexpected tokens after class name")]
            end
            pbl_body = parse_block_lines(lines, pbl_i + 1, ["end"])
            if pbl_body[2] != "":
                return [lb_to_list(pbl_stmts), pbl_i, pbl_body[2]]
            end
            pbl_i = pbl_body[1]
            pbl_end_tokens = lines[pbl_i]
            tok_end = tok_get(pbl_end_tokens, 0)
            if not (tok_end[0] == "id" and tok_end[1] == "end"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "expected end")]
            end
            methods = []
            mi = 0
            loop len(pbl_body[0]):
                st = pbl_body[0][mi]
                if st[0] != "function":
                    return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "only function definitions are allowed in class")]
                end
                methods = methods + [st]
                mi = mi + 1
            end
            pbl_stmts = lb_add(pbl_stmts, ["class", name_tok[1], methods])
            pbl_i = pbl_i + 1
            continue
        end
        if tok0[0] == "id" and tok0[1] == "function":
            name_tok = tok_get(pbl_tokens, 1)
            if name_tok[0] != "id":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, 1, "expected function name")]
            end
            tok1 = tok_get(pbl_tokens, 2)
            if tok1[0] != "lparen":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, 2, "expected (")]
            end
            params = []
            ppos = 3
            tok2 = tok_get(pbl_tokens, ppos)
            if tok2[0] != "rparen":
                if tok2[0] != "id":
                    return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, ppos, "expected parameter name")]
                end
                params = params + [tok2[1]]
                ppos = ppos + 1
                while true:
                    tok2 = tok_get(pbl_tokens, ppos)
                    if tok2[0] == "comma":
                        tok2 = tok_get(pbl_tokens, ppos + 1)
                        if tok2[0] != "id":
                            return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, ppos + 1, "expected parameter name")]
                        end
                        params = params + [tok2[1]]
                        ppos = ppos + 2
                        continue
                    end
                    break
                end
                tok2 = tok_get(pbl_tokens, ppos)
            end
            if tok2[0] != "rparen":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, ppos, "expected )")]
            end
            ppos = ppos + 1
            tok2 = tok_get(pbl_tokens, ppos)
            if tok2[0] == "colon":
                ppos = ppos + 1
            end
            tok2 = tok_get(pbl_tokens, ppos)
            if tok2[0] != "eof":
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_tokens, ppos, "unexpected tokens after function header")]
            end
            pbl_body = parse_block_lines(lines, pbl_i + 1, ["end"])
            if pbl_body[2] != "":
                return [lb_to_list(pbl_stmts), pbl_i, pbl_body[2]]
            end
            pbl_i = pbl_body[1]
            pbl_end_tokens = lines[pbl_i]
            tok_end = tok_get(pbl_end_tokens, 0)
            if not (tok_end[0] == "id" and tok_end[1] == "end"):
                return [lb_to_list(pbl_stmts), pbl_i, err_at(pbl_end_tokens, 0, "expected end")]
            end
            pbl_stmts = lb_add(pbl_stmts, ["function", name_tok[1], params, pbl_body[0]])
            pbl_i = pbl_i + 1
            continue
        end
        # simple statement line
        ps = parse_stmt_line_tokens(pbl_tokens)
        if not ps[0]:
            return [lb_to_list(pbl_stmts), pbl_i, ps[2]]
        end
        pbl_stmts = lb_add(pbl_stmts, ps[1])
        pbl_i = pbl_i + 1
    end
    # if terminators include <eof>, end is ok
    ti = 0
    loop len(terminators):
        if terminators[ti] == "<eof>":
            return [lb_to_list(pbl_stmts), pbl_i, ""]
        end
        ti = ti + 1
    end
    last_i = len(lines) - 1
    if last_i >= 0:
        return [lb_to_list(pbl_stmts), pbl_i, err_at(lines[last_i], 0, "unexpected eof")]
    end
    return [lb_to_list(pbl_stmts), pbl_i, "unexpected eof"]
end
function parse_stmt_line_tokens(tokens):
    tok0 = tok_get(tokens, 0)
    if tok0[0] == "id" and tok0[1] == "use":
        tok1 = tok_get(tokens, 1)
        if tok1[0] != "str":
            return [false, null, err_at(tokens, 1, "expected string literal")]
        end
        use_path = tok1[1]
        alias = ""
        check_pos = 2
        tok2 = tok_get(tokens, 2)
        if tok2[0] == "id" and tok2[1] == "as":
            tok3 = tok_get(tokens, 3)
            if tok3[0] != "id":
                return [false, null, err_at(tokens, 3, "expected identifier after as")]
            end
            alias = tok3[1]
            check_pos = 4
            tok2 = tok_get(tokens, check_pos)
        end
        if tok2[0] != "eof":
            return [false, null, err_at(tokens, check_pos, "unexpected tokens after use")]
        end
        return [true, ["use", use_path, alias, tok_line(tok0), tok_col(tok0)], ""]
    end
    if tok0[0] == "id" and tok0[1] == "return":
        tok1 = tok_get(tokens, 1)
        if tok1[0] == "eof":
            return [true, ["return", ["null"]], ""]
        end
        pe = parse_expr(tokens, 1)
        if not pe[0]:
            return [false, null, err_at(tokens, pe[2], pe[3])]
        end
        if tok_get(tokens, pe[2])[0] != "eof":
            return [false, null, err_at(tokens, pe[2], "unexpected tokens after return")]
        end
        return [true, ["return", pe[1]], ""]
    end
    if tok0[0] == "id" and tok0[1] == "break":
        if tok_get(tokens, 1)[0] != "eof":
            return [false, null, err_at(tokens, 1, "unexpected tokens after break")]
        end
        return [true, ["break"], ""]
    end
    if tok0[0] == "id" and tok0[1] == "continue":
        if tok_get(tokens, 1)[0] != "eof":
            return [false, null, err_at(tokens, 1, "unexpected tokens after continue")]
        end
        return [true, ["continue"], ""]
    end
    if tok0[0] == "id" and tok0[1] == "print":
        pe = parse_expr(tokens, 1)
        if not pe[0]:
            return [false, null, err_at(tokens, pe[2], pe[3])]
        end
        if tok_get(tokens, pe[2])[0] != "eof":
            return [false, null, err_at(tokens, pe[2], "unexpected tokens after print")]
        end
        return [true, ["print", pe[1]], ""]
    end
    if tok0[0] == "id" and (tok0[1] == "readfile" or tok0[1] == "writefile" or tok0[1] == "appendfile" or tok0[1] == "createdir" or tok0[1] == "listdir" or tok0[1] == "deletedir"):
        tok1 = tok_get(tokens, 1)
        if tok1[0] == "str":
            args = [["str", tok1[1]]]
            ppos = 2
            if tok0[1] == "writefile" or tok0[1] == "appendfile":
                if tok_get(tokens, ppos)[0] != "comma":
                    return [false, null, err_at(tokens, ppos, "expected ,")]
                end
                pe = parse_expr(tokens, ppos + 1)
                if not pe[0]:
                    return [false, null, err_at(tokens, pe[2], pe[3])]
                end
                args = args + [pe[1]]
                ppos = pe[2]
            end
            if tok_get(tokens, ppos)[0] != "eof":
                return [false, null, err_at(tokens, ppos, "unexpected tokens after file op")]
            end
            return [true, ["expr", ["call", ["id", tok0[1]], args]], ""]
        end
    end
    # member/index assignment: obj.key = expr
    pa_lhs = parse_postfix(tokens, 0)
    if pa_lhs[0]:
        tok_assign = tok_get(tokens, pa_lhs[2])
        if tok_assign[0] == "eq" or tok_assign[0] == "pluseq" or tok_assign[0] == "minuseq" or tok_assign[0] == "stareq" or tok_assign[0] == "slasheq" or tok_assign[0] == "percenteq":
            if pa_lhs[1][0] == "index" and pa_lhs[1][1][0] == "id":
                pe = parse_expr(tokens, pa_lhs[2] + 1)
                if not pe[0]:
                    return [false, null, err_at(tokens, pe[2], pe[3])]
                end
                if tok_get(tokens, pe[2])[0] != "eof":
                    return [false, null, err_at(tokens, pe[2], "unexpected tokens after assignment")]
                end
                op = "+"
                if tok_assign[0] == "minuseq":
                    op = "-"
                elif tok_assign[0] == "stareq":
                    op = "*"
                elif tok_assign[0] == "slasheq":
                    op = "/"
                elif tok_assign[0] == "percenteq":
                    op = "%"
                end
                lhs_obj = ["id", pa_lhs[1][1][1]]
                lhs_key = pa_lhs[1][2]
                rhs = pe[1]
                if tok_assign[0] != "eq":
                    rhs = ["bin", op, ["index", lhs_obj, lhs_key], rhs]
                end
                set_expr = ["call", ["id", "__lsl_dict_set"], [lhs_obj, lhs_key, rhs]]
                return [true, ["assign", pa_lhs[1][1][1], set_expr], ""]
            elif pa_lhs[1][0] == "index":
                return [false, null, err_at(tokens, 0, "invalid assignment target")]
            end
        end
    end
    if tok0[0] == "id" and tok0[1] == "wait":
        pe = parse_expr(tokens, 1)
        if not pe[0]:
            return [false, null, err_at(tokens, pe[2], pe[3])]
        end
        if tok_get(tokens, pe[2])[0] != "eof":
            return [false, null, err_at(tokens, pe[2], "unexpected tokens after wait")]
        end
        return [true, ["wait", pe[1]], ""]
    end
    if tok0[0] == "id" and tok0[1] == "call":
        name_tok = tok_get(tokens, 1)
        if name_tok[0] != "id":
            return [false, null, err_at(tokens, 1, "expected function name")]
        end
        tok2 = tok_get(tokens, 2)
        if tok2[0] != "lparen":
            return [false, null, err_at(tokens, 2, "expected (")]
        end
        args = []
        ppos = 3
        tok2 = tok_get(tokens, ppos)
        if tok2[0] != "rparen":
            pa = parse_expr(tokens, ppos)
            if not pa[0]:
                return [false, null, err_at(tokens, pa[2], pa[3])]
            end
            args = args + [pa[1]]
            ppos = pa[2]
            while true:
                tok2 = tok_get(tokens, ppos)
                if tok2[0] == "comma":
                    pa2 = parse_expr(tokens, ppos + 1)
                    if not pa2[0]:
                        return [false, null, err_at(tokens, pa2[2], pa2[3])]
                    end
                    args = args + [pa2[1]]
                    ppos = pa2[2]
                    continue
                end
                break
            end
            tok2 = tok_get(tokens, ppos)
        end
        if tok2[0] != "rparen":
            return [false, null, err_at(tokens, ppos, "expected )")]
        end
        if tok_get(tokens, ppos + 1)[0] != "eof":
            return [false, null, err_at(tokens, ppos + 1, "unexpected tokens after call")]
        end
        return [true, ["expr", ["call", ["id", name_tok[1]], args]], ""]
    end
    if tok0[0] == "id":
        tok1 = tok_get(tokens, 1)
        if tok1[0] == "eq":
            pe = parse_expr(tokens, 2)
            if not pe[0]:
                return [false, null, err_at(tokens, pe[2], pe[3])]
            end
            if tok_get(tokens, pe[2])[0] != "eof":
                return [false, null, err_at(tokens, pe[2], "unexpected tokens after assignment")]
            end
            return [true, ["assign", tok0[1], pe[1]], ""]
        end
        if tok1[0] == "pluseq" or tok1[0] == "minuseq" or tok1[0] == "stareq" or tok1[0] == "slasheq" or tok1[0] == "percenteq":
            pe = parse_expr(tokens, 2)
            if not pe[0]:
                return [false, null, err_at(tokens, pe[2], pe[3])]
            end
            if tok_get(tokens, pe[2])[0] != "eof":
                return [false, null, err_at(tokens, pe[2], "unexpected tokens after assignment")]
            end
            op = "+"
            if tok1[0] == "minuseq":
                op = "-"
            elif tok1[0] == "stareq":
                op = "*"
            elif tok1[0] == "slasheq":
                op = "/"
            elif tok1[0] == "percenteq":
                op = "%"
            end
            return [true, ["assign", tok0[1], ["bin", op, ["id", tok0[1]], pe[1]]], ""]
        end
    end
    pe = parse_expr(tokens, 0)
    if not pe[0]:
        return [false, null, err_at(tokens, pe[2], pe[3])]
    end
    if tok_get(tokens, pe[2])[0] != "eof":
        return [false, null, err_at(tokens, pe[2], "unexpected tokens after expression")]
    end
    return [true, ["expr", pe[1]], ""]
end
function parse_expr(tokens, pos):
    return parse_or(tokens, pos)
end
function parse_or(tokens, pos):
    po_res = parse_and(tokens, pos)
    if not po_res[0]:
        return po_res
    end
    po_left = po_res[1]
    po_pos = po_res[2]
    while true:
        tok = tok_get(tokens, po_pos)
        if tok[0] == "id" and tok[1] == "or":
            po_res2 = parse_and(tokens, po_pos + 1)
            if not po_res2[0]:
                return po_res2
            end
            po_left = ["bin", "or", po_left, po_res2[1]]
            po_pos = po_res2[2]
        else:
            break
        end
    end
    return [true, po_left, po_pos, ""]
end
function parse_and(tokens, pos):
    pa_res = parse_not(tokens, pos)
    if not pa_res[0]:
        return pa_res
    end
    pa_left = pa_res[1]
    pa_pos = pa_res[2]
    while true:
        tok = tok_get(tokens, pa_pos)
        if tok[0] == "id" and tok[1] == "and":
            pa_res2 = parse_not(tokens, pa_pos + 1)
            if not pa_res2[0]:
                return pa_res2
            end
            pa_left = ["bin", "and", pa_left, pa_res2[1]]
            pa_pos = pa_res2[2]
        else:
            break
        end
    end
    return [true, pa_left, pa_pos, ""]
end
function parse_not(tokens, pos):
    tok = tok_get(tokens, pos)
    if tok[0] == "id" and tok[1] == "not":
        pn_res = parse_not(tokens, pos + 1)
        if not pn_res[0]:
            return pn_res
        end
        return [true, ["unary", "not", pn_res[1]], pn_res[2], ""]
    end
    return parse_cmp(tokens, pos)
end
function parse_cmp(tokens, pos):
    pc_res = parse_add(tokens, pos)
    if not pc_res[0]:
        return pc_res
    end
    pc_left = pc_res[1]
    pc_pos = pc_res[2]
    tok = tok_get(tokens, pc_pos)
    if tok[0] == "dotdot":
        pc_res2 = parse_add(tokens, pc_pos + 1)
        if not pc_res2[0]:
            return pc_res2
        end
        pc_right = pc_res2[1]
        pc_pos = pc_res2[2]
        return [true, ["range", pc_left, pc_right], pc_pos, ""]
    end
    tok = tok_get(tokens, pc_pos)
    if tok[0] == "eqeq" or tok[0] == "neq" or tok[0] == "lt" or tok[0] == "lte" or tok[0] == "gt" or tok[0] == "gte":
        pc_op = tok[1]
        pc_res2 = parse_add(tokens, pc_pos + 1)
        if not pc_res2[0]:
            return pc_res2
        end
        pc_right = pc_res2[1]
        pc_pos = pc_res2[2]
        return [true, ["cmp", pc_op, pc_left, pc_right], pc_pos, ""]
    end
    return [true, pc_left, pc_pos, ""]
end
function parse_add(tokens, pos):
    pa_res = parse_term(tokens, pos)
    if not pa_res[0]:
        return pa_res
    end
    pa_left = pa_res[1]
    pa_pos = pa_res[2]
    while true:
        tok = tok_get(tokens, pa_pos)
        if tok[0] == "plus" or tok[0] == "minus":
            pa_op = tok[1]
            pa_res2 = parse_term(tokens, pa_pos + 1)
            if not pa_res2[0]:
                return pa_res2
            end
            pa_right = pa_res2[1]
            pa_pos = pa_res2[2]
            pa_left = ["bin", pa_op, pa_left, pa_right]
        else:
            break
        end
    end
    return [true, pa_left, pa_pos, ""]
end
function parse_term(tokens, pos):
    pt_res = parse_unary(tokens, pos)
    if not pt_res[0]:
        return pt_res
    end
    pt_left = pt_res[1]
    pt_pos = pt_res[2]
    while true:
        tok = tok_get(tokens, pt_pos)
        if tok[0] == "star" or tok[0] == "slash" or tok[0] == "percent":
            pt_op = tok[1]
            pt_res2 = parse_unary(tokens, pt_pos + 1)
            if not pt_res2[0]:
                return pt_res2
            end
            pt_right = pt_res2[1]
            pt_pos = pt_res2[2]
            pt_left = ["bin", pt_op, pt_left, pt_right]
        else:
            break
        end
    end
    return [true, pt_left, pt_pos, ""]
end
function parse_unary(tokens, pos):
    tok = tok_get(tokens, pos)
    if tok[0] == "minus":
        pu_res = parse_unary(tokens, pos + 1)
        if not pu_res[0]:
            return pu_res
        end
        return [true, ["unary", "-", pu_res[1]], pu_res[2], ""]
    end
    if tok[0] == "id" and tok[1] == "not":
        pu_res = parse_unary(tokens, pos + 1)
        if not pu_res[0]:
            return pu_res
        end
        return [true, ["unary", "not", pu_res[1]], pu_res[2], ""]
    end
    return parse_postfix(tokens, pos)
end
function parse_postfix(tokens, pos):
    pp_res = parse_primary(tokens, pos)
    if not pp_res[0]:
        return pp_res
    end
    pp_expr = pp_res[1]
    pp_pos = pp_res[2]
    while true:
        tok = tok_get(tokens, pp_pos)
        if tok[0] == "lparen":
            args = []
            pp_pos = pp_pos + 1
            tok2 = tok_get(tokens, pp_pos)
            if tok2[0] != "rparen":
                pa = parse_expr(tokens, pp_pos)
                if not pa[0]:
                    return pa
                end
                args = args + [pa[1]]
                pp_pos = pa[2]
                while true:
                    tok2 = tok_get(tokens, pp_pos)
                    if tok2[0] == "comma":
                        pa2 = parse_expr(tokens, pp_pos + 1)
                        if not pa2[0]:
                            return pa2
                        end
                        args = args + [pa2[1]]
                        pp_pos = pa2[2]
                    else:
                        break
                    end
                end
                tok2 = tok_get(tokens, pp_pos)
            end
            if tok2[0] != "rparen":
                return [false, null, pp_pos, "expected )"]
            end
            pp_pos = pp_pos + 1
            pp_expr = ["call", pp_expr, args]
            continue
        end
        if tok[0] == "lbrack":
            pi = parse_expr(tokens, pp_pos + 1)
            if not pi[0]:
                return pi
            end
            tok2 = tok_get(tokens, pi[2])
            if tok2[0] != "rbrack":
                return [false, null, pp_pos, "expected ]"]
            end
            pp_pos = pi[2] + 1
            pp_expr = ["index", pp_expr, pi[1]]
            continue
        end
        if tok[0] == "dot":
            tok2 = tok_get(tokens, pp_pos + 1)
            if tok2[0] != "id":
                return [false, null, pp_pos, "expected member name"]
            end
            tok3 = tok_get(tokens, pp_pos + 2)
            if tok3[0] == "lparen":
                args = []
                ppos = pp_pos + 3
                tok4 = tok_get(tokens, ppos)
                if tok4[0] != "rparen":
                    pa = parse_expr(tokens, ppos)
                    if not pa[0]:
                        return pa
                    end
                    args = args + [pa[1]]
                    ppos = pa[2]
                    while true:
                        tok4 = tok_get(tokens, ppos)
                        if tok4[0] == "comma":
                            pa2 = parse_expr(tokens, ppos + 1)
                            if not pa2[0]:
                                return pa2
                            end
                            args = args + [pa2[1]]
                            ppos = pa2[2]
                            continue
                        end
                        break
                    end
                    tok4 = tok_get(tokens, ppos)
                end
                if tok4[0] != "rparen":
                    return [false, null, pp_pos, "expected )"]
                end
                pp_expr = ["methodcall", pp_expr, tok2[1], args]
                pp_pos = ppos + 1
                continue
            end
            pp_expr = ["index", pp_expr, ["str", tok2[1]]]
            pp_pos = pp_pos + 2
            continue
        end
        break
    end
    return [true, pp_expr, pp_pos, ""]
end
function parse_primary(tokens, pos):
    tok = tok_get(tokens, pos)
    if tok[0] == "num":
        return [true, ["num", tok[1]], pos + 1, ""]
    end
    if tok[0] == "str":
        return [true, ["str", tok[1]], pos + 1, ""]
    end
    if tok[0] == "id" and tok[1] == "new":
        tok2 = tok_get(tokens, pos + 1)
        if tok2[0] != "id":
            return [false, null, pos + 1, "expected class name"]
        end
        tok3 = tok_get(tokens, pos + 2)
        if tok3[0] != "lparen":
            return [false, null, pos + 2, "expected ("]
        end
        args = []
        ppos = pos + 3
        tok4 = tok_get(tokens, ppos)
        if tok4[0] != "rparen":
            pa = parse_expr(tokens, ppos)
            if not pa[0]:
                return pa
            end
            args = args + [pa[1]]
            ppos = pa[2]
            while true:
                tok4 = tok_get(tokens, ppos)
                if tok4[0] == "comma":
                    pa2 = parse_expr(tokens, ppos + 1)
                    if not pa2[0]:
                        return pa2
                    end
                    args = args + [pa2[1]]
                    ppos = pa2[2]
                    continue
                end
                break
            end
            tok4 = tok_get(tokens, ppos)
        end
        if tok4[0] != "rparen":
            return [false, null, pos, "expected )"]
        end
        return [true, ["new", tok2[1], args], ppos + 1, ""]
    end
    if tok[0] == "id":
        if tok[1] == "true":
            return [true, ["bool", 1], pos + 1, ""]
        end
        if tok[1] == "false":
            return [true, ["bool", 0], pos + 1, ""]
        end
        if tok[1] == "null":
            return [true, ["null"], pos + 1, ""]
        end
        return [true, ["id", tok[1]], pos + 1, ""]
    end
    if tok[0] == "lparen":
        pe_res = parse_expr(tokens, pos + 1)
        if not pe_res[0]:
            return pe_res
        end
        tok2 = tok_get(tokens, pe_res[2])
        if tok2[0] != "rparen":
            return [false, null, pos, "expected )"]
        end
        return [true, pe_res[1], pe_res[2] + 1, ""]
    end
    if tok[0] == "lbrack":
        elems = []
        ppos = pos + 1
        tok2 = tok_get(tokens, ppos)
        if tok2[0] != "rbrack":
            pe = parse_expr(tokens, ppos)
            if not pe[0]:
                return pe
            end
            elems = elems + [pe[1]]
            ppos = pe[2]
            while true:
                tok2 = tok_get(tokens, ppos)
                if tok2[0] == "comma":
                    pe2 = parse_expr(tokens, ppos + 1)
                    if not pe2[0]:
                        return pe2
                    end
                    elems = elems + [pe2[1]]
                    ppos = pe2[2]
                else:
                    break
                end
            end
            tok2 = tok_get(tokens, ppos)
        end
        if tok2[0] != "rbrack":
            return [false, null, pos, "expected ]"]
        end
        return [true, ["list", elems], ppos + 1, ""]
    end
    if tok[0] == "lbrace":
        pairs = []
        ppos = pos + 1
        tok2 = tok_get(tokens, ppos)
        if tok2[0] != "rbrace":
            if tok2[0] != "id":
                return [false, null, pos, "expected key"]
            end
            key = tok2[1]
            tok2 = tok_get(tokens, ppos + 1)
            if tok2[0] != "colon":
                return [false, null, pos, "expected :"]
            end
            pe = parse_expr(tokens, ppos + 2)
            if not pe[0]:
                return pe
            end
            pairs = pairs + [[key, pe[1]]]
            ppos = pe[2]
            while true:
                tok2 = tok_get(tokens, ppos)
                if tok2[0] == "comma":
                    tok2 = tok_get(tokens, ppos + 1)
                    if tok2[0] != "id":
                        return [false, null, ppos + 1, "expected key"]
                    end
                    key = tok2[1]
                    tok2 = tok_get(tokens, ppos + 2)
                    if tok2[0] != "colon":
                        return [false, null, ppos + 2, "expected :"]
                    end
                    pe2 = parse_expr(tokens, ppos + 3)
                    if not pe2[0]:
                        return pe2
                    end
                    pairs = pairs + [[key, pe2[1]]]
                    ppos = pe2[2]
                    continue
                end
                break
            end
            tok2 = tok_get(tokens, ppos)
        end
        if tok2[0] != "rbrace":
            return [false, null, pos, "expected }"]
        end
        return [true, ["dict", pairs], ppos + 1, ""]
    end
    return [false, null, pos, "unexpected token"]
end
function code_patch_u32le(code, pos, value):
    return substr(code, 0, pos) + u32le(value) + substr(code, pos + 4, len(code) - pos - 4)
end
function code_patch_u64le(code, pos, value):
    return substr(code, 0, pos) + u64le(value) + substr(code, pos + 8, len(code) - pos - 8)
end
function bytes_patch(code, pos, bytes):
    if pos < 0:
        pos = 0
    end
    if pos > len(code):
        pos = len(code)
    end
    end_pos = pos + len(bytes)
    if end_pos > len(code):
        end_pos = len(code)
    end
    return substr(code, 0, pos) + bytes + substr(code, end_pos, len(code) - end_pos)
end
function apply_patches(code, patch_entries):
    out = bb_new()
    cur = 0
    pi = 0
    loop len(patch_entries):
        pe = patch_entries[pi]
        pos = pe[0]
        bytes = pe[1]
        if pos > cur:
            out = bb_add(out, substr(code, cur, pos - cur))
        end
        out = bb_add(out, bytes)
        cur = pos + len(bytes)
        pi = pi + 1
    end
    if cur < len(code):
        out = bb_add(out, substr(code, cur, len(code) - cur))
    end
    return bb_to_string(out)
end
function has_function(funcs, name):
    i = 0
    loop len(funcs):
        if funcs[i][0] == "function" and funcs[i][1] == name:
            return true
        end
        i = i + 1
    end
    return false
end
function parse_prelude():
    pre_src = readfile("stdlib/prelude.lsl")
    if pre_src == "":
        return [true, [], ""]
    end
    pr = parse_program_stream(pre_src, "stdlib/prelude.lsl")
    if pr[1] != "":
        return [false, [], pr[1]]
    end
    return [true, pr[0], ""]
end
function parse_lib_functions(path):
    src = readfile(path)
    if src == "":
        return [true, [], ""]
    end
    pr = parse_program_stream(src, path)
    if pr[1] != "":
        return [false, [], pr[1]]
    end
    funcs = []
    si = 0
    loop len(pr[0]):
        st = pr[0][si]
        if st[0] == "function":
            funcs = funcs + [st]
        end
        si = si + 1
    end
    return [true, funcs, ""]
end
function build_dispatch_fn(arity, funcs):
    fname = "__lsl_call" + int_to_string(arity)
    params = ["name"]
    pi = 0
    loop arity:
        params = params + ["a" + int_to_string(pi)]
        pi = pi + 1
    end
    body = []
    fi = 0
    loop len(funcs):
        f = funcs[fi]
        if f[0] == "function":
            fn_name = f[1]
            if starts_with(fn_name, "__lsl_call"):
                fi = fi + 1
                continue
            end
            if len(f[2]) == arity:
                cond = ["cmp", "==", ["id", "name"], ["str", fn_name]]
                call_args = []
                ai = 0
                loop arity:
                    call_args = call_args + [["id", "a" + int_to_string(ai)]]
                    ai = ai + 1
                end
                body = body + [["if", cond, [["return", ["call", ["id", fn_name], call_args]]], []]]
            end
        end
        fi = fi + 1
    end
    body = body + [["return", ["null"]]]
    return ["function", fname, params, body]
end
function helper_range_fn():
    body = []
    then_body = []
    else_body = []
    loop_body = []
    loop_body = loop_body + [["assign", "out", ["bin", "+", ["id", "out"], ["list", [["id", "i"]]]]]]
    loop_body = loop_body + [["assign", "i", ["bin", "+", ["id", "i"], ["num", 1]]]]
    then_body = then_body + [["assign", "i", ["id", "start"]]]
    then_body = then_body + [["while", ["cmp", "<=", ["id", "i"], ["id", "end"]], loop_body]]
    loop_body2 = []
    loop_body2 = loop_body2 + [["assign", "out", ["bin", "+", ["id", "out"], ["list", [["id", "i"]]]]]]
    loop_body2 = loop_body2 + [["assign", "i", ["bin", "-", ["id", "i"], ["num", 1]]]]
    else_body = else_body + [["assign", "i", ["id", "start"]]]
    else_body = else_body + [["while", ["cmp", ">=", ["id", "i"], ["id", "end"]], loop_body2]]
    body = body + [["assign", "out", ["list", []]]]
    body = body + [["if", ["cmp", "<=", ["id", "start"], ["id", "end"]], then_body, else_body]]
    body = body + [["return", ["id", "out"]]]
    return ["function", "__lsl_range", ["start", "end"], body]
end
function helper_dict_get_fn():
    body = []
    loop_body = []
    loop_body = loop_body + [["assign", "pair", ["index", ["id", "d"], ["id", "i"]]]]
    loop_body = loop_body + [["if", ["cmp", "==", ["index", ["id", "pair"], ["num", 0]], ["id", "key"]], [["return", ["index", ["id", "pair"], ["num", 1]]]], []]]
    loop_body = loop_body + [["assign", "i", ["bin", "+", ["id", "i"], ["num", 1]]]]
    body = body + [["assign", "i", ["num", 0]]]
    body = body + [["while", ["cmp", "<", ["id", "i"], ["call", ["id", "len"], [["id", "d"]]]], loop_body]]
    body = body + [["return", ["null"]]]
    return ["function", "__lsl_dict_get", ["d", "key"], body]
end
function helper_dict_set_fn():
    body = []
    loop_body = []
    then_body = []
    else_body = []
    then_body = then_body + [["assign", "out", ["bin", "+", ["id", "out"], ["list", [["list", [["id", "key"], ["id", "value"]]]]]]]]
    then_body = then_body + [["assign", "found", ["bool", 1]]]
    else_body = else_body + [["assign", "out", ["bin", "+", ["id", "out"], ["list", [["id", "pair"]]]]]]
    loop_body = loop_body + [["assign", "pair", ["index", ["id", "d"], ["id", "i"]]]]
    loop_body = loop_body + [["if", ["cmp", "==", ["index", ["id", "pair"], ["num", 0]], ["id", "key"]], then_body, else_body]]
    loop_body = loop_body + [["assign", "i", ["bin", "+", ["id", "i"], ["num", 1]]]]
    body = body + [["assign", "i", ["num", 0]]]
    body = body + [["assign", "out", ["list", []]]]
    body = body + [["assign", "found", ["bool", 0]]]
    body = body + [["while", ["cmp", "<", ["id", "i"], ["call", ["id", "len"], [["id", "d"]]]], loop_body]]
    body = body + [["if", ["cmp", "==", ["id", "found"], ["bool", 0]], [["assign", "out", ["bin", "+", ["id", "out"], ["list", [["list", [["id", "key"], ["id", "value"]]]]]]]], []]]
    body = body + [["return", ["id", "out"]]]
    return ["function", "__lsl_dict_set", ["d", "key", "value"], body]
end
function wrap_returns(stmts):
    out = []
    i = 0
    loop len(stmts):
        s = stmts[i]
        if s[0] == "return":
            out = out + [["return", ["list", [s[1], ["id", "self"]]]]]
        elif s[0] == "if":
            out = out + [["if", s[1], wrap_returns(s[2]), wrap_returns(s[3])]]
        elif s[0] == "while":
            out = out + [["while", s[1], wrap_returns(s[2])]]
        elif s[0] == "for":
            out = out + [["for", s[1], s[2], s[3], s[4], wrap_returns(s[5])]]
        elif s[0] == "forin":
            out = out + [["forin", s[1], s[2], wrap_returns(s[3])]]
        elif s[0] == "forin2":
            out = out + [["forin2", s[1], s[2], s[3], wrap_returns(s[4])]]
        elif s[0] == "forrange":
            out = out + [["forrange", s[1], s[2], s[3], s[4], wrap_returns(s[5])]]
        elif s[0] == "repeat":
            out = out + [["repeat", s[1], wrap_returns(s[2])]]
        elif s[0] == "do":
            out = out + [["do", s[1], wrap_returns(s[2])]]
        elif s[0] == "loop":
            out = out + [["loop", s[1], wrap_returns(s[2])]]
        elif s[0] == "safe":
            out = out + [["safe", wrap_returns(s[1]), wrap_returns(s[2])]]
        elif s[0] == "switch":
            cases = []
            ci = 0
            loop len(s[2]):
                c = s[2][ci]
                cases = cases + [[c[0], wrap_returns(c[1])]]
                ci = ci + 1
            end
            out = out + [["switch", s[1], cases, wrap_returns(s[3])]]
        else:
            out = out + [s]
        end
        i = i + 1
    end
    return out
end
function repeat_zero(count):
    rz_chunk = u8(0)
    rz_out = ""
    while count > 0:
        if count % 2 == 1:
            rz_out = rz_out + rz_chunk
        end
        rz_chunk = rz_chunk + rz_chunk
        count = idiv(count, 2)
    end
    return rz_out
end
function rel32(n):
    if n < 0:
        return 4294967296 + n
    end
    return n
end
function var_ensure(var_map, var_count, name):
    ve = env_get(var_map, name)
    if ve[0] == "missing":
        idx = var_count
        var_count = var_count + 1
        var_map = env_set(var_map, name, ["local", idx])
    end
    return [var_map, var_count]
end
function gen_expr_num(node, code, fixups, var_map, var_names, strings, safe_label):
    # Tag constants must be local because module globals are not executed on `use`
    TAG_INT = 1
    TAG_BOOL = 2
    TAG_NULL = 3
    TAG_STR = 4
    TAG_LIST = 5
    if safe_label == null:
        safe_label = ""
    end
    if node[0] == "num":
        val = node[1] * 8 + TAG_INT
        code = bb_add(code, u8(72) + u8(184) + u64le(val))
        return [true, code, fixups, var_map, var_names, strings, ""]
    end
    if node[0] == "bool":
        val = node[1] * 8 + TAG_BOOL
        code = bb_add(code, u8(72) + u8(184) + u64le(val))
        return [true, code, fixups, var_map, var_names, strings, ""]
    end
    if node[0] == "null":
        code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
        return [true, code, fixups, var_map, var_names, strings, ""]
    end
    if node[0] == "str":
        str_idx = lb_len(strings)
        strings = lb_add(strings, node[1])
        pos = bb_len(code)
        code = bb_add(code, u8(72) + u8(184) + u64le(0))
        fixups = lb_add(fixups, [pos + 2, "str_obj", str_idx])
        code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_STR))
        return [true, code, fixups, var_map, var_names, strings, ""]
    end
    if node[0] == "list":
        li = len(node[1]) - 1
        while li >= 0:
            ge = gen_expr_num(node[1][li], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(80)) # push rax
            li = li - 1
        end
        # call rt_list_new with length
        code = bb_add(code, u8(72) + u8(191) + u64le(len(node[1])))
        call_pos = bb_len(code)
        code = bb_add(code, u8(232) + u32le(0))
        fixups = lb_add(fixups, [call_pos + 1, "call", "rt_list_new"])
        # rax = tagged list, rbx = untagged ptr
        code = bb_add(code, u8(72) + u8(137) + u8(195))
        code = bb_add(code, u8(72) + u8(131) + u8(227) + u8(248))
        li = 0
        loop len(node[1]):
            code = bb_add(code, u8(89)) # pop rcx
            offset = 8 + li * 8
            code = bb_add(code, u8(72) + u8(137) + u8(139) + u32le(offset))
            li = li + 1
        end
        return [true, code, fixups, var_map, var_names, strings, ""]
    end
    if node[0] == "dict":
        pairs = []
        pi = 0
        loop len(node[1]):
            p = node[1][pi]
            pairs = pairs + [["list", [["str", p[0]], p[1]]]]
            pi = pi + 1
        end
        return gen_expr_num(["list", pairs], code, fixups, var_map, var_names, strings, safe_label)
    end
    if node[0] == "range":
        return gen_expr_num(["call", ["id", "__lsl_range"], [node[1], node[2]]], code, fixups, var_map, var_names, strings, safe_label)
    end
    if node[0] == "new":
        return gen_expr_num(["call", ["id", node[1] + "__new"], node[2]], code, fixups, var_map, var_names, strings, safe_label)
    end
    if node[0] == "id":
        ve = env_get(var_map, node[1])
        if ve[0] == "missing":
            vr = var_ensure(var_map, var_names, node[1])
            var_map = vr[0]
            var_names = vr[1]
            ve = env_get(var_map, node[1])
        end
        if ve[0] == "param":
            offset = ve[1]
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(offset)))
        else:
            offset = 0 - ((ve[1] + 1) * 8)
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(offset)))
        end
        return [true, code, fixups, var_map, var_names, strings, ""]
    end
    if node[0] == "index":
        if node[2][0] == "str":
            return gen_expr_num(["call", ["id", "__lsl_dict_get"], [node[1], node[2]]], code, fixups, var_map, var_names, strings, safe_label)
        end
        ge = gen_expr_num(node[1], code, fixups, var_map, var_names, strings, safe_label)
        if not ge[0]:
            return ge
        end
        code = ge[1]
        fixups = ge[2]
        var_map = ge[3]
        var_names = ge[4]
        strings = ge[5]
        code = bb_add(code, u8(80)) # push rax
        ge2 = gen_expr_num(node[2], code, fixups, var_map, var_names, strings, safe_label)
        if not ge2[0]:
            return ge2
        end
        code = ge2[1]
        fixups = ge2[2]
        var_map = ge2[3]
        var_names = ge2[4]
        strings = ge2[5]
        code = bb_add(code, u8(89)) # pop rcx
        code = bb_add(code, u8(72) + u8(137) + u8(207)) # mov rdi, rcx
        code = bb_add(code, u8(72) + u8(137) + u8(198)) # mov rsi, rax
        call_pos = bb_len(code)
        code = bb_add(code, u8(232) + u32le(0))
        fixups = lb_add(fixups, [call_pos + 1, "call", "rt_index"])
        return [true, code, fixups, var_map, var_names, strings, ""]
    end
    if node[0] == "methodcall":
        call_name = "__lsl_call_method" + int_to_string(len(node[3]))
        call_args = [node[1], ["str", node[2]]] + node[3]
        ge = gen_expr_num(["call", ["id", call_name], call_args], code, fixups, var_map, var_names, strings, safe_label)
        if not ge[0]:
            return ge
        end
        code = ge[1]
        fixups = ge[2]
        var_map = ge[3]
        var_names = ge[4]
        strings = ge[5]
        # rax = [result, self]
        code = bb_add(code, u8(80)) # push rax (list)
        code = bb_add(code, u8(72) + u8(137) + u8(199)) # mov rdi, rax
        code = bb_add(code, u8(72) + u8(190) + u64le(1)) # mov rsi, tagged 0
        call_pos = bb_len(code)
        code = bb_add(code, u8(232) + u32le(0))
        fixups = lb_add(fixups, [call_pos + 1, "call", "rt_index"])
        code = bb_add(code, u8(80)) # push rax (result)
        code = bb_add(code, u8(72) + u8(139) + u8(124) + u8(36) + u8(8)) # mov rdi, [rsp+8]
        code = bb_add(code, u8(72) + u8(190) + u64le(9)) # mov rsi, tagged 1
        call_pos = bb_len(code)
        code = bb_add(code, u8(232) + u32le(0))
        fixups = lb_add(fixups, [call_pos + 1, "call", "rt_index"])
        if node[1][0] == "id":
            ve = env_get(var_map, node[1][1])
            if ve[0] == "missing":
                vr = var_ensure(var_map, var_names, node[1][1])
                var_map = vr[0]
                var_names = vr[1]
                ve = env_get(var_map, node[1][1])
            end
            if ve[0] == "param":
                code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(ve[1])))
            else:
                offset = 0 - ((ve[1] + 1) * 8)
                code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(offset)))
            end
        end
        code = bb_add(code, u8(88)) # pop rax (result)
        code = bb_add(code, u8(72) + u8(131) + u8(196) + u8(8)) # add rsp, 8 (drop list)
        return [true, code, fixups, var_map, var_names, strings, ""]
    end
    if node[0] == "unary":
        if node[1] == "-":
            gr = gen_expr_num(node[2], code, fixups, var_map, var_names, strings, safe_label)
            if not gr[0]:
                return gr
            end
            code = gr[1]
            fixups = gr[2]
            var_map = gr[3]
            var_names = gr[4]
            strings = gr[5]
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(247) + u8(216))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if node[1] == "not":
            gr = gen_expr_num(node[2], code, fixups, var_map, var_names, strings, safe_label)
            if not gr[0]:
                return gr
            end
            code = gr[1]
            fixups = gr[2]
            var_map = gr[3]
            var_names = gr[4]
            strings = gr[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_val_to_bool"])
            code = bb_add(code, u8(72) + u8(131) + u8(240) + u8(1))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_BOOL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        return [false, code, fixups, var_map, var_names, strings, "unsupported unary"]
    end
    if node[0] == "bin":
        op = node[1]
        grl = gen_expr_num(node[2], code, fixups, var_map, var_names, strings, safe_label)
        if not grl[0]:
            return grl
        end
        code = grl[1]
        fixups = grl[2]
        var_map = grl[3]
        var_names = grl[4]
        strings = grl[5]
        code = bb_add(code, u8(80)) # push rax
        grr = gen_expr_num(node[3], code, fixups, var_map, var_names, strings, safe_label)
        if not grr[0]:
            return grr
        end
        code = grr[1]
        fixups = grr[2]
        var_map = grr[3]
        var_names = grr[4]
        strings = grr[5]
        code = bb_add(code, u8(89)) # pop rcx
        if op == "and":
            code = bb_add(code, u8(72) + u8(137) + u8(202)) # mov rdx, rcx
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_val_to_bool"])
            code = bb_add(code, u8(72) + u8(137) + u8(193))
            code = bb_add(code, u8(72) + u8(137) + u8(215)) # mov rdi, rdx
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_val_to_bool"])
            code = bb_add(code, u8(72) + u8(33) + u8(200))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_BOOL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if op == "or":
            code = bb_add(code, u8(72) + u8(137) + u8(202)) # mov rdx, rcx
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_val_to_bool"])
            code = bb_add(code, u8(72) + u8(137) + u8(193))
            code = bb_add(code, u8(72) + u8(137) + u8(215)) # mov rdi, rdx
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_val_to_bool"])
            code = bb_add(code, u8(72) + u8(9) + u8(200))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_BOOL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if op == "+":
            code = bb_add(code, u8(72) + u8(137) + u8(207))
            code = bb_add(code, u8(72) + u8(137) + u8(198))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_add"])
            if safe_label != "":
                code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(TAG_NULL))
                pos = bb_len(code)
                code = bb_add(code, u8(15) + u8(132) + u32le(0))
                fixups = lb_add(fixups, [pos + 2, "rel", safe_label])
            end
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if op == "-":
            code = bb_add(code, u8(72) + u8(193) + u8(249) + u8(3))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(41) + u8(193))
            code = bb_add(code, u8(72) + u8(137) + u8(200))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if op == "*":
            code = bb_add(code, u8(72) + u8(193) + u8(249) + u8(3))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(15) + u8(175) + u8(193))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if op == "/":
            code = bb_add(code, u8(72) + u8(193) + u8(249) + u8(3))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(137) + u8(195))
            if safe_label != "":
                code = bb_add(code, u8(72) + u8(131) + u8(251) + u8(0))
                pos = bb_len(code)
                code = bb_add(code, u8(15) + u8(132) + u32le(0))
                fixups = lb_add(fixups, [pos + 2, "rel", safe_label])
            end
            code = bb_add(code, u8(72) + u8(137) + u8(200))
            code = bb_add(code, u8(72) + u8(153))
            code = bb_add(code, u8(72) + u8(247) + u8(251))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if op == "%":
            code = bb_add(code, u8(72) + u8(193) + u8(249) + u8(3))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(137) + u8(195))
            if safe_label != "":
                code = bb_add(code, u8(72) + u8(131) + u8(251) + u8(0))
                pos = bb_len(code)
                code = bb_add(code, u8(15) + u8(132) + u32le(0))
                fixups = lb_add(fixups, [pos + 2, "rel", safe_label])
            end
            code = bb_add(code, u8(72) + u8(137) + u8(200))
            code = bb_add(code, u8(72) + u8(153))
            code = bb_add(code, u8(72) + u8(247) + u8(251))
            code = bb_add(code, u8(72) + u8(137) + u8(208))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        return [false, code, fixups, var_map, var_names, strings, "unsupported op"]
    end
        if node[0] == "call":
            callee = node[1]
            if callee[0] != "id":
                return [false, code, fixups, var_map, var_names, strings, "unsupported call target"]
            end
        if callee[1] == "len":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "len expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_len"])
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "chr":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "chr expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_chr"])
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "num":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "num expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_num"])
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "readfile":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "readfile expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_readfile"])
            if safe_label != "":
                code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(TAG_NULL))
                pos = bb_len(code)
                code = bb_add(code, u8(15) + u8(132) + u32le(0))
                fixups = lb_add(fixups, [pos + 2, "rel", safe_label])
            end
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "writefile":
            if len(node[2]) != 2:
                return [false, code, fixups, var_map, var_names, strings, "writefile expects 2 args"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(80)) # push rax
            ge = gen_expr_num(node[2][1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(198)) # mov rsi, rax
            code = bb_add(code, u8(89)) # pop rcx
            code = bb_add(code, u8(72) + u8(137) + u8(207)) # mov rdi, rcx
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_writefile"])
            if safe_label != "":
                code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(TAG_NULL))
                pos = bb_len(code)
                code = bb_add(code, u8(15) + u8(132) + u32le(0))
                fixups = lb_add(fixups, [pos + 2, "rel", safe_label])
            end
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "appendfile":
            if len(node[2]) != 2:
                return [false, code, fixups, var_map, var_names, strings, "appendfile expects 2 args"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(80)) # push rax
            ge = gen_expr_num(node[2][1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(198)) # mov rsi, rax
            code = bb_add(code, u8(89)) # pop rcx
            code = bb_add(code, u8(72) + u8(137) + u8(207)) # mov rdi, rcx
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_appendfile"])
            if safe_label != "":
                code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(TAG_NULL))
                pos = bb_len(code)
                code = bb_add(code, u8(15) + u8(132) + u32le(0))
                fixups = lb_add(fixups, [pos + 2, "rel", safe_label])
            end
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "createdir":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "createdir expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_createdir"])
            if safe_label != "":
                code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(TAG_NULL))
                pos = bb_len(code)
                code = bb_add(code, u8(15) + u8(132) + u32le(0))
                fixups = lb_add(fixups, [pos + 2, "rel", safe_label])
            end
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "listdir":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "listdir expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_listdir"])
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "deletedir":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "deletedir expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_deletedir"])
            if safe_label != "":
                code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(TAG_NULL))
                pos = bb_len(code)
                code = bb_add(code, u8(15) + u8(132) + u32le(0))
                fixups = lb_add(fixups, [pos + 2, "rel", safe_label])
            end
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "input":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "input expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "print_val"])
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_readline"])
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "readline":
            if len(node[2]) != 0:
                return [false, code, fixups, var_map, var_names, strings, "readline expects 0 args"]
            end
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_readline"])
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "inb":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "inb expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(102) + u8(137) + u8(194))
            code = bb_add(code, u8(236))
            code = bb_add(code, u8(15) + u8(182) + u8(192))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "inw":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "inw expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(102) + u8(137) + u8(194))
            code = bb_add(code, u8(102) + u8(237))
            code = bb_add(code, u8(15) + u8(183) + u8(192))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "inl":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "inl expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(102) + u8(137) + u8(194))
            code = bb_add(code, u8(237))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "outb":
            if len(node[2]) != 2:
                return [false, code, fixups, var_map, var_names, strings, "outb expects 2 args"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(80))
            ge = gen_expr_num(node[2][1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(193))
            code = bb_add(code, u8(88))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(102) + u8(137) + u8(194))
            code = bb_add(code, u8(72) + u8(193) + u8(233) + u8(3))
            code = bb_add(code, u8(136) + u8(200))
            code = bb_add(code, u8(238))
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "outw":
            if len(node[2]) != 2:
                return [false, code, fixups, var_map, var_names, strings, "outw expects 2 args"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(80))
            ge = gen_expr_num(node[2][1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(193))
            code = bb_add(code, u8(88))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(102) + u8(137) + u8(194))
            code = bb_add(code, u8(72) + u8(193) + u8(233) + u8(3))
            code = bb_add(code, u8(102) + u8(137) + u8(200))
            code = bb_add(code, u8(102) + u8(239))
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "outl":
            if len(node[2]) != 2:
                return [false, code, fixups, var_map, var_names, strings, "outl expects 2 args"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(80))
            ge = gen_expr_num(node[2][1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(193))
            code = bb_add(code, u8(88))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(102) + u8(137) + u8(194))
            code = bb_add(code, u8(72) + u8(193) + u8(233) + u8(3))
            code = bb_add(code, u8(137) + u8(200))
            code = bb_add(code, u8(239))
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "peek8":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "peek8 expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(15) + u8(182) + u8(0))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "peek16":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "peek16 expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(15) + u8(183) + u8(0))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "peek32":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "peek32 expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(139) + u8(0))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "poke8":
            if len(node[2]) != 2:
                return [false, code, fixups, var_map, var_names, strings, "poke8 expects 2 args"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(80))
            ge = gen_expr_num(node[2][1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(193))
            code = bb_add(code, u8(88))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(193) + u8(233) + u8(3))
            code = bb_add(code, u8(136) + u8(8))
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "poke16":
            if len(node[2]) != 2:
                return [false, code, fixups, var_map, var_names, strings, "poke16 expects 2 args"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(80))
            ge = gen_expr_num(node[2][1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(193))
            code = bb_add(code, u8(88))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(193) + u8(233) + u8(3))
            code = bb_add(code, u8(102) + u8(137) + u8(8))
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "poke32":
            if len(node[2]) != 2:
                return [false, code, fixups, var_map, var_names, strings, "poke32 expects 2 args"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(80))
            ge = gen_expr_num(node[2][1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(193))
            code = bb_add(code, u8(88))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(193) + u8(233) + u8(3))
            code = bb_add(code, u8(137) + u8(8))
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "phys_read":
            if len(node[2]) != 2:
                return [false, code, fixups, var_map, var_names, strings, "phys_read expects 2 args"]
            end
            if node[2][1][0] != "num":
                return [false, code, fixups, var_map, var_names, strings, "phys_read expects constant size"]
            end
            size = node[2][1][1]
            if size == 1:
                node = ["call", ["id", "peek8"], [node[2][0]]]
                return gen_expr_num(node, code, fixups, var_map, var_names, strings, safe_label)
            elif size == 2:
                node = ["call", ["id", "peek16"], [node[2][0]]]
                return gen_expr_num(node, code, fixups, var_map, var_names, strings, safe_label)
            elif size == 4:
                node = ["call", ["id", "peek32"], [node[2][0]]]
                return gen_expr_num(node, code, fixups, var_map, var_names, strings, safe_label)
            end
            return [false, code, fixups, var_map, var_names, strings, "phys_read supports size 1, 2, or 4"]
        end
        if callee[1] == "phys_write":
            if len(node[2]) != 2:
                return [false, code, fixups, var_map, var_names, strings, "phys_write expects 2 args"]
            end
            node = ["call", ["id", "poke32"], [node[2][0], node[2][1]]]
            return gen_expr_num(node, code, fixups, var_map, var_names, strings, safe_label)
        end
        if callee[1] == "virt_to_phys":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "virt_to_phys expects 1 arg"]
            end
            return gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
        end
        if callee[1] == "mmap":
            if len(node[2]) != 3:
                return [false, code, fixups, var_map, var_names, strings, "mmap expects 3 args"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(80))
            ge = gen_expr_num(node[2][1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            ge = gen_expr_num(node[2][2], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(88))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "alloc_pages":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "alloc_pages expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "register_isr":
            if len(node[2]) != 2:
                return [false, code, fixups, var_map, var_names, strings, "register_isr expects 2 args"]
            end
            ai = len(node[2]) - 1
            while ai >= 0:
                gea = gen_expr_num(node[2][ai], code, fixups, var_map, var_names, strings, safe_label)
                if not gea[0]:
                    return gea
                end
                code = gea[1]
                fixups = gea[2]
                var_map = gea[3]
                var_names = gea[4]
                strings = gea[5]
                code = bb_add(code, u8(80))
                ai = ai - 1
            end
            if len(node[2]) > 0:
                code = bb_add(code, u8(72) + u8(129) + u8(196) + u32le(len(node[2]) * 8))
            end
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "cli":
            if len(node[2]) != 0:
                return [false, code, fixups, var_map, var_names, strings, "cli expects 0 args"]
            end
            code = bb_add(code, u8(250))
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "sti":
            if len(node[2]) != 0:
                return [false, code, fixups, var_map, var_names, strings, "sti expects 0 args"]
            end
            code = bb_add(code, u8(251))
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "hlt":
            if len(node[2]) != 0:
                return [false, code, fixups, var_map, var_names, strings, "hlt expects 0 args"]
            end
            code = bb_add(code, u8(244))
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "int":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "int expects 1 arg"]
            end
            if node[2][0][0] != "num":
                return [false, code, fixups, var_map, var_names, strings, "int expects constant vector"]
            end
            vec = node[2][0][1]
            if vec < 0 or vec > 255:
                return [false, code, fixups, var_map, var_names, strings, "int vector out of range"]
            end
            code = bb_add(code, u8(205) + u8(vec))
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "rdtsc":
            if len(node[2]) != 0:
                return [false, code, fixups, var_map, var_names, strings, "rdtsc expects 0 args"]
            end
            code = bb_add(code, u8(15) + u8(49))
            code = bb_add(code, u8(72) + u8(193) + u8(226) + u8(32))
            code = bb_add(code, u8(72) + u8(9) + u8(208))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "cpuid":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "cpuid expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(49) + u8(201))
            code = bb_add(code, u8(15) + u8(162))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "rdmsr":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "rdmsr expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(137) + u8(193))
            code = bb_add(code, u8(15) + u8(50))
            code = bb_add(code, u8(72) + u8(193) + u8(226) + u8(32))
            code = bb_add(code, u8(72) + u8(9) + u8(208))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "wrmsr":
            if len(node[2]) != 3:
                return [false, code, fixups, var_map, var_names, strings, "wrmsr expects 3 args"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(80))
            ge = gen_expr_num(node[2][1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(80))
            ge = gen_expr_num(node[2][2], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(137) + u8(194))
            code = bb_add(code, u8(89))
            code = bb_add(code, u8(72) + u8(193) + u8(249) + u8(3))
            code = bb_add(code, u8(137) + u8(200))
            code = bb_add(code, u8(89))
            code = bb_add(code, u8(72) + u8(193) + u8(249) + u8(3))
            code = bb_add(code, u8(15) + u8(48))
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "fb_init":
            if len(node[2]) != 3:
                return [false, code, fixups, var_map, var_names, strings, "fb_init expects 3 args"]
            end
            ai = len(node[2]) - 1
            while ai >= 0:
                gea = gen_expr_num(node[2][ai], code, fixups, var_map, var_names, strings, safe_label)
                if not gea[0]:
                    return gea
                end
                code = gea[1]
                fixups = gea[2]
                var_map = gea[3]
                var_names = gea[4]
                strings = gea[5]
                code = bb_add(code, u8(80))
                ai = ai - 1
            end
            if len(node[2]) > 0:
                code = bb_add(code, u8(72) + u8(129) + u8(196) + u32le(len(node[2]) * 8))
            end
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "fb_pixel":
            if len(node[2]) != 3:
                return [false, code, fixups, var_map, var_names, strings, "fb_pixel expects 3 args"]
            end
            ai = len(node[2]) - 1
            while ai >= 0:
                gea = gen_expr_num(node[2][ai], code, fixups, var_map, var_names, strings, safe_label)
                if not gea[0]:
                    return gea
                end
                code = gea[1]
                fixups = gea[2]
                var_map = gea[3]
                var_names = gea[4]
                strings = gea[5]
                code = bb_add(code, u8(80))
                ai = ai - 1
            end
            if len(node[2]) > 0:
                code = bb_add(code, u8(72) + u8(129) + u8(196) + u32le(len(node[2]) * 8))
            end
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "fb_rect":
            if len(node[2]) != 5:
                return [false, code, fixups, var_map, var_names, strings, "fb_rect expects 5 args"]
            end
            ai = len(node[2]) - 1
            while ai >= 0:
                gea = gen_expr_num(node[2][ai], code, fixups, var_map, var_names, strings, safe_label)
                if not gea[0]:
                    return gea
                end
                code = gea[1]
                fixups = gea[2]
                var_map = gea[3]
                var_names = gea[4]
                strings = gea[5]
                code = bb_add(code, u8(80))
                ai = ai - 1
            end
            if len(node[2]) > 0:
                code = bb_add(code, u8(72) + u8(129) + u8(196) + u32le(len(node[2]) * 8))
            end
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "fb_clear":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "fb_clear expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "keyboard_read" or callee[1] == "keyboard_poll" or callee[1] == "mouse_read" or callee[1] == "mouse_poll":
            if len(node[2]) != 0:
                return [false, code, fixups, var_map, var_names, strings, callee[1] + " expects 0 args"]
            end
            code = bb_add(code, u8(72) + u8(184) + u64le(TAG_NULL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "is_number":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "is_number expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(193)) # mov rcx, rax
            code = bb_add(code, u8(72) + u8(131) + u8(225) + u8(7)) # and rcx, 7
            code = bb_add(code, u8(72) + u8(131) + u8(249) + u8(TAG_INT)) # cmp rcx, TAG_INT
            code = bb_add(code, u8(15) + u8(148) + u8(192)) # sete al
            code = bb_add(code, u8(72) + u8(15) + u8(182) + u8(192)) # movzx rax, al
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_BOOL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "is_string":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "is_string expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(193)) # mov rcx, rax
            code = bb_add(code, u8(72) + u8(131) + u8(225) + u8(7)) # and rcx, 7
            code = bb_add(code, u8(72) + u8(131) + u8(249) + u8(TAG_STR)) # cmp rcx, TAG_STR
            code = bb_add(code, u8(15) + u8(148) + u8(192)) # sete al
            code = bb_add(code, u8(72) + u8(15) + u8(182) + u8(192)) # movzx rax, al
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_BOOL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "is_list":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "is_list expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(193)) # mov rcx, rax
            code = bb_add(code, u8(72) + u8(131) + u8(225) + u8(7)) # and rcx, 7
            code = bb_add(code, u8(72) + u8(131) + u8(249) + u8(TAG_LIST)) # cmp rcx, TAG_LIST
            code = bb_add(code, u8(15) + u8(148) + u8(192)) # sete al
            code = bb_add(code, u8(72) + u8(15) + u8(182) + u8(192)) # movzx rax, al
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_BOOL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "exists":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "exists expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199)) # mov rdi, rax
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_to_cstr"])
            code = bb_add(code, u8(72) + u8(137) + u8(199)) # mov rdi, rax
            code = bb_add(code, u8(72) + u8(49) + u8(246)) # xor rsi, rsi
            code = bb_add(code, u8(72) + u8(199) + u8(192) + u32le(21)) # mov rax, 21 (sys_access)
            code = bb_add(code, u8(15) + u8(5))
            code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(0)) # cmp rax, 0
            code = bb_add(code, u8(15) + u8(148) + u8(192)) # sete al
            code = bb_add(code, u8(72) + u8(15) + u8(182) + u8(192)) # movzx rax, al
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_BOOL))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "argc":
            if len(node[2]) != 0:
                return [false, code, fixups, var_map, var_names, strings, "argc expects 0 args"]
            end
            # mov rax, [__argc] - absolute address using RIP-relative or absolute
            # Using: mov rax, [addr] (48 A1 + 64-bit address for MOV RAX, moffs64)
            # Or: mov rax, [rel32] - but we need to patch the address
            # Let's use: mov rax, [rip+rel32] encoding (48 8B 05 rel32)
            argc_load_pos = bb_len(code)
            code = bb_add(code, u8(72) + u8(139) + u8(5) + u32le(0))  # mov rax, [rip+rel32]
            fixups = lb_add(fixups, [argc_load_pos + 3, "argc_data", "argc_data"])
            # rax now contains raw argc, tag it: rax = rax * 8 + TAG_INT
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))  # shl rax, 3
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))  # or rax, TAG_INT
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        if callee[1] == "argv":
            if len(node[2]) != 1:
                return [false, code, fixups, var_map, var_names, strings, "argv expects 1 arg"]
            end
            ge = gen_expr_num(node[2][0], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return ge
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            # rax = tagged index
            # Get argv pointer into rcx: mov rcx, [rip+rel32]
            argv_load_pos = bb_len(code)
            code = bb_add(code, u8(72) + u8(139) + u8(13) + u32le(0))  # mov rcx, [rip+rel32]
            fixups = lb_add(fixups, [argv_load_pos + 3, "argv_data", "argv_data"])
            # Untag index: rax = rax >> 3
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))  # sar rax, 3
            # Load argv[index]: mov rax, [rcx + rax*8]
            code = bb_add(code, u8(72) + u8(139) + u8(132) + u8(193) + u32le(0))  # mov rax, [rbx + rax*8] no, that's wrong
            # Actually: [base + index*scale + disp]
            # We want [rcx + rax*8] which is: 48 8B 04 C1
            code = bb_add(code, u8(72) + u8(139) + u8(4) + u8(193))  # mov rax, [rcx + rax*8]
            # Now rax = char* (argv[n])
            # Create a string object from C string using rt_str_alloc
            # First save rax
            code = bb_add(code, u8(80))  # push rax (save C string pointer)
            # Calculate string length - call strlen-like helper
            # Actually, we can use the existing string creation logic
            # Call rt_str_alloc to create string object
            code = bb_add(code, u8(72) + u8(137) + u8(199))  # mov rdi, rax (c string)
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))  # call rt_str_alloc
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_str_alloc"])
            # rax now points to string object with tag, just need to tag it as string
            # rt_str_alloc already returns tagged pointer, so we're done
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        ai = len(node[2]) - 1
        while ai >= 0:
            gea = gen_expr_num(node[2][ai], code, fixups, var_map, var_names, strings, safe_label)
            if not gea[0]:
                return gea
            end
            code = gea[1]
            fixups = gea[2]
            var_map = gea[3]
            var_names = gea[4]
            strings = gea[5]
            code = bb_add(code, u8(80)) # push rax
            ai = ai - 1
        end
        call_pos = bb_len(code)
        code = bb_add(code, u8(232) + u32le(0))
        fixups = lb_add(fixups, [call_pos + 1, "call", callee[1]])
        if len(node[2]) > 0:
            code = bb_add(code, u8(72) + u8(129) + u8(196) + u32le(len(node[2]) * 8))
        end
        return [true, code, fixups, var_map, var_names, strings, ""]
    end
    if node[0] == "cmp":
        op = node[1]
        grl = gen_expr_num(node[2], code, fixups, var_map, var_names, strings, safe_label)
        if not grl[0]:
            return grl
        end
        code = grl[1]
        fixups = grl[2]
        var_map = grl[3]
        var_names = grl[4]
        strings = grl[5]
        code = bb_add(code, u8(80)) # push rax
        grr = gen_expr_num(node[3], code, fixups, var_map, var_names, strings, safe_label)
        if not grr[0]:
            return grr
        end
        code = grr[1]
        fixups = grr[2]
        var_map = grr[3]
        var_names = grr[4]
        strings = grr[5]
        code = bb_add(code, u8(89)) # pop rcx
        if op == "==" or op == "!=" :
            code = bb_add(code, u8(72) + u8(137) + u8(207))
            code = bb_add(code, u8(72) + u8(137) + u8(198))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_cmp_eq"])
            if op == "!=" :
                code = bb_add(code, u8(72) + u8(131) + u8(240) + u8(1))
            end
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
            return [true, code, fixups, var_map, var_names, strings, ""]
        end
        code = bb_add(code, u8(72) + u8(193) + u8(249) + u8(3))
        code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
        code = bb_add(code, u8(72) + u8(57) + u8(193))
        if op == "<":
            code = bb_add(code, u8(15) + u8(156) + u8(192))
        elif op == "<=":
            code = bb_add(code, u8(15) + u8(158) + u8(192))
        elif op == ">":
            code = bb_add(code, u8(15) + u8(159) + u8(192))
        elif op == ">=":
            code = bb_add(code, u8(15) + u8(157) + u8(192))
        else:
            return [false, code, fixups, var_map, var_names, strings, "unsupported cmp"]
        end
        code = bb_add(code, u8(15) + u8(182) + u8(192))
        code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
        code = bb_add(code, u8(72) + u8(131) + u8(200) + u8(TAG_INT))
        return [true, code, fixups, var_map, var_names, strings, ""]
    end
    return [false, code, fixups, var_map, var_names, strings, "non-numeric expr"]
end
function rt_new_label(prefix, st):
    name = prefix + int_to_string(st[6])
    if len(st) > 8:
        st = [st[0], st[1], st[2], st[3], st[4], st[5], st[6] + 1, st[7], st[8]]
    else:
        st = [st[0], st[1], st[2], st[3], st[4], st[5], st[6] + 1, st[7]]
    end
    return [name, st]
end
function rt_emit_jmp(st, label):
    code = st[0]
    fixups = st[1]
    pos = bb_len(code)
    code = bb_add(code, u8(233) + u32le(0))
    fixups = lb_add(fixups, [pos + 1, "rel", label])
    if len(st) > 8:
        return [code, fixups, st[2], st[3], st[4], st[5], st[6], st[7], st[8]]
    end
    return [code, fixups, st[2], st[3], st[4], st[5], st[6], st[7]]
end
function rt_emit_jcc(st, opcode, label):
    code = st[0]
    fixups = st[1]
    pos = bb_len(code)
    code = bb_add(code, u8(15) + u8(opcode) + u32le(0))
    fixups = lb_add(fixups, [pos + 2, "rel", label])
    if len(st) > 8:
        return [code, fixups, st[2], st[3], st[4], st[5], st[6], st[7], st[8]]
    end
    return [code, fixups, st[2], st[3], st[4], st[5], st[6], st[7]]
end
function append_helpers(code, fixups, labels):
    h_start = bb_len(code)
    labels = env_set(labels, "rt_alloc", ["num", h_start + 0])
    labels = env_set(labels, "rt_list_new", ["num", h_start + 25])
    labels = env_set(labels, "rt_str_alloc", ["num", h_start + 49])
    labels = env_set(labels, "rt_str_concat", ["num", h_start + 65])
    labels = env_set(labels, "rt_list_concat", ["num", h_start + 127])
    labels = env_set(labels, "rt_str_eq", ["num", h_start + 201])
    labels = env_set(labels, "rt_cmp_eq", ["num", h_start + 253])
    labels = env_set(labels, "rt_val_to_bool", ["num", h_start + 300])
    labels = env_set(labels, "rt_len", ["num", h_start + 412])
    labels = env_set(labels, "rt_index", ["num", h_start + 477])
    labels = env_set(labels, "rt_num", ["num", h_start + 588])
    labels = env_set(labels, "rt_chr", ["num", h_start + 708])
    labels = env_set(labels, "rt_add", ["num", h_start + 760])
    labels = env_set(labels, "rt_to_cstr", ["num", h_start + 884])
    labels = env_set(labels, "rt_readfile", ["num", h_start + 930])
    labels = env_set(labels, "rt_writefile", ["num", h_start + 1077])
    labels = env_set(labels, "rt_appendfile", ["num", h_start + 1226])
    labels = env_set(labels, "rt_createdir", ["num", h_start + 1326])
    labels = env_set(labels, "rt_deletedir", ["num", h_start + 1372])
    labels = env_set(labels, "rt_listdir", ["num", h_start + 1627])
    labels = env_set(labels, "print_val", ["num", h_start + 1411])
    helpers_hex = "4889f84883c0074883e0f84889c1498b07488d1408498917c34889fe488d3cfd08000000e8000000004889304883c805"
    helpers_hex = helpers_hex + "c34889fe488d7f08e800000000488930c3fc4989fa4983e2f84989f34983e3f84d8b024d8b0b4c89c04c01c84889c7e8"
    helpers_hex = helpers_hex + "00000000488d7808498d72084c89c1f3a4498d73084c89c9f3a44883c804c3fc4989fa4983e2f84989f34983e3f84d8b"
    helpers_hex = helpers_hex + "024d8b0b4c89c04c01c84889c7e8000000004889c34883e3f8488d7b08498d72084c89c1f348a5498d73084c89c9f348"
    helpers_hex = helpers_hex + "a54889d84883c805c3fc4989fa4983e2f84989f34983e3f8498b0a498b134839d175174885c9740c498d7a08498d7308"
    helpers_hex = helpers_hex + "f3a67506b801000000c331c0c34889f84883e0074889f14883e1074839c875194883f804740d4889f84839f00f94c00f"
    helpers_hex = helpers_hex + "b6c0c3e800000000c331c0c34889f84883e0074883f80174154883f80274214883f804742d4883f805743c31c0c34889"
    helpers_hex = helpers_hex + "f848c1f8034883f8000f95c00fb6c0c34889f848c1f8034883f8000f95c00fb6c0c34889f84883e0f8488b004883f800"
    helpers_hex = helpers_hex + "0f95c00fb6c0c34889f84883e0f8488b004883f8000f95c00fb6c0c34889f84883e0074883f804740e4883f805741b48"
    helpers_hex = helpers_hex + "c7c001000000c34889f84883e0f8488b0048c1e0034883c801c34889f84883e0f8488b0048c1e0034883c801c34889f0"
    helpers_hex = helpers_hex + "4883e0074883f801755a4889f148c1f9034889f84883e0074883f80574084883f8047417eb3e4889fa4883e2f84c8b02"
    helpers_hex = helpers_hex + "4c39c1732f488b44ca08c34889fa4883e2f84c8b024c39c1731a448a4c0a0848c7c701000000e8000000004488480848"
    helpers_hex = helpers_hex + "83c804c348c7c003000000c34889f84883e0074883f80475634889fe4883e6f8488b0e488d76084831c04831d24883f9"
    helpers_hex = helpers_hex + "0074408a1e80fb2d7508b20148ffc648ffc94883f90074238a1e80fb30721c80fb397717486bc00a4c0fb6c34983e830"
    helpers_hex = helpers_hex + "4c01c048ffc648ffc9ebd780fa00740348f7d848c1e0034883c801c348c7c001000000c34889f84883e0074883f80175"
    helpers_hex = helpers_hex + "1f4889f848c1f8034188c148c7c701000000e800000000448848084883c804c348c7c003000000c34889f84883e00748"
    helpers_hex = helpers_hex + "83f80175274889f04883e0074883f801751a4889f848c1f8034889f148c1f9034801c848c1e0034883c801c34889f848"
    helpers_hex = helpers_hex + "83e0074883f80475134889f04883e0074883f8047506e800000000c34889f84883e0074883f80575134889f04883e007"
    helpers_hex = helpers_hex + "4883f8057506e800000000c348c7c003000000c3fc4889f84883e0f8488b08488d70084889cf4883c701e80000000048"
    helpers_hex = helpers_hex + "89c34889ca4889dff3a4c60413004889d8c3e8000000004889c74831f64831d248c7c0020000000f054883f8007c6e48"
    helpers_hex = helpers_hex + "89c34889df4831f648c7c20200000048c7c0080000000f054883f8007c434989c04889df4831f64831d248c7c0080000"
    helpers_hex = helpers_hex + "000f054c89c7e8000000004989c1498d71084889df4c89c24831c00f054889df48c7c0030000000f054c89c84883c804"
    helpers_hex = helpers_hex + "c34889df48c7c0030000000f0548c7c003000000c34989f2e8000000004989c44889c748c7c64102000048c7c2a80100"
    helpers_hex = helpers_hex + "0048c7c0020000000f054883f8007c624889c34c89d04883e0f84c8b00488d70084889df4c89c248c7c0010000000f05"
    helpers_hex = helpers_hex + "4889df48c7c0030000000f054c89d04883e0f84c8b004983f8047c1e8b480881f97f454c4675134c89e748c7c6e80100"
    helpers_hex = helpers_hex + "0048c7c05a0000000f0548c7c00a000000c348c7c003000000c34989f2e8000000004889c748c7c64104000048c7c2a8"
    helpers_hex = helpers_hex + "01000048c7c0020000000f054883f8007c344889c34c89d04883e0f84c8b00488d70084889df4c89c248c7c001000000"
    helpers_hex = helpers_hex + "0f054889df48c7c0030000000f0548c7c00a000000c348c7c003000000c3e8000000004889c748c7c6e801000048c7c0"
    helpers_hex = helpers_hex + "530000000f054883f8007c0848c7c00a000000c348c7c003000000c3e8000000004889c748c7c0540000000f054883f8"
    helpers_hex = helpers_hex + "007c0848c7c00a000000c348c7c003000000c34889f84883e0074883f80174134883f804741a4883f80274374883f803"
    helpers_hex = helpers_hex + "746ec34889f848c1f803e800000000c34889f84883e0f8488b08488d700848c7c00100000048c7c7010000004889ca0f"
    helpers_hex = helpers_hex + "05eb5b4889f848c1f8034883f8007510488d356a00000048c7c205000000eb0e488d355600000048c7c20400000048c7"
    helpers_hex = helpers_hex + "c00100000048c7c7010000000f05eb1e488d353f00000048c7c20400000048c7c00100000048c7c7010000000f05488d"
    helpers_hex = helpers_hex + "352500000048c7c20100000048c7c00100000048c7c7010000000f05c37472756566616c73656e756c6c0a4883ec40e8"
    helpers_hex = helpers_hex + "000000004889c74831f648c7c20000010048c7c0020000000f054883f8000f8c2e0100004889042448c7c700100000e8"
    helpers_hex = helpers_hex + "00000000488944240848c7c700000000e8000000004889442430488b3c24488b74240848c7c20010000048c7c0d90000"
    helpers_hex = helpers_hex + "000f054883f8000f8ece000000488944241048c7442418000000004c8b7424184c8b6c24104d39ee7dc0488b5c240842"
    helpers_hex = helpers_hex + "0fb74c33104e8d4c33134831d2418a04113c00740548ffc2ebf34c894c242048895424284901ce4c89742418488b7424"
    helpers_hex = helpers_hex + "20488b5424284883fa0175068a063c2e74a94883fa02750d8a063c2e75078a46013c2e7496488b7c2428e80000000048"
    helpers_hex = helpers_hex + "8b4c2428488b742420488d7808f3a44883c804488944242848c7c701000000e8000000004889c34883e3f8488b4c2428"
    helpers_hex = helpers_hex + "48894b08488b7c24304889c6e8000000004889442430e940ffffff488b3c2448c7c0030000000f05488b4424304883c4"
    helpers_hex = helpers_hex + "40c348c7c700000000e8000000004883c440c3"
    h_len = idiv(len(helpers_hex), 2)
    labels = env_set(labels, "rt_readline", ["num", h_start + h_len])
    helpers_hex = helpers_hex + "48c7c7001000004889fe488d7f084889f84883c0074883e0f84889c1498b07488d14084989174889304989c1498d71084831ff48c7c2001000004831c00f054883f8007e414889c14d31c04939c87d2b438a4401083c0a740549ffc0ebed4983f800740c438a4401073c0d750349ffc84d89014c89c84883c804c34989094c89c84883c804c349c701000000004c89c84883c804c3"
    helpers = hex_to_bytes(helpers_hex)
    # patch rt_listdir to print entries while preserving list result
    listdir_patch = hex_to_bytes("4883c8044889c34889c7e80000000048c7c701000000e800000000488d50fb48895a08488b7c24304889c6e8000000004889442430e942ffffff90")
    helpers = bytes_patch(helpers, 1887, listdir_patch)
    code = bb_add(code, helpers)
    fixups = lb_add(fixups, [h_start + 37, "call", "rt_alloc"])
    fixups = lb_add(fixups, [h_start + 57, "call", "rt_alloc"])
    fixups = lb_add(fixups, [h_start + 96, "call", "rt_str_alloc"])
    fixups = lb_add(fixups, [h_start + 158, "call", "rt_list_new"])
    fixups = lb_add(fixups, [h_start + 292, "call", "rt_str_eq"])
    fixups = lb_add(fixups, [h_start + 567, "call", "rt_str_alloc"])
    fixups = lb_add(fixups, [h_start + 739, "call", "rt_str_alloc"])
    fixups = lb_add(fixups, [h_start + 839, "call", "rt_str_concat"])
    fixups = lb_add(fixups, [h_start + 871, "call", "rt_list_concat"])
    fixups = lb_add(fixups, [h_start + 907, "call", "rt_alloc"])
    fixups = lb_add(fixups, [h_start + 931, "call", "rt_to_cstr"])
    fixups = lb_add(fixups, [h_start + 1015, "call", "rt_str_alloc"])
    fixups = lb_add(fixups, [h_start + 1081, "call", "rt_to_cstr"])
    fixups = lb_add(fixups, [h_start + 1230, "call", "rt_to_cstr"])
    fixups = lb_add(fixups, [h_start + 1327, "call", "rt_to_cstr"])
    fixups = lb_add(fixups, [h_start + 1373, "call", "rt_to_cstr"])
    fixups = lb_add(fixups, [h_start + 1451, "call", "print_num"])
    fixups = lb_add(fixups, [h_start + 1632, "call", "rt_to_cstr"])
    fixups = lb_add(fixups, [h_start + 1680, "call", "rt_alloc"])
    fixups = lb_add(fixups, [h_start + 1697, "call", "rt_list_new"])
    fixups = lb_add(fixups, [h_start + 1867, "call", "rt_str_alloc"])
    fixups = lb_add(fixups, [h_start + 1898, "call", "print_val"])
    fixups = lb_add(fixups, [h_start + 1910, "call", "rt_list_new"])
    fixups = lb_add(fixups, [h_start + 1931, "call", "rt_list_concat"])
    fixups = lb_add(fixups, [h_start + 1978, "call", "rt_list_new"])
    return [code, fixups, labels]
end
function rt_emit_stmt_list(stmts, st):
    code = st[0]
    fixups = st[1]
    labels = st[2]
    var_map = st[3]
    var_names = st[4]
    strings = st[5]
    label_counter = st[6]
    loop_stack = st[7]
    safe_label = ""
    if len(st) > 8:
        safe_label = st[8]
    end
    si = 0
    loop len(stmts):
        st_stmt = stmts[si]
        if st_stmt[0] == "assign":
            ge = gen_expr_num(st_stmt[2], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            ve = env_get(var_map, st_stmt[1])
            if ve[0] == "missing":
                vr = var_ensure(var_map, var_names, st_stmt[1])
                var_map = vr[0]
                var_names = vr[1]
                ve = env_get(var_map, st_stmt[1])
            end
            if ve[0] == "param":
                code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(ve[1])))
            else:
                offset = 0 - ((ve[1] + 1) * 8)
                code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(offset)))
            end
        elif st_stmt[0] == "print":
            ge = gen_expr_num(st_stmt[1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "print_val"])
        elif st_stmt[0] == "expr":
            ge = gen_expr_num(st_stmt[1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
        elif st_stmt[0] == "wait":
            ge = gen_expr_num(st_stmt[1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            # rax = tagged int seconds; use nanosleep syscall
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(0))
            w_skip = "waitskip" + int_to_string(label_counter)
            label_counter = label_counter + 1
            pos = bb_len(code)
            code = bb_add(code, u8(15) + u8(142) + u32le(0))
            fixups = lb_add(fixups, [pos + 2, "rel", w_skip])
            code = bb_add(code, u8(72) + u8(131) + u8(236) + u8(16))
            code = bb_add(code, u8(72) + u8(137) + u8(4) + u8(36))
            code = bb_add(code, u8(72) + u8(49) + u8(201))
            code = bb_add(code, u8(72) + u8(137) + u8(76) + u8(36) + u8(8))
            code = bb_add(code, u8(72) + u8(137) + u8(231))
            code = bb_add(code, u8(72) + u8(49) + u8(246))
            code = bb_add(code, u8(72) + u8(199) + u8(192) + u32le(35))
            code = bb_add(code, u8(15) + u8(5))
            code = bb_add(code, u8(72) + u8(131) + u8(196) + u8(16))
            labels = env_set(labels, w_skip, ["num", bb_len(code)])
        elif st_stmt[0] == "return":
            ge = gen_expr_num(st_stmt[1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = bb_add(ge[1], u8(201) + u8(195))
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
        elif st_stmt[0] == "break":
            if len(loop_stack) == 0:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "break outside loop"]
            end
            br = loop_stack[len(loop_stack) - 1]
            pos = bb_len(code)
            code = bb_add(code, u8(233) + u32le(0))
            fixups = lb_add(fixups, [pos + 1, "rel", br[0]])
        elif st_stmt[0] == "continue":
            if len(loop_stack) == 0:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "continue outside loop"]
            end
            br = loop_stack[len(loop_stack) - 1]
            pos = bb_len(code)
            code = bb_add(code, u8(233) + u32le(0))
            fixups = lb_add(fixups, [pos + 1, "rel", br[1]])
        elif st_stmt[0] == "if":
            ge = gen_expr_num(st_stmt[1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_val_to_bool"])
            code = bb_add(code, u8(72) + u8(133) + u8(192))
            else_label = "else" + int_to_string(label_counter)
            label_counter = label_counter + 1
            end_label = "endif" + int_to_string(label_counter)
            label_counter = label_counter + 1
            pos = bb_len(code)
            code = bb_add(code, u8(15) + u8(132) + u32le(0))
            fixups = lb_add(fixups, [pos + 2, "rel", else_label])
            res = rt_emit_stmt_list(st_stmt[2], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label])
            if not res[0]:
                return res
            end
            code = res[1][0]
            fixups = res[1][1]
            labels = res[1][2]
            var_map = res[1][3]
            var_names = res[1][4]
            strings = res[1][5]
            label_counter = res[1][6]
            loop_stack = res[1][7]
            pos = bb_len(code)
            code = bb_add(code, u8(233) + u32le(0))
            fixups = lb_add(fixups, [pos + 1, "rel", end_label])
            labels = env_set(labels, else_label, ["num", bb_len(code)])
            res = rt_emit_stmt_list(st_stmt[3], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label])
            if not res[0]:
                return res
            end
            code = res[1][0]
            fixups = res[1][1]
            labels = res[1][2]
            var_map = res[1][3]
            var_names = res[1][4]
            strings = res[1][5]
            label_counter = res[1][6]
            loop_stack = res[1][7]
            labels = env_set(labels, end_label, ["num", bb_len(code)])
        elif st_stmt[0] == "switch":
            ge = gen_expr_num(st_stmt[1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            sw_name = "__switch" + int_to_string(label_counter)
            label_counter = label_counter + 1
            vr = var_ensure(var_map, var_names, sw_name)
            var_map = vr[0]
            var_names = vr[1]
            ve_sw = env_get(var_map, sw_name)
            sw_off = 0 - ((ve_sw[1] + 1) * 8)
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(sw_off)))
            end_label = "swend" + int_to_string(label_counter)
            label_counter = label_counter + 1
            ci = 0
            loop len(st_stmt[2]):
                case = st_stmt[2][ci]
                next_label = "swcase" + int_to_string(label_counter)
                label_counter = label_counter + 1
                code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(sw_off)))
                code = bb_add(code, u8(80)) # push rax
                ge2 = gen_expr_num(case[0], code, fixups, var_map, var_names, strings, safe_label)
                if not ge2[0]:
                    return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge2[6]]
                end
                code = ge2[1]
                fixups = ge2[2]
                var_map = ge2[3]
                var_names = ge2[4]
                strings = ge2[5]
                code = bb_add(code, u8(89)) # pop rcx
                code = bb_add(code, u8(72) + u8(137) + u8(207))
                code = bb_add(code, u8(72) + u8(137) + u8(198))
                call_pos = bb_len(code)
                code = bb_add(code, u8(232) + u32le(0))
                fixups = lb_add(fixups, [call_pos + 1, "call", "rt_cmp_eq"])
                code = bb_add(code, u8(72) + u8(133) + u8(192))
                pos = bb_len(code)
                code = bb_add(code, u8(15) + u8(132) + u32le(0))
                fixups = lb_add(fixups, [pos + 2, "rel", next_label])
                res = rt_emit_stmt_list(case[1], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label])
                if not res[0]:
                    return res
                end
                code = res[1][0]
                fixups = res[1][1]
                labels = res[1][2]
                var_map = res[1][3]
                var_names = res[1][4]
                strings = res[1][5]
                label_counter = res[1][6]
                loop_stack = res[1][7]
                pos = bb_len(code)
                code = bb_add(code, u8(233) + u32le(0))
                fixups = lb_add(fixups, [pos + 1, "rel", end_label])
                labels = env_set(labels, next_label, ["num", bb_len(code)])
                ci = ci + 1
            end
            res = rt_emit_stmt_list(st_stmt[3], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label])
            if not res[0]:
                return res
            end
            code = res[1][0]
            fixups = res[1][1]
            labels = res[1][2]
            var_map = res[1][3]
            var_names = res[1][4]
            strings = res[1][5]
            label_counter = res[1][6]
            loop_stack = res[1][7]
            labels = env_set(labels, end_label, ["num", bb_len(code)])
        elif st_stmt[0] == "while":
            start_label = "while" + int_to_string(label_counter)
            label_counter = label_counter + 1
            end_label = "wend" + int_to_string(label_counter)
            label_counter = label_counter + 1
            loop_stack = loop_stack + [[end_label, start_label]]
            labels = env_set(labels, start_label, ["num", bb_len(code)])
            ge = gen_expr_num(st_stmt[1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_val_to_bool"])
            code = bb_add(code, u8(72) + u8(133) + u8(192))
            pos = bb_len(code)
            code = bb_add(code, u8(15) + u8(132) + u32le(0))
            fixups = lb_add(fixups, [pos + 2, "rel", end_label])
            res = rt_emit_stmt_list(st_stmt[2], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label])
            if not res[0]:
                return res
            end
            code = res[1][0]
            fixups = res[1][1]
            labels = res[1][2]
            var_map = res[1][3]
            var_names = res[1][4]
            strings = res[1][5]
            label_counter = res[1][6]
            loop_stack = res[1][7]
            pos = bb_len(code)
            code = bb_add(code, u8(233) + u32le(0))
            fixups = lb_add(fixups, [pos + 1, "rel", start_label])
            labels = env_set(labels, end_label, ["num", bb_len(code)])
            lp = list_pop(loop_stack)
            loop_stack = lp[0]
        elif st_stmt[0] == "repeat":
            start_label = "rstart" + int_to_string(label_counter)
            label_counter = label_counter + 1
            end_label = "rend" + int_to_string(label_counter)
            label_counter = label_counter + 1
            cont_label = "rcheck" + int_to_string(label_counter)
            label_counter = label_counter + 1
            loop_stack = loop_stack + [[end_label, cont_label]]
            labels = env_set(labels, start_label, ["num", bb_len(code)])
            res = rt_emit_stmt_list(st_stmt[2], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label])
            if not res[0]:
                return res
            end
            code = res[1][0]
            fixups = res[1][1]
            labels = res[1][2]
            var_map = res[1][3]
            var_names = res[1][4]
            strings = res[1][5]
            label_counter = res[1][6]
            loop_stack = res[1][7]
            labels = env_set(labels, cont_label, ["num", bb_len(code)])
            ge = gen_expr_num(st_stmt[1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_val_to_bool"])
            code = bb_add(code, u8(72) + u8(133) + u8(192))
            pos = bb_len(code)
            code = bb_add(code, u8(15) + u8(132) + u32le(0))
            fixups = lb_add(fixups, [pos + 2, "rel", start_label])
            labels = env_set(labels, end_label, ["num", bb_len(code)])
            lp = list_pop(loop_stack)
            loop_stack = lp[0]
        elif st_stmt[0] == "do":
            start_label = "dstart" + int_to_string(label_counter)
            label_counter = label_counter + 1
            check_label = "dcheck" + int_to_string(label_counter)
            label_counter = label_counter + 1
            end_label = "dend" + int_to_string(label_counter)
            label_counter = label_counter + 1
            loop_stack = loop_stack + [[end_label, check_label]]
            labels = env_set(labels, start_label, ["num", bb_len(code)])
            res = rt_emit_stmt_list(st_stmt[2], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label])
            if not res[0]:
                return res
            end
            code = res[1][0]
            fixups = res[1][1]
            labels = res[1][2]
            var_map = res[1][3]
            var_names = res[1][4]
            strings = res[1][5]
            label_counter = res[1][6]
            loop_stack = res[1][7]
            labels = env_set(labels, check_label, ["num", bb_len(code)])
            ge = gen_expr_num(st_stmt[1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_val_to_bool"])
            code = bb_add(code, u8(72) + u8(133) + u8(192))
            pos = bb_len(code)
            code = bb_add(code, u8(15) + u8(132) + u32le(0))
            fixups = lb_add(fixups, [pos + 2, "rel", end_label])
            pos = bb_len(code)
            code = bb_add(code, u8(233) + u32le(0))
            fixups = lb_add(fixups, [pos + 1, "rel", start_label])
            labels = env_set(labels, end_label, ["num", bb_len(code)])
            lp = list_pop(loop_stack)
            loop_stack = lp[0]
        elif st_stmt[0] == "safe":
            safe_err = "safeerr" + int_to_string(label_counter)
            label_counter = label_counter + 1
            safe_end = "safeend" + int_to_string(label_counter)
            label_counter = label_counter + 1
            prev_safe = safe_label
            res = rt_emit_stmt_list(st_stmt[1], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_err])
            if not res[0]:
                return res
            end
            code = res[1][0]
            fixups = res[1][1]
            labels = res[1][2]
            var_map = res[1][3]
            var_names = res[1][4]
            strings = res[1][5]
            label_counter = res[1][6]
            loop_stack = res[1][7]
            safe_label = prev_safe
            pos = bb_len(code)
            code = bb_add(code, u8(233) + u32le(0))
            fixups = lb_add(fixups, [pos + 1, "rel", safe_end])
            labels = env_set(labels, safe_err, ["num", bb_len(code)])
            res = rt_emit_stmt_list(st_stmt[2], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, prev_safe])
            if not res[0]:
                return res
            end
            code = res[1][0]
            fixups = res[1][1]
            labels = res[1][2]
            var_map = res[1][3]
            var_names = res[1][4]
            strings = res[1][5]
            label_counter = res[1][6]
            loop_stack = res[1][7]
            labels = env_set(labels, safe_end, ["num", bb_len(code)])
        elif st_stmt[0] == "forin":
            ge = gen_expr_num(st_stmt[2], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            list_name = "__for_list" + int_to_string(label_counter)
            label_counter = label_counter + 1
            idx_name = "__for_idx" + int_to_string(label_counter)
            label_counter = label_counter + 1
            len_name = "__for_len" + int_to_string(label_counter)
            label_counter = label_counter + 1
            vr = var_ensure(var_map, var_names, list_name)
            var_map = vr[0]
            var_names = vr[1]
            vr = var_ensure(var_map, var_names, idx_name)
            var_map = vr[0]
            var_names = vr[1]
            vr = var_ensure(var_map, var_names, len_name)
            var_map = vr[0]
            var_names = vr[1]
            ve_list = env_get(var_map, list_name)
            ve_idx = env_get(var_map, idx_name)
            ve_len = env_get(var_map, len_name)
            loff = 0 - ((ve_list[1] + 1) * 8)
            ioff = 0 - ((ve_idx[1] + 1) * 8)
            lenoff = 0 - ((ve_len[1] + 1) * 8)
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(loff)))
            code = bb_add(code, u8(72) + u8(184) + u64le(1))
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(ioff)))
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(loff)))
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_len"])
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(lenoff)))
            start_label = "forstart" + int_to_string(label_counter)
            label_counter = label_counter + 1
            end_label = "forend" + int_to_string(label_counter)
            label_counter = label_counter + 1
            cont_label = "forcont" + int_to_string(label_counter)
            label_counter = label_counter + 1
            loop_stack = loop_stack + [[end_label, cont_label]]
            labels = env_set(labels, start_label, ["num", bb_len(code)])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(lenoff)))
            code = bb_add(code, u8(72) + u8(137) + u8(193))
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(ioff)))
            code = bb_add(code, u8(72) + u8(57) + u8(200))
            pos = bb_len(code)
            code = bb_add(code, u8(15) + u8(141) + u32le(0))
            fixups = lb_add(fixups, [pos + 2, "rel", end_label])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(loff)))
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(ioff)))
            code = bb_add(code, u8(72) + u8(137) + u8(198))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_index"])
            ve = env_get(var_map, st_stmt[1])
            if ve[0] == "missing":
                vr = var_ensure(var_map, var_names, st_stmt[1])
                var_map = vr[0]
                var_names = vr[1]
                ve = env_get(var_map, st_stmt[1])
            end
            if ve[0] == "param":
                code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(ve[1])))
            else:
                offset = 0 - ((ve[1] + 1) * 8)
                code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(offset)))
            end
            res = rt_emit_stmt_list(st_stmt[3], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label])
            if not res[0]:
                return res
            end
            code = res[1][0]
            fixups = res[1][1]
            labels = res[1][2]
            var_map = res[1][3]
            var_names = res[1][4]
            strings = res[1][5]
            label_counter = res[1][6]
            loop_stack = res[1][7]
            labels = env_set(labels, cont_label, ["num", bb_len(code)])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(ioff)))
            code = bb_add(code, u8(72) + u8(131) + u8(192) + u8(8))
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(ioff)))
            pos = bb_len(code)
            code = bb_add(code, u8(233) + u32le(0))
            fixups = lb_add(fixups, [pos + 1, "rel", start_label])
            labels = env_set(labels, end_label, ["num", bb_len(code)])
            lp = list_pop(loop_stack)
            loop_stack = lp[0]
        elif st_stmt[0] == "forin2":
            ge = gen_expr_num(st_stmt[3], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            list_name = "__for_list" + int_to_string(label_counter)
            label_counter = label_counter + 1
            idx_name = "__for_idx" + int_to_string(label_counter)
            label_counter = label_counter + 1
            len_name = "__for_len" + int_to_string(label_counter)
            label_counter = label_counter + 1
            vr = var_ensure(var_map, var_names, list_name)
            var_map = vr[0]
            var_names = vr[1]
            vr = var_ensure(var_map, var_names, idx_name)
            var_map = vr[0]
            var_names = vr[1]
            vr = var_ensure(var_map, var_names, len_name)
            var_map = vr[0]
            var_names = vr[1]
            ve_list = env_get(var_map, list_name)
            ve_idx = env_get(var_map, idx_name)
            ve_len = env_get(var_map, len_name)
            loff = 0 - ((ve_list[1] + 1) * 8)
            ioff = 0 - ((ve_idx[1] + 1) * 8)
            lenoff = 0 - ((ve_len[1] + 1) * 8)
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(loff)))
            code = bb_add(code, u8(72) + u8(184) + u64le(1))
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(ioff)))
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(loff)))
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_len"])
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(lenoff)))
            start_label = "forstart" + int_to_string(label_counter)
            label_counter = label_counter + 1
            end_label = "forend" + int_to_string(label_counter)
            label_counter = label_counter + 1
            cont_label = "forcont" + int_to_string(label_counter)
            label_counter = label_counter + 1
            loop_stack = loop_stack + [[end_label, cont_label]]
            labels = env_set(labels, start_label, ["num", bb_len(code)])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(lenoff)))
            code = bb_add(code, u8(72) + u8(137) + u8(193))
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(ioff)))
            code = bb_add(code, u8(72) + u8(57) + u8(200))
            pos = bb_len(code)
            code = bb_add(code, u8(15) + u8(141) + u32le(0))
            fixups = lb_add(fixups, [pos + 2, "rel", end_label])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(loff)))
            code = bb_add(code, u8(72) + u8(137) + u8(199))
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(ioff)))
            code = bb_add(code, u8(72) + u8(137) + u8(198))
            call_pos = bb_len(code)
            code = bb_add(code, u8(232) + u32le(0))
            fixups = lb_add(fixups, [call_pos + 1, "call", "rt_index"])
            ve = env_get(var_map, st_stmt[1])
            if ve[0] == "missing":
                vr = var_ensure(var_map, var_names, st_stmt[1])
                var_map = vr[0]
                var_names = vr[1]
                ve = env_get(var_map, st_stmt[1])
            end
            if ve[0] == "param":
                code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(ve[1])))
            else:
                offset = 0 - ((ve[1] + 1) * 8)
                code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(offset)))
            end
            ve_idxuser = env_get(var_map, st_stmt[2])
            if ve_idxuser[0] == "missing":
                vr = var_ensure(var_map, var_names, st_stmt[2])
                var_map = vr[0]
                var_names = vr[1]
                ve_idxuser = env_get(var_map, st_stmt[2])
            end
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(ioff)))
            if ve_idxuser[0] == "param":
                code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(ve_idxuser[1])))
            else:
                offset = 0 - ((ve_idxuser[1] + 1) * 8)
                code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(offset)))
            end
            res = rt_emit_stmt_list(st_stmt[4], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label])
            if not res[0]:
                return res
            end
            code = res[1][0]
            fixups = res[1][1]
            labels = res[1][2]
            var_map = res[1][3]
            var_names = res[1][4]
            strings = res[1][5]
            label_counter = res[1][6]
            loop_stack = res[1][7]
            labels = env_set(labels, cont_label, ["num", bb_len(code)])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(ioff)))
            code = bb_add(code, u8(72) + u8(131) + u8(192) + u8(8))
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(ioff)))
            pos = bb_len(code)
            code = bb_add(code, u8(233) + u32le(0))
            fixups = lb_add(fixups, [pos + 1, "rel", start_label])
            labels = env_set(labels, end_label, ["num", bb_len(code)])
            lp = list_pop(loop_stack)
            loop_stack = lp[0]
        elif st_stmt[0] == "forrange":
            ge = gen_expr_num(st_stmt[2], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            ve_cur = env_get(var_map, st_stmt[1])
            if ve_cur[0] == "missing":
                vr = var_ensure(var_map, var_names, st_stmt[1])
                var_map = vr[0]
                var_names = vr[1]
                ve_cur = env_get(var_map, st_stmt[1])
            end
            if ve_cur[0] == "param":
                code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(ve_cur[1])))
                cur_off = ve_cur[1]
            else:
                cur_off = 0 - ((ve_cur[1] + 1) * 8)
                code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(cur_off)))
            end
            end_name = "__for_end" + int_to_string(label_counter)
            label_counter = label_counter + 1
            step_name = "__for_step" + int_to_string(label_counter)
            label_counter = label_counter + 1
            pos_name = "__for_pos" + int_to_string(label_counter)
            label_counter = label_counter + 1
            vr = var_ensure(var_map, var_names, end_name)
            var_map = vr[0]
            var_names = vr[1]
            vr = var_ensure(var_map, var_names, step_name)
            var_map = vr[0]
            var_names = vr[1]
            vr = var_ensure(var_map, var_names, pos_name)
            var_map = vr[0]
            var_names = vr[1]
            ve_end = env_get(var_map, end_name)
            ve_step = env_get(var_map, step_name)
            ve_pos = env_get(var_map, pos_name)
            end_off = 0 - ((ve_end[1] + 1) * 8)
            step_off = 0 - ((ve_step[1] + 1) * 8)
            pos_off = 0 - ((ve_pos[1] + 1) * 8)
            ge = gen_expr_num(st_stmt[3], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(end_off)))
            ge = gen_expr_num(st_stmt[4], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(step_off)))
            step_ok = "forstepok" + int_to_string(label_counter)
            label_counter = label_counter + 1
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(step_off)))
            code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(1))
            pos = bb_len(code)
            code = bb_add(code, u8(15) + u8(133) + u32le(0))
            fixups = lb_add(fixups, [pos + 2, "rel", step_ok])
            code = bb_add(code, u8(72) + u8(184) + u64le(9))
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(step_off)))
            labels = env_set(labels, step_ok, ["num", bb_len(code)])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(step_off)))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(0))
            code = bb_add(code, u8(15) + u8(159) + u8(192))
            code = bb_add(code, u8(72) + u8(15) + u8(182) + u8(192))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(192) + u8(2))
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(pos_off)))
            check_label = "forcheck" + int_to_string(label_counter)
            label_counter = label_counter + 1
            neg_label = "forneg" + int_to_string(label_counter)
            label_counter = label_counter + 1
            body_label = "forbody" + int_to_string(label_counter)
            label_counter = label_counter + 1
            cont_label = "forcont" + int_to_string(label_counter)
            label_counter = label_counter + 1
            end_label = "forend" + int_to_string(label_counter)
            label_counter = label_counter + 1
            loop_stack = loop_stack + [[end_label, cont_label]]
            labels = env_set(labels, check_label, ["num", bb_len(code)])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(pos_off)))
            code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(10))
            pos = bb_len(code)
            code = bb_add(code, u8(15) + u8(133) + u32le(0))
            fixups = lb_add(fixups, [pos + 2, "rel", neg_label])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(cur_off)))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(139) + u8(141) + u32le(rel32(end_off)))
            code = bb_add(code, u8(72) + u8(193) + u8(249) + u8(3))
            code = bb_add(code, u8(72) + u8(57) + u8(200))
            pos = bb_len(code)
            code = bb_add(code, u8(15) + u8(141) + u32le(0))
            fixups = lb_add(fixups, [pos + 2, "rel", end_label])
            pos = bb_len(code)
            code = bb_add(code, u8(233) + u32le(0))
            fixups = lb_add(fixups, [pos + 1, "rel", body_label])
            labels = env_set(labels, neg_label, ["num", bb_len(code)])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(cur_off)))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(139) + u8(141) + u32le(rel32(end_off)))
            code = bb_add(code, u8(72) + u8(193) + u8(249) + u8(3))
            code = bb_add(code, u8(72) + u8(57) + u8(200))
            pos = bb_len(code)
            code = bb_add(code, u8(15) + u8(142) + u32le(0))
            fixups = lb_add(fixups, [pos + 2, "rel", end_label])
            pos = bb_len(code)
            code = bb_add(code, u8(233) + u32le(0))
            fixups = lb_add(fixups, [pos + 1, "rel", body_label])
            labels = env_set(labels, body_label, ["num", bb_len(code)])
            res = rt_emit_stmt_list(st_stmt[5], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label])
            if not res[0]:
                return res
            end
            code = res[1][0]
            fixups = res[1][1]
            labels = res[1][2]
            var_map = res[1][3]
            var_names = res[1][4]
            strings = res[1][5]
            label_counter = res[1][6]
            loop_stack = res[1][7]
            labels = env_set(labels, cont_label, ["num", bb_len(code)])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(cur_off)))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(139) + u8(141) + u32le(rel32(step_off)))
            code = bb_add(code, u8(72) + u8(193) + u8(249) + u8(3))
            code = bb_add(code, u8(72) + u8(1) + u8(200))
            code = bb_add(code, u8(72) + u8(193) + u8(224) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(192) + u8(1))
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(cur_off)))
            pos = bb_len(code)
            code = bb_add(code, u8(233) + u32le(0))
            fixups = lb_add(fixups, [pos + 1, "rel", check_label])
            labels = env_set(labels, end_label, ["num", bb_len(code)])
            lp = list_pop(loop_stack)
            loop_stack = lp[0]
        elif st_stmt[0] == "loop":
            ge = gen_expr_num(st_stmt[1], code, fixups, var_map, var_names, strings, safe_label)
            if not ge[0]:
                return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: " + ge[6]]
            end
            code = ge[1]
            fixups = ge[2]
            var_map = ge[3]
            var_names = ge[4]
            strings = ge[5]
            lname = "__loop" + int_to_string(label_counter)
            label_counter = label_counter + 1
            vr = var_ensure(var_map, var_names, lname)
            var_map = vr[0]
            var_names = vr[1]
            ve = env_get(var_map, lname)
            loff = 0 - ((ve[1] + 1) * 8)
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(loff)))
            start_label = "lstart" + int_to_string(label_counter)
            label_counter = label_counter + 1
            end_label = "lend" + int_to_string(label_counter)
            label_counter = label_counter + 1
            cont_label = "lcont" + int_to_string(label_counter)
            label_counter = label_counter + 1
            loop_stack = loop_stack + [[end_label, cont_label]]
            labels = env_set(labels, start_label, ["num", bb_len(code)])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(loff)))
            code = bb_add(code, u8(72) + u8(193) + u8(248) + u8(3))
            code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(0))
            pos = bb_len(code)
            code = bb_add(code, u8(15) + u8(142) + u32le(0))
            fixups = lb_add(fixups, [pos + 2, "rel", end_label])
            res = rt_emit_stmt_list(st_stmt[2], [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label])
            if not res[0]:
                return res
            end
            code = res[1][0]
            fixups = res[1][1]
            labels = res[1][2]
            var_map = res[1][3]
            var_names = res[1][4]
            strings = res[1][5]
            label_counter = res[1][6]
            loop_stack = res[1][7]
            labels = env_set(labels, cont_label, ["num", bb_len(code)])
            code = bb_add(code, u8(72) + u8(139) + u8(133) + u32le(rel32(loff)))
            code = bb_add(code, u8(72) + u8(131) + u8(232) + u8(8))
            code = bb_add(code, u8(72) + u8(137) + u8(133) + u32le(rel32(loff)))
            pos = bb_len(code)
            code = bb_add(code, u8(233) + u32le(0))
            fixups = lb_add(fixups, [pos + 1, "rel", start_label])
            labels = env_set(labels, end_label, ["num", bb_len(code)])
            lp = list_pop(loop_stack)
            loop_stack = lp[0]
        else:
            return [false, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], "runtime unsupported: statement"]
        end
        si = si + 1
    end
    return [true, [code, fixups, labels, var_map, var_names, strings, label_counter, loop_stack, safe_label], ""]
end
function compile_runtime_numeric(source, source_path, baremetal):
    cr_stmts = []
    cr_err = ""
    if source_path == null:
        source_path = ""
    end
    do_progress = len(source) > 5000
    prog_last = -1
    if do_progress and prog_last != 1:
        progress(1, "start")
        prog_last = 1
    end
    cr_ranges = split_line_ranges(source)
    if do_progress and prog_last != 5:
        progress(5, "split lines")
        prog_last = 5
    end
    cr_tl = tokenize_ranges(source, cr_ranges, source_path)
    if cr_tl[1] != "":
        if starts_with(cr_tl[1], "[ ERROR"):
            return ["", cr_tl[1]]
        end
        if source_path != "":
            return ["", source_path + ": " + cr_tl[1]]
        end
        return ["", cr_tl[1]]
    end
    if do_progress and prog_last != 15:
        progress(15, "tokenize")
        prog_last = 15
    end
    cr_parse = parse_block_lines(cr_tl[0], 0, ["<eof>"])
    if cr_parse[2] != "":
        if starts_with(cr_parse[2], "[ ERROR"):
            return ["", cr_parse[2]]
        end
        if source_path != "":
            return ["", source_path + ": " + cr_parse[2]]
        end
        return ["", cr_parse[2]]
    end
    cr_stmts = cr_parse[0]
    if do_progress and prog_last != 30:
        progress(30, "parse")
        prog_last = 30
    end
    base_dir = "."
    if source_path != "":
        base_dir = path_dirname(source_path)
    end
    seen = env_bucket_new()
    if source_path != "":
        seen = env_set(seen, source_path, 1)
    end
    exp = expand_use_stmts(cr_stmts, base_dir, source_path, seen)
    if not exp[0]:
        return ["", exp[3]]
    end
    cr_stmts = exp[1]
    main_stmts = []
    func_stmts = []
    class_stmts = []
    si = 0
    loop len(cr_stmts):
        if cr_stmts[si][0] == "function":
            func_stmts = func_stmts + [cr_stmts[si]]
        elif cr_stmts[si][0] == "class":
            class_stmts = class_stmts + [cr_stmts[si]]
        else:
            main_stmts = main_stmts + [cr_stmts[si]]
        end
        si = si + 1
    end
    # inject prelude (builtin helpers) if available
    pre = parse_prelude()
    if not pre[0]:
        return ["", pre[2]]
    end
    pre_stmts = pre[1]
    if len(pre_stmts) > 0:
        pre_main = []
        pre_funcs = []
        pre_classes = []
        pi = 0
        loop len(pre_stmts):
            if pre_stmts[pi][0] == "function":
                pre_funcs = pre_funcs + [pre_stmts[pi]]
            elif pre_stmts[pi][0] == "class":
                pre_classes = pre_classes + [pre_stmts[pi]]
            else:
                pre_main = pre_main + [pre_stmts[pi]]
            end
            pi = pi + 1
        end
        # prepend prelude main statements
        if len(pre_main) > 0:
            main_stmts = pre_main + main_stmts
        end
        # append prelude classes
        if len(pre_classes) > 0:
            class_stmts = pre_classes + class_stmts
        end
        # append prelude functions if missing
        pi = 0
        loop len(pre_funcs):
            pf = pre_funcs[pi]
            if not has_function(func_stmts, pf[1]):
                func_stmts = func_stmts + [pf]
            end
            pi = pi + 1
        end
    end
    # inject stdlib library functions by default (safe no-op if missing)
    lib_paths = ["stdlib/string.lsl", "stdlib/list.lsl", "stdlib/math.lsl", "stdlib/advanced.lsl"]
    li = 0
    loop len(lib_paths):
        lf = parse_lib_functions(lib_paths[li])
        if not lf[0]:
            return ["", lf[2]]
        end
        lfuncs = lf[1]
        fi = 0
        loop len(lfuncs):
            f = lfuncs[fi]
            if not has_function(func_stmts, f[1]):
                func_stmts = func_stmts + [f]
            end
            fi = fi + 1
        end
        li = li + 1
    end
    class_methods = []
    max_arity = 0
    ci = 0
    loop len(class_stmts):
        cls = class_stmts[ci]
        cname = cls[1]
        methods = cls[2]
        init_params = null
        mi = 0
        loop len(methods):
            m = methods[mi]
            mname = m[1]
            mparams = m[2]
            mbody = wrap_returns(m[3])
            mbody = mbody + [["return", ["list", [["null"], ["id", "self"]]]]]
            func_stmts = func_stmts + [["function", cname + "__" + mname, ["self"] + mparams, mbody]]
            class_methods = class_methods + [[cname, mname, len(mparams)]]
            if len(mparams) > max_arity:
                max_arity = len(mparams)
            end
            if mname == "__init__":
                init_params = mparams
            end
            mi = mi + 1
        end
        new_params = []
        if init_params != null:
            new_params = init_params
        end
        new_body = []
        new_body = new_body + [["assign", "obj", ["dict", [["__class", ["str", cname]]]]]]
        if init_params != null:
            call_args = [["id", "obj"]]
            pi = 0
            loop len(init_params):
                call_args = call_args + [["id", init_params[pi]]]
                pi = pi + 1
            end
            tmp_name = "__newtmp_" + cname
            new_body = new_body + [["assign", tmp_name, ["call", ["id", cname + "____init__"], call_args]]]
            new_body = new_body + [["assign", "obj", ["index", ["id", tmp_name], ["num", 1]]]]
        end
        new_body = new_body + [["return", ["id", "obj"]]]
        func_stmts = func_stmts + [["function", cname + "__new", new_params, new_body]]
        ci = ci + 1
    end
    if len(class_methods) > 0:
        ai = 0
        while ai <= max_arity:
            params = ["obj", "name"]
            pi = 0
            loop ai:
                params = params + ["a" + int_to_string(pi)]
                pi = pi + 1
            end
            body = []
            body = body + [["assign", "cls", ["call", ["id", "__lsl_dict_get"], [["id", "obj"], ["str", "__class"]]]]]
            mi = 0
            loop len(class_methods):
                m = class_methods[mi]
                if m[2] == ai:
                    cond = ["bin", "and", ["cmp", "==", ["id", "cls"], ["str", m[0]]], ["cmp", "==", ["id", "name"], ["str", m[1]]]]
                    call_args = [["id", "obj"]]
                    pj = 0
                    loop ai:
                        call_args = call_args + [["id", "a" + int_to_string(pj)]]
                        pj = pj + 1
                    end
                    body = body + [["if", cond, [["return", ["call", ["id", m[0] + "__" + m[1]], call_args]]], []]]
                end
                mi = mi + 1
            end
            body = body + [["return", ["list", [["null"], ["id", "obj"]]]]]
            func_stmts = func_stmts + [["function", "__lsl_call_method" + int_to_string(ai), params, body]]
            ai = ai + 1
        end
    end
    # dynamic dispatch helpers for higher-order stdlib (map/filter/reduce)
    func_stmts = func_stmts + [build_dispatch_fn(1, func_stmts)]
    func_stmts = func_stmts + [build_dispatch_fn(2, func_stmts)]
    if not has_function(func_stmts, "__lsl_range"):
        func_stmts = func_stmts + [helper_range_fn()]
    end
    if not has_function(func_stmts, "__lsl_dict_get"):
        func_stmts = func_stmts + [helper_dict_get_fn()]
    end
    if not has_function(func_stmts, "__lsl_dict_set"):
        func_stmts = func_stmts + [helper_dict_set_fn()]
    end
    if do_progress and prog_last != 35:
        progress(35, "split main/func")
        prog_last = 35
    end
    code = bb_new()
    patches = lb_new()
    code = bb_add(code, u8(85) + u8(72) + u8(137) + u8(229))
    main_stack_pos = bb_len(code)
    code = bb_add(code, u8(72) + u8(129) + u8(236) + u32le(0))
    heap_pos = bb_len(code)
    code = bb_add(code, u8(73) + u8(191) + u64le(0))
    fixups = lb_new()
    fixups = lb_add(fixups, [heap_pos + 2, "heap_ptr", "heap_ptr"])
    # Store argc/argv from initial stack to globals
    # After prologue: rbp[8] = argc (at original rsp), rbp[16] = argv
    # mov rax, [rbp+8] (argc) - encoded as 48 8B 45 08
    code = bb_add(code, u8(72) + u8(139) + u8(69) + u8(8))
    # mov [__argc], rax - RIP-relative: 48 89 05 disp32
    argc_store_pos = bb_len(code)
    code = bb_add(code, u8(72) + u8(137) + u8(5) + u32le(0))
    fixups = lb_add(fixups, [argc_store_pos + 3, "argc_entry", "argc_entry"])
    # mov rax, [rbp+16] (argv) - encoded as 48 8B 45 10
    code = bb_add(code, u8(72) + u8(139) + u8(69) + u8(16))
    # mov [__argv], rax - RIP-relative: 48 89 05 disp32
    argv_store_pos = bb_len(code)
    code = bb_add(code, u8(72) + u8(137) + u8(5) + u32le(0))
    fixups = lb_add(fixups, [argv_store_pos + 3, "argv_entry", "argv_entry"])
    st = [code, fixups, env_bucket_new(), env_bucket_new(), 0, lb_new(), 0, [], ""]
    res = rt_emit_stmt_list(main_stmts, st)
    if not res[0]:
        return ["", res[2]]
    end
    st = res[1]
    if do_progress and prog_last != 40:
        progress(40, "codegen main")
        prog_last = 40
    end
    # patch main stack size
    main_stack_size = st[4] * 8
    main_rem = main_stack_size % 16
    if main_rem != 0:
        main_stack_size = main_stack_size + (16 - main_rem)
    end
    patches = lb_add(patches, [main_stack_pos + 3, main_stack_size])
    code = st[0]
    fixups = st[1]
    labels = st[2]
    var_map = st[3]
    var_names = st[4]
    strings = st[5]
    code = bb_add(code, u8(201) + u8(72) + u8(184) + u64le(60) + u8(72) + u8(49) + u8(255) + u8(15) + u8(5))
    st = [code, fixups, labels, var_map, var_names, strings, st[6], st[7], st[8]]
    # compile functions
    fcount = len(func_stmts)
    fi = 0
    loop len(func_stmts):
        f = func_stmts[fi]
        fname = f[1]
        fparams = f[2]
        fbody = f[3]
        if do_progress and fcount > 0:
            fpct = 50 + idiv(fi * 30, fcount)
            if fpct != prog_last:
                progress(fpct, "codegen fn " + fname)
                prog_last = fpct
            end
        end
        labels = env_set(labels, fname, ["num", bb_len(code)])
        # prolog
        code = bb_add(code, u8(85) + u8(72) + u8(137) + u8(229))
        f_stack_pos = bb_len(code)
        code = bb_add(code, u8(72) + u8(129) + u8(236) + u32le(0))
        # init var_map with params
        f_var_map = env_bucket_new()
        f_var_names = 0
        pi = 0
        loop len(fparams):
            f_var_map = env_set(f_var_map, fparams[pi], ["param", 16 + (pi * 8)])
            pi = pi + 1
        end
        f_state = [code, fixups, labels, f_var_map, f_var_names, strings, st[6], [], st[8]]
        f_res = rt_emit_stmt_list(fbody, f_state)
        if not f_res[0]:
            return ["", f_res[2]]
        end
        f_state = f_res[1]
        code = f_state[0]
        fixups = f_state[1]
        labels = f_state[2]
        strings = f_state[5]
        st = [code, fixups, labels, st[3], st[4], strings, f_state[6], st[7], st[8]]
        f_stack_size = f_state[4] * 8
        f_rem = f_stack_size % 16
        if f_rem != 0:
            f_stack_size = f_stack_size + (16 - f_rem)
        end
        patches = lb_add(patches, [f_stack_pos + 3, f_stack_size])
        # default return 0
        code = bb_add(code, u8(72) + u8(184) + u64le(0) + u8(201) + u8(195))
        st = [code, fixups, labels, st[3], st[4], strings, st[6], st[7], st[8]]
        fi = fi + 1
    end
    if do_progress and prog_last < 80:
        progress(80, "functions done")
        prog_last = 80
    end
    code = st[0]
    fixups = st[1]
    labels = st[2]
    strings = st[5]
    labels = env_set(labels, "print_num", ["num", bb_len(code)])
    # print_num routine
    pos_buf1 = bb_len(code)
    code = bb_add(code, u8(72) + u8(187) + u64le(0))
    fixups = lb_add(fixups, [pos_buf1 + 2, "buf_end", "buf_end"])
    pos_buf2 = bb_len(code)
    code = bb_add(code, u8(73) + u8(185) + u64le(0))
    fixups = lb_add(fixups, [pos_buf2 + 2, "buf_end", "buf_end"])
    code = bb_add(code, u8(73) + u8(255) + u8(201))
    code = bb_add(code, u8(65) + u8(198) + u8(1) + u8(10))
    code = bb_add(code, u8(72) + u8(185) + u64le(0))
    code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(0))
    jge_pos = bb_len(code)
    code = bb_add(code, u8(15) + u8(141) + u32le(0))
    code = bb_add(code, u8(72) + u8(247) + u8(216))
    code = bb_add(code, u8(72) + u8(185) + u64le(1))
    pos_label_pos = bb_len(code)
    code = bb_add(code, u8(73) + u8(184) + u64le(10))
    code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(0))
    jne_loop = bb_len(code)
    code = bb_add(code, u8(15) + u8(133) + u32le(0))
    code = bb_add(code, u8(73) + u8(255) + u8(201))
    code = bb_add(code, u8(65) + u8(198) + u8(1) + u8(48))
    jmp_after = bb_len(code)
    code = bb_add(code, u8(233) + u32le(0))
    loop_label = bb_len(code)
    code = bb_add(code, u8(72) + u8(49) + u8(210))
    code = bb_add(code, u8(73) + u8(247) + u8(240))
    code = bb_add(code, u8(128) + u8(194) + u8(48))
    code = bb_add(code, u8(73) + u8(255) + u8(201))
    code = bb_add(code, u8(65) + u8(136) + u8(17))
    code = bb_add(code, u8(72) + u8(131) + u8(248) + u8(0))
    jne_loop2 = bb_len(code)
    code = bb_add(code, u8(15) + u8(133) + u32le(0))
    after_label = bb_len(code)
    code = bb_add(code, u8(72) + u8(131) + u8(249) + u8(0))
    je_len = bb_len(code)
    code = bb_add(code, u8(15) + u8(132) + u32le(0))
    code = bb_add(code, u8(73) + u8(255) + u8(201))
    code = bb_add(code, u8(65) + u8(198) + u8(1) + u8(45))
    len_label = bb_len(code)
    code = bb_add(code, u8(76) + u8(137) + u8(206))
    code = bb_add(code, u8(72) + u8(137) + u8(218))
    code = bb_add(code, u8(76) + u8(41) + u8(202))
    code = bb_add(code, u8(72) + u8(184) + u64le(1))
    code = bb_add(code, u8(72) + u8(191) + u64le(1))
    code = bb_add(code, u8(15) + u8(5))
    code = bb_add(code, u8(195))
    patches = lb_add(patches, [jge_pos + 2, rel32(pos_label_pos - (jge_pos + 6))])
    patches = lb_add(patches, [jne_loop + 2, rel32(loop_label - (jne_loop + 6))])
    patches = lb_add(patches, [jmp_after + 1, rel32(after_label - (jmp_after + 5))])
    patches = lb_add(patches, [jne_loop2 + 2, rel32(loop_label - (jne_loop2 + 6))])
    patches = lb_add(patches, [je_len + 2, rel32(len_label - (je_len + 6))])
    if do_progress and prog_last < 85:
        progress(85, "helpers")
        prog_last = 85
    end
    helper_res = append_helpers(code, fixups, labels)
    code = helper_res[0]
    fixups = helper_res[1]
    labels = helper_res[2]
    pad = bb_len(code) % 8
    if pad != 0:
        pad = 8 - pad
        pi = 0
        loop pad:
            code = bb_add(code, u8(0))
            pi = pi + 1
        end
    end
    if do_progress and prog_last < 90:
        progress(90, "emit data")
        prog_last = 90
    end
    strings = lb_to_list(strings)
    data = bb_new()
    str_offsets = []
    si = 0
    loop len(strings):
        str_offsets = str_offsets + [bb_len(data)]
        data = bb_add(data, u64le(len(strings[si])) + strings[si])
        pad = bb_len(data) % 8
        if pad != 0:
            pad = 8 - pad
            pi = 0
            loop pad:
                data = bb_add(data, u8(0))
                pi = pi + 1
            end
        end
        si = si + 1
    end
    buf_offset = bb_len(data)
    data = bb_add(data, u64le(0) + u64le(0) + u64le(0) + u64le(0))
    buf_end = buf_offset + 32
    heap_ptr_offset = bb_len(data)
    data = bb_add(data, u64le(0))
    argc_offset = bb_len(data)
    data = bb_add(data, u64le(0))
    argv_offset = bb_len(data)
    data = bb_add(data, u64le(0))
    heap_offset = bb_len(data)
    if baremetal:
        heap_size = 4194304
        base = 536870912
        code_offset = 32
    else:
        heap_size = 1073741824
        base = 4194304
        code_offset = 120
    end
    data_offset = code_offset + bb_len(code)
    heap_addr = base + data_offset + heap_offset
    code = bb_to_string(code)
    data = bb_to_string(data)
    fixups = lb_to_list(fixups)
    patches = lb_to_list(patches)
    patch_entries = lb_new()
    pi = 0
    fi = 0
    while pi < len(patches) or fi < len(fixups):
        if fi >= len(fixups) or (pi < len(patches) and patches[pi][0] < fixups[fi][0]):
            patch_entries = lb_add(patch_entries, [patches[pi][0], u32le(patches[pi][1])])
            pi = pi + 1
        else:
            fx = fixups[fi]
            fpos = fx[0]
            fkind = fx[1]
            fkey = fx[2]
            if fkind == "str":
                soff = str_offsets[fkey]
                addr = base + data_offset + soff
                patch_entries = lb_add(patch_entries, [fpos, u64le(addr)])
            elif fkind == "str_obj":
                soff = str_offsets[fkey]
                addr = base + data_offset + soff
                patch_entries = lb_add(patch_entries, [fpos, u64le(addr)])
            elif fkind == "heap_ptr":
                addr = base + data_offset + heap_ptr_offset
                patch_entries = lb_add(patch_entries, [fpos, u64le(addr)])
            elif fkind == "buf_end":
                addr = base + data_offset + buf_end
                patch_entries = lb_add(patch_entries, [fpos, u64le(addr)])
            elif fkind == "argc_addr":
                addr = base + data_offset + argc_offset
                patch_entries = lb_add(patch_entries, [fpos, u32le(addr)])
            elif fkind == "argv_addr":
                addr = base + data_offset + argv_offset
                patch_entries = lb_add(patch_entries, [fpos, u32le(addr)])
            elif fkind == "argc_entry":
                addr = base + data_offset + argc_offset
                rel = addr - (fpos + 4)
                patch_entries = lb_add(patch_entries, [fpos, u32le(rel32(rel))])
            elif fkind == "argv_entry":
                addr = base + data_offset + argv_offset
                rel = addr - (fpos + 4)
                patch_entries = lb_add(patch_entries, [fpos, u32le(rel32(rel))])
            elif fkind == "argc_data":
                # RIP-relative addressing: addr is the data address, we need rel32 from instruction end
                # fpos points to the rel32 field in the instruction
                addr = base + data_offset + argc_offset
                rel = addr - (fpos + 4)
                patch_entries = lb_add(patch_entries, [fpos, u32le(rel32(rel))])
            elif fkind == "argv_data":
                addr = base + data_offset + argv_offset
                rel = addr - (fpos + 4)
                patch_entries = lb_add(patch_entries, [fpos, u32le(rel32(rel))])
            elif fkind == "call":
                l = env_get(labels, fkey)
                if l[0] == "missing":
                    return ["", "missing label: " + fkey]
                end
                lpos = l[1]
                rel = lpos - (fpos + 4)
                patch_entries = lb_add(patch_entries, [fpos, u32le(rel32(rel))])
            elif fkind == "rel":
                l = env_get(labels, fkey)
                if l[0] == "missing":
                    return ["", "missing label: " + fkey]
                end
                lpos = l[1]
                rel = lpos - (fpos + 4)
                patch_entries = lb_add(patch_entries, [fpos, u32le(rel32(rel))])
            end
            fi = fi + 1
        end
    end
    patch_entries = lb_to_list(patch_entries)
    code = apply_patches(code, patch_entries)
    data = apply_patches(data, [[heap_ptr_offset, u64le(heap_addr)]])
    if do_progress and prog_last < 95:
        progress(95, "patches")
        prog_last = 95
    end
    entry = base + code_offset
    file_size = data_offset + len(data)
    mem_size = file_size + heap_size
    if baremetal:
        lxb = ""
        lxb = lxb + "LXB1"
        lxb = lxb + u32le(0)
        lxb = lxb + u64le(entry)
        lxb = lxb + u64le(file_size)
        lxb = lxb + u64le(mem_size)
        if do_progress and prog_last < 100:
            progress(100, "done")
            prog_last = 100
        end
        return [lxb + code + data, ""]
    end
    elf = ""
    elf = elf + u8(127) + "ELF"
    elf = elf + u8(2) + u8(1) + u8(1) + u8(0)
    elf = elf + u8(0) + u8(0) + u8(0) + u8(0) + u8(0) + u8(0) + u8(0) + u8(0)
    elf = elf + u16le(2)
    elf = elf + u16le(62)
    elf = elf + u32le(1)
    elf = elf + u64le(entry)
    elf = elf + u64le(64)
    elf = elf + u64le(0)
    elf = elf + u32le(0)
    elf = elf + u16le(64)
    elf = elf + u16le(56)
    elf = elf + u16le(1)
    elf = elf + u16le(0)
    elf = elf + u16le(0)
    elf = elf + u16le(0)
    ph = ""
    ph = ph + u32le(1)
    ph = ph + u32le(7)
    ph = ph + u64le(0)
    ph = ph + u64le(base)
    ph = ph + u64le(base)
    ph = ph + u64le(file_size)
    ph = ph + u64le(mem_size)
    ph = ph + u64le(2097152)
    if do_progress and prog_last < 100:
        progress(100, "done")
        prog_last = 100
    end
    return [elf + ph + code + data, ""]
end
# Split command line arguments by null terminator (\0)
# This is needed because /proc/self/cmdline uses null-separated arguments
function split_nul(s):
    out = []
    cur = ""
    i = 0
    while i < len(s):
        ch = s[i]
        # Simple null detection: check if character code is 0
        # In LSL, null characters might appear as empty strings or special chars
        try:
            # Try to get character code
            char_code = 0
            # Method 1: Check if it's a null character we can detect
            if ch == "":
                # Empty string might represent null
                out = out + [cur]
                cur = ""
            else:
                # Normal character, add to current argument
                cur = cur + ch
            end
        catch:
            # If any error, just append the character
            cur = cur + ch
        end
        i = i + 1
    end
    
    # Add the last argument if not empty
    if cur != "":
        out = out + [cur]
    end
    
    return out
end
function print_usage():
    print "Usage: compiler_selfhost [options] <input.lsl>"
    print "Options:"
    print "  -o <file>           Output file"
    print "  -b, --baremetal     Emit baremetal LXB output"
    print "  --format <fmt>      Output format: elf or baremetal"
    print "  -h, --help          Show this help text"
end
function default_output_path(input_path, baremetal):
    out_ext = ".out"
    if baremetal:
        out_ext = ".lxb"
    end
    if ends_with(input_path, ".lsl"):
        return substr(input_path, 0, len(input_path) - 4) + out_ext
    end
    return input_path + out_ext
end
function parse_cli_args(args):
    input_path = ""
    output_path = ""
    baremetal = false
    show_help = false
    format_set = ""
    i = 1
    while i < len(args):
        arg = args[i]
        if arg == "-h" or arg == "--help":
            show_help = true
        elif arg == "-b" or arg == "--baremetal":
            if format_set == "elf":
                return ["", "", false, false, "format already set to elf"]
            end
            baremetal = true
            format_set = "baremetal"
        elif arg == "--format":
            if i + 1 < len(args):
                fmt = args[i + 1]
                i = i + 1
                if fmt == "elf":
                    if format_set == "baremetal":
                        return ["", "", false, false, "format already set to baremetal"]
                    end
                    baremetal = false
                    format_set = "elf"
                elif fmt == "baremetal":
                    if format_set == "elf":
                        return ["", "", false, false, "format already set to elf"]
                    end
                    baremetal = true
                    format_set = "baremetal"
                else:
                    return ["", "", false, false, "unknown format: " + fmt]
                end
            else:
                return ["", "", false, false, "missing format after --format"]
            end
        elif arg == "-o":
            if i + 1 < len(args):
                if output_path != "":
                    return ["", "", false, false, "output already set"]
                end
                output_path = args[i + 1]
                i = i + 1
            else:
                return ["", "", false, false, "missing output after -o"]
            end
        elif starts_with(arg, "-"):
            return ["", "", false, false, "unknown option: " + arg]
        else:
            if input_path == "":
                input_path = arg
            elif output_path == "":
                output_path = arg
            else:
                return ["", "", false, false, "unexpected argument: " + arg]
            end
        end
        i = i + 1
    end
    if show_help:
        return [input_path, output_path, baremetal, show_help, ""]
    end
    if input_path == "":
        if output_path != "":
            return ["", "", false, false, "missing input path"]
        end
        return [input_path, output_path, baremetal, show_help, ""]
    end
    if output_path == "":
        output_path = default_output_path(input_path, baremetal)
    end
    return [input_path, output_path, baremetal, show_help, ""]
end
function compile_file(input_path, output_path, baremetal_override):
    cf_src = readfile(input_path)
    cf_bare = ends_with(output_path, ".lxb")
    if baremetal_override:
        cf_bare = true
    end
    cf_res = compile_runtime_numeric(cf_src, input_path, cf_bare)
    cf_elf = cf_res[0]
    cf_err = cf_res[1]
    if cf_err != "":
        if starts_with(cf_err, "[ ERROR"):
            print cf_err
        else:
            print "Compiler error: " + cf_err
        end
        return false
    end
    writefile(output_path, cf_elf)
    return true
end
# =============================================================================
# MAIN EXECUTION ENTRY POINT
# =============================================================================
# Simple approach: test if we can read and parse cmdline

print "DEBUG: Starting compiler..."

# Read command line
cmdline = ""
try:
    cmdline = readfile("/proc/self/cmdline")
    print "DEBUG: cmdline length = " + len(cmdline)
    if len(cmdline) > 0:
        print "DEBUG: cmdline starts with: " + substr(cmdline, 0, 20)
    end
catch:
    print "DEBUG: Cannot read cmdline"
end

# Simple split: assume arguments are separated by nulls
# But first, let's just try to count how many nulls we have
null_count = 0
i = 0
while i < len(cmdline):
    ch = cmdline[i]
    # Try to detect null by looking for empty string
    if ch == "":
        null_count = null_count + 1
    end
    i = i + 1
end

print "DEBUG: Found " + null_count + " null separators"

# For now, just create a simple argument list for testing
if null_count > 0:
    __args = ["compiler_selfhost.out", "-h"]  # Test with help
    __argc = 2
else:
    __args = ["compiler_selfhost.out", "-h"]  # Also test with help
    __argc = 2
end

print "DEBUG: Using " + __argc + " arguments for testing"
did_compile = false
skip_fallback = false
if __argc > 1:
    skip_fallback = true
    parsed = parse_cli_args(__args)
    if parsed[4] != "":
        print "Argument error: " + parsed[4]
        print_usage()
    elif parsed[3]:
        print_usage()
    elif parsed[0] != "" and parsed[1] != "":
        did_compile = compile_file(parsed[0], parsed[1], parsed[2])
    else:
        print_usage()
    end
end
if not did_compile and not skip_fallback:
    req = readfile("build/compile_request.txt")
    if req != "":
        nl = find_char(req, "\n", 0)
        if nl < 0:
            print "compile_request: missing newline"
        else:
            in_path = rtrim(substr(req, 0, nl))
            nl2 = find_char(req, "\n", nl + 1)
            if nl2 < 0:
                nl2 = len(req)
            end
            out_path = rtrim(substr(req, nl + 1, nl2 - nl - 1))
            if in_path != "" and out_path != "":
                did_compile = compile_file(in_path, out_path, false)
            else:
                print "compile_request: empty path"
            end
        end
    end
end
