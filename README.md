# tarlib

`tarlib` is an Ada library for deterministic POSIX tar archive processing.

## Scope

The project target is full tar support for both reading and writing archives.
The current implementation supports POSIX USTAR regular files, directories,
hard links, symbolic links, character devices, block devices, FIFOs, and
selected GNU/PAX variants:

- sequential archive writing through `Tarlib.Writers`
- sequential archive reading through `Tarlib.Readers`
- filesystem-backed stream adapters and portable regular-file/directory
  pack/extract helpers through `Tarlib.Files`
- recursive filesystem directory packing for ordinary files and directories
- extraction options for rejecting or skipping unsupported entry kinds
- optional POSIX mode-bit application during extraction
- POSIX filesystem extraction for symbolic links and hard links
- POSIX filesystem extraction for FIFOs and device nodes when enabled
- optional POSIX timestamp and ownership application during extraction
- opt-in filesystem materialization for GNU metadata entries: multi-volume
  payloads, incremental dump listings, and volume labels
- GNU multi-volume reassembly from newline-listed archive paths into one
  logical output file
- optional vendor metadata extraction for xattrs, ACL text, and file flags
- explicit reader lifecycle state and clean end-of-archive detection
- failed reader state is terminal after malformed archives or input failures
- caller-owned input and output stream abstractions
- deterministic metadata defaults for reproducible archives
- validation for USTAR paths, fixed-width fields, headers, checksums, content
  sizes, padding, and archive termination
- shared archive-relative path validation for USTAR and PAX metadata
- reader-side maximum USTAR prefix/name path reconstruction
- reader-side maximum USTAR link target reconstruction
- raw header construction rejects USTAR link targets over 100 bytes
- reader-side archive termination is recognized at the first zero block
- per-entry PAX `path` and `linkpath` records for entries whose names or link
  targets exceed USTAR field limits
- writer-side overlong hard-link and symbolic-link targets are encoded with
  PAX `linkpath`
- writer-side PAX `size`, `mtime`, `atime`, `ctime`, `uid`, `gid`, `uname`,
  and `gname` records for values exceeding USTAR field limits or metadata not
  represented by USTAR
- writer-side PAX metadata records for files, links, directories, devices, and
  FIFOs
- writer-side per-entry PAX records are combined into one extended header
- writer-side arbitrary local PAX extension record injection for the next entry
- writer-side overlarge PAX records are rejected before partial output
- writer-side invalid link and special-entry metadata is rejected before PAX
  output
- writer-side public generic entry creation supports files, directories, GNU
  multi-volume continuation entries, and GNU incremental dump entries
- writer-side sparse regular files through `Begin_Sparse_File`, with GNU PAX,
  star PAX, libarchive PAX, and old-GNU sparse header dialects
- writer-side hard-link targets must remain archive-relative before PAX output
- writer-side link targets reject embedded NUL bytes before output
- writer-side device numbers are limited to character and block device entries
- failed writer state is terminal after output failures
- reader-side PAX numeric overrides for `size`, `mtime`, `atime`, `ctime`,
  `uid`, and `gid`
- reader-side USTAR and PAX `uname`/`gname` owner name metadata
- reader-side bounded retention of unknown local PAX records for callers that
  need vendor metadata such as xattrs or comments
- reader-side typed vendor PAX accessors for `SCHILY.xattr.*`,
  `SCHILY.acl.access`, `SCHILY.acl.default`, and `LIBARCHIVE.fflags`
- reader-side PAX `devmajor`, `devminor`, `SCHILY.devmajor`, and
  `SCHILY.devminor` device overrides, range-checked and limited to
  character/block device entries
- reader-side signed-positive PAX numeric values are accepted
- reader-side signed PAX `mtime`, `atime`, and `ctime` timestamps, including
  negative pre-epoch values
- reader-side malformed PAX record lengths are rejected without exceptions
- reader-side empty PAX keywords are rejected as malformed records
- reader-side PAX `size` overrides are applied to regular-file and hard-link
  data entries
- reader-side PAX `size` overrides are ignored for directories, symbolic links,
  device entries, and FIFOs
- reader-side empty PAX `path` and `linkpath` records are rejected
- reader-side PAX `path` records must remain archive-relative
- reader-side raw and extended hard-link targets must remain archive-relative
- reader-side hard-link PAX `linkpath` records must remain archive-relative
- reader-side PAX and GNU long link records reject embedded NUL bytes
- reader-side PAX and GNU long link records must target link entries
- reader-side PAX `linkpath` records may supply otherwise empty link header
  targets
- reader-side fractional PAX `mtime` values, stored as integer seconds
- reader-side global PAX metadata for `mtime`, `atime`, `ctime`, `uid`, `gid`,
  `uname`, and `gname`
- reader-side empty global PAX `mtime`, `atime`, `ctime`, `uid`, `gid`,
  `uname`, and `gname` values delete existing global metadata
- reader-side global PAX `path`, `linkpath`, `size`, `devmajor`, and `devminor`
  records are ignored without value validation
- reader-side dangling per-entry PAX and GNU long records are rejected
- reader-side GNU long name and long link records
- reader-side GNU long name records must remain archive-relative
- reader-side hard-link GNU long link records must remain archive-relative
- reader-side hard-link entries with link data blocks are accepted and skipped
- reader-side legacy V7-style file, directory, and hard-link headers without
  USTAR magic
- reader-side old GNU magic/version headers without POSIX USTAR prefix handling
- reader-side historical contiguous-file typeflag entries as regular files
- reader-side GNU volume label entries
- reader-side and writer-side GNU multi-volume continuation (`M`) and
  incremental dump directory (`D`) data entries
- reader-side and writer-side GNU volume label (`V`) entries
- reader-side GNU multi-volume continuation offset metadata from old-GNU
  headers and PAX `GNU.volume.offset`
- reader-side bounded GNU incremental dump directory listing parsing
- reader-side positive base-256 size and metadata fields used by GNU/star tar
  variants
- reader-side oversized base-256 numeric fields are rejected deterministically
- reader-side unsigned and historical signed header checksum validation
- PAX extended-header payloads up to 64 KiB
- reader-side GNU sparse PAX and old-GNU in-header map reconstruction with
  zero-filled holes
- reader-side star/libarchive sparse PAX reconstruction through repeated
  offset/length records
- reader-side old-GNU sparse extension-header maps
- reader-side un-mapped GNU sparse headers and unsupported sparse PAX variants
  are rejected deterministically
- POSIX device node creation supports selectable Linux, BSD, and Solaris
  major/minor `dev_t` layouts when special-entry extraction is enabled
- Linux xattrs can be applied with `setxattr`; ACL and file-flag metadata can
  be materialized as deterministic sidecar metadata or applied through native
  `setfacl`/`chattr` extraction options
- reader corpus coverage includes archives emitted by locally available
  external tar tools such as GNU tar and BusyBox tar
- deterministic fuzz-corpus coverage mutates valid archives and exercises
  malformed/truncated header, payload, PAX, and sparse-map cases without
  requiring external fuzzing tools

## Tests

Run the library and AUnit test suite with:

```sh
alr build
alr test
```

Maintainer checks use the `project_tools`-based guard:

```sh
cd check_tarlib
alr build
./bin/check_tarlib
```
