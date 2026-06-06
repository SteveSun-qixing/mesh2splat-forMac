///////////////////////////////////////////////////////////////////////////////
//         Mesh2Splat: fast mesh to 3D gaussian splat conversion             //
//        Copyright (c) 2025 Electronic Arts Inc. All rights reserved.       //
///////////////////////////////////////////////////////////////////////////////

#pragma once

#include <cstdint>

enum class EventType {
    LoadModel,
    LoadPly,
    ViewDepth,
    RunConversion,
    SavePLY,
    EnableGaussianRendering,
    CheckShaderUpdate,
    ResizedWindow,
    UpdateTransforms
};

namespace mesh2splat::renderer {

enum class RendererInputEventType : uint32_t {
    Unknown = 0,
    Key = 1,
    MouseButton = 2,
    MouseMove = 3,
    MouseScroll = 4,
    Text = 5,
    Modifiers = 6,
    Resize = 7,
    FrameTick = 8,
};

enum class RendererInputDevice : uint32_t {
    Unknown = 0,
    Keyboard = 1,
    Mouse = 2,
    Trackpad = 3,
    Touch = 4,
    Stylus = 5,
};

enum class RendererInputAction : uint32_t {
    None = 0,
    Press = 1,
    Release = 2,
    Move = 3,
    Scroll = 4,
    Change = 5,
    Tick = 6,
    Cancel = 7,
};

enum RendererInputModifierFlag : uint32_t {
    RendererInputModifierNone = 0,
    RendererInputModifierShift = 1u << 0,
    RendererInputModifierControl = 1u << 1,
    RendererInputModifierOption = 1u << 2,
    RendererInputModifierCommand = 1u << 3,
    RendererInputModifierCapsLock = 1u << 4,
    RendererInputModifierFunction = 1u << 5,
};

struct RendererInputEvent {
    RendererInputEventType type = RendererInputEventType::Unknown;
    RendererInputDevice device = RendererInputDevice::Unknown;
    RendererInputAction action = RendererInputAction::None;
    uint64_t eventId = 0;
    double timestampSeconds = 0.0;
    uint32_t code = 0;
    uint32_t character = 0;
    uint32_t modifiers = 0;
    double x = 0.0;
    double y = 0.0;
    double deltaX = 0.0;
    double deltaY = 0.0;
    uint32_t width = 0;
    uint32_t height = 0;
    float backingScale = 1.0f;
    double deltaTimeSeconds = 0.0;
    uint64_t frameIndex = 0;
    double pressure = 0.0;
    uint32_t clickCount = 0;
    bool repeat = false;

    bool hasPosition() const
    {
        return type == RendererInputEventType::MouseButton ||
            type == RendererInputEventType::MouseMove ||
            type == RendererInputEventType::MouseScroll;
    }

    bool hasDelta() const
    {
        return deltaX != 0.0 || deltaY != 0.0;
    }
};

inline bool rendererInputHasModifier(
    const RendererInputEvent& event,
    RendererInputModifierFlag modifier)
{
    return (event.modifiers & static_cast<uint32_t>(modifier)) != 0;
}

} // namespace mesh2splat::renderer
