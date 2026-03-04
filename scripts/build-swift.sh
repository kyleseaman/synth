#!/bin/bash
cd "$(dirname "$0")/../SynthApp"
swiftc *.swift -o Synth
