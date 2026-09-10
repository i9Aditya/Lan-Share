#!/usr/bin/env python3
"""
Self-contained Pure-Python QR Code generator.
Supports standard byte-mode QR codes (Version 1 to 5) with zero dependencies.
Renders to ANSI terminal blocks or ASCII text.
"""
import sys

# Galois Field GF(256) tables for QR Reed-Solomon Error Correction
GF_EXP = [0] * 512
GF_LOG = [0] * 256
_x = 1
for _i in range(255):
    GF_EXP[_i] = _x
    GF_EXP[_i + 255] = _x
    GF_LOG[_x] = _i
    _x = (_x << 1) ^ (0x11d if (_x & 0x80) else 0)

def gf_mul(x, y):
    if x == 0 or y == 0: return 0
    return GF_EXP[GF_LOG[x] + GF_LOG[y]]

def rs_poly(ec_len):
    poly = [1]
    for i in range(ec_len):
        next_poly = [0] * (len(poly) + 1)
        root = GF_EXP[i]
        for j in range(len(poly)):
            next_poly[j] ^= gf_mul(poly[j], root)
            next_poly[j + 1] ^= poly[j]
        poly = next_poly
    return poly

def rs_encode(data, ec_len):
    poly = rs_poly(ec_len)
    res = [0] * ec_len
    for b in data:
        factor = b ^ res[0]
        res = res[1:] + [0]
        for i in range(ec_len):
            res[i] ^= gf_mul(poly[i], factor)
    return res

# QR Specs for Versions 1-5, ECC Level M (15% recovery)
# (total_data_bytes, ec_bytes_per_block, num_blocks)
QR_SPECS_M = {
    1: (16, 10, 1),
    2: (28, 16, 1),
    3: (44, 26, 1),
    4: (64, 18, 2),
    5: (86, 24, 2),
}

ALIGN_PATTERNS = {
    2: [6, 18],
    3: [6, 22],
    4: [6, 26],
    5: [6, 30]
}

def make_qr_matrix(text):
    data_bytes = text.encode('utf-8')
    data_len = len(data_bytes)
    version = None
    for v in sorted(QR_SPECS_M.keys()):
        total_data, _, _ = QR_SPECS_M[v]
        if data_len + 2 <= total_data: # 4 bits mode + 8 bits len count
            version = v
            break
    if version is None:
        version = 5
        data_bytes = data_bytes[:60]
        data_len = len(data_bytes)

    total_data, ec_len, num_blocks = QR_SPECS_M[version]
    size = version * 4 + 17

    # 1. Build bitstream
    bits = [0, 1, 0, 0] # 8-bit byte mode
    for i in range(7, -1, -1):
        bits.append((data_len >> i) & 1)
    for b in data_bytes:
        for i in range(7, -1, -1):
            bits.append((b >> i) & 1)
    
    # Terminator
    for _ in range(min(4, total_data * 8 - len(bits))):
        bits.append(0)
    while len(bits) % 8 != 0:
        bits.append(0)
    
    # Pad bytes
    pads = [0xEC, 0x11]
    p_idx = 0
    while len(bits) < total_data * 8:
        for i in range(7, -1, -1):
            bits.append((pads[p_idx] >> i) & 1)
        p_idx = (p_idx + 1) % 2

    # Group into bytes
    raw_data = []
    for i in range(0, len(bits), 8):
        b = 0
        for bit in bits[i:i+8]:
            b = (b << 1) | bit
        raw_data.append(b)

    # Error correction blocks
    block_size = total_data // num_blocks
    data_blocks = []
    ec_blocks = []
    for blk in range(num_blocks):
        sub_data = raw_data[blk * block_size : (blk + 1) * block_size]
        data_blocks.append(sub_data)
        ec_blocks.append(rs_encode(sub_data, ec_len))

    # Interleave
    final_stream = []
    for i in range(block_size):
        for blk in range(num_blocks):
            final_stream.append(data_blocks[blk][i])
    for i in range(ec_len):
        for blk in range(num_blocks):
            final_stream.append(ec_blocks[blk][i])

    # Convert to bit list
    final_bits = []
    for b in final_stream:
        for i in range(7, -1, -1):
            final_bits.append((b >> i) & 1)

    # 2. Setup Matrix
    matrix = [[None] * size for _ in range(size)]
    reserved = [[False] * size for _ in range(size)]

    # Finder patterns
    def add_finder(r0, c0):
        for r in range(7):
            for c in range(7):
                val = 1 if (r in (0, 6) or c in (0, 6) or (2 <= r <= 4 and 2 <= c <= 4)) else 0
                matrix[r0 + r][c0 + c] = val
                reserved[r0 + r][c0 + c] = True
        # Separator
        for r in range(-1, 8):
            for c in range(-1, 8):
                nr, nc = r0 + r, c0 + c
                if 0 <= nr < size and 0 <= nc < size and not reserved[nr][nc]:
                    matrix[nr][nc] = 0
                    reserved[nr][nc] = True

    add_finder(0, 0)
    add_finder(0, size - 7)
    add_finder(size - 7, 0)

    # Alignment pattern
    if version in ALIGN_PATTERNS:
        coords = ALIGN_PATTERNS[version]
        for r0 in coords:
            for c0 in coords:
                if (r0 <= 8 and c0 <= 8) or (r0 <= 8 and c0 >= size - 8) or (r0 >= size - 8 and c0 <= 8):
                    continue
                for dr in range(-2, 3):
                    for dc in range(-2, 3):
                        val = 1 if (abs(dr) == 2 or abs(dc) == 2 or (dr == 0 and dc == 0)) else 0
                        matrix[r0 + dr][c0 + dc] = val
                        reserved[r0 + dr][c0 + dc] = True

    # Timing patterns
    for i in range(8, size - 8):
        val = 1 if i % 2 == 0 else 0
        if not reserved[6][i]:
            matrix[6][i] = val
            reserved[6][i] = True
        if not reserved[i][6]:
            matrix[i][6] = val
            reserved[i][6] = True

    # Dark module
    matrix[size - 8][8] = 1
    reserved[size - 8][8] = True

    # Reserve format info areas
    for i in range(9):
        if not reserved[8][i]: reserved[8][i] = True
        if not reserved[i][8]: reserved[i][8] = True
        if not reserved[8][size - 1 - i]: reserved[8][size - 1 - i] = True
        if not reserved[size - 1 - i][8]: reserved[size - 1 - i][8] = True

    # Place data bits (Mask 0: (row + col) % 2 == 0)
    bit_idx = 0
    col = size - 1
    dir_up = True
    while col > 0:
        if col == 6: col -= 1
        rows = range(size - 1, -1, -1) if dir_up else range(size)
        for row in rows:
            for c in (col, col - 1):
                if not reserved[row][c]:
                    val = final_bits[bit_idx] if bit_idx < len(final_bits) else 0
                    bit_idx += 1
                    # Mask 0 condition
                    if (row + c) % 2 == 0:
                        val ^= 1
                    matrix[row][c] = val
        col -= 2
        dir_up = not dir_up

    # Format info for ECC Level M (00), Mask 0 (000) -> 00000 -> BCH code: 00000 0000000000 ^ 101010000010010 = 101010000010010
    format_bits = [1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0]
    # Place format bits around top-left, top-right, bottom-left
    # 0..5
    for i in range(6):
        matrix[8][i] = format_bits[i]
    matrix[8][7] = format_bits[6]
    matrix[8][8] = format_bits[7]
    matrix[7][8] = format_bits[8]
    for i in range(5, -1, -1):
        matrix[i][8] = format_bits[14 - i]
    # Mirror format bits
    for i in range(8):
        matrix[size - 1 - i][8] = format_bits[i]
    for i in range(8):
        matrix[8][size - 8 + i] = format_bits[7 + i]

    return matrix

def print_terminal_qr(text):
    matrix = make_qr_matrix(text)
    # Add quiet zone border
    border = 2
    full_matrix = []
    width = len(matrix) + 2 * border
    for _ in range(border):
        full_matrix.append([0] * width)
    for row in matrix:
        full_matrix.append([0] * border + [(1 if cell == 1 else 0) for cell in row] + [0] * border)
    for _ in range(border):
        full_matrix.append([0] * width)

    # Render pairs of rows using ANSI half-block characters
    lines = []
    for r in range(0, len(full_matrix), 2):
        line = ""
        for c in range(len(full_matrix[0])):
            top = full_matrix[r][c]
            bot = full_matrix[r + 1][c] if r + 1 < len(full_matrix) else 0
            if top and bot:
                line += " "
            elif top and not bot:
                line += "▄"
            elif not top and bot:
                line += "▀"
            else:
                line += "█"
        lines.append(line)
    return "\n".join(lines)

if __name__ == "__main__":
    url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080"
    print(print_terminal_qr(url))
