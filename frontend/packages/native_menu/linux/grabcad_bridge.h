#ifndef PROTOTYPE_LINUX_GRABCAD_H_
#define PROTOTYPE_LINUX_GRABCAD_H_
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <memory>
class LinuxGrabCad {
public:
  LinuxGrabCad();
  ~LinuxGrabCad();
  bool Handle(GtkWindow *owner, FlMethodCall *call);

private:
  struct Impl;
  std::shared_ptr<Impl> impl_;
};
#endif
