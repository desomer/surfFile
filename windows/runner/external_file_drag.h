#ifndef RUNNER_EXTERNAL_FILE_DRAG_H_
#define RUNNER_EXTERNAL_FILE_DRAG_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

void StartWindowsFileDrag(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

#endif  // RUNNER_EXTERNAL_FILE_DRAG_H_
