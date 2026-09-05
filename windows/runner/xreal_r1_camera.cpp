#include "xreal_r1_camera.h"

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <array>
#include <filesystem>

namespace {
constexpr char kR1Address[] = "169.254.2.1";
constexpr uint16_t kControlPort = 52999;
constexpr uint16_t kVideoPort = 52995;
constexpr std::array<uint8_t, 12> kStartCommand = {
    0x27, 0x81, 0x00, 0x00, 0x00, 0x06, 0x80, 0x00, 0x00, 0x01, 0x1a, 0x00};

SOCKET AsSocket(uintptr_t value) { return static_cast<SOCKET>(value); }
uintptr_t FromSocket(SOCKET value) { return static_cast<uintptr_t>(value); }

HANDLE AsHandle(uintptr_t value) { return reinterpret_cast<HANDLE>(value); }
uintptr_t FromHandle(HANDLE value) { return reinterpret_cast<uintptr_t>(value); }

std::wstring FindFfmpeg() {
  wchar_t module_path[MAX_PATH];
  const auto length = GetModuleFileNameW(nullptr, module_path, MAX_PATH);
  if (length > 0 && length < MAX_PATH) {
    const auto bundled = std::filesystem::path(module_path).parent_path() / L"ffmpeg.exe";
    if (GetFileAttributesW(bundled.c_str()) != INVALID_FILE_ATTRIBUTES) return bundled.wstring();
  }
  const std::filesystem::path krita = L"C:\\Program Files\\Krita (x64)\\bin\\ffmpeg.exe";
  if (GetFileAttributesW(krita.c_str()) != INVALID_FILE_ATTRIBUTES) return krita.wstring();
  return {};
}
}  // namespace

XrealR1Camera::XrealR1Camera() {
  WSADATA data;
  if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
    last_error_ = "Windows networking could not be initialized.";
  }
}

XrealR1Camera::~XrealR1Camera() {
  Stop();
  WSACleanup();
}

bool XrealR1Camera::ConnectControl() {
  SOCKET socket = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (socket == INVALID_SOCKET) return false;
  sockaddr_in address{};
  address.sin_family = AF_INET;
  address.sin_port = htons(kControlPort);
  inet_pton(AF_INET, kR1Address, &address.sin_addr);
  if (connect(socket, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == SOCKET_ERROR) {
    closesocket(socket);
    return false;
  }
  control_socket_ = FromSocket(socket);
  return true;
}

bool XrealR1Camera::ConnectVideo() {
  SOCKET socket = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (socket == INVALID_SOCKET) return false;
  sockaddr_in address{};
  address.sin_family = AF_INET;
  address.sin_port = htons(kVideoPort);
  inet_pton(AF_INET, kR1Address, &address.sin_addr);
  if (connect(socket, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == SOCKET_ERROR) {
    closesocket(socket);
    return false;
  }
  video_socket_ = FromSocket(socket);
  return true;
}

bool XrealR1Camera::SendStartCommand() {
  const auto sent = send(AsSocket(control_socket_), reinterpret_cast<const char*>(kStartCommand.data()),
                         static_cast<int>(kStartCommand.size()), 0);
  return sent == static_cast<int>(kStartCommand.size());
}

bool XrealR1Camera::Start() {
  Stop();
  // R1 expects the video connection to be established before the control
  // connection. The start command also has a framed acknowledgement that must
  // be consumed before reading the video stream.
  if (!ConnectVideo() || !ConnectControl() || !SendStartCommand()) {
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      last_error_ = "ROG XREAL R1 camera transport was not reachable.";
    }
    Stop();
    return false;
  }
  uint8_t acknowledgement[12];
  if (!ReadExact(control_socket_, acknowledgement, sizeof(acknowledgement)) ||
      acknowledgement[0] != 0x27 || acknowledgement[1] != 0x81) {
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      last_error_ = "ROG XREAL R1 rejected the camera-start request.";
    }
    Stop();
    return false;
  }
  if (!StartDecoder()) {
    Stop();
    return false;
  }
  available_ = true;
  streaming_ = true;
  running_ = true;
  packet_count_ = 0;
  reader_thread_ = std::thread(&XrealR1Camera::ReadLoop, this);
  return true;
}

void XrealR1Camera::Stop() {
  running_ = false;
  if (video_socket_ != 0) {
    shutdown(AsSocket(video_socket_), SD_BOTH);
    closesocket(AsSocket(video_socket_));
    video_socket_ = 0;
  }
  if (control_socket_ != 0) {
    shutdown(AsSocket(control_socket_), SD_BOTH);
    closesocket(AsSocket(control_socket_));
    control_socket_ = 0;
  }
  if (reader_thread_.joinable()) reader_thread_.join();
  StopDecoder();
  streaming_ = false;
  available_ = false;
}

bool XrealR1Camera::StartDecoder() {
  const auto ffmpeg = FindFfmpeg();
  if (ffmpeg.empty()) {
    std::lock_guard<std::mutex> lock(state_mutex_);
    last_error_ = "XREAL R1 needs ffmpeg.exe for native HEVC decoding.";
    return false;
  }
  SECURITY_ATTRIBUTES attributes{sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE};
  HANDLE stdin_read = nullptr, stdin_write = nullptr;
  HANDLE stdout_read = nullptr, stdout_write = nullptr;
  if (!CreatePipe(&stdin_read, &stdin_write, &attributes, 0) ||
      !CreatePipe(&stdout_read, &stdout_write, &attributes, 0)) {
    if (stdin_read) CloseHandle(stdin_read);
    if (stdin_write) CloseHandle(stdin_write);
    if (stdout_read) CloseHandle(stdout_read);
    if (stdout_write) CloseHandle(stdout_write);
    return false;
  }
  SetHandleInformation(stdin_write, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(stdout_read, HANDLE_FLAG_INHERIT, 0);
  std::wstring command = L"\"" + ffmpeg +
      L"\" -loglevel error -f hevc -i pipe:0 -f mjpeg -q:v 5 pipe:1";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = stdin_read;
  startup.hStdOutput = stdout_write;
  startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(nullptr, command.data(), nullptr, nullptr, TRUE,
                      CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
    CloseHandle(stdin_read); CloseHandle(stdin_write);
    CloseHandle(stdout_read); CloseHandle(stdout_write);
    std::lock_guard<std::mutex> lock(state_mutex_);
    last_error_ = "Could not start the native HEVC decoder.";
    return false;
  }
  CloseHandle(process.hThread);
  CloseHandle(stdin_read);
  CloseHandle(stdout_write);
  decoder_process_ = FromHandle(process.hProcess);
  decoder_input_ = FromHandle(stdin_write);
  decoder_output_ = FromHandle(stdout_read);
  decoder_thread_ = std::thread(&XrealR1Camera::DecodeLoop, this);
  return true;
}

void XrealR1Camera::StopDecoder() {
  if (decoder_input_ != 0) {
    CloseHandle(AsHandle(decoder_input_));
    decoder_input_ = 0;
  }
  if (decoder_output_ != 0) {
    CloseHandle(AsHandle(decoder_output_));
    decoder_output_ = 0;
  }
  if (decoder_thread_.joinable()) decoder_thread_.join();
  if (decoder_process_ != 0) {
    TerminateProcess(AsHandle(decoder_process_), 0);
    CloseHandle(AsHandle(decoder_process_));
    decoder_process_ = 0;
  }
}

bool XrealR1Camera::ReadExact(uintptr_t socket_value, uint8_t* buffer, size_t size) {
  size_t received = 0;
  while (received < size) {
    const int count = recv(AsSocket(socket_value), reinterpret_cast<char*>(buffer + received),
                           static_cast<int>(size - received), 0);
    if (count <= 0) return false;
    received += static_cast<size_t>(count);
  }
  return true;
}

void XrealR1Camera::ReadLoop() {
  while (running_) {
    uint8_t header[6];
    if (!ReadExact(video_socket_, header, sizeof(header))) break;
    const uint32_t payload_size = (static_cast<uint32_t>(header[2]) << 24) |
                                  (static_cast<uint32_t>(header[3]) << 16) |
                                  (static_cast<uint32_t>(header[4]) << 8) | header[5];
    if (payload_size == 0 || payload_size > 16 * 1024 * 1024) break;
    std::vector<uint8_t> payload(payload_size);
    if (!ReadExact(video_socket_, payload.data(), payload.size())) break;
    if (header[0] == 0x27 && header[1] == 0x85) {
      ++packet_count_;
      size_t start = std::string::npos;
      for (size_t i = 80; i + 4 < payload.size() && i < 120; ++i) {
        if (payload[i] == 0 && payload[i + 1] == 0 && payload[i + 2] == 0 &&
            payload[i + 3] == 1) {
          start = i;
          break;
        }
      }
      if (start != std::string::npos && decoder_input_ != 0) {
        DWORD written = 0;
        WriteFile(AsHandle(decoder_input_), payload.data() + start,
                  static_cast<DWORD>(payload.size() - start), &written, nullptr);
      }
    }
  }
  streaming_ = false;
  if (running_) {
    std::lock_guard<std::mutex> lock(state_mutex_);
    last_error_ = "ROG XREAL R1 camera stream disconnected.";
  }
}

void XrealR1Camera::DecodeLoop() {
  std::vector<uint8_t> buffer;
  std::array<uint8_t, 8192> chunk;
  DWORD read = 0;
  while (decoder_output_ != 0 && ReadFile(AsHandle(decoder_output_), chunk.data(),
                                          static_cast<DWORD>(chunk.size()), &read, nullptr) &&
         read > 0) {
    buffer.insert(buffer.end(), chunk.begin(), chunk.begin() + read);
    while (true) {
      size_t start = std::string::npos;
      for (size_t i = 0; i + 1 < buffer.size(); ++i) {
        if (buffer[i] == 0xff && buffer[i + 1] == 0xd8) { start = i; break; }
      }
      if (start == std::string::npos) {
        if (buffer.size() > 1) buffer.erase(buffer.begin(), buffer.end() - 1);
        break;
      }
      size_t end = std::string::npos;
      for (size_t i = start + 2; i + 1 < buffer.size(); ++i) {
        if (buffer[i] == 0xff && buffer[i + 1] == 0xd9) { end = i + 2; break; }
      }
      if (end == std::string::npos) {
        if (start > 0) buffer.erase(buffer.begin(), buffer.begin() + start);
        break;
      }
      {
        std::lock_guard<std::mutex> lock(frame_mutex_);
        latest_frame_.assign(buffer.begin() + start, buffer.begin() + end);
      }
      buffer.erase(buffer.begin(), buffer.begin() + end);
    }
  }
}

bool XrealR1Camera::IsAvailable() const { return available_; }
bool XrealR1Camera::IsStreaming() const { return streaming_; }
uint64_t XrealR1Camera::PacketCount() const { return packet_count_; }
std::vector<uint8_t> XrealR1Camera::LatestFrame() const {
  std::lock_guard<std::mutex> lock(frame_mutex_);
  return latest_frame_;
}
std::string XrealR1Camera::LastError() const {
  std::lock_guard<std::mutex> lock(state_mutex_);
  return last_error_;
}
