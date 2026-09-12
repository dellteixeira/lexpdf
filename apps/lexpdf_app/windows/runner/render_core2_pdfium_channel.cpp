#include "render_core2_pdfium_channel.h"

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace {

using FPDF_DOCUMENT = void*;
using FPDF_PAGE = void*;
using FPDF_BITMAP = void*;

class PdfiumRuntime {
 public:
  PdfiumRuntime() = default;
  ~PdfiumRuntime() { Reset(); }

  bool EnsureLoaded(std::string* error) {
    if (module_ != nullptr) return true;
    module_ = LoadLibraryW(L"pdfium.dll");
    if (module_ == nullptr) {
      *error = "pdfium.dll was not found next to the app or on PATH";
      return false;
    }

    init_library_ = Load<InitLibraryFn>("FPDF_InitLibrary");
    destroy_library_ = Load<DestroyLibraryFn>("FPDF_DestroyLibrary");
    load_document_ = Load<LoadDocumentFn>("FPDF_LoadDocument");
    close_document_ = Load<CloseDocumentFn>("FPDF_CloseDocument");
    get_page_count_ = Load<GetPageCountFn>("FPDF_GetPageCount");
    load_page_ = Load<LoadPageFn>("FPDF_LoadPage");
    close_page_ = Load<ClosePageFn>("FPDF_ClosePage");
    get_page_width_ = Load<GetPageDimensionFn>("FPDF_GetPageWidth");
    get_page_height_ = Load<GetPageDimensionFn>("FPDF_GetPageHeight");
    bitmap_create_ = Load<BitmapCreateFn>("FPDFBitmap_Create");
    bitmap_destroy_ = Load<BitmapDestroyFn>("FPDFBitmap_Destroy");
    bitmap_fill_rect_ = Load<BitmapFillRectFn>("FPDFBitmap_FillRect");
    bitmap_get_buffer_ = Load<BitmapGetBufferFn>("FPDFBitmap_GetBuffer");
    bitmap_get_stride_ = Load<BitmapGetStrideFn>("FPDFBitmap_GetStride");
    render_page_bitmap_ = Load<RenderPageBitmapFn>("FPDF_RenderPageBitmap");

    if (!init_library_ || !destroy_library_ || !load_document_ ||
        !close_document_ || !get_page_count_ || !load_page_ || !close_page_ ||
        !get_page_width_ || !get_page_height_ || !bitmap_create_ ||
        !bitmap_destroy_ || !bitmap_fill_rect_ || !bitmap_get_buffer_ ||
        !bitmap_get_stride_ || !render_page_bitmap_) {
      *error = "pdfium.dll is missing required PDFium exports";
      Reset();
      return false;
    }

    init_library_();
    initialized_ = true;
    return true;
  }

  bool Open(const std::string& path, std::string* error) {
    if (!EnsureLoaded(error)) return false;
    CloseDocument();
    document_ = load_document_(path.c_str(), nullptr);
    if (document_ == nullptr) {
      *error = "FPDF_LoadDocument failed";
      return false;
    }
    document_path_ = path;
    return true;
  }

  void CloseDocument() {
    if (document_ != nullptr && close_document_) {
      close_document_(document_);
    }
    document_ = nullptr;
    document_path_.clear();
  }

  bool PageInfo(int page_number, int* page_count, double* width_points,
                double* height_points, std::string* error) {
    if (document_ == nullptr) {
      *error = "No PDF document is open";
      return false;
    }

    const int count = get_page_count_(document_);
    const int page_index = page_number - 1;
    if (page_index < 0 || page_index >= count) {
      *error = "Requested page is outside the document range";
      return false;
    }

    FPDF_PAGE page = load_page_(document_, page_index);
    if (page == nullptr) {
      *error = "FPDF_LoadPage failed";
      return false;
    }

    const double width = get_page_width_(page);
    const double height = get_page_height_(page);
    close_page_(page);
    if (width <= 0.0 || height <= 0.0) {
      *error = "PDFium returned invalid page dimensions";
      return false;
    }

    *page_count = count;
    *width_points = width;
    *height_points = height;
    return true;
  }

  bool Render(int page_number, int width, int height,
              std::vector<uint8_t>* pixels, int* stride,
              std::string* error) {
    if (document_ == nullptr) {
      *error = "No PDF document is open";
      return false;
    }
    if (width <= 0 || height <= 0) {
      *error = "Invalid target dimensions";
      return false;
    }

    const int page_index = page_number - 1;
    const int page_count = get_page_count_(document_);
    if (page_index < 0 || page_index >= page_count) {
      *error = "Requested page is outside the document range";
      return false;
    }

    FPDF_PAGE page = load_page_(document_, page_index);
    if (page == nullptr) {
      *error = "FPDF_LoadPage failed";
      return false;
    }

    FPDF_BITMAP bitmap = bitmap_create_(width, height, 1);
    if (bitmap == nullptr) {
      close_page_(page);
      *error = "FPDFBitmap_Create failed";
      return false;
    }

    bitmap_fill_rect_(bitmap, 0, 0, width, height, 0xFFFFFFFFu);
    render_page_bitmap_(bitmap, page, 0, 0, width, height, 0, 0);

    void* raw = bitmap_get_buffer_(bitmap);
    const int row_bytes = bitmap_get_stride_(bitmap);
    if (raw == nullptr || row_bytes < width * 4) {
      bitmap_destroy_(bitmap);
      close_page_(page);
      *error = "PDFium returned an invalid bitmap buffer";
      return false;
    }

    const auto byte_count = static_cast<size_t>(row_bytes) *
                            static_cast<size_t>(height);
    const auto* begin = static_cast<const uint8_t*>(raw);
    pixels->assign(begin, begin + byte_count);
    *stride = row_bytes;

    bitmap_destroy_(bitmap);
    close_page_(page);
    return true;
  }

 private:
  using InitLibraryFn = void (*)();
  using DestroyLibraryFn = void (*)();
  using LoadDocumentFn = FPDF_DOCUMENT (*)(const char*, const char*);
  using CloseDocumentFn = void (*)(FPDF_DOCUMENT);
  using GetPageCountFn = int (*)(FPDF_DOCUMENT);
  using LoadPageFn = FPDF_PAGE (*)(FPDF_DOCUMENT, int);
  using ClosePageFn = void (*)(FPDF_PAGE);
  using GetPageDimensionFn = double (*)(FPDF_PAGE);
  using BitmapCreateFn = FPDF_BITMAP (*)(int, int, int);
  using BitmapDestroyFn = void (*)(FPDF_BITMAP);
  using BitmapFillRectFn = void (*)(FPDF_BITMAP, int, int, int, int, uint32_t);
  using BitmapGetBufferFn = void* (*)(FPDF_BITMAP);
  using BitmapGetStrideFn = int (*)(FPDF_BITMAP);
  using RenderPageBitmapFn = void (*)(FPDF_BITMAP, FPDF_PAGE, int, int, int,
                                       int, int, int);

  template <typename T>
  T Load(const char* name) {
    return reinterpret_cast<T>(GetProcAddress(module_, name));
  }

  void Reset() {
    CloseDocument();
    if (initialized_ && destroy_library_) destroy_library_();
    initialized_ = false;
    if (module_ != nullptr) FreeLibrary(module_);
    module_ = nullptr;
  }

  HMODULE module_ = nullptr;
  bool initialized_ = false;
  FPDF_DOCUMENT document_ = nullptr;
  std::string document_path_;

  InitLibraryFn init_library_ = nullptr;
  DestroyLibraryFn destroy_library_ = nullptr;
  LoadDocumentFn load_document_ = nullptr;
  CloseDocumentFn close_document_ = nullptr;
  GetPageCountFn get_page_count_ = nullptr;
  LoadPageFn load_page_ = nullptr;
  ClosePageFn close_page_ = nullptr;
  GetPageDimensionFn get_page_width_ = nullptr;
  GetPageDimensionFn get_page_height_ = nullptr;
  BitmapCreateFn bitmap_create_ = nullptr;
  BitmapDestroyFn bitmap_destroy_ = nullptr;
  BitmapFillRectFn bitmap_fill_rect_ = nullptr;
  BitmapGetBufferFn bitmap_get_buffer_ = nullptr;
  BitmapGetStrideFn bitmap_get_stride_ = nullptr;
  RenderPageBitmapFn render_page_bitmap_ = nullptr;
};

struct TextureFrame {
  std::vector<uint8_t> rgba8888;
  size_t width = 0;
  size_t height = 0;
  int64_t generation = 0;
};

struct PixelBufferLease {
  std::shared_ptr<const TextureFrame> frame;
  FlutterDesktopPixelBuffer pixel_buffer = {};
};

class PdfiumTexturePresenter {
 public:
  explicit PdfiumTexturePresenter(flutter::TextureRegistrar* registrar)
      : registrar_(registrar) {}

  ~PdfiumTexturePresenter() { Dispose(); }

  int64_t EnsureRegistered(std::string* error) {
    if (registrar_ == nullptr) {
      *error = "Flutter texture registrar is unavailable";
      return -1;
    }

    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (texture_id_ >= 0) return texture_id_;
    }

    auto texture = std::make_shared<flutter::TextureVariant>(
        flutter::PixelBufferTexture(
            [this](size_t width, size_t height)
                -> const FlutterDesktopPixelBuffer* {
              return CopyPixelBuffer(width, height);
            }));
    const int64_t texture_id = registrar_->RegisterTexture(texture.get());
    if (texture_id < 0) {
      *error = "Flutter failed to register the Render Core 2 texture";
      return -1;
    }

    {
      std::lock_guard<std::mutex> lock(mutex_);
      texture_ = std::move(texture);
      texture_id_ = texture_id;
    }
    return texture_id;
  }

  bool Present(const std::vector<uint8_t>& bgra8888, int width, int height,
               int stride, int64_t generation, int64_t* texture_id,
               std::string* error) {
    if (width <= 0 || height <= 0 || stride < width * 4) {
      *error = "Invalid PDFium frame for native texture presentation";
      return false;
    }

    const auto required_bytes = static_cast<size_t>(stride) *
                                static_cast<size_t>(height);
    if (bgra8888.size() < required_bytes) {
      *error = "PDFium frame buffer is smaller than its declared stride";
      return false;
    }

    const int64_t id = EnsureRegistered(error);
    if (id < 0) return false;

    auto frame = std::make_shared<TextureFrame>();
    frame->width = static_cast<size_t>(width);
    frame->height = static_cast<size_t>(height);
    frame->generation = generation;
    frame->rgba8888.resize(frame->width * frame->height * 4);

    // Flutter's PixelBufferTexture path consumes tightly packed RGBA8888.
    // PDFium exposes BGRA, so swizzle entirely in native memory. Dart never
    // receives the page-sized pixel payload in the Texture path.
    for (int y = 0; y < height; ++y) {
      const uint8_t* source =
          bgra8888.data() + static_cast<size_t>(y) * stride;
      uint8_t* target = frame->rgba8888.data() +
                        static_cast<size_t>(y) * frame->width * 4;
      for (int x = 0; x < width; ++x) {
        const size_t offset = static_cast<size_t>(x) * 4;
        target[offset] = source[offset + 2];
        target[offset + 1] = source[offset + 1];
        target[offset + 2] = source[offset];
        target[offset + 3] = source[offset + 3];
      }
    }

    {
      std::lock_guard<std::mutex> lock(mutex_);
      current_frame_ = std::move(frame);
    }

    if (!registrar_->MarkTextureFrameAvailable(id)) {
      *error = "Flutter rejected the Render Core 2 texture frame notification";
      return false;
    }

    *texture_id = id;
    return true;
  }

  void Dispose() {
    if (registrar_ == nullptr) return;

    int64_t id = -1;
    std::shared_ptr<flutter::TextureVariant> texture;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      id = texture_id_;
      texture_id_ = -1;
      texture = std::move(texture_);
      current_frame_.reset();
    }

    if (id >= 0 && texture) {
      registrar_->UnregisterTexture(id, [texture]() {});
    }
  }

 private:
  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t requested_width,
                                                    size_t requested_height) {
    (void)requested_width;
    (void)requested_height;

    std::shared_ptr<const TextureFrame> frame;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      frame = current_frame_;
    }
    if (!frame || frame->rgba8888.empty()) return nullptr;

    auto* lease = new PixelBufferLease();
    lease->frame = std::move(frame);
    lease->pixel_buffer.buffer = lease->frame->rgba8888.data();
    lease->pixel_buffer.width = lease->frame->width;
    lease->pixel_buffer.height = lease->frame->height;
    lease->pixel_buffer.release_callback = [](void* context) {
      delete static_cast<PixelBufferLease*>(context);
    };
    lease->pixel_buffer.release_context = lease;
    return &lease->pixel_buffer;
  }

  flutter::TextureRegistrar* registrar_ = nullptr;
  std::mutex mutex_;
  int64_t texture_id_ = -1;
  std::shared_ptr<flutter::TextureVariant> texture_;
  std::shared_ptr<const TextureFrame> current_frame_;
};

const flutter::EncodableMap* AsMap(const flutter::EncodableValue* value) {
  return value == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(value);
}

const std::string* GetString(const flutter::EncodableMap& map,
                             const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return nullptr;
  return std::get_if<std::string>(&it->second);
}

int64_t GetInteger(const flutter::EncodableMap& map, const char* key,
                   int64_t fallback) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return fallback;
  if (const auto* value = std::get_if<int32_t>(&it->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&it->second)) return *value;
  return fallback;
}

bool ReadRenderArguments(const flutter::EncodableMap* args, int64_t* page,
                         int64_t* width, int64_t* height,
                         int64_t* generation, std::string* error) {
  if (args == nullptr) {
    *error = "Expected argument map";
    return false;
  }

  *page = GetInteger(*args, "pageNumber", -1);
  *width = GetInteger(*args, "pixelWidth", -1);
  *height = GetInteger(*args, "pixelHeight", -1);
  *generation = GetInteger(*args, "generation", 0);
  if (*page <= 0 || *width <= 0 || *height <= 0 ||
      *width > 32768 || *height > 32768) {
    *error = "Invalid page or dimensions";
    return false;
  }
  return true;
}

}  // namespace

void RegisterRenderCore2PdfiumChannel(
    flutter::BinaryMessenger* messenger,
    flutter::TextureRegistrar* texture_registrar) {
  auto runtime = std::make_shared<PdfiumRuntime>();
  auto texture_presenter =
      std::make_shared<PdfiumTexturePresenter>(texture_registrar);
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "lexpdf/render_core2_pdfium",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [runtime, texture_presenter](const auto& call, auto result) {
        const std::string& method = call.method_name();
        const auto* args = AsMap(call.arguments());

        if (method == "openDocument") {
          if (args == nullptr) {
            result->Error("invalid_arguments", "Expected argument map");
            return;
          }
          const std::string* path = GetString(*args, "documentPath");
          if (path == nullptr || path->empty()) {
            result->Error("invalid_arguments", "documentPath is required");
            return;
          }
          std::string error;
          if (!runtime->Open(*path, &error)) {
            result->Error("pdfium_open_failed", error);
            return;
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (method == "getPageInfo") {
          if (args == nullptr) {
            result->Error("invalid_arguments", "Expected argument map");
            return;
          }
          const int64_t page = GetInteger(*args, "pageNumber", -1);
          if (page <= 0) {
            result->Error("invalid_arguments", "Invalid page number");
            return;
          }

          int page_count = 0;
          double width_points = 0.0;
          double height_points = 0.0;
          std::string error;
          if (!runtime->PageInfo(static_cast<int>(page), &page_count,
                                 &width_points, &height_points, &error)) {
            result->Error("pdfium_page_info_failed", error);
            return;
          }

          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("pageNumber")] =
              flutter::EncodableValue(static_cast<int32_t>(page));
          payload[flutter::EncodableValue("pageCount")] =
              flutter::EncodableValue(static_cast<int32_t>(page_count));
          payload[flutter::EncodableValue("widthPoints")] =
              flutter::EncodableValue(width_points);
          payload[flutter::EncodableValue("heightPoints")] =
              flutter::EncodableValue(height_points);
          result->Success(flutter::EncodableValue(std::move(payload)));
          return;
        }

        if (method == "createTexture") {
          std::string error;
          const int64_t texture_id = texture_presenter->EnsureRegistered(&error);
          if (texture_id < 0) {
            result->Error("texture_register_failed", error);
            return;
          }
          result->Success(flutter::EncodableValue(texture_id));
          return;
        }

        if (method == "renderPage" || method == "renderPageToTexture") {
          int64_t page = -1;
          int64_t width = -1;
          int64_t height = -1;
          int64_t generation = 0;
          std::string error;
          if (!ReadRenderArguments(args, &page, &width, &height, &generation,
                                   &error)) {
            result->Error("invalid_arguments", error);
            return;
          }

          std::vector<uint8_t> pixels;
          int stride = 0;
          if (!runtime->Render(static_cast<int>(page), static_cast<int>(width),
                               static_cast<int>(height), &pixels, &stride,
                               &error)) {
            result->Error("pdfium_render_failed", error);
            return;
          }

          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("width")] =
              flutter::EncodableValue(static_cast<int32_t>(width));
          payload[flutter::EncodableValue("height")] =
              flutter::EncodableValue(static_cast<int32_t>(height));
          payload[flutter::EncodableValue("generation")] =
              flutter::EncodableValue(generation);

          if (method == "renderPageToTexture") {
            int64_t texture_id = -1;
            if (!texture_presenter->Present(
                    pixels, static_cast<int>(width), static_cast<int>(height),
                    stride, generation, &texture_id, &error)) {
              result->Error("texture_present_failed", error);
              return;
            }
            payload[flutter::EncodableValue("textureId")] =
                flutter::EncodableValue(texture_id);
            result->Success(flutter::EncodableValue(std::move(payload)));
            return;
          }

          payload[flutter::EncodableValue("rowBytes")] =
              flutter::EncodableValue(static_cast<int32_t>(stride));
          payload[flutter::EncodableValue("bgra8888")] =
              flutter::EncodableValue(std::move(pixels));
          result->Success(flutter::EncodableValue(std::move(payload)));
          return;
        }

        if (method == "disposeTexture") {
          texture_presenter->Dispose();
          result->Success();
          return;
        }

        if (method == "closeDocument") {
          runtime->CloseDocument();
          result->Success();
          return;
        }

        result->NotImplemented();
      });

  // Keep the channel alive for the lifetime of the process. The engine owns
  // the messenger; the handler captures the shared PDFium runtime and texture
  // presenter. Texture buffers are ref-counted per frame by release callbacks.
  channel.release();
}
