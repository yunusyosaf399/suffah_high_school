#include "flutter_window.h"

#include <optional>
#include <mmsystem.h>
#include <flutter/standard_method_codec.h>
#include <string>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  call_audio_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "suffah/call_audio",
      &flutter::StandardMethodCodec::GetInstance());
  call_audio_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "stopRing") {
          StopCallRing();
          result->Success();
          return;
        }
        if (call.method_name() == "repeatRing") {
          if (mci_ringtone_open_) {
            wchar_t mode[32] = {};
            if (mciSendStringW(L"status suffah_ring mode", mode, 32, nullptr) == 0 &&
                std::wstring(mode) == L"stopped") {
              mciSendStringW(L"play suffah_ring from 0", nullptr, 0, nullptr);
            }
          }
          result->Success();
          return;
        }
        if (call.method_name() != "ringFile") {
          result->NotImplemented();
          return;
        }
        StopCallRing();
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) { result->Success(flutter::EncodableValue(false)); return; }
        const auto it = args->find(flutter::EncodableValue("path"));
        const auto* path = it == args->end() ? nullptr : std::get_if<std::string>(&it->second);
        if (!path || path->empty() || path->size() > 4096) {
          result->Success(flutter::EncodableValue(false)); return;
        }
        const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->data(),
            static_cast<int>(path->size()), nullptr, 0);
        if (count <= 0) { result->Success(flutter::EncodableValue(false)); return; }
        std::wstring file(count, L'\0');
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->data(),
            static_cast<int>(path->size()), file.data(), count);
        if (file.find(L'"') != std::wstring::npos || file.find(L'\0') != std::wstring::npos) {
          result->Success(flutter::EncodableValue(false)); return;
        }
        if (file.size() >= 4 && _wcsicmp(file.c_str() + file.size() - 4, L".wav") == 0) {
          result->Success(flutter::EncodableValue(
            PlaySoundW(file.c_str(), nullptr, SND_FILENAME | SND_ASYNC | SND_LOOP | SND_NODEFAULT) != FALSE));
          return;
        }
        // Windows codecs determine which compressed ringtone formats work.
        const auto command = L"open \"" + file + L"\" alias suffah_ring";
        if (mciSendStringW(command.c_str(), nullptr, 0, nullptr) == 0) {
          mci_ringtone_open_ = true;
          if (mciSendStringW(L"play suffah_ring from 0", nullptr, 0, nullptr) == 0) {
            result->Success(flutter::EncodableValue(true)); return;
          }
          StopCallRing();
        }
        result->Success(flutter::EncodableValue(false));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::StopCallRing() {
  PlaySoundW(nullptr, nullptr, 0);
  if (mci_ringtone_open_) {
    mciSendStringW(L"stop suffah_ring", nullptr, 0, nullptr);
    mciSendStringW(L"close suffah_ring", nullptr, 0, nullptr);
    mci_ringtone_open_ = false;
  }
}

void FlutterWindow::OnDestroy() {
  StopCallRing();
  call_audio_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
