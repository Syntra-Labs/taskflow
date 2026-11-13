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
	ln -sf $(CURDIR)/governance/verify-governance $(BIN_DIR)/verify-governance
	ln -sf $(CURDIR)/governance/agent-governance-hook $(BIN_DIR)/agent-governance-hook
	ln -sf $(CURDIR)/governance/universal-governance-wrapper $(BIN_DIR)/universal-governance-wrapper
	ln -sf $(CURDIR)/governance/sync-calendar-policy $(BIN_DIR)/sync-calendar-policy
	ln -sf $(CURDIR)/governance/log-practice-event $(BIN_DIR)/log-practice-event
	ln -sf $(CURDIR)/governance/log-session-event $(BIN_DIR)/log-session-event

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all install clean
