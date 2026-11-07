# ONNX Runtime

PitcheeCore currently targets ONNX Runtime `1.24.2`. The binary XCFramework and
its C/C++ headers are intentionally not committed to this repository.

From the repository root, restore them with:

```sh
./Scripts/bootstrap-native-dependencies.sh
```

The Xcode project expects this directory to contain:

```text
ONNXRuntime/
├── Headers/
├── LICENSE
└── onnxruntime.xcframework/
```

