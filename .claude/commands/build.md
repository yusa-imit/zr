Build the zr project.

Steps:
1. Run `zig build` in the project root
2. If build fails, analyze the error output
3. If the error is in our code, fix it and rebuild
4. If build succeeds, report success with binary location (`./zig-out/bin/zr`)

Optional flags from user input: $ARGUMENTS
- If user specifies a target (e.g., "linux"), cross-compile with `-Dtarget=x86_64-linux`
- If user says "release", add `-Doptimize=ReleaseSafe`
- If user says "clean", run `rm -rf zig-out .zig-cache` first
