//
//  Renderable.swift
//  ObsidianEngine
//
//  Created by Gellert on 6/13/18.
//  Copyright © 2018 Gellert. All rights reserved.
//

import MetalKit

public protocol Renderable {
    
    func doRender(commandEncoder: MTLRenderCommandEncoder, uniforms: STLRUniforms, fragmentUniforms: STLRFragmentUniforms)
    
}
