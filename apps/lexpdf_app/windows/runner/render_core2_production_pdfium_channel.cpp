#include "render_core2_production_pdfium_channel.h"

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

using FPDF_DOCUMENT = void*;
using FPDF_PAGE = void*;
using FPDF_BITMAP = void*;

constexpr int kFpdfAnnot = 0x01;
constexpr int kFpdfLcdText = 0x02;
constexpr int kMaxRenderDimension = 32768;

class ProductionPdfiumRuntime {
 public:
  ProductionPdfiumRuntime() = default;
  ~ProductionPdfiumRuntime() { Reset(); }

  bool IsOpenPath(const std::string& path) const {
    return document_ != nullptr && document_path_ == path;
  }

  bool EnsureLoaded(std::string* error) {
    if (module_ != nullptr) return true;

    // Flutter Windows copies Dart native assets next to the executable. pdfrx
    // packages PDFium as a Windows native asset named pdfium.dll, so the normal
    // Windows DLL search order resolves the exact binary already shipped with
    // the application.
    module_ = LoadLibraryW(L"pdfium.dll");
    if (module_ == nullptr) {
      *error = "pdfium.dll was not found in the Windows application bundle";
      return false;
    }

    init_library_ = Load<InitLibraryFn>("FPDF_InitLibrary");
    destroy_library_ = Load<DestroyLibraryFn>("FPDF_DestroyLibrary");
    load_document_ = Load<LoadDocumentFn>("FPDF_LoadDocument");
    close_document_ = Load<CloseDocumentFn>("FPDF_CloseDocument");
    get_page_count_ = Load<GetPageCountFn>("FPDF_GetPageCount");
    load_page_ = Load<LoadPageFn>("FPDF_LoadPage");
    close_page_ = Load<ClosePageFn>("FPDF_ClosePage");
    bitmap_create_ = Load<BitmapCreateFn>("FPDFBitmap_Create");
    bitmap_destroy_ = Load<BitmapDestroyFn>("FPDFBitmap_Destroy");
    bitmap_fill_rect_ = Load<BitmapFillRectFn>("FPDFBitmap_FillRect");
    bitmap_get_buffer_ = Load<BitmapGetBufferFn>("FPDFBitmap_GetBuffer");
    bitmap_get_stride_ = Load<BitmapGetStrideFn>("FPDFBitmap_GetStride");
    render_page_bitmap_ = Load<RenderPageBitmapFn>("FPDF_RenderPageBitmap");

    if (!init_library_ || !destroy_library_ || !load_document_ ||
        !close_document_ || !get_page_count_ || !load_page_ || !close_page_ ||
        !bitmap_create_ || !bitmap_destroy_ || !bitmap_fill_rect_ ||
        !bitmap_get_buffer_ || !bitmap_get_stride_ || !render_page_bitmap_) {
      *error = "pdfium.dll is missing required Render Core 2 exports";
      Reset();
      return false;
    }

    init_library_();
    initialized_ = true;
    return true;
  }

  bool OpenOrReuse(const std::string& path, std::string* error) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!EnsureLoaded(error)) return false;
    if (IsOpenPath(path)) return true;

    CloseDocumentUnlocked();
    document_ = load_document_(path.c_str(), nullptr);
    if (document_ == nullptr) {
      *error = "FPDF_LoadDocument failed for the production renderer";
      return false;
    }
    document_path_ = path;
    return true;
  }

  void CloseDocument() {
    std::lock_guard<std::mutex> lock(mutex_);
    CloseDocumentUnlocked();
  }

  bool Render(int page_number, int width, int height,
              std::vector<uint8_t>* bgra8888, int* stride,
              std::string* error) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (document_ == nullptr) {
      *error = "No PDF document is open in the production renderer";
      return false;
    }
    if (page_number <= 0 || width <= 0 || height <= 0 ||
        width > kMaxRenderDimension || height > kMaxRenderDimension) {
      *error = "Invalid production render page or dimensions";
      return false;
    }

    const int page_count = get_page_count_(document_);
    const int page_index = page_number - 1;
    if (page_index < 0 || page_index >= page_count) {
      *error = "Requested production page is outside the document range";
      return false;
    }

    FPDF_PAGE page = load_page_(document_, page_index);
    if (page == nullptr) {
      *error = "FPDF_LoadPage failed in the production renderer";
      return false;
    }

    FPDF_BITMAP bitmap = bitmap_create_(width, height, 1);
    if (bitmap == nullptr) {
      close_page_(page);
      *error = "FPDFBitmap_Create failed in the production renderer";
      return false;
    }

    bitmap_fill_rect_(bitmap, 0, 0, width, height, 0xFFFFFFFFu);

    // FPDF_LCD_TEXT enables PDFium's LCD/ClearType-oriented text rendering.
    // FPDF_ANNOT preserves annotations already embedded in the source PDF.
    // The raster size is already the exact physical target; no viewer zoom is
    // multiplied here and Flutter must not resample a low-resolution backing
    // page into the visible surface.
    render_page_bitmap_(bitmap, page, 0, 0, width, height, 0,
                        kFpdfAnnot | kFpdfLcdText);

    void* raw = bitmap_get_buffer_(bitmap);
    const int row_bytes = bitmap_get_stride_(bitmap);
    if (raw == nullptr || row_bytes < width * 4) {
      bitmap_destroy_(bitmap);
      close_page_(page);
      *error = "PDFium returned an invalid production bitmap buffer";
      return false;
    }

    const auto byte_count = static_cast<size_t>(row_bytes) *
                            static_cast<size_t>(height);
    const auto* begin = static_cast<const uint8_t*>(raw);
    bgra8888->assign(begin, begin + byte_count);
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

  void CloseDocumentUnlocked() {
    if (document_ != nullptr && close_document_) {
      close_document_(document_);
    }
    document_ = nullptr;
    document_path_.clear();
  }

  void Reset() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      CloseDocumentUnlocked();
    }
    if (initialized_ && destroy_library_) destroy_library_();
    initialized_ = false;
    if (module_ != nullptr) FreeLibrary(module_);
    module_ = nullptr;
  }

  mutable std::mutex mutex_;
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
  BitmapCreateFn bitmap_create_ = nullptr;
  BitmapDestroyFn bitmap_destroy_ = nullptr;
  BitmapFillRectFn bitmap_fill_rect_ = nullptr;
  BitmapGetBufferFn bitmap_get_buffer_ = nullptr;
  BitmapGetStrideFn bitmap_get_stride_ = nullptr;
  RenderPageBitmapFn render_page_bitmap_ = nullptr;
};

struct ProductionTextureFrame {
  std::vector<uint8_t> rgba8888;
  size_t width = 0;
  size_t height = 0;
  int64_t generation = 0;
};

struct ProductionPixelBufferLease {
  std::shared_ptr<const ProductionTextureFrame> frame;
  FlutterDesktopPixelBuffer pixel_buffer = {};
};

class ProductionTexturePresenter {
 public:
  explicit ProductionTexturePresenter(flutter::TextureRegistrar* registrar)
      : registrar_(registrar) {}

  ~ProductionTexturePresenter() { Dispose(); }

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
      *error = "Flutter failed to register a production PDF texture";
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
      *error = "Invalid PDFium frame for production texture presentation";
      return false;
    }
    const auto required_bytes = static_cast<size_t>(stride) *
                                static_cast<size_t>(height);
    if (bgra8888.size() < required_bytes) {
      *error = "Production PDFium buffer is smaller than its declared stride";
      return false;
    }

    const int64_t id = EnsureRegistered(error);
    if (id < 0) return false;

    auto frame = std::make_shared<ProductionTextureFrame>();
    frame->width = static_cast<size_t>(width);
    frame->height = static_cast<size_t>(height);
    frame->generation = generation;
    frame->rgba8888.resize(frame->width * frame->height * 4);

    // PixelBufferTexture consumes RGBA8888. PDFium returns BGRA8888, so the
    // swizzle stays entirely in native memory. No page-sized byte array crosses
    // the Dart method channel in the production path.
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
      *error = "Flutter rejected the production PDF texture frame";
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

    std::shared_ptr<const ProductionTextureFrame> frame;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      frame = current_frame_;
    }
    if (!frame || frame->rgba8888.empty()) return nullptr;

    auto* lease = new ProductionPixelBufferLease();
    lease->frame = std::move(frame);
    lease->pixel_buffer.buffer = lease->frame->rgba8888.data();
    lease->pixel_buffer.width = lease->frame->width;
    lease->pixel_buffer.height = lease->frame->height;
    lease->pixel_buffer.release_callback = [](void* context) {
      delete static_cast<ProductionPixelBufferLease*>(context);
    };
    lease->pixel_buffer.release_context = lease;
    return &lease->pixel_buffer;
  }

  flutter::TextureRegistrar* registrar_ = nullptr;
  std::mutex mutex_;
  int64_t texture_id_ = -1;
  std::shared_ptr<flutter::TextureVariant> texture_;
  std::shared_ptr<const ProductionTextureFrame> current_frame_;
};

class ProductionTexturePool {
 public:
  explicit ProductionTexturePool(flutter::TextureRegistrar* registrar)
      : registrar_(registrar) {}

  std::shared_ptr<ProductionTexturePresenter> GetOrCreate(int64_t key) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = presenters_.find(key);
    if (it != presenters_.end()) return it->second;
    auto presenter = std::make_shared<ProductionTexturePresenter>(registrar_);
    presenters_[key] = presenter;
    return presenter;
  }

  void Dispose(int64_t key) {
    std::shared_ptr<ProductionTexturePresenter> presenter;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      auto it = presenters_.find(key);
      if (it == presenters_.end()) return;
      presenter = std::move(it->second);
      presenters_.erase(it);
    }
    presenter->Dispose();
  }

  void DisposeAll() {
    std::unordered_map<int64_t, std::shared_ptr<ProductionTexturePresenter>> old;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      old.swap(presenters_);
    }
    for (auto& entry : old) {
      entry.second->Dispose();
    }
  }

 private:
  flutter::TextureRegistrar* registrar_ = nullptr;
  std::mutex mutex_;
  std::unordered_map<int64_t, std::shared_ptr<ProductionTexturePresenter>>
      presenters_;
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

bool ReadRenderArguments(const flutter::EncodableMap* args, int64_t* texture_key,
                         int64_t* page, int64_t* width, int64_t* height,
                         int64_t* generation, std::string* error) {
  if (args == nullptr) {
    *error = "Expected argument map";
    return false;
  }
  *texture_key = GetInteger(*args, "textureKey", -1);
  *page = GetInteger(*args, "pageNumber", -1);
  *width = GetInteger(*args, "pixelWidth", -1);
  *height = GetInteger(*args, "pixelHeight", -1);
  *generation = GetInteger(*args, "generation", 0);
  if (*texture_key < 0 || *page <= 0 || *width <= 0 || *height <= 0 ||
      *width > kMaxRenderDimension || *height > kMaxRenderDimension) {
    *error = "Invalid production texture, page, or dimensions";
    return false;
  }
  return true;
}

}  // namespace

void RegisterRenderCore2ProductionPdfiumChannel(
    flutter::BinaryMessenger* messenger,
    flutter::TextureRegistrar* texture_registrar) {
  auto runtime = std::make_shared<ProductionPdfiumRuntime>();
  auto textures = std::make_shared<ProductionTexturePool>(texture_registrar);
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "lexpdf/render_core2_production_pdfium",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [runtime, textures](const auto& call, auto result) {
        const std::string& method = call.method_name();
        const auto* args = AsMap(call.arguments());

        if (method == "ensureDocument") {
          if (args == nullptr) {
            result->Error("invalid_arguments", "Expected argument map");
            return;
          }
          const std::string* path = GetString(*args, "documentPath");
          if (path == nullptr || path->empty()) {
            result->Error("invalid_arguments", "documentPath is required");
            return;
          }
          const bool changed = !runtime->IsOpenPath(*path);
          if (changed) textures->DisposeAll();
          std::string error;
          if (!runtime->OpenOrReuse(*path, &error)) {
            result->Error("pdfium_open_failed", error);
            return;
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (method == "createTexture") {
          if (args == nullptr) {
            result->Error("invalid_arguments", "Expected argument map");
            return;
          }
          const int64_t key = GetInteger(*args, "textureKey", -1);
          if (key < 0) {
            result->Error("invalid_arguments", "textureKey is required");
            return;
          }
          std::string error;
          const int64_t id = textures->GetOrCreate(key)->EnsureRegistered(&error);
          if (id < 0) {
            result->Error("texture_register_failed", error);
            return;
          }
          result->Success(flutter::EncodableValue(id));
          return;
        }

        if (method == "renderPageToTexture") {
          int64_t texture_key = -1;
          int64_t page = -1;
          int64_t width = -1;
          int64_t height = -1;
          int64_t generation = 0;
          std::string error;
          if (!ReadRenderArguments(args, &texture_key, &page, &width, &height,
                                   &generation, &error)) {
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

          int64_t texture_id = -1;
          if (!textures->GetOrCreate(texture_key)->Present(
                  pixels, static_cast<int>(width), static_cast<int>(height),
                  stride, generation, &texture_id, &error)) {
            result->Error("texture_present_failed", error);
            return;
          }

          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("textureId")] =
              flutter::EncodableValue(texture_id);
          payload[flutter::EncodableValue("width")] =
              flutter::EncodableValue(static_cast<int32_t>(width));
          payload[flutter::EncodableValue("height")] =
              flutter::EncodableValue(static_cast<int32_t>(height));
          payload[flutter::EncodableValue("generation")] =
              flutter::EncodableValue(generation);
          result->Success(flutter::EncodableValue(std::move(payload)));
          return;
        }

        if (method == "disposeTexture") {
          if (args != nullptr) {
            const int64_t key = GetInteger(*args, "textureKey", -1);
            if (key >= 0) textures->Dispose(key);
          }
          result->Success();
          return;
        }

        if (method == "closeDocument") {
          textures->DisposeAll();
          runtime->CloseDocument();
          result->Success();
          return;
        }

        result->NotImplemented();
      });

  // The handler captures the shared runtime and texture pool for the engine's
  // lifetime. Every visible page owns an independent texture keyed from Dart.
  channel.release();
}
