#ifndef REMYA_CAPTURE_WINDOWS_H_
#define REMYA_CAPTURE_WINDOWS_H_

#include <gtk/gtk.h>

inline constexpr char kResidentCaptureId[] = APPLICATION_ID ".Resident";

bool forward_resident_capture(const char* mode);
void start_capture_windows(GtkApplication* application, char** arguments);
void stop_capture_windows(GtkApplication* application);

#endif
