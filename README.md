# plezy-apk

Mirrors [Plezy](https://github.com/edde746/plezy) releases with the arm64-v8a APK attached, so [Obtainium](https://github.com/ImranR98/Obtainium) can track updates automatically.

Since Plezy v1.13.0, Android assets ship as architecture-specific `.tar.gz` tarballs rather than APK files. This repo re-publishes each new release with the APK extracted from the tarball.

## Obtainium Setup

Point Obtainium to this repository:

```
https://forgejo.patilla.es/patillacode/plezy-apk
```

New releases appear here within 24 hours of the upstream Plezy release.
