# Agent instructions — tarlib

Deterministic POSIX tar archive read/write library.

This crate pins its GNAT toolchain via Alire (`gnat_native = "=15.2.1"`). Build and test with `alr`, not
system GNAT / GPRBuild / GNATprove / GNATdoc tools on `PATH` — `alr exec -- gnatls --version` must report the pinned GNAT.

```sh
alr build
```
