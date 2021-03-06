//
//  TestScene.swift
//  StellarEngineMacOS
//
//  Created by Gellert Li on 2/13/21.
//  Copyright © 2021 Gellert. All rights reserved.
//

import StellarMacOS

class TestScene: STLRScene {
    override init(name: String = "Untitled Scene") {
        super.init(name: name)
        setupScene()
    }
    
    func setupScene() {
        skybox = STLRSkybox(textureName: nil)
        skybox?.skySettings = STLRSkybox.SunSet
        
        let water = STLRWater()
        add(water: water)
        
        let ground = STLRModel(modelName: "plane")
        ground.scale = [10, 10, 10]
        ground.position = [0, 1, 0]
        add(node: ground)

        let train = STLRModel(modelName: "train")
        add(node: train, parent: ground)
        train.scale = [0.2, 0.2, 0.2]
        train.position = [0.8, 0, -0.8]

        let chest = STLRModel(modelName: "chest")
        add(node: chest, parent: ground)
        chest.position = [0, 0, -0.8]
        chest.scale = [0.1, 0.1, 0.1]
//
//        let mouse = STLRModel(modelName: "MagicMouse")
//        add(node: mouse, parent: ground)
//        mouse.scale = [0.005, 0.005, 0.005]
//        mouse.position = [-1, 0, 0]
//
        let car = STLRModel(modelName: "racing-car")
        car.scale = [0.1, 0.1, 0.1]
        car.position = [0.8, 0, 0]
        add(node: car, parent: ground)
        
        let temple = STLRModel(modelName: "Temple")
        temple.scale = float3(repeating: 0.001)
        temple.position = [0.0, 0.01, 0.0]
        add(node: temple, parent: ground)
        
        camera.fovDegrees = 60
        
        sunLignt.position = float3(0, 20, -15)
        sunLignt.intensity = 1.0
        sunLignt.color = [Float(253/255.0), Float(160/255.0), Float(49/255.0)]
        ambientLight.color = [Float(255/255.0), Float(244/255.0), Float(229/255.0)]
        ambientLight.intensity = 0.01
        
        lights.append(sunLignt)
        lights.append(ambientLight)
        createPointLights(count: 100, min: [-10, 1.3, -10], max: [10, 10, 10])
    }
    
    func printNodes(root: STLRNode, level: Int) {
        for child in root.children {
            print("\(child.name) at level \(level)")
            printNodes(root: child, level: level+1)
        }
    }
    
    override func updateScene(deltaTime: Float) {
        for (index, child) in renderables.enumerated() {
            if (index != 0) {
                if let renderable = child as? STLRModel {
                    renderable.rotation.y += 0.01
                }
            }
        }
    }
    
    func random(range: CountableClosedRange<Int>) -> Int {
        var offset = 0
        if range.lowerBound < 0 {
            offset = abs(range.lowerBound)
        }
        let min = UInt32(range.lowerBound + offset)
        let max = UInt32(range.upperBound + offset)
        return Int(min + arc4random_uniform(max-min)) - offset
    }
    
    func createPointLights(count: Int, min: float3, max: float3) {
        let colors: [float3] = [
            float3(1, 0, 0),
            float3(1, 1, 0),
            float3(1, 1, 1),
            float3(0, 1, 0),
            float3(0, 1, 1),
            float3(0, 0, 1),
            float3(0, 1, 1),
            float3(1, 0, 1) ]
        let newMin: float3 = [min.x*100, min.y*100, min.z*100]
        let newMax: float3 = [max.x*100, max.y*100, max.z*100]
        for _ in 0..<count {
            var light = buildDefaultLight()
            light.type = Pointlight
            let x = Float(random(range: Int(newMin.x)...Int(newMax.x))) * 0.01
            let y = Float(random(range: Int(newMin.y)...Int(newMax.y))) * 0.01
            let z = Float(random(range: Int(newMin.z)...Int(newMax.z))) * 0.01
            light.position = [x, y, z]
            light.color = colors[random(range: 0...colors.count)]
            light.intensity = 2
            light.attenuation = float3(2, 2, 2)
            lights.append(light)
        }
    }
}
