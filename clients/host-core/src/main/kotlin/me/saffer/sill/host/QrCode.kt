package me.saffer.sill.host

/**
 * The pairing window's QR code (PairDeviceWindow.swift's QRCodeView, whose CIQRCodeGenerator uses
 * error correction "M"): the link's UTF-8 bytes in byte mode at level M, the smallest version that
 * holds them (1 to 40), and the mask with the lowest penalty (ISO/IEC 18004 §7.8.3's four rules, the
 * first of equal ones). The penalty is judged as python-qrcode judges it, with the format and version
 * areas and the dark module still light, so the matrices are that implementation's module for module
 * (QrCodeTest, clients/host-core/src/test/qr); any mask decodes the same.
 *
 * `modules[row][col]`, true dark, no quiet zone (draw four light modules round it).
 */
class QrCode private constructor(val version: Int, val mask: Int, val modules: Array<BooleanArray>) {
    val size get() = modules.size

    companion object {
        /** The link as a QR code; throws IllegalArgumentException past version 40 (2,331 bytes). */
        fun encode(text: String): QrCode {
            val data = text.toByteArray(Charsets.UTF_8)
            val version = (1..40).firstOrNull { v -> 4 + countBits(v) + data.size * 8 <= dataCodewords(v) * 8 }
                ?: throw IllegalArgumentException("too long for a QR code: ${data.size} bytes")
            val codewords = interleave(version, dataStream(version, data))
            var best = -1; var bestPenalty = Int.MAX_VALUE
            for (m in 0 until 8) {
                val p = penalty(build(version, codewords, m, test = true))
                if (p < bestPenalty) { bestPenalty = p; best = m }
            }
            return QrCode(version, best, build(version, codewords, best, test = false))
        }

        // MARK: Capacity (level M)

        private val EC_PER_BLOCK = intArrayOf(0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
            26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28)
        private val BLOCKS = intArrayOf(0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16,
            17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49)

        private fun countBits(version: Int) = if (version <= 9) 8 else 16

        /** Data modules of a version, function patterns and format and version areas left out. */
        private fun rawModules(v: Int): Int {
            var r = (16 * v + 128) * v + 64
            if (v >= 2) { val n = v / 7 + 2; r -= (25 * n - 10) * n - 55; if (v >= 7) r -= 36 }
            return r
        }

        private fun totalCodewords(v: Int) = rawModules(v) / 8
        private fun dataCodewords(v: Int) = totalCodewords(v) - EC_PER_BLOCK[v] * BLOCKS[v]

        // MARK: Data

        private fun dataStream(version: Int, data: ByteArray): ByteArray {
            val bits = ArrayList<Boolean>()
            fun put(value: Int, n: Int) { for (i in n - 1 downTo 0) bits += (value ushr i) and 1 == 1 }
            put(0b0100, 4)
            put(data.size, countBits(version))
            for (b in data) put(b.toInt() and 0xFF, 8)
            val capacity = dataCodewords(version) * 8
            repeat(minOf(4, capacity - bits.size)) { bits += false }
            while (bits.size % 8 != 0) bits += false
            val out = ByteArray(dataCodewords(version))
            for (i in 0 until bits.size / 8) { var b = 0; for (j in 0 until 8) b = (b shl 1) or (if (bits[i * 8 + j]) 1 else 0); out[i] = b.toByte() }
            var pad = 0xEC
            for (i in bits.size / 8 until out.size) { out[i] = pad.toByte(); pad = pad xor 0xEC xor 0x11 }
            return out
        }

        /** The data split into blocks (the short ones first), each with its Reed–Solomon codewords, interleaved. */
        private fun interleave(version: Int, data: ByteArray): ByteArray {
            val blocks = BLOCKS[version]; val ec = EC_PER_BLOCK[version]
            val total = totalCodewords(version)
            val shortBlocks = blocks - total % blocks
            val shortLen = total / blocks
            val gen = generator(ec)
            val dataBlocks = ArrayList<ByteArray>(); val ecBlocks = ArrayList<ByteArray>()
            var k = 0
            for (i in 0 until blocks) {
                val len = shortLen - ec + if (i < shortBlocks) 0 else 1
                val d = data.copyOfRange(k, k + len); k += len
                dataBlocks += d; ecBlocks += remainder(d, gen)
            }
            val out = ByteArray(total); var o = 0
            for (i in 0 until shortLen - ec + 1) for (b in 0 until blocks) if (i < dataBlocks[b].size) out[o++] = dataBlocks[b][i]
            for (i in 0 until ec) for (b in 0 until blocks) out[o++] = ecBlocks[b][i]
            return out
        }

        private fun multiply(x: Int, y: Int): Int {
            var z = 0
            for (i in 7 downTo 0) { z = (z shl 1) xor ((z ushr 7) * 0x11D); z = z xor (((y ushr i) and 1) * x) }
            return z
        }

        private fun generator(degree: Int): IntArray {
            val r = IntArray(degree); r[degree - 1] = 1
            var root = 1
            repeat(degree) {
                for (j in 0 until degree) { r[j] = multiply(r[j], root); if (j + 1 < degree) r[j] = r[j] xor r[j + 1] }
                root = multiply(root, 0x02)
            }
            return r
        }

        private fun remainder(data: ByteArray, gen: IntArray): ByteArray {
            val r = IntArray(gen.size)
            for (b in data) {
                val factor = (b.toInt() and 0xFF) xor r[0]
                for (i in 0 until r.size - 1) r[i] = r[i + 1]
                r[r.size - 1] = 0
                for (i in r.indices) r[i] = r[i] xor multiply(gen[i], factor)
            }
            return ByteArray(r.size) { r[it].toByte() }
        }

        // MARK: The matrix

        private fun alignment(v: Int): IntArray {
            if (v == 1) return IntArray(0)
            val n = v / 7 + 2
            val step = if (v == 32) 26 else (v * 4 + n * 2 + 1) / (n * 2 - 2) * 2
            val out = IntArray(n); out[0] = 6
            for (i in n - 1 downTo 1) out[i] = v * 4 + 10 - (n - 1 - i) * step
            return out
        }

        private fun build(version: Int, codewords: ByteArray, mask: Int, test: Boolean): Array<BooleanArray> {
            val n = version * 4 + 17
            val m = Array(n) { BooleanArray(n) }
            val fn = Array(n) { BooleanArray(n) }
            fun set(r: Int, c: Int, dark: Boolean) { m[r][c] = dark; fn[r][c] = true }
            for (i in 0 until n) { set(6, i, i % 2 == 0); set(i, 6, i % 2 == 0) }
            for ((r0, c0) in listOf(0 to 0, n - 7 to 0, 0 to n - 7)) {
                for (dr in -1..7) for (dc in -1..7) {
                    val r = r0 + dr; val c = c0 + dc
                    if (r !in 0 until n || c !in 0 until n) continue
                    val inside = dr in 0..6 && dc in 0..6
                    set(r, c, inside && (dr == 0 || dr == 6 || dc == 0 || dc == 6 || (dr in 2..4 && dc in 2..4)))
                }
            }
            val pos = alignment(version)
            for (r in pos) for (c in pos) {
                if ((r == 6 && c == 6) || (r == 6 && c == n - 7) || (r == n - 7 && c == 6)) continue
                for (dr in -2..2) for (dc in -2..2) set(r + dr, c + dc, maxOf(kotlin.math.abs(dr), kotlin.math.abs(dc)) != 1)
            }
            // Format and version areas, and the dark module: light while a mask is judged (`test`).
            val format = if (test) 0 else formatBits(mask)
            for (i in 0 until 15) {
                val bit = (format ushr i) and 1 == 1
                when { i < 6 -> set(i, 8, bit); i < 8 -> set(i + 1, 8, bit); else -> set(n - 15 + i, 8, bit) }
                when { i < 8 -> set(8, n - i - 1, bit); i < 9 -> set(8, 15 - i - 1 + 1, bit); else -> set(8, 15 - i - 1, bit) }
            }
            set(n - 8, 8, !test)
            if (version >= 7) {
                val bits = if (test) 0 else versionBits(version)
                for (i in 0 until 18) {
                    val bit = (bits ushr i) and 1 == 1
                    set(i / 3, i % 3 + n - 11, bit); set(i % 3 + n - 11, i / 3, bit)
                }
            }
            // The codewords in the zigzag, masked.
            var bit = 0
            var col = n - 1; var upward = true
            while (col > 0) {
                if (col == 6) col--
                for (k in 0 until n) {
                    val r = if (upward) n - 1 - k else k
                    for (c in intArrayOf(col, col - 1)) {
                        if (fn[r][c]) continue
                        var dark = bit < codewords.size * 8 && ((codewords[bit / 8].toInt() ushr (7 - bit % 8)) and 1) == 1
                        if (masked(mask, r, c)) dark = !dark
                        m[r][c] = dark
                        bit++
                    }
                }
                upward = !upward; col -= 2
            }
            return m
        }

        private fun masked(mask: Int, r: Int, c: Int) = when (mask) {
            0 -> (r + c) % 2 == 0
            1 -> r % 2 == 0
            2 -> c % 3 == 0
            3 -> (r + c) % 3 == 0
            4 -> (r / 2 + c / 3) % 2 == 0
            5 -> r * c % 2 + r * c % 3 == 0
            6 -> (r * c % 2 + r * c % 3) % 2 == 0
            else -> ((r + c) % 2 + r * c % 3) % 2 == 0
        }

        /** Level M (00) and the mask, BCH(15,5), XOR 101010000010010. */
        private fun formatBits(mask: Int): Int {
            val data = (0 shl 3) or mask
            var rem = data
            repeat(10) { rem = (rem shl 1) xor ((rem ushr 9) * 0x537) }
            return ((data shl 10) or rem) xor 0x5412
        }

        private fun versionBits(v: Int): Int {
            var rem = v
            repeat(12) { rem = (rem shl 1) xor ((rem ushr 11) * 0x1F25) }
            return (v shl 12) or rem
        }

        // MARK: The penalty

        private fun penalty(m: Array<BooleanArray>): Int {
            val n = m.size
            var p = 0
            // Runs of five or more of one colour, in rows and columns: 3, and 1 for each more.
            for (line in 0 until n) for (vertical in listOf(false, true)) {
                var run = 0; var prev = false
                for (i in 0 until n) {
                    val v = if (vertical) m[i][line] else m[line][i]
                    if (i == 0 || v != prev) { if (run >= 5) p += run - 2; run = 1; prev = v } else run++
                }
                if (run >= 5) p += run - 2
            }
            // 2×2 blocks of one colour: 3 each.
            for (r in 0 until n - 1) for (c in 0 until n - 1) {
                val v = m[r][c]
                if (v == m[r][c + 1] && v == m[r + 1][c] && v == m[r + 1][c + 1]) p += 3
            }
            // 1:1:3:1:1 with four light modules on one side: 40 each.
            val a = booleanArrayOf(true, false, true, true, true, false, true, false, false, false, false)
            val b = booleanArrayOf(false, false, false, false, true, false, true, true, true, false, true)
            for (line in 0 until n) for (i in 0 until n - 10) {
                var rowA = true; var rowB = true; var colA = true; var colB = true
                for (k in 0 until 11) {
                    val h = m[line][i + k]; val v = m[i + k][line]
                    if (h != a[k]) rowA = false; if (h != b[k]) rowB = false
                    if (v != a[k]) colA = false; if (v != b[k]) colB = false
                }
                if (rowA || rowB) p += 40
                if (colA || colB) p += 40
            }
            // Balance: 10 for each whole 5 % away from half dark.
            var dark = 0
            for (row in m) for (v in row) if (v) dark++
            p += (kotlin.math.abs(dark.toDouble() / (n * n) * 100 - 50) / 5).toInt() * 10
            return p
        }
    }
}
