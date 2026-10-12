#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

constexpr char kMagic[8] = {'V', 'M', 'W', 'L', 'P', 'K', '0', '1'};
constexpr DWORD kTrailerSize = 52;
constexpr DWORD kDigestSize = 32;
constexpr DWORD kReadChunk = 1u << 20;

constexpr wchar_t kEntryPoint[] = L"vmware_localizer.exe";

constexpr wchar_t kReadyMarker[] = L".extracted";

void AttachParentConsole() {
  const HANDLE existing = ::GetStdHandle(STD_OUTPUT_HANDLE);
  if (existing != nullptr && existing != INVALID_HANDLE_VALUE) {
    return;
  }

  if (::AttachConsole(ATTACH_PARENT_PROCESS) == 0) return;
  FILE* stream = nullptr;
  if (freopen_s(&stream, "CONOUT$", "w", stdout) != 0) return;
  if (freopen_s(&stream, "CONOUT$", "w", stderr) != 0) return;
  SetConsoleOutputCP(CP_UTF8);
}

std::wstring Env(const wchar_t* name) {
  DWORD needed = GetEnvironmentVariableW(name, nullptr, 0);
  if (needed == 0) return std::wstring();
  std::vector<wchar_t> buffer(needed);
  GetEnvironmentVariableW(name, buffer.data(), needed);
  return std::wstring(buffer.data());
}

std::wstring ExecutablePath() {
  std::vector<wchar_t> buffer(32768);
  DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                    static_cast<DWORD>(buffer.size()));
  if (length == 0) return std::wstring();
  return std::wstring(buffer.data(), length);
}

bool ReadTrailer(HANDLE file, LARGE_INTEGER file_size, ULONGLONG* payload_offset,
                 ULONGLONG* payload_length, BYTE digest[kDigestSize]) {
  if (file_size.QuadPart <= static_cast<LONGLONG>(kTrailerSize)) return false;

  LARGE_INTEGER pos;
  pos.QuadPart = file_size.QuadPart - kTrailerSize;
  if (!SetFilePointerEx(file, pos, nullptr, FILE_BEGIN)) return false;

  BYTE trailer[kTrailerSize] = {};
  DWORD read = 0;
  if (!ReadFile(file, trailer, kTrailerSize, &read, nullptr) ||
      read != kTrailerSize) {
    return false;
  }
  if (memcmp(trailer, kMagic, 8) != 0) return false;

  ULONGLONG length = 0;
  memcpy(&length, trailer + 8, 8);
  DWORD trailer_len = 0;
  memcpy(&trailer_len, trailer + 48, 4);
  if (trailer_len != kTrailerSize) return false;
  if (length == 0 || length + kTrailerSize > static_cast<ULONGLONG>(file_size.QuadPart)) {
    return false;
  }

  memcpy(digest, trailer + 16, kDigestSize);
  *payload_length = length;
  *payload_offset =
      static_cast<ULONGLONG>(file_size.QuadPart) - kTrailerSize - length;
  return true;
}

std::wstring PayloadTag(const BYTE digest[kDigestSize]) {
  static const wchar_t* kHex = L"0123456789abcdef";
  std::wstring out;
  out.reserve(16);
  for (int i = 0; i < 8; ++i) {
    out.push_back(kHex[digest[i] >> 4]);
    out.push_back(kHex[digest[i] & 0x0f]);
  }
  return out;
}

bool EnsureDirectory(const std::wstring& path) {
  if (CreateDirectoryW(path.c_str(), nullptr) != 0) return true;
  const DWORD error = GetLastError();
  if (error == ERROR_ALREADY_EXISTS) return true;
  if (error != ERROR_PATH_NOT_FOUND) return false;

  const size_t slash = path.find_last_of(L'\\');
  if (slash == std::wstring::npos || slash == 0) return false;
  if (!EnsureDirectory(path.substr(0, slash))) return false;
  if (CreateDirectoryW(path.c_str(), nullptr) != 0) return true;
  return GetLastError() == ERROR_ALREADY_EXISTS;
}

bool ExtractionComplete(const std::wstring& dir) {
  const std::wstring entry = dir + L"\\" + kEntryPoint;
  const DWORD attrs = GetFileAttributesW(entry.c_str());
  if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
    return false;
  }
  const std::wstring marker = dir + L"\\" + kReadyMarker;
  return GetFileAttributesW(marker.c_str()) != INVALID_FILE_ATTRIBUTES;
}

bool WritePayloadToFile(HANDLE source, ULONGLONG offset, ULONGLONG length,
                        const std::wstring& zip_path) {
  LARGE_INTEGER pos;
  pos.QuadPart = static_cast<LONGLONG>(offset);
  if (!SetFilePointerEx(source, pos, nullptr, FILE_BEGIN)) return false;

  HANDLE zip = CreateFileW(zip_path.c_str(), GENERIC_WRITE, 0, nullptr,
                           CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (zip == INVALID_HANDLE_VALUE) return false;

  std::vector<BYTE> buffer(kReadChunk);
  ULONGLONG remaining = length;
  bool ok = true;
  while (remaining > 0) {
    const DWORD want =
        static_cast<DWORD>(remaining < kReadChunk ? remaining : kReadChunk);
    DWORD got = 0;
    if (!ReadFile(source, buffer.data(), want, &got, nullptr) || got == 0) {
      ok = false;
      break;
    }
    DWORD written = 0;
    if (!WriteFile(zip, buffer.data(), got, &written, nullptr) || written != got) {
      ok = false;
      break;
    }
    remaining -= got;
  }
  CloseHandle(zip);
  return ok;
}

int RunAndWait(const std::wstring& command_line, const std::wstring& working_dir,
               bool hide_window) {
  std::vector<wchar_t> cmd(command_line.begin(), command_line.end());
  cmd.push_back(L'\0');

  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  if (hide_window) {
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
  }
  PROCESS_INFORMATION process = {};

  const wchar_t* cwd = working_dir.empty() ? nullptr : working_dir.c_str();
  if (!CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, TRUE,
                      hide_window ? CREATE_NO_WINDOW : 0, nullptr, cwd, &startup,
                      &process)) {
    return -1;
  }

  WaitForSingleObject(process.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(process.hProcess, &code);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return static_cast<int>(code);
}

std::wstring FindTar() {
  const std::wstring system_root = Env(L"SystemRoot");
  if (system_root.empty()) return std::wstring();
  const std::wstring candidate = system_root + L"\\System32\\tar.exe";
  if (GetFileAttributesW(candidate.c_str()) != INVALID_FILE_ATTRIBUTES) {
    return candidate;
  }
  return std::wstring();
}

bool ExtractPayload(const std::wstring& exe_path, ULONGLONG offset,
                    ULONGLONG length, const std::wstring& target_dir) {
  const std::wstring tar = FindTar();
  if (tar.empty()) {
    fwprintf(stderr,
             L"error: tar.exe was not found. It is included with Windows 10 "
             L"build 17063 and later.\n");
    return false;
  }

  HANDLE source = CreateFileW(exe_path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                              nullptr);
  if (source == INVALID_HANDLE_VALUE) {
    fwprintf(stderr, L"error: cannot open the executable for reading\n");
    return false;
  }

  if (!EnsureDirectory(target_dir)) {
    CloseHandle(source);
    fwprintf(stderr, L"error: cannot create %ls\n", target_dir.c_str());
    return false;
  }

  const std::wstring zip_path = target_dir + L"\\payload.zip";
  const bool written = WritePayloadToFile(source, offset, length, zip_path);
  CloseHandle(source);
  if (!written) {
    fwprintf(stderr, L"error: cannot write the payload\n");
    return false;
  }

  const std::wstring command =
      L"\"" + tar + L"\" -x -f \"" + zip_path + L"\" -C \"" + target_dir + L"\"";
  const int code = RunAndWait(command, target_dir,  true);

  DeleteFileW(zip_path.c_str());

  if (code != 0) {
    fwprintf(stderr, L"error: extraction failed (tar exit code %d)\n", code);
    return false;
  }

  const std::wstring marker = target_dir + L"\\" + kReadyMarker;
  HANDLE handle = CreateFileW(marker.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) return false;
  CloseHandle(handle);
  return true;
}

int Launch(const std::wstring& target_dir, const std::wstring& arguments) {
  const std::wstring exe = target_dir + L"\\" + kEntryPoint;
  std::wstring command_line = L"\"" + exe + L"\"";
  if (!arguments.empty()) {
    command_line += L" ";
    command_line += arguments;
  }
  const int code = RunAndWait(command_line, target_dir,  false);
  return code < 0 ? 1 : code;
}

std::wstring RemainingArguments() {
  const wchar_t* raw = GetCommandLineW();
  if (raw == nullptr) return std::wstring();
  size_t i = 0;
  if (raw[0] == L'"') {
    ++i;
    while (raw[i] != L'\0' && raw[i] != L'"') ++i;
    if (raw[i] == L'"') ++i;
  } else {
    while (raw[i] != L'\0' && raw[i] != L' ') ++i;
  }
  while (raw[i] == L' ') ++i;
  return std::wstring(raw + i);
}

}  

int WINAPI wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int) {
  AttachParentConsole();

  const std::wstring exe_path = ExecutablePath();
  if (exe_path.empty()) {
    fwprintf(stderr, L"error: cannot determine the executable path\n");
    return 1;
  }

  HANDLE file = CreateFileW(exe_path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                            nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    fwprintf(stderr, L"error: cannot open the executable for reading\n");
    return 1;
  }

  LARGE_INTEGER file_size;
  if (!GetFileSizeEx(file, &file_size)) {
    CloseHandle(file);
    fwprintf(stderr, L"error: cannot read the executable size\n");
    return 1;
  }

  ULONGLONG payload_offset = 0;
  ULONGLONG payload_length = 0;
  BYTE digest[kDigestSize] = {};
  const bool have_payload =
      ReadTrailer(file, file_size, &payload_offset, &payload_length, digest);
  CloseHandle(file);

  if (!have_payload) {
    fwprintf(stderr,
             L"error: no payload found in this executable.\n"
             L"       Build the portable package with "
             L"tool\\build_portable_exe.ps1.\n");
    return 2;
  }

  std::wstring base = Env(L"LOCALAPPDATA");
  if (base.empty()) base = Env(L"TEMP");
  if (base.empty()) {
    fwprintf(stderr, L"error: neither LOCALAPPDATA nor TEMP is set\n");
    return 1;
  }

  const std::wstring target_dir =
      base + L"\\VMwareLocalizer\\" + PayloadTag(digest);

  if (!ExtractionComplete(target_dir)) {
    fwprintf(stderr, L"Extracting to %ls\n", target_dir.c_str());
    if (!ExtractPayload(exe_path, payload_offset, payload_length, target_dir)) {
      return 1;
    }
  }

  return Launch(target_dir, RemainingArguments());
}
