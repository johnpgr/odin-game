package util

import "core:os"
import "core:fmt"
import "core:strings"
import img "vendor:sdl3/image"
import sdl "vendor:sdl3"

IMAGES_PATH :: "assets/images"

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

