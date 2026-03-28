# Task Completion Checklist

Before committing any change:

1. **`just test 2>&1 | tee /tmp/ksh-test.log`** — darwin must pass (112/112)
2. **`just test linux 2>&1 | tee /tmp/ksh-test-linux.log`** — linux must build, results reported
3. **Read the log** — use Read tool on /tmp/*.log, never re-run to check results
4. **No hardcoded values** — counts, paths, thresholds computed at runtime
5. **Probe stderr** — delegate probes use probe_run(), primitives use /dev/null
6. **Test infrastructure errors** — captured in test log (exec redirect), missing tests detected (pass+fail != stamp_count)
7. **Commit message** — prefixed (fix:/refactor:/etc.), explains why
8. **Force push only with explicit ask** — never push to main without Lane's approval
