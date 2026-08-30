# Climb3D GPX → 3D → STL Prototype

This is the corrected prototype architecture.

Workflow:
1. Import GPX.
2. The app itself generates the 3D mesh.
3. The generated mesh is displayed immediately in SceneKit.
4. The progress slider moves a red marker along the generated 3D route.
5. The same generated mesh can be exported as binary STL.

No external GPXtruder step is required.

The 3D module is isolated so it can later be integrated into RideClimb.
RideClimb will replace the manual slider with:
progress = distanceM / route.totalDistanceM
