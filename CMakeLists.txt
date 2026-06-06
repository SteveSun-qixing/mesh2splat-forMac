cmake_minimum_required(VERSION 3.15)
project(Mesh2Splat LANGUAGES CXX)

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
target_include_directories(Mesh2Splat PRIVATE ${CMAKE_SOURCE_DIR}/src)
target_include_directories(Mesh2Splat SYSTEM PRIVATE
    ${GLFW_DIR}/include
    ${GLEW_DIR}/include
    ${GLM_DIR}
    ${IMGUI_DIR}
    ${IGFD_DIR}
    ${IMGUIZMO_DIR}
    ${XATLAS_DIR}
    ${THIRD_PARTY_DIR}
)

add_executable(CoreIoSmokeTest
    ${CMAKE_SOURCE_DIR}/tests/CoreIoSmokeTest.cpp
    ${CMAKE_SOURCE_DIR}/src/core/CameraController.cpp
    ${CMAKE_SOURCE_DIR}/src/core/PrimitiveMeshFactory.cpp
    ${CMAKE_SOURCE_DIR}/src/io/GltfLoader.cpp
    ${CMAKE_SOURCE_DIR}/src/io/PlyWriter.cpp
    ${CMAKE_SOURCE_DIR}/src/implementationFiles/tiny_gltf_impl.cpp
    ${CMAKE_SOURCE_DIR}/src/implementationFiles/stb_image_impl.cpp
    ${CMAKE_SOURCE_DIR}/src/implementationFiles/stb_image_write_impl.cpp
)
target_compile_features(CoreIoSmokeTest PRIVATE cxx_std_17)
target_include_directories(CoreIoSmokeTest PRIVATE ${CMAKE_SOURCE_DIR}/src)
target_include_directories(CoreIoSmokeTest SYSTEM PRIVATE ${THIRD_PARTY_DIR})

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
    set(MESH2SPLAT_ENABLE_SWIFTUI_APP OFF)
    if(CMAKE_GENERATOR MATCHES "^(Xcode|Ninja|Ninja Multi-Config)$")
        enable_language(Swift)
        set(MESH2SPLAT_ENABLE_SWIFTUI_APP ON)
    else()
        message(STATUS "SwiftUI app frontend disabled for ${CMAKE_GENERATOR}; use Xcode or Ninja to enable Swift sources.")
    endif()

    set(METAL_SHADER_DIR ${CMAKE_SOURCE_DIR}/shaders/metal)
    file(GLOB METAL_SHADER_SOURCES ${METAL_SHADER_DIR}/*.metal)
    if(METAL_SHADER_SOURCES)
        set_source_files_properties(${METAL_SHADER_SOURCES} PROPERTIES HEADER_FILE_ONLY TRUE)
    endif()

    set(MACOS_APP_OBJCXX_SOURCES
        ${CMAKE_SOURCE_DIR}/src/app/macos/MacApp.mm
        ${CMAKE_SOURCE_DIR}/src/app/macos/MetalView.mm
        ${CMAKE_SOURCE_DIR}/src/app/macos/MetalView.hpp
    )

    set(MACOS_APP_SWIFTUI_SOURCES)

    set(MACOS_APP_CORE_SOURCES
        ${CMAKE_SOURCE_DIR}/src/core/FrameData.hpp
        ${CMAKE_SOURCE_DIR}/src/core/GaussianData.hpp
        ${CMAKE_SOURCE_DIR}/src/core/GpuTypes.hpp
        ${CMAKE_SOURCE_DIR}/src/core/InputState.hpp
        ${CMAKE_SOURCE_DIR}/src/core/CameraController.cpp
        ${CMAKE_SOURCE_DIR}/src/core/CameraController.hpp
        ${CMAKE_SOURCE_DIR}/src/core/MeshData.hpp
        ${CMAKE_SOURCE_DIR}/src/core/PrimitiveMeshFactory.cpp
        ${CMAKE_SOURCE_DIR}/src/core/PrimitiveMeshFactory.hpp
        ${CMAKE_SOURCE_DIR}/src/core/SceneData.hpp
    )

    set(MACOS_APP_IO_SOURCES
        ${CMAKE_SOURCE_DIR}/src/io/GltfLoader.cpp
        ${CMAKE_SOURCE_DIR}/src/io/GltfLoader.hpp
        ${CMAKE_SOURCE_DIR}/src/io/PlyWriter.cpp
        ${CMAKE_SOURCE_DIR}/src/io/PlyWriter.hpp
        ${CMAKE_SOURCE_DIR}/src/implementationFiles/stb_image_impl.cpp
        ${CMAKE_SOURCE_DIR}/src/implementationFiles/stb_image_write_impl.cpp
        ${CMAKE_SOURCE_DIR}/src/implementationFiles/tiny_gltf_impl.cpp
    )

    set(MACOS_APP_RENDERER_SOURCES
        ${CMAKE_SOURCE_DIR}/src/renderer/event.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/RendererInterface.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalBindings.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalBuffer.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalBuffer.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalCommandScheduler.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalCommandScheduler.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalConversionPass.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalConversionPass.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDeviceContext.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDeviceContext.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDiagnostics.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDispatchUtils.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDispatchUtils.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameUniformBuffer.cpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameUniformBuffer.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameResources.cpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameResources.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianBuffer.cpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianBuffer.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianRenderPass.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianRenderPass.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianSortBuffer.cpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianSortBuffer.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianSortPass.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianSortPass.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalMesh.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalMesh.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalMeshRenderPass.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalMeshRenderPass.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalPassContext.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalPipelineCache.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalPipelineCache.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderTarget.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderTarget.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderer.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderer.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderStateCache.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderStateCache.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalResourceUploader.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalResourceUploader.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalSceneResources.cpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalSceneResources.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalShaderLibrary.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalShaderLibrary.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalTexture.mm
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalTexture.hpp
    )

    set(MACOS_APP_OPTIONAL_OBJCXX_SOURCES
        ${CMAKE_SOURCE_DIR}/src/app/macos/RendererBridge.mm
        ${CMAKE_SOURCE_DIR}/src/app/macos/RendererBridge.hpp
    )
    foreach(MACOS_APP_OPTIONAL_SOURCE IN LISTS MACOS_APP_OPTIONAL_OBJCXX_SOURCES)
        if(EXISTS ${MACOS_APP_OPTIONAL_SOURCE})
            list(APPEND MACOS_APP_OBJCXX_SOURCES ${MACOS_APP_OPTIONAL_SOURCE})
        endif()
    endforeach()

    set(MACOS_APP_OPTIONAL_CORE_SOURCES
        ${CMAKE_SOURCE_DIR}/src/core/AssetFileTypes.hpp
        ${CMAKE_SOURCE_DIR}/src/core/GaussianVisibility.hpp
        ${CMAKE_SOURCE_DIR}/src/core/NumericUtils.hpp
        ${CMAKE_SOURCE_DIR}/src/core/PathUtils.hpp
        ${CMAKE_SOURCE_DIR}/src/core/RenderSettings.hpp
    )
    foreach(MACOS_APP_OPTIONAL_SOURCE IN LISTS MACOS_APP_OPTIONAL_CORE_SOURCES)
        if(EXISTS ${MACOS_APP_OPTIONAL_SOURCE})
            list(APPEND MACOS_APP_CORE_SOURCES ${MACOS_APP_OPTIONAL_SOURCE})
        endif()
    endforeach()

    set(MACOS_APP_OPTIONAL_RENDERER_SOURCES
        ${CMAKE_SOURCE_DIR}/src/renderer/RenderCommandQueue.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/RendererAssetSession.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalBindingValidation.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalConversionJob.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDebugLabels.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameCapture.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameGraph.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderTargetPool.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalResourceLedger.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalShaderSourcePackage.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalSortPlanner.hpp
        ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalUploadBatch.hpp
    )
    foreach(MACOS_APP_OPTIONAL_SOURCE IN LISTS MACOS_APP_OPTIONAL_RENDERER_SOURCES)
        if(EXISTS ${MACOS_APP_OPTIONAL_SOURCE})
            list(APPEND MACOS_APP_RENDERER_SOURCES ${MACOS_APP_OPTIONAL_SOURCE})
        endif()
    endforeach()

    set(MACOS_APP_SWIFTUI_REQUIRED_SOURCES
        ${CMAKE_SOURCE_DIR}/src/app/macos/AppState.swift
        ${CMAKE_SOURCE_DIR}/src/app/macos/ContentView.swift
        ${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.swift
        ${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.hpp
        ${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.mm
    )
    set(MACOS_APP_HAS_SWIFTUI_SOURCES ON)
    foreach(MACOS_APP_SWIFTUI_SOURCE IN LISTS MACOS_APP_SWIFTUI_REQUIRED_SOURCES)
        if(NOT EXISTS ${MACOS_APP_SWIFTUI_SOURCE})
            set(MACOS_APP_HAS_SWIFTUI_SOURCES OFF)
        endif()
    endforeach()

    set(MESH2SPLAT_USE_SWIFTUI_APP OFF)
    if(MESH2SPLAT_ENABLE_SWIFTUI_APP AND MACOS_APP_HAS_SWIFTUI_SOURCES)
        set(MESH2SPLAT_USE_SWIFTUI_APP ON)
        list(REMOVE_ITEM MACOS_APP_OBJCXX_SOURCES ${CMAKE_SOURCE_DIR}/src/app/macos/MacApp.mm)
        list(APPEND MACOS_APP_OBJCXX_SOURCES
            ${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.hpp
            ${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.mm
        )
        list(APPEND MACOS_APP_SWIFTUI_SOURCES ${MACOS_APP_SWIFTUI_REQUIRED_SOURCES})
        list(REMOVE_ITEM MACOS_APP_SWIFTUI_SOURCES
            ${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.hpp
            ${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.mm
        )

        set(MACOS_APP_OPTIONAL_SWIFTUI_SOURCES
            ${CMAKE_SOURCE_DIR}/src/app/macos/DocumentActions.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/InspectorPanel.swift
        )
        foreach(MACOS_APP_OPTIONAL_SOURCE IN LISTS MACOS_APP_OPTIONAL_SWIFTUI_SOURCES)
            if(EXISTS ${MACOS_APP_OPTIONAL_SOURCE})
                list(APPEND MACOS_APP_SWIFTUI_SOURCES ${MACOS_APP_OPTIONAL_SOURCE})
            endif()
        endforeach()
    elseif(MESH2SPLAT_ENABLE_SWIFTUI_APP)
        message(STATUS "SwiftUI app frontend disabled because SwiftUI entry sources are not present yet.")
    endif()

    set(METAL_APP_SOURCES
        ${MACOS_APP_OBJCXX_SOURCES}
        ${MACOS_APP_SWIFTUI_SOURCES}
        ${MACOS_APP_CORE_SOURCES}
        ${MACOS_APP_IO_SOURCES}
        ${MACOS_APP_RENDERER_SOURCES}
    )

    add_executable(Mesh2SplatMetal MACOSX_BUNDLE ${METAL_APP_SOURCES} ${METAL_SHADER_SOURCES})
    source_group("App/Objective-C++" FILES ${MACOS_APP_OBJCXX_SOURCES})
    if(MACOS_APP_SWIFTUI_SOURCES)
        source_group("App/SwiftUI" FILES ${MACOS_APP_SWIFTUI_SOURCES})
    endif()
    source_group("Core" FILES ${MACOS_APP_CORE_SOURCES})
    source_group("IO" FILES ${MACOS_APP_IO_SOURCES})
    source_group("Renderer/Metal" FILES ${MACOS_APP_RENDERER_SOURCES})
    if(METAL_SHADER_SOURCES)
        source_group("Shaders/Metal" FILES ${METAL_SHADER_SOURCES})
    endif()
    target_compile_features(Mesh2SplatMetal PRIVATE cxx_std_17)
    target_compile_options(Mesh2SplatMetal PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
    if(MESH2SPLAT_USE_SWIFTUI_APP)
        target_compile_options(Mesh2SplatMetal PRIVATE
            $<$<COMPILE_LANGUAGE:Swift>:-import-objc-header>
            $<$<COMPILE_LANGUAGE:Swift>:${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.hpp>
        )
        target_compile_definitions(Mesh2SplatMetal PRIVATE MESH2SPLAT_USE_SWIFTUI_APP=1)
    endif()
    target_include_directories(Mesh2SplatMetal PRIVATE ${CMAKE_SOURCE_DIR}/src)
    target_include_directories(Mesh2SplatMetal SYSTEM PRIVATE ${THIRD_PARTY_DIR})

    find_library(APPKIT_LIBRARY AppKit REQUIRED)
    find_library(METAL_LIBRARY Metal REQUIRED)
    find_library(METALKIT_LIBRARY MetalKit REQUIRED)
    find_library(QUARTZCORE_LIBRARY QuartzCore REQUIRED)
    find_library(SWIFTUI_LIBRARY SwiftUI REQUIRED)
    find_library(UNIFORMTYPEIDENTIFIERS_LIBRARY UniformTypeIdentifiers REQUIRED)

    target_link_libraries(Mesh2SplatMetal PRIVATE
        ${APPKIT_LIBRARY}
        ${METAL_LIBRARY}
        ${METALKIT_LIBRARY}
        ${QUARTZCORE_LIBRARY}
        ${SWIFTUI_LIBRARY}
        ${UNIFORMTYPEIDENTIFIERS_LIBRARY}
    )

    set_target_properties(Mesh2SplatMetal PROPERTIES
        MACOSX_BUNDLE_BUNDLE_NAME "Mesh2Splat Metal"
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.mesh2splat.metal"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
        MACOSX_BUNDLE_BUNDLE_VERSION "1"
        MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/cmake/macos/Info.plist.in
        RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin/Metal
        XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.mesh2splat.metal"
        XCODE_ATTRIBUTE_SWIFT_VERSION "5.9"
    )

    if(MESH2SPLAT_USE_SWIFTUI_APP)
        set_target_properties(Mesh2SplatMetal PROPERTIES
            XCODE_ATTRIBUTE_SWIFT_OBJC_BRIDGING_HEADER "${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.hpp"
        )
    endif()

    if(METAL_SHADER_SOURCES)
        add_custom_command(TARGET Mesh2SplatMetal POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_CONTENT_DIR:Mesh2SplatMetal>/Resources/Shaders"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                ${METAL_SHADER_SOURCES}
                "$<TARGET_BUNDLE_CONTENT_DIR:Mesh2SplatMetal>/Resources/Shaders"
        )

        find_program(XCRUN_EXECUTABLE xcrun)
        if(XCRUN_EXECUTABLE)
            execute_process(
                COMMAND ${XCRUN_EXECUTABLE} -sdk macosx --find metal
                RESULT_VARIABLE METAL_COMPILER_RESULT
                OUTPUT_VARIABLE METAL_COMPILER
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
            )
            execute_process(
                COMMAND ${XCRUN_EXECUTABLE} -sdk macosx --find metallib
                RESULT_VARIABLE METALLIB_RESULT
                OUTPUT_VARIABLE METALLIB
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
            )
        else()
            set(METAL_COMPILER_RESULT 1)
            set(METALLIB_RESULT 1)
        endif()

        if(XCRUN_EXECUTABLE AND METAL_COMPILER_RESULT EQUAL 0 AND METALLIB_RESULT EQUAL 0)
            set(METAL_LIBRARY_OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/Mesh2SplatMetal.metallib)
            set(METAL_AIR_OUTPUTS)

            foreach(METAL_SHADER_SOURCE IN LISTS METAL_SHADER_SOURCES)
                get_filename_component(METAL_SHADER_NAME ${METAL_SHADER_SOURCE} NAME_WE)
                set(METAL_AIR_OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${METAL_SHADER_NAME}.air)
                add_custom_command(
                    OUTPUT ${METAL_AIR_OUTPUT}
                    COMMAND ${XCRUN_EXECUTABLE} -sdk macosx metal -c ${METAL_SHADER_SOURCE} -o ${METAL_AIR_OUTPUT}
                    DEPENDS ${METAL_SHADER_SOURCE}
                    COMMENT "Compiling ${METAL_SHADER_NAME}.metal"
                    VERBATIM
                )
                list(APPEND METAL_AIR_OUTPUTS ${METAL_AIR_OUTPUT})
            endforeach()

            add_custom_command(
                OUTPUT ${METAL_LIBRARY_OUTPUT}
                COMMAND ${XCRUN_EXECUTABLE} -sdk macosx metallib ${METAL_AIR_OUTPUTS} -o ${METAL_LIBRARY_OUTPUT}
                DEPENDS ${METAL_AIR_OUTPUTS}
                COMMENT "Linking Mesh2Splat Metal shader library"
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
            message(WARNING "Metal shader tools are unavailable; skipping .metallib generation for now. Install them with: xcodebuild -downloadComponent MetalToolchain")
        endif()
    endif()
endif()
