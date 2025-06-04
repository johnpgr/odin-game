#+feature dynamic-literals
package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

WIDTH :: 640
HEIGHT :: 480

TARGET_FPS :: 60
FRAME_TIME_MS :: 1000 / TARGET_FPS

PI :: 3.14159265358979323846

IMAGES_PATH :: "assets/images"
SPRITE_COUNT :: 1024

Vec2 :: distinct [2]f32
Vec3 :: distinct [3]f32
Vec4 :: distinct [4]f32
Mat4x4 :: distinct [4][4]f32

SUPPORTED_SHADER_FORMATS :: sdl.GPUShaderFormat{.DXIL, .MSL, .SPIRV}

SpriteId :: enum {
	Ravioli_1,
	Ravioli_2,
	Ravioli_3,
	Ravioli_4,
}

Sprite :: struct {
	atlas_offset: Vec2,
	sprite_size:  Vec2,
}

SpriteBatch :: struct {
	texture:  ^sdl.GPUTexture,
	sprites:  [dynamic]RenderableSprite,
	capacity: int,
}

create_sprite_batch :: proc(texture: ^sdl.GPUTexture, initial_capacity: int) -> SpriteBatch {
	return SpriteBatch {
		texture = texture,
		sprites = make([dynamic]RenderableSprite, 0, initial_capacity),
		capacity = initial_capacity,
	}
}

add_sprite_to_layer :: proc(game: ^Game, sprite: ^RenderableSprite, z_index: int) {
	layer := &game.layers[z_index]

	if layer == nil {
		game.layers[z_index] = RenderLayer {
			batches = make(map[^sdl.GPUTexture]SpriteBatch),
			z_index = z_index,
		}
		layer = &game.layers[z_index]
	}

	batch := &layer.batches[game.texture]
	if batch == nil {
		layer.batches[game.texture] = create_sprite_batch(game.texture, game.max_sprites_per_batch)
		batch = &layer.batches[game.texture]
	}

	if len(batch.sprites) >= batch.capacity {
		batch.capacity *= 2
		reserve(&batch.sprites, batch.capacity)
	}

	sprite.depth = (f32(z_index) + (1.0 - sprite.transform.position.y / HEIGHT))
	append(&batch.sprites, sprite^)
	game.sprite_count += 1
}

render_layer :: proc(
	game: ^Game,
	cmd_buf: ^sdl.GPUCommandBuffer,
	render_pass: ^sdl.GPURenderPass,
	layer: RenderLayer,
) {
	for texture, batch in layer.batches {
		if len(batch.sprites) == 0 do continue

		sdl.BindGPUFragmentSamplers(
			render_pass,
			0,
			&sdl.GPUTextureSamplerBinding{texture = texture, sampler = game.sampler},
			1,
		)

		sdl.DrawGPUPrimitives(render_pass, u32(len(batch.sprites)) * 6, 1, 0, 0)
	}
}

RenderLayer :: struct {
	batches: map[^sdl.GPUTexture]SpriteBatch,
	z_index: int,
}

SpriteInstance :: struct {
	x, y, z, rotation:          f32,
	w, h, padding_a, padding_b: f32,
	tex_u, tex_v, tex_w, tex_h: f32,
	r, g, b, a:                 f32,
}

SPRITE_ATLAS := map[SpriteId]Sprite {
	.Ravioli_1 = {atlas_offset = {0.0, 0.0}, sprite_size = {0.5, 0.5}},
	.Ravioli_2 = {atlas_offset = {0.5, 0.0}, sprite_size = {0.5, 0.5}},
	.Ravioli_3 = {atlas_offset = {0.0, 0.5}, sprite_size = {0.5, 0.5}},
	.Ravioli_4 = {atlas_offset = {0.5, 0.5}, sprite_size = {0.5, 0.5}},
}

Transform :: struct {
	position: Vec2,
	scale:    Vec2,
	rotation: f32,
}

get_sprite :: proc(id: SpriteId) -> Sprite {
	return SPRITE_ATLAS[id]
}

RenderableSprite :: struct {
	sprite_id: SpriteId,
	transform: Transform,
	color:     Vec4,
	depth:     f32,
}

OrthographicCamera2d :: struct {
	zoom:       f32,
	position:   Vec2,
	dimensions: Vec2,
}

get_projection_matrix :: proc(camera: ^OrthographicCamera2d) -> Mat4x4 {
	half_width := camera.dimensions.x / (2 * camera.zoom)
	half_height := camera.dimensions.y / (2 * camera.zoom)

	left := camera.position.x - half_width
	right := camera.position.x + half_width
	bottom := camera.position.y + half_height
	top := camera.position.y - half_height

	return create_orthographic_offcenter(left, right, top, bottom, 0, -1)
}

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
		{0, 0, 1 / (z_near_plane - z_far_plane), 0},
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

LoadShaderParams :: struct {
	num_samplers, num_uniform_buffers:         u32,
	num_storage_buffers, num_storage_textures: u32,
}

load_shader :: proc(
	device: ^sdl.GPUDevice,
	shader_name: string,
	params: LoadShaderParams,
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
	target_format := sdl.GPUShaderFormat{}
	extension: string
	entrypoint: string = "main"

	if .DXIL in shader_formats {
		target_format = {.DXIL}
		extension = ".dxil"
	} else if .MSL in shader_formats {
		target_format = {.MSL}
		extension = ".msl"
		entrypoint = "main0"
	} else if .SPIRV in shader_formats {
		target_format = {.SPIRV}
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
		format               = target_format,
		stage                = stage,
		entrypoint           = strings.clone_to_cstring(entrypoint, context.temp_allocator),
		code                 = raw_data(code),
		code_size            = len(code),
		num_samplers         = params.num_samplers,
		num_uniform_buffers  = params.num_uniform_buffers,
		num_storage_buffers  = params.num_storage_buffers,
		num_storage_textures = params.num_storage_textures,
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
	sprites:                [dynamic]RenderableSprite,
	camera:                 OrthographicCamera2d,
	layers:                 map[int]RenderLayer,
	max_sprites_per_batch:  int,
	sprite_count:           int,
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

select_optimal_present_mode :: proc(
	device: ^sdl.GPUDevice,
	window: ^sdl.Window,
) -> sdl.GPUPresentMode {
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
	vertex_shader, vertex_err := load_shader(
		device,
		"pull-sprite-batch.vert",
		{
			num_samplers = 0,
			num_uniform_buffers = 1,
			num_storage_buffers = 1,
			num_storage_textures = 0,
		},
	)
	if vertex_err != nil {
		sdl.Log("Failed to load vertex shader: %s", vertex_err)
		return nil
	}
	defer sdl.ReleaseGPUShader(device, vertex_shader)

	frag_shader, frag_err := load_shader(
		device,
		"textured-quad-color.frag",
		{
			num_samplers = 1,
			num_uniform_buffers = 0,
			num_storage_buffers = 0,
			num_storage_textures = 0,
		},
	)
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
			depth_stencil_state = sdl.GPUDepthStencilState {
				enable_depth_test = true,
				enable_depth_write = true,
				compare_op = .LESS,
			},
		},
	)
	return graphics_pipeline
}

TextureAndSampler :: struct {
	texture: ^sdl.GPUTexture,
	sampler: ^sdl.GPUSampler,
}

TextureAndSamplerError :: enum {
	FailedToCreateTexture,
	FailedToCreateSampler,
	FailedToAcquireCommandBuffer,
	FailedToBeginCopyPass,
}

create_texture_and_sampler_from_image :: proc(
	device: ^sdl.GPUDevice,
	image: ^sdl.Surface,
) -> (
	TextureAndSampler,
	TextureAndSamplerError,
) {
	texture_transfer_buffer := sdl.CreateGPUTransferBuffer(
		device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = u32(image.pitch * image.h)},
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

	_ = sdl.memcpy(texture_transfer_ptr, image.pixels, uint(image.w * image.h * 4))
	sdl.UnmapGPUTransferBuffer(device, texture_transfer_buffer)

	texture := sdl.CreateGPUTexture(
		device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .R8G8B8A8_UNORM,
			width = u32(image.w),
			height = u32(image.h),
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
		sdl.GPUTextureRegion{texture = texture, w = u32(image.w), h = u32(image.h), d = 1},
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

sprite_instance_from_renderable_sprite :: proc(renderable: RenderableSprite) -> SpriteInstance {
	sprite := get_sprite(renderable.sprite_id)

	return SpriteInstance {
		x = renderable.transform.position.x,
		y = renderable.transform.position.y,
		z = renderable.depth,
		rotation = renderable.transform.rotation,
		w = sprite.sprite_size.x * renderable.transform.scale.x,
		h = sprite.sprite_size.y * renderable.transform.scale.y,
		tex_u = sprite.atlas_offset.x,
		tex_v = sprite.atlas_offset.y,
		tex_w = sprite.sprite_size.x,
		tex_h = sprite.sprite_size.y,
		r = renderable.color.x,
		g = renderable.color.y,
		b = renderable.color.z,
		a = renderable.color.w,
		padding_a = 0,
		padding_b = 0,
	}
}

update_sprites :: proc(sprite_data: [^]SpriteInstance, renderable_sprites: []RenderableSprite) {
	for i := 0; i < len(renderable_sprites); i += 1 {
		renderable := renderable_sprites[i]
		sprite_data[i] = sprite_instance_from_renderable_sprite(renderable)
	}
}

game_upload_sprite_data :: proc(game: ^Game, cmd_buf: ^sdl.GPUCommandBuffer) -> bool {
	raw_ptr := sdl.MapGPUTransferBuffer(game.device, game.sprite_transfer_buffer, true)
	if raw_ptr == nil {
		sdl.Log("Failed to map sprite transfer buffer for upload")
		return false
	}

	sprite_data_ptr: [^]SpriteInstance = cast([^]SpriteInstance)raw_ptr
	update_sprites(sprite_data_ptr, game.sprites[:])

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

	cmd_buf := sdl.AcquireGPUCommandBuffer(game.device)
	if cmd_buf == nil {
		sdl.Log("Failed to acquire GPU command buffer for rendering")
		return
	}

	for z_index, layer in game.layers {
		for texture, batch in layer.batches {
			if len(batch.sprites) == 0 do continue

			sprite_data_ptr := sdl.MapGPUTransferBuffer(
				game.device,
				game.sprite_transfer_buffer,
				true,
			)
			if sprite_data_ptr == nil {
				sdl.Log("Failed to map sprite transfer buffer for batch")
				continue
			}

			sprite_instances := cast([^]SpriteInstance)sprite_data_ptr
			update_sprites(sprite_instances, batch.sprites[:])
			sdl.UnmapGPUTransferBuffer(game.device, game.sprite_transfer_buffer)

			copy_pass := sdl.BeginGPUCopyPass(cmd_buf)
			if copy_pass == nil {
				sdl.Log("Failed to begin GPU copy pass for batch")
				continue
			}

			sdl.UploadToGPUBuffer(
				copy_pass,
				sdl.GPUTransferBufferLocation {
					transfer_buffer = game.sprite_transfer_buffer,
					offset = 0,
				},
				sdl.GPUBufferRegion {
					buffer = game.sprite_buffer,
					offset = 0,
					size = u32(len(batch.sprites)) * size_of(SpriteInstance),
				},
				true,
			)
			sdl.EndGPUCopyPass(copy_pass)
		}
	}

	swapchain_texture: ^sdl.GPUTexture = nil
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, game.window, &swapchain_texture, nil, nil) {
		sdl.Log("Failed to acquire swapchain texture for rendering")
		return
	}

	if swapchain_texture != nil {
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

		camera_matrix := get_projection_matrix(&game.camera)
		sdl.PushGPUVertexUniformData(cmd_buf, 0, &camera_matrix, size_of(Mat4x4))

		layer_indices := make([dynamic]int)
		defer delete(layer_indices)
		for z_index in game.layers {
			append(&layer_indices, z_index)
		}
		slice.sort(layer_indices[:])

		for z_index in layer_indices {
			render_layer(game, cmd_buf, render_pass, game.layers[z_index])
		}

		sdl.EndGPURenderPass(render_pass)
	}

	if !sdl.SubmitGPUCommandBuffer(cmd_buf) {
		sdl.Log("Failed to submit GPU command buffer for rendering")
		return
	}
}

game_clear_sprites :: proc(game: ^Game) {
	for _, &layer in game.layers {
		for _, &batch in layer.batches {
			clear(&batch.sprites)
		}
	}
	game.sprite_count = 0
}

game_init_random_sprites :: proc(game: ^Game) {
	for i := 0; i < 500; i += 1 {
		z_index := int(sdl.rand(3))
		sprite := RenderableSprite {
			sprite_id = SpriteId(sdl.rand(4)),
			transform = Transform {
				position = {f32(sdl.rand(WIDTH)), f32(sdl.rand(HEIGHT))},
				scale = {64, 64},
				rotation = 0,
			},
			color = {1, 1, 1, 1},
		}
		add_sprite_to_layer(game, &sprite, z_index)
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

	present_mode := select_optimal_present_mode(game.device, game.window)
	_ = sdl.SetGPUSwapchainParameters(game.device, game.window, .SDR, present_mode)

	sdl.srand(0)

	game.render_pipeline = create_graphics_pipeline(game.device, game.window)
	if game.render_pipeline == nil {
		fmt.println("Failed to create graphics pipeline")
		return
	}

	image, image_err := load_image("ravioli_atlas.bmp")
	if image_err != nil {
		sdl.Log("Failed to load image: %s", image_err)
		return
	}

	texture_result, texture_error := create_texture_and_sampler_from_image(game.device, image)
	if texture_error != nil {
		fmt.println("Failed to create texture and sampler:", texture_error)
		return
	}
	game.texture = texture_result.texture
	game.sampler = texture_result.sampler

	sdl.DestroySurface(image)

	sprite_buffers, sprite_buffers_err := create_sprite_buffers(game.device)
	if sprite_buffers_err != nil {
		sdl.Log("Failed to create sprite buffers: %s", sprite_buffers_err)
		return
	}
	game.sprite_transfer_buffer = sprite_buffers.transfer_buffer
	game.sprite_buffer = sprite_buffers.storage_buffer

	game.camera = OrthographicCamera2d {
		zoom       = 1.0,
		position   = {WIDTH / 2.0, HEIGHT / 2.0},
		dimensions = {WIDTH, HEIGHT},
	}
	game.max_sprites_per_batch = 1024
	game.layers = make(map[int]RenderLayer)

	last_reset_time := sdl.GetTicks()
	game_init_random_sprites(&game)

	for game.running {
		frame_start := sdl.GetTicks()
		if frame_start - last_reset_time >= 3000 {
			game_clear_sprites(&game)
			game_init_random_sprites(&game)
			last_reset_time = sdl.GetTicks()
		}

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

		frame_time := sdl.GetTicks() - frame_start
		if frame_time < FRAME_TIME_MS {
			sdl.Delay(u32(FRAME_TIME_MS - frame_time))
		}
	}
}
