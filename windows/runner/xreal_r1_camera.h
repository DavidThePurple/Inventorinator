#ifndef RUNNER_XREAL_R1_CAMERA_H_
#define RUNNER_XREAL_R1_CAMERA_H_

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class XrealR1Camera {
 public:
  XrealR1Camera();
  ~XrealR1Camera();

  bool Start();
  void Stop();
  bool IsAvailable() const;
  bool IsStreaming() const;
  uint64_t PacketCount() const;
  std::string LastError() const;

 private:
  void ReadLoop();
  bool ConnectControl();
  bool ConnectVideo();
  bool SendStartCommand();
  static bool ReadExact(uintptr_t socket, uint8_t* buffer, size_t size);

  std::atomic<bool> running_{false};
  std::atomic<bool> available_{false};
  std::atomic<bool> streaming_{false};
  std::atomic<uint64_t> packet_count_{0};
  uintptr_t control_socket_ = 0;
  uintptr_t video_socket_ = 0;
  std::thread reader_thread_;
  mutable std::mutex state_mutex_;
  std::string last_error_;
};

#endif  // RUNNER_XREAL_R1_CAMERA_H_
