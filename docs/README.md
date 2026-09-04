# Memory-Only Mica Alloy Model

This documents the current simplified model in `models/mica.als`.

For now, the model covers only memory channels. Control-flow transition channels
are intentionally ignored and should be added later as a separate step.

## Current Alloy Vocabulary

`Peer`

A collocated TEE component.

`Gateway`

A subset of `Peer`. A peer is in `Gateway` exactly when it maps unprotected
memory.

`Host`

The untrusted host. Data reaches `Host` only through writable unprotected memory
in this simplified model.

`MemChannel`

A runtime memory channel. It records the actual channel type, mappings, and
access permissions.

`MemChannelSpec`

One policy's local description of a memory channel. It has:

- `channel`: the underlying runtime `MemChannel`;
- `memType`: `Protected` or `Unprotected`;
- `mapped`: peers with a mapping;
- `canRead`, `canWrite`, `canExec`: access permissions.

`Policy`

One policy in the combined policy set. It records:

- `peers`: peers named by the policy;
- `memChannels`: policy-local memory-channel specifications;
- `transitions`: transition channels described by the policy.

## Current Validation Rules

`PolicyShape`

Memory-channel specifications can only map peers named by their policy.

`MemoryAccessRequiresMapping`

A peer can read, write, or execute a memory channel only if it is mapped there.

`ExplicitActiveSharing`

If a memory channel is active, meaning more than one peer maps it, every
participant must be permitted by every combined policy that names any
participant.

`GatewayMatchesUnprotectedMemory`

A peer is in `Gateway` exactly when it maps unprotected memory.

## Current Properties

The model checks:

- active memory sharing is mutually authorized;
- reaching the host through memory requires reaching a gateway peer.

It also includes:

- a protected-only pipeline example that should be satisfiable;
- a gateway-memory example that should be satisfiable;
- two rejected loophole scenarios that should be unsatisfiable.

## Run

```sh
alloy exec -f -t text -o /tmp/mica-alloy-out -c '*' models/mica.als
```

Expected results:

```text
check ActiveMemorySharingIsMutuallyAuthorized      UNSAT
check HostReachabilityRequiresGatewayOnPath        UNSAT
run   protectedPipelineExample                     SAT
run   gatewayMemoryExample                         SAT
run   unauthorizedActiveMemoryRejected             UNSAT
run   hiddenGatewayMemoryRejected                  UNSAT
```
