import CEGLGLES
import DesktopTestSupport
import Foundation
import Glibc
import Testing

@testable import WaylandBridge

extension NativeSessionTests {
  @Test(arguments: [[Int32](), [-1]])
  func missingOrInvalidDMABufDescriptorsFallBackAndPreserveGLErrors(descriptors: [Int32]) throws {
    let renderer = NativeRenderer()
    try renderer.setup(input: .init(width: 8, height: 8))
    defer { renderer.cleanup() }
    let display = try unsafe #require(eglGetCurrentDisplay())
    var synchronization = unsafe DMABufSynchronization(display: display)
    glClearColor(0, 1, 0, 1)
    glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    let native = synchronization.finishRendering(descriptors: descriptors.span)
    #expect(!native)
    var pixel: [UInt8] = [0, 0, 0, 0]
    unsafe glReadPixels(0, 0, 1, 1, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixel)
    #expect(pixel == [0, 255, 0, 255])
    glEnable(GLenum(GL_ARRAY_BUFFER))
    let retried = synchronization.finishRendering(descriptors: descriptors.span)
    #expect(!retried)
    #expect(glGetError() == GL_INVALID_ENUM)
  }

  @Test(
    .enabled("Wayland dma-buf presentation is unavailable") {
      try await WaylandAvailability.presentation
    })
  func nativeFencePublishesWritesAndDoesNotLeakDescriptors() async throws {
    let host = NativeHost(configuration: .init(width: 16, height: 16))
    defer { host.cleanup() }
    try await host.connect()
    try host.setupRenderer(surfaceless: false)
    let display = try unsafe #require(eglGetCurrentDisplay())
    let context = try unsafe #require(eglGetCurrentContext())
    var target = try unsafe DMABufTarget.create(
      display: display, context: context, connection: host.connection, width: 16, height: 16,
      popup: false, device: host.renderer.device, preferences: host.connection.dmabufPreferences,
      rejected: [])
    defer { target.close() }
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), target.framebuffer)
    var synchronization = unsafe DMABufSynchronization(display: display)
    // Warm up driver state before checking per-frame descriptor ownership.
    glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    let native = target.finishRendering(using: &synchronization)
    let before = try FileManager.default.contentsOfDirectory(atPath: "/proc/self/fd").count
    for index in 0..<24 {
      glClearColor(index.isMultiple(of: 2) ? 1 : 0, 0, 1, 1)
      glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
      let published = target.finishRendering(using: &synchronization)
      #expect(published == native)
      var pixel: [UInt8] = [0, 0, 0, 0]
      unsafe glReadPixels(0, 0, 1, 1, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixel)
      #expect(pixel == [index.isMultiple(of: 2) ? 255 : 0, 0, 255, 255])
    }
    #expect(glGetError() == GL_NO_ERROR)
    #expect(try FileManager.default.contentsOfDirectory(atPath: "/proc/self/fd").count == before)
    nativeLog("dma-buf synchronization test: \(native ? "native fence" : "glFinish fallback")")
  }
}
