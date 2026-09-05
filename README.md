# Mica Alloy Model

This repository contains an Alloy model for the Mica policy design from
"Sharing is caring: Attestable and Trusted Workflows out of Distrustful
Components" (arXiv:2603.03403v2, 7 March 2026).

The current model is intentionally narrow: it covers only memory channels.
Control-flow transition channels are deferred.

The current vocabulary uses:

- `Peer` for a collocated TEE component;
- `MemChannel` for protected or unprotected memory channels;
- `Policy` for one policy in the combined policy set.

## Files

- `models/mica.als`: Alloy signatures, facts, assertions, and examples.
- `docs/README.md`: explanation of the memory-only model and properties.

## Run

```sh
alloy exec -f -t text -o /tmp/mica-alloy-out -c '*' models/mica.als
```

Expected result: the `check` command passes, the two positive examples are
`SAT`, and the `*Rejected` run is `UNSAT`.
