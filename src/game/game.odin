package game

import "../gfx"
import "../util"
import "../sprite"
import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

SPRITE_COUNT :: 1024
SUPPORTED_SHADER_FORMATS :: sdl.GPUShaderFormat{.DXIL, .MSL, .SPIRV}

Game :: struct {
	window:                 ^sdl.Window,
	device:                 ^sdl.GPUDevice,
	render_pipeline:        ^sdl.GPUGraphicsPipeline,
	texture:                ^sdl.GPUTexture,
	sampler:                ^sdl.GPUSampler,
	sprite_transfer_buffer: ^sdl.GPUTransferBuffer,
	sprite_buffer:          ^sdl.GPUBuffer,
	sprites:                [dynamic]sprite.RenderableSprite,
	camera:                 OrthographicCamera2d,
	running:                bool,
	paused:                 bool,
}

init :: proc(game: ^Game, width: i32, height: i32) -> bool {
	game.running = true
	game.paused = false

	if !sdl.Init(sdl.INIT_VIDEO) {
		sdl.Log("Failed to initialize SDL video subsystem")
		return false
	}

	sdl.SetLogPriorities(.VERBOSE)

	game.window = sdl.CreateWindow(
		strings.clone_to_cstring("Hello, World!", context.temp_allocator),
		width,
		height,
		sdl.WindowFlags{.HIDDEN, .RESIZABLE, .HIGH_PIXEL_DENSITY},
	)
	if game.window == nil {
		sdl.Log("Failed to create SDL window: %s", sdl.GetError())
		return false
	}

	// Setup GPU driver preference
	driver_count := sdl.GetNumGPUDrivers()
	for i in 0 ..< driver_count {
		driver_name := sdl.GetGPUDriver(i)
		if driver_name == "direct3d12" {
			sdl.SetHint(sdl.HINT_GPU_DRIVER, "direct3d12")
		}
	}

	game.device = sdl.CreateGPUDevice(SUPPORTED_SHADER_FORMATS, true, nil)
	if game.device == nil {
		sdl.Log("Failed to create GPU device: %s", sdl.GetError())
		return false
	}

	if !sdl.ClaimWindowForGPUDevice(game.device, game.window) {
		sdl.Log("Failed to claim window for GPU device: %s", sdl.GetError())
		return false
	}

	if !sdl.ShowWindow(game.window) {
		sdl.Log("Failed to show SDL window: %s", sdl.GetError())
		return false
	}

	present_mode := setup_present_mode(game.device, game.window)
	_ = sdl.SetGPUSwapchainParameters(game.device, game.window, .SDR, present_mode)

	sdl.srand(0)

	// Initialize graphics pipeline
	game.render_pipeline = gfx.create_pipeline(game.device, game.window)
	if game.render_pipeline == nil {
		fmt.println("Failed to create graphics pipeline")
		return false
	}

	// Initialize texture
	texture_result, texture_error := gfx.create_texture_and_sampler(game.device)
	if texture_error != nil {
		fmt.println("Failed to create texture and sampler:", texture_error)
		return false
	}
	game.texture = texture_result.texture
	game.sampler = texture_result.sampler

	// Initialize sprite buffers
	sprite_buffers, sprite_buffers_err := gfx.create_sprite_buffers(game.device)
	if sprite_buffers_err != nil {
		sdl.Log("Failed to create sprite buffers: %s", sprite_buffers_err)
		return false
	}
	game.sprite_transfer_buffer = sprite_buffers.transfer_buffer
	game.sprite_buffer = sprite_buffers.storage_buffer

	// Initialize camera
	game.camera = OrthographicCamera2d {
		zoom       = 1.0,
		position   = {f32(width) / 2.0, f32(height) / 2.0},
		dimensions = {f32(width), f32(height)},
	}

	// Initialize sprites
	for i := 0; i < SPRITE_COUNT; i += 1 {
		append(
			&game.sprites,
			sprite.RenderableSprite {
				sprite_id = sprite.SpriteId(sdl.rand(4)),
				transform = sprite.Transform {
					position = {f32(sdl.rand(width)), f32(sdl.rand(height))},
					scale = {64, 64},
					rotation = 0,
				},
				color = {1, 1, 1, 1},
			},
		)
	}

	return true
}

deinit :: proc(game: ^Game) {
	if game.device != nil {
		if game.sprite_buffer != nil {
			sdl.ReleaseGPUBuffer(game.device, game.sprite_buffer)
		}
		if game.sprite_transfer_buffer != nil {
			sdl.ReleaseGPUTransferBuffer(game.device, game.sprite_transfer_buffer)
		}
		if game.texture != nil {
			sdl.ReleaseGPUTexture(game.device, game.texture)
		}
		if game.sampler != nil {
			sdl.ReleaseGPUSampler(game.device, game.sampler)
		}
		if game.render_pipeline != nil {
			sdl.ReleaseGPUGraphicsPipeline(game.device, game.render_pipeline)
		}
		if game.window != nil {
			sdl.ReleaseWindowFromGPUDevice(game.device, game.window)
		}

		sdl.DestroyGPUDevice(game.device)
	}

	if game.window != nil {
		sdl.DestroyWindow(game.window)
	}

	sdl.Quit()
}

run :: proc(game: ^Game) {
	for game.running {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				game.running = false
				break
			case .KEY_DOWN:
				switch event.key.key {
				case sdl.K_Q, sdl.K_ESCAPE:
					game.running = false
				case sdl.K_P:
					game.paused = !game.paused
				}
			}
		}
		render(game)
	}
}

render :: proc(game: ^Game) {
	if game.paused {return}

	cmd_buf := sdl.AcquireGPUCommandBuffer(game.device)
	if cmd_buf == nil {
		sdl.Log("Failed to acquire GPU command buffer for rendering")
		return
	}

	swapchain_texture: ^sdl.GPUTexture = nil
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, game.window, &swapchain_texture, nil, nil) {
		sdl.Log("Failed to acquire swapchain texture for rendering")
		return
	}

	if swapchain_texture != nil {
		gfx.upload_sprite_data(
			game.device,
			cmd_buf,
			{game.sprite_transfer_buffer, game.sprite_buffer},
			game.sprites,
		)
		camera_matrix := get_projection_matrix(&game.camera)
		render_pass := sdl.BeginGPURenderPass(
			cmd_buf,
			&sdl.GPUColorTargetInfo {
				texture = swapchain_texture,
				cycle = false,
				load_op = .CLEAR,
				store_op = .STORE,
				clear_color = {0.0, 0.0, 0.0, 1.0},
			},
			1,
			nil,
		)
		if render_pass == nil {
			sdl.Log("Failed to begin GPU render pass")
			return
		}

		sdl.BindGPUGraphicsPipeline(render_pass, game.render_pipeline)
		sdl.BindGPUVertexStorageBuffers(render_pass, 0, &game.sprite_buffer, 1)
		sdl.BindGPUFragmentSamplers(
			render_pass,
			0,
			&sdl.GPUTextureSamplerBinding{texture = game.texture, sampler = game.sampler},
			1,
		)
		sdl.PushGPUVertexUniformData(cmd_buf, 0, &camera_matrix, size_of(util.Mat4x4))
		sdl.DrawGPUPrimitives(render_pass, u32(len(game.sprites)) * 6, 1, 0, 0)
		sdl.EndGPURenderPass(render_pass)
	}

	if !sdl.SubmitGPUCommandBuffer(cmd_buf) {
		sdl.Log("Failed to submit GPU command buffer for rendering")
		return
	}
}

// Helper procedures
setup_present_mode :: proc(device: ^sdl.GPUDevice, window: ^sdl.Window) -> sdl.GPUPresentMode {
	present_mode: sdl.GPUPresentMode = .VSYNC
	if sdl.WindowSupportsGPUPresentMode(device, window, .MAILBOX) {
		present_mode = .MAILBOX
	} else if sdl.WindowSupportsGPUPresentMode(device, window, .IMMEDIATE) {
		present_mode = .IMMEDIATE
	}
	return present_mode
}
