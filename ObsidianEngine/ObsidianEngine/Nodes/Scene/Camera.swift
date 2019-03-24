//
//  Camera.swift
//  ObsidianEngine
//
//  Created by Gellert on 6/17/18.
//  Copyright © 2018 Gellert. All rights reserved.
//

import MetalKit

open class OBSDCamera: OBSDNode {
    
    var viewMatrix: matrix_float4x4 {
        get{
            let translateMatrix = float4x4(translation: position)
            let rotateMatrix = float4x4(rotation: rotation)
            return (translateMatrix * rotateMatrix)
        }
    }
    var currentPosition: float3?
    
    open var fovDegrees: Float = 100
    open var nearZ: Float = 0.1
    open var farZ: Float = 1000
    
    var mod: Float {
        return modulus(vector: position)
    }
    
    var projectionMatrix: float4x4 {
        return float4x4(projectionFov: radians(fromDegrees: fovDegrees),
                        near: nearZ,
                        far: farZ,
                        aspect: Float(UIScreen.main.bounds.size.width / UIScreen.main.bounds.size.height))
    }

    var vMatrix: matrix_float4x4 {
        let translateMatrix = float4x4(translation: position)
        let rotateMatrix = float4x4(rotation: rotation)
        return (translateMatrix * rotateMatrix)
    }
//    var transform = Transform() {
//        didSet {
//            let translateMatrix = float4x4(translation: [-transform.position.x,
//                                                         -transform.position.y,
//                                                         -transform.position.z])
//            let rotateMatrix = float4x4(rotation: transform.rotation)
//            vMatrix = rotateMatrix * translateMatrix
//        }
//    }
}
