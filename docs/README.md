# Mica Alloy Model

This documents the current simplified Mica Alloy model.

For now, validation and information-flow semantics cover memory channels. The
model includes transition-channel signatures, but validation predicates for
those channels are still deferred.

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

## Current Constraint Predicates

`policyShape`

Memory-channel specifications can only map peers named by their policy.
Peers marked strict must also be named by that policy.

`noOrphans`

Every peer must be named by a policy, every memory channel must be referenced
by a policy-owned memory-channel specification, and every transition channel
must be listed by a policy. Every memory-channel specification and `ANY`
mapping must likewise be contained by a policy.

`strictPeersHaveNoUnlistedChannels`

Every memory channel accessible to a peer marked strict by a policy must have a
memory-channel specification in that policy. Strictness is policy-relative: a
peer can be strict in one policy without being strict in another.

`memorySpecificationShape`

Each memory-channel specification belongs to exactly one policy, and each
`ANY` entry belongs to exactly one specification. A specification has at most
one `ANY` entry for each access right. A policy has at most one specification
for each memory channel.

`anyMappingCountShape`

An `ANY` count is either `-1`, meaning unlimited, or a positive integer.

`anyMappingsCoverUnnamedPeers`

Runtime participants named by the policy must be mapped explicitly. Every
unnamed runtime participant must have at least one access right, and each of
its rights must be covered by an `ANY` entry in the specification.

`anyMappingCounts`

For a bounded `ANY` entry, the number of unnamed runtime participants using
its access right cannot exceed its positive count. A peer with multiple rights
is counted once against each corresponding entry.

`gatewayMatchesUnprotectedMemory`

A peer is in `Gateway` exactly when it maps unprotected memory.

`valid`

Composes all the predicates above into the current definition of a valid Mica
configuration. The predicate remains optional until a module invokes it.

## Project Structure

`models/mica/core.als`

Declares signatures and fields. It deliberately contains no facts, so focused
tests can start from the unconstrained vocabulary.

`models/mica/relations.als`

Defines derived relations such as `channelMapped`, `accessRights`,
`memoryFlow`, and `peerFlow`. These helpers calculate values but do not activate
the model's validation constraints.

`models/mica/constraints.als`

Defines every validation rule as a named predicate. The `valid` predicate
composes the complete set of current rules. Opening this module does not force
`valid`, which allows checks to activate individual constraints.

`models/mica/model.als`

Provides the fully constrained model by applying `valid` in the
`ValidMicaConfiguration` fact.

`checks/`

Contains assertions and `check` commands grouped by concern. These modules open
the fully constrained model.

`examples/`

Contains satisfiable scenarios and `run` commands.

## Current Properties

The active assertions check that:

- reaching the host through memory requires a gateway on the peer-flow path;
- a direct flow to the host is backed by an unprotected channel writable by the
  source peer;
- one policy cannot contain multiple specifications for the same memory
  channel.

The model also runs satisfiable examples of a protected pipeline and a gateway
pipeline.

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

For `check`, `UNSAT` means Alloy found no counterexample within the configured
scope. For `run`, `SAT` means Alloy found a matching instance.
