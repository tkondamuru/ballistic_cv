cmake_minimum_required(VERSION 3.10.2)

project(native_tracker)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Point to opencv-mobile CMake config
set(OpenCV_DIR ${CMAKE_CURRENT_SOURCE_DIR}/opencv-mobile-android/opencv-mobile-4.13.0-android/sdk/native/jni)
find_package(OpenCV REQUIRED)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${OpenCV_INCLUDE_DIRS}
)

add_library(
    native_tracker
    SHARED
    native_tracker.cpp
)

target_link_libraries(
    native_tracker
    ${OpenCV_LIBS}
    log
)
