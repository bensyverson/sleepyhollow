# SleepyGoldenTests

Golden-output tests for the `sleepy` CLI: every verb's default and `json`
formats, byte-stable. Populated by the verb-family leaves and the golden
e2e suite leaf (AHtSh); this target exists from the scaffold so suites land
in a consistent place. No placeholder tests — a test that is green during
red tests nothing.
