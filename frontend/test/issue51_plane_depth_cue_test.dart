// #51 — "somehow the planes look weird. the edges are the same color and
// exactly the same even when they are behind another plane. this looks very
// weird".
//
// That reads like an impression and is a measurement. All three origin planes
// were one frozen orange in the renderer, with a border a few parts away from
// it, and the renderer draws a plane as a 28%-opaque fill over an opaque
// border. So a border seen THROUGH the plane in front of it is
//
//     fill * 0.28 + border * 0.72
//
// which for (0xEA, 0x9E, 0x5C) over (0xF0, 0xA8, 0x68) is (238.3, 165.2,
// 100.6) against (240, 168, 104) — under FOUR PARTS IN 255 on the widest
// channel. "Exactly the same" is the literal reading, not an exaggeration:
// there was no depth cue to see. And with one colour on all three, a pair of
// crossing borders said nothing about which plane either belonged to.
//
// Each origin plane now takes the colour of the axis it stands across, so the
// wash in front of a border is a different HUE. These tests do the same
// arithmetic the renderer does and hold the result to a margin the old scheme
// could not have met — `oldSchemeWouldFail` runs it against the two oranges
// and shows exactly how far short they fall.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart';
import 'package:prototype/theme.dart';

/// What the renderer composites: `Materials.unlitTransparent(fill, 0.28)` over
/// the opaque border underneath it. Kept here as the one place that mirrors
/// PlaneEntity.buildFill's alpha, so it is obvious what these numbers mean.
const double kPlaneFillAlpha = 0.28;

Color _over(Color fill, Color border, double alpha) => Color.fromARGB(
      255,
      ((fill.r * alpha + border.r * (1 - alpha)) * 255).round(),
      ((fill.g * alpha + border.g * (1 - alpha)) * 255).round(),
      ((fill.b * alpha + border.b * (1 - alpha)) * 255).round(),
    );

/// The widest per-channel difference between two colours, in 0..255. Crude on
/// purpose: the failure being pinned is three orders of magnitude away from
/// any argument about perceptual colour spaces.
int _gap(Color a, Color b) => [
      ((a.r - b.r).abs() * 255).round(),
      ((a.g - b.g).abs() * 255).round(),
      ((a.b - b.b).abs() * 255).round(),
    ].reduce(math.max);

/// Comfortably above what the old scheme could produce (4) and far below what
/// the new one does (tens). A border behind a plane has to differ from the
/// same border in the open by at least this much, or "behind" is invisible.
const int kMinDepthCue = 12;

void main() {
  tearDown(T.resetForTest);

  for (final palette in [kEmber, kChalk]) {
    final scheme = palette.brightness == Brightness.dark ? 'dark' : 'light';

    test('$scheme — a border BEHIND a plane is visibly not one in front', () {
      T.palette = palette;
      for (final mine in kPlaneKeys) {
        final (_, border) = T.originPlane(mine);
        for (final theirs in kPlaneKeys) {
          if (theirs == mine) continue;
          final (fill, _) = T.originPlane(theirs);
          final behind = _over(fill, border, kPlaneFillAlpha);
          expect(_gap(behind, border), greaterThanOrEqualTo(kMinDepthCue),
              reason: '$mine seen through $theirs must read as behind it');
        }
      }
    });

    test('$scheme — the three planes do not share a colour', () {
      T.palette = palette;
      for (final a in kPlaneKeys) {
        for (final b in kPlaneKeys) {
          if (a == b) continue;
          expect(_gap(T.originPlane(a).$1, T.originPlane(b).$1),
              greaterThanOrEqualTo(kMinDepthCue),
              reason: 'fills of $a and $b are tellable apart');
          expect(_gap(T.originPlane(a).$2, T.originPlane(b).$2),
              greaterThanOrEqualTo(kMinDepthCue),
              reason: 'borders of $a and $b are tellable apart');
        }
      }
    });

    test('$scheme — a border still reads against its OWN fill', () {
      T.palette = palette;
      for (final key in kPlaneKeys) {
        final (fill, border) = T.originPlane(key);
        expect(_gap(fill, border), greaterThanOrEqualTo(kMinDepthCue),
            reason: '$key: the border is not lost in its own sheet');
      }
    });
  }

  test('the old single-orange scheme misses that margin by a factor of three',
      () {
    // The exact two colours PlaneEntity used for every plane, and still falls
    // back to for a payload that carries no tint. Not a hypothetical: this is
    // what the report was looking at.
    const fill = Color(0xFFEA9E5C); // Colors.orange
    const border = Color(0xFFF0A868); // Colors.orangeEdge
    final behind = _over(fill, border, kPlaneFillAlpha);
    expect(_gap(behind, border), lessThan(5),
        reason: 'the measurement in this file header');
    expect(_gap(behind, border), lessThan(kMinDepthCue),
        reason: 'which is why the planes read as having no depth at all');
  });

  test('every origin plane ships its colours; a work plane keeps the default',
      () {
    T.palette = kEmber;
    for (final key in kPlaneKeys) {
      final p = planeTintPayload(key);
      expect(p['tint'], isA<int>());
      expect(p['edge'], isA<int>());
      // Zero is the renderer's "no colour given" sentinel — shipping it would
      // silently fall back to orange and put the bug straight back.
      expect(p['tint'], isNot(0));
      expect(p['edge'], isNot(0));
      expect(p['tint'], isNot(p['edge']));
    }
    // A user's work plane stands across no axis, so it carries nothing and the
    // renderer draws the orange it always has.
    expect(planeTintPayload('wp:7'), isEmpty);
    expect(planeTintPayload('wp:preview'), isEmpty);
  });

  test('the payload packs ARGB the way the renderer unpacks it', () {
    T.palette = kEmber;
    final (fill, _) = T.originPlane('xy');
    final argb = planeTintPayload('xy')['tint'] as int;
    // Payload.color in PartScene.swift reads exactly these shifts.
    expect((argb >> 24) & 0xFF, (fill.a * 255).round());
    expect((argb >> 16) & 0xFF, (fill.r * 255).round());
    expect((argb >> 8) & 0xFF, (fill.g * 255).round());
    expect(argb & 0xFF, (fill.b * 255).round());
  });

  test('a plane takes the colour of the axis it stands ACROSS', () {
    T.palette = kEmber;
    // The same axisX/Y/Z the coordinate triad draws, so the plane and the axis
    // through it say the same thing rather than two different ones.
    expect(T.originPlane('yz').$1, T.axisX);
    expect(T.originPlane('xz').$1, T.axisY);
    expect(T.originPlane('xy').$1, T.axisZ);
  });
}
