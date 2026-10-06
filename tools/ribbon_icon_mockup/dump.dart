import 'dart:convert';
import 'dart:io';
import '../../frontend/lib/svg_icons.dart';
/// Dumps every icon in frontend/lib/svg_icons.dart to JSON for build.py.
/// Usage: dart run tools/ribbon_icon_mockup/dump.dart <out/icons.json>
void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run dump.dart <out.json>');
    exit(64);
  }
  final maps = {'IC':IC,'CN':CN,'IN':IN,'MD':MD,'PD':PD,'VW':VW,'MS':MS,'CR':CR,'MO':MO,'WF':WF,'PT':PT,'PL':PL,'AX':AX,'PN':PN,'AS':AS,'AC':AC};
  final singles = {'layerBigIcon':layerBigIcon,'finishIcon':finishIcon,'returnIcon':returnIcon,'newSketchIcon':newSketchIcon,'layerRowIcon':layerRowIcon,'sketchCubeIcon':sketchCubeIcon,'sharedSketchCubeIcon':sharedSketchCubeIcon,'treeCubeIcon':treeCubeIcon,'treeRootCubeIcon':treeRootCubeIcon,'treeFolderIcon':treeFolderIcon,'originIcon':originIcon,'xAxisIcon':xAxisIcon,'yAxisIcon':yAxisIcon,'zAxisIcon':zAxisIcon,'centerPointIcon':centerPointIcon,'endOfSketchIcon':endOfSketchIcon,'homeTabIcon':homeTabIcon,'tabHomeIcon':tabHomeIcon,'asmSelectionIcon':asmSelectionIcon,'asmPickPartIcon':asmPickPartIcon,'asmPreviewIcon':asmPreviewIcon,'asmPredictIcon':asmPredictIcon,'asmSickIcon':asmSickIcon,'asmConstraintIcon':asmConstraintIcon,'asmSuppressedIcon':asmSuppressedIcon,'assemblyMenuIcon':assemblyMenuIcon,'assemblyCubeIcon':assemblyCubeIcon,'componentCubeIcon':componentCubeIcon,'groundedPinIcon':groundedPinIcon,'asmPatternIcon':asmPatternIcon,'relationshipsIcon':relationshipsIcon,'representationsIcon':representationsIcon,'viewRepActiveIcon':viewRepActiveIcon,'viewRepIcon':viewRepIcon,'viewRepLockedIcon':viewRepLockedIcon,'inPlaceReturnIcon':inPlaceReturnIcon,'partCubeIcon':partCubeIcon,'derivedCubeIcon':derivedCubeIcon,'planeIcon':planeIcon,'sketch2dMenuIcon':sketch2dMenuIcon,'part3dMenuIcon':part3dMenuIcon};
  File(args[0]).writeAsStringSync(jsonEncode({'maps':maps,'singles':singles}));
  var n = singles.length; maps.forEach((k,v)=> n += v.length);
  print('icons: $n');
}
