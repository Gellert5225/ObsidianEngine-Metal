//
//  OBSDViewController.swift
//  ObsidianEngine
//
//  Created by Gellert on 6/17/18.
//  Copyright © 2018 Gellert. All rights reserved.
//

import MetalKit

open class OBSDViewController: UIViewController {

    open var scene: OBSDScene {
        set {
            renderer.scene = newValue
            print("new scene has been set")
        } get {
            return renderer.scene!
        }
    }
    open var panEnabled: Bool = false {
        didSet {
            if self.panEnabled {
                self.view.addGestureRecognizer(panGesture!)
            } else {
                self.view.removeGestureRecognizer(panGesture!)
            }
        }
    }
    
    open var panSensivity: Float = 0.01
    
    open var verticalCameraAngleInterval: (min: Float, max: Float) = (-.greatestFiniteMagnitude, .greatestFiniteMagnitude)
    
    var lastPanLocation: CGPoint!
    var currentAngleY: Float?
    var currentAngleX: Float?
    
    var renderer: OBSDRenderer!
    var pipelineState: MTLRenderPipelineState!
    var commandQueue: MTLCommandQueue!
    var metalView: MTKView {
        return view as! MTKView
    }
    
    var panGesture: UIPanGestureRecognizer?
    
    override open func viewDidLoad() {
        super.viewDidLoad()

        metalView.depthStencilPixelFormat = .depth32Float
        metalView.device = MTLCreateSystemDefaultDevice()
        guard let device = metalView.device else {
            fatalError("Device not created. Run on a physical device")
        }
        //metalView.sampleCount = 4
        renderer = OBSDRenderer(with: device, metalView: metalView)
        print("renderer has been init");
        metalView.delegate = renderer
        
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        
        let pinch = UIPinchGestureRecognizer(target: self,
                                             action: #selector(handlePinch(gesture:)))
        view.addGestureRecognizer(pinch)
    }
    
    open func add(_ shape: OBSDNode) {
        renderer.scene?.add(childNode: shape)
    }
    
    var previousScale: CGFloat = 0.0
    
    @objc func handlePinch(gesture: UIPinchGestureRecognizer) {
        var sensitivity: Float = 0.2
        if gesture.state == .changed {
            let delta = gesture.scale - previousScale
            previousScale = gesture.scale
            
            sensitivity = delta < 0.0 ? -sensitivity : sensitivity
            let x = scene.camera.position.x
            let y = scene.camera.position.y
            let z = scene.camera.position.z
            
            let length = sqrt(x * x + y * y + z * z)

            scene.camera.position.x = (length - sensitivity) / length * abs(x)
            scene.camera.position.y = (length - sensitivity) / length * abs(y)
            scene.camera.position.z = (length - sensitivity) / length * abs(z)
        }
        
        if gesture.state == .ended {
            previousScale = 1
        }
    }
    
    @objc func handlePan(recognizer:UIPanGestureRecognizer) {
        if recognizer.state == UIGestureRecognizer.State.changed {
            let pointInView = recognizer.location(in: self.view)

            let xDelta = -Float(lastPanLocation.x - pointInView.x) * panSensivity
            let yDelta = -Float(lastPanLocation.y - pointInView.y) * panSensivity

            if (yDelta + currentAngleX! > radians(fromDegrees: verticalCameraAngleInterval.min) && yDelta + currentAngleX! < radians(fromDegrees: verticalCameraAngleInterval.max)) {
                scene.camera.rotation.x = (yDelta + currentAngleX!)

                currentAngleX! += yDelta
            }
            
            scene.camera.rotation.y = (xDelta + currentAngleY!)

            lastPanLocation = pointInView
            currentAngleY! += xDelta

            if let position = scene.camera.currentPosition {
                let multiplier = (quardrantOf(angle: currentAngleY!) == 2 || quardrantOf(angle: currentAngleY!) == 3 ? -1 : 1)
                scene.camera.currentPosition = float3(sin(currentAngleY!) * scene.camera.mod,
                                                      sin(currentAngleX!) * scene.camera.mod,
                                                      Float(multiplier) * sqrt(scene.camera.mod * scene.camera.mod - position.x * position.x))
            } else {
                scene.camera.currentPosition = float3(sin(currentAngleY!) * scene.camera.mod, sin(currentAngleX!) * scene.camera.mod, sqrt(scene.camera.mod * scene.camera.mod - scene.camera.position.x * scene.camera.position.x))
            }
        } else if recognizer.state == UIGestureRecognizer.State.began {
            lastPanLocation = recognizer.location(in: self.view)
            if (currentAngleX == nil) {
                currentAngleX = scene.camera.rotation.x
            }

            if (currentAngleY == nil) {
                currentAngleY = scene.camera.rotation.y
            }
        }
        //print(scene.camera.currentPosition)
    }
    
    func quardrantOf(angle: Float) -> Int {
        if (sin(angle) >= 0 && cos(angle) >= 0) {
            return 1
        } else if (sin(angle) > 0 && cos(angle) < 0) {
            return 2
        } else if (sin(angle) < 0 && cos(angle) < 0) {
            return 3
        } else {
            return 4
        }
    }
}
