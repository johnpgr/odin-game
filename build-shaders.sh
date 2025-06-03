#!/bin/bash

# Check if shadercross is available
if ! command -v shadercross &> /dev/null; then
    echo "shadercross not found - skipping shader compilation"
    exit 0
fi

echo "Compiling shaders with shadercross..."

SHADER_SOURCE_DIR="assets/shaders/source"
SHADER_OUT_DIR="assets/shaders/compiled"

# Create output directory if it doesn't exist
mkdir -p "$SHADER_OUT_DIR"

# Check if shader source directory exists
if [ ! -d "$SHADER_SOURCE_DIR" ]; then
    echo "Error: Shader directory '$SHADER_SOURCE_DIR' not found"
    exit 1
fi

# Shader types to process
SHADER_EXTENSIONS=(".vert.hlsl" ".frag.hlsl" ".comp.hlsl")

# Output formats
OUTPUT_EXTENSIONS=(".spv" ".msl" ".dxil")

# Process each file in the shader source directory
for file in "$SHADER_SOURCE_DIR"/*; do
    # Skip if not a regular file
    [ ! -f "$file" ] && continue
    
    filename=$(basename "$file")
    
    # Check if file matches any shader extension
    for ext in "${SHADER_EXTENSIONS[@]}"; do
        if [[ "$filename" == *"$ext" ]]; then
            # Remove only the .hlsl extension (last 5 characters) to preserve .vert/.frag/.comp
            output_basename="${filename:0:$((${#filename}-5))}"
            
            # Generate output files for each format
            for output_ext in "${OUTPUT_EXTENSIONS[@]}"; do
                output_file="../$(basename "$SHADER_OUT_DIR")/${output_basename}${output_ext}"
                
                echo "Compiling $filename -> ${output_basename}${output_ext}"
                (cd "$SHADER_SOURCE_DIR" && shadercross "$filename" -o "$output_file")
                
                if [ $? -ne 0 ]; then
                    echo "Error: Failed to compile $filename"
                    exit 1
                fi
            done
            break
        fi
    done
done

echo "Shader compilation complete"
