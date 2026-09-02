import Metal
import UIKit
import OSLog

/// Runs `FoodScene.metal` once and hands back a photograph.
///
/// Two compute passes: the first path-marches the scene at twice the output resolution,
/// the second resolves it — downsampling for antialiasing, applying depth of field from
/// the depth channel, grading, and adding grain.
///
/// This is far too expensive for a frame budget and that is the point. It runs once per
/// food, off the main actor, and the JPEG it produces is cached exactly like a
/// generated photograph, so nothing ever pays for it twice.
final class FoodSceneRenderer: @unchecked Sendable {
    static let shared = FoodSceneRenderer()

    /// Bump when the shader changes: it is part of the cache key, so old renders are
    /// superseded rather than lingering next to new ones in the same catalog.
    static let version = 6

    private let logger = Logger(subsystem: "com.plate.Plate", category: "FoodScene")
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let renderPipeline: MTLComputePipelineState?
    private let resolvePipeline: MTLComputePipelineState?

    /// Serialises dispatches. Several foods can be logged at once and there is no
    /// reason to have four of these fighting for the GPU.
    private let lock = NSLock()

    private init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let renderFunction = library.makeFunction(name: "foodSceneRender"),
              let resolveFunction = library.makeFunction(name: "foodSceneResolve"),
              let renderPipeline = try? device.makeComputePipelineState(function: renderFunction),
              let resolvePipeline = try? device.makeComputePipelineState(function: resolveFunction)
        else {
            self.device = nil
            self.queue = nil
            self.renderPipeline = nil
            self.resolvePipeline = nil
            Logger(subsystem: "com.plate.Plate", category: "FoodScene")
                .error("Metal unavailable; procedural imagery disabled")
            return
        }

        self.device = device
        self.queue = queue
        self.renderPipeline = renderPipeline
        self.resolvePipeline = resolvePipeline
    }

    var isAvailable: Bool { device != nil }

    /// Layout must match `FoodSceneParams` in the shader exactly. The two floats of
    /// padding put `foodPrimary` on the 16-byte boundary Metal requires for a float4.
    private struct Params {
        var resolution: SIMD2<Float>
        var seed: Float
        var vessel: Int32
        var texture: Int32
        var pieceCount: Int32
        var padding: SIMD2<Float> = .zero
        var foodPrimary: SIMD4<Float>
        var foodSecondary: SIMD4<Float>
        var ground: SIMD4<Float>
        var baseColour: SIMD4<Float>
        var roughness: Float
        var subsurface: Float
        var focusBlur: Float
        var grain: Float
    }

    /// Renders `recipe` at `size` points square. Blocking; call it off the main actor.
    func render(_ recipe: FoodSceneRecipe, size: Int = 768) -> UIImage? {
        guard let device, let queue, let renderPipeline, let resolvePipeline else { return nil }

        lock.lock()
        defer { lock.unlock() }

        let supersample = 2
        let renderSize = size * supersample
        let started = CFAbsoluteTimeGetCurrent()

        // rgba16Float for the render target: the depth channel needs range far beyond
        // 0…1, and the colour is still in linear light at this stage.
        let renderDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: renderSize,
            height: renderSize,
            mipmapped: false
        )
        renderDescriptor.usage = [.shaderWrite, .shaderRead]
        renderDescriptor.storageMode = .private

        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        outputDescriptor.usage = [.shaderWrite, .shaderRead]
        outputDescriptor.storageMode = .shared

        guard let sceneTexture = device.makeTexture(descriptor: renderDescriptor),
              let outputTexture = device.makeTexture(descriptor: outputDescriptor),
              let commands = queue.makeCommandBuffer()
        else { return nil }

        var params = Params(
            resolution: SIMD2(Float(renderSize), Float(renderSize)),
            seed: Float(recipe.seed % 9973) / 37.0,
            vessel: Int32(recipe.vessel.shaderValue),
            texture: recipe.texture.shaderValue,
            pieceCount: recipe.texture.pieceCount,
            foodPrimary: recipe.primary,
            foodSecondary: recipe.secondary,
            ground: recipe.ground,
            baseColour: recipe.base,
            roughness: recipe.texture.roughness,
            subsurface: recipe.texture.subsurface,
            focusBlur: 1.35,
            grain: 0.016
        )

        if let encoder = commands.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(renderPipeline)
            encoder.setTexture(sceneTexture, index: 0)
            encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
            dispatch(encoder, pipeline: renderPipeline, width: renderSize, height: renderSize)
            encoder.endEncoding()
        }

        if let encoder = commands.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(resolvePipeline)
            encoder.setTexture(sceneTexture, index: 0)
            encoder.setTexture(outputTexture, index: 1)
            encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
            dispatch(encoder, pipeline: resolvePipeline, width: size, height: size)
            encoder.endEncoding()
        }

        commands.commit()
        commands.waitUntilCompleted()

        if let error = commands.error {
            logger.error("Render failed: \(error.localizedDescription)")
            return nil
        }

        let image = makeImage(from: outputTexture, size: size)
        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
        logger.info("Rendered \(recipe.texture.rawValue, privacy: .public) in \(Int(elapsed))ms")
        return image
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder,
                          pipeline: MTLComputePipelineState,
                          width: Int,
                          height: Int) {
        let threadWidth = pipeline.threadExecutionWidth
        let threadHeight = max(pipeline.maxTotalThreadsPerThreadgroup / threadWidth, 1)
        let threadgroup = MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        let groups = MTLSize(
            width: (width + threadWidth - 1) / threadWidth,
            height: (height + threadHeight - 1) / threadHeight,
            depth: 1
        )
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadgroup)
    }

    private func makeImage(from texture: MTLTexture, size: Int) -> UIImage? {
        let bytesPerRow = size * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * size)
        texture.getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )

        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(
                width: size,
                height: size,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                // bgra8Unorm, so the byte order is little-endian 32-bit with alpha first.
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                         | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
