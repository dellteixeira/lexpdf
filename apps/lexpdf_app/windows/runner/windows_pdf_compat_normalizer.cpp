#include "windows_pdf_compat_normalizer.h"

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdio>
#include <memory>
#include <string>

namespace {

using FPDF_DOCUMENT = void*;
using FPDF_BOOL = int;
using FPDF_DWORD = unsigned long;
using FPDF_BYTESTRING = const char*;

struct FPDF_FILEWRITE {
  int version;
  int (*WriteBlock)(FPDF_FILEWRITE* pThis, const void* pData,
                    unsigned long size);
};

constexpr FPDF_DWORD kFpdfNoIncremental = 2;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring output(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      output.data(), size);
  return output;
}

class PdfiumCompatRuntime {
 public:
  PdfiumCompatRuntime() = default;
  ~PdfiumCompatRuntime() { Reset(); }

  bool Normalize(const std::string& source_path,
                 const std::string& destination_path,
                 int* page_count,
                 std::string* error) {
    if (!EnsureLoaded(error)) return false;

    FPDF_DOCUMENT source = load_document_(source_path.c_str(), nullptr);
    if (source == nullptr) {
      *error = "FPDF_LoadDocument failed for compatibility source";
      return false;
    }

    const int source_pages = get_page_count_(source);
    if (source_pages <= 0) {
      close_document_(source);
      *error = "Compatibility source has no pages";
      return false;
    }

    FPDF_DOCUMENT destination = create_new_document_();
    if (destination == nullptr) {
      close_document_(source);
      *error = "FPDF_CreateNewDocument failed";
      return false;
    }

    // Importing into a fresh document rebuilds the page tree and discards the
    // problematic document-level structure graph that triggered the physical
    // Windows rendering corruption, while keeping page content vector/text.
    if (!import_pages_(destination, source, nullptr, 0)) {
      close_document_(destination);
      close_document_(source);
      *error = "FPDF_ImportPages failed";
      return false;
    }

    const int imported_pages = get_page_count_(destination);
    if (imported_pages != source_pages) {
      close_document_(destination);
      close_document_(source);
      *error = "Imported PDF page count does not match source";
      return false;
    }

    const std::wstring wide_destination = Utf8ToWide(destination_path);
    if (wide_destination.empty()) {
      close_document_(destination);
      close_document_(source);
      *error = "Destination path is not valid UTF-8";
      return false;
    }

    FILE* output = nullptr;
    if (_wfopen_s(&output, wide_destination.c_str(), L"wb") != 0 ||
        output == nullptr) {
      close_document_(destination);
      close_document_(source);
      *error = "Could not create normalized PDF output";
      return false;
    }

    FileWriter writer = {};
    writer.base.version = 1;
    writer.base.WriteBlock = &WriteBlock;
    writer.file = output;

    const bool saved =
        save_as_copy_(destination, &writer.base, kFpdfNoIncremental) != 0;
    const int close_result = fclose(output);

    close_document_(destination);
    close_document_(source);

    if (!saved || close_result != 0) {
      DeleteFileW(wide_destination.c_str());
      *error = "FPDF_SaveAsCopy failed";
      return false;
    }

    *page_count = imported_pages;
    return true;
  }

 private:
  using InitLibraryFn = void (*)();
  using DestroyLibraryFn = void (*)();
  using LoadDocumentFn = FPDF_DOCUMENT (*)(const char*, const char*);
  using CloseDocumentFn = void (*)(FPDF_DOCUMENT);
  using GetPageCountFn = int (*)(FPDF_DOCUMENT);
  using CreateNewDocumentFn = FPDF_DOCUMENT (*)();
  using ImportPagesFn = FPDF_BOOL (*)(FPDF_DOCUMENT, FPDF_DOCUMENT,
                                      FPDF_BYTESTRING, int);
  using SaveAsCopyFn = FPDF_BOOL (*)(FPDF_DOCUMENT, FPDF_FILEWRITE*,
                                     FPDF_DWORD);

  struct FileWriter {
    FPDF_FILEWRITE base = {};
    FILE* file = nullptr;
  };

  static int WriteBlock(FPDF_FILEWRITE* base, const void* data,
                        unsigned long size) {
    if (base == nullptr || data == nullptr) return 0;
    auto* writer = reinterpret_cast<FileWriter*>(base);
    if (writer->file == nullptr) return 0;
    return fwrite(data, 1, static_cast<size_t>(size), writer->file) ==
                   static_cast<size_t>(size)
               ? 1
               : 0;
  }

  template <typename T>
  T Load(const char* name) {
    return reinterpret_cast<T>(GetProcAddress(module_, name));
  }

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
    create_new_document_ =
        Load<CreateNewDocumentFn>("FPDF_CreateNewDocument");
    import_pages_ = Load<ImportPagesFn>("FPDF_ImportPages");
    save_as_copy_ = Load<SaveAsCopyFn>("FPDF_SaveAsCopy");

    if (!init_library_ || !destroy_library_ || !load_document_ ||
        !close_document_ || !get_page_count_ || !create_new_document_ ||
        !import_pages_ || !save_as_copy_) {
      *error = "pdfium.dll is missing PDF compatibility exports";
      Reset();
      return false;
    }

    init_library_();
    initialized_ = true;
    return true;
  }

  void Reset() {
    if (initialized_ && destroy_library_) destroy_library_();
    initialized_ = false;
    if (module_ != nullptr) FreeLibrary(module_);
    module_ = nullptr;

    init_library_ = nullptr;
    destroy_library_ = nullptr;
    load_document_ = nullptr;
    close_document_ = nullptr;
    get_page_count_ = nullptr;
    create_new_document_ = nullptr;
    import_pages_ = nullptr;
    save_as_copy_ = nullptr;
  }

  HMODULE module_ = nullptr;
  bool initialized_ = false;
  InitLibraryFn init_library_ = nullptr;
  DestroyLibraryFn destroy_library_ = nullptr;
  LoadDocumentFn load_document_ = nullptr;
  CloseDocumentFn close_document_ = nullptr;
  GetPageCountFn get_page_count_ = nullptr;
  CreateNewDocumentFn create_new_document_ = nullptr;
  ImportPagesFn import_pages_ = nullptr;
  SaveAsCopyFn save_as_copy_ = nullptr;
};

const flutter::EncodableMap* AsMap(const flutter::EncodableValue* value) {
  return value == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(value);
}

const std::string* GetString(const flutter::EncodableMap& map,
                             const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return nullptr;
  return std::get_if<std::string>(&it->second);
}

std::shared_ptr<PdfiumCompatRuntime> g_runtime;
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

}  // namespace

void RegisterWindowsPdfCompatNormalizerChannel(
    flutter::BinaryMessenger* messenger) {
  g_runtime = std::make_shared<PdfiumCompatRuntime>();
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "lexpdf/windows_pdf_compat",
      &flutter::StandardMethodCodec::GetInstance());

  g_channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() != "normalize") {
          result->NotImplemented();
          return;
        }

        const auto* args = AsMap(call.arguments());
        if (!g_runtime || args == nullptr) {
          result->Error("invalid_state", "PDF compatibility normalizer unavailable");
          return;
        }

        const std::string* source = GetString(*args, "sourcePath");
        const std::string* destination = GetString(*args, "destinationPath");
        if (source == nullptr || source->empty() || destination == nullptr ||
            destination->empty()) {
          result->Error("invalid_arguments",
                        "sourcePath and destinationPath are required");
          return;
        }

        int page_count = 0;
        std::string error;
        if (!g_runtime->Normalize(*source, *destination, &page_count, &error)) {
          result->Error("pdf_compat_normalization_failed", error);
          return;
        }

        flutter::EncodableMap payload;
        payload[flutter::EncodableValue("ok")] = flutter::EncodableValue(true);
        payload[flutter::EncodableValue("pageCount")] =
            flutter::EncodableValue(static_cast<int32_t>(page_count));
        result->Success(flutter::EncodableValue(std::move(payload)));
      });
}

void ShutdownWindowsPdfCompatNormalizerChannel() {
  g_channel.reset();
  g_runtime.reset();
}
