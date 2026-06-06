cmake_minimum_required(VERSION 3.10)
project(h2o_wrapper C)

set(HOMEBREW_INCLUDE_DIR "/opt/homebrew/include")
set(HOMEBREW_LIB_DIR "/opt/homebrew/lib")

add_library(h2o_wrapper SHARED 
    h2o_wrapper.c
    include/dart_api_dl.c
)

target_include_directories(h2o_wrapper PRIVATE include ${HOMEBREW_INCLUDE_DIR})

# Mencari secara SPESIFIK versi evloop, bukan versi libuv
find_library(H2O_EVLOOP_LIB NAMES h2o-evloop PATHS ${HOMEBREW_LIB_DIR} REQUIRED)

target_link_libraries(h2o_wrapper ${H2O_EVLOOP_LIB})