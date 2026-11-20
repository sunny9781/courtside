# Courtside's own code keeps its names (crash reports stay readable) but is optimised like the libraries (inlining,
# dead code removed), which makes the screens faster on low-power TVs.
-keep,allowoptimization class ca.sunny9781.courtside.** { *; }
-dontwarn org.slf4j.**
# The sound decoder is found by name when the player starts.
-keep class androidx.media3.decoder.ffmpeg.** { *; }
