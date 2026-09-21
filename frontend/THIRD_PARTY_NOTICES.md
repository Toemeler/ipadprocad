# Third-party notices

Code in this app that came from somewhere else, and the terms it came under.

Dependencies declared in `pubspec.yaml` carry their own licences through pub
and Flutter's `showLicensePage`; this file is for code that was PORTED or
COPIED into this repository, where nothing else would record where it is from.

---

## Apple Intelligence Glow Effect

Ported into `lib/widgets/ai_stage.dart` as `AiGlowBorder`, and the six hues it
uses, in `lib/theme.dart` as `kAiIntelligenceHues`.

The original is SwiftUI; this is a Dart re-implementation of its technique —
an angular gradient of six fixed hues whose stop positions are re-randomised
several times a second and eased between, stroked repeatedly with increasing
width and blur. The hue values are copied verbatim.

Source: https://github.com/jacobamobin/AppleIntelligenceGlowEffect

```
MIT License

Copyright (c) 2025 Jacob Mobin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

This app is not affiliated with or endorsed by Apple. "Apple Intelligence" is
Apple's trademark; the glow is an independent recreation, because Apple vends
no API for it.
