// M404 — #36: "on windows there is still the option reality kit or cycles but
// reality kit doesnt exist at all on windows. another real time renderer
// should be used."
//
// Another one already was: the viewport picks RealityKit on iOS and
// flutter_scene on Flutter GPU everywhere else, and the log on that machine
// says "renderer: flutter_scene (Flutter GPU)" at every launch. What was wrong
// was the LABEL on the picker, which named a renderer that is not in a Windows
// build at all — so the option looked like a choice between something absent
// and something present.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/render_engine.dart';

void main() {
  test('the stored id keeps its old spelling', () {
    // Renaming the enum value must not reset anybody's saved choice: this
    // string is in every settings.json in the field.
    expect(RenderEngine.realtime.id, 'realitykit');
    expect(RenderEngine.byId('realitykit'), RenderEngine.realtime);
    expect(RenderEngine.cycles.id, 'cycles');
  });

  test('the default is the instant one, whatever draws it', () {
    // Unchanged by the rename, and for the reason the header gives: rendered
    // mode has to stay instant unless you ask for the path tracer.
    expect(kRenderEngineDefault, RenderEngine.realtime);
    expect(RenderEngines.current, RenderEngine.realtime);
    expect(RenderEngines.isRealtime, isTrue);
    expect(RenderEngines.isCycles, isFalse);
  });

  test('nothing is called RealityKit where RealityKit cannot run', () {
    // In the host test there is no platform view and no Flutter GPU context,
    // so the honest answer is no name at all — and, crucially, never the name
    // of an engine this build does not contain.
    final name = realtimeEngineName();
    expect(name, anyOf(isNull, 'RealityKit', 'Flutter GPU'));
    expect(name, isNot('RealityKit'),
        reason: 'RealityKit is iOS only, and this is not iOS');
  });

  test('the two engines are the two questions, not two products', () {
    // The choice is "every frame" against "one path-traced image". If a third
    // value ever appears it has to be one of those two things, or the picker
    // is answering a different question than its label says.
    expect(RenderEngine.values, hasLength(2));
  });
}
