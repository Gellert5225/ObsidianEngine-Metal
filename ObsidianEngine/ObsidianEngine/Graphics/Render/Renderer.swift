//
//  ShapeRenderer.swift
//  ObsidianEngine
//
//  Created by Gellert on 6/8/18.
//  Copyright © 2018 Gellert. All rights reserved.
//

import Foundation
import Metal
import MetalKit

open class OBSDRenderer: NSObject {
    
    static var metalDevice: MTLDevice!
    static var library: MTLLibrary!
    static var colorPixelFormat: MTLPixelFormat!
    static var commandQueue: MTLCommandQueue!
    static var commandBuffer: MTLCommandBuffer?
    static var drawableSize: CGSize!
    
    var renderPassDescriptor: MTLRenderPassDescriptor!
    
    var metalLayer: CAMetalLayer!
    var depthStencilState: MTLDepthStencilState!
    
    var shadowTexture: MTLTexture!
    let shadowRenderPassDescriptor = MTLRenderPassDescriptor()
    var shadowPipelineState: MTLRenderPipelineState!
    
    var albedoTexture: MTLTexture!
    var normalTexture: MTLTexture!
    var positionTexture: MTLTexture!
    var depthTexture: MTLTexture!
    
    var gBufferPipelineState: MTLRenderPipelineState!
    var gBufferRenderPassDescriptor: MTLRenderPassDescriptor!
    var gBufferRenderPipelineDescriptor: MTLRenderPipelineDescriptor!
    
    var compositionPipelineState: MTLRenderPipelineState!
    
    //var reflectionRenderPass: RenderPass
    
    var quadVerticesBuffer: MTLBuffer!
    var quadTexCoordBuffer: MTLBuffer!
    
    let quadVertices: [Float] = [
        -1.0,  1.0,
         1.0, -1.0,
        -1.0, -1.0,
        -1.0,  1.0,
         1.0,  1.0,
         1.0, -1.0
    ]
    
    let quadTexCoords: [Float] = [
        0.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
        0.0, 0.0,
        1.0, 0.0,
        1.0, 1.0
    ]
    
    var samplerState: MTLSamplerState?
    
    var scene: OBSDScene?
    
    public init(with device: MTLDevice, metalView: MTKView) {
        OBSDRenderer.commandQueue = device.makeCommandQueue()
        OBSDRenderer.metalDevice = device
        OBSDRenderer.colorPixelFormat = metalView.colorPixelFormat
        OBSDRenderer.drawableSize = metalView.drawableSize
        
        super.init()
        
        metalView.depthStencilPixelFormat = .depth32Float
        let frameworkBundle = Bundle(for: OBSDShape.self)
        guard let defaultLibrary = try? device.makeDefaultLibrary(bundle: frameworkBundle) else {
            fatalError("Could not load default library from specified bundle")
        }
        OBSDRenderer.library = defaultLibrary
        print("Metal Device: \(device.name)")
                
        renderPassDescriptor = MTLRenderPassDescriptor()
        
        buildDepthStencilState()
        buildShadowTexture(size: metalView.drawableSize)
        buildShadowPipelineState()
        
        buildGBufferRenderPassDescriptor(size: metalView.drawableSize, descriptor: renderPassDescriptor)
        //buildGbufferPipelineState()
        gBufferRenderPipelineDescriptor = MTLRenderPipelineDescriptor()
        
        quadVerticesBuffer = OBSDRenderer.metalDevice.makeBuffer(bytes: quadVertices, length: MemoryLayout<Float>.size * quadVertices.count, options: [])
        quadVerticesBuffer.label = "Quad vertices"
        
        quadTexCoordBuffer = OBSDRenderer.metalDevice.makeBuffer(bytes: quadTexCoords, length: MemoryLayout<Float>.size * quadTexCoords.count, options: [])
        quadTexCoordBuffer.label = "Quad texCoords"
        
        buildCompositionPipelineState()
    }
    
    fileprivate func buildDepthStencilState() {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilState = OBSDRenderer.metalDevice.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
    
    func buildTexture(pixelFormat: MTLPixelFormat, size: CGSize, label: String) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: Int(size.width), height: Int(size.height), mipmapped: false)
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        guard let texture = OBSDRenderer.metalDevice.makeTexture(descriptor: descriptor) else {
            fatalError()
        }
        texture.label = "\(label) texture"
        return texture
    }
    
    func buildShadowTexture(size: CGSize) {
        shadowTexture = buildTexture(pixelFormat: .depth32Float, size: size, label: "Shadow")
        shadowRenderPassDescriptor.setUpDepthAttachment(texture: shadowTexture)
    }
    
    func buildShadowPipelineState() {
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = OBSDRenderer.library.makeFunction(name: "vertex_depth")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .invalid
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(OBSDModel.defaultVertexDescriptor)
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        do {
            shadowPipelineState = try OBSDRenderer.metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    func renderShadowPass(renderEncoder: MTLRenderCommandEncoder) {
        guard let scene = scene else { return }
        
        renderEncoder.pushDebugGroup("Shadow pass")
        renderEncoder.label = "Shadow encoder"
        renderEncoder.setCullMode(.none)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setDepthBias(0.01, slopeScale: 1.0, clamp: 0.01)
        scene.uniforms.projectionMatrix = float4x4(orthoLeft: -15, right: 15, bottom: -15, top: 15, near: 0.1, far: 30)
        let position: float3 = [-scene.sunLignt.position.x, -scene.sunLignt.position.y, -scene.sunLignt.position.z]
        let center: float3 = [0, 0, 0]
        let lookAt = float4x4(eye: position, center: center, up: [0, 1, 0])
        scene.uniforms.viewMatrix = float4x4(translation: [0, 0, 7]) * lookAt
        scene.uniforms.shadowMatrix = scene.uniforms.projectionMatrix * scene.uniforms.viewMatrix
        
        renderEncoder.setRenderPipelineState(shadowPipelineState)
        for child in scene.children {
            if let renderable = child as? OBSDModel {
                draw(renderEncoder: renderEncoder, model: renderable)
            }
        }
        renderEncoder.endEncoding()
        renderEncoder.popDebugGroup()
    }
    
    func buildGbufferTextures(size: CGSize) {
        albedoTexture = buildTexture(pixelFormat: .bgra8Unorm, size: size, label: "Albedo")
        normalTexture = buildTexture(pixelFormat: .rgba16Float, size: size, label: "Normal")
        positionTexture = buildTexture(pixelFormat: .rgba16Float, size: size, label: "Position")
        depthTexture = buildTexture(pixelFormat: .depth32Float, size: size, label: "Depth")
    }
    
    func buildGBufferRenderPassDescriptor(size: CGSize, descriptor: MTLRenderPassDescriptor) {
        buildGbufferTextures(size: size)
        let textures: [MTLTexture] = [albedoTexture, normalTexture, positionTexture]
        for (index, texture) in textures.enumerated() {
            descriptor.setUpColorAttachment(position: index, texture: texture)
        }

        descriptor.setUpDepthAttachment(texture: depthTexture)
    }
    
    func buildGbufferPipelineState(withFragmentFunctionName name: String) {
        //let descriptor = MTLRenderPipelineDescriptor()
        //descriptor.colorAttachments[0].pixelFormat = OBSDRenderer.colorPixelFormat
        gBufferRenderPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        gBufferRenderPipelineDescriptor.colorAttachments[1].pixelFormat = .rgba16Float
        gBufferRenderPipelineDescriptor.colorAttachments[2].pixelFormat = .rgba16Float
        gBufferRenderPipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        gBufferRenderPipelineDescriptor.label = "GBuffer state"
        gBufferRenderPipelineDescriptor.vertexFunction = OBSDRenderer.library.makeFunction(name: "vertex_main")
        if (name == "fragment_PBR") {
            gBufferRenderPipelineDescriptor.fragmentFunction = OBSDRenderer.library.makeFunction(name: "gBufferFragment")
        } else {
            gBufferRenderPipelineDescriptor.fragmentFunction = OBSDRenderer.library.makeFunction(name: "gBufferFragment_IBL")
        }
        gBufferRenderPipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(OBSDModel.defaultVertexDescriptor)
        //let a = OBSDModel.defaultVertexDescriptor.attributes[3] as! MDLVertexAttribute
        do {
            gBufferPipelineState = try OBSDRenderer.metalDevice.makeRenderPipelineState(descriptor: gBufferRenderPipelineDescriptor)
        } catch let error {
            fatalError(error.localizedDescription)
        }
    }
    
    func renderGbufferPass(renderEncoder: MTLRenderCommandEncoder, model: OBSDModel) {
        guard let scene = scene else { return }
        
        renderEncoder.pushDebugGroup("Gbuffer pass \(model.name)")
        renderEncoder.label = "Gbuffer encoder \(model.name)"
        renderEncoder.setDepthStencilState(depthStencilState)
        
        renderEncoder.setFragmentTexture(shadowTexture, index: 5)
        renderEncoder.setFragmentBytes(&scene.fragmentUniforms, length: MemoryLayout<OBSDFragmentUniforms>.stride, index: 15)
        let lights = scene.lights
        let lightsBuffer = OBSDRenderer.metalDevice.makeBuffer(bytes: lights, length: MemoryLayout<Light>.stride * lights.count, options: [])
        renderEncoder.setFragmentBuffer(lightsBuffer, offset: 0, index: 2)
//        for child in scene.children {
//            if let renderable = child as? OBSDModel {
//                buildGbufferPipelineState(withFragmentFunctionName: renderable.fragmentFunctionName)
//                renderEncoder.setRenderPipelineState(gBufferPipelineState)
//                draw(renderEncoder: renderEncoder, model: renderable)
//            }
//        }
        
//        buildGbufferPipelineState(withFragmentFunctionName: model.fragmentFunctionName)
//        renderEncoder.setRenderPipelineState(gBufferPipelineState)
//        draw(renderEncoder: renderEncoder, model: model)
        
        model.doRender(commandEncoder: renderEncoder, uniforms: scene.uniforms, fragmentUniforms: scene.fragmentUniforms)

        renderEncoder.popDebugGroup()
    }
    
    func renderCompositionPass(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.pushDebugGroup("Composition Pass")
        renderEncoder.label = "Composition encoder"
        
        renderEncoder.setRenderPipelineState(compositionPipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setVertexBuffer(quadVerticesBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(quadTexCoordBuffer, offset: 0, index: 1)
        
        guard let scene = scene else { return }
        
        let lights = scene.lights
        let lightsBuffer = OBSDRenderer.metalDevice.makeBuffer(bytes: lights, length: MemoryLayout<Light>.stride * lights.count, options: [])
        renderEncoder.setFragmentBuffer(lightsBuffer, offset: 0, index: 2)
        renderEncoder.setFragmentBytes(&scene.fragmentUniforms, length: MemoryLayout<OBSDFragmentUniforms>.stride, index: 15)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: quadVertices.count)
        
        renderEncoder.popDebugGroup()
    }
    
    func buildCompositionPipelineState() {
        let descriptor = MTLRenderPipelineDescriptor()
        //descriptor.colorAttachments[0].pixelFormat = OBSDRenderer.colorPixelFormat
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[1].pixelFormat = .rgba16Float
        descriptor.colorAttachments[2].pixelFormat = .rgba16Float
        descriptor.depthAttachmentPixelFormat = .depth32Float
        //descriptor.sampleCount = 4
        descriptor.label = "Composition state"
        descriptor.vertexFunction = OBSDRenderer.library.makeFunction(name: "composition_vert")
        descriptor.fragmentFunction = OBSDRenderer.library.makeFunction(name: "composition_frag")
        
        do {
            compositionPipelineState = try OBSDRenderer.metalDevice.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}

private extension MTLRenderPassDescriptor {
    func setUpDepthAttachment(texture: MTLTexture) {
        depthAttachment.texture = texture
        depthAttachment.loadAction = .clear
        depthAttachment.storeAction = .store
        depthAttachment.clearDepth = 1
    }
    
    func setUpColorAttachment(position: Int, texture: MTLTexture) {
        colorAttachments[position].texture = texture
        colorAttachments[position].loadAction = .clear
        colorAttachments[position].storeAction = .store
        colorAttachments[position].clearColor = MTLClearColorMake(0.66, 0.9, 0.96, 1)
    }
}

extension OBSDRenderer: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("size will change")
        guard let scene = scene else {return}
        buildShadowTexture(size: size)
        buildGBufferRenderPassDescriptor(size: size, descriptor: renderPassDescriptor)
        for water in scene.waters {
            water.reflectionRenderPass.updateTextures(size: size)
        }
    }
    
    public func draw(in view: MTKView) {
        OBSDRenderer.commandBuffer = OBSDRenderer.commandQueue.makeCommandBuffer()
        
        guard let scene = scene else { return }
        
        renderPassDescriptor.colorAttachments[0].texture = view.currentDrawable?.texture
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.66, green: 0.9, blue: 0.96, alpha: 1.0)
    
        //renderPassDescriptor.depthAttachment.texture = view.depthStencilTexture
        
        let deltaTime = 1 / Float(view.preferredFramesPerSecond)
        scene.fps = view.preferredFramesPerSecond
        scene.update(deltaTime: deltaTime)
        
        // shadow pass
        guard let shadowEncoder = OBSDRenderer.commandBuffer?.makeRenderCommandEncoder(descriptor: shadowRenderPassDescriptor) else { return }
        renderShadowPass(renderEncoder: shadowEncoder)
        
        for water in scene.waters {
            guard let reflectEncoder = OBSDRenderer.commandBuffer?.makeRenderCommandEncoder(descriptor: water.reflectionRenderPass.descriptor)
                else { return }
            
            scene.fragmentUniforms.cameraPosition = scene.camera.position
            scene.fragmentUniforms.lightCount = uint(scene.lights.count)
            scene.uniforms.projectionMatrix = scene.camera.projectionMatrix
            
            // Render reflection
            reflectEncoder.setDepthStencilState(depthStencilState)
            scene.reflectionCamera.position = scene.camera.position
            scene.reflectionCamera.rotation = scene.camera.rotation
            scene.reflectionCamera.position.y = -scene.camera.position.y
            scene.reflectionCamera.rotation.x = -scene.camera.rotation.x
            scene.uniforms.viewMatrix = scene.reflectionCamera.vMatrix
            scene.uniforms.clipPlane = float4(0, 1, 0, 0.1)
            
            scene.skybox?.update(renderEncoder: reflectEncoder)
            for child in scene.children {
                if let model = child as? OBSDModel {
                    renderGbufferPass(renderEncoder: reflectEncoder, model: model)
                }
            }
            
            scene.skybox?.render(renderEncoder: reflectEncoder, uniforms: scene.uniforms)
            
            reflectEncoder.endEncoding()
        }
        
        // Render Objects
        guard let renderEncoder = OBSDRenderer.commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {return}
        
        scene.fragmentUniforms.cameraPosition = scene.camera.position
        scene.fragmentUniforms.lightCount = uint(scene.lights.count)
        
        scene.uniforms.viewMatrix = scene.camera.viewMatrix
        scene.uniforms.projectionMatrix = scene.camera.projectionMatrix
        scene.uniforms.clipPlane = float4(0, -1, 0, 1000)
        
        // gbuffer pass
        scene.skybox?.update(renderEncoder: renderEncoder)
        for child in scene.children {
            if let model = child as? OBSDModel {
                renderGbufferPass(renderEncoder: renderEncoder, model: model)
            }
        }
        
        // composition pass
        //renderCompositionPass(renderEncoder: renderEncoder)
        
        // skybox pass
        scene.skybox?.render(renderEncoder: renderEncoder, uniforms: scene.uniforms)
        
        for water in scene.waters {
            water.update()
            water.render(renderEncoder: renderEncoder, uniforms: scene.uniforms)
        }
        
//        for terrain in scene.terrains {
//            terrain.doRender(commandEncoder: renderEncoder, uniforms: scene.uniforms, fragmentUniforms: scene.fragmentUniforms)
//        }
        
//        for child in scene.children {
//            if let renderable = child as? Renderable {
//                renderable.doRender(commandEncoder: renderEncoder, uniforms: scene.uniforms, fragmentUniforms: scene.fragmentUniforms)
//            }
//        }
    
        renderEncoder.endEncoding()
        
        guard let drawable = view.currentDrawable else {
            //sOBSDRenderer.commandBuffer?.commit()
            return
        }
        
        OBSDRenderer.commandBuffer?.present(drawable)
        OBSDRenderer.commandBuffer?.commit()
        //OBSDRenderer.commandBuffer = nil
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, model: OBSDModel) {
        guard let scene = scene else { return }
        
        scene.uniforms.modelMatrix = model.worldTransform
        scene.uniforms.normalMatrix = float3x3(normalFrom4x4: model.modelMatrix)
        renderEncoder.setVertexBytes(&scene.uniforms, length: MemoryLayout<OBSDUniforms>.stride, index: 11)
        renderEncoder.setVertexBuffer(model.mesh?.vertexBuffers[0].buffer, offset: 0, index: 0)
        renderEncoder.setFragmentSamplerState(model.samplerState, index: 0)
        
        for modelSubmesh in model.submeshes! {
            let submesh = modelSubmesh.submesh
            var material = modelSubmesh.material
            renderEncoder.setFragmentTexture(modelSubmesh.textures.baseColor, index: 0)
            renderEncoder.setFragmentTexture(modelSubmesh.textures.normal, index: 1)
            renderEncoder.setFragmentTexture(modelSubmesh.textures.roughness, index: 2)
            renderEncoder.setFragmentTexture(modelSubmesh.textures.metallic, index: 3)
            renderEncoder.setFragmentTexture(modelSubmesh.textures.ao, index: 4)
            renderEncoder.setFragmentBytes(&material, length: MemoryLayout<Material>.stride, index: 13)
            renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                indexCount: submesh.indexCount,
                                                indexType: submesh.indexType,
                                                indexBuffer: submesh.indexBuffer.buffer,
                                                indexBufferOffset: submesh.indexBuffer.offset)
        }
    }
    
}
