// M405 — #38: "the ribbon should also be retracted when the App is installed
// on iphone. retracted by default. but only on iphone, Not on ipad".
//
// The model browser has retracted by default since M242; this is its twin,
// and the "only on iPhone" is the whole of it. On a 390-point screen the band
// is a rail of icons taking a fifth of the width; on an iPad, where the
// browser retracts and the ribbon does not, that is a judgement someone made
// with the space to make it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/device_class.dart';
import 'package:prototype/ribbon_dock.dart';

void main() {
  setUp(RibbonRetract.resetForTest);
  tearDown(RibbonRetract.resetForTest);

  test('out by default — an iPad and every desktop are untouched', () {
    expect(RibbonRetract.on, isFalse);
    RibbonRetract.adoptDefault(phone: false);
    expect(RibbonRetract.on, isFalse);
  });

  test('away by default on a phone', () {
    RibbonRetract.adoptDefault(phone: true);
    expect(RibbonRetract.on, isTrue);
  });

  test('a stored choice beats the default, in that order', () async {
    // Someone who pulled the band out on their iPhone keeps it out. The order
    // is what makes that work: the device answers first and the file second.
    final dir = await Directory.systemTemp.createTemp('m405');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/${RibbonStore.fileName}')
        .writeAsStringSync(jsonEncode({RibbonStore.retractedKey: false}));

    RibbonRetract.adoptDefault(phone: true);
    expect(RibbonRetract.on, isTrue, reason: 'the phone default');
    RibbonRetract.attachStore(RibbonStore(dir));
    expect(RibbonRetract.on, isFalse, reason: 'and the owner overrules it');
  });

  test('a file that says nothing about it leaves the default alone', () async {
    final dir = await Directory.systemTemp.createTemp('m405');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/${RibbonStore.fileName}')
        .writeAsStringSync(jsonEncode({'ribbon': 'left'}));
    RibbonRetract.adoptDefault(phone: true);
    RibbonRetract.attachStore(RibbonStore(dir));
    expect(RibbonRetract.on, isTrue);
  });

  test('toggling writes it back, beside the other ribbon settings', () async {
    final dir = await Directory.systemTemp.createTemp('m405');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = RibbonStore(dir);
    // Something else is in the file first: the retract must merge into it
    // rather than own it, which is the rule every store in this app follows.
    store.saveNames(true);
    RibbonRetract.attachStore(store);
    RibbonRetract.toggle();
    expect(RibbonRetract.on, isTrue);
    expect(store.loadRetracted(), isTrue);
    expect(store.loadNames(), isTrue, reason: 'the neighbour survived');
  });

  test('a corrupt file costs the preference and nothing else', () async {
    final dir = await Directory.systemTemp.createTemp('m405');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/${RibbonStore.fileName}').writeAsStringSync('{oh no');
    expect(RibbonStore(dir).loadRetracted(), isNull);
    RibbonRetract.adoptDefault(phone: true);
    RibbonRetract.attachStore(RibbonStore(dir));
    expect(RibbonRetract.on, isTrue, reason: 'the default still stands');
  });

  test('the host is not a phone, so nothing here retracts itself', () {
    // isPhoneDevice is iOS-only by construction: the test host is not iOS and
    // must never be read as one, or every widget test would lose its ribbon.
    expect(isPhoneDevice(), isFalse);
  });
}
