#!/bin/bash
cd "$(dirname "$0")/../SynthApp"
swiftc \
  Theme.swift \
  FileNode.swift \
  Document.swift \
  MarkdownRenderer.swift \
  AIPanel.swift \
  main.swift \
  -import-objc-header BridgingHeader.h \
  -L ../synth-core/target/release \
  -I ../synth-core \
  -lsynth_core \
  -o Synth
