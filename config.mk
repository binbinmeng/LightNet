.SUFFIXES:
MAJOR = 0
MINOR = 1
MICRO = 0
BUILD_DIR ?= build
CUDA_INSTALL_DIR ?= /usr/local/cuda
DEBUG ?= no
INSTALL_DIR ?= /usr/local
PKGCONFIG_DIR ?= /usr/local/lib/pkgconfig
TARGET ?= lightnet
WITH_CUDA ?= no
WITH_CUDNN ?= no