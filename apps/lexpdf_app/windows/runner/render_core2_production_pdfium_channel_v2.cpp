#include "render_core2_production_pdfium_channel.h"

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <algorithm>
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
constexpr int kFpdfBitmapBgrx = 3;
constexpr int kMaxRenderDimension = 32768;

class ProductionPdfiumRuntime {
 public:
  ProductionPdfiumRuntime() = default;
  ~ProductionPdfiumRuntime() { Reset(); }

  bool IsOpenPath(const std::string& path) const {
    std::lock_guard<std::mutex> lock(mutex_);
    return document_ != nullptr && document_path_ == path;
  }

  bool OpenOrReuse(const std::string& path, std::string* error) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!EnsureLoadedUnlocked(error)) return false;
    if (document_ != nullptr && document_path_ == path) return true;

    CloseDocumentUnlocked();
    document_ = load_document_(path.c_str(), nullptr);
    if (document_ == nullptr) {
      *error = "FPDF_LoadDocument failed for Render Core 2 production";
      return false;
    }
    document_path_ = path;
    return true;
  }

  void CloseDocument() {
    std::lock_guard<std::mutex> lock(mutex_);
    CloseDocumentUnlocked();
  }

  bool RenderOpaqueBgrx(int page_number, int width, int height,
                        std::vector<uint8_t>* bgrx8888,
                        std::string* error) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (document_ == nullptr) {
      *error = "No PDF document is open in Render Core 2 production";
      return false;
    }
    if (page_number <= 0 || width <= 0 || height <= 0 ||
        width > kMaxRenderDimension || height > kMaxRenderDimension) {
      *error = "Invalid page or physical dimensions";
      return false;
    }

    const int page_count = get_page_count_(document_);
    const int page_index = page_number - 1;
    if (page_index < 0 || page_index >= page_count) {
      *error = "Requested page is outside the document range";
      return false;
    }

    FPDF_PAGE page = load_page_(document_, page_index);
    if (page == nullptr) {
      *error = "FPDF_LoadPage failed";
      return false;
    }

    const int stride = width * 4;
    const size_t byte_count =
        static_cast<size_t>(stride) * static_cast<size_t>(height);
    bgrx8888->assign(byte_count, 0xFF);

    // Use an application-owned, tightly packed buffer. This removes PDFium
    // stride allocation and bitmap-buffer lifetime from the presentation path.
    // The page is opaque, so BGRx is intentional; Flutter should never blend a
    // straight-alpha PDFium page buffer as though it were premultiplied RGBA.
    FPDF_BITMAP bitmap = bitmap_create_ex_(
        width, height, kFpdfBitmapBgrx, bgrx8888->data(), stride);
    if (bitmap == nullptr) {
      close_page_(page);
      *error = "FPDFBitmap_CreateEx(BGRx) failed";
      return false;
    }

    bitmap_fill_rect_(bitmap, 0, 0, width, height, 0xFFFFFFFFu);
    render_page_bitmap_(bitmap, page, 0, 0, width, height, 0,
                        kFpdfAnnot | kFpdfLcdText);

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
  using BitmapCreateExFn = FPDF_BITMAP (*)(int, int, int, void*, int);
  using BitmapDestroyFn = void (*)(FPDF_BITMAP);
  using BitmapFillRectFn = void (*)(FPDF_BITMAP, int, int, int, int, uint32_t);
  using RenderPageBitmapFn = void (*)(FPDF_BITMAP, FPDF_PAGE, int, int, int,
                                      int, int, int);

  template <typename T>
  T Load(const char* name) {
    return reinterpret_cast<T>(GetProcAddress(module_, name));
  }

  bool EnsureLoadedUnlocked(std::string* error) {
    if (module_ != nullptr) return true;
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
    bitmap_create_ex_ = Load<BitmapCreateExFn>("FPDFBitmap_CreateEx");
    bitmap_destroy_ = Load<BitmapDestroyFn>("FPDFBitmap_Destroy");
    bitmap_fill_rect_ = Load<BitmapFillRectFn>("FPDFBitmap_FillRect");
    render_page_bitmap_ = Load<RenderPageBitmapFn>("FPDF_RenderPageBitmap");

    if (!init_library_ || !destroy_library_ || !load_document_ ||
        !close_document_ || !get_page_count_ || !load_page_ || !close_page_ ||
        !bitmap_create_ex_ || !bitmap_destroy_ || !bitmap_fill_rect_ ||
        !render_page_bitmap_) {
      *error = "pdfium.dll is missing required Render Core 2 v2 exports";
      ResetUnlocked();
      return false;
    }

    init_library_();
    initialized_ = true;
    return true;
  }

  void CloseDocumentUnlocked() {
    if (document_ != nullptr && close_document_) close_document_(document_);
    document_ = nullptr;
    document_path_.clear();
  }

  void ResetUnlocked() {
    CloseDocumentUnlocked();
    if (initialized_ && destroy_library_) destroy_library_();
    initialized_ = false;
    if (module_ != nullptr) FreeLibrary(module_);
    module_ = nullptr;
  }

  void Reset() {
    std::lock_guard<std::mutex> lock(mutex_);
    ResetUnlocked();
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
  BitmapCreateExFn bitmap_create_ex_ = nullptr;
  BitmapDestroyFn bitmap_destroy_ = nullptr;
  BitmapFillRectFn bitmap_fill_rect_ = nullptr;
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

std::shared_ptr<ProductionTextureFrame> ConvertBgrxToOpaqueRgba(
    const std::vector<uint8_t>& bgrx, int width, int height,
    int64_t generation) {
  auto frame = std::make_shared<ProductionTextureFrame>();
  frame->width = static_cast<size_t>(width);
  frame->height = static_cast<size_t>(height);
  frame->generation = generation;
  frame->rgba8888.resize(frame->width * frame->height * 4);

  for (size_t i = 0; i < frame->width * frame->height; ++i) {
    const size_t offset = i * 4;
    frame->rgba8888[offset] = bgrx[offset + 2];
    frame->rgba8888[offset + 1] = bgrx[offset + 1];
    frame->rgba8888[offset + 2] = bgrx[offset];
    frame->rgba8888[offset + 3] = 0xFF;
  }
  return frame;
}

std::shared_ptr<ProductionTextureFrame> ResizeNearest(
    const ProductionTextureFrame& source, size_t target_width,
    size_t target_height) {
  if (target_width == 0 || target_height == 0 ||
      (target_width == source.width && target_height == source.height)) {
    auto copy = std::make_shared<ProductionTextureFrame>();
    *copy = source;
    return copy;
  }

  auto target = std::make_shared<ProductionTextureFrame>();
  target->width = target_width;
  target->height = target_height;
  target->generation = source.generation;
  target->rgba8888.resize(target_width * target_height * 4);

  for (size_t y = 0; y < target_height; ++y) {
    const size_t source_y = std::min(
        source.height - 1, (y * source.height) / target_height);
    for (size_t x = 0; x < target_width; ++x) {
      const size_t source_x = std::min(
          source.width - 1, (x * source.width) / target_width);
      const size_t source_offset = (source_y * source.width + source_x) * 4;
      const size_t target_offset = (y * target_width + x) * 4;
      std::copy_n(source.rgba8888.data() + source_offset, 4,
                  target->rgba8888.data() + target_offset);
    }
  }
  return target;
}

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
    const int64_t id = registrar_->RegisterTexture(texture.get());
    if (id < 0) {
      *error = "Flutter failed to register production texture";
      return -1;
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      texture_ = std::move(texture);
      texture_id_ = id;
    }
    return id;
  }

  bool Present(std::shared_ptr<ProductionTextureFrame> frame,
               int64_t* texture_id, std::string* error) {
    if (!frame || frame->width == 0 || frame->height == 0 ||
        frame->rgba8888.size() != frame->width * frame->height * 4) {
      *error = "Invalid tightly packed RGBA production frame";
      return false;
    }
    const int64_t id = EnsureRegistered(error);
    if (id < 0) return false;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      current_frame_ = std::move(frame);
    }
    if (!registrar_->MarkTextureFrameAvailable(id)) {
      *error = "Flutter rejected production texture frame notification";
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
    if (id >= 0 && texture) registrar_->UnregisterTexture(id, [texture]() {});
  }

 private:
  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t requested_width,
                                                    size_t requested_height) {
    std::shared_ptr<const ProductionTextureFrame> source;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      source = current_frame_;
    }
    if (!source || source->rgba8888.empty()) return nullptr;

    // Flutter invokes this callback with the intended physical surface size.
    // Return exactly that size when it differs from the PDFium raster. This
    // prevents the Windows embedder from interpreting a differently-sized
    // buffer as the requested surface, which can cause severe vertical smear.
    std::shared_ptr<const ProductionTextureFrame> delivered = source;
    if (requested_width > 0 && requested_height > 0 &&
        (requested_width != source->width ||
         requested_height != source->height)) {
      delivered = ResizeNearest(*source, requested_width, requested_height);
    }

    auto* lease = new ProductionPixelBufferLease();
    lease->frame = std::move(delivered);
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
    for (auto& entry : old) entry.second->Dispose();
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

bool ReadRenderArguments(const flutter::EncodableMap* args,
                         int64_t* texture_key, int64_t* page,
                         int64_t* width, int64_t* height,
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

          std::vector<uint8_t> bgrx;
          if (!runtime->RenderOpaqueBgrx(
                  static_cast<int>(page), static_cast<int>(width),
                  static_cast<int>(height), &bgrx, &error)) {
            result->Error("pdfium_render_failed", error);
            return;
          }
          auto frame = ConvertBgrxToOpaqueRgba(
              bgrx, static_cast<int>(width), static_cast<int>(height),
              generation);

          int64_t texture_id = -1;
          if (!textures->GetOrCreate(texture_key)->Present(
                  std::move(frame), &texture_id, &error)) {
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
          payload[flutter::EncodableValue("pixelFormat")] =
              flutter::EncodableValue("opaque-rgba8888");
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

  channel.release();
}
