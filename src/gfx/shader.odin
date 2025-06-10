package gfx

import "core:os"
import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

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
