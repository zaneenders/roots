import CWaylandTransport
import Glibc
import SystemPackage

// C only exposes the ancillary-data macros; Swift owns I/O and descriptor lifetimes.
enum UnixSocket {
  // Linux's SCM_MAX_FD limit for a single SCM_RIGHTS transfer.
  static let maximumDescriptors = 253

  static func prepareConnected(_ socket: Int32) throws {
    var address = sockaddr_storage()
    var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
    let connected = withUnsafeMutablePointer(to: &address) {
      unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        unsafe getpeername(socket, $0, &length)
      }
    }
    var type: Int32 = 0
    var typeLength = socklen_t(MemoryLayout<Int32>.size)
    guard connected == 0, address.ss_family == sa_family_t(AF_UNIX),
      unsafe getsockopt(socket, SOL_SOCKET, SO_TYPE, &type, &typeLength) == 0,
      type == Int32(SOCK_STREAM.rawValue)
    else { throw WaylandError.connection }
    let flags = fcntl(socket, F_GETFL)
    let descriptorFlags = fcntl(socket, F_GETFD)
    guard flags >= 0, descriptorFlags >= 0,
      fcntl(socket, F_SETFL, flags | O_NONBLOCK) == 0,
      fcntl(socket, F_SETFD, descriptorFlags | FD_CLOEXEC) == 0
    else { throw WaylandError.connection }
  }

  static func receive(
    _ socket: Int32, into bytes: inout [UInt8], descriptorLimit: Int = maximumDescriptors
  ) throws -> (count: Int, descriptors: [WireDescriptor]) {
    precondition((0...maximumDescriptors).contains(descriptorLimit))
    return try withUnsafeTemporaryAllocation(
      byteCount: cwt_control_space(descriptorLimit * MemoryLayout<Int32>.stride),
      alignment: MemoryLayout<cmsghdr>.alignment
    ) { control in
      try bytes.withUnsafeMutableBytes { buffer in
        var vector = unsafe iovec(iov_base: buffer.baseAddress, iov_len: buffer.count)
        return try withUnsafeMutablePointer(to: &vector) { vector in
          var message = unsafe msghdr()
          unsafe message.msg_iov = vector
          unsafe message.msg_iovlen = 1
          unsafe message.msg_control = control.baseAddress
          unsafe message.msg_controllen = control.count
          let count = unsafe recvmsg(socket, &message, Int32(MSG_DONTWAIT | MSG_CMSG_CLOEXEC))
          guard count >= 0 else { throw Errno(rawValue: errno) }
          var descriptors: [WireDescriptor] = []
          var header = unsafe cwt_first_header(&message)
          while let current = unsafe header {
            if unsafe current.pointee.cmsg_level == SOL_SOCKET,
              unsafe current.pointee.cmsg_type == SCM_RIGHTS
            {
              let size = unsafe current.pointee.cmsg_len - cwt_control_length(0)
              let data = unsafe cwt_control_data(current)!
              for offset in stride(from: 0, to: size, by: MemoryLayout<Int32>.stride) {
                let fd = unsafe data.loadUnaligned(fromByteOffset: offset, as: Int32.self)
                descriptors.append(WireDescriptor(taking: fd))
              }
            }
            unsafe header = cwt_next_header(&message, current)
          }
          guard unsafe message.msg_flags & Int32(MSG_CTRUNC) == 0,
            descriptors.count <= descriptorLimit
          else {
            for descriptor in descriptors { descriptor.close() }
            throw Errno.messageTooLong
          }
          return (count, descriptors)
        }
      }
    }
  }

  static func send(_ socket: Int32, bytes: UnsafeRawBufferPointer, descriptors: [Int32]) throws -> Int {
    guard descriptors.count <= maximumDescriptors else { throw Errno.messageTooLong }
    return try withUnsafeTemporaryAllocation(
      byteCount: cwt_control_space(descriptors.count * MemoryLayout<Int32>.stride),
      alignment: MemoryLayout<cmsghdr>.alignment
    ) { control in
      unsafe control.initializeMemory(as: UInt8.self, repeating: 0)
      var vector = unsafe iovec(
        iov_base: UnsafeMutableRawPointer(mutating: bytes.baseAddress), iov_len: bytes.count)
      return try withUnsafeMutablePointer(to: &vector) { vector in
        var message = unsafe msghdr()
        unsafe message.msg_iov = vector
        unsafe message.msg_iovlen = 1
        if !descriptors.isEmpty {
          unsafe message.msg_control = control.baseAddress
          unsafe message.msg_controllen = control.count
          let header = unsafe cwt_first_header(&message)!
          unsafe header.pointee.cmsg_level = SOL_SOCKET
          unsafe header.pointee.cmsg_type = Int32(SCM_RIGHTS)
          unsafe header.pointee.cmsg_len = cwt_control_length(descriptors.count * MemoryLayout<Int32>.stride)
          descriptors.withUnsafeBytes {
            _ = unsafe memcpy(cwt_control_data(header), $0.baseAddress!, $0.count)
          }
        }
        let count = unsafe sendmsg(socket, &message, Int32(MSG_DONTWAIT | MSG_NOSIGNAL))
        guard count >= 0 else { throw Errno(rawValue: errno) }
        return count
      }
    }
  }
}
