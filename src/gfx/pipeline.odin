package gfx

import sdl "vendor:sdl3"

create_pipeline :: proc(
    device: ^sdl.GPUDevice,
    window: ^sdl.Window,
) -> ^sdl.GPUGraphicsPipeline {
    vertex_shader, vertex_err := load_shader(device, "pull-sprite-batch.vert", 0, 1, 1, 0)
    if vertex_err != nil {
        sdl.Log("Failed to load vertex shader: %s", vertex_err)
        return nil
    }
    defer sdl.ReleaseGPUShader(device, vertex_shader)

    frag_shader, frag_err := load_shader(device, "textured-quad-color.frag", 1, 0, 0, 0)
    if frag_err != nil {
        sdl.Log("Failed to load fragment shader: %s", frag_err)
        return nil
    }
    defer sdl.ReleaseGPUShader(device, frag_shader)

    color_target_descs := sdl.GPUColorTargetDescription {
        format = sdl.GetGPUSwapchainTextureFormat(device, window),
        blend_state = sdl.GPUColorTargetBlendState {
            enable_blend = true,
            color_blend_op = .ADD,
            alpha_blend_op = .ADD,
            src_color_blendfactor = .SRC_ALPHA,
            dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
            src_alpha_blendfactor = .SRC_ALPHA,
            dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
        },
    }

    graphics_pipeline := sdl.CreateGPUGraphicsPipeline(
        device,
        sdl.GPUGraphicsPipelineCreateInfo {
            target_info = sdl.GPUGraphicsPipelineTargetInfo {
                num_color_targets = 1,
                color_target_descriptions = &color_target_descs,
            },
            primitive_type = .TRIANGLELIST,
            vertex_shader = vertex_shader,
            fragment_shader = frag_shader,
        },
    )
    return graphics_pipeline
}
