@echo off
REM filepath: c:\Users\jpgre\work\odin-game\build-shaders.bat

REM Check if shadercross is available
shadercross --version >nul 2>&1
if %errorlevel% neq 0 (
    echo shadercross not found - skipping shader compilation
    exit /b 0
)

echo Compiling shaders with shadercross...

set SHADER_SOURCE_DIR=assets\shaders\source
set SHADER_OUT_DIR=assets\shaders\compiled

REM Create output directory if it doesn't exist
if not exist "%SHADER_OUT_DIR%" mkdir "%SHADER_OUT_DIR%"

REM Check if shader source directory exists
if not exist "%SHADER_SOURCE_DIR%" (
    echo Error: Shader directory '%SHADER_SOURCE_DIR%' not found
    exit /b 1
)

REM Process each file in the shader source directory
for %%f in ("%SHADER_SOURCE_DIR%\*.vert.hlsl" "%SHADER_SOURCE_DIR%\*.frag.hlsl" "%SHADER_SOURCE_DIR%\*.comp.hlsl") do (
    if exist "%%f" (
        set "filename=%%~nxf"
        call :compile_shader "%%f"
        if !errorlevel! neq 0 exit /b !errorlevel!
    )
)

echo Shader compilation complete
exit /b 0

:compile_shader
setlocal enabledelayedexpansion
set "filepath=%~1"
set "filename=%~nx1"

REM Remove .hlsl extension (last 5 characters) to preserve .vert/.frag/.comp
set "output_basename=!filename:~0,-5!"

REM Generate output files for each format
for %%e in (.spv .msl .dxil) do (
    set "output_file=%SHADER_OUT_DIR%\!output_basename!%%e"
    echo Compiling !filename! -^> !output_basename!%%e
    
    pushd "%SHADER_SOURCE_DIR%"
    shadercross "!filename!" -o "../%SHADER_OUT_DIR%/!output_basename!%%e"
    set compile_result=!errorlevel!
    popd
    
    if !compile_result! neq 0 (
        echo Error: Failed to compile !filename!
        exit /b 1
    )
)
endlocal
exit /b 0