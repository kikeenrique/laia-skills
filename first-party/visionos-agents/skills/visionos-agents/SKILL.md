---
name: visionos-agents
description: "Router for Apple Vision Pro / visionOS spatial computing development. Use when building a visionOS app and choosing which specialized skill applies: spatial SwiftUI, RealityKit (rendering, animation/physics, audio, custom ECS), ARKit providers (world/plane/hand/scene/image/object tracking, camera access), ShaderGraph and USD authoring, SharePlay/GroupActivities, visionOS WidgetKit, immersive/spatial video, or Swift Charts 3D. Start here to route to the focused skill for the task."
---

# visionOS Agents

Entry-point router for Apple Vision Pro / visionOS spatial computing work. Pick the focused skill for the task, then follow its guidance. Target the project's actual visionOS deployment target and Swift 6.2+ strict concurrency.

## Routing

| Area | Skill |
| --- | --- |
| App architecture — window vs volume vs immersive, scene boundaries, state ownership | `spatial-app-architecture` |
| Spatial SwiftUI — RealityView, Model3D, attachments, volumes, ImmersiveSpace, gestures | `spatial-swiftui-developer` |
| RealityKit (general) — scenes, entities/components, asset loading, anchoring, portals | `realitykit-visionos-developer` |
| RealityKit rendering — materials, lighting, cameras, effects, render cost | `realitykit-rendering-materials` |
| RealityKit animation & physics — skeletal/IK, particles, collisions, forces | `realitykit-animation-physics` |
| RealityKit spatial audio — 3D sound, ambient/channel audio, mix groups, reverb | `realitykit-audio-spatial` |
| RealityKit custom ECS — components, systems, per-frame multi-entity behavior | `realitykit-ecs-systems` |
| ARKit (router) — session, authorization, provider selection, anchors | `arkit-visionos-developer` |
| ARKit spatial tracking — world/plane/scene/room/shared-space providers | `arkit-spatial-tracking-providers` |
| ARKit hand tracking | `arkit-hand-tracking-provider` |
| ARKit reference tracking — image/object/barcode/accessory | `arkit-reference-tracking-providers` |
| ARKit rendering context — light estimation, stereo, visual fidelity | `arkit-rendering-context-providers` |
| ARKit camera access — frame/region providers | `arkit-camera-access-providers` |
| Shaders / materials authoring — Reality Composer Pro Shader Graph | `shadergraph-editor` |
| USD hand-editing / pipeline (`.usda`) | `usd-editor` |
| USD runtime editing in Swift (USDKit) | `usdkit-runtime-developer` |
| SharePlay / GroupActivities | `shareplay-developer` |
| WidgetKit for visionOS | `visionos-widgetkit-developer` |
| Immersive / spatial video | `visionos-immersive-media-developer` |
| 3D data visualization — Chart3D / Swift Charts 3D | `swiftui-chart3d-developer` |
| Swift code review / standards | `coding-standards-enforcer` |
| Authoring or updating skills | `tkr-skill-writer` |

## Notes

- Prefer SwiftUI + documented RealityKit components; reach for custom ECS `System`s only when documented components can't express the needed state/behavior.
- Consult the `visionos-design-guidelines` skill (Apple HIG for Vision Pro) for design decisions.
- Skills vendored from [tomkrikorian/visionOSAgents](https://github.com/tomkrikorian/visionOSAgents) (MIT); the pristine source is tracked as the `upstream/` submodule.
