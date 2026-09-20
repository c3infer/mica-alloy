# Mica Alloy Model

This repository contains an Alloy model for the Mica policy design from
"Sharing is caring: Attestable and Trusted Workflows out of Distrustful
Components" (arXiv:2603.03403v2, 7 March 2026).

The current validation and information-flow model focuses on memory channels.
It includes the vocabulary for control-flow transition channels, but their
validation semantics are still deferred.

The current vocabulary uses:

- `Peer` for a collocated TEE component;
- `MemChannel` for the identity and intrinsic type of a memory channel;
- `MemChannelSpec` for a policy-local description of channel access;
- `AnyMapping` for bounded or unlimited access by unnamed peers;
- `TransitionChannel` for calls and exceptions to the host;
- `Policy` for one policy in the combined policy set.

Memory-channel specifications support Mica's `ANY` and `count` semantics.
Strictness is policy-relative: a policy may require a named peer's complete set
of accessible memory channels to be described.

## Files

- `models/mica/core.als`: signatures and fields, with no global facts.
- `models/mica/relations.als`: derived relations and helper predicates.
- `models/mica/constraints.als`: optional named constraint predicates and the
  composed `valid` predicate.
- `models/mica/model.als`: fully constrained model; activates `valid` as a fact.
- `checks/`: assertions grouped by concern.
- `examples/`: satisfiable scenarios and their `run` commands.
- `docs/README.md`: detailed explanation of the model and project layout.

## Run

```sh
alloy exec -f -t text -o /tmp/mica-confidentiality -c '*' checks/confidentiality.als
alloy exec -f -t text -o /tmp/mica-structure -c '*' checks/structure.als
alloy exec -f -t text -o /tmp/mica-examples -c '*' examples/pipelines.als
```

Expected results:

```text
check HostReachabilityRequiresGatewayOnPath        UNSAT
check ProtectedChannelsDoNotFlowDirectlyToHost     UNSAT
check AtMostOneSpecPerPolicyAndChannel              UNSAT
run   protectedPipelineExample                     SAT
run   gatewayMemoryExample                         SAT
```

`UNSAT` is the expected result for an Alloy `check`: it means no counterexample
was found within the selected scope. `SAT` for a `run` command means Alloy found
an instance of the requested example.

To test an individual constraint without activating the complete model, open
`core`, `relations`, and `constraints`, then use the relevant predicate in the
assertion or scenario. Open `model` when every constraint in `valid` should be
enforced.
