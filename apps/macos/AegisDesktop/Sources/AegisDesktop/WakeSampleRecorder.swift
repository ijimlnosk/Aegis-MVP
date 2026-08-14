import AVFoundation
import Foundation

final class WakeSampleRecorder: NSObject, AVAudioRecorderDelegate {
  private var recorder: AVAudioRecorder?
  private var completion: ((URL?) -> Void)?

  func capture(label: String, completion: @escaping (URL?) -> Void) {
    self.completion = completion
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "Aegis/wake-samples")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: "\(label)-\(UUID().uuidString).caf")
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                                   AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16]
    AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
      guard granted, let self else { return completion(nil) }
      DispatchQueue.main.async {
        do {
          self.recorder = try AVAudioRecorder(url: url, settings: settings)
          self.recorder?.delegate = self
          self.recorder?.record(forDuration: 2.5)
        } catch { completion(nil) }
      }
    }
  }

  func audioRecorderDidFinishRecording(_: AVAudioRecorder, successfully _: Bool) {
    let url = recorder?.url
    recorder = nil
    completion?(url)
    completion = nil
  }
}
