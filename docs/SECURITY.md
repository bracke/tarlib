# Extraction and Security Policy

Archive extraction is security-sensitive. `tarlib` validates archive paths and
requires opt-in flags for behavior that can affect the host filesystem outside
ordinary file creation.

## Path Safety

Archive paths must be relative. Absolute paths, parent-directory traversal, and
empty PAX path metadata are rejected. Hard-link targets must also be
archive-relative. This prevents entries from naming files outside the requested
destination tree through normal path fields.

Symbolic-link targets are preserved as archive metadata. Applications should
decide whether symbolic links are acceptable for their threat model before
enabling link extraction.

## Extraction Options

The default `Extract_All` overload extracts regular files and directories.
Entries such as links, devices, and FIFOs are rejected.

`Extraction_Options` controls broader behavior:

- `Unsupported_Entries` can reject or skip unsupported entries.
- `Apply_Permissions` applies POSIX mode bits.
- `Apply_Timestamps` applies access and modification times.
- `Apply_Ownership` applies UID/GID ownership.
- `Create_Special_Entries` enables FIFOs and device nodes.
- `Extract_GNU_Metadata` materializes GNU metadata entries.
- `Apply_Extended_Attributes` applies Linux xattrs.
- `Apply_ACLs` and `Apply_File_Flags` materialize metadata sidecar files.
- `Apply_Native_ACLs` and `Apply_Native_File_Flags` invoke native host tools.

Ownership, device nodes, ACLs, file flags, and xattrs can require elevated
privileges or filesystem support. Treat these options as trusted-archive
features.

## Failure Behavior

Malformed archives, invalid metadata, short input, checksum mismatches, and
unsupported required variants return explicit error statuses. After a fatal
reader error, the reader enters `Failed` and subsequent read/skip operations
report input failure.
