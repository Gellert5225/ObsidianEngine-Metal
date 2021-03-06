//
//  Model.swift
//  ObsidianEngine
//
//  Created by Gellert on 6/18/18.
//  Copyright © 2018 Gellert. All rights reserved.
//

import MetalKit
import ModelIO

open class STLRModel: STLRNode {
    
    open var tiling: UInt32 = 1
    open var fragmentFunctionName: String = "fragment_PBR"
    open var vertexFunctionName: String = "mp_vertex"
    
    static var vertexDescriptor: MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()
        
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 4
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = MemoryLayout<Float>.stride * 7
        vertexDescriptor.attributes[2].bufferIndex = 0
        
        vertexDescriptor.attributes[3].format = .float
        vertexDescriptor.attributes[3].offset = MemoryLayout<Float>.stride * 9
        vertexDescriptor.attributes[3].bufferIndex = 0
        
        vertexDescriptor.attributes[4].format = .float3
        vertexDescriptor.attributes[4].offset = MemoryLayout<Float>.stride * 10
        vertexDescriptor.attributes[4].bufferIndex = 0
        
        vertexDescriptor.attributes[5].format = .float3
        vertexDescriptor.attributes[5].offset = MemoryLayout<Float>.stride * 13
        vertexDescriptor.attributes[5].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 16
        return vertexDescriptor
    }
    
    static var defaultVertexDescriptor: MDLVertexDescriptor {
        let descriptor = MTKModelIOVertexDescriptorFromMetal(STLRModel.vertexDescriptor)
        
        let attributePosition = descriptor.attributes[0] as! MDLVertexAttribute
        attributePosition.name = MDLVertexAttributePosition
        descriptor.attributes[0] = attributePosition
        
        let attributeNormal = descriptor.attributes[1] as! MDLVertexAttribute
        attributeNormal.name = MDLVertexAttributeNormal
        descriptor.attributes[1] = attributeNormal
        
        let attributeTexture = descriptor.attributes[2] as! MDLVertexAttribute
        attributeTexture.name = MDLVertexAttributeTextureCoordinate
        descriptor.attributes[2] = attributeTexture
        
        let attributeAO = descriptor.attributes[3] as! MDLVertexAttribute
        attributeAO.name = MDLVertexAttributeOcclusionValue
        descriptor.attributes[3] = attributeAO
        
        return descriptor
    }
    
    private var transforms: [Transform]
    
    var texture: MTLTexture?
    var mesh: MTKMesh?
    var submeshes: [STLRSubmesh]?
    var instanceBuffer: MTLBuffer
    
    let instanceCount: Int
    let samplerState: MTLSamplerState?
    var pipelineState: MTLRenderPipelineState!
    
    public init(modelName: String, vertexFunctionName: String = "mp_vertex",
                fragmentFunctionName: String = "fragment_IBL", instanceCount: Int = 1) {
        self.instanceCount = instanceCount
        samplerState = STLRModel.buildSamplerState()
        transforms = STLRModel.buildTransforms(instanceCount: instanceCount)
        instanceBuffer = STLRModel.buildInstanceBuffer(transforms: transforms)
        super.init()
        name = modelName
        loadModel(modelName: modelName, vertexFunctionName: vertexFunctionName, fragmentFunctionName: fragmentFunctionName)
        self.vertexFunctionName = vertexFunctionName
        self.fragmentFunctionName = fragmentFunctionName
        //pipelineState = buildPipelineState()
    }
    
    private static func buildSamplerState() -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        descriptor.mipFilter = .linear
        descriptor.magFilter = .linear
        descriptor.maxAnisotropy = 8
        
        let samplerState = STLRRenderer.metalDevice.makeSamplerState(descriptor: descriptor)
        return samplerState
    }
    
    static func buildTransforms(instanceCount: Int) -> [Transform] {
        return [Transform](repeatElement(Transform(), count: instanceCount))
    }
    
    static func buildInstanceBuffer(transforms: [Transform]) -> MTLBuffer {
        let instances = transforms.map {
            Instances(modelMatrix: $0.modelMatrix, normalMatrix: float3x3(normalFrom4x4: $0.modelMatrix))
        }
        
        guard let instanceBuffer = STLRRenderer.metalDevice.makeBuffer(bytes: instances, length: MemoryLayout<Instances>.stride * instances.count)
            else {
                fatalError("Failed to create instance buffer")
        }
        
        return instanceBuffer
    }
    
    open func updateBuffer(instance: Int, transform: Transform) {
        transforms[instance] = transform
        var pointer = instanceBuffer.contents().bindMemory(to: Instances.self, capacity: transforms.count)
        pointer = pointer.advanced(by: instance)
        pointer.pointee.modelMatrix = transforms[instance].modelMatrix
        pointer.pointee.normalMatrix = transforms[instance].normalMatrix
    }
    
    func loadModel(modelName: String, vertexFunctionName: String, fragmentFunctionName: String) {
        guard let bundleURL = Bundle.main.url(forResource: "Assets", withExtension: "bundle") else { return }
        guard let assetURL = recursivePathsForResource(name: modelName, extensionName: "obj", in: bundleURL.path) else {
            STLRLog.CORE_ERROR("Failed to load model: \(modelName), file does not exist!")
            return
        }
        STLRLog.CORE_INFO("Loaded model: \(modelName)")
        
        let bufferAllocator = MTKMeshBufferAllocator(device: STLRRenderer.metalDevice)
        let asset = MDLAsset(url: assetURL, vertexDescriptor: STLRModel.defaultVertexDescriptor, bufferAllocator: bufferAllocator)
        let mdlMesh = asset.object(at: 0) as! MDLMesh
        
        //mdlMesh.generateAmbientOcclusionVertexColors(withQuality: 1, attenuationFactor: 1, objectsToConsider: [mdlMesh], vertexAttributeNamed: MDLVertexAttributeOcclusionValue)
        
        do {
            mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, tangentAttributeNamed: MDLVertexAttributeTangent, bitangentAttributeNamed: MDLVertexAttributeBitangent)
            mesh = try MTKMesh(mesh: mdlMesh, device: STLRRenderer.metalDevice)
            submeshes = mdlMesh.submeshes?.enumerated().compactMap {index, submesh in
                (submesh as? MDLSubmesh).map {
                    return STLRSubmesh(submesh: (mesh?.submeshes[index])!,
                                       mdlSubmesh: $0, vertexFunctionName: vertexFunctionName, fragmentFunctionName: fragmentFunctionName)
                }
            }
            ?? []
        } catch {
            STLRLog.CORE_ERROR("Mesh error: \(error.localizedDescription)")
        }
    }
    
}

extension STLRModel: Renderable {
    
    public func doRender(commandEncoder: MTLRenderCommandEncoder, uniforms: STLRUniforms, fragmentUniforms: STLRFragmentUniforms) {
//        var fragConsts = fragmentUniforms
//        fragConsts.tiling = tiling
//        var vertexUniform = uniforms
//        vertexUniform.modelMatrix = worldTransform
//        vertexUniform.normalMatrix = float3x3(normalFrom4x4: modelMatrix)
//        
//        commandEncoder.setVertexBuffer(instanceBuffer, offset: 0, index: Int(BufferIndexInstances.rawValue))
//        
//        commandEncoder.setFragmentSamplerState(samplerState, index: 0)
//        
//        commandEncoder.setFragmentBytes(&fragConsts, length: MemoryLayout<STLRFragmentUniforms>.stride, index: 15)
//        commandEncoder.setVertexBytes(&vertexUniform, length: MemoryLayout<STLRUniforms>.stride, index: 11)
//        
//        for (index, vertexBuffer) in (mesh?.vertexBuffers.enumerated())! {
//            commandEncoder.setVertexBuffer(vertexBuffer.buffer, offset: 0, index: index)
//        }
//        
//        for mesh in submeshes! {
//            commandEncoder.setRenderPipelineState(mesh.pipelineState)
//            
//            commandEncoder.setFragmentTexture(mesh.textures.baseColor, index: Int(BaseColorTexture.rawValue))
//            commandEncoder.setFragmentTexture(mesh.textures.normal, index: Int(NormalTexture.rawValue))
//            commandEncoder.setFragmentTexture(mesh.textures.roughness, index: Int(RoughnessTexture.rawValue))
//            commandEncoder.setFragmentTexture(mesh.textures.metallic, index: Int(MetallicTexture.rawValue))
//            commandEncoder.setFragmentTexture(mesh.textures.ao, index: Int(AOTexture.rawValue))
//            var material = mesh.material
//            commandEncoder.setFragmentBytes(&material, length: MemoryLayout<Material>.stride, index: 13)
//
//            commandEncoder.drawIndexedPrimitives(type: mesh.submesh.primitiveType,
//                                                 indexCount: mesh.submesh.indexCount,
//                                                 indexType: mesh.submesh.indexType,
//                                                 indexBuffer: mesh.submesh.indexBuffer.buffer,
//                                                 indexBufferOffset: mesh.submesh.indexBuffer.offset,
//                                                 instanceCount: instanceCount)
//        }
    }
    
}

extension STLRModel: Texturable {}
