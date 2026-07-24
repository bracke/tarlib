# Tar Format Support

This matrix summarizes the intended public compatibility surface.

| Feature | Read | Write | Notes |
| --- | --- | --- | --- |
| POSIX USTAR regular files | Yes | Yes | Sequential streaming API. |
| Directories | Yes | Yes | Directory names are normalized with trailing slash policy. |
| Hard links | Yes | Yes | Hard-link targets must be archive-relative. |
| Symbolic links | Yes | Yes | Absolute symbolic-link targets are preserved. |
| Character/block devices | Yes | Yes | Device metadata is range checked. |
| FIFOs | Yes | Yes | Filesystem creation is opt-in. |
| POSIX PAX path/linkpath | Yes | Yes | Used for paths and link targets beyond USTAR field limits. |
| PAX size/time/uid/gid/uname/gname | Yes | Yes | Includes signed timestamps and signed-positive numeric input. |
| Global PAX metadata | Yes | No | Supported for common metadata keys. |
| Unknown local PAX records | Yes | Yes | Reader retains a bounded number; writer can inject records. |
| GNU long name/link | Yes | No | Writer uses PAX for long names/links. |
| Legacy V7 headers | Yes | No | Reader accepts common V7-style file, directory, and hard-link headers. |
| Old GNU magic headers | Yes | Partial | Writer emits old-GNU sparse headers. |
| Base-256 numeric fields | Yes | No | Reader supports positive GNU/star style fields. |
| Signed checksum headers | Yes | No | Reader accepts unsigned and historical signed checksums. |
| GNU PAX sparse | Yes | Yes | Holes are reconstructed as zero bytes while reading. |
| star PAX sparse | Yes | Yes | Repeated offset/length PAX records. |
| libarchive PAX sparse | Yes | Yes | Repeated offset/length PAX records. |
| old-GNU sparse | Yes | Yes | Includes extension sparse headers. |
| GNU multi-volume continuation entries | Yes | Yes | Reassembly helper validates continuation offsets. |
| GNU incremental dump entries | Yes | Yes | Reader parses a bounded directory listing. |
| GNU volume labels | Yes | Yes | Extraction can materialize labels when enabled. |
| xattrs via `SCHILY.xattr.*` | Yes | No direct capture | Extraction can apply Linux xattrs. |
| ACLs via `SCHILY.acl.*` | Yes | No direct capture | Extraction can materialize sidecars or apply native ACLs. |
| file flags via `LIBARCHIVE.fflags` | Yes | No direct capture | Extraction can materialize sidecars or apply native flags. |
| gzip/bzip2/xz/zstd compression | No | No | Wrap streams outside `tarlib`. |
| Automatic volume splitting | No | No | Manual `M` entries can be written. |

The implementation intentionally treats unsupported or malformed variants as
structured failures instead of attempting best-effort parsing.
