cmake_minimum_required(VERSION 3.10)
project(Mesh2Splat)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(APPLE)
    enable_language(OBJCXX)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum macOS deployment target")
endif()

set(THIRD_PARTY_DIR         ${CMAKE_SOURCE_DIR}/thirdParty)
set(GLFW_DIR                ${THIRD_PARTY_DIR}/glfw)
set(GLEW_DIR                ${THIRD_PARTY_DIR}/glew)
set(GLM_DIR                 ${THIRD_PARTY_DIR}/glm)
set(IMGUI_DIR               ${THIRD_PARTY_DIR}/imgui)
set(IGFD_DIR                ${THIRD_PARTY_DIR}/ImGuiFileDialog)
set(IMGUIZMO_DIR            ${THIRD_PARTY_DIR}/imguizmo)
set(XATLAS_DIR              ${THIRD_PARTY_DIR}/xatlas)

include_directories(${CMAKE_SOURCE_DIR}/src)
include_directories(SYSTEM
    ${GLFW_DIR}/include
    ${GLEW_DIR}/include
    ${GLM_DIR}
    ${IMGUI_DIR}
    ${IGFD_DIR}
    ${IMGUIZMO_DIR}
    ${XATLAS_DIR}
    ${THIRD_PARTY_DIR}
)


file(GLOB_RECURSE SOURCES 
        ${CMAKE_SOURCE_DIR}/src/*.cpp
        ${CMAKE_SOURCE_DIR}/src/*.hpp
        ${CMAKE_SOURCE_DIR}/src/*.h
)

file(GLOB IMGUI_SOURCES
        ${IMGUI_DIR}/*.cpp
        ${IMGUI_DIR}/*.hpp
        ${IMGUI_DIR}/*.h
)
list(APPEND SOURCES ${IMGUI_SOURCES})

file(GLOB IMGUIZMO_SOURCES
        ${IMGUIZMO_DIR}/*.cpp
        ${IMGUIZMO_DIR}/*.hpp
        ${IMGUIZMO_DIR}/*.h
)
list(APPEND SOURCES ${IMGUIZMO_SOURCES})

file(GLOB IGFD_SOURCE
        ${IGFD_DIR}/*.cpp
        ${IGFD_DIR}/*.hpp
        ${IGFD_DIR}/*.h
)
list(APPEND SOURCES ${IGFD_SOURCE})

file(GLOB XATLAS_SOURCE
        ${XATLAS_DIR}/*.cpp
        ${XATLAS_DIR}/*.hpp
        ${XATLAS_DIR}/*.h
)
list(APPEND SOURCES ${XATLAS_SOURCE})

set(THIRD_PARTY_SOURCES ${IMGUI_SOURCES} ${IMGUIZMO_SOURCES} ${IGFD_SOURCE} ${XATLAS_SOURCE})
if(MSVC)
    set_source_files_properties(${THIRD_PARTY_SOURCES} PROPERTIES COMPILE_FLAGS "/W0")
else()
    set_source_files_properties(${THIRD_PARTY_SOURCES} PROPERTIES COMPILE_FLAGS "-w")
endif()

add_executable(Mesh2Splat ${SOURCES})

target_compile_definitions(Mesh2Splat PRIVATE GLEW_STATIC)

if(MSVC)
    target_compile_options(Mesh2Splat PRIVATE
        /wd4244   # conversion, possible loss of data
        /wd4267   # size_t to smaller integer conversion
        /wd4018   # signed/unsigned mismatch
        /wd4101   # unreferenced local variable
    )
    target_link_options(Mesh2Splat PRIVATE
        /ignore:4098  # defaultlib runtime library conflict (glew32s.lib)
        /ignore:4099  # PDB not found for glew32s.lib
    )
endif()

if (WIN32)
    target_link_libraries(Mesh2Splat 
        ${GLFW_DIR}/lib-vc2022/glfw3.lib 
        ${GLEW_DIR}/lib/Release/x64/glew32s.lib 
        opengl32)
elseif (APPLE)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(GLFW REQUIRED glfw3)
    pkg_check_modules(GLEW REQUIRED glew)
    find_library(OPENGL_LIBRARY OpenGL REQUIRED)

    target_include_directories(Mesh2Splat PRIVATE
        ${GLFW_INCLUDE_DIRS}
        ${GLEW_INCLUDE_DIRS}
    )
    target_link_directories(Mesh2Splat PRIVATE
        ${GLFW_LIBRARY_DIRS}
        ${GLEW_LIBRARY_DIRS}
    )
    target_link_libraries(Mesh2Splat
        ${GLFW_LIBRARIES}
        ${GLEW_LIBRARIES}
        ${OPENGL_LIBRARY}
    )
else()
    target_link_libraries(Mesh2Splat glfw GLEW GL X11 Xrandr Xinerama Xcursor Xi Xxf86vm pthread dl) #todo
endif()

set_target_properties(Mesh2Splat PROPERTIES 
    RUNTIME_OUTPUT_DIRECTORY_DEBUG ${CMAKE_SOURCE_DIR}/bin/Debug
    RUNTIME_OUTPUT_DIRECTORY_RELEASE ${CMAKE_SOURCE_DIR}/bin/Release
    ARCHIVE_OUTPUT_DIRECTORY_DEBUG ${CMAKE_SOURCE_DIR}/lib/Debug
    ARCHIVE_OUTPUT_DIRECTORY_RELEASE ${CMAKE_SOURCE_DIR}/lib/Release
    LIBRARY_OUTPUT_DIRECTORY_DEBUG ${CMAKE_SOURCE_DIR}/lib/Debug
    LIBRARY_OUTPUT_DIRECTORY_RELEASE ${CMAKE_SOURCE_DIR}/lib/Release
)

if(APPLE)
    set(METAL_APP_SOURCES
        ${CMAKE_SOURCE_DIR}/src/app/macos/MacApp.mm
        ${CMAKE_SOURCE_DIR}/src/app/macos/MetalView.mm
        ${CMAKE_SOURCE_DIR}/src/app/macos/MetalView.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalBuffer.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalBuffer.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDeviceContext.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDeviceContext.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameResources.cpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameResources.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderer.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderer.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalTexture.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalTexture.hpp
    )

    add_executable(Mesh2SplatMetal MACOSX_BUNDLE ${METAL_APP_SOURCES})
    target_compile_features(Mesh2SplatMetal PRIVATE cxx_std_17)
    target_compile_options(Mesh2SplatMetal PRIVATE -fobjc-arc)
    target_include_directories(Mesh2SplatMetal PRIVATE ${CMAKE_SOURCE_DIR}/src)

    find_library(APPKIT_LIBRARY AppKit REQUIRED)
    find_library(METAL_LIBRARY Metal REQUIRED)
    find_library(METALKIT_LIBRARY MetalKit REQUIRED)
    find_library(QUARTZCORE_LIBRARY QuartzCore REQUIRED)

    target_link_libraries(Mesh2SplatMetal PRIVATE
        ${APPKIT_LIBRARY}
        ${METAL_LIBRARY}
        ${METALKIT_LIBRARY}
        ${QUARTZCORE_LIBRARY}
    )

    set_target_properties(Mesh2SplatMetal PROPERTIES
        MACOSX_BUNDLE_BUNDLE_NAME "Mesh2Splat Metal"
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.mesh2splat.metal"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
        MACOSX_BUNDLE_BUNDLE_VERSION "1"
        RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin/Metal
    )

    set(METAL_SHADER_DIR ${CMAKE_SOURCE_DIR}/shaders/metal)
    file(GLOB METAL_SHADER_SOURCES ${METAL_SHADER_DIR}/*.metal)
    if(METAL_SHADER_SOURCES)
        execute_process(
            COMMAND xcrun -sdk macosx --find metal
            RESULT_VARIABLE METAL_COMPILER_RESULT
            OUTPUT_VARIABLE METAL_COMPILER
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        execute_process(
            COMMAND xcrun -sdk macosx --find metallib
            RESULT_VARIABLE METALLIB_RESULT
            OUTPUT_VARIABLE METALLIB
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )

        if(METAL_COMPILER_RESULT EQUAL 0 AND METALLIB_RESULT EQUAL 0)
            set(METAL_AIR_OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/Mesh2SplatMetal.air)
            set(METAL_LIBRARY_OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/Mesh2SplatMetal.metallib)

            add_custom_command(
                OUTPUT ${METAL_LIBRARY_OUTPUT}
                COMMAND ${METAL_COMPILER} -c ${METAL_SHADER_SOURCES} -o ${METAL_AIR_OUTPUT}
                COMMAND ${METALLIB} ${METAL_AIR_OUTPUT} -o ${METAL_LIBRARY_OUTPUT}
                DEPENDS ${METAL_SHADER_SOURCES}
                COMMENT "Compiling Mesh2Splat Metal shaders"
                VERBATIM
            )
            add_custom_target(Mesh2SplatMetalShaders DEPENDS ${METAL_LIBRARY_OUTPUT})
            add_dependencies(Mesh2SplatMetal Mesh2SplatMetalShaders)
            add_custom_command(TARGET Mesh2SplatMetal POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_CONTENT_DIR:Mesh2SplatMetal>/Resources"
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    ${METAL_LIBRARY_OUTPUT}
                    "$<TARGET_BUNDLE_CONTENT_DIR:Mesh2SplatMetal>/Resources/Mesh2SplatMetal.metallib"
            )
        else()
            message(WARNING "Metal shader tools are unavailable; skipping .metallib generation for now.")
        endif()
    endif()
endif()
