#
# iPadProCAD — in-repo iOS plugin: a RealityKit-backed 3D viewport.
#
# Same delivery path as native_menu (M48) and file_picker (M44): there is no
# hand-written frontend/ios/ in this repo — CI scaffolds the Runner with
# `flutter create` every run, so native code lives in a plugin pod that
# CocoaPods discovers from `.flutter-plugins-dependencies`. This pod links the
# RealityKit / ARKit / Metal stack the viewport needs.
#
Pod::Spec.new do |s|
  s.name             = 'reality_view'
  s.version          = '0.1.0'
  s.summary          = 'RealityKit 3D viewport surface for iPadProCAD.'
  s.description      = <<-DESC
Embeds a RealityKit ARView (.nonAR) as a Flutter platform view and renders the
CAD part on the GPU: true orthographic camera (OrthographicCameraComponent on
iOS 18+, near-orthographic PerspectiveCamera fallback below), physically-based
shading and — crucially — a real depth buffer, so origin planes, sketches and
edges occlude correctly without the CPU painter's screen-space tricks.
                       DESC
  s.homepage         = 'https://github.com/Toemeler/ipadprocad'
  s.license          = { :type => 'GPLv3' }
  s.author           = { 'iPadProCAD' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'

  # RealityKit + ARKit are weak-linked: the app deployment target is 14.0, the
  # orthographic camera path is gated to iOS 18 at runtime, and ARView(.nonAR)
  # is available from iOS 13 — weak linking keeps the binary loadable on 14/15.
  s.weak_frameworks  = 'RealityKit', 'ARKit'
  # simd is a header-only module (`import simd`), NOT a linkable framework, so
  # it must not appear here — it needs no -framework flag.
  s.frameworks       = 'Metal', 'MetalKit', 'QuartzCore'

  # Flutter.framework does not contain an i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
