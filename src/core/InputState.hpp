#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace mesh2splat::core {

struct InputState {
    static constexpr std::size_t KeyCount = 256;
    static constexpr std::size_t MouseButtonCount = 3;

    enum MouseButton : std::size_t {
        MouseButtonLeft = 0,
        MouseButtonRight = 1,
        MouseButtonMiddle = 2,
    };

    enum Modifier : uint32_t {
        ModifierShift = 1u << 0,
        ModifierControl = 1u << 1,
        ModifierOption = 1u << 2,
        ModifierCommand = 1u << 3,
        ModifierCapsLock = 1u << 4,
        ModifierFunction = 1u << 5,
    };

    enum class PointerDevice : uint8_t {
        Mouse,
        Trackpad,
    };

    std::array<bool, KeyCount> keysDown{};
    std::array<bool, MouseButtonCount> mouseButtonsDown{};

    uint32_t modifierMask = 0;
    double frameDeltaSeconds = 0.0;
    uint32_t viewportWidth = 0;
    uint32_t viewportHeight = 0;
    float viewportAspect = 1.0f;
    bool hasViewportAspect = false;

    double mouseX = 0.0;
    double mouseY = 0.0;
    double mouseDeltaX = 0.0;
    double mouseDeltaY = 0.0;
    double trackpadDeltaX = 0.0;
    double trackpadDeltaY = 0.0;
    PointerDevice lastPointerDevice = PointerDevice::Mouse;
    double scrollDeltaX = 0.0;
    double scrollDeltaY = 0.0;

    double orbitDeltaX = 0.0;
    double orbitDeltaY = 0.0;
    double panDeltaX = 0.0;
    double panDeltaY = 0.0;
    double dollyDelta = 0.0;
    bool resetViewRequested = false;

    void beginFrame()
    {
        frameDeltaSeconds = 0.0;
        mouseDeltaX = 0.0;
        mouseDeltaY = 0.0;
        trackpadDeltaX = 0.0;
        trackpadDeltaY = 0.0;
        scrollDeltaX = 0.0;
        scrollDeltaY = 0.0;
        orbitDeltaX = 0.0;
        orbitDeltaY = 0.0;
        panDeltaX = 0.0;
        panDeltaY = 0.0;
        dollyDelta = 0.0;
        resetViewRequested = false;
    }

    void setKey(std::size_t keyCode, bool down)
    {
        if (keyCode < keysDown.size()) {
            keysDown[keyCode] = down;
        }
    }

    void setMouseButton(std::size_t button, bool down)
    {
        if (button < mouseButtonsDown.size()) {
            mouseButtonsDown[button] = down;
        }
    }

    void setModifier(Modifier modifier, bool down)
    {
        if (down) {
            modifierMask |= static_cast<uint32_t>(modifier);
        } else {
            modifierMask &= ~static_cast<uint32_t>(modifier);
        }
    }

    void setModifiers(uint32_t modifiers)
    {
        modifierMask = modifiers;
    }

    bool isModifierDown(Modifier modifier) const
    {
        return (modifierMask & static_cast<uint32_t>(modifier)) != 0;
    }

    void setFrameDeltaSeconds(double deltaTimeSeconds)
    {
        frameDeltaSeconds = deltaTimeSeconds > 0.0 ? deltaTimeSeconds : 0.0;
    }

    void setViewportSize(uint32_t width, uint32_t height)
    {
        viewportWidth = width;
        viewportHeight = height;
        viewportAspect = height == 0 ? 1.0f : static_cast<float>(width) / static_cast<float>(height);
        hasViewportAspect = true;
    }

    void setViewportAspect(float aspectRatio)
    {
        viewportAspect = aspectRatio > 0.0f ? aspectRatio : 1.0f;
        hasViewportAspect = true;
    }

    void updateMousePosition(double x, double y)
    {
        mouseDeltaX += x - mouseX;
        mouseDeltaY += y - mouseY;
        mouseX = x;
        mouseY = y;
        lastPointerDevice = PointerDevice::Mouse;
    }

    void addMouseDelta(double x, double y)
    {
        mouseDeltaX += x;
        mouseDeltaY += y;
        lastPointerDevice = PointerDevice::Mouse;
    }

    void addTrackpadDelta(double x, double y)
    {
        trackpadDeltaX += x;
        trackpadDeltaY += y;
        lastPointerDevice = PointerDevice::Trackpad;
    }

    void addPointerDelta(double x, double y, PointerDevice device)
    {
        if (device == PointerDevice::Trackpad) {
            addTrackpadDelta(x, y);
        } else {
            addMouseDelta(x, y);
        }
    }

    void addScrollDelta(double x, double y)
    {
        scrollDeltaX += x;
        scrollDeltaY += y;
    }

    void addOrbitDelta(double x, double y)
    {
        orbitDeltaX += x;
        orbitDeltaY += y;
    }

    void addPanDelta(double x, double y)
    {
        panDeltaX += x;
        panDeltaY += y;
    }

    void addDollyDelta(double delta)
    {
        dollyDelta += delta;
    }

    void requestResetView()
    {
        resetViewRequested = true;
    }
};

} // namespace mesh2splat::core
