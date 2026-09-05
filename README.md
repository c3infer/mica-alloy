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

- `models/mica.als`: Alloy signatures, facts, assertions, and examples.
- `docs/README.md`: explanation of the memory-only model and properties.

## Run

```sh
alloy exec -f -t text -o /tmp/mica-alloy-out -c '*' models/mica.als
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
