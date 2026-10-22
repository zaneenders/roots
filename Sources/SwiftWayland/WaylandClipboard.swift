import Foundation
import Glibc
import SystemPackage

@MainActor final class WaylandClipboard {
  static let textTypes = ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING"]
  private let objects: WaylandObjects
  var manager: UInt32 = 0
  private var device: UInt32 = 0
  private var offers: [UInt32: Set<String>] = [:]
  private var pendingOffers: Set<UInt32> = []
  private var selection: UInt32 = 0
  private var drag: UInt32 = 0
  private var source: UInt32 = 0
  private var payload: [UInt8] = []
  var serial: UInt32?
  var focused = false
  init(objects: WaylandObjects) { self.objects = objects }

  func attach(seat: UInt32) {
    guard device == 0, manager != 0 else { return }
    device = objects.create(manager, 1, "wl_data_device", [.uint(seat)])
  }
  private func retire(_ id: UInt32) {
    guard id != 0, offers.removeValue(forKey: id) != nil else { return }
    pendingOffers.remove(id)
    objects.request(id, 2)
  }
  func event(_ message: WireMessage) {
    let a = message.arguments
    if message.opcode == 0, objects.interfaces[message.object] == "wl_data_device",
      message.object != device
    {
      objects.register(a[0].word, "wl_data_offer")
      objects.request(a[0].word, 2)
      return
    }
    if message.object == device {
      switch message.opcode {
      case 0:
        let id = a[0].word
        objects.register(id, "wl_data_offer")
        offers[id] = []
        pendingOffers.insert(id)
      case 1:
        retire(drag)
        drag = a[4].word
        pendingOffers.remove(drag)
      case 2, 4:
        retire(drag)
        drag = 0
      case 5:
        retire(selection)
        selection = a[0].word
        pendingOffers.remove(selection)
      default: break
      }
    } else if offers[message.object] != nil, message.opcode == 0, let mime = a[0].text {
      _ = offers[message.object, default: []].insert(mime)
    } else if message.object == source {
      if message.opcode == 1, case .fd(let fd) = a[1] {
        guard let mime = a[0].text, Self.textTypes.contains(mime) else {
          fd.close()
          return
        }
        let bytes = payload
        let descriptor = fd.take()
        Task.detached(executorPreference: BlockingIOExecutor.shared) {
          ClipboardTransfer.write(bytes, to: descriptor)
        }
      } else if message.opcode == 2 {
        objects.request(source, 1)
        source = 0
        payload.removeAll()
      }
    }
  }
  func write(_ text: String) -> Bool {
    guard focused, let serial, manager != 0, device != 0,
      text.utf8.count <= ClipboardTransfer.maximumBytes
    else {
      return false
    }
    objects.request(source, 1)
    source = objects.create(manager, 0, "wl_data_source")
    payload = Array(text.utf8)
    for mime in Self.textTypes { objects.request(source, 0, [.string(mime)]) }
    objects.request(device, 1, [.uint(source), .uint(serial)])
    return true
  }
  func beginRead() -> Int32? {
    guard focused, let types = offers[selection],
      let mime = Self.textTypes.first(where: types.contains)
    else {
      return nil
    }
    guard let pipe = try? FileDescriptor.pipe(options: .closeOnExec) else { return nil }
    let read = WireDescriptor(taking: pipe.readEnd.rawValue)
    let write = WireDescriptor(taking: pipe.writeEnd.rawValue)
    guard fcntl(pipe.readEnd.rawValue, F_SETFL, O_NONBLOCK) == 0 else { return nil }
    objects.request(selection, 1, [.string(mime), .fd(write)])
    return read.take()
  }
  func detachSeat() {
    for id in Array(offers.keys) { retire(id) }
    objects.retire(device)
    device = 0
    selection = 0
    drag = 0
    serial = nil
    focused = false
  }
  func close() {
    detachSeat()
    objects.request(source, 1)
    source = 0
    payload.removeAll()
    objects.retire(manager)
    manager = 0
  }
}
enum ClipboardTransfer {
  static let maximumBytes = 16 * 1024 * 1024

  static func read(from fd: Int32) -> String? {
    defer { _ = Glibc.close(fd) }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 8192)
    while !Task.isCancelled, ContinuousClock.now < deadline {
      let count = unsafe Glibc.read(fd, &buffer, buffer.count)
      if count == 0 { return String(bytes: bytes, encoding: .utf8) }
      if count > 0 {
        guard bytes.count + count <= maximumBytes else { return nil }
        bytes.append(contentsOf: buffer.prefix(count))
      } else if errno == EAGAIN {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        _ = unsafe poll(&descriptor, 1, 100)
      } else if errno != EINTR {
        return nil
      }
    }
    return nil
  }

  static func write(_ bytes: [UInt8], to fd: Int32) {
    let descriptor = FileDescriptor(rawValue: fd)
    defer { try? descriptor.close() }
    guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { return }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    bytes.withUnsafeBytes { buffer in
      var offset = 0
      while offset < buffer.count, ContinuousClock.now < deadline {
        do {
          let count = try unsafe writeWithoutSIGPIPE(
            UnsafeRawBufferPointer(rebasing: buffer[offset...]), to: descriptor)
          guard count > 0 else { return }
          offset += count
        } catch let error as Errno where error == .resourceTemporarilyUnavailable {
          var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
          _ = unsafe poll(&descriptor, 1, 100)
        } catch let error as Errno where error == .interrupted {
          continue
        } catch {
          return
        }
      }
    }
  }

  static func writeWithoutSIGPIPE(_ buffer: UnsafeRawBufferPointer, to descriptor: FileDescriptor)
    throws -> Int
  {
    var blocked = sigset_t()
    var previous = sigset_t()
    var pending = sigset_t()
    _ = unsafe sigemptyset(&blocked)
    _ = unsafe sigaddset(&blocked, SIGPIPE)
    let error = unsafe pthread_sigmask(SIG_BLOCK, &blocked, &previous)
    guard error == 0 else { throw Errno(rawValue: error) }
    defer { _ = unsafe pthread_sigmask(SIG_SETMASK, &previous, nil) }
    guard unsafe sigpending(&pending) == 0 else { throw Errno(rawValue: errno) }
    let wasPending = unsafe sigismember(&pending, SIGPIPE) == 1
    do {
      return try unsafe descriptor.write(buffer, retryOnInterrupt: false)
    } catch {
      if let error = error as? Errno, error == .brokenPipe, !wasPending {
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        while unsafe sigtimedwait(&blocked, nil, &timeout) < 0 && errno == EINTR {}
      }
      throw error
    }
  }
}
