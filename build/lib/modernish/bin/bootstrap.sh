#! /usr/bin/env modernish
#! use safe
#! use sys/base/mktemp
#! use sys/cmd/harden
#! use sys/cmd/extern
#! use var/local

# configure bootstrap — modernish bundle target
# This file exists so install.sh -B can bundle the modules we need.
# The real orchestrator is configure.sh at the project root.
putln "modernish ${MSH_VERSION} initialized on ${MSH_SHELL}"
