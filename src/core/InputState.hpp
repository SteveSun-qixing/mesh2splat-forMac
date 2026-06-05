#pragma once

#include <array>
#include <cstddef>

namespace mesh2splat::core {

struct InputState {
    static constexpr std::size_t KeyCount = 256;
    static constexpr std::size_t MouseButtonCount = 3;

    std::array<bool, KeyCount> keysDown{};
    std::array<bool, MouseButtonCount> mouseButtonsDown{};

    double mouseX = 0.0;
    double mouseY = 0.0;
    double mouseDeltaX = 0.0;
    double mouseDeltaY = 0.0;
    double scrollDeltaX = 0.0;
    double scrollDeltaY = 0.0;

    void beginFrame()
    {
        mouseDeltaX = 0.0;
        mouseDeltaY = 0.0;
        scrollDeltaX = 0.0;
        scrollDeltaY = 0.0;
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

    void updateMousePosition(double x, double y)
    {
        mouseDeltaX += x - mouseX;
        mouseDeltaY += y - mouseY;
        mouseX = x;
        mouseY = y;
    }

    void addScrollDelta(double x, double y)
    {
        scrollDeltaX += x;
        scrollDeltaY += y;
    }
};

} // namespace mesh2splat::core
