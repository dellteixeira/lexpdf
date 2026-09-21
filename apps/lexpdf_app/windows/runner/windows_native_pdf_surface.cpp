#include "windows_native_pdf_surface.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <wincodec.h>
#include <wrl/client.h>

#include <winrt/Windows.Data.Pdf.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <list>
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

class NativePdfFrameCache {
 public:
  explicit NativePdfFrameCache(size_t max_bytes) : max_bytes_(max_bytes) {}

  std::shared_ptr<const DecodedFrame> Get(const std::string& key) {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto it = entries_.find(key);
    if (it == entries_.end()) return nullptr;
    lru_.erase(it->second.lru);
    lru_.push_front(key);
    it->second.lru = lru_.begin();
    return it->second.frame;
  }

  void Put(const std::string& key, std::shared_ptr<const DecodedFrame> frame) {
    if (!frame || frame->bgra.empty()) return;
    const size_t bytes = frame->bgra.size();
    if (bytes > max_bytes_) return;
    std::lock_guard<std::mutex> lock(mutex_);
    const auto existing = entries_.find(key);
    if (existing != entries_.end()) {
      current_bytes_ -= existing->second.bytes;
      lru_.erase(existing->second.lru);
      entries_.erase(existing);
    }
    lru_.push_front(key);
    entries_.emplace(key, Entry{std::move(frame), bytes, lru_.begin()});
    current_bytes_ += bytes;
    while (current_bytes_ > max_bytes_ && !lru_.empty()) {
      const std::string victim = lru_.back();
      lru_.pop_back();
      const auto victim_it = entries_.find(victim);
      if (victim_it == entries_.end()) continue;
      current_bytes_ -= victim_it->second.bytes;
      entries_.erase(victim_it);
    }
  }

  void Clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    entries_.clear();
    lru_.clear();
    current_bytes_ = 0;
  }

  size_t bytes() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return current_bytes_;
  }

  size_t entries() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return entries_.size();
  }

 private:
  struct Entry {
    std::shared_ptr<const DecodedFrame> frame;
    size_t bytes;
    std::list<std::string>::iterator lru;
  };

  const size_t max_bytes_;
  mutable std::mutex mutex_;
  size_t current_bytes_ = 0;
  std::list<std::string> lru_;
  std::unordered_map<std::string, Entry> entries_;
};

std::string FrameCacheKey(const std::string& path, int page_number, int width,
                          int height) {
  return path + "|" + std::to_string(page_number) + "|" +
         std::to_string(width) + "x" + std::to_string(height);
}

NativePdfFrameCache g_frame_cache(128ull * 1024ull * 1024ull);
std::atomic<int64_t> g_render_requests{0};
std::atomic<int64_t> g_cache_hits{0};
std::atomic<int64_t> g_cache_misses{0};
std::atomic<int64_t> g_stale_discards{0};
std::atomic<int64_t> g_render_failures{0};
std::atomic<int64_t> g_total_render_ms{0};

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

    const auto file =
        StorageFile::GetFileFromPathAsync(winrt::to_hstring(path)).get();
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
  NativePdfSurface(HWND parent, HWND coordinate_window, int64_t key)
      : parent_(parent),
        coordinate_window_(coordinate_window),
        key_(key) {}
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

    // Dart sends physical client coordinates relative to Flutter's render
    // view. The native PDF HWND is intentionally a sibling of that view,
    // parented by the top-level LexPDF window, so it is not trapped below
    // Flutter's own compositor. Map the physical rectangle into the root
    // client coordinate space before positioning the native surface.
    POINT corners[2] = {
        {x, y},
        {x + width, y + height},
    };
    MapWindowPoints(coordinate_window_, parent_, corners, 2);

    const int mapped_width =
        static_cast<int>(corners[1].x - corners[0].x);
    const int mapped_height =
        static_cast<int>(corners[1].y - corners[0].y);
    width = std::clamp(mapped_width, 1, kMaxNativeDimension);
    height = std::clamp(mapped_height, 1, kMaxNativeDimension);

    SetWindowPos(window_, HWND_TOP, corners[0].x, corners[0].y, width, height,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);

    const int64_t generation = ++generation_;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      loading_ = true;
      error_.clear();
    }
    InvalidateRect(window_, nullptr, FALSE);

    std::weak_ptr<NativePdfSurface> weak_self = shared_from_this();
    ++g_render_requests;
    std::thread([weak_self, generation, path, page_number, width, height]() {
      const auto started = std::chrono::steady_clock::now();
      const std::string cache_key =
          FrameCacheKey(path, page_number, width, height);
      std::shared_ptr<const DecodedFrame> frame = g_frame_cache.Get(cache_key);
      std::string error;
      bool ok = frame != nullptr;
      if (ok) {
        ++g_cache_hits;
      } else {
        ++g_cache_misses;
        auto rendered = std::make_shared<DecodedFrame>();
        ok = RenderWithWindowsPdf(path, page_number, width, height,
                                  rendered.get(), &error);
        if (ok) {
          frame = rendered;
          g_frame_cache.Put(cache_key, frame);
        } else {
          ++g_render_failures;
        }
      }
      const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - started);
      g_total_render_ms += elapsed.count();

      const auto self = weak_self.lock();
      if (!self || generation != self->generation_.load()) {
        ++g_stale_discards;
        return;
      }
      {
        std::lock_guard<std::mutex> lock(self->mutex_);
        self->loading_ = false;
        if (ok && frame) {
          self->frame_ = std::move(frame);
          self->error_.clear();
        } else {
          self->frame_.reset();
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

    std::shared_ptr<const DecodedFrame> frame;
    bool loading = false;
    std::string error;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      frame = frame_;
      loading = loading_;
      error = error_;
    }

    const int client_width = client.right - client.left;
    const int client_height = client.bottom - client.top;
    bool geometry_mismatch = false;
    if (frame && !frame->bgra.empty() && frame->width > 0 &&
        frame->height > 0) {
      BITMAPINFO info = {};
      info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
      info.bmiHeader.biWidth = frame->width;
      info.bmiHeader.biHeight = -frame->height;
      info.bmiHeader.biPlanes = 1;
      info.bmiHeader.biBitCount = 32;
      info.bmiHeader.biCompression = BI_RGB;
      if (frame->width == client_width && frame->height == client_height) {
        // Exact 1:1 presentation. Never silently resample the PDF page in GDI.
        // If Windows.Data.Pdf/WIC returns different dimensions, fail visibly
        // instead of recreating the blur/vertical-smear failure mode.
        SetDIBitsToDevice(dc, 0, 0, static_cast<DWORD>(frame->width),
                          static_cast<DWORD>(frame->height), 0, 0, 0,
                          static_cast<UINT>(frame->height), frame->bgra.data(),
                          &info, DIB_RGB_COLORS);
      } else {
        geometry_mismatch = true;
      }
    }

    const wchar_t* badge = L"WINPDF NATIVE";
    RECT badge_rect = {6, 6, 118, 28};
    FillRect(dc, &badge_rect,
             reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(255, 255, 255));
    DrawTextW(dc, badge, -1, &badge_rect,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);

    if (geometry_mismatch) {
      const std::wstring geometry =
          L"WINPDF SIZE MISMATCH frame=" + std::to_wstring(frame ? frame->width : 0) +
          L"x" + std::to_wstring(frame ? frame->height : 0) + L" client=" +
          std::to_wstring(client_width) + L"x" +
          std::to_wstring(client_height);
      RECT status = {12, 36, client.right - 12, 88};
      SetTextColor(dc, RGB(180, 0, 0));
      DrawTextW(dc, geometry.c_str(), -1, &status,
                DT_LEFT | DT_TOP | DT_WORDBREAK | DT_NOPREFIX);
    } else if (loading) {
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
  // The Flutter render-view HWND is only a coordinate source, never a parent.
  HWND coordinate_window_ = nullptr;
  HWND window_ = nullptr;
  int64_t key_ = 0;
  std::atomic<int64_t> generation_{0};
  std::mutex mutex_;
  std::shared_ptr<const DecodedFrame> frame_;
  bool loading_ = false;
  std::string error_;
};

class NativePdfSurfaceHost {
 public:
  NativePdfSurfaceHost(HWND parent, HWND coordinate_window)
      : parent_(parent),
        coordinate_window_(coordinate_window) {}

  bool Show(int64_t key, int x, int y, int width, int height,
            const std::string& path, int page_number, std::string* error) {
    std::shared_ptr<NativePdfSurface> surface;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      auto it = surfaces_.find(key);
      if (it == surfaces_.end()) {
        surface = std::make_shared<NativePdfSurface>(
            parent_, coordinate_window_, key);
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
  HWND coordinate_window_ = nullptr;
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
    HWND root_window,
    HWND flutter_view_window) {
  g_host = std::make_shared<NativePdfSurfaceHost>(
      root_window, flutter_view_window);
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "lexpdf/windows_native_pdf",
      &flutter::StandardMethodCodec::GetInstance());

  g_channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        const auto* args = AsMap(call.arguments());
        if (!g_host || args == nullptr) {
          result->Error("invalid_state",
                        "Native Windows PDF host is unavailable");
          return;
        }

        if (call.method_name() == "showPage") {
          const auto* path = GetString(*args, "documentPath");
          const int64_t key = GetInteger(*args, "surfaceKey", -1);
          const int page =
              static_cast<int>(GetInteger(*args, "pageNumber", -1));
          const int x = static_cast<int>(GetInteger(*args, "x", 0));
          const int y = static_cast<int>(GetInteger(*args, "y", 0));
          const int width =
              static_cast<int>(GetInteger(*args, "width", -1));
          const int height =
              static_cast<int>(GetInteger(*args, "height", -1));
          if (path == nullptr || path->empty() || key < 0 || page <= 0 ||
              width <= 0 || height <= 0) {
            result->Error("invalid_arguments",
                          "Invalid native PDF surface request");
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

        if (call.method_name() == "getDiagnostics") {
          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("renderRequests")] =
              flutter::EncodableValue(g_render_requests.load());
          payload[flutter::EncodableValue("cacheHits")] =
              flutter::EncodableValue(g_cache_hits.load());
          payload[flutter::EncodableValue("cacheMisses")] =
              flutter::EncodableValue(g_cache_misses.load());
          payload[flutter::EncodableValue("staleDiscards")] =
              flutter::EncodableValue(g_stale_discards.load());
          payload[flutter::EncodableValue("renderFailures")] =
              flutter::EncodableValue(g_render_failures.load());
          payload[flutter::EncodableValue("totalRenderMs")] =
              flutter::EncodableValue(g_total_render_ms.load());
          payload[flutter::EncodableValue("cacheBytes")] =
              flutter::EncodableValue(static_cast<int64_t>(g_frame_cache.bytes()));
          payload[flutter::EncodableValue("cacheEntries")] =
              flutter::EncodableValue(static_cast<int64_t>(g_frame_cache.entries()));
          result->Success(flutter::EncodableValue(std::move(payload)));
          return;
        }

        if (call.method_name() == "clearRenderCache") {
          g_frame_cache.Clear();
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
