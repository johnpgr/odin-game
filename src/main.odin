package main

import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

WIDTH :: 640
HEIGHT :: 480

PI :: 3.14159265358979323846

IMAGES_PATH :: "assets/images"
SPRITE_COUNT :: 8192

Vec2 :: distinct [2]f32
Vec3 :: distinct [3]f32
Vec4 :: distinct [4]f32
Mat4x4 :: distinct [4][4]f32

SUPPORTED_SHADER_FORMATS :: sdl.GPUShaderFormat{.DXIL, .MSL, .SPIRV}

SpriteInstance :: struct {
	x, y, z, rotation:          f32,
	w, h, padding_a, padding_b: f32,
	tex_u, tex_v, tex_w, tex_h: f32,
	r, g, b, a:                 f32,
}

u_coords: [4]f32 = {0.0, 0.5, 0.0, 0.5}
v_coords: [4]f32 = {0.0, 0.0, 0.5, 0.5}

create_orthographic_offcenter :: proc(
	left: f32,
	right: f32,
	bottom: f32,
	top: f32,
	z_near_plane: f32,
	z_far_plane: f32,
) -> Mat4x4 {
	return Mat4x4 {
		{2 / (right - left), 0, 0, 0},
		{0, 2 / (top - bottom), 0, 0},
		{0, 0, 1.0 / (z_near_plane - z_far_plane), 0},
		{
			(left + right) / (left - right),
			(top + bottom) / (bottom - top),
			z_near_plane / (z_near_plane - z_far_plane),
			1,
		},
	}
}

LoadImageError :: enum {
	FileNotFound,
}

load_image :: proc(filename: string) -> (^sdl.Surface, LoadImageError) {
	full_path := fmt.tprintf("%s/%s", IMAGES_PATH, filename)
	cstr_filename := strings.clone_to_cstring(full_path, context.temp_allocator)
	defer delete(cstr_filename, context.temp_allocator)

	surface := img.Load(cstr_filename)
	if surface == nil {
		return nil, .FileNotFound
	}

	return surface, nil
}

ShaderLoadError :: enum {
	FileNotFound,
	InvalidShader,
	InvalidShaderStage,
}

load_shader :: proc(
	device: ^sdl.GPUDevice,
	shader_name: string,
	num_samplers, num_uniform_buffers, num_storage_buffers, num_storage_textures: u32,
) -> (
	^sdl.GPUShader,
	ShaderLoadError,
) {
	stage: sdl.GPUShaderStage
	if strings.ends_with(shader_name, ".vert") {
		stage = .VERTEX
	} else if strings.ends_with(shader_name, ".frag") {
		stage = .FRAGMENT
	} else {
		return nil, .InvalidShaderStage
	}

	shader_formats := sdl.GetGPUShaderFormats(device)
	format := sdl.GPUShaderFormat{}
	extension: string
	entrypoint: string = "main"

	if .DXIL in shader_formats {
		format = {.DXIL}
		extension = ".dxil"
	} else if .MSL in shader_formats {
		format = {.MSL}
		extension = ".msl"
		entrypoint = "main0"
	} else if .SPIRV in shader_formats {
		format = {.SPIRV}
		extension = ".spv"
	} else {
		sdl.Log(
			"Unrecognized shader format for file: %s",
			strings.clone_to_cstring(shader_name, context.temp_allocator),
		)
		return nil, .InvalidShader
	}

	shader_path := fmt.tprintf("assets/shaders/compiled/%s%s", shader_name, extension)

	code, ok := os.read_entire_file_from_filename(shader_path, context.temp_allocator)
	if !ok {
		sdl.Log(
			"Failed to read shader file: %s",
			strings.clone_to_cstring(shader_path, context.temp_allocator),
		)
		return nil, .FileNotFound
	}

	shader_info := sdl.GPUShaderCreateInfo {
		format               = format,
		stage                = stage,
		entrypoint           = strings.clone_to_cstring(entrypoint, context.temp_allocator),
		code                 = raw_data(code),
		code_size            = len(code),
		num_samplers         = num_samplers,
		num_uniform_buffers  = num_uniform_buffers,
		num_storage_buffers  = num_storage_buffers,
		num_storage_textures = num_storage_textures,
	}

	shader := sdl.CreateGPUShader(device, shader_info)

	if shader == nil {
		sdl.Log(
			"Failed to create shader from file: %s",
			strings.clone_to_cstring(shader_path, context.temp_allocator),
		)
		return nil, .InvalidShader
	}

	return shader, nil
}

Game :: struct {
	window:                 ^sdl.Window,
	device:                 ^sdl.GPUDevice,
	render_pipeline:        ^sdl.GPUGraphicsPipeline,
	texture:                ^sdl.GPUTexture,
	sampler:                ^sdl.GPUSampler,
	sprite_transfer_buffer: ^sdl.GPUTransferBuffer,
	sprite_buffer:          ^sdl.GPUBuffer,
	running:                bool,
	paused:                 bool,
}

game_deinit :: proc(game: ^Game) {
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

setup_present_mode :: proc(device: ^sdl.GPUDevice, window: ^sdl.Window) -> sdl.GPUPresentMode {
	present_mode: sdl.GPUPresentMode = .VSYNC
	if sdl.WindowSupportsGPUPresentMode(device, window, .MAILBOX) {
		present_mode = .MAILBOX
	} else if sdl.WindowSupportsGPUPresentMode(device, window, .IMMEDIATE) {
		present_mode = .IMMEDIATE
	}
	return present_mode
}

create_graphics_pipeline :: proc(
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

TextureAndSampler :: struct {
	texture: ^sdl.GPUTexture,
	sampler: ^sdl.GPUSampler,
}

TextureAndSamplerError :: enum {
	FailedToLoadImage,
	FailedToCreateTexture,
	FailedToCreateSampler,
	FailedToAcquireCommandBuffer,
	FailedToBeginCopyPass,
}

create_texture_and_sampler :: proc(
	device: ^sdl.GPUDevice,
) -> (
	TextureAndSampler,
	TextureAndSamplerError,
) {
	image_data, image_err := load_image("ravioli_atlas.bmp")
	if image_err != nil {
		sdl.Log("Failed to load image: %s", image_err)
		return {}, .FailedToLoadImage
	}
	defer sdl.DestroySurface(image_data)

	texture_transfer_buffer := sdl.CreateGPUTransferBuffer(
		device,
		sdl.GPUTransferBufferCreateInfo {
			usage = .UPLOAD,
			size = u32(image_data.pitch * image_data.h),
		},
	)
	if texture_transfer_buffer == nil {
		sdl.Log("Failed to create GPU transfer buffer for texture")
		return {}, .FailedToCreateTexture
	}
	defer sdl.ReleaseGPUTransferBuffer(device, texture_transfer_buffer)

	texture_transfer_ptr := sdl.MapGPUTransferBuffer(device, texture_transfer_buffer, false)
	if texture_transfer_ptr == nil {
		sdl.Log("Failed to map GPU transfer buffer for texture")
		return {}, .FailedToCreateTexture
	}

	_ = sdl.memcpy(texture_transfer_ptr, image_data.pixels, uint(image_data.w * image_data.h * 4))
	sdl.UnmapGPUTransferBuffer(device, texture_transfer_buffer)

	texture := sdl.CreateGPUTexture(
		device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .R8G8B8A8_UNORM,
			width = u32(image_data.w),
			height = u32(image_data.h),
			layer_count_or_depth = 1,
			num_levels = 1,
			usage = sdl.GPUTextureUsageFlags{.SAMPLER},
		},
	)

	if texture == nil {
		sdl.Log("Failed to create GPU texture: %s", sdl.GetError())
		return {}, .FailedToCreateTexture
	}

	sampler := sdl.CreateGPUSampler(
		device,
		sdl.GPUSamplerCreateInfo {
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			mipmap_mode = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		},
	)
	if sampler == nil {
		sdl.Log("Failed to create GPU sampler: %s", sdl.GetError())
		sdl.ReleaseGPUTexture(device, texture)
		return {}, .FailedToCreateSampler
	}

	upload_cmd_buf := sdl.AcquireGPUCommandBuffer(device)
	if upload_cmd_buf == nil {
		sdl.Log("Failed to acquire GPU command buffer for texture upload")
		sdl.ReleaseGPUSampler(device, sampler)
		sdl.ReleaseGPUTexture(device, texture)
		return {}, .FailedToAcquireCommandBuffer
	}

	copy_pass := sdl.BeginGPUCopyPass(upload_cmd_buf)
	if copy_pass == nil {
		sdl.Log("Failed to begin GPU copy pass for texture")
		sdl.ReleaseGPUSampler(device, sampler)
		sdl.ReleaseGPUTexture(device, texture)
		return {}, .FailedToBeginCopyPass
	}

	sdl.UploadToGPUTexture(
		copy_pass,
		sdl.GPUTextureTransferInfo{transfer_buffer = texture_transfer_buffer, offset = 0},
		sdl.GPUTextureRegion {
			texture = texture,
			w = u32(image_data.w),
			h = u32(image_data.h),
			d = 1,
		},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)
	_ = sdl.SubmitGPUCommandBuffer(upload_cmd_buf)

	return {texture = texture, sampler = sampler}, nil
}

SpriteBuffers :: struct {
	transfer_buffer: ^sdl.GPUTransferBuffer,
	storage_buffer:  ^sdl.GPUBuffer,
}

SpriteBuffersError :: enum {
	FailedToCreateTransferBuffer,
	FailedToCreateStorageBuffer,
	FailedToAcquireCommandBuffer,
	FailedToBeginCopyPass,
}

create_sprite_buffers :: proc(device: ^sdl.GPUDevice) -> (SpriteBuffers, SpriteBuffersError) {
	sprite_transfer_buffer := sdl.CreateGPUTransferBuffer(
		device,
		sdl.GPUTransferBufferCreateInfo {
			usage = .UPLOAD,
			size = SPRITE_COUNT * size_of(SpriteInstance),
		},
	)
	if sprite_transfer_buffer == nil {
		sdl.Log("Failed to create GPU transfer buffer for sprite instances")
		return {}, .FailedToCreateTransferBuffer
	}

	sprite_buffer := sdl.CreateGPUBuffer(
		device,
		sdl.GPUBufferCreateInfo {
			usage = {.GRAPHICS_STORAGE_READ},
			size = SPRITE_COUNT * size_of(SpriteInstance),
		},
	)
	if sprite_buffer == nil {
		sdl.Log("Failed to create GPU buffer for sprite instances")
		sdl.ReleaseGPUTransferBuffer(device, sprite_transfer_buffer)
		return {}, .FailedToCreateStorageBuffer
	}

	return {transfer_buffer = sprite_transfer_buffer, storage_buffer = sprite_buffer}, nil
}

update_sprites :: proc(sprite_data: [^]SpriteInstance) {
	for i in 0 ..< SPRITE_COUNT {
		ravioli := sdl.rand(4)
		sprite_data[i] = SpriteInstance {
			x         = f32(sdl.rand(WIDTH)),
			y         = f32(sdl.rand(HEIGHT)),
			z         = 0,
			rotation  = sdl.randf() * PI * 2,
			w         = 64.0,
			h         = 64.0,
			tex_u     = u_coords[ravioli],
			tex_v     = v_coords[ravioli],
			tex_w     = 0.5,
			tex_h     = 0.5,
			r         = 1.0,
			g         = 1.0,
			b         = 1.0,
			a         = 1.0,
			padding_a = 0.0,
			padding_b = 0.0,
		}
	}
}

game_upload_sprite_data :: proc(game: ^Game, cmd_buf: ^sdl.GPUCommandBuffer) -> bool {
	raw_ptr := sdl.MapGPUTransferBuffer(game.device, game.sprite_transfer_buffer, true)
	if raw_ptr == nil {
		sdl.Log("Failed to map sprite transfer buffer for upload")
		return false
	}

	sprite_data_ptr: [^]SpriteInstance = cast([^]SpriteInstance)raw_ptr
	update_sprites(sprite_data_ptr)

	sdl.UnmapGPUTransferBuffer(game.device, game.sprite_transfer_buffer)

	copy_pass := sdl.BeginGPUCopyPass(cmd_buf)
	if copy_pass == nil {
		sdl.Log("Failed to begin GPU copy pass for sprite data upload")
		return false
	}

	sdl.UploadToGPUBuffer(
		copy_pass,
		sdl.GPUTransferBufferLocation{transfer_buffer = game.sprite_transfer_buffer, offset = 0},
		sdl.GPUBufferRegion {
			buffer = game.sprite_buffer,
			offset = 0,
			size = SPRITE_COUNT * size_of(SpriteInstance),
		},
		true,
	)

	sdl.EndGPUCopyPass(copy_pass)
	return true
}


game_render :: proc(game: ^Game) {
	if game.paused {return}

	camera_matrix := create_orthographic_offcenter(0, WIDTH, HEIGHT, 0, 0, -1)

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
		game_upload_sprite_data(game, cmd_buf)

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
		sdl.PushGPUVertexUniformData(cmd_buf, 0, &camera_matrix, size_of(Mat4x4))
		sdl.DrawGPUPrimitives(render_pass, SPRITE_COUNT * 6, 1, 0, 0)
		sdl.EndGPURenderPass(render_pass)
	}

	if !sdl.SubmitGPUCommandBuffer(cmd_buf) {
		sdl.Log("Failed to submit GPU command buffer for rendering")
		return
	}
}

main :: proc() {
	game := Game{}
	defer game_deinit(&game)
	game.running = true
	game.paused = false

	if !sdl.Init(sdl.INIT_VIDEO) {
		sdl.Log("Failed to initialize SDL video subsystem")
		return
	}

	sdl.SetLogPriorities(.VERBOSE)

	game.window = sdl.CreateWindow(
		strings.clone_to_cstring("Hello, World!", context.temp_allocator),
		WIDTH,
		HEIGHT,
		sdl.WindowFlags{.HIDDEN, .RESIZABLE, .HIGH_PIXEL_DENSITY},
	)
	if game.window == nil {
		sdl.Log("Failed to create SDL window: %s", sdl.GetError())
		return
	}

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
		return
	}

	if !sdl.ClaimWindowForGPUDevice(game.device, game.window) {
		sdl.Log("Failed to claim window for GPU device: %s", sdl.GetError())
		return
	}

	if !sdl.ShowWindow(game.window) {
		sdl.Log("Failed to show SDL window: %s", sdl.GetError())
		return
	}

	present_mode := setup_present_mode(game.device, game.window)
	_ = sdl.SetGPUSwapchainParameters(game.device, game.window, .SDR, present_mode)

	sdl.srand(0)

	game.render_pipeline = create_graphics_pipeline(game.device, game.window)
	if game.render_pipeline == nil {
		fmt.println("Failed to create graphics pipeline")
		return
	}

	texture_result, texture_error := create_texture_and_sampler(game.device)
	if texture_error != nil {
		fmt.println("Failed to create texture and sampler:", texture_error)
		return
	}
	game.texture = texture_result.texture
	game.sampler = texture_result.sampler

	sprite_buffers, sprite_buffers_err := create_sprite_buffers(game.device)
	if sprite_buffers_err != nil {
		sdl.Log("Failed to create sprite buffers: %s", sprite_buffers_err)
		return
	}
	game.sprite_transfer_buffer = sprite_buffers.transfer_buffer
	game.sprite_buffer = sprite_buffers.storage_buffer

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
		game_render(&game)
	}
}
