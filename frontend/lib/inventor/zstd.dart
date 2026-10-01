// Zstandard decompression (RFC 8878), decode only, in pure Dart.
//
// Autodesk Inventor has zstd-compressed every segment of its documents since
// the 2025-era releases, so reading an .ipt means reading zstd. A pure-Dart
// decoder keeps the reader identical on every platform (iPad included) and
// testable on any host without the native library. Dictionaries are not
// supported (Inventor does not use them); everything else in the format is.
import 'dart:typed_data';

class ZstdException implements Exception {
  final String message;
  ZstdException(this.message);
  @override
  String toString() => 'ZstdException: $message';
}

const int _kMagic = 0xFD2FB528;

/// Decompresses every zstd frame in [src] (skippable frames are skipped).
Uint8List zstdDecompress(Uint8List src) {
  final out = _Out();
  var p = 0;
  while (p + 4 <= src.length) {
    final magic = _le32(src, p);
    if ((magic & 0xFFFFFFF0) == 0x184D2A50) {
      final size = _le32(src, p + 4);
      p += 8 + size;
      continue;
    }
    if (magic != _kMagic) {
      if (out.length == 0) throw ZstdException('not a zstd frame');
      break;
    }
    p = _Frame(src, p + 4, out).decode();
  }
  return out.bytes();
}

int _le32(Uint8List b, int p) =>
    b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24);

class _Out {
  Uint8List _b = Uint8List(1 << 16);
  int length = 0;

  void _grow(int need) {
    if (length + need <= _b.length) return;
    var n = _b.length * 2;
    while (n < length + need) {
      n *= 2;
    }
    final nb = Uint8List(n)..setRange(0, length, _b);
    _b = nb;
  }

  void addAll(Uint8List src, int start, int end) {
    _grow(end - start);
    _b.setRange(length, length + end - start, src, start);
    length += end - start;
  }

  void fill(int byte, int n) {
    _grow(n);
    _b.fillRange(length, length + n, byte);
    length += n;
  }

  void copyMatch(int offset, int len, int frameStart) {
    if (offset > length - frameStart || offset <= 0) {
      throw ZstdException('match offset $offset beyond decoded data');
    }
    _grow(len);
    var s = length - offset;
    if (offset >= len) {
      _b.setRange(length, length + len, _b, s);
      length += len;
    } else {
      for (var i = 0; i < len; i++) {
        _b[length++] = _b[s++];
      }
    }
  }

  Uint8List bytes() => Uint8List.sublistView(_b, 0, length);
}

// ---------------------------------------------------------------- bit readers
/// Backward bit stream (literal streams, sequences): read from the end,
/// the last byte's highest set bit is a marker.
class _BackBits {
  final Uint8List b;
  final int start;
  int bitPos; // bits still unread, counted from `start`

  _BackBits(this.b, this.start, int end) : bitPos = 0 {
    if (end <= start) throw ZstdException('empty bit stream');
    final last = b[end - 1];
    if (last == 0) throw ZstdException('bit stream has no end marker');
    var hi = 7;
    while ((last >> hi) & 1 == 0) {
      hi--;
    }
    bitPos = (end - 1 - start) * 8 + hi;
  }

  int read(int n) {
    if (n == 0) return 0;
    var v = 0;
    for (var i = 0; i < n; i++) {
      bitPos--;
      final bit = bitPos < 0
          ? 0
          : (b[start + (bitPos >> 3)] >> (bitPos & 7)) & 1;
      v = (v << 1) | bit;
    }
    return v;
  }

  bool get overflowed => bitPos < 0;
  bool get done => bitPos == 0;
}

/// Forward bit stream (FSE table descriptions): LSB first.
class _FwdBits {
  final Uint8List b;
  int bit;
  _FwdBits(this.b, int start) : bit = start * 8;

  int read(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      final byte = b[(bit + i) >> 3];
      v |= ((byte >> ((bit + i) & 7)) & 1) << i;
    }
    bit += n;
    return v;
  }

  int peek(int n) {
    final save = bit;
    final v = read(n);
    bit = save;
    return v;
  }

  int get bytePos => (bit + 7) >> 3;
}

// ---------------------------------------------------------------- FSE
class _Fse {
  final int accuracy;
  final Int32List symbol, nbBits, baseline;
  _Fse(this.accuracy)
      : symbol = Int32List(1 << accuracy),
        nbBits = Int32List(1 << accuracy),
        baseline = Int32List(1 << accuracy);

  /// Builds the decoding table from normalised counts (-1 = "less than 1").
  static _Fse build(List<int> norm, int accuracy) {
    final t = _Fse(accuracy);
    final size = 1 << accuracy;
    var high = size - 1;
    final next = List<int>.filled(norm.length, 0);
    for (var s = 0; s < norm.length; s++) {
      if (norm[s] == -1) {
        t.symbol[high--] = s;
        next[s] = 1;
      } else {
        next[s] = norm[s];
      }
    }
    final step = (size >> 1) + (size >> 3) + 3;
    final mask = size - 1;
    var pos = 0;
    for (var s = 0; s < norm.length; s++) {
      for (var i = 0; i < norm[s]; i++) {
        t.symbol[pos] = s;
        do {
          pos = (pos + step) & mask;
        } while (pos > high);
      }
    }
    if (pos != 0) throw ZstdException('corrupt FSE distribution');
    for (var i = 0; i < size; i++) {
      final s = t.symbol[i];
      final x = next[s]++;
      var hb = 31;
      while (hb > 0 && (x >> hb) == 0) {
        hb--;
      }
      final nb = accuracy - hb;
      t.nbBits[i] = nb;
      t.baseline[i] = (x << nb) - size;
    }
    return t;
  }

  static _Fse rle(int sym) {
    final t = _Fse(0);
    t.symbol[0] = sym;
    t.nbBits[0] = 0;
    t.baseline[0] = 0;
    return t;
  }

  /// Reads a table description; returns (table, bytes consumed).
  static (_Fse, int) read(Uint8List b, int start, int maxSymbol, int maxLog) {
    final r = _FwdBits(b, start);
    final accuracy = r.read(4) + 5;
    if (accuracy > maxLog) throw ZstdException('FSE accuracy too large');
    var remaining = (1 << accuracy) + 1;
    var threshold = 1 << accuracy;
    var nbBits = accuracy + 1;
    final norm = <int>[];
    while (remaining > 1 && norm.length <= maxSymbol) {
      final max = (2 * threshold - 1) - remaining;
      int count;
      final low = r.peek(nbBits - 1);
      if (low < max) {
        count = r.read(nbBits - 1);
      } else {
        count = r.read(nbBits);
        if (count >= threshold) count -= max;
      }
      count -= 1;
      norm.add(count);
      remaining -= count.abs();
      if (count == 0) {
        // repeat flags: runs of zero-probability symbols
        while (true) {
          final rep = r.read(2);
          for (var i = 0; i < rep; i++) {
            norm.add(0);
          }
          if (rep != 3) break;
        }
      }
      while (remaining < threshold) {
        nbBits--;
        threshold >>= 1;
      }
    }
    if (remaining != 1) throw ZstdException('corrupt FSE table description');
    return (build(norm, accuracy), r.bytePos - start);
  }
}

class _FseState {
  final _Fse t;
  int state = 0;
  _FseState(this.t);
  void init(_BackBits br) => state = br.read(t.accuracy);
  int get symbol => t.symbol[state];
  void update(_BackBits br) {
    state = t.baseline[state] + br.read(t.nbBits[state]);
  }
}

// ---------------------------------------------------------------- Huffman
class _Huff {
  final int maxBits;
  final Uint8List sym, len;
  _Huff(this.maxBits)
      : sym = Uint8List(1 << maxBits),
        len = Uint8List(1 << maxBits);

  static (_Huff, int) read(Uint8List b, int start) {
    final h = b[start];
    final weights = <int>[];
    var used = 1;
    if (h >= 128) {
      final n = h - 127;
      for (var i = 0; i < n; i++) {
        final byte = b[start + 1 + (i >> 1)];
        weights.add(i.isEven ? byte >> 4 : byte & 15);
      }
      used += (n + 1) >> 1;
    } else {
      // FSE-compressed weights, two interleaved states
      final (fse, hdr) = _Fse.read(b, start + 1, 255, 6);
      final br = _BackBits(b, start + 1 + hdr, start + 1 + h);
      final s1 = _FseState(fse)..init(br);
      final s2 = _FseState(fse)..init(br);
      while (true) {
        weights.add(s1.symbol);
        s1.update(br);
        if (br.overflowed) {
          weights.add(s2.symbol);
          break;
        }
        weights.add(s2.symbol);
        s2.update(br);
        if (br.overflowed) {
          weights.add(s1.symbol);
          break;
        }
        if (weights.length > 255) throw ZstdException('too many Huffman weights');
      }
      used += h;
    }
    var total = 0;
    for (final w in weights) {
      if (w > 0) total += 1 << (w - 1);
    }
    var maxBits = 0;
    while ((1 << maxBits) <= total) {
      maxBits++;
    }
    final rest = (1 << maxBits) - total;
    var lastW = 0;
    while ((1 << lastW) < rest) {
      lastW++;
    }
    if ((1 << lastW) != rest) throw ZstdException('corrupt Huffman weights');
    weights.add(lastW + 1);
    final t = _Huff(maxBits);
    // canonical: symbols ranked by weight, then by value; fill from the start
    var pos = 0;
    for (var w = 1; w <= maxBits; w++) {
      for (var s = 0; s < weights.length; s++) {
        if (weights[s] != w) continue;
        final n = 1 << (w - 1);
        final l = maxBits + 1 - w;
        for (var i = 0; i < n; i++) {
          t.sym[pos] = s;
          t.len[pos] = l;
          pos++;
        }
      }
    }
    return (t, used);
  }

  void decodeStream(Uint8List b, int start, int end, Uint8List out, int o, int n) {
    final br = _BackBits(b, start, end);
    var state = br.read(maxBits);
    for (var i = 0; i < n; i++) {
      out[o + i] = sym[state];
      final l = len[state];
      state = ((state << l) & ((1 << maxBits) - 1)) | br.read(l);
    }
  }
}

// ---------------------------------------------------------------- tables
const _llBase = [
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28,
  32, 40, 48, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536,
];
const _llBits = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 4, 6,
  7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
];
const _mlBase = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
  24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 37, 39, 41, 43, 47, 51, 59,
  67, 83, 99, 131, 259, 515, 1027, 2051, 4099, 8195, 16387, 32771, 65539,
];
const _mlBits = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13,
  14, 15, 16,
];
const _llDefault = [
  4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3,
  2, 1, 1, 1, 1, 1, -1, -1, -1, -1,
];
const _mlDefault = [
  1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1,
  -1, -1, -1,
];
const _ofDefault = [
  1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1,
  -1, -1, -1, -1,
];

final _Fse _llPre = _Fse.build(_llDefault, 6);
final _Fse _mlPre = _Fse.build(_mlDefault, 6);
final _Fse _ofPre = _Fse.build(_ofDefault, 5);

// ---------------------------------------------------------------- frame
class _Frame {
  final Uint8List src;
  int p;
  final _Out out;
  final int frameStart;
  _Huff? huff;
  _Fse? ll, of, ml;
  final reps = [1, 4, 8];

  _Frame(this.src, this.p, this.out) : frameStart = out.length;

  int decode() {
    final fhd = src[p++];
    final fcsFlag = fhd >> 6;
    final single = (fhd >> 5) & 1 == 1;
    final checksum = (fhd >> 2) & 1 == 1;
    final dictFlag = fhd & 3;
    if (!single) p++; // window descriptor
    if (dictFlag != 0) {
      final n = [0, 1, 2, 4][dictFlag];
      var id = 0;
      for (var i = 0; i < n; i++) {
        id |= src[p + i] << (8 * i);
      }
      p += n;
      if (id != 0) throw ZstdException('zstd dictionaries are not supported');
    }
    p += [single ? 1 : 0, 2, 4, 8][fcsFlag];
    while (true) {
      if (p + 3 > src.length) throw ZstdException('truncated block header');
      final h = src[p] | (src[p + 1] << 8) | (src[p + 2] << 16);
      p += 3;
      final last = h & 1 == 1;
      final type = (h >> 1) & 3;
      final size = h >> 3;
      switch (type) {
        case 0:
          out.addAll(src, p, p + size);
          p += size;
          break;
        case 1:
          out.fill(src[p], size);
          p += 1;
          break;
        case 2:
          _block(p, p + size);
          p += size;
          break;
        default:
          throw ZstdException('reserved block type');
      }
      if (last) break;
    }
    if (checksum) p += 4;
    return p;
  }

  void _block(int start, int end) {
    var q = start;
    // ---- literals
    final b0 = src[q];
    final ltype = b0 & 3;
    final sf = (b0 >> 2) & 3;
    int regen, comp = 0, streams = 1;
    if (ltype < 2) {
      if (sf == 0 || sf == 2) {
        regen = b0 >> 3;
        q += 1;
      } else if (sf == 1) {
        regen = (b0 >> 4) | (src[q + 1] << 4);
        q += 2;
      } else {
        regen = (b0 >> 4) | (src[q + 1] << 4) | (src[q + 2] << 12);
        q += 3;
      }
    } else {
      final hbytes = sf < 2 ? 3 : (sf == 2 ? 4 : 5);
      var v = 0;
      for (var i = 0; i < hbytes; i++) {
        v |= src[q + i] << (8 * i);
      }
      final bits = sf < 2 ? 10 : (sf == 2 ? 14 : 18);
      regen = (v >> 4) & ((1 << bits) - 1);
      comp = (v >> (4 + bits)) & ((1 << bits) - 1);
      streams = sf == 0 ? 1 : 4;
      q += hbytes;
    }
    final lit = Uint8List(regen);
    if (ltype == 0) {
      lit.setRange(0, regen, src, q);
      q += regen;
    } else if (ltype == 1) {
      lit.fillRange(0, regen, src[q]);
      q += 1;
    } else {
      final lend = q + comp;
      if (ltype == 2) {
        final (h, used) = _Huff.read(src, q);
        huff = h;
        q += used;
      } else if (huff == null) {
        throw ZstdException('treeless literals without a previous tree');
      }
      final h = huff!;
      if (streams == 1) {
        h.decodeStream(src, q, lend, lit, 0, regen);
      } else {
        final s1 = src[q] | (src[q + 1] << 8);
        final s2 = src[q + 2] | (src[q + 3] << 8);
        final s3 = src[q + 4] | (src[q + 5] << 8);
        final a = q + 6, bb = a + s1, c = bb + s2, d = c + s3;
        final seg = (regen + 3) >> 2;
        h.decodeStream(src, a, bb, lit, 0, seg);
        h.decodeStream(src, bb, c, lit, seg, seg);
        h.decodeStream(src, c, d, lit, 2 * seg, seg);
        h.decodeStream(src, d, lend, lit, 3 * seg, regen - 3 * seg);
      }
      q = lend;
    }
    // ---- sequences
    var nseq = src[q++];
    if (nseq == 0) {
      out.addAll(lit, 0, regen);
      return;
    }
    if (nseq >= 128) {
      if (nseq < 255) {
        nseq = ((nseq - 128) << 8) + src[q++];
      } else {
        nseq = src[q] + (src[q + 1] << 8) + 0x7F00;
        q += 2;
      }
    }
    final modes = src[q++];
    final (llT, q1) = _table(modes >> 6, q, ll, _llPre, 35, 9);
    final (ofT, q2) = _table((modes >> 4) & 3, q1, of, _ofPre, 31, 8);
    final (mlT, q3) = _table((modes >> 2) & 3, q2, ml, _mlPre, 52, 9);
    ll = llT;
    of = ofT;
    ml = mlT;
    q = q3;
    final br = _BackBits(src, q, end);
    final sLL = _FseState(ll!)..init(br);
    final sOF = _FseState(of!)..init(br);
    final sML = _FseState(ml!)..init(br);
    var litPos = 0;
    for (var i = 0; i < nseq; i++) {
      final ofCode = sOF.symbol;
      final mlCode = sML.symbol;
      final llCode = sLL.symbol;
      if (llCode > 35 || mlCode > 52 || ofCode > 31) {
        throw ZstdException('corrupt sequence codes');
      }
      final ofValue = (1 << ofCode) + br.read(ofCode);
      final matchLen = _mlBase[mlCode] + br.read(_mlBits[mlCode]);
      final litLen = _llBase[llCode] + br.read(_llBits[llCode]);
      int offset;
      if (ofValue > 3) {
        offset = ofValue - 3;
        reps[2] = reps[1];
        reps[1] = reps[0];
        reps[0] = offset;
      } else {
        var idx = ofValue - 1;
        if (litLen == 0) idx++;
        if (idx == 0) {
          offset = reps[0];
        } else {
          offset = idx == 3 ? reps[0] - 1 : reps[idx];
          if (idx > 1) reps[2] = reps[1];
          reps[1] = reps[0];
          reps[0] = offset;
        }
      }
      if (litPos + litLen > regen) throw ZstdException('literal overrun');
      out.addAll(lit, litPos, litPos + litLen);
      litPos += litLen;
      out.copyMatch(offset, matchLen, frameStart);
      if (i < nseq - 1) {
        sLL.update(br);
        sML.update(br);
        sOF.update(br);
      }
    }
    out.addAll(lit, litPos, regen);
  }

  (_Fse?, int) _table(int mode, int q, _Fse? prev, _Fse pre, int maxSym, int maxLog) {
    switch (mode) {
      case 0:
        return (pre, q);
      case 1:
        return (_Fse.rle(src[q]), q + 1);
      case 2:
        final (t, used) = _Fse.read(src, q, maxSym, maxLog);
        return (t, q + used);
      default:
        if (prev == null) throw ZstdException('repeat mode without a table');
        return (prev, q);
    }
  }
}
