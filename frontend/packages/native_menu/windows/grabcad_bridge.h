#ifndef PROTOTYPE_GRABCAD_BRIDGE_H_
#define PROTOTYPE_GRABCAD_BRIDGE_H_

#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_result.h>
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <memory>
#include <windows.h>

// Persistent WebView2 session. Cookies/account payloads never leave WebView2.
class WindowsGrabCad {
public:
  explicit WindowsGrabCad(HWND owner);
  ~WindowsGrabCad();
  bool Handle(
      const flutter::MethodCall<flutter::EncodableValue> &call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> &result);

private:
  struct Impl;
  std::shared_ptr<Impl> impl_;
};
#endif
