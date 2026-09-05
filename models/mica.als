module models/mica

sig Peer {}

sig Gateway in Peer {}

one sig Host {}

abstract sig MemType {}
one sig Protected, Unprotected extends MemType {}

-- A transition channel governs a class of control-flow transitions from a
-- peer to the untrusted host.
abstract sig TransitionType {}
one sig Call, Exception extends TransitionType {}

-- Platform-specific identifiers for individual calls or exceptions.
sig TransitionID {}

-- The action Mica applies when a covered transition occurs.
abstract sig TransitionAction {}
one sig Allow, Scrub, Block extends TransitionAction {}

sig TransitionChannel {
  owner: one Peer,
  transitionType: one TransitionType,
  -- This is probably not necessary. I could remove if it increases
  -- the model checking time too much
  range: some TransitionID,
  action: one TransitionAction
}

sig MemChannel {
  -- The memory type is intrinsic to the underlying shared resource.
  -- Other systems check that all peers map a channel with the same visibility
  memType: one MemType
}

abstract sig MemAccessRight {}
one sig ReadAccess, WriteAccess, ExecAccess extends MemAccessRight {}

-- A policy's ANY entry for a memory channel.
sig AnyMapping {
  count: one Int,
  access: one MemAccessRight
}

-- One policy's local description of an underlying memory channel.
sig MemChannelSpec {
  channel: one MemChannel,
  canRead: set Peer,
  canWrite: set Peer,
  canExec: set Peer,
  anyMappings: set AnyMapping
}

sig Policy {
  -- Peers named by this policy.
  peers: set Peer,

  -- Named peers whose complete channel access must be described here.
  strictPeers: set Peer,

  -- Policy-local descriptions of memory channels.
  memChannels: set MemChannelSpec,

  -- Control-flow transition channels described by this policy.
  -- FIXME: We need some facts about those as well!
  transitions: set TransitionChannel
}

fun channelSpecs[ch: MemChannel]: set MemChannelSpec {
  ch.~channel
}

fun specMapped[spec: MemChannelSpec]: set Peer {
  spec.canRead + spec.canWrite + spec.canExec
}

fun channelMapped[ch: MemChannel]: set Peer {
  let specs = channelSpecs[ch] |
    specs.canRead + specs.canWrite + specs.canExec
}

fun channelCanRead[ch: MemChannel]: set Peer {
  channelSpecs[ch].canRead
}

fun channelCanWrite[ch: MemChannel]: set Peer {
  channelSpecs[ch].canWrite
}

fun channelCanExec[ch: MemChannel]: set Peer {
  channelSpecs[ch].canExec
}

fun accessRights[ch: MemChannel, peer: Peer]: set MemAccessRight {
  { right: MemAccessRight |
    (right = ReadAccess and peer in channelCanRead[ch]) or
    (right = WriteAccess and peer in channelCanWrite[ch]) or
    (right = ExecAccess and peer in channelCanExec[ch])
  }
}

-- Finds the unnamed peers using a particular access right on a channel
fun anyUsers[
  policy: Policy,
  spec: MemChannelSpec,
  right: MemAccessRight
]: set Peer {
  { peer: channelMapped[spec.channel] - policy.peers |
    right in accessRights[spec.channel, peer]
  }
}

pred permits[p: Policy, ch: MemChannel, peer: Peer] {
  some spec: p.memChannels {
    spec.channel = ch

    peer in specMapped[spec] or {
      peer in channelMapped[ch] - p.peers
      some accessRights[ch, peer]
      accessRights[ch, peer] in spec.anyMappings.access
    }
  }
}

fun memoryFlow: Peer -> (Peer + Host) {
  { src, dst: Peer |
    some ch: MemChannel |
      src in channelCanWrite[ch] and
      dst in channelCanRead[ch] and
      src + dst in channelMapped[ch]
  }
  +
  { src: Peer, h: Host |
    some ch: MemChannel |
      ch.memType = Unprotected and
      src in channelCanWrite[ch] and
      src in channelMapped[ch]
  }
}

fun peerFlow: Peer -> Peer {
  memoryFlow :> Peer
}

fact PolicyShape {
  all p: Policy {
    -- Strictness is a property assigned to a peer named by this policy.
    p.strictPeers in p.peers

    -- Memory channel specifications can only map peers named by the policy.
    all spec: p.memChannels | specMapped[spec] in p.peers
  }
}

fact NoOrphans {
  -- Every modeled object is affiliated with at least one policy.
  Peer = Policy.peers
  MemChannel = Policy.memChannels.channel
  TransitionChannel = Policy.transitions
  MemChannelSpec = Policy.memChannels
  AnyMapping = Policy.memChannels.anyMappings
}

fact StrictPeersHaveNoUnlistedChannels {
  all policy: Policy, peer: policy.strictPeers, ch: MemChannel |
    peer in channelMapped[ch] implies
      some spec: policy.memChannels | spec.channel = ch
}

fact MemorySpecificationShape {
  -- Every MemChannelSpec belongs to exactly one policy
  all spec: MemChannelSpec |
    one policy: Policy | spec in policy.memChannels

  -- A policy has at most one specification for each memory channel
  all policy: Policy, ch: MemChannel |
    lone { spec: policy.memChannels | spec.channel = ch }

  -- AnyMapping belongs to exactly one MemChannelSpec
  all mapping: AnyMapping |
    one spec: MemChannelSpec | mapping in spec.anyMappings

  -- Any two distinct AnyMapping objects must cover different access rights
  all spec: MemChannelSpec, disj left, right: spec.anyMappings |
    left.access != right.access
}

fact AnyMappingCountShape {
  -- -1 means unlimited; every other valid count is positive.
  all mapping: AnyMapping |
    mapping.count = -1 or mapping.count > 0
}

fact AnyMappingsCoverUnnamedPeers {
  all policy: Policy, spec: policy.memChannels {
    -- Named runtime participants must be described explicitly. The remaining
    -- runtime participants consume ANY entries.
    specMapped[spec] = channelMapped[spec.channel] & policy.peers

    all peer: channelMapped[spec.channel] - policy.peers {
      some accessRights[spec.channel, peer]
      accessRights[spec.channel, peer] in spec.anyMappings.access
    }
  }
}

fact AnyMappingCounts {
  all policy: Policy,
      spec: policy.memChannels,
      mapping: spec.anyMappings |
    mapping.count = -1 or
      #anyUsers[policy, spec, mapping.access] <= mapping.count
}

fact GatewayMatchesUnprotectedMemory {
  -- A peer is a gateway exactly when it maps unprotected memory.
  all p: Peer |
    p in Gateway iff some ch: MemChannel |
      ch.memType = Unprotected and p in channelMapped[ch]
}

assert HostReachabilityRequiresGatewayOnPath {
  all src: Peer |
    Host in src.^memoryFlow implies
      some (src.*peerFlow & Gateway)
}

assert ProtectedChannelsDoNotFlowDirectlyToHost {
  all peer: Peer |
    Host in peer.memoryFlow implies
      some ch: MemChannel |
        ch.memType = Unprotected and
        peer in channelCanWrite[ch]
}

assert AtMostOneSpecPerPolicyAndChannel {
  all policy: Policy, ch: MemChannel |
    lone { spec: policy.memChannels | spec.channel = ch }
}

pred protectedPipelineExample {
  #Peer = 3
  #MemChannel = 2

  some disj a, b, c: Peer, ab, bc: MemChannel {
    ab.memType = Protected
    channelMapped[ab] = a + b
    channelCanWrite[ab] = a
    channelCanRead[ab] = b

    bc.memType = Protected
    channelMapped[bc] = b + c
    channelCanWrite[bc] = b
    channelCanRead[bc] = c

    no Gateway
    Host not in a.^memoryFlow
    c in a.^memoryFlow
  }
}

pred gatewayMemoryExample {
  #Peer = 2

  some disj source, gatewayPeer: Peer, internal, egress: MemChannel {
    internal.memType = Protected
    channelMapped[internal] = source + gatewayPeer
    channelCanWrite[internal] = source
    channelCanRead[internal] = gatewayPeer

    egress.memType = Unprotected
    channelMapped[egress] = gatewayPeer
    channelCanWrite[egress] = gatewayPeer

    Host in source.^memoryFlow
  }
}

check HostReachabilityRequiresGatewayOnPath for 5
check ProtectedChannelsDoNotFlowDirectlyToHost for 5
check AtMostOneSpecPerPolicyAndChannel for 5

run protectedPipelineExample for 5
run gatewayMemoryExample for 5
