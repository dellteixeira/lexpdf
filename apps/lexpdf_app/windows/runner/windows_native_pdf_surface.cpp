#include "windows_native_pdf_surface.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <wincodec.h>
#include <wrl/client.h>

#include <winrt/Windows.Data.Pdf.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

using Microsoft::WRL::ComPtr;
using winrt::Windows::Data::Pdf::PdfDocument;
using winrt::Windows::Data::Pdf::PdfPageRenderOptions;
using winrt::Windows::Storage::StorageFile;
using winrt::Windows::Storage::Streams::DataReader;
using winrt::Windows::Storage::Streams::InMemoryRandomAccessStream;

constexpr wchar_t kSurfaceWindowClass[] = L"LexPdfWindowsNativePdfSurface";
constexpr UINT kFrameReadyMessage = WM_APP + 0x415;
constexpr int kMaxNativeDimension = 16384;

struct DecodedFrame {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> bgra;
};

std::wstring ErrorToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return L"Native PDF error";
  std::wstring output(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      output.data(), size);
  return output;
}

bool DecodeWithWic(const std::vector<uint8_t>& encoded, DecodedFrame* frame,
                   std::string* error) {
  if (encoded.empty()) {
    *error = "Windows.Data.Pdf returned an empty encoded frame";
    return false;
  }

  ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
  if (FAILED(hr)) {
    *error = "WIC factory initialization failed";
    return false;
  }

  ComPtr<IWICStream> stream;
  hr = factory->CreateStream(&stream);
  if (FAILED(hr)) {
    *error = "WIC stream creation failed";
    return false;
  }

  hr = stream->InitializeFromMemory(
      const_cast<BYTE*>(reinterpret_cast<const BYTE*>(encoded.data())),
      static_cast<DWORD>(encoded.size()));
  if (FAILED(hr)) {
    *error = "WIC stream initialization failed";
    return false;
  }

  ComPtr<IWICBitmapDecoder> decoder;
  hr = factory->CreateDecoderFromStream(stream.Get(), nullptr,
                                        WICDecodeMetadataCacheOnLoad, &decoder);
  if (FAILED(hr)) {
    *error = "WIC could not decode the Windows PDF frame";
    return false;
  }

  ComPtr<IWICBitmapFrameDecode> source;
  hr = decoder->GetFrame(0, &source);
  if (FAILED(hr)) {
    *error = "WIC could not read the Windows PDF frame";
    return false;
  }

  UINT width = 0;
  UINT height = 0;
  hr = source->GetSize(&width, &height);
  if (FAILED(hr) || width == 0 || height == 0 ||
      width > kMaxNativeDimension || height > kMaxNativeDimension) {
    *error = "Windows PDF frame dimensions are invalid";
    return false;
  }

  ComPtr<IWICFormatConverter> converter;
  hr = factory->CreateFormatConverter(&converter);
  if (FAILED(hr)) {
    *error = "WIC format converter creation failed";
    return false;
  }

  hr = converter->Initialize(source.Get(), GUID_WICPixelFormat32bppBGRA,
                             WICBitmapDitherTypeNone, nullptr, 0.0,
                             WICBitmapPaletteTypeCustom);
  if (FAILED(hr)) {
    *error = "WIC BGRA conversion failed";
    return false;
  }

  const UINT stride = width * 4;
  const UINT byte_count = stride * height;
  frame->bgra.resize(byte_count);
  hr = converter->CopyPixels(nullptr, stride, byte_count, frame->bgra.data());
  if (FAILED(hr)) {
    frame->bgra.clear();
    *error = "WIC pixel copy failed";
    return false;
  }

  frame->width = static_cast<int>(width);
  frame->height = static_cast<int>(height);
  return true;
}

bool RenderWithWindowsPdf(const std::string& path, int page_number, int width,
                          int height, DecodedFrame* frame,
                          std::string* error) {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);

    const auto file = StorageFile::GetFileFromPathAsync(winrt::to_hstring(path)).get();
    const auto document = PdfDocument::LoadFromFileAsync(file).get();
    if (page_number <= 0 ||
        static_cast<uint32_t>(page_number) > document.PageCount()) {
      *error = "Requested page is outside Windows.Data.Pdf document range";
      return false;
    }

    const auto page = document.GetPage(static_cast<uint32_t>(page_number - 1));
    PdfPageRenderOptions options;
    options.DestinationWidth(static_cast<uint32_t>(width));
    options.DestinationHeight(static_cast<uint32_t>(height));

    InMemoryRandomAccessStream output;
    page.RenderToStreamAsync(output, options).get();
    output.Seek(0);

    const uint64_t stream_size_64 = output.Size();
    if (stream_size_64 == 0 || stream_size_64 > 512ull * 1024ull * 1024ull) {
      *error = "Windows.Data.Pdf produced an invalid stream size";
      return false;
    }

    const auto stream_size = static_cast<uint32_t>(stream_size_64);
    DataReader reader(output.GetInputStreamAt(0));
    reader.LoadAsync(stream_size).get();
    std::vector<uint8_t> encoded(stream_size);
    reader.ReadBytes(winrt::array_view<uint8_t>(encoded));
    reader.Close();
    page.Close();

    return DecodeWithWic(encoded, frame, error);
  } catch (const winrt::hresult_error& exception) {
    *error = winrt::to_string(exception.message());
    return false;
  } catch (const std::exception& exception) {
    *error = exception.what();
    return false;
  } catch (...) {
    *error = "Unknown Windows.Data.Pdf rendering failure";
    return false;
  }
}

class NativePdfSurface : public std::enable_shared_from_this<NativePdfSurface> {
 public:
  NativePdfSurface(HWND parent, int64_t key) : parent_(parent), key_(key) {}
  ~NativePdfSurface() { Destroy(); }

  bool EnsureWindow(std::string* error) {
    if (window_ != nullptr) return true;

    WNDCLASSEXW window_class = {};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &NativePdfSurface::WindowProc;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kSurfaceWindowClass;
    if (RegisterClassExW(&window_class) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      *error = "Could not register native PDF child-window class";
      return false;
    }

    window_ = CreateWindowExW(
        WS_EX_NOACTIVATE, kSurfaceWindowClass, L"", WS_CHILD | WS_CLIPSIBLINGS,
        0, 0, 1, 1, parent_, nullptr, GetModuleHandleW(nullptr), this);
    if (window_ == nullptr) {
      *error = "Could not create native PDF child window";
      return false;
    }
    return true;
  }

  void Show(int x, int y, int width, int height, const std::string& path,
            int page_number) {
    if (window_ == nullptr) return;
    width = std::clamp(width, 1, kMaxNativeDimension);
    height = std::clamp(height, 1, kMaxNativeDimension);

    SetWindowPos(window_, HWND_TOP, x, y, width, height,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);

    const int64_t generation = ++generation_;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      loading_ = true;
      error_.clear();
    }
    InvalidateRect(window_, nullptr, FALSE);

    std::weak_ptr<NativePdfSurface> weak_self = shared_from_this();
    std::thread([weak_self, generation, path, page_number, width, height]() {
      DecodedFrame frame;
      std::string error;
      const bool ok = RenderWithWindowsPdf(path, page_number, width, height,
                                           &frame, &error);
      const auto self = weak_self.lock();
      if (!self || generation != self->generation_.load()) return;
      {
        std::lock_guard<std::mutex> lock(self->mutex_);
        self->loading_ = false;
        if (ok) {
          self->frame_ = std::move(frame);
          self->error_.clear();
        } else {
          self->frame_ = DecodedFrame{};
          self->error_ = std::move(error);
        }
      }
      if (self->window_ != nullptr) {
        PostMessageW(self->window_, kFrameReadyMessage, 0, 0);
      }
    }).detach();
  }

  void Hide() {
    ++generation_;
    if (window_ != nullptr) ShowWindow(window_, SW_HIDE);
  }

  void Destroy() {
    ++generation_;
    if (window_ != nullptr) {
      DestroyWindow(window_);
      window_ = nullptr;
    }
  }

 private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
    NativePdfSurface* self = reinterpret_cast<NativePdfSurface*>(
        GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
      self = static_cast<NativePdfSurface*>(create->lpCreateParams);
      SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(self));
    }

    if (self != nullptr) {
      switch (message) {
        case WM_NCHITTEST:
          return HTTRANSPARENT;
        case WM_ERASEBKGND:
          return 1;
        case kFrameReadyMessage:
          InvalidateRect(hwnd, nullptr, FALSE);
          return 0;
        case WM_PAINT:
          self->Paint();
          return 0;
        default:
          break;
      }
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }

  void Paint() {
    PAINTSTRUCT paint = {};
    HDC dc = BeginPaint(window_, &paint);
    RECT client = {};
    GetClientRect(window_, &client);

    FillRect(dc, &client, reinterpret_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));

    DecodedFrame frame;
    bool loading = false;
    std::string error;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      frame = frame_;
      loading = loading_;
      error = error_;
    }

    if (!frame.bgra.empty() && frame.width > 0 && frame.height > 0) {
      BITMAPINFO info = {};
      info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
      info.bmiHeader.biWidth = frame.width;
      info.bmiHeader.biHeight = -frame.height;
      info.bmiHeader.biPlanes = 1;
      info.bmiHeader.biBitCount = 32;
      info.bmiHeader.biCompression = BI_RGB;
      SetStretchBltMode(dc, COLORONCOLOR);
      StretchDIBits(dc, 0, 0, client.right - client.left,
                    client.bottom - client.top, 0, 0, frame.width, frame.height,
                    frame.bgra.data(), &info, DIB_RGB_COLORS, SRCCOPY);
    }

    const wchar_t* badge = L"WINPDF NATIVE";
    RECT badge_rect = {6, 6, 118, 28};
    FillRect(dc, &badge_rect, reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(255, 255, 255));
    DrawTextW(dc, badge, -1, &badge_rect,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);

    if (loading) {
      RECT status = {12, 36, client.right - 12, 64};
      SetTextColor(dc, RGB(80, 80, 80));
      DrawTextW(dc, L"Windows.Data.Pdf rendering...", -1, &status,
                DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    } else if (!error.empty()) {
      const std::wstring wide = ErrorToWide(error);
      RECT status = {12, 36, client.right - 12, client.bottom - 12};
      SetTextColor(dc, RGB(180, 0, 0));
      DrawTextW(dc, wide.c_str(), -1, &status,
                DT_LEFT | DT_TOP | DT_WORDBREAK | DT_NOPREFIX);
    }

    EndPaint(window_, &paint);
  }

  HWND parent_ = nullptr;
  HWND window_ = nullptr;
  int64_t key_ = 0;
  std::atomic<int64_t> generation_{0};
  std::mutex mutex_;
  DecodedFrame frame_;
  bool loading_ = false;
  std::string error_;
};

class NativePdfSurfaceHost {
 public:
  explicit NativePdfSurfaceHost(HWND parent) : parent_(parent) {}

  bool Show(int64_t key, int x, int y, int width, int height,
            const std::string& path, int page_number, std::string* error) {
    std::shared_ptr<NativePdfSurface> surface;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      auto it = surfaces_.find(key);
      if (it == surfaces_.end()) {
        surface = std::make_shared<NativePdfSurface>(parent_, key);
        surfaces_.emplace(key, surface);
      } else {
        surface = it->second;
      }
    }
    if (!surface->EnsureWindow(error)) return false;
    surface->Show(x, y, width, height, path, page_number);
    return true;
  }

  void Hide(int64_t key) {
    std::shared_ptr<NativePdfSurface> surface = Find(key);
    if (surface) surface->Hide();
  }

  void Dispose(int64_t key) {
    std::shared_ptr<NativePdfSurface> surface;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      auto it = surfaces_.find(key);
      if (it == surfaces_.end()) return;
      surface = std::move(it->second);
      surfaces_.erase(it);
    }
    surface->Destroy();
  }

  void DisposeAll() {
    std::unordered_map<int64_t, std::shared_ptr<NativePdfSurface>> old;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      old.swap(surfaces_);
    }
    for (auto& entry : old) entry.second->Destroy();
  }

 private:
  std::shared_ptr<NativePdfSurface> Find(int64_t key) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = surfaces_.find(key);
    return it == surfaces_.end() ? nullptr : it->second;
  }

  HWND parent_ = nullptr;
  std::mutex mutex_;
  std::unordered_map<int64_t, std::shared_ptr<NativePdfSurface>> surfaces_;
};

const flutter::EncodableMap* AsMap(const flutter::EncodableValue* value) {
  return value == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(value);
}

int64_t GetInteger(const flutter::EncodableMap& map, const char* key,
                   int64_t fallback = 0) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return fallback;
  if (const auto* value = std::get_if<int32_t>(&it->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&it->second)) return *value;
  return fallback;
}

const std::string* GetString(const flutter::EncodableMap& map,
                             const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : std::get_if<std::string>(&it->second);
}

std::shared_ptr<NativePdfSurfaceHost> g_host;
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

}  // namespace

void RegisterWindowsNativePdfSurfaceChannel(
    flutter::BinaryMessenger* messenger,
    HWND flutter_view_window) {
  g_host = std::make_shared<NativePdfSurfaceHost>(flutter_view_window);
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "lexpdf/windows_native_pdf",
      &flutter::StandardMethodCodec::GetInstance());

  g_channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        const auto* args = AsMap(call.arguments());
        if (!g_host || args == nullptr) {
          result->Error("invalid_state", "Native Windows PDF host is unavailable");
          return;
        }

        if (call.method_name() == "showPage") {
          const auto* path = GetString(*args, "documentPath");
          const int64_t key = GetInteger(*args, "surfaceKey", -1);
          const int page = static_cast<int>(GetInteger(*args, "pageNumber", -1));
          const int x = static_cast<int>(GetInteger(*args, "x", 0));
          const int y = static_cast<int>(GetInteger(*args, "y", 0));
          const int width = static_cast<int>(GetInteger(*args, "width", -1));
          const int height = static_cast<int>(GetInteger(*args, "height", -1));
          if (path == nullptr || path->empty() || key < 0 || page <= 0 ||
              width <= 0 || height <= 0) {
            result->Error("invalid_arguments", "Invalid native PDF surface request");
            return;
          }
          std::string error;
          if (!g_host->Show(key, x, y, width, height, *path, page, &error)) {
            result->Error("native_pdf_failed", error);
            return;
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (call.method_name() == "hideSurface") {
          g_host->Hide(GetInteger(*args, "surfaceKey", -1));
          result->Success();
          return;
        }

        if (call.method_name() == "disposeSurface") {
          g_host->Dispose(GetInteger(*args, "surfaceKey", -1));
          result->Success();
          return;
        }

        if (call.method_name() == "disposeAll") {
          g_host->DisposeAll();
          result->Success();
          return;
        }

        result->NotImplemented();
      });
}

void ShutdownWindowsNativePdfSurfaceChannel() {
  if (g_host) g_host->DisposeAll();
  g_channel.reset();
  g_host.reset();
}
