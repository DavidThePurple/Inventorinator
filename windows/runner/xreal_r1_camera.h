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
  std::vector<uint8_t> LatestFrame() const;
  std::string LastError() const;

 private:
  void ReadLoop();
  void DecodeLoop();
  bool ConnectControl();
  bool ConnectVideo();
  bool SendStartCommand();
  bool ReadStartAcknowledgement();
  bool ActivateVideoBurst();
  bool StartDecoder();
  void StopDecoder();
  static bool ReadExact(uintptr_t socket, uint8_t* buffer, size_t size);

  std::atomic<bool> running_{false};
  std::atomic<bool> available_{false};
  std::atomic<bool> streaming_{false};
  std::atomic<uint64_t> packet_count_{0};
  uintptr_t control_socket_ = 0;
  uintptr_t video_socket_ = 0;
  std::thread reader_thread_;
  std::thread decoder_thread_;
  uintptr_t decoder_process_ = 0;
  uintptr_t decoder_input_ = 0;
  uintptr_t decoder_output_ = 0;
  mutable std::mutex state_mutex_;
  std::string last_error_;
  mutable std::mutex frame_mutex_;
  std::vector<uint8_t> latest_frame_;
};

#endif  // RUNNER_XREAL_R1_CAMERA_H_
