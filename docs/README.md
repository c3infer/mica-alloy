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

A memory channel identity. It records only its intrinsic type. Its participants
and access permissions are derived as the unions of all specifications that
reference it.

`MemChannelSpec`

One policy's local description of a memory channel. It has:

- `channel`: the underlying runtime `MemChannel`;
- `canRead`, `canWrite`, `canExec`: access permissions;
- `anyMappings`: wildcard mappings for unnamed peers.

The peers mapped by a specification are derived as the union of its read,
write, and execute permission sets. Channel-wide mappings are the corresponding
union across all specifications that reference the channel.

`AnyMapping`

A policy-local `ANY` entry. It records a `count` and its associated memory
access right. A memory-channel specification may contain multiple
`ANY` entries with different access rights. A positive `count` bounds the
number of unnamed peers using that access right; `-1` means unlimited.

`Policy`

One policy in the combined policy set. It records:

- `peers`: peers named by the policy;
- `strictPeers`: named peers whose complete channel access must be described by
  the policy;
- `memChannels`: policy-local memory-channel specifications;
- `transitions`: transition channels described by the policy.

## Current Validation Rules

`PolicyShape`

Memory-channel specifications can only map peers named by their policy.
Peers marked strict must also be named by that policy.

`NoOrphans`

Every peer must be named by a policy, every memory channel must be referenced
by a policy-owned memory-channel specification, and every transition channel
must be listed by a policy. Every memory-channel specification and `ANY`
mapping must likewise be contained by a policy.

`StrictPeersHaveNoUnlistedChannels`

Every memory channel accessible to a peer marked strict by a policy must have a
memory-channel specification in that policy. Strictness is policy-relative: a
peer can be strict in one policy without being strict in another.

`MemorySpecificationShape`

Each memory-channel specification belongs to exactly one policy, and each
`ANY` entry belongs to exactly one specification. A specification has at most
one `ANY` entry for each access right. A policy has at most one specification
for each memory channel.

`AnyMappingCountShape`

An `ANY` count is either `-1`, meaning unlimited, or a positive integer.

`AnyMappingsCoverUnnamedPeers`

Runtime participants named by the policy must be mapped explicitly. Every
unnamed runtime participant must have at least one access right, and each of
its rights must be covered by an `ANY` entry in the specification.

`AnyMappingCounts`

For a bounded `ANY` entry, the number of unnamed runtime participants using
its access right cannot exceed its positive count. A peer with multiple rights
is counted once against each corresponding entry.

`GatewayMatchesUnprotectedMemory`

A peer is in `Gateway` exactly when it maps unprotected memory.

## Current Properties

The model checks that reaching the host through memory requires reaching a
gateway peer.

It also includes:

- a protected-only pipeline example that should be satisfiable;
- a gateway-memory example that should be satisfiable;
- a hidden-gateway scenario that should be unsatisfiable.

## Run

```sh
alloy exec -f -t text -o /tmp/mica-alloy-out -c '*' models/mica.als
```

Expected results:

```text
check HostReachabilityRequiresGatewayOnPath        UNSAT
run   protectedPipelineExample                     SAT
run   gatewayMemoryExample                         SAT
run   hiddenGatewayMemoryRejected                  UNSAT
```
