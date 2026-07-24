# Limitations

`tarlib` handles tar records directly. It does not currently include these
features:

- Built-in compression wrappers for `.tar.gz`, `.tar.bz2`, `.tar.xz`, or
  `.tar.zst`.
- Automatic multi-volume archive splitting.
- Filesystem extraction that preserves sparse holes with seek or punch-hole
  operations. Sparse reads reconstruct logical zero bytes.
- Native ACL/file-flag validation on every platform. Native application depends
  on host commands and filesystem support.
- Native BSD/Solaris device-node validation in CI. Device number layouts are
  selectable, but platform behavior must be verified on those systems.
- Unbounded metadata retention. PAX records, sparse extents, incremental dump
  records, and vendor records have explicit public limits.
- Full preservation of every vendor-specific tar extension.

The simple filesystem extraction overload is conservative: it extracts regular
files and directories and rejects links, devices, and FIFOs. Use
`Extraction_Options` only when the calling application has chosen a policy for
those entries.
