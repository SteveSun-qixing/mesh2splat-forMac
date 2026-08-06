cmake_minimum_required(VERSION 3.15)
project(Mesh2Splat LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(APPLE)
    enable_language(OBJCXX)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum macOS deployment target")
endif()

set(THIRD_PARTY_DIR ${CMAKE_SOURCE_DIR}/thirdParty)
set(METAL_SHADER_DIR ${CMAKE_SOURCE_DIR}/shaders/metal)
file(GLOB METAL_SHADER_SOURCES ${METAL_SHADER_DIR}/*.metal)
if(METAL_SHADER_SOURCES)
    set_source_files_properties(${METAL_SHADER_SOURCES} PROPERTIES HEADER_FILE_ONLY TRUE)
endif()

# ---------------------------------------------------------------------------
# Mesh2SplatMetalLib
#
# API-neutral core, IO and Metal renderer backend. No AppKit/MTKView
# dependencies, so the same library can serve the macOS app, headless tests
# and the command line converter.
# ---------------------------------------------------------------------------

set(M2S_CORE_SOURCES
    ${CMAKE_SOURCE_DIR}/src/core/AssetFileTypes.hpp
    ${CMAKE_SOURCE_DIR}/src/core/CameraController.cpp
    ${CMAKE_SOURCE_DIR}/src/core/CameraController.hpp
    ${CMAKE_SOURCE_DIR}/src/core/ConversionSettings.hpp
    ${CMAKE_SOURCE_DIR}/src/core/FrameData.hpp
    ${CMAKE_SOURCE_DIR}/src/core/GaussianData.hpp
    ${CMAKE_SOURCE_DIR}/src/core/GaussianVisibility.hpp
    ${CMAKE_SOURCE_DIR}/src/core/GpuTypes.hpp
    ${CMAKE_SOURCE_DIR}/src/core/InputState.hpp
    ${CMAKE_SOURCE_DIR}/src/core/MeshData.hpp
    ${CMAKE_SOURCE_DIR}/src/core/NumericUtils.hpp
    ${CMAKE_SOURCE_DIR}/src/core/PathUtils.hpp
    ${CMAKE_SOURCE_DIR}/src/core/PrimitiveMeshFactory.cpp
    ${CMAKE_SOURCE_DIR}/src/core/PrimitiveMeshFactory.hpp
    ${CMAKE_SOURCE_DIR}/src/core/RenderSettings.hpp
    ${CMAKE_SOURCE_DIR}/src/core/SceneData.hpp
)

set(M2S_IO_SOURCES
    ${CMAKE_SOURCE_DIR}/src/io/GltfLoader.cpp
    ${CMAKE_SOURCE_DIR}/src/io/GltfLoader.hpp
    ${CMAKE_SOURCE_DIR}/src/io/PlyReader.cpp
    ${CMAKE_SOURCE_DIR}/src/io/PlyReader.hpp
    ${CMAKE_SOURCE_DIR}/src/io/PlyWriter.cpp
    ${CMAKE_SOURCE_DIR}/src/io/PlyWriter.hpp
    ${CMAKE_SOURCE_DIR}/src/implementationFiles/stb_image_impl.cpp
    ${CMAKE_SOURCE_DIR}/src/implementationFiles/stb_image_write_impl.cpp
    ${CMAKE_SOURCE_DIR}/src/implementationFiles/tiny_gltf_impl.cpp
)

set(M2S_RENDERER_SOURCES
    ${CMAKE_SOURCE_DIR}/src/renderer/event.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/RenderCommandQueue.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/RendererAssetSession.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/RendererInterface.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalBindingValidation.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalBindings.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalBuffer.mm
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalBuffer.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalCommandScheduler.mm
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalCommandScheduler.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalConversionJob.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalConversionPass.mm
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalConversionPass.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDebugLabels.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDeviceContext.mm
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDeviceContext.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDiagnostics.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDispatchUtils.mm
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalDispatchUtils.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameCapture.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameGraph.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameResources.cpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameResources.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameUniformBuffer.cpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalFrameUniformBuffer.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianBuffer.cpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianBuffer.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianRenderPass.mm
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianRenderPass.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianShadowPass.mm
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalGaussianShadowPass.hpp
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
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderTargetPool.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderer.mm
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderer.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderStateCache.mm
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalRenderStateCache.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalResourceLedger.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalResourceUploader.mm
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalResourceUploader.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalSceneResources.cpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalSceneResources.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalShaderLibrary.mm
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalShaderLibrary.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalSortPlanner.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalTexture.mm
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalTexture.hpp
    ${CMAKE_SOURCE_DIR}/src/renderer/metal/MetalUploadBatch.hpp
)

add_library(Mesh2SplatMetalLib STATIC
    ${M2S_CORE_SOURCES}
    ${M2S_IO_SOURCES}
    ${M2S_RENDERER_SOURCES}
)
target_compile_features(Mesh2SplatMetalLib PRIVATE cxx_std_17)
target_compile_options(Mesh2SplatMetalLib PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
target_include_directories(Mesh2SplatMetalLib PUBLIC ${CMAKE_SOURCE_DIR}/src)
target_include_directories(Mesh2SplatMetalLib SYSTEM PUBLIC ${THIRD_PARTY_DIR})
source_group("Core" FILES ${M2S_CORE_SOURCES})
source_group("IO" FILES ${M2S_IO_SOURCES})
source_group("Renderer/Metal" FILES ${M2S_RENDERER_SOURCES})

# ---------------------------------------------------------------------------
# macOS app
# ---------------------------------------------------------------------------

if(APPLE)
    set(MESH2SPLAT_ENABLE_SWIFTUI_APP OFF)
    if(CMAKE_GENERATOR MATCHES "^(Xcode|Ninja|Ninja Multi-Config)$")
        enable_language(Swift)
        set(MESH2SPLAT_ENABLE_SWIFTUI_APP ON)
    else()
        message(STATUS "SwiftUI app frontend disabled for ${CMAKE_GENERATOR}; use Xcode or Ninja to enable Swift sources.")
    endif()

    set(MACOS_APP_OBJCXX_SOURCES
        ${CMAKE_SOURCE_DIR}/src/app/macos/MacApp.mm
        ${CMAKE_SOURCE_DIR}/src/app/macos/MetalView.mm
        ${CMAKE_SOURCE_DIR}/src/app/macos/MetalView.hpp
    )

    set(MACOS_APP_SWIFTUI_SOURCES)

    set(MACOS_APP_OPTIONAL_OBJCXX_SOURCES
        ${CMAKE_SOURCE_DIR}/src/app/macos/RendererBridge.mm
        ${CMAKE_SOURCE_DIR}/src/app/macos/RendererBridge.hpp
    )
    foreach(MACOS_APP_OPTIONAL_SOURCE IN LISTS MACOS_APP_OPTIONAL_OBJCXX_SOURCES)
        if(EXISTS ${MACOS_APP_OPTIONAL_SOURCE})
            list(APPEND MACOS_APP_OBJCXX_SOURCES ${MACOS_APP_OPTIONAL_SOURCE})
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
            ${CMAKE_SOURCE_DIR}/src/app/macos/MacBridgeTypes.hpp
            ${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.hpp
            ${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.mm
        )
        list(APPEND MACOS_APP_SWIFTUI_SOURCES ${MACOS_APP_SWIFTUI_REQUIRED_SOURCES})
        list(REMOVE_ITEM MACOS_APP_SWIFTUI_SOURCES
            ${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.hpp
            ${CMAKE_SOURCE_DIR}/src/app/macos/SwiftUIApp.mm
        )

        set(MACOS_APP_OPTIONAL_SWIFTUI_SOURCES
            ${CMAKE_SOURCE_DIR}/src/app/macos/AppCommands.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/AppEnvironment.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/ConversionProgressPanel.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/DiagnosticsPanel.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/DocumentActions.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/ExportWorkflowPanel.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/InspectorPanel.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/MetricViews.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/RendererStatusFormatting.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/RenderControlsPanel.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/RenderPresetStore.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/ResourceTelemetryPanel.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/SceneDropZone.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/SceneWorkflowPanel.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/SidebarPanels.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/StatusBarView.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/TelemetryPanel.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/ViewportOverlay.swift
            ${CMAKE_SOURCE_DIR}/src/app/macos/ViewportToolbar.swift
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
    )

    add_executable(Mesh2SplatMetal MACOSX_BUNDLE ${METAL_APP_SOURCES} ${METAL_SHADER_SOURCES})
    source_group("App/Objective-C++" FILES ${MACOS_APP_OBJCXX_SOURCES})
    if(MACOS_APP_SWIFTUI_SOURCES)
        source_group("App/SwiftUI" FILES ${MACOS_APP_SWIFTUI_SOURCES})
    endif()
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
        target_compile_definitions(Mesh2SplatMetal PRIVATE MESH2SPLAT_USE_SWIFTUI_APP)
    endif()

    find_library(APPKIT_LIBRARY AppKit REQUIRED)
    find_library(METAL_LIBRARY Metal REQUIRED)
    find_library(METALKIT_LIBRARY MetalKit REQUIRED)
    find_library(QUARTZCORE_LIBRARY QuartzCore REQUIRED)
    find_library(SWIFTUI_LIBRARY SwiftUI REQUIRED)
    find_library(UNIFORMTYPEIDENTIFIERS_LIBRARY UniformTypeIdentifiers REQUIRED)

    target_link_libraries(Mesh2SplatMetal PRIVATE
        Mesh2SplatMetalLib
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

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

add_executable(CoreIoSmokeTest
    ${CMAKE_SOURCE_DIR}/tests/CoreIoSmokeTest.cpp
)
target_compile_features(CoreIoSmokeTest PRIVATE cxx_std_17)
target_link_libraries(CoreIoSmokeTest PRIVATE Mesh2SplatMetalLib)

if(EXISTS ${CMAKE_SOURCE_DIR}/tests/MetalGpuSmokeTest.mm)
    add_executable(MetalGpuSmokeTest
        ${CMAKE_SOURCE_DIR}/tests/MetalGpuSmokeTest.mm
    )
    target_compile_features(MetalGpuSmokeTest PRIVATE cxx_std_17)
    target_compile_options(MetalGpuSmokeTest PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fno-objc-arc>)
    target_link_options(MetalGpuSmokeTest PRIVATE -lobjc)
    target_link_libraries(MetalGpuSmokeTest PRIVATE Mesh2SplatMetalLib)
    if(APPLE)
        find_library(METAL_LIBRARY Metal REQUIRED)
        find_library(APPKIT_LIBRARY AppKit REQUIRED)
        find_library(FOUNDATION_LIBRARY Foundation REQUIRED)
        target_link_libraries(MetalGpuSmokeTest PRIVATE
            ${METAL_LIBRARY}
            ${APPKIT_LIBRARY}
            ${FOUNDATION_LIBRARY}
        )
    endif()
endif()

# ---------------------------------------------------------------------------
# Command line converter
# ---------------------------------------------------------------------------

if(EXISTS ${CMAKE_SOURCE_DIR}/src/app/cli/Mesh2SplatConvert.mm)
    add_executable(Mesh2SplatConvert
        ${CMAKE_SOURCE_DIR}/src/app/cli/Mesh2SplatConvert.mm
    )
elseif(EXISTS ${CMAKE_SOURCE_DIR}/src/app/cli/Mesh2SplatConvert.cpp)
    add_executable(Mesh2SplatConvert
        ${CMAKE_SOURCE_DIR}/src/app/cli/Mesh2SplatConvert.cpp
    )
endif()
if(TARGET Mesh2SplatConvert)
    target_compile_features(Mesh2SplatConvert PRIVATE cxx_std_17)
    target_compile_options(Mesh2SplatConvert PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fno-objc-arc>)
    target_link_options(Mesh2SplatConvert PRIVATE -lobjc)
    target_link_libraries(Mesh2SplatConvert PRIVATE Mesh2SplatMetalLib)
    set_target_properties(Mesh2SplatConvert PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin
    )
    if(APPLE)
        find_library(METAL_LIBRARY Metal REQUIRED)
        find_library(APPKIT_LIBRARY AppKit REQUIRED)
        find_library(FOUNDATION_LIBRARY Foundation REQUIRED)
        target_link_libraries(Mesh2SplatConvert PRIVATE
            ${METAL_LIBRARY}
            ${APPKIT_LIBRARY}
            ${FOUNDATION_LIBRARY}
        )
    endif()
endif()
