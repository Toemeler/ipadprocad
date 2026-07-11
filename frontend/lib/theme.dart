// iPadProCAD — design tokens, 1:1 from create-panel.html (FINAL mock).
import 'package:flutter/material.dart';

class T {
  // :root palette
  static const bg = Color(0xFF2A2E33);
  static const panel = Color(0xFF292D33);
  static const fly = Color(0xFF212429);
  static const flyHov = Color(0xFF31363D);
  static const text = Color(0xFFDDE0E3);
  static const dim = Color(0xFF9EA4AA);
  static const sep = Color(0xFF131518);
  static const blue = Color(0xFF3D9BE9);

  static const viewport = Color(0xFF212830);
  static const ribbonTop = Color(0xD92F7BD6); // rgba(47,123,214,.85)
  static const ribbonBottom = Color(0x732F7BD6); // rgba(47,123,214,.45)
  static const panelSep = Color(0xFF3A3F45);

  // model browser
  static const mbBg = Color(0xFF262A2F);
  static const mbHead = Color(0xFF2E3237);
  static const mbBorder = Color(0xFF16181B);
  static const mbHeadBorder = Color(0xFF1A1D20);
  static const mbText = Color(0xFFD5D8DB);
  static const mbDim = Color(0xFF9AA0A6);
  static const mbDimmed = Color(0xFF8B9197);
  static const mbActiveBg = Color(0xFF3A4149);
  static const mbActiveOutline = Color(0xFF5A88B5);
  static const mbHover = Color(0x14A0C8FF); // rgba(160,200,255,.08)

  // tab bar
  static const tabbarBg = Color(0xFF14171B);
  static const tabbarBorder = Color(0xFF0D0F12);
  static const tabBg = Color(0xFF1E2227);
  static const tabOnBg = Color(0xFF262B31);
  static const tabText = Color(0xFFAEB3B9);
  static const tabUnderline = Color(0xFF2F7BD6);

  // home
  static const cardBg = Color(0xFF24282D);
  static const cardBorder = Color(0xFF1A1D20);
  static const cardHoverBorder = Color(0xFF2F7BD6);
  static const homeH1 = Color(0xFFE8EAEC);
  static const cardName = Color(0xFFE2E5E8);
  static const cardDate = Color(0xFF8B9197);

  // edit-mode sketch overlay
  static const rawGrey = Color(0xFF6B7178);
  static const projYellow = Color(0xFFE8C63F);
  static const projYellowEdge = Color(0xFF9A8320);
  static const finishGreen = Color(0xFF3FA43C);

  static const hover6 = Color(0x0FFFFFFF); // rgba(255,255,255,.06)
  static const hover7 = Color(0x12FFFFFF); // .07
  static const hover8 = Color(0x14FFFFFF); // .08
  static const border10 = Color(0x1AFFFFFF); // .10
  static const conActiveBg = Color(0x2E3D9BE9); // rgba(61,155,233,.18)
  static const conActiveBorder = Color(0x8C3D9BE9); // .55

  static const fontFamily = '.SF UI Text'; // system-ui on iOS (mock fallback)
}

TextStyle ts(double size, Color color,
        {FontWeight w = FontWeight.normal, double height = 1.1}) =>
    TextStyle(fontSize: size, color: color, fontWeight: w, height: height);
