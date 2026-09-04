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
  -- Runtime properties of the underlying shared resource.
  memType: one MemType,
  mapped: set Peer,
  canRead: set Peer,
  canWrite: set Peer,
  canExec: set Peer
}

-- One policy's local description of an underlying memory channel.
sig MemChannelSpec {
  channel: one MemChannel,
  memType: one MemType,
  mapped: set Peer,
  canRead: set Peer,
  canWrite: set Peer,
  canExec: set Peer
}

sig Policy {
  -- Peers named by this policy.
  peers: set Peer,

  -- Policy-local descriptions of memory channels.
  memChannels: set MemChannelSpec,

  -- Control-flow transition channels described by this policy.
  transitions: set TransitionChannel
}

pred active[ch: MemChannel] {
  #ch.mapped > 1
}

pred permits[p: Policy, ch: MemChannel, peer: Peer] {
  some spec: p.memChannels |
    spec.channel = ch and peer in spec.mapped
}

fun memoryFlow: Peer -> (Peer + Host) {
  { src, dst: Peer |
    some ch: MemChannel |
      src in ch.canWrite and
      dst in ch.canRead and
      src + dst in ch.mapped
  }
  +
  { src: Peer, h: Host |
    some ch: MemChannel |
      ch.memType = Unprotected and
      src in ch.canWrite and
      src in ch.mapped
  }
}

fun peerFlow: Peer -> Peer {
  memoryFlow :> Peer
}

fact PolicyShape {
  all p: Policy {
    -- Memory channel specifications can only map peers named by the policy.
    -- I will probably revisit that with any
    p.memChannels.mapped in p.peers
  }
}

fact MemoryAccessRequiresMapping {
  all ch: MemChannel |
    ch.canRead + ch.canWrite + ch.canExec in ch.mapped
}

fact ExplicitActiveSharing {
  -- Every peer on an active memory channel must be admitted by every other
  -- policy that names a participant.
  -- marios: I don't fully understand that. I need to revisit
  all ch: MemChannel |
    active[ch] implies all policy: Policy, observer, participant: ch.mapped |
      observer in policy.peers implies permits[policy, ch, participant]
}

fact GatewayMatchesUnprotectedMemory {
  -- A peer is a gateway exactly when it maps unprotected memory.
  all p: Peer |
    p in Gateway iff some ch: MemChannel |
      ch.memType = Unprotected and p in ch.mapped
}

assert ActiveMemorySharingIsMutuallyAuthorized {
  all ch: MemChannel |
    active[ch] implies all policy: Policy, observer, participant: ch.mapped |
      observer in policy.peers implies permits[policy, ch, participant]
}

assert HostReachabilityRequiresGatewayOnPath {
  all src: Peer |
    Host in src.^memoryFlow implies
      some (src.*peerFlow & Gateway)
}

pred protectedPipelineExample {
  #Peer = 3
  #MemChannel = 2

  some disj a, b, c: Peer, ab, bc: MemChannel {
    ab.memType = Protected
    ab.mapped = a + b
    ab.canWrite = a
    ab.canRead = b

    bc.memType = Protected
    bc.mapped = b + c
    bc.canWrite = b
    bc.canRead = c

    no Gateway
    Host not in a.^memoryFlow
  }
}

pred gatewayMemoryExample {
  #Peer = 2

  some disj source, gatewayPeer: Peer, internal, egress: MemChannel {
    internal.memType = Protected
    internal.mapped = source + gatewayPeer
    internal.canWrite = source
    internal.canRead = gatewayPeer

    egress.memType = Unprotected
    egress.mapped = gatewayPeer
    egress.canWrite = gatewayPeer

    Host in source.^memoryFlow
  }
}

pred unauthorizedActiveMemoryRejected {
  #Peer = 2

  some disj a, b: Peer, ch: MemChannel {
    ch.memType = Protected
    ch.mapped = a + b
    ch.canWrite = a
    ch.canRead = b

    some policy: Policy |
      a in policy.peers and
      no spec: policy.memChannels | spec.channel = ch
  }
}

pred hiddenGatewayMemoryRejected {
  some p: Peer, ch: MemChannel {
    ch.memType = Unprotected
    ch.mapped = p

    p not in Gateway
  }
}

check ActiveMemorySharingIsMutuallyAuthorized for 5
check HostReachabilityRequiresGatewayOnPath for 5

run protectedPipelineExample for 5
run gatewayMemoryExample for 5
run unauthorizedActiveMemoryRejected for 5
run hiddenGatewayMemoryRejected for 5
