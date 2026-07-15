// iPadProCAD — hand-drawn Inventor-style inline SVGs, ported VERBATIM from
// create-panel.html (the binding design spec). Icon language: light gray
// geometry, blue square grips, red constraints with grey cursor arrows/checks,
// yellow bolts, no green except the plus in the layer icon.
//
// Rendered with flutter_svg (SvgPicture.string).

// Icon language constants (same names as in the mock's JS).
const G = '#C4C9CE';
const BL = '#3D9BE9';
const DIM = '#82888f';
const RD = '#E05A56';
const YL = '#E8C63F';
const RDD = '#a83e3b';
const GC = '#9aa0a6';
const BLM = '#3D9BE9';

String S(num vb, String inner) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $vb $vb" fill="none" stroke-linecap="round" stroke-linejoin="round">$inner</svg>';
String gp(num x, num y, [num sz = 3.4]) =>
    '<rect x="${x - sz / 2}" y="${y - sz / 2}" width="$sz" height="$sz" fill="$BL"/>';
String gpd(num x, num y, [num r = 1.9]) =>
    '<circle cx="$x" cy="$y" r="$r" fill="$BL"/>';
String cursorArrow(num x, num y) =>
    '<path d="M$x ${y}l4.2 1.6-1.8.7 1.1 2-1 .5-1.1-2-1.4 1.4z" fill="$GC"/>';
String check(num x, num y) =>
    '<path d="M$x ${y}l1.5 1.7 2.7-3.2" stroke="$GC" stroke-width="1.3" fill="none"/>';
String bolt(num x, num y, [num s = 1]) =>
    '<path d="M${x + 3 * s} ${y}l-3.2 ${4.6 * s}h${2.1 * s}l-1.4 ${3.6 * s} 3.9-${5 * s}h-${2.2 * s}l1.2-${3.2 * s}z" fill="$YL" stroke="#9a8320" stroke-width=".5"/>';

// ==== Create panel (big 34px + small 18px + flyout 26px) ====
final Map<String, String> IC = {
  'line34': S(34,
      '<line x1="7" y1="27" x2="27" y2="7" stroke="$G" stroke-width="1.7"/>${gp(7, 27, 4)}${gp(27, 7, 4)}'),
  'circle34': S(34,
      '<circle cx="17" cy="17" r="12" stroke="$G" stroke-width="1.7"/>${gpd(17, 17, 2.4)}'),
  'arc34': S(34,
      '<path d="M7 27 A 16.5 16.5 0 0 1 27 9" stroke="$G" stroke-width="1.7"/>${gp(7, 27, 4)}${gp(15, 15.5, 4)}${gp(27, 9, 4)}'),
  'rect34': S(34,
      '<rect x="6" y="9" width="22" height="16" stroke="$G" stroke-width="1.7"/>${gp(6, 9, 4)}${gp(28, 9, 4)}${gp(6, 25, 4)}${gp(28, 25, 4)}'),
  'fillet18':
      S(18, '<path d="M3 15v-6 A 6 6 0 0 1 9 3h6" stroke="$G" stroke-width="1.5"/>'),
  'text18': S(18,
      '<text x="9" y="13.5" font-size="14" font-weight="600" fill="$G" text-anchor="middle" font-family="Segoe UI" stroke="none">A</text>'),
  'point18': S(18,
      '<line x1="9" y1="3" x2="9" y2="15" stroke="$G" stroke-width="1.2"/><line x1="3" y1="9" x2="15" y2="9" stroke="$G" stroke-width="1.2"/>${gp(9, 9, 3.4)}'),
  'fline': S(26,
      '<line x1="5" y1="21" x2="21" y2="5" stroke="$G" stroke-width="1.5"/>${gp(5, 21, 3.4)}${gp(21, 5, 3.4)}'),
  'fmidline': S(26,
      '<line x1="5" y1="21" x2="21" y2="5" stroke="$G" stroke-width="1.5"/>${gp(13, 13, 3.4)}'),
  'fsplinecv': S(26,
      '<path d="M4 20 C 8 6, 16 22, 22 7" stroke="$G" stroke-width="1.5"/><path d="M4 20L9 9L17 17L22 7" stroke="$DIM" stroke-width="1" stroke-dasharray="2 2"/>${gp(4, 20, 3)}${gp(9, 9, 3)}${gp(17, 17, 3)}${gp(22, 7, 3)}'),
  'fsplinei': S(26,
      '<path d="M4 19 C 8 8, 12 22, 16 12 S 22 6, 22 6" stroke="$G" stroke-width="1.5"/>${gp(4, 19, 3)}${gp(11, 14, 3)}${gp(17, 11, 3)}${gp(22, 6, 3)}'),
  'feqcurve': S(26,
      '<path d="M4 22h18M4 22V5" stroke="$DIM" stroke-width="1"/><path d="M5 20 C 10 20, 12 7, 21 7" stroke="$G" stroke-width="1.5"/><text x="10" y="12" font-size="8" font-style="italic" fill="$BL" font-family="Georgia" stroke="none">fx</text><path d="M4 5l-1.2 2M4 5l1.2 2" stroke="$DIM" stroke-width="1"/>'),
  'fbridge': S(26,
      '<path d="M3 20 C 9 20, 8 6, 14 6" stroke="$DIM" stroke-width="1.2"/><path d="M14 6 C 19 6, 18 20, 23 20" stroke="$G" stroke-width="1.5"/>${gp(14, 6, 3)}${gp(3, 20, 3)}${gp(23, 20, 3)}'),
  'fcirclecp': S(26,
      '<circle cx="13" cy="13" r="9" stroke="$G" stroke-width="1.5"/>${gpd(13, 13, 2)}'),
  'fcircletan': S(26,
      '<circle cx="13" cy="13" r="8" stroke="$G" stroke-width="1.5" stroke-dasharray="10 3"/><line x1="2" y1="21" x2="9" y2="20" stroke="$G" stroke-width="1.3"/><line x1="18" y1="20" x2="24" y2="18" stroke="$G" stroke-width="1.3"/>'),
  'fellipse': S(26,
      '<ellipse cx="13" cy="13" rx="10" ry="6.5" stroke="$G" stroke-width="1.5" stroke-dasharray="12 3"/>${gpd(13, 13, 2)}${gp(23, 13, 3)}'),
  'farc3': S(26,
      '<path d="M5 21 A 13 13 0 0 1 21 7" stroke="$G" stroke-width="1.5"/>${gp(5, 21, 3.2)}${gp(12, 12.5, 3.2)}${gp(21, 7, 3.2)}'),
  'farctan': S(26,
      '<line x1="3" y1="20" x2="12" y2="20" stroke="$G" stroke-width="1.4"/><path d="M12 20 A 8 8 0 0 0 20 12" stroke="$G" stroke-width="1.5"/>${gp(12, 20, 3.2)}${gp(20, 12, 3.2)}'),
  'farccp': S(26,
      '<path d="M5 21 A 13 13 0 0 1 21 7" stroke="$G" stroke-width="1.5"/><line x1="13" y1="14" x2="5" y2="21" stroke="$DIM" stroke-width="1" stroke-dasharray="2 2"/>${gpd(13, 14, 2)}${gp(5, 21, 3.2)}${gp(21, 7, 3.2)}'),
  'ffillet': S(26,
      '<path d="M4 22v-8 A 8 8 0 0 1 12 6h10" stroke="$G" stroke-width="1.5"/><path d="M4 22v-2M22 6h-2" stroke="$DIM" stroke-width="1.2"/>'),
  'fchamfer': S(26, '<path d="M4 22v-8l8-8h10" stroke="$G" stroke-width="1.5"/>'),
  'ftext': S(26,
      '<text x="13" y="19" font-size="19" font-weight="600" fill="$G" text-anchor="middle" font-family="Segoe UI" stroke="none">A</text>'),
  'fgtext': S(26,
      '<path d="M4 18 A 11 11 0 0 1 22 18" stroke="$DIM" stroke-width="1.1" stroke-dasharray="2 2"/><text x="13" y="15" font-size="13" font-weight="600" fill="$G" text-anchor="middle" font-family="Segoe UI" stroke="none">A</text>'),
  'frect2p': S(26,
      '<rect x="4" y="7" width="18" height="12" stroke="$G" stroke-width="1.5"/>${gp(4, 7, 3.2)}${gp(22, 19, 3.2)}'),
  'frect3p': S(26,
      '<path d="M13 3L23 13L13 23L3 13z" stroke="$G" stroke-width="1.5"/>${gp(13, 3, 3.2)}${gp(23, 13, 3.2)}${gp(13, 23, 3.2)}'),
  'frect2pc': S(26,
      '<rect x="4" y="7" width="18" height="12" stroke="$G" stroke-width="1.5"/>${gpd(13, 13, 2)}${gp(22, 19, 3.2)}'),
  'frect3pc': S(26,
      '<path d="M13 3L23 13L13 23L3 13z" stroke="$G" stroke-width="1.5"/>${gpd(13, 13, 2)}${gp(23, 13, 3.2)}'),
  'fslotcc': S(26,
      '<path d="M8 8h10a5 5 0 0 1 0 10H8a5 5 0 0 1 0-10z" stroke="$G" stroke-width="1.4"/>${gpd(8, 13, 1.8)}${gpd(18, 13, 1.8)}'),
  'fslotov': S(26,
      '<path d="M8 8h10a5 5 0 0 1 0 10H8a5 5 0 0 1 0-10z" stroke="$G" stroke-width="1.4"/>${gp(3, 13, 3)}${gp(23, 13, 3)}'),
  'fslotcp': S(26,
      '<path d="M8 8h10a5 5 0 0 1 0 10H8a5 5 0 0 1 0-10z" stroke="$G" stroke-width="1.4"/>${gpd(13, 13, 1.8)}${gpd(18, 13, 1.8)}'),
  'fslot3a': S(26,
      '<path d="M3.5 15.5 A11 11 0 0 1 22.5 15.5 A2.75 2.75 0 0 1 17.8 18.25 A5.5 5.5 0 0 0 8.2 18.25 A2.75 2.75 0 0 1 3.5 15.5z" stroke="$G" stroke-width="1.3"/>${gpd(5, 13, 1.8)}${gpd(13, 9, 1.8)}${gpd(21, 13, 1.8)}'),
  'fslotcpa': S(26,
      '<path d="M3.5 13.5 A11 11 0 0 1 22.5 13.5 A2.75 2.75 0 0 1 17.8 16.25 A5.5 5.5 0 0 0 8.2 16.25 A2.75 2.75 0 0 1 3.5 13.5z" stroke="$G" stroke-width="1.3"/>${gpd(13, 21, 1.8)}${gpd(5, 11, 1.8)}${gpd(21, 11, 1.8)}'),
  'fpolygon': S(26,
      '<path d="M13 3.5L22 10L18.5 21h-11L4 10z" stroke="$G" stroke-width="1.5"/>${gpd(13, 13, 2)}'),
  // project geometry — isometric layered planes, Inventor teal/blue
  'projgeo': S(34,
      '<path d="M6 14 L17 8 L28 14 L17 20 Z" fill="#2E8FD4" stroke="#1a5f95" stroke-width=".8"/><path d="M6 14 L17 20 L17 26 L6 20 Z" fill="#1F6FAE" stroke="#154d7a" stroke-width=".8"/><path d="M28 14 L17 20 L17 26 L28 20 Z" fill="#54B0E8" stroke="#1a5f95" stroke-width=".8"/>'),
  // pattern — blue like screenshot
  'patrect': S(18,
      '<rect x="2" y="2" width="5" height="5" fill="$BL"/><rect x="2" y="10.5" width="5" height="5" fill="$BL"/><rect x="10.5" y="2" width="5" height="5" fill="$BL"/><rect x="10.5" y="10.5" width="5" height="5" fill="$BL"/>'),
  'patcirc': S(18,
      '${gpd(9, 3, 1.9)}${gpd(14.2, 6, 1.9)}${gpd(14.2, 12, 1.9)}${gpd(9, 15, 1.9)}${gpd(3.8, 12, 1.9)}${gpd(3.8, 6, 1.9)}'),
  'patmir': S(18,
      '<path d="M9 2v14" stroke="$G" stroke-width="1" stroke-dasharray="2 2"/><path d="M7 4.5v9L2 11z" fill="$BL"/><path d="M11 4.5v9l5-2.5z" fill="none" stroke="$BL" stroke-width="1.2"/>'),
};

// ==== Constrain panel ====
final Map<String, String> CN = {
  'dim': S(34,
      '<line x1="4" y1="17" x2="30" y2="17" stroke="$G" stroke-width="1.5"/><line x1="4" y1="10" x2="4" y2="24" stroke="$G" stroke-width="1.5"/><line x1="30" y1="10" x2="30" y2="24" stroke="$G" stroke-width="1.5"/><path d="M4 17l4.5-2.4M4 17l4.5 2.4M30 17l-4.5-2.4M30 17l-4.5 2.4" stroke="$G" stroke-width="1.4"/>'),
  'autodim': S(18,
      '<line x1="3" y1="4" x2="3" y2="12" stroke="$GC" stroke-width="1.2"/><line x1="3" y1="8" x2="9" y2="8" stroke="$GC" stroke-width="1.2"/><path d="M3 8l2.4-1.4M3 8l2.4 1.4" stroke="$GC" stroke-width="1"/>${bolt(9.5, 3.5, 1.15)}'),
  // two point-markers merging into one shared point (Inventor's coincident
  // reads as "these two points become the same point")
  'coincident': S(18,
      '<circle cx="5.6" cy="11" r="2.9" stroke="$RD" stroke-width="1.5" fill="none"/><circle cx="10.1" cy="11" r="2.9" stroke="$RD" stroke-width="1.5" fill="none"/><circle cx="7.85" cy="11" r="1.5" fill="$RD"/>${cursorArrow(11.5, 3.5)}'),
  'collinear': S(18,
      '<line x1="2" y1="12.5" x2="8" y2="9.5" stroke="$RD" stroke-width="1.7"/><line x1="9.5" y1="7.5" x2="15.5" y2="4.5" stroke="$RD" stroke-width="1.7"/>${cursorArrow(4, 3)}'),
  'concentric': S(18,
      '<circle cx="9" cy="9" r="6.5" stroke="$RD" stroke-width="1.5"/><circle cx="9" cy="9" r="2.8" stroke="$RD" stroke-width="1.5"/>'),
  'lock': S(18,
      '<rect x="4" y="8" width="10" height="7.5" rx="1" fill="$RD" stroke="$RDD" stroke-width=".8"/><path d="M6 8V6a3 3 0 0 1 6 0v2" stroke="$RD" stroke-width="1.7" fill="none"/><circle cx="9" cy="11.5" r="1.1" fill="#5c1e1c"/>'),
  'showcons': S(18,
      '<path d="M7 3H3.5v12H7" stroke="$GC" stroke-width="1.3" fill="none"/>${bolt(9.5, 4, 1.2)}'),
  'parallel': S(18,
      '<line x1="3.5" y1="13.5" x2="8" y2="3.5" stroke="$RD" stroke-width="1.7"/><line x1="8" y1="15" x2="12.5" y2="5" stroke="$RD" stroke-width="1.7"/>${check(12, 10.5)}'),
  'perp': S(18,
      '<path d="M3 4l7 5.5L3.5 15" stroke="$RD" stroke-width="1.7" fill="none"/>${check(11.5, 8)}'),
  'horiz': S(18,
      '<line x1="2.5" y1="7.5" x2="15.5" y2="7.5" stroke="$RD" stroke-width="1.8"/><path d="M5 12.5l2-2.6M8 12.5l2-2.6M11 12.5l2-2.6" stroke="$GC" stroke-width="1.1"/>'),
  'vert': S(18,
      '<line x1="10.5" y1="2.5" x2="10.5" y2="15.5" stroke="$RD" stroke-width="1.8"/><path d="M5.5 5l2.6 2M5.5 8l2.6 2M5.5 11l2.6 2" stroke="$GC" stroke-width="1.1"/>'),
  'conset': S(18,
      '<path d="M7 3H3.5v12H7" stroke="$GC" stroke-width="1.3" fill="none"/>${check(9, 9)}'),
  'tangent': S(18,
      '<circle cx="7.5" cy="10.5" r="4.8" stroke="$RD" stroke-width="1.5"/><line x1="2" y1="4.5" x2="16" y2="7.5" stroke="$RD" stroke-width="1.5"/>${check(12, 12)}'),
  'smooth': S(18,
      '<path d="M2 13 C 5.5 13, 6 5.5, 9.5 5.5" stroke="$RD" stroke-width="1.6" fill="none"/><line x1="9.5" y1="5.5" x2="16" y2="5.5" stroke="$RD" stroke-width="1.6"/>${check(10.5, 11)}'),
  'symmetric': S(18,
      '<path d="M9 2.5v13" stroke="$GC" stroke-width="1" stroke-dasharray="2 2"/><path d="M6 4.5H3.5v9H6" stroke="$RD" stroke-width="1.6" fill="none"/><path d="M12 4.5h2.5v9H12" stroke="$RD" stroke-width="1.6" fill="none"/>'),
  'equal': S(18,
      '<line x1="4" y1="6.5" x2="14" y2="6.5" stroke="$RD" stroke-width="2"/><line x1="4" y1="11.5" x2="14" y2="11.5" stroke="$RD" stroke-width="2"/>'),
};

// ==== Insert & Format panels ====
final Map<String, String> IN = {
  'image': S(18,
      '<rect x="2" y="3" width="14" height="12" rx="1" fill="#2E6FA8" stroke="#1a4a75" stroke-width=".8"/><circle cx="6" cy="7" r="1.5" fill="#E8C63F"/><path d="M3 13.5l4.5-5 3 3.5 2-2 2.5 3.5z" fill="#7FBF6A"/>'),
  'points': S(18,
      '<rect x="2" y="3" width="14" height="12" fill="none" stroke="$GC" stroke-width="1.1"/><path d="M2 7h14M8 3v12" stroke="$GC" stroke-width="1"/><circle cx="5" cy="11" r="1.5" fill="#3D9BE9"/><circle cx="12" cy="5" r="1.5" fill="#3D9BE9"/><circle cx="12" cy="11" r="1.5" fill="#3D9BE9"/>'),
  'acad': S(18,
      '<rect x="2.5" y="2.5" width="13" height="13" rx="1" fill="#B03A3A" stroke="#7d2727" stroke-width=".8"/><text x="9" y="13" font-size="10.5" font-weight="700" fill="#fff" text-anchor="middle" font-family="Segoe UI" stroke="none">A</text>'),
  'driven': S(18,
      '<line x1="2" y1="9" x2="5" y2="9" stroke="$GC" stroke-width="1.2"/><line x1="13" y1="9" x2="16" y2="9" stroke="$GC" stroke-width="1.2"/><line x1="2" y1="5.5" x2="2" y2="12.5" stroke="$GC" stroke-width="1.2"/><line x1="16" y1="5.5" x2="16" y2="12.5" stroke="$GC" stroke-width="1.2"/><path d="M7 5.5 C 5.8 7, 5.8 11, 7 12.5" stroke="$GC" stroke-width="1.1" fill="none"/><path d="M11 5.5 C 12.2 7, 12.2 11, 11 12.5" stroke="$GC" stroke-width="1.1" fill="none"/><circle cx="9" cy="9" r="1.1" fill="$GC"/>'),
  'sphere': S(18,
      '<circle cx="9" cy="9" r="6.5" stroke="$GC" stroke-width="1.2"/><ellipse cx="9" cy="9" rx="6.5" ry="2.6" stroke="$GC" stroke-width="1" fill="none"/><ellipse cx="9" cy="9" rx="2.6" ry="6.5" stroke="$GC" stroke-width="1" fill="none"/>'),
  'center': S(18,
      '<line x1="9" y1="2.5" x2="9" y2="15.5" stroke="#3D9BE9" stroke-width="1.4"/><line x1="2.5" y1="9" x2="15.5" y2="9" stroke="#3D9BE9" stroke-width="1.4"/><path d="M9 2.5l-1.5 1.8M9 2.5l1.5 1.8M9 15.5l-1.5-1.8M9 15.5l1.5-1.8M2.5 9l1.8-1.5M2.5 9l1.8 1.5M15.5 9l-1.8-1.5M15.5 9l-1.8 1.5" stroke="#3D9BE9" stroke-width="1.1"/>'),
  'showfmt': S(18,
      '<rect x="2.5" y="3" width="13" height="12" fill="none" stroke="$GC" stroke-width="1.1"/><path d="M2.5 6.5h13M6.5 6.5V15" stroke="$GC" stroke-width="1"/><rect x="8" y="8.5" width="5.5" height="1.6" fill="#3D9BE9"/><rect x="8" y="11.5" width="4" height="1.6" fill="#3D9BE9"/>'),
};

// ==== Modify panel ====
final Map<String, String> MD = {
  'move': S(18,
      '<path d="M9 2v14M2 9h14" stroke="$BLM" stroke-width="1.4"/><path d="M9 2L7.4 3.9M9 2l1.6 1.9M9 16l-1.6-1.9M9 16l1.6-1.9M2 9l1.9-1.6M2 9l1.9 1.6M16 9l-1.9-1.6M16 9l-1.9 1.6" stroke="$BLM" stroke-width="1.2"/>'),
  'copy': S(18,
      '<rect x="6.5" y="6.5" width="9" height="9" stroke="$BLM" stroke-width="1.3"/><path d="M2.5 11.5v-9h9" stroke="$GC" stroke-width="1.2"/><circle cx="4.8" cy="15" r="1.5" stroke="$BLM" stroke-width="1.1"/><circle cx="1.9" cy="12.4" r="1.3" stroke="$BLM" stroke-width="1"/>'),
  'mrotate': S(18,
      '<path d="M15 9a6 6 0 1 1-2.1-4.6" stroke="$BLM" stroke-width="1.5"/><path d="M15.3 2.4v3.6h-3.6" stroke="$BLM" stroke-width="1.4"/>'),
  'trim': S(18,
      '<path d="M2.5 15L14 3.5" stroke="$GC" stroke-width="1.2"/><circle cx="4.6" cy="4" r="1.7" stroke="$BLM" stroke-width="1.1"/><circle cx="9" cy="4" r="1.7" stroke="$BLM" stroke-width="1.1"/><path d="M5.8 5.3l4.5 5.5M8 5.3L6.6 7" stroke="$BLM" stroke-width="1.1"/>'),
  'extend': S(18,
      '<line x1="2" y1="12.5" x2="7.5" y2="12.5" stroke="$GC" stroke-width="1.4"/><path d="M8.5 12.5h4.5" stroke="$BLM" stroke-width="1.4" stroke-dasharray="2.2 1.6"/><path d="M13.5 12.5l-2-1.6M13.5 12.5l-2 1.6" stroke="$BLM" stroke-width="1.2"/><line x1="15" y1="4" x2="15" y2="15.5" stroke="$GC" stroke-width="1.3"/>'),
  'split': S(18,
      '<line x1="2" y1="9" x2="6.8" y2="9" stroke="$GC" stroke-width="1.4"/><line x1="11.2" y1="9" x2="16" y2="9" stroke="$GC" stroke-width="1.4"/><line x1="9" y1="4.5" x2="9" y2="13.5" stroke="$BLM" stroke-width="1.5"/>'),
  'mscale': S(18,
      '<rect x="2.5" y="9" width="6" height="6" stroke="$GC" stroke-width="1.2"/><rect x="6" y="2.5" width="9.5" height="9.5" stroke="$BLM" stroke-width="1.3"/><path d="M8.5 9l4-4M12.5 5l-2.8.3M12.5 5l-.3 2.8" stroke="$BLM" stroke-width="1.1"/>'),
  'stretch': S(18,
      '<path d="M2.5 4.5h7v9h-7z" stroke="$GC" stroke-width="1.2"/><path d="M9.5 4.5h3.5M9.5 13.5h3.5" stroke="$BLM" stroke-width="1.2" stroke-dasharray="2 1.5"/><path d="M15.5 9h-4M15.5 9l-1.8-1.5M15.5 9l-1.8 1.5" stroke="$BLM" stroke-width="1.3"/>'),
  'moffset': S(18,
      '<path d="M14 3.5 A 8.5 8.5 0 0 0 14 14.5" stroke="$BLM" stroke-width="1.5"/><path d="M13 6 A 5 5 0 0 0 13 12" stroke="$BLM" stroke-width="1.3"/>'),
};

// ==== Layer / Sketch / Finish / misc ====
final layerBigIcon = S(34, '''
 <path d="M4 4h4M4 4v4M20 4h-4M20 4v4M4 22v-4M4 22h4" stroke="$GC" stroke-width="1.2"/>
 <path d="M6 14 L12 10.5 L18 14 L12 17.5 Z" fill="none" stroke="#C4C9CE" stroke-width="1.3"/>
 <path d="M6 10.5 L12 7 L18 10.5 L12 14 Z" fill="#2E8FD4" stroke="#1a5f95" stroke-width=".9"/>
 <path d="M27 20v9M22.5 24.5h9" stroke="#5CBF4A" stroke-width="3" stroke-linecap="round"/>''');

final finishIcon =
    S(34, '<path d="M5 18 L13 27 L29 8" stroke="#3FA43C" stroke-width="6" fill="none"/>');

final newSketchIcon = S(34,
    '<rect x="4" y="6" width="20" height="16" fill="none" stroke="$G" stroke-width="1.5"/>${gp(4, 6, 4)}${gp(24, 6, 4)}${gp(4, 22, 4)}${gp(24, 22, 4)}<path d="M27 20v9M22.5 24.5h9" stroke="#5CBF4A" stroke-width="3" stroke-linecap="round"/>');

// model-browser tree icons (15px rows, 16 viewBox)
const layerRowIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M2.5 9 L8 5.8 L13.5 9 L8 12.2 Z" fill="none" stroke="#C4C9CE" stroke-width="1.1"/><path d="M2.5 6.5 L8 3.3 L13.5 6.5 L8 9.7 Z" fill="#2E8FD4" stroke="#1a5f95" stroke-width=".8"/></svg>';
const sketchCubeIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M8 1.5L14 5v6L8 14.5L2 11V5z" fill="#3D9BE9" stroke="#1d5c8a" stroke-width=".8"/><path d="M2 5l6 3.5L14 5M8 8.5v6" stroke="#1d5c8a" stroke-width=".8" fill="none"/></svg>';
const originIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M3 13V3.5" stroke="#3D9BE9" stroke-width="1.4"/><path d="M3 13h10" stroke="#D65A56" stroke-width="1.4"/><path d="M3 13l5-4.5 5 1.5-5 4.5z" fill="#E8C63F" fill-opacity=".55" stroke="#a68b1f" stroke-width=".7"/></svg>';
const xAxisIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><line x1="1.5" y1="8" x2="14.5" y2="8" stroke="#D65A56" stroke-width="1.5"/><path d="M14.5 8l-2-1.4M14.5 8l-2 1.4" stroke="#D65A56" stroke-width="1.1" fill="none"/></svg>';
const yAxisIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><line x1="8" y1="14.5" x2="8" y2="1.5" stroke="#3D9BE9" stroke-width="1.5"/><path d="M8 1.5l-1.4 2M8 1.5l1.4 2" stroke="#3D9BE9" stroke-width="1.1" fill="none"/></svg>';
const centerPointIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><line x1="8" y1="2.5" x2="8" y2="13.5" stroke="#9aa0a6" stroke-width="1"/><line x1="2.5" y1="8" x2="13.5" y2="8" stroke="#9aa0a6" stroke-width="1"/><rect x="6.4" y="6.4" width="3.2" height="3.2" fill="#3D9BE9"/></svg>';
const endOfSketchIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.5" fill="#C0392B" stroke="#7d1f14" stroke-width=".8"/><path d="M5.5 5.5l5 5M10.5 5.5l-5 5" stroke="#fff" stroke-width="1.5"/></svg>';
const homeTabIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="none"><path d="M2 8.5L8 3l6 5.5" stroke="#aeb3b9" stroke-width="1.4"/><path d="M4 8v5h8V8" stroke="#aeb3b9" stroke-width="1.4"/></svg>';

// ==== Pattern dialog (M35) — dialog-internal glyphs, same icon language ====
final Map<String, String> PD = {
  // selector cursor (the pick buttons, blue-underlined like Inventor)
  'sel': S(18, '${cursorArrow(4, 3.5)}<path d="M3 14.5h12" stroke="$BL" stroke-width="1.6"/>'),
  'selAxis': S(18, '${cursorArrow(4, 3.5)}<line x1="9" y1="3" x2="9" y2="15" stroke="$G" stroke-width="1" stroke-dasharray="2.4 1.8"/>'),
  // flip direction — Inventor's red/black double arrow
  'flip': S(18,
      '<path d="M6.5 14V5" stroke="$RD" stroke-width="1.6"/><path d="M6.5 4l-2.2 3.1M6.5 4l2.2 3.1" stroke="$RD" stroke-width="1.4"/><path d="M11.5 4v9" stroke="$G" stroke-width="1.6"/><path d="M11.5 15l-2.2-3.1M11.5 15l2.2-3.1" stroke="$G" stroke-width="1.4"/>'),
  // count of instances — Direction 1 (dots in a row) / Direction 2 (column)
  'countH': S(18, '${gpd(3.5, 9, 1.7)}${gpd(9, 9, 1.7)}${gpd(14.5, 9, 1.7)}'),
  'countV': S(18, '${gpd(9, 3.5, 1.7)}${gpd(9, 9, 1.7)}${gpd(9, 14.5, 1.7)}'),
  'countC': S(18, '${gpd(9, 3.2, 1.6)}${gpd(13.8, 6.2, 1.6)}${gpd(13.8, 11.8, 1.6)}${gpd(9, 14.8, 1.6)}${gpd(4.2, 11.8, 1.6)}'),
  // spacing / distance — Inventor's yellow diamond
  'spacing': S(18,
      '<path d="M9 2.5L15.5 9L9 15.5L2.5 9z" fill="$YL" stroke="#9a8320" stroke-width=".8"/>'),
  // angle — swept arc with arrows
  'angle': S(18,
      '<path d="M3.5 13 A7 7 0 0 1 14.5 13" fill="none" stroke="$G" stroke-width="1.4"/><path d="M3.5 13l1-2.2M3.5 13l2.3-.5M14.5 13l-1-2.2M14.5 13l-2.3-.5" stroke="$G" stroke-width="1.1"/><path d="M9 6v-2" stroke="$YL" stroke-width="1.6"/>'),
  // mirror line pick
  'mirLine': S(18,
      '<line x1="9" y1="2.5" x2="9" y2="15.5" stroke="$G" stroke-width="1.1" stroke-dasharray="2.6 2"/>${cursorArrow(10.5, 8)}'),
  // chamfer mode toggles (M36) — Inventor's three little mode buttons
  'chamEq': S(18,
      '<path d="M3 15V6l9 9z" fill="none" stroke="$G" stroke-width="1.3"/><path d="M3 6l9 9" stroke="$BL" stroke-width="1.5"/><path d="M3 10.5h2M7.5 15v-2" stroke="$YL" stroke-width="1.4"/>'),
  'cham2d': S(18,
      '<path d="M3 15V4l11 11z" fill="none" stroke="$G" stroke-width="1.3"/><path d="M3 4l11 11" stroke="$BL" stroke-width="1.5"/><path d="M3 8h2M9 15v-2M3 4h1.5M14 15h-1.5" stroke="$YL" stroke-width="1.4"/>'),
  'chamAng': S(18,
      '<path d="M3 15V5l10 10z" fill="none" stroke="$G" stroke-width="1.3"/><path d="M3 5l10 10" stroke="$BL" stroke-width="1.5"/><path d="M3 9 A5 5 0 0 1 6.5 11.5" fill="none" stroke="$YL" stroke-width="1.2"/>'),
};

