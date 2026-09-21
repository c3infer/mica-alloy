# Mica JSON to Alloy

This tool compiles one or more Mica JSON policy files into an Alloy module. The
generated module contains:

- named atoms for the concrete deployment;
- a `configuration` predicate encoding the JSON exactly;
- a `validConfiguration` predicate combining the configuration with `valid`;
- a `ConfigurationIsValid` assertion;
- `run` and `check` commands for all three.

It requires Python 3.10 or newer and has no third-party dependencies.

## Usage

```sh
python3 tools/mica-json-to-alloy/mica_json_to_alloy.py \
  tools/mica-json-to-alloy/examples/policy-p1.json \
  tools/mica-json-to-alloy/examples/policy-p2.json \
  -o generated/example.als \
  --module generated/example

alloy exec -f -t text -o /tmp/mica-generated -c '*' generated/example.als
```

Generate the module inside the repository so Alloy can resolve imports under
`models/`. The repository's `generated/` directory ignores generated `.als`
files by default.

Interpretation:

- `run configuration` should be `SAT`; otherwise the emitted concrete encoding
  is internally inconsistent.
- `run validConfiguration` is `SAT` only when the configuration satisfies the
  current Mica constraint predicates.
- `check ConfigurationIsValid` is `UNSAT` for a valid configuration and `SAT`
  when Alloy finds the concrete configuration as a counterexample to `valid`.

## Resolution conventions

Peer identifiers and memory-channel names are treated as deployment-global
across all input files. `SELF` in a mapping resolves through `Peers.Self`.

When files use different local names, pass a manifest:

```json
{
  "peers": {
    "policy-p1:localP2": "P2",
    "policy-p2:P2": "P2"
  },
  "channels": {
    "policy-p1:out": "PipelineChannel",
    "policy-p2:in": "PipelineChannel"
  },
  "policies": {
    "policy-p1": "P1Policy",
    "policy-p2": "P2Policy"
  }
}
```

Manifest keys may be either `file-stem:local-name` or unqualified local names.

## Current model coverage

The compiler models:

- peers and policy-relative `strict` values;
- declared gateway values;
- protected and unprotected memory channels;
- explicit `R`, `W`, and `X` mappings;
- `ANY` mappings and counts;
- transition channel owners, types, ranges, and actions.

The current Alloy model does not yet represent peer hashes, GPAs, channel sizes,
or transition validation semantics. Accepted but unmodeled JSON fields are
listed in a comment in the generated module.
