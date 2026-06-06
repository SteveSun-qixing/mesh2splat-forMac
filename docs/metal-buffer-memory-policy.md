# Metal Buffer Memory Policy

`MetalBuffer` keeps the existing allocation entry points stable while recording the
memory policy chosen by each one:

| Entry point | Policy | Storage mode | CPU cache mode | Intended path |
| --- | --- | --- | --- | --- |
| `createShared` | `Shared` | `shared` | `default-cache` | CPU reads or CPU/GPU bidirectional staging where readback is expected. |
| `createSharedWriteCombined` | `SharedWriteCombined` | `shared` | `write-combined` | Apple Silicon frame or upload data that the CPU writes and does not read back. |
| `createPrivate` | `Private` | `private` | `default-cache` | GPU-only transient or persistent buffers. CPU `update` and `read` are rejected. |
| `createPrivateWithData` | `Private` | `private` | `default-cache` | GPU-only buffers initialized through a shared staging upload. |

On Apple Silicon, shared buffers use unified memory and are CPU accessible, but
write-combined memory should still be treated as write-only from the CPU side
because CPU reads can be slow. Private buffers stay non-CPU-accessible and must be
initialized or modified through Metal commands.

Use `memoryDiagnostics()` for structured inspection of policy, storage/cache mode,
label, size, CPU accessibility, and unified-memory device status. Use
`memoryDescription()` for one-line diagnostics in logs.
