#ifndef SUPER_CONTAINER_LAYOUT_WINDOW_TRANSPARENCY_H_
#define SUPER_CONTAINER_LAYOUT_WINDOW_TRANSPARENCY_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

void RegisterWindowTransparency(flutter::BinaryMessenger* messenger,
                                HWND window);

#endif  // SUPER_CONTAINER_LAYOUT_WINDOW_TRANSPARENCY_H_
