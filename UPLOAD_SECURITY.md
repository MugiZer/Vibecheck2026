# Upload security properties

The upload path accepts a user's Lean specification and optional supporting proofs. The user controls file contents, filenames, and request timing. The user also controls Lean commands in the submitted source. File validation and proof checking address different risks: a safe filename does not make Lean source safe to execute.

These are proposed properties for the upload implementation. They are not yet proved. The implementation must use the verified Lean functions directly; proofs about a separate copy do not establish how the application behaves.

## Admission properties

1. **Only expected files are accepted.** An accepted request contains exactly one Lean source file. It contains no additional file, directory entry, symbolic link, archive entry, or executable. The implementation chooses the destination filename rather than joining an uploaded filename to a directory.
2. **Accepted contents are bounded.** The accepted source is no larger than its configured byte limit. The server enforces a streaming limit before accumulating an unbounded request; checking a declared content length alone is insufficient.
3. **Rejected requests do not become jobs.** A request missing a required file, exceeding a limit, or containing an unexpected or duplicate entry produces a rejection and no runnable job. A partially received upload is never considered accepted.
4. **Each job is bound to its own input.** Once accepted, the job uses a fixed snapshot of those exact contents. Subsequent uploads or candidate repairs cannot change the requirement used by the verifier. Acceptance evidence identifies the template, specification and generated candidate together.

Formally verify two properties: the destination is server-controlled regardless of the uploaded filename, and the streaming code accepts no more than the per-upload limit. Define readable Lean propositions about the actual functions, prove them without extra axioms, and provide concrete accepted examples and counterexamples that the specifications reject. Include at least `../UserSpec.lean`, an absolute path, oversized content, and a chunk that crosses the limit. Test the production HTTP and file-writing path too: a theorem about a pure function alone does not prove the transport or operating system calls use it correctly. Enforce and test the other admission controls as well.

## Isolation properties

Uploaded Lean can execute commands during elaboration. Build it only inside the Linux verifier's sandbox, with no model credentials, no writable template or challenge, and no network during the upload build. Pre-resolve pinned dependencies outside the upload job. Run the upload check before exposing a job to the generator, and run Comparator on the final proof against a challenge controlled by the coordinator.

The proof must identify its assumptions about the filesystem and sandbox. It cannot establish Linux kernel isolation or prove that credentials were absent merely by asserting those facts in a Lean model. Check those boundaries by executing the real worker with a deliberately hostile fixture that attempts to read a planted secret, modify the frozen challenge, and access the network. Check that a changed specification or candidate invalidates prior acceptance.

## Evidence before claiming verification

Build the actual Lean modules, inspect their warnings, audit the axioms of each main theorem, and run `lake check` and Comparator on Linux. Record the theorem statements and their transitive project definitions. Prove that the hypotheses can be met, and show that known-bad inputs fail the specs. Report separately which properties were proved about executable Lean code and which boundaries were exercised only through integration tests.
