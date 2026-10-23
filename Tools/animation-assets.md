# Animation assets

## Movie loading

Input: user-supplied `logo2.png`, copied unchanged into `MovieLogo.imageset`.
Output: `AnyAnime/Resources/MovieLoading.gif` (320 × 320, 48 frames, 2-second loop).
Generated with the imagegen tool using the input logo as an edit reference.

Prompt specification: produce an eight-frame sprite sheet, four columns by two rows;
preserve the exact character, logo lettering and centered scale in every frame;
use a black background and advance subtle neon orbit/glint highlights through eight
phases; do not redesign the logo or add text. The generated sheet was visually inspected.

The sheet was converted with FFmpeg: scale to 1792 × 896, `untile=4x2`, duplicate
the cycle, scale to 320 × 320, set timestamps at 4 fps, blend to 24 fps, trim to two
seconds, then palettegen/paletteuse (Bayer dithering). The generated spritesheet is
an intermediate asset, not required at runtime. Loading uses screen blending on a dark
background and a static frame for Reduce Motion. Movie playback loading is unchanged.

## Native transitions and icons

`LibraryTransition.swift`: launch logo merge and library-switch tile burst, 60 Hz
TimelineView; no network dependency. Reduce Motion uses a short crossfade.

`Tools/morphicons/generate.mjs` uses Morphicons 2.0.0 resampling, morph planning,
polar interpolation and spring easing. Run `npm ci --prefix Tools/morphicons`, then
`npm run --prefix Tools/morphicons generate` to regenerate `Resources/Morphicons.json`.
`MorphIcon.swift` renders those paths with CAShapeLayer, preserving the presentation
path when an animation is interrupted. MIT license is bundled with the resources.
