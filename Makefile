CXX ?= g++
CXXFLAGS ?= -std=c++20 -O3 -Wall -Wextra -fPIC

BUILD_DIR ?= build
LIB_DIR ?= $(HOME)/.local/lib
BIN_DIR ?= $(HOME)/.local/bin
ROUTER_DIR ?= vendor/router

TARGETS = $(BUILD_DIR)/libtaskflow_dtl.so $(BUILD_DIR)/libtaskflow_anchor.so $(BUILD_DIR)/manifold

all: $(TARGETS)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/libtaskflow_dtl.so: c_src/dtl_engine.cpp c_src/dtl_engine.h | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -shared -o $@ c_src/dtl_engine.cpp

$(BUILD_DIR)/libtaskflow_anchor.so: c_src/anchor_engine.cpp c_src/anchor_engine.h | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -shared -o $@ c_src/anchor_engine.cpp

$(BUILD_DIR)/manifold: $(ROUTER_DIR)/src/manifold.cpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $(ROUTER_DIR)/src/manifold.cpp

install: all
	mkdir -p $(LIB_DIR) $(BIN_DIR)
	cp $(BUILD_DIR)/*.so $(LIB_DIR)/
	ln -sf $(CURDIR)/bin/taskflow $(BIN_DIR)/taskflow
	ln -sf $(CURDIR)/bin/taskflow $(BIN_DIR)/agent

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all install clean
