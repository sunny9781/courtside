# Courtside's own code is kept as is (it's small); the shrinking comes from the libraries and unused icons.
-keep class ca.sunny9781.courtside.** { *; }
-dontwarn org.slf4j.**
# The sound decoder is found by name when the player starts.
-keep class androidx.media3.decoder.ffmpeg.** { *; }
