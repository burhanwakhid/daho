cmake_minimum_required(VERSION 3.10)
project(h2o_wrapper C)

# Locate H2O portably across platforms instead of hardcoding a path:
#   - macOS / Homebrew (Apple Silicon): /opt/homebrew
#   - macOS / Homebrew (Intel) & source installs: /usr/local
#   - Linux (apt, etc.): /usr, /usr/lib/<triplet>
# Override on the command line if needed:
#   cmake -DH2O_INCLUDE_DIR=... -DH2O_EVLOOP_LIB=...
find_path(H2O_INCLUDE_DIR
    NAMES h2o.h
    HINTS
        /opt/homebrew/include
        /usr/local/include
        /usr/include
)

find_library(H2O_EVLOOP_LIB
    NAMES h2o-evloop
    HINTS
        /opt/homebrew/lib
        /usr/local/lib
        /usr/lib
        /usr/lib/x86_64-linux-gnu
        /usr/lib/aarch64-linux-gnu
)

if(NOT H2O_INCLUDE_DIR OR NOT H2O_EVLOOP_LIB)
    message(FATAL_ERROR
        "H2O (h2o-evloop) not found.\n"
        "Install it (e.g. `brew install h2o`, or build libh2o-evloop), or pass\n"
        "-DH2O_INCLUDE_DIR=<dir> and -DH2O_EVLOOP_LIB=<file> to cmake.")
endif()

message(STATUS "H2O headers: ${H2O_INCLUDE_DIR}")
message(STATUS "H2O evloop lib: ${H2O_EVLOOP_LIB}")

# libh2o-evloop itself depends on OpenSSL and zlib. Homebrew's package
# happens to ship a *shared* libh2o-evloop.dylib, which records its own
# transitive dependencies, so this was never needed on macOS — but a
# from-source build (e.g. in Docker, since H2O has no Debian/Ubuntu
# package) produces a *static* libh2o-evloop.a by default, which does not
# carry transitive link deps, so they must be linked explicitly here or
# the final link fails with undefined SSL_*/X509_*/deflate/inflate symbols.
find_package(OpenSSL REQUIRED)
find_package(ZLIB REQUIRED)

add_library(h2o_wrapper SHARED
    h2o_wrapper.c
    include/dart_api_dl.c
)

target_include_directories(h2o_wrapper PRIVATE include ${H2O_INCLUDE_DIR})
target_link_libraries(h2o_wrapper ${H2O_EVLOOP_LIB} OpenSSL::SSL OpenSSL::Crypto ZLIB::ZLIB)
