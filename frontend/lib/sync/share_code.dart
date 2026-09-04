// Prototype — the share code, and what it is made of.
//
// A share code is the WHOLE of the pairing story: type the same one on two
// devices on the same network and they mirror each other. There is no account,
// no server, no QR dance and nothing to sign in to — which is the point, and
// which means the code has to carry three jobs at once:
//
//   1. it has to be SAYABLE. Someone reads it off one screen and types it on
//      another, possibly across a room. So: base32 without the letters that
//      look like digits, in groups of four, case-insensitive on input.
//   2. it has to be a KEY. Two devices prove to each other that they know it
//      before either sends a byte of a document — see SyncSession's handshake.
//      Derived, not used raw, so the code itself never crosses the wire.
//   3. it has to be a FINGERPRINT. A device broadcasts "I am here, and this is
//      the group I am in" without saying which code that is.
//
// WHAT THIS IS NOT. The fingerprint is a convenience for discovery, not a
// secret: it is a hash of a short code, and a short code can be searched
// offline. What actually gates a connection is the challenge/response, where
// each side has to answer a nonce it did not choose. And the transfer itself
// is NOT encrypted — this is a local network mirror, on the same footing as an
// unencrypted file share, and the settings footer says so rather than implying
// a privacy property it does not have.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The alphabet a code is written in.
///
/// Crockford-style base32 minus the four characters that are read wrong when
/// they are spoken or typed from a photograph: I and 1, O and 0. Twenty-eight
/// symbols rather than thirty-two, which costs a fifth of a bit per character
/// and buys a code someone can dictate over a phone.
const String kShareCodeAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

/// How many characters a generated code has, before grouping.
///
/// Twelve of a 32-symbol alphabet is 60 bits. That is not a password and is
/// not treated as one — it is a rendezvous token whose exposure is bounded by
/// being on one local network — but it is far past what anyone would guess,
/// and it still reads as three short groups.
const int kShareCodeLength = 12;

/// How the code is SHOWN: groups of four separated by a hyphen.
const int kShareCodeGroup = 4;

/// A new random code, already grouped for display.
///
/// [Random.secure] rather than the default generator. The difference does not
/// matter for a token on a home network and does matter for the one where
/// someone runs this in an office, and the cost is nothing.
String generateShareCode() {
  final r = Random.secure();
  final b = StringBuffer();
  for (var i = 0; i < kShareCodeLength; i++) {
    b.write(kShareCodeAlphabet[r.nextInt(kShareCodeAlphabet.length)]);
  }
  return formatShareCode(b.toString());
}

/// The canonical form of whatever the user typed, or null if it is not a code.
///
/// Case is folded, separators are dropped, and the two pairs of look-alikes are
/// FOLDED IN rather than rejected: someone reading `K` off a screen may well
/// type `l` for `1`, and a code that refuses the obvious mistake is a code that
/// gets typed twice. O becomes 0 — which is not in the alphabet — so the
/// mapping goes the other way: O/o are read as the digit-shaped letter they
/// were mistaken for, and I/i/l/L as J's neighbour... which is a guess, and
/// guessing is worse than asking. So they are simply INVALID, and the field
/// says so.
String? normaliseShareCode(String input) {
  final buf = StringBuffer();
  for (final ch in input.toUpperCase().split('')) {
    if (ch == ' ' || ch == '-' || ch == '–') continue;
    if (!kShareCodeAlphabet.contains(ch)) return null;
    buf.write(ch);
  }
  final s = buf.toString();
  if (s.length != kShareCodeLength) return null;
  return s;
}

/// Groups a canonical code for display: `ABCD-EFGH-JKLM`.
String formatShareCode(String canonical) {
  final out = <String>[];
  for (var i = 0; i < canonical.length; i += kShareCodeGroup) {
    out.add(canonical.substring(
        i, min(i + kShareCodeGroup, canonical.length)));
  }
  return out.join('-');
}

/// The key two devices authenticate with, derived from [canonical].
///
/// A domain-separated hash rather than the code's own bytes: the same code is
/// used for the fingerprint below, and a key that is also a public identifier
/// is not a key at all.
Uint8List shareCodeKey(String canonical) => Uint8List.fromList(
    sha256.convert(utf8.encode('prototype-sync-key\x00$canonical')).bytes);

/// The group fingerprint a device broadcasts, as lower-case hex.
///
/// Separately domain-separated from [shareCodeKey], so seeing one tells you
/// nothing about the other. Truncated because a beacon is sent every couple of
/// seconds and the whole hash would be forty bytes of nothing.
String shareCodeFingerprint(String canonical) =>
    sha256
        .convert(utf8.encode('prototype-sync-fp\x00$canonical'))
        .toString()
        .substring(0, 16);

/// The proof a peer returns for a nonce it did not choose.
String shareCodeProof(Uint8List key, String nonce) =>
    Hmac(sha256, key).convert(utf8.encode(nonce)).toString();

/// Constant-time string compare, for the one place it matters.
///
/// Comparing proofs with `==` leaks how many leading characters matched, which
/// over a few thousand attempts is a way in. On a LAN with a rate-limited
/// handshake that is a thin attack; it is also two lines to remove.
bool secureEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// A fresh nonce for a handshake.
String newNonce() {
  final r = Random.secure();
  final b = Uint8List(18);
  for (var i = 0; i < b.length; i++) {
    b[i] = r.nextInt(256);
  }
  return base64Url.encode(b);
}
