#include "xreal_r1_camera.h"

#include <winsock2.h>
#include <ws2tcpip.h>

#include <array>

namespace {
constexpr char kR1Address[] = "169.254.2.1";
constexpr uint16_t kControlPort = 52999;
constexpr uint16_t kVideoPort = 52995;
constexpr std::array<uint8_t, 12> kStartCommand = {
    0x27, 0x81, 0x00, 0x00, 0x00, 0x06, 0x80, 0x00, 0x00, 0x01, 0x1a, 0x00};

SOCKET AsSocket(uintptr_t value) { return static_cast<SOCKET>(value); }
uintptr_t FromSocket(SOCKET value) { return static_cast<uintptr_t>(value); }
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
  if (!ConnectControl() || !ConnectVideo() || !SendStartCommand()) {
    std::lock_guard<std::mutex> lock(state_mutex_);
    last_error_ = "ROG XREAL R1 camera transport was not reachable.";
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
  streaming_ = false;
  available_ = false;
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
    if (header[0] == 0x27 && header[1] == 0x85) ++packet_count_;
  }
  streaming_ = false;
  if (running_) {
    std::lock_guard<std::mutex> lock(state_mutex_);
    last_error_ = "ROG XREAL R1 camera stream disconnected.";
  }
}

bool XrealR1Camera::IsAvailable() const { return available_; }
bool XrealR1Camera::IsStreaming() const { return streaming_; }
uint64_t XrealR1Camera::PacketCount() const { return packet_count_; }
std::string XrealR1Camera::LastError() const {
  std::lock_guard<std::mutex> lock(state_mutex_);
  return last_error_;
}
