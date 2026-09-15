# Contributing

Keep the interface limited to workspace selection and date/time. Do not add
mouse gestures or background polling without a clear user requirement.

Use Win32 APIs and keep the process count at one. Measure both resident working
set and private committed memory; never reduce apparent memory by periodically
trimming the working set. Document the workload and avoid guarantees based on
one idle snapshot.

Build with CMake and run CTest before proposing a change. Installer changes need
tests proving that unrelated settings survive, unsupported input is rejected
before mutation, and updates retain the first backup. Do not add private configs,
diagnostics, user paths, credentials or release binaries to Git.

Desktop tests change workspace focus and must be explicitly opted into. Keep
reboot/multi-monitor/long-run claims separate from what was actually tested.
