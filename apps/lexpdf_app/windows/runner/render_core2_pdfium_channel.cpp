#include "render_core2_pdfium_channel.h"

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
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

}  // namespace

void RegisterRenderCore2PdfiumChannel(flutter::BinaryMessenger* messenger) {
  auto runtime = std::make_shared<PdfiumRuntime>();
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "lexpdf/render_core2_pdfium",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [runtime](const auto& call, auto result) {
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

        if (method == "renderPage") {
          if (args == nullptr) {
            result->Error("invalid_arguments", "Expected argument map");
            return;
          }
          const int64_t page = GetInteger(*args, "pageNumber", -1);
          const int64_t width = GetInteger(*args, "pixelWidth", -1);
          const int64_t height = GetInteger(*args, "pixelHeight", -1);
          const int64_t generation = GetInteger(*args, "generation", 0);
          if (page <= 0 || width <= 0 || height <= 0 ||
              width > 32768 || height > 32768) {
            result->Error("invalid_arguments", "Invalid page or dimensions");
            return;
          }

          std::vector<uint8_t> pixels;
          int stride = 0;
          std::string error;
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
          payload[flutter::EncodableValue("rowBytes")] =
              flutter::EncodableValue(static_cast<int32_t>(stride));
          payload[flutter::EncodableValue("generation")] =
              flutter::EncodableValue(generation);
          payload[flutter::EncodableValue("bgra8888")] =
              flutter::EncodableValue(std::move(pixels));
          result->Success(flutter::EncodableValue(std::move(payload)));
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
  // the messenger; the handler captures the shared PDFium runtime.
  channel.release();
}
