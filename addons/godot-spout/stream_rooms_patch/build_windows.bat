@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set CMAKE="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
cd /d C:\temp\godot-spout
if not exist C:\temp\vklib\vulkan-1.lib (
  mkdir C:\temp\vklib
  dumpbin /exports C:\Windows\System32\vulkan-1.dll > C:\temp\vklib\exports.txt
  echo EXPORTS> C:\temp\vklib\vulkan-1.def
  for /f "skip=19 tokens=4" %%a in (C:\temp\vklib\exports.txt) do echo %%a>> C:\temp\vklib\vulkan-1.def
  lib /nologo /def:C:\temp\vklib\vulkan-1.def /out:C:\temp\vklib\vulkan-1.lib /machine:x64
)
if not exist build mkdir build
cd build
%CMAKE% -G "Visual Studio 17 2022" -A x64 .. -DGODOT_SPOUT_ENABLE_VULKAN=ON -DVulkan_INCLUDE_DIR=C:/temp/Vulkan-Headers/include -DVulkan_LIBRARY=C:/temp/vklib/vulkan-1.lib || exit /b 1
%CMAKE% --build . --config Release --target install -- /m || exit /b 1
%CMAKE% --build . --config Debug --target install -- /m || exit /b 1
