# Test fixture licences

Every fixture used by the SplitKitViews tests is listed here with its origin and licence.

## Images (ImageViewer)

| Path | Origin | Licence |
|---|---|---|
| `Images/pixel.png` | Self-made: an 8×8 gradient, generated for this repository | MIT (the repository licence) |
| `Images/pixel.jpg` | Self-made: the same gradient as JPEG | MIT |
| `Images/corrupt.png` | Self-made: 17 bytes of text with a `.png` extension (decoding must fail) | MIT |
| `Images/notes.txt` | Self-made: a text file (not an image; `.unsupportedFile`) | MIT |

## Models (ModelViewer3D)

Downloaded by `Spikes/SpikeB-RealityKit/scripts/fetch-corpus.sh` from
[KhronosGroup/glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets) (branch `main`) into `Models/`;
the licence of each model comes from its `metadata.json`. Reference screenshots (`Models/<Model>/screenshot/`) carry the
same licence as their model. The hand-made error fixtures under `Models/Errors/` (`malformed.gltf`, `missing-buffer.gltf`,
`fake.fbx`) are original to this repository (MIT). The 2 Artifex exports spec §10 asks for are not in the corpus yet
(a recorded gap, spec §11.2).

| Model | File | Row | Licence | Artist | Owner | Year | Licence URL |
|---|---|---|---|---|---|---|---|
| Box | glTF/Box.gltf | required | CC-BY-4.0 | Cesium | Cesium | 2017 | https://creativecommons.org/licenses/by/4.0/legalcode |
| BoxTextured | glTF/BoxTextured.gltf | required | CC-BY-4.0 | Cesium | Cesium | 2017 | https://creativecommons.org/licenses/by/4.0/legalcode |
| Duck | glTF-Binary/Duck.glb | required | SCEA | Sony | Sony | 2006 | https://github.com/KhronosGroup/glTF-Sample-Assets/blob/main/LICENSES/SCEA.txt |
| DamagedHelmet | glTF-Binary/DamagedHelmet.glb | required | CC-BY-4.0 | ctxwing | ctxwing | 2018 | https://creativecommons.org/licenses/by/4.0/legalcode |
| CesiumMilkTruck | glTF/CesiumMilkTruck.gltf | required | CC-BY-4.0 | Cesium | Cesium | 2017 | https://creativecommons.org/licenses/by/4.0/legalcode |
| CesiumMan | glTF-Binary/CesiumMan.glb | optional | CC-BY-4.0 | Cesium | Cesium | 2017 | https://creativecommons.org/licenses/by/4.0/legalcode |
| RiggedSimple | glTF-Binary/RiggedSimple.glb | optional | CC-BY-4.0 | Cesium | Cesium | 2017 | https://creativecommons.org/licenses/by/4.0/legalcode |
| AnimatedMorphCube | glTF-Binary/AnimatedMorphCube.glb | optional | CC0-1.0 | Microsoft | Public | 2017 | https://creativecommons.org/publicdomain/zero/1.0/legalcode |
| TransmissionTest | glTF-Binary/TransmissionTest.glb | optional | CC0-1.0 | Adobe | Public | 2020 | https://creativecommons.org/publicdomain/zero/1.0/legalcode |
| ClearCoatTest | glTF-Binary/ClearCoatTest.glb | optional | CC-BY-4.0 | Ed Mackey | Analytical Graphics, Inc. | 2020 | https://creativecommons.org/licenses/by/4.0/legalcode |
| Box | glTF-Draco/Box.gltf | optional | CC-BY-4.0 | Cesium | Cesium | 2017 | https://creativecommons.org/licenses/by/4.0/legalcode |
| Duck | glTF-Draco/Duck.gltf | optional | SCEA | Sony | Sony | 2006 | https://github.com/KhronosGroup/glTF-Sample-Assets/blob/main/LICENSES/SCEA.txt |
