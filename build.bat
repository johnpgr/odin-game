@echo off
REM filepath: c:\Users\jpgre\work\odin-game\build.bat

odin build src -debug -out:build/main.exe
copy /Y "%ODIN_ROOT%\vendor\sdl3\SDL3.dll" build >nul
copy /Y "%ODIN_ROOT%\vendor\sdl3\image\SDL3_image.dll" build >nul
copy /Y "%ODIN_ROOT%\vendor\sdl3\ttf\SDL3_ttf.dll" build >nul
if %errorlevel% neq 0 exit /b %errorlevel%