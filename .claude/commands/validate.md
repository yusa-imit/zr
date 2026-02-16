Validate the zr configuration file (zr.toml).

Steps:
1. Check if `zr.toml` exists in the current directory or project root
2. If not found, report error with hint to run `zr init`
3. If found, parse the TOML file and validate against the schema:
   a. Check required fields (tasks must have `cmd` or `deps`)
   b. Validate task names (no spaces, valid identifiers)
   c. Check dependency references (all deps must exist)
   d. Validate expressions in `condition` fields (syntax only)
   e. Check for circular dependencies in the DAG
   f. Validate timeout/duration formats
   g. Validate environment variable references
4. Report results:
   - If valid: "✓ Configuration valid: N tasks, M workflows defined"
   - If errors: List each error with file:line and actionable hint

Optional: $ARGUMENTS
- If user says "strict", also warn about unused tasks and missing descriptions
- If user says "schema", output the full schema reference
