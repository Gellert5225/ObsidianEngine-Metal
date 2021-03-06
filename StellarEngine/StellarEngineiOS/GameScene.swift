//
//  GameScene.swift
//  ObsidianTest
//
//  Created by Gellert on 6/18/18.
//  Copyright © 2018 Gellert. All rights reserved.
//

import StellariOS

class GameScene: STLRScene {
    
    let ground = STLRModel(modelName: "large-plane")
    let tree = STLRModel(modelName: "tree", instanceCount: 25)
    var light: Light!
    
    override init() {
        super.init()
        
        skybox = STLRSkybox(textureName: nil)
        ground.tiling = 16
        
        add(childNode: ground)
        add(childNode: tree)
        
        for i in 0..<25 {
            var transform = Transform()
            transform.position.x = .random(in: -10..<10)
            transform.position.z = .random(in: -10..<10)
            transform.rotation.y = .random(in: -Float.pi..<Float.pi)
            tree.updateBuffer(instance: i, transform: transform)
        }
        for _ in 0..<25 {
            let tree = STLRModel(modelName: "tree")
            add(childNode: tree)
            tree.position.x = .random(in: -10..<10)
            tree.position.z = .random(in: -10..<10)
            tree.rotation.y = .random(in: -Float.pi..<Float.pi)
        }
        
        camera.position = float3(0, 0, 30)
        camera.rotate(x: 0, y: 0, z: 0)
        camera.fovDegrees = 60
        
        light = buildDefaultLight()
        
        light.position = float3(100, 50, -50)
        light.intensity = 1.0
        lights.append(light)
        lights.append(ambientLight)
    }
    
    // using instancing
    
}
